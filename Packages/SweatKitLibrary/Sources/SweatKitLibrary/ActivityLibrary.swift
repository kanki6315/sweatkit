import Foundation
import SweatKitIdentity
import SweatKitAnalysis
import SweatKitModel
import SweatKitStore

/// The library as screens and sync see it: files go in, the feed and each
/// activity's streams and metrics come out, and whatever was derived is
/// kept in step with the profile and with the build's own rules.
///
/// It wraps a `LibraryStore` and joins it to Ingest and Analysis. Everything
/// that crosses the actor boundary is a `Sendable` value. Decoding, stream
/// building and metrics run on the concurrent executor, never on this actor
/// or the main actor, so the feed stays readable during a long import.
///
/// **What an import stores**, in this order: the original and its source
/// record, the decoded activity, the analysis stream, the feed row, and the
/// metrics as a derived result. The file is decoded before anything is
/// stored, so a rejected file leaves the library exactly as it was. The
/// metrics are written last and are the mark of a finished import: an
/// activity without them is rebuilt by the next recompute, or by importing
/// the same file again.
///
/// **Provenance.** Each metrics result records
/// `PipelineVersions.inputRevision(original:)`, the profile fingerprint for
/// the activity's start reading only the values its sport uses, and
/// `PipelineVersions.combinedAlgorithmVersion`. `recompute` asks the store
/// which results no longer match and rebuilds each from the cheapest stored
/// form that is still good.
///
/// **Calls that overlap.** The actor does its heavy work elsewhere, so two
/// calls can be in progress at once. Mutations take turns across the library
/// so grouping and revisions cannot overwrite one another. Beyond that, every write is a whole replacement derived from
/// stored inputs, and a result records what it was computed from. A result
/// written from a profile that was replaced meanwhile is therefore found
/// stale by the next recompute, not left wrong.
///
/// Identity resolves matching source records into activities, keeping user
/// decisions in an add-only journal and replacing the affected feed rows atomically.
public actor ActivityLibrary {
    /// The store underneath. Reading from it is safe. Write through the
    /// library, which keeps streams, rows and results in step.
    public nonisolated let store: LibraryStore
    /// The versions this library treats as current.
    public nonisolated let versions: PipelineVersions

    var cachedTrendsHistory: (revision: UInt64, history: TrendsHistory)?
    var trendsHistoryTask: (revision: UInt64, token: UUID, task: Task<TrendsHistory, Error>)?
    var routeCatalogCache: RouteCatalogCache?

    /// The kind of the derived result that holds an activity's
    /// `ActivityMetrics`.
    public static let metricsKind = "metrics"

    /// How many files or activities are worked on at once. Decoding is the
    /// slow step and uses one core each.
    public static let maximumConcurrentWork = 4

    /// An algorithm version no stored result has, because
    /// `combinedAlgorithmVersion` is never negative. Asking the store what
    /// is stale under it lists every stored result.
    private static let noSuchAlgorithmVersion = -1

    /// A library over an open store.
    public init(store: LibraryStore, versions: PipelineVersions = .current) {
        self.store = store
        self.versions = versions
    }

    /// Opens the library under `root`, creating it when it does not exist.
    public init(root: URL, versions: PipelineVersions = .current) throws(LibraryError) {
        do {
            self.store = try LibraryStore(root: root)
            try Self.separateLegacyHealthCandidates(root: root)
        } catch {
            throw LibraryError(error)
        }
        self.versions = versions
    }

    // MARK: The athlete profile

    /// The stored profile, or an empty one before any is saved.
    public func profile() async throws(LibraryError) -> AthleteProfile {
        do {
            return try await currentProfile()
        } catch {
            throw LibraryError(error)
        }
    }

    /// Saves the profile and reports the activities whose metrics it made
    /// stale, ordered by ID. Nothing is recomputed here: call `recompute`.
    ///
    /// A threshold power corrected for a range of dates stales only the
    /// rides that started in that range. Weight and units stale nothing.
    @discardableResult
    public func saveProfile(_ profile: AthleteProfile) async throws(LibraryError) -> [StaleActivity] {
        let token = SourceIdentity(source: .file, externalID: "profile-writer")
        await begin(token); defer { end(token) }
        do {
            try await store.saveProfile(profile)
            return try await scan(profile: profile, checkingStreamFiles: false)
        } catch {
            throw LibraryError(error)
        }
    }

    private func currentProfile() async throws -> AthleteProfile {
        try await store.profile() ?? AthleteProfile()
    }

    // MARK: Import

    /// Imports one FIT file.
    ///
    /// The bytes are decoded first. A file that is not FIT, is truncated or
    /// damaged, or holds no activity throws `.rejected` with Ingest's error,
    /// and one with no start or end throws `.noTimeSpan`; either way nothing
    /// is stored. Importing bytes that are already in the library returns
    /// `.alreadyInLibrary` without decoding or computing anything.
    ///
    /// - Parameters:
    ///   - bytes: The file, byte for byte. For a Garmin download it is the
    ///     file inside the zip: unzipping is the caller's work.
    ///   - identity: The source identity to import under, such as a Garmin
    ///     activity ID. Nil imports a plain file, whose identity is the hash
    ///     of its bytes. Different bytes under an existing identity are a
    ///     new revision of the same record, and its activity is rebuilt.
    ///   - fallbackUTCOffset: Seconds east of UTC to use when the file does
    ///     not state its own offset, as Zwift files do not. It decides the
    ///     time of day in the title. A sync that knows the local start time
    ///     from the source's summary passes it here.
    ///   - date: The time recorded as the import and computation time.
    @discardableResult
    public func importFile(
        _ bytes: Data,
        as identity: SourceIdentity? = nil,
        fallbackUTCOffset: Int? = nil,
        at date: Date = Date()
    ) async throws(LibraryError) -> ImportResult {
        do {
            return try await importBytes(bytes, as: identity, fallbackUTCOffset: fallbackUTCOffset, at: date)
        } catch {
            throw LibraryError(error)
        }
    }

    /// Imports a Health workout snapshot under its stable workout UUID.
    /// A changed route or sample set becomes a new revision of that source.
    @discardableResult
    public func importHealthSnapshot(_ snapshot: HealthSnapshot, at date: Date = Date()) async throws -> ImportResult {
        let result = try await importBytes(snapshot.encoded(), as: snapshot.identity,
            fallbackUTCOffset: snapshot.activity.stated.utcOffset, at: date)
        // Health data remains local even when device backups are enabled.
        let records = try await store.sourceRecord(snapshot.identity)
        if let revision = records?.currentRevision {
            for relative in ["Originals/\(revision.hex)", "Streams/\(revision.hex).analysis", "Streams/\(revision.hex).recorded"] {
                var url = store.root.appendingPathComponent(relative)
                if FileManager.default.fileExists(atPath: url.path) {
                    var values = URLResourceValues()
                    values.isExcludedFromBackup = true
                    try url.setResourceValues(values)
                }
            }
        }
        if let record = try await store.sourceRecord(snapshot.identity), record.state == .removedAtSource {
            try await store.setState(.active, for: snapshot.identity)
        }
        return result
    }

    /// A deletion reported explicitly by the source keeps the local recording.
    public func markHealthWorkoutRemoved(_ id: UUID) async throws {
        let identity = SourceIdentity(source: .healthKit, externalID: id.uuidString)
        if let record = try await store.sourceRecord(identity), record.state == .active {
            try await store.setState(.removedAtSource, for: identity)
        }
    }

    /// Imports several files. Each succeeds or fails on its own, and the
    /// outcomes come back in the order the files were given.
    ///
    /// Up to `maximumConcurrentWork` files are read at once; mutations serialize. `progress`
    /// is called as each file finishes, in the order they finish, from this
    /// actor and not from the main actor. If the calling task is cancelled,
    /// files not yet started fail with `.cancelled`.
    ///
    /// Reading a zip or a folder is not built. Unpack it first and pass the
    /// files inside. A zip passed as it is fails with `.rejected(.notFIT)`.
    public func importFiles(
        _ files: [ImportFile],
        at date: Date = Date(),
        progress: (@Sendable (ImportProgress) -> Void)? = nil
    ) async -> [ImportFileOutcome] {
        var outcomes: [ImportFileOutcome] = []
        await forEachBounded(files) { [self] index, file in
            await importOne(file, index: index, at: date)
        } onEach: { _, outcome in
            outcomes.append(outcome)
            progress?(ImportProgress(completed: outcomes.count, total: files.count, latest: outcome))
        }
        return outcomes.sorted { $0.index < $1.index }
    }

    private func importOne(_ file: ImportFile, index: Int, at date: Date) async -> ImportFileOutcome {
        let result: Result<ImportResult, LibraryError>
        do {
            try Task.checkCancellation()
            let bytes = try await Pipeline.read(file.contents)
            result = .success(try await importBytes(bytes, as: file.identity, fallbackUTCOffset: file.fallbackUTCOffset, at: date))
        } catch {
            result = .failure(LibraryError(error))
        }
        return ImportFileOutcome(index: index, name: file.name, result: result)
    }

    func importBytes(
        _ bytes: Data,
        as identity: SourceIdentity?,
        fallbackUTCOffset: Int?,
        at date: Date,
        alreadyLocked: Bool = false
    ) async throws -> ImportResult {
        let hash = ContentHash(of: bytes)
        let identity = identity ?? SourceIdentity(source: .file, externalID: hash.hex)

        // One import of an identity at a time, so the same file twice in one
        // batch is added once and found already there once.
        if !alreadyLocked { await begin(identity) }
        defer { if !alreadyLocked { end(identity) } }

        if identityNeedsRecovery && FileManager.default.fileExists(atPath: identityURL.path) { try await reconcileIdentity() }

        if try deletedIdentities().contains(identity) { throw LibraryError.permanentlyDeleted(identity) }

        // Already imported: nothing to decode, store or compute.
        if let activity = try await finishedActivity(of: identity, holding: hash) {
            if !FileManager.default.fileExists(atPath: identityURL.path) { try await reconcileIdentity() }
            let resolved = try await activityContaining(identity)
            return ImportResult(change: .alreadyInLibrary, source: identity, activity: resolved ?? activity)
        }

        // Decode before anything is stored, so a rejected file leaves no trace.
        let profile = try await currentProfile()
        var decoded = try await Pipeline.decode(bytes, versions: versions, allowsSnapshot: identity.source == .healthKit)

        identityNeedsRecovery = true
        let record = try await store.importOriginal(bytes, as: identity, at: date).record
        if record.identity != identity {
            // A file whose bytes are already another source's original, such
            // as a Garmin download. It is that record, and adds nothing.
            if let activity = try await finishedActivity(of: record.identity, holding: record.currentRevision) {
                return ImportResult(change: .alreadyInLibrary, source: record.identity, activity: activity)
            }
            // That record's own import never finished. Finish it from its
            // current original, which these bytes may not be.
            if record.currentRevision != hash {
                decoded = try await Pipeline.decode(try await original(record.currentRevision), versions: versions, allowsSnapshot: record.source == .healthKit)
            }
        }

        let row = try await write(decoded, for: record, fallbackUTCOffset: fallbackUTCOffset, profile: profile, at: date)
        var journal = try readIdentityJournal()
        journal.candidates[record.identity.description] = MatchCandidate(identity: record.identity,
            sport: decoded.recorded.sport, start: decoded.stream.start,
            elapsed: Double(decoded.stream.count), distance: (0..<decoded.stream.count).reversed().lazy.compactMap { decoded.stream.distance[$0] }.first ?? decoded.recorded.stated.distance,
            isIndoor: decoded.recorded.isIndoor || decoded.recorded.isVirtual,
            linkedIdentities: (try HealthSnapshot.decode(bytes))?.linkedIdentities ?? [])
        try writeIdentityJournal(journal)
        try await reconcileIdentity()
        let resolvedID = try await store.sourceRecord(record.identity)?.activityID
        let resolvedRow: ActivityRecord?
        if let resolvedID { resolvedRow = try await store.activity(resolvedID) } else { resolvedRow = nil }
        return ImportResult(
            change: record.activityID == nil ? .added : .updated,
            source: record.identity,
            activity: resolvedRow ?? row
        )
    }

    /// The activity of the source record `identity`, when the record's
    /// current revision is `hash` and its import finished.
    private func finishedActivity(of identity: SourceIdentity, holding hash: ContentHash) async throws -> ActivityRecord? {
        guard let record = try await store.sourceRecord(identity),
              record.currentRevision == hash,
              let id = record.activityID,
              let activity = try await store.activity(id),
              try await store.derivedResult(owner: .activity(id), kind: Self.metricsKind) != nil
        else { return nil }
        return activity
    }

    /// Stores everything derived from `record`'s current revision and
    /// returns its activity's feed row.
    private func write(
        _ decoded: Pipeline.Decoded,
        for record: SourceRecord,
        fallbackUTCOffset: Int?,
        profile: AthleteProfile,
        at date: Date
    ) async throws -> ActivityRecord {
        let revision = record.currentRevision
        var existing: ActivityRecord?
        if let id = record.activityID {
            existing = try await store.activity(id)
        }
        try await store.saveRecordedActivity(decoded.recorded, decoderVersion: versions.decoder, for: revision)
        try await store.saveAnalysisStream(decoded.stream, for: revision)

        // Only an activity's primary member supplies its streams, so the row
        // and the metrics are not another member's to write. Merges are not
        // built, so today every record is its activity's primary.
        if let existing, existing.primary != record.identity {
            return existing
        }

        let derived = try await Pipeline.derive(
            facts: ActivityFacts(decoded.recorded, fallbackUTCOffset: fallbackUTCOffset ?? existing?.utcOffset),
            stream: decoded.stream,
            profile: profile,
            versions: versions,
            target: Pipeline.Target(
                members: existing?.members ?? [record.identity],
                primary: record.identity,
                revision: revision,
                existing: existing
            ),
            at: date,
            summaryOnly: decoded.recorded.stream.samples.isEmpty ? decoded.recorded.stated : nil,
            sourceDistance: record.source == .healthKit ? decoded.recorded.stated.distance : nil
        )
        // The row first and the metrics last: the metrics are the mark of a
        // finished write, and their absence is what a recompute looks for.
        try await store.saveActivity(derived.row)
        try await store.saveDerivedResult(derived.result)
        return derived.row
    }

    // MARK: Reading

    /// One page of the feed: visible activities matching `filter`, newest
    /// first. Pass the previous page's `next` to continue.
    public func feed(
        _ filter: FeedFilter = FeedFilter(),
        limit: Int,
        after cursor: FeedCursor? = nil
    ) async throws(LibraryError) -> FeedPage {
        do {
            if identityNeedsRecovery && FileManager.default.fileExists(atPath: identityURL.path) {
                let token = SourceIdentity(source: .file, externalID: "recovery")
                await begin(token)
                do { try await reconcileIdentity(); end(token) }
                catch { end(token); throw error }
            }
            return try await store.feed(filter, limit: limit, after: cursor)
        } catch {
            throw LibraryError(error)
        }
    }

    /// The activity with this ID, or nil when there is none.
    public func activity(_ id: SourceIdentity) async throws(LibraryError) -> ActivityRecord? {
        do {
            return try await store.activity(id)
        } catch {
            throw LibraryError(error)
        }
    }

    /// The stored metrics of an activity, or nil when none are stored or
    /// they were written in a form this build does not read. They may be
    /// stale: `staleActivities` says which are, and `recompute` renews them.
    public func metrics(for id: SourceIdentity) async throws(LibraryError) -> ActivityMetrics? {
        do {
            return try await store.derivedResult(owner: .activity(id), kind: Self.metricsKind)
                .flatMap { Pipeline.decodeMetrics($0.payload) }
        } catch {
            throw LibraryError(error)
        }
    }

    /// The analysis stream of an activity.
    ///
    /// A stream file that is missing, unreadable or built under other stream
    /// rules is built again, from the stored decoded activity or, failing
    /// that, from the original, and stored. The metrics are not touched:
    /// that is `recompute`'s work.
    public func analysisStream(for id: SourceIdentity) async throws(LibraryError) -> AnalysisStream {
        await begin(id)
        defer { end(id) }
        do {
            return try await materials(for: try await currentRevision(of: id), renormalise: false, needsRecorded: false).stream
        } catch {
            throw LibraryError(error)
        }
    }

    /// The decoded activity of an activity's primary source, with its laps,
    /// timer events and native samples. A missing, unreadable or outdated
    /// file is decoded again from the original and stored.
    public func recordedActivity(for id: SourceIdentity) async throws(LibraryError) -> RecordedActivity {
        await begin(id)
        defer { end(id) }
        do {
            let revision = try await currentRevision(of: id)
            let found = try await materials(for: revision, renormalise: false, needsRecorded: true)
            guard let recorded = found.recorded else { throw LibraryError.originalMissing(revision) }
            return recorded
        } catch {
            throw LibraryError(error)
        }
    }

    /// The current revision of an activity's primary member.
    private func currentRevision(of id: SourceIdentity) async throws -> ContentHash {
        guard let activity = try await store.activity(id),
              let record = try await store.sourceRecord(activity.primary)
        else { throw LibraryError.unknownActivity(id) }
        return record.currentRevision
    }

    private func original(_ revision: ContentHash) async throws -> Data {
        guard let bytes = try await store.original(revision) else {
            throw LibraryError.originalMissing(revision)
        }
        return bytes
    }

    // MARK: Staleness

    /// The activities whose stored metrics no longer match the stored
    /// profile, the current versions or their current original, ordered by ID.
    /// A source record that an interrupted import left without an activity
    /// is listed too, under its own identity, as not computed.
    ///
    /// With `checkingStreamFiles`, every activity's two stream files are
    /// read as well, and one that needs rebuilding is reported even when the
    /// metrics are still valid. That reads every file, so it is for a
    /// maintenance pass, not for every launch.
    public func staleActivities(checkingStreamFiles: Bool = false) async throws(LibraryError) -> [StaleActivity] {
        do {
            return try await scan(profile: try await currentProfile(), checkingStreamFiles: checkingStreamFiles)
        } catch {
            throw LibraryError(error)
        }
    }

    private func scan(profile: AthleteProfile, checkingStreamFiles: Bool) async throws -> [StaleActivity] {
        // Every activity, and the original its primary member reads now.
        let records = try await store.sourceRecords()
        let ids = Set(records.compactMap(\.activityID))
        let originals = try await store.activityInputRevisions()
        var activities: [ResultOwner: SourceIdentity] = [:]
        var inputRevisions: [ResultOwner: ContentHash] = [:]
        for id in ids {
            let owner = ResultOwner.activity(id)
            activities[owner] = id
            inputRevisions[owner] = originals[owner].map(versions.inputRevision(original:))
        }

        var reasons: [SourceIdentity: Set<StaleActivity.Reason>] = [:]
        let stale = try await store.staleResults(
            kind: Self.metricsKind,
            algorithmVersion: versions.combinedAlgorithmVersion,
            profile: profile,
            inputRevisions: inputRevisions
        )
        for result in stale {
            // A result whose owner is not an activity is not this pass's to rebuild.
            guard let id = activities[result.owner] else { continue }
            for reason in result.reasons {
                switch reason {
                case .algorithm: reasons[id, default: []].insert(.algorithm)
                case .input: reasons[id, default: []].insert(.input)
                case .profile: reasons[id, default: []].insert(.profile)
                }
            }
        }

        // An activity with no metrics at all is not in the store's list,
        // which holds only stored results.
        let computed = Set(try await store.staleResults(
            kind: Self.metricsKind,
            algorithmVersion: Self.noSuchAlgorithmVersion,
            profile: profile,
            inputRevisions: inputRevisions
        ).map(\.owner))
        for (owner, id) in activities where !computed.contains(owner) {
            reasons[id, default: []].insert(.notComputed)
        }
        // An import that stopped after storing its original left a source
        // record with no activity. It becomes its own activity, as it would
        // have, so it is listed under its own identity.
        for record in records where record.activityID == nil && record.state == .active {
            reasons[record.identity, default: []].insert(.notComputed)
        }

        if checkingStreamFiles {
            for (owner, id) in activities {
                guard let revision = originals[owner] else { continue }
                let analysis = await store.analysisStream(for: revision, rulesVersion: versions.streamRules)
                let recorded = await store.recordedActivity(for: revision, decoderVersion: versions.decoder)
                if analysis.value == nil || recorded.value == nil {
                    reasons[id, default: []].insert(.streamFile)
                }
            }
        }

        return reasons
            .map { StaleActivity(id: $0.key, reasons: $0.value) }
            .sorted { $0.id < $1.id }
    }

    // MARK: Recompute

    /// Finds the stale activities under the stored profile and rebuilds each
    /// one's metrics, and its feed row when the row's values change.
    ///
    /// Each rebuild starts from the cheapest stored form that is still good:
    ///
    /// - The stored analysis stream, when only the profile or an algorithm
    ///   changed. Nothing is decoded and no stream is built.
    /// - The stored decoded activity, when the stream rules changed or the
    ///   analysis stream file needs rebuilding. The stream is built again
    ///   and stored.
    /// - The original, when the decoder changed or the decoded activity's
    ///   file needs rebuilding too. It is decoded again and both files are
    ///   stored.
    ///
    /// An activity that cannot be rebuilt, because its original is gone or
    /// no longer decodes, is listed in the report's failures and left as it
    /// was. The call itself throws only when the library cannot be read.
    ///
    /// `checkingStreamFiles` also repairs stream files of activities whose
    /// metrics are still valid; see `staleActivities`. `progress` is called
    /// as each activity finishes, from this actor.
    @discardableResult
    public func recompute(
        checkingStreamFiles: Bool = false,
        at date: Date = Date(),
        progress: (@Sendable (RecomputeProgress) -> Void)? = nil
    ) async throws(LibraryError) -> RecomputeReport {
        let profile: AthleteProfile
        let stale: [StaleActivity]
        do {
            profile = try await currentProfile()
            stale = try await scan(profile: profile, checkingStreamFiles: checkingStreamFiles)
        } catch {
            throw LibraryError(error)
        }

        var report = RecomputeReport()
        var completed = 0
        await forEachBounded(stale) { [self] _, activity -> Result<RecomputeReport.Rebuilt, LibraryError> in
            do {
                try Task.checkCancellation()
                return .success(try await rebuild(activity, profile: profile, at: date))
            } catch {
                return .failure(LibraryError(error))
            }
        } onEach: { index, result in
            switch result {
            case .success(let rebuilt): report.rebuilt.append(rebuilt)
            case .failure(let error): report.failures.append(.init(id: stale[index].id, error: error))
            }
            completed += 1
            progress?(RecomputeProgress(completed: completed, total: stale.count))
        }
        report.rebuilt.sort { $0.id < $1.id }
        report.failures.sort { $0.id < $1.id }
        return report
    }

    private func rebuild(_ stale: StaleActivity, profile: AthleteProfile, at date: Date) async throws -> RecomputeReport.Rebuilt {
        // A source record with no activity yet is its own primary.
        let primary = try await store.activity(stale.id)?.primary ?? stale.id
        // Not while the same source is being imported: the two would write
        // the same row from different revisions.
        await begin(primary)
        defer { end(primary) }

        let existing = try await store.activity(stale.id)
        guard let record = try await store.sourceRecord(existing?.primary ?? stale.id) else {
            throw LibraryError.unknownActivity(stale.id)
        }
        let revision = record.currentRevision

        // A changed input means the stored stream may have come from another
        // original, decoder or set of rules, so it is not trusted. Metrics
        // that were never written say nothing about the stream either way.
        let renormalise = stale.reasons.contains(.input) || stale.reasons.contains(.notComputed)
        let found = try await materials(
            for: revision,
            renormalise: renormalise,
            // With no row there is nowhere else to learn the sport from.
            needsRecorded: stale.reasons.contains(.streamFile) || existing == nil || record.source == .healthKit
        )

        // Sport, flags and offset come from the decoded activity when it was
        // read. Otherwise the stored row holds what that activity said.
        guard let facts = found.recorded.map({ ActivityFacts($0, fallbackUTCOffset: existing?.utcOffset) })
            ?? existing.map(ActivityFacts.init)
        else { throw LibraryError.unknownActivity(stale.id) }
        let derived = try await Pipeline.derive(
            facts: facts,
            stream: found.stream,
            profile: profile,
            versions: versions,
            target: Pipeline.Target(
                members: existing?.members ?? [record.identity],
                primary: record.identity,
                revision: revision,
                existing: existing
            ),
            at: date,
            summaryOnly: found.recorded.flatMap { $0.stream.samples.isEmpty ? $0.stated : nil },
            sourceDistance: record.source == .healthKit ? found.recorded?.stated.distance : nil
        )
        // The row first and the metrics last, as in an import.
        let rowChanged = derived.row != existing
        if rowChanged {
            try await store.saveActivity(derived.row)
        }
        try await store.saveDerivedResult(derived.result)
        return RecomputeReport.Rebuilt(id: stale.id, reasons: stale.reasons, source: found.source, feedRowChanged: rowChanged)
    }

    /// The stream of a revision, the decoded activity when it had to be
    /// read, and the stored form they came from. Files that had to be built
    /// again are stored on the way.
    ///
    /// - `renormalise`: do not use the stored analysis stream; build it
    ///   again from the decoded activity.
    /// - `needsRecorded`: the decoded activity is wanted too, so its file is
    ///   read, and rebuilt from the original when it is not good.
    private func materials(
        for revision: ContentHash,
        renormalise: Bool,
        needsRecorded: Bool
    ) async throws -> (stream: AnalysisStream, recorded: RecordedActivity?, source: RebuildSource) {
        var stored: AnalysisStream?
        if !renormalise {
            stored = await store.analysisStream(for: revision, rulesVersion: versions.streamRules).value
        }
        if let stored, !needsRecorded {
            return (stored, nil, .analysisStream)
        }

        if let recorded = await store.recordedActivity(for: revision, decoderVersion: versions.decoder).value {
            if let stored {
                return (stored, recorded, .analysisStream)
            }
            let stream = try await Pipeline.normalise(recorded, versions: versions)
            try await store.saveAnalysisStream(stream, for: revision)
            return (stream, recorded, .recordedActivity)
        }

        let decoded = try await Pipeline.decode(try await original(revision), versions: versions, allowsSnapshot: true)
        try await store.saveRecordedActivity(decoded.recorded, decoderVersion: versions.decoder, for: revision)
        try await store.saveAnalysisStream(decoded.stream, for: revision)
        return (decoded.stream, decoded.recorded, .original)
    }

    // MARK: Serialized library mutations

    /// Imports, rebuilds and identity decisions share one writer so a merge
    /// cannot race a revision or a split across actor suspension points.
    private var identityNeedsRecovery = true
    private var busy: Set<SourceIdentity> = []
    private var waiting: [SourceIdentity: [CheckedContinuation<Void, Never>]] = [:]

    /// Waits for the library mutation slot. Reads can continue during derivation.
    func begin(_ source: SourceIdentity) async {
        let identity = SourceIdentity(source: .file, externalID: "library-writer")
        while busy.contains(identity) {
            await withCheckedContinuation { continuation in
                waiting[identity, default: []].append(continuation)
            }
        }
        busy.insert(identity)
    }

    func end(_ source: SourceIdentity) {
        let identity = SourceIdentity(source: .file, externalID: "library-writer")
        busy.remove(identity)
        for continuation in waiting.removeValue(forKey: identity) ?? [] {
            continuation.resume()
        }
    }

    // MARK: Bounded work

    /// Runs `work` for every item, at most `maximumConcurrentWork` at a
    /// time, and hands each output to `onEach` on this actor as it finishes.
    private func forEachBounded<Item: Sendable, Output: Sendable>(
        _ items: [Item],
        _ work: @escaping @Sendable (Int, Item) async -> Output,
        onEach: (Int, Output) -> Void
    ) async {
        await withTaskGroup(of: (Int, Output).self) { group in
            var next = 0
            func startNext(in group: inout TaskGroup<(Int, Output)>) {
                guard next < items.count else { return }
                let index = next
                let item = items[index]
                next += 1
                group.addTask { (index, await work(index, item)) }
            }
            for _ in 0..<Self.maximumConcurrentWork {
                startNext(in: &group)
            }
            while let (index, output) = await group.next() {
                onEach(index, output)
                startNext(in: &group)
            }
        }
    }

    // MARK: Durable identity decisions and resolved feed

    struct IdentityJournal: Codable {
        var version = 1
        var device = DeviceID(UUID().uuidString)
        var candidates: [String: MatchCandidate] = [:]
        var links: [LinkRecord] = []
        var decisions: [DecisionRecord] = []
        var tombstones: [Tombstone] = []
    }

    /// Upgrade the old mixed journal before returning the app's opened
    /// library. User decisions/identities remain backed up; Health facts do not.
    private nonisolated static func separateLegacyHealthCandidates(root: URL) throws {
        let url = root.appendingPathComponent("identity.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        var journal = try JSONDecoder().decode(IdentityJournal.self, from: Data(contentsOf: url))
        guard journal.version == 1 else { throw LibraryError.storage("Unsupported identity journal version") }
        let health = journal.candidates.filter { $0.value.identity.source == .healthKit }
        guard !health.isEmpty else { return }
        var directory = root.appendingPathComponent("HealthMetadata", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        let localURL = directory.appendingPathComponent("candidates.json")
        var local: [String: MatchCandidate] = [:]
        if FileManager.default.fileExists(atPath: localURL.path) {
            local = try JSONDecoder().decode([String: MatchCandidate].self, from: Data(contentsOf: localURL))
        }
        local.merge(health) { local, _ in local }
        try JSONEncoder().encode(local).write(to: localURL, options: .atomic)
        journal.candidates = journal.candidates.filter { $0.value.identity.source != .healthKit }
        try JSONEncoder().encode(journal).write(to: url, options: .atomic)
    }

    private var identityURL: URL { store.root.appendingPathComponent("identity.json") }

    func readIdentityJournal() throws -> IdentityJournal {
        guard FileManager.default.fileExists(atPath: identityURL.path) else { return IdentityJournal() }
        var journal = try JSONDecoder().decode(IdentityJournal.self, from: Data(contentsOf: identityURL))
        guard journal.version == 1 else { throw LibraryError.storage("Unsupported identity journal version") }
        let healthURL = store.root.appendingPathComponent("HealthMetadata/candidates.json")
        if FileManager.default.fileExists(atPath: healthURL.path) {
            let local = try JSONDecoder().decode([String: MatchCandidate].self, from: Data(contentsOf: healthURL))
            journal.candidates.merge(local) { _, local in local }
        }
        return journal
    }

    func writeIdentityJournal(_ journal: IdentityJournal) throws {
        var safe = journal
        let local = journal.candidates.filter { $0.value.identity.source == .healthKit }
        safe.candidates = journal.candidates.filter { $0.value.identity.source != .healthKit }
        var directory = store.root.appendingPathComponent("HealthMetadata", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        try JSONEncoder().encode(local).write(to: directory.appendingPathComponent("candidates.json"), options: .atomic)
        try JSONEncoder().encode(safe).write(to: identityURL, options: .atomic)
        identityNeedsRecovery = true
    }

    /// Rebuilds the resolved feed from source facts and add-only decisions.
    /// The journal is the durable intent; a failed cache replacement is retried
    /// on the next feed read or import, including after relaunch.
    func reconcileIdentity() async throws {
        var journal = try readIdentityJournal()
        let deleted = Set(journal.tombstones.filter { $0.kind == .deleted }.map(\.identity))
        if !deleted.isEmpty {
            // Intent is durable before any erasure. Recovery also repeats file
            // collection after a crash between the metadata save and unlink.
            try await cloudPurgeDeletedAssets(deleted)
            try await store.eraseSources(deleted)
            journal.candidates = journal.candidates.filter { !deleted.contains($0.value.identity) }
        }
        let records = try await store.sourceRecords()
        var old: [SourceIdentity: ActivityRecord] = [:]
        for id in Set(records.compactMap(\.activityID)) {
            old[id] = try await store.activity(id)
        }
        for record in records where journal.candidates[record.identity.description] == nil {
            guard let id = record.activityID, let row = old[id] else { continue }
            let found = try await materials(for: record.currentRevision, renormalise: false, needsRecorded: true)
            guard let recorded = found.recorded else { continue }
            var linked: Set<SourceIdentity> = []
            if record.source == .healthKit {
                linked = try HealthSnapshot.decode(try await original(record.currentRevision))?.linkedIdentities ?? []
            }
            journal.candidates[record.identity.description] = MatchCandidate(identity: record.identity,
                sport: recorded.sport, start: found.stream.start, elapsed: Double(found.stream.count),
                distance: (0..<found.stream.count).reversed().lazy.compactMap { found.stream.distance[$0] }.first ?? recorded.stated.distance,
                isIndoor: recorded.isIndoor || recorded.isVirtual, linkedIdentities: linked)
            // Migrate pre-journal user edits without guessing again on future imports.
            if row.title != FeedRules.generatedTitle(for: row) {
                journal.decisions.append(DecisionRecord(name: RecordName("legacy-title-\(id)"), value: .title(row.title),
                    time: record.importedAt, device: journal.device, members: Set(row.members)))
            }
            if row.isHidden {
                journal.decisions.append(DecisionRecord(name: RecordName("legacy-hide-\(id)"), value: .hidden(true),
                    time: record.importedAt, device: journal.device, members: Set(row.members)))
                journal.tombstones += Tombstone.written(.hidden, for: Set(row.members), at: record.importedAt)
            }
        }
        let scan = MatchScan.scan(Array(journal.candidates.values), at: Date(timeIntervalSince1970: 0), device: DeviceID("automatic"))
        let names = Set(journal.links.map(\.name))
        journal.links += scan.links.filter { !names.contains($0.name) }
        try writeIdentityJournal(journal)
        let resolved = ResolvedLibrary.resolve(records: Set(journal.candidates.values.map(\.identity)).intersection(records.map(\.identity)), links: journal.links,
            decisions: journal.decisions, tombstones: journal.tombstones)
        let byIdentity = Dictionary(uniqueKeysWithValues: records.map { ($0.identity, $0) })
        let profile = try await currentProfile()
        var replacements: [ActivityRecord] = []
        var results: [DerivedResult] = []
        var removing = Set(old.keys).subtracting(resolved.activities.map(\.id))
        for group in resolved.activities {
            guard let primary = byIdentity[group.primary] else { continue }
            let existing = old[group.id]
            let members = group.members.sorted()
            let locality = ActivityLocalityCache.entry(root: store.root, revision: primary.currentRevision)?.name
            let expectedTitle = group.title ?? existing.map { FeedRules.generatedTitle(for: $0, locality: locality) }
            if let existing, existing.members.sorted() == members, existing.primary == group.primary,
               existing.isHidden == group.isHidden,
               let cached = try await store.derivedResult(owner: .activity(group.id), kind: Self.metricsKind) {
                if let expectedTitle, existing.title != expectedTitle {
                    var renamed = existing
                    renamed.title = expectedTitle
                    replacements.append(renamed)
                    results.append(cached)
                    removing.insert(group.id)
                }
                continue
            }
            let found = try await materials(for: primary.currentRevision, renormalise: false, needsRecorded: true)
            guard let recorded = found.recorded else { throw LibraryError.originalMissing(primary.currentRevision) }
            var derived = try await Pipeline.derive(facts: ActivityFacts(recorded, fallbackUTCOffset: existing?.utcOffset),
                stream: found.stream, profile: profile, versions: versions,
                target: Pipeline.Target(members: members, primary: group.primary,
                    revision: primary.currentRevision, existing: nil), at: Date(),
                summaryOnly: recorded.stream.samples.isEmpty ? recorded.stated : nil,
                sourceDistance: primary.source == .healthKit ? recorded.stated.distance : nil)
            derived.row.title = group.title ?? FeedRules.generatedTitle(for: derived.row, locality: locality)
            derived.row.isHidden = group.isHidden
            replacements.append(derived.row)
            results.append(derived.result)
            for member in members { if let id = byIdentity[member]?.activityID { removing.insert(id) } }
        }
        if !removing.isEmpty || !replacements.isEmpty {
            try await store.replaceActivities(removing: removing, with: replacements, results: results)
        }
        for record in records {
            let standing = Tombstone.standing(of: record.identity, tombstones: journal.tombstones, decisions: journal.decisions)
            let next: SourceRecordState
            switch standing {
            case .deleted: next = .deleted
            case .hidden: next = .hidden
            case .live: next = record.state == .hidden ? .active : record.state
            }
            if next != record.state { try await store.setState(next, for: record.identity) }
        }
        identityNeedsRecovery = false
    }

    public func possibleDuplicates() async throws -> [IdentityPair] {
        let journal = try readIdentityJournal()
        let scan = MatchScan.scan(Array(journal.candidates.values), at: Date(), device: journal.device)
        let resolved = ResolvedLibrary.resolve(records: Set(journal.candidates.values.map(\.identity)),
            links: journal.links, decisions: journal.decisions, tombstones: journal.tombstones)
        // Pairwise tolerances are not transitive: A can match B and B can
        // match C while A/C fails. Once the links put all three in one
        // activity, that last pair needs no further user decision. The same
        // applies when a refreshed source no longer passes an existing link.
        let activityOf = Dictionary(uniqueKeysWithValues: resolved.activities.flatMap { activity in
            activity.members.map { ($0, activity.id) }
        })
        let pending = Set(scan.awaitingReview(given: journal.links) + resolved.possibleDuplicates.map(\.pair))
        return pending.filter { pair in
            guard let first = activityOf[pair.lower], let second = activityOf[pair.upper] else { return false }
            return first != second
        }.sorted()
    }

    public func identityChanges() throws -> IdentityChanges {
        let journal = try readIdentityJournal()
        return IdentityChanges(links: journal.links, decisions: journal.decisions, tombstones: journal.tombstones)
    }

    public func applyIdentityChanges(_ changes: IdentityChanges) async throws {
        let token = SourceIdentity(source: .file, externalID: "decisions")
        await begin(token)
        defer { end(token) }
        var journal = try readIdentityJournal()
        journal.links = Array(Set(journal.links + changes.links))
        journal.decisions = Array(Set(journal.decisions + changes.decisions))
        journal.tombstones = Array(Set(journal.tombstones + changes.tombstones))
        try writeIdentityJournal(journal)
        try await reconcileIdentity()
    }

    /// Channels present in preserved alternatives but absent from the primary.
    /// Only measured/interpolated values count; an all-missing series does not.
    public func alternativeSources(for id: SourceIdentity) async throws -> [AlternativeOffer] {
        await begin(id)
        defer { end(id) }
        guard let row = try await store.activity(id) else { throw LibraryError.unknownActivity(id) }
        guard row.members.count > 1 else { return [] }
        var channels: [SourceIdentity: Set<Channel>] = [:]
        for member in row.members {
            guard let record = try await store.sourceRecord(member) else { continue }
            let stream = try await materials(for: record.currentRevision, renormalise: false, needsRecorded: false).stream
            let series: [(Channel, Series)] = [(.latitude, stream.latitude), (.longitude, stream.longitude),
                (.altitude, stream.altitude), (.distance, stream.distance), (.speed, stream.speed),
                (.heartRate, stream.heartRate), (.power, stream.power), (.cadence, stream.cadence),
                (.temperature, stream.temperature), (.gradient, stream.gradient)]
            channels[member] = Set(series.compactMap { channel, values in
                (0..<values.count).contains { values[$0] != nil } ? channel : nil
            })
        }
        return PrimaryChoice.alternativesOfferingMore(than: row.primary, channelsByMember: channels)
    }

    public func activityContaining(_ source: SourceIdentity) async throws -> ActivityRecord? {
        guard let id = try await store.sourceRecord(source)?.activityID else { return nil }
        return try await store.activity(id)
    }

    public func hiddenActivities() async throws -> [ActivityRecord] {
        let ids = Set(try await store.sourceRecords().compactMap(\.activityID))
        var rows: [ActivityRecord] = []
        for id in ids {
            if let row = try await store.activity(id), row.isHidden { rows.append(row) }
        }
        return rows.sorted { $0.start > $1.start }
    }

    /// The durable identities that imports and sync must never restore.
    public func deletedIdentities() throws -> Set<SourceIdentity> {
        Set(try readIdentityJournal().tombstones.filter { $0.kind == .deleted }.map(\.identity))
    }

    /// Caller must obtain explicit confirmation. Tombstones commit first; the
    /// next feed/import completes erasure if storage fails or the app exits.
    public func permanentlyDelete(_ id: SourceIdentity, at date: Date = Date()) async throws {
        await begin(id)
        defer { end(id) }
        if identityNeedsRecovery && FileManager.default.fileExists(atPath: identityURL.path) { try await reconcileIdentity() }
        guard let row = try await store.activity(id) else {
            if try deletedIdentities().contains(id) { return }
            throw LibraryError.unknownActivity(id)
        }
        var journal = try readIdentityJournal()
        journal.tombstones += Tombstone.written(.deleted, for: Set(row.members), at: date)
        try writeIdentityJournal(journal)
        try await reconcileIdentity()
    }

    /// Saves a successful geocoding result (nil means no locality found).
    /// Network failure is not a result: the app leaves it uncached for retry.
    /// Explicit title decisions always win, even if written while geocoding.
    @discardableResult
    public func setLocality(_ locality: String?, for request: ActivityLocalityRequest) async throws -> Bool {
        await begin(request.source)
        defer { end(request.source) }
        // Recover pending identity/deletion intent and migrate legacy titles
        // before checking the source or adding a generated locality.
        if identityNeedsRecovery { try await reconcileIdentity() }
        guard let source = try await store.sourceRecord(request.source),
              source.state != .deleted, source.currentRevision == request.revision else { return false }
        try ActivityLocalityCache.save(locality, root: store.root, revision: request.revision)
        identityNeedsRecovery = true
        try await reconcileIdentity()
        return true
    }

    /// User decisions apply to every current member, independent of primary.
    public func decide(_ value: DecisionValue, for id: SourceIdentity, at date: Date = Date()) async throws {
        await begin(id)
        defer { end(id) }
        if identityNeedsRecovery && FileManager.default.fileExists(atPath: identityURL.path) { try await reconcileIdentity() }
        guard let row = try await store.activity(id) else { throw LibraryError.unknownActivity(id) }
        var journal = try readIdentityJournal()
        let members = Set(row.members)
        if case .primary(let primary) = value, !members.contains(primary) { throw LibraryError.unknownActivity(primary) }
        journal.decisions.append(DecisionRecord(name: RecordName(UUID().uuidString), value: value,
            time: date, device: journal.device, members: members))
        if value == .hidden(true) { journal.tombstones += Tombstone.written(.hidden, for: members, at: date) }
        try writeIdentityJournal(journal)
        try await reconcileIdentity()
    }

    public func link(_ pair: IdentityPair, kind: LinkKind, at date: Date = Date()) async throws {
        await begin(pair.lower)
        defer { end(pair.lower) }
        var journal = try readIdentityJournal()
        journal.links.append(LinkRecord(name: RecordName(UUID().uuidString), pair: pair, kind: kind,
            maker: .user, time: date, device: journal.device))
        try writeIdentityJournal(journal)
        try await reconcileIdentity()
    }

    /// Separates every member, inheriting the decisions that were in effect.
    public func split(_ id: SourceIdentity, at date: Date = Date()) async throws {
        await begin(id)
        defer { end(id) }
        guard let row = try await store.activity(id) else { throw LibraryError.unknownActivity(id) }
        var journal = try readIdentityJournal()
        journal.decisions += Split.inheritedCopies(splitting: Set(row.members),
            into: row.members.map { Set([$0]) }, decisions: journal.decisions, device: journal.device)
        for (index, first) in row.members.enumerated() {
            for second in row.members.dropFirst(index + 1) {
                journal.links.append(LinkRecord(name: RecordName(UUID().uuidString), pair: IdentityPair(first, second),
                    kind: .keepSeparate, maker: .user, time: date, device: journal.device))
            }
        }
        try writeIdentityJournal(journal)
        try await reconcileIdentity()
    }

}
