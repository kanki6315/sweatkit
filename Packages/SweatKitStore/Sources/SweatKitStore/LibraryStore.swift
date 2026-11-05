import Foundation
import SwiftData
import SweatKitModel

/// The on-device library: originals, source records, activities, streams,
/// derived results and the athlete profile.
///
/// Persistence only. The store never decodes a file, computes a metric or
/// decides a merge: a pipeline above it calls Ingest, Identity and Analysis
/// and hands their results here. Everything that crosses the actor boundary
/// is a `Sendable` value type.
///
/// Metadata lives in SwiftData. Originals and streams are files under the
/// root directory passed to `init(root:)`. A write that touches both writes
/// the file first, atomically, then the metadata, so an interrupted write
/// leaves at worst a file that no metadata names. `collectGarbage()` removes
/// those; nothing reads a file as a record.
///
/// Where later work attaches:
/// - Hiding, restoring and deleting: `setState(_:for:)` records a source
///   record's state and `ActivityRecord.isHidden` an activity's. Permanent
///   deletion adds a method that writes a tombstone model keyed by identity
///   before erasing the record's revisions, originals, streams and results;
///   `importOriginal` then refuses identities with a tombstone.
/// - Merge links and decisions: add-only models beside `ActivityEntity`, see
///   `StoreSchemaV1`. A merge or split replaces the affected activities in
///   one save; `saveActivity` refuses a member of another activity until then.
/// - The iCloud copy: CloudKit's sync engine reads and writes source records
///   by identity and revisions by content hash, which are already the unique
///   keys, and uploads `Originals/` files as assets. Streams and derived
///   results stay on the device.
/// - HealthKit snapshots: a snapshot's encoded bytes are imported with
///   `importOriginal` under the workout's identity; each new snapshot is a
///   revision.
/// - Unzipping Garmin downloads: the Garmin adapter unzips and passes the
///   inner file's bytes to `importOriginal`. The zip is never stored.
/// - Thumbnails: files beside `Streams/`, see `LibraryFiles`.
/// - The pipeline: calls `importOriginal`, then the stream and activity
///   writes, and recomputes whatever `staleResults` reports.
public actor LibraryStore: ModelActor {
    public nonisolated let modelExecutor: any ModelExecutor
    public nonisolated let modelContainer: ModelContainer
    private nonisolated let files: LibraryFiles

    /// The single key of the stored athlete profile.
    private static let profileKey = "athlete"

    /// Opens the library under `root`, creating it when it does not exist.
    public init(root: URL) throws {
        let files = LibraryFiles(root: root)
        try files.createDirectories()
        let schema = Schema(versionedSchema: StoreSchemaV1.self)
        // No CloudKit mirroring, even if the app gains the entitlement: iCloud
        // goes through CloudKit's sync engine, and mirroring forbids the
        // unique keys the identity rule needs.
        let configuration = ModelConfiguration(schema: schema, url: files.databaseURL, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: StoreMigrationPlan.self,
            configurations: [configuration]
        )
        let context = ModelContext(container)
        context.autosaveEnabled = false
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: context)
        self.modelContainer = container
        self.files = files
    }

    /// The root directory the library lives in.
    public nonisolated var root: URL { files.root }

    // MARK: Originals and source records

    /// Stores an original under a source identity.
    ///
    /// - Bytes already current for this identity change nothing.
    /// - Bytes that are an earlier revision of this identity become its
    ///   current revision again, reported as a new revision.
    /// - Other bytes under an existing identity are a new revision of the
    ///   same record, never a new record.
    /// - An imported file must use `SourceIdentity(fileContents:)`. If its
    ///   bytes are already stored under any record, it is recognised as that
    ///   record and nothing is added.
    public func importOriginal(_ bytes: Data, as identity: SourceIdentity, at date: Date) throws -> ImportOutcome {
        let hash = ContentHash(of: bytes)
        if identity.source == .file {
            guard identity == SourceIdentity(fileContents: bytes) else {
                throw StoreError.fileIdentityMismatch(identity)
            }
            if let owner = try recordsHolding(hash).min(by: { $0.key < $1.key }), owner.key != identity.description {
                return .recognised(try value(of: owner))
            }
        }

        let existing = try fetchRecord(identity)
        if let existing, existing.revisions.contains(where: { $0.contentHash == hash.hex }) {
            if existing.currentRevisionHash == hash.hex {
                return .unchanged(try value(of: existing))
            }
            existing.currentRevisionHash = hash.hex
            try modelContext.save()
            return .newRevision(try value(of: existing))
        }

        try files.writeOriginal(bytes, hash: hash)

        let record: SourceRecordEntity
        if let existing {
            record = existing
        } else {
            record = SourceRecordEntity(
                key: identity.description,
                sourceRaw: identity.source.rawValue,
                externalID: identity.externalID,
                stateRaw: SourceRecordState.active.rawValue,
                importedAt: date,
                currentRevisionHash: hash.hex
            )
            modelContext.insert(record)
        }
        let sequence = (record.revisions.map(\.sequence).max() ?? -1) + 1
        let revision = RevisionEntity(
            key: Self.revisionKey(identity: identity, hash: hash),
            contentHash: hash.hex,
            sequence: sequence,
            addedAt: date,
            byteCount: bytes.count
        )
        modelContext.insert(revision)
        revision.record = record
        record.currentRevisionHash = hash.hex
        try modelContext.save()
        let stored = try value(of: record)
        return existing == nil ? .newRecord(stored) : .newRevision(stored)
    }

    /// Imports a file, whose identity is the hash of its bytes.
    public func importFile(_ bytes: Data, at date: Date) throws -> ImportOutcome {
        try importOriginal(bytes, as: SourceIdentity(fileContents: bytes), at: date)
    }

    public func sourceRecord(_ identity: SourceIdentity) throws -> SourceRecord? {
        try fetchRecord(identity).map(value(of:))
    }

    /// Every source record, ordered by identity.
    public func sourceRecords() throws -> [SourceRecord] {
        let descriptor = FetchDescriptor<SourceRecordEntity>(sortBy: [SortDescriptor(\.key, comparator: .lexical)])
        return try modelContext.fetch(descriptor).map(value(of:))
    }

    /// Records a source record's state. What the state means for the rest of
    /// the library is decided above the store.
    public func setState(_ state: SourceRecordState, for identity: SourceIdentity) throws {
        guard let record = try fetchRecord(identity) else { throw StoreError.unknownSourceRecord(identity) }
        record.stateRaw = state.rawValue
        try modelContext.save()
    }

    /// The bytes of a stored original, checked against their hash. Nil when
    /// no file is stored.
    @concurrent
    public nonisolated func original(_ hash: ContentHash) async throws -> Data? {
        try files.readOriginal(hash)
    }

    // MARK: Activities

    /// Saves an activity, replacing the stored one with the same ID. The ID
    /// is the lowest identity among the members, which must all be stored
    /// source records. Returns the ID.
    @discardableResult
    public func saveActivity(_ activity: ActivityRecord) throws -> SourceIdentity {
        try writeActivity(activity, save: true)
    }

    private func writeActivity(_ activity: ActivityRecord, save: Bool) throws -> SourceIdentity {
        let members = Array(Set(activity.members)).sorted()
        guard let id = members.first, members.contains(activity.primary) else {
            throw StoreError.invalidMembers
        }
        var records: [SourceRecordEntity] = []
        for member in members {
            guard let record = try fetchRecord(member) else { throw StoreError.unknownSourceRecord(member) }
            if let current = record.activity, current.id != id.description {
                throw StoreError.memberOfAnotherActivity(member)
            }
            records.append(record)
        }

        let entity: ActivityEntity
        if let existing = try fetchActivityEntity(id) {
            entity = existing
        } else {
            entity = ActivityEntity(
                id: id.description,
                primaryKey: activity.primary.description,
                sportRaw: activity.sport.rawValue,
                start: activity.start,
                elapsedTime: activity.elapsedTime,
                isIndoor: activity.isIndoor,
                isVirtual: activity.isVirtual,
                title: activity.title,
                isHidden: activity.isHidden
            )
            modelContext.insert(entity)
        }
        entity.primaryKey = activity.primary.description
        entity.sportRaw = activity.sport.rawValue
        entity.start = activity.start
        entity.utcOffset = activity.utcOffset
        entity.elapsedTime = activity.elapsedTime
        entity.timerTime = activity.timerTime
        entity.movingTime = activity.movingTime
        entity.distance = activity.distance
        entity.ascent = activity.ascent
        entity.isIndoor = activity.isIndoor
        entity.isVirtual = activity.isVirtual
        entity.title = activity.title
        entity.headlineKind = activity.headline?.kind
        entity.headlineValue = activity.headline?.value.value
        entity.headlineUnavailableReason = activity.headline?.value.reason?.rawValue
        entity.isHidden = activity.isHidden
        entity.members = records
        if save { try modelContext.save() }
        return id
    }

    /// Atomically replaces a set of resolved activities after a merge or split.
    /// Originals and source records are retained. No member may occur twice or
    /// be taken from an activity outside `removing`.
    public func replaceActivities(
        removing: Set<SourceIdentity>, with activities: [ActivityRecord],
        results: [DerivedResult] = []
    ) throws {
        var seen: Set<SourceIdentity> = []
        for activity in activities {
            guard let id = activity.id, activity.members.contains(activity.primary),
                  Set(activity.members).count == activity.members.count else { throw StoreError.invalidMembers }
            if try fetchActivityEntity(id) != nil, !removing.contains(id) {
                throw StoreError.memberOfAnotherActivity(id)
            }
            for member in activity.members {
                guard seen.insert(member).inserted else { throw StoreError.invalidMembers }
                guard let record = try fetchRecord(member) else { throw StoreError.unknownSourceRecord(member) }
                if let current = record.activity, !removing.contains(where: { $0.description == current.id }) {
                    throw StoreError.memberOfAnotherActivity(member)
                }
            }
        }
        let newIDs = Set(activities.compactMap(\.id))
        do {
            for id in removing {
                if let entity = try fetchActivityEntity(id) {
                    for record in entity.members { record.activity = nil }
                    entity.members = []
                    if !newIDs.contains(id) { modelContext.delete(entity) }
                }
                let owner = ResultOwner.activity(id).rawValue
                let replacementKinds = Set(results.filter { $0.owner.rawValue == owner }.map(\.kind))
                for result in try modelContext.fetch(FetchDescriptor<DerivedResultEntity>(predicate: #Predicate { $0.owner == owner })) {
                    if !newIDs.contains(id) || !replacementKinds.contains(result.kind) { modelContext.delete(result) }
                }
            }
            for activity in activities { _ = try writeActivity(activity, save: false) }
            for result in results { try writeDerivedResult(result, save: false) }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    public func activity(_ id: SourceIdentity) throws -> ActivityRecord? {
        try fetchActivityEntity(id).map(value(of:))
    }

    /// One page of the feed: visible activities matching `filter`, newest
    /// first, with ties broken by ID so the order is total. Pass the previous
    /// page's `next` to continue.
    public func feed(_ filter: FeedFilter = FeedFilter(), limit: Int, after cursor: FeedCursor? = nil) throws -> FeedPage {
        guard limit > 0 else { return FeedPage(activities: [], next: nil) }
        let filterSports = filter.sports != nil
        let sports = (filter.sports ?? []).map(\.rawValue)
        let from = filter.dates?.lowerBound ?? .distantPast
        let to = filter.dates?.upperBound ?? .distantFuture
        let filterSetting = filter.setting != nil
        let wantIndoor = filter.setting == .indoor
        let text = filter.titleContains ?? ""
        let filterTitle = !text.isEmpty
        let hasCursor = cursor != nil
        let cursorStart = cursor?.start ?? .distantFuture
        let cursorID = cursor?.id.description ?? ""

        // Separate parts, joined below, keep each one within what the type
        // checker can handle.
        let visibleInRange = #Predicate<ActivityEntity> { activity in
            activity.isHidden == false && activity.start >= from && activity.start < to
        }
        let matchesSport = #Predicate<ActivityEntity> { activity in
            filterSports == false || sports.contains(activity.sportRaw)
        }
        let matchesSetting = #Predicate<ActivityEntity> { activity in
            filterSetting == false || activity.isIndoor == wantIndoor
        }
        let matchesTitle = #Predicate<ActivityEntity> { activity in
            filterTitle == false || activity.title.localizedStandardContains(text)
        }
        let afterCursor = #Predicate<ActivityEntity> { activity in
            hasCursor == false || activity.start < cursorStart
                || (activity.start == cursorStart && activity.id < cursorID)
        }
        let predicate = #Predicate<ActivityEntity> { activity in
            visibleInRange.evaluate(activity) && matchesSport.evaluate(activity)
                && matchesSetting.evaluate(activity) && matchesTitle.evaluate(activity)
                && afterCursor.evaluate(activity)
        }
        var descriptor = FetchDescriptor<ActivityEntity>(
            predicate: predicate,
            // Lexical, not the default numeric-aware comparison, so the order
            // agrees with the cursor's `<` and with `SourceIdentity`'s order.
            sortBy: [SortDescriptor(\.start, order: .reverse), SortDescriptor(\.id, comparator: .lexical, order: .reverse)]
        )
        // One extra row says whether another page follows.
        descriptor.fetchLimit = limit + 1
        descriptor.relationshipKeyPathsForPrefetching = [\.members]
        let entities = try modelContext.fetch(descriptor)
        let page = try entities.prefix(limit).map(value(of:))
        var next: FeedCursor?
        if entities.count > limit, let last = page.last, let id = last.id {
            next = FeedCursor(start: last.start, id: id)
        }
        return FeedPage(activities: page, next: next)
    }

    // MARK: Streams

    /// Stores the decoded recorded activity of a revision, replacing any
    /// earlier one. `decoderVersion` is the version of the decoder that built it.
    public func saveRecordedActivity(_ activity: RecordedActivity, decoderVersion: Int, for revision: ContentHash) throws {
        try requireRevision(revision)
        let file = try StreamFileFormat.encode(activity, decoderVersion: decoderVersion)
        try file.write(to: files.recordedURL(revision), options: .atomic)
    }

    /// Stores the analysis stream of a revision, replacing any earlier one.
    public func saveAnalysisStream(_ stream: AnalysisStream, for revision: ContentHash) throws {
        try requireRevision(revision)
        let file = try StreamFileFormat.encode(stream)
        try file.write(to: files.analysisURL(revision), options: .atomic)
    }

    /// The decoded recorded activity of a revision, or why it needs a rebuild.
    /// A file from another decoder version is outdated.
    @concurrent
    public nonisolated func recordedActivity(for revision: ContentHash, decoderVersion: Int) async -> StreamRead<RecordedActivity> {
        let file: Data
        switch Self.readStreamFile(files.recordedURL(revision)) {
        case .available(let data): file = data
        case .needsRebuild(let reason): return .needsRebuild(reason)
        }
        do {
            let decoded = try StreamFileFormat.decodeRecordedActivity(file)
            guard decoded.decoderVersion == decoderVersion else { return .needsRebuild(.outdated) }
            return .available(decoded.activity)
        } catch {
            return .needsRebuild(Self.reason(for: error))
        }
    }

    /// The analysis stream of a revision, or why it needs a rebuild. A
    /// stream built under other stream rules is outdated.
    @concurrent
    public nonisolated func analysisStream(for revision: ContentHash, rulesVersion: Int) async -> StreamRead<AnalysisStream> {
        let file: Data
        switch Self.readStreamFile(files.analysisURL(revision)) {
        case .available(let data): file = data
        case .needsRebuild(let reason): return .needsRebuild(reason)
        }
        do {
            let stream = try StreamFileFormat.decodeAnalysisStream(file)
            guard stream.rulesVersion == rulesVersion else { return .needsRebuild(.outdated) }
            return .available(stream)
        } catch {
            return .needsRebuild(Self.reason(for: error))
        }
    }

    private nonisolated static func readStreamFile(_ url: URL) -> StreamRead<Data> {
        guard FileManager.default.fileExists(atPath: url.path) else { return .needsRebuild(.missing) }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return .needsRebuild(.unreadable) }
        return .available(data)
    }

    private nonisolated static func reason(for failure: StreamFileFormat.ReadFailure) -> RebuildReason {
        switch failure {
        case .unreadable: .unreadable
        case .unsupportedFormat: .unsupportedFormat
        }
    }

    // MARK: Derived results

    /// Saves a derived result, replacing the one with the same owner and kind.
    public func saveDerivedResult(_ result: DerivedResult) throws {
        try writeDerivedResult(result, save: true)
    }

    private func writeDerivedResult(_ result: DerivedResult, save: Bool) throws {
        guard (result.profileReading == nil) == (result.provenance.profileFingerprint == nil) else {
            throw StoreError.inconsistentProvenance
        }
        let key = Self.resultKey(owner: result.owner, kind: result.kind)
        let entity: DerivedResultEntity
        if let existing = try modelContext.fetch(FetchDescriptor<DerivedResultEntity>(predicate: #Predicate { $0.key == key })).first {
            entity = existing
        } else {
            entity = DerivedResultEntity(
                key: key,
                owner: result.owner.rawValue,
                kind: result.kind,
                inputRevision: result.provenance.inputRevision.hex,
                algorithmVersion: result.provenance.algorithmVersion,
                payload: result.payload,
                computedAt: result.computedAt
            )
            modelContext.insert(entity)
        }
        entity.inputRevision = result.provenance.inputRevision.hex
        entity.profileFingerprint = result.provenance.profileFingerprint?.hex
        entity.algorithmVersion = result.provenance.algorithmVersion
        entity.profileReadingDate = result.profileReading?.date
        entity.profileReadingInputs = result.profileReading?.inputs.rawValue
        entity.payload = result.payload
        entity.computedAt = result.computedAt
        if save { try modelContext.save() }
    }

    public func derivedResult(owner: ResultOwner, kind: String) throws -> DerivedResult? {
        let key = Self.resultKey(owner: owner, kind: kind)
        return try modelContext.fetch(FetchDescriptor<DerivedResultEntity>(predicate: #Predicate { $0.key == key }))
            .first.map(value(of:))
    }

    /// Every result of one owner, ordered by kind.
    public func derivedResults(owner: ResultOwner) throws -> [DerivedResult] {
        let raw = owner.rawValue
        let descriptor = FetchDescriptor<DerivedResultEntity>(
            predicate: #Predicate { $0.owner == raw },
            sortBy: [SortDescriptor(\.kind, comparator: .lexical)]
        )
        return try modelContext.fetch(descriptor).map(value(of:))
    }

    /// The current input revision of every activity: the current revision of
    /// its primary member. A pipeline whose results read more than that
    /// passes its own revisions to `staleResults` instead.
    public func activityInputRevisions() throws -> [ResultOwner: ContentHash] {
        var revisions: [ResultOwner: ContentHash] = [:]
        for activity in try modelContext.fetch(FetchDescriptor<ActivityEntity>()) {
            guard let primary = activity.members.first(where: { $0.key == activity.primaryKey }) else { continue }
            revisions[.activity(try Self.identity(canonical: activity.id))] = ContentHash(hex: primary.currentRevisionHash)
        }
        return revisions
    }

    /// The results of `kind` that no longer match what the caller says is
    /// current. A result is stale when its algorithm version differs, when
    /// its owner's input revision differs or is absent from
    /// `inputRevisions`, or when the profile values it read differ on the
    /// date it read them for.
    ///
    /// Results computed from other results are covered by giving them an
    /// input revision that includes their inputs' provenance; the store does
    /// not follow dependencies itself.
    public func staleResults(
        kind: String,
        algorithmVersion: Int,
        profile: AthleteProfile,
        inputRevisions: [ResultOwner: ContentHash]
    ) throws -> [StaleResult] {
        let descriptor = FetchDescriptor<DerivedResultEntity>(
            predicate: #Predicate { $0.kind == kind },
            sortBy: [SortDescriptor(\.owner, comparator: .lexical)]
        )
        var stale: [StaleResult] = []
        for entity in try modelContext.fetch(descriptor) {
            let owner = ResultOwner(rawValue: entity.owner)
            var reasons: Set<StaleReason> = []
            if entity.algorithmVersion != algorithmVersion {
                reasons.insert(.algorithm)
            }
            if inputRevisions[owner]?.hex != entity.inputRevision {
                reasons.insert(.input)
            }
            if let stored = entity.profileFingerprint {
                let current = entity.profileReadingDate.map {
                    profile.fingerprint(on: $0, reading: AthleteProfile.Inputs(rawValue: entity.profileReadingInputs ?? AthleteProfile.Inputs.all.rawValue))
                }
                if current?.hex != stored {
                    reasons.insert(.profile)
                }
            }
            if !reasons.isEmpty {
                stale.append(StaleResult(owner: owner, kind: entity.kind, reasons: reasons))
            }
        }
        return stale
    }

    // MARK: Athlete profile

    public func saveProfile(_ profile: AthleteProfile) throws {
        let encoded = try PropertyListEncoder().encode(profile)
        let key = Self.profileKey
        if let existing = try modelContext.fetch(FetchDescriptor<ProfileEntity>(predicate: #Predicate { $0.key == key })).first {
            existing.encoded = encoded
        } else {
            modelContext.insert(ProfileEntity(key: key, encoded: encoded))
        }
        try modelContext.save()
    }

    /// The stored profile, or nil before one is saved.
    public func profile() throws -> AthleteProfile? {
        let key = Self.profileKey
        guard let entity = try modelContext.fetch(FetchDescriptor<ProfileEntity>(predicate: #Predicate { $0.key == key })).first else {
            return nil
        }
        do {
            return try PropertyListDecoder().decode(AthleteProfile.self, from: entity.encoded)
        } catch {
            throw StoreError.unreadableMetadata("athlete profile")
        }
    }

    // MARK: Garbage

    /// Removes files that no metadata names: originals and streams left by
    /// interrupted writes, and leftover temporary files. Reports revisions
    /// whose original is missing without changing them.
    public func collectGarbage() throws -> GarbageReport {
        let revisions = try modelContext.fetch(FetchDescriptor<RevisionEntity>())
        let known = Set(revisions.map(\.contentHash))
        let manager = FileManager.default

        var removedOriginals: [ContentHash] = []
        for url in try files.contents(of: files.originalsDirectory) where !known.contains(url.lastPathComponent) {
            try manager.removeItem(at: url)
            removedOriginals.append(ContentHash(hex: url.lastPathComponent))
        }

        let streamExtensions: Set<String> = [LibraryFiles.recordedExtension, LibraryFiles.analysisExtension]
        var removedStreamFiles = 0
        for url in try files.contents(of: files.streamsDirectory) {
            let isStream = streamExtensions.contains(url.pathExtension)
            if !isStream || !known.contains(url.deletingPathExtension().lastPathComponent) {
                try manager.removeItem(at: url)
                removedStreamFiles += 1
            }
        }

        let missing = known
            .filter { !manager.fileExists(atPath: files.originalURL(ContentHash(hex: $0)).path) }
            .sorted()
            .map(ContentHash.init(hex:))
        return GarbageReport(
            removedOriginals: removedOriginals.sorted { $0.hex < $1.hex },
            removedStreamFiles: removedStreamFiles,
            revisionsMissingOriginal: missing
        )
    }

    // MARK: Fetching

    private func fetchRecord(_ identity: SourceIdentity) throws -> SourceRecordEntity? {
        let key = identity.description
        return try modelContext.fetch(FetchDescriptor<SourceRecordEntity>(predicate: #Predicate { $0.key == key })).first
    }

    private func recordsHolding(_ hash: ContentHash) throws -> [SourceRecordEntity] {
        let hex = hash.hex
        return try modelContext.fetch(FetchDescriptor<RevisionEntity>(predicate: #Predicate { $0.contentHash == hex }))
            .compactMap(\.record)
    }

    private func requireRevision(_ hash: ContentHash) throws {
        let hex = hash.hex
        var descriptor = FetchDescriptor<RevisionEntity>(predicate: #Predicate { $0.contentHash == hex })
        descriptor.fetchLimit = 1
        guard try modelContext.fetchCount(descriptor) > 0 else { throw StoreError.unknownRevision(hash) }
    }

    private func fetchActivityEntity(_ id: SourceIdentity) throws -> ActivityEntity? {
        let key = id.description
        return try modelContext.fetch(FetchDescriptor<ActivityEntity>(predicate: #Predicate { $0.id == key })).first
    }

    // MARK: Conversion

    private static func revisionKey(identity: SourceIdentity, hash: ContentHash) -> String {
        "\(identity)#\(hash.hex)"
    }

    /// Owner and kind, length-prefixed so no pair of names can collide.
    private static func resultKey(owner: ResultOwner, kind: String) -> String {
        "\(owner.rawValue.utf8.count):\(owner.rawValue)\(kind)"
    }

    /// Parses the canonical form `source:externalID`.
    private static func identity(canonical: String) throws -> SourceIdentity {
        guard let separator = canonical.firstIndex(of: ":"),
              let source = SourceKind(rawValue: String(canonical[..<separator]))
        else { throw StoreError.unreadableMetadata("identity \(canonical)") }
        return SourceIdentity(source: source, externalID: String(canonical[canonical.index(after: separator)...]))
    }

    private func value(of record: SourceRecordEntity) throws -> SourceRecord {
        guard let source = SourceKind(rawValue: record.sourceRaw),
              let state = SourceRecordState(rawValue: record.stateRaw)
        else { throw StoreError.unreadableMetadata("source record \(record.key)") }
        let revisions = record.revisions
            .sorted { $0.sequence < $1.sequence }
            .map { SourceRevision(contentHash: ContentHash(hex: $0.contentHash), addedAt: $0.addedAt, byteCount: $0.byteCount) }
        return SourceRecord(
            identity: SourceIdentity(source: source, externalID: record.externalID),
            state: state,
            importedAt: record.importedAt,
            revisions: revisions,
            currentRevision: ContentHash(hex: record.currentRevisionHash),
            activityID: try record.activity.map { try Self.identity(canonical: $0.id) }
        )
    }

    private func value(of entity: ActivityEntity) throws -> ActivityRecord {
        guard let sport = Sport(rawValue: entity.sportRaw) else {
            throw StoreError.unreadableMetadata("activity \(entity.id)")
        }
        var headline: ActivityRecord.Headline?
        if let kind = entity.headlineKind {
            if let value = entity.headlineValue {
                headline = .init(kind: kind, value: .available(value))
            } else if let reason = entity.headlineUnavailableReason {
                headline = .init(kind: kind, value: .unavailable(UnavailableReason(rawValue: reason)))
            } else {
                throw StoreError.unreadableMetadata("activity \(entity.id) headline")
            }
        }
        let members = try entity.members.map { try Self.identity(canonical: $0.key) }.sorted()
        return ActivityRecord(
            members: members,
            primary: try Self.identity(canonical: entity.primaryKey),
            sport: sport,
            start: entity.start,
            utcOffset: entity.utcOffset,
            elapsedTime: entity.elapsedTime,
            timerTime: entity.timerTime,
            movingTime: entity.movingTime,
            distance: entity.distance,
            ascent: entity.ascent,
            isIndoor: entity.isIndoor,
            isVirtual: entity.isVirtual,
            title: entity.title,
            headline: headline,
            isHidden: entity.isHidden
        )
    }

    private func value(of entity: DerivedResultEntity) throws -> DerivedResult {
        var reading: ProfileReading?
        if let date = entity.profileReadingDate, let inputs = entity.profileReadingInputs {
            reading = ProfileReading(date: date, inputs: AthleteProfile.Inputs(rawValue: inputs))
        }
        return DerivedResult(
            owner: ResultOwner(rawValue: entity.owner),
            kind: entity.kind,
            provenance: Provenance(
                inputRevision: ContentHash(hex: entity.inputRevision),
                profileFingerprint: entity.profileFingerprint.map(ContentHash.init(hex:)),
                algorithmVersion: entity.algorithmVersion
            ),
            profileReading: reading,
            payload: entity.payload,
            computedAt: entity.computedAt
        )
    }
}
