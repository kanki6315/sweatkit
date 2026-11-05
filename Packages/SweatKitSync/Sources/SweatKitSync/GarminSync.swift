import Foundation
import SweatKitGarmin
import SweatKitModel

/// Garmin sync as reconciliation (spec, "Data sources and sync").
///
/// Garmin's search filters only by local start date and pages by offset, with
/// no change feed, so each run lists date ranges and compares each entry with
/// the library's record of the same identity:
///
/// - A **quick sync** lists start dates from 30 days before today, open-ended.
/// - A **pass over history** lists every local-time calendar month from the
///   earliest activity to today, newest first. The first pass is the backfill;
///   later ones are the weekly deep scan, or a full reconciliation on request.
///   A month counts only when two listings of it in a row return the same set
///   of identities.
///
/// Requests are paced. The first rate-limit response stops the run and the
/// stated wait is honoured. Checkpoints are saved after every month, so the
/// next run resumes where this one stopped.
public actor GarminSync {
    private let remote: any GarminRemoteSource
    private let library: any GarminLibrary
    private let clock: any SyncClock
    private let calendar: Calendar
    public let configuration: SyncConfiguration
    private var running = false
    /// Carried across runs so pacing holds between them too.
    private var lastRequest: Date?

    /// - Parameter calendar: Its time zone sets "today" and the local-time months.
    public init(
        remote: any GarminRemoteSource,
        library: any GarminLibrary,
        clock: any SyncClock = SystemSyncClock(),
        calendar: Calendar = .current,
        configuration: SyncConfiguration = SyncConfiguration()
    ) {
        precondition(configuration.pageOverlap >= 0 && configuration.pageOverlap < configuration.pageSize)
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        self.remote = remote
        self.library = library
        self.clock = clock
        self.calendar = gregorian
        self.configuration = configuration
    }

    public func run(
        _ run: SyncRun,
        onProgress: (@Sendable (SyncProgress) async -> Void)? = nil
    ) async -> SyncReport {
        guard !running else { return SyncReport(outcome: .alreadyRunning) }
        running = true
        defer { running = false }
        let reconciler = Reconciler(remote: remote, library: library, clock: clock, calendar: calendar, configuration: configuration, lastRequest: lastRequest, onProgress: onProgress)
        let report = await reconciler.execute(run)
        lastRequest = await reconciler.lastRequest
        return report
    }
}

/// Why a run stops early.
enum Stop: Error {
    case rateLimited(until: Date)
    case keyRefused
    case tokenRefused
    case cancelled
    case library
    /// Any other remote failure. Fatal for a listing, recorded per activity for
    /// a download.
    case remote(GarminError)
}

/// One run's work and state.
actor Reconciler {
    let remote: any GarminRemoteSource
    let library: any GarminLibrary
    let clock: any SyncClock
    let calendar: Calendar
    let configuration: SyncConfiguration
    private(set) var lastRequest: Date?

    private var state = GarminSyncState()
    private var known: [Int64: KnownGarminActivity] = [:]
    private var tombstoned: Set<Int64> = []
    private var report = SyncReport(outcome: .completed)
    private let onProgress: (@Sendable (SyncProgress) async -> Void)?
    private var lastProgress = SyncProgress(added: 0, updated: 0)
    /// Activities that already failed in this run, so they are not tried twice.
    private var failedThisRun: Set<Int64> = []

    init(remote: any GarminRemoteSource, library: any GarminLibrary, clock: any SyncClock, calendar: Calendar, configuration: SyncConfiguration, lastRequest: Date?, onProgress: (@Sendable (SyncProgress) async -> Void)?) {
        self.remote = remote
        self.library = library
        self.clock = clock
        self.calendar = calendar
        self.configuration = configuration
        self.lastRequest = lastRequest
        self.onProgress = onProgress
    }

    func execute(_ run: SyncRun) async -> SyncReport {
        await onProgress?(lastProgress)
        do {
            state = try await library.loadSyncState() ?? GarminSyncState()
            for (identity, activity) in try await library.knownGarminActivities() {
                if let id = identity.garminActivityID { known[id] = activity }
            }
            tombstoned = Set(try await library.garminTombstones().compactMap(\.garminActivityID))
        } catch {
            report.outcome = .libraryFailed
            return report
        }

        if let until = state.rateLimitedUntil {
            if clock.now < until {
                report.outcome = .rateLimited(until: until)
                return finishedReport()
            }
            state.rateLimitedUntil = nil
        }

        do {
            switch run {
            case .quick:
                try await quickSync()
                try await retryPending()
            case .routine:
                try await quickSync()
                try await retryPending()
                if passIsOwed { try await historyPass(starting: nil) }
            case .fullReconciliation(let redownload):
                try await retryPending()
                try await historyPass(starting: HistoryPass(kind: .fullReconciliation, redownload: redownload, started: clock.now))
            }
            report.outcome = .completed
        } catch let stop as Stop {
            switch stop {
            case .rateLimited(let until):
                state.rateLimitedUntil = until
                report.outcome = .rateLimited(until: until)
            case .keyRefused: report.outcome = .keyRefused
            case .tokenRefused: report.outcome = .tokenRefused
            case .cancelled: report.outcome = .interrupted
            case .library: report.outcome = .libraryFailed
            case .remote(let error): report.outcome = .listingFailed(error)
            }
        } catch {
            report.outcome = .libraryFailed
        }

        do {
            try await library.saveSyncState(state)
        } catch {
            report.outcome = .libraryFailed
        }
        return finishedReport()
    }

    private func finishedReport() -> SyncReport {
        report.outstanding = state.pending.count
        if let pass = state.pass {
            report.pass = .inProgress(pass.kind, completedMonths: pass.completed.count)
        }
        return report
    }

    // MARK: Depths

    private var today: CalendarDate { CalendarDate(clock.now, in: calendar) }

    /// The first-sync backfill until it finishes, an interrupted pass, or a deep
    /// scan a week after the last pass finished.
    private var passIsOwed: Bool {
        guard state.pass == nil, state.backfillFinished != nil, let last = state.lastPassFinished else { return true }
        return clock.now >= last.addingTimeInterval(configuration.deepScanInterval)
    }

    /// Start dates in the last 30 days plus anything newer, listed once.
    ///
    /// Removals are inferred only when the listing came back as one page: one
    /// response is a consistent view of the range, while offset pages fetched
    /// apart can miss an entry that shifted between them. A quick sync that
    /// needs paging leaves removals in its window to the deep scan.
    private func quickSync() async throws {
        let range = DateRange(start: today.adding(days: -configuration.quickSyncDays), end: nil)
        let listing = try await listRange(range)
        try await apply(listing.entries, redownload: .none)
        if listing.pages == 1 {
            try await inferRemovals(in: range, listed: listing.entries)
        }
        state.lastQuickSync = clock.now
    }

    /// Activities that failed before and that this run's listings did not
    /// already handle.
    private func retryPending() async throws {
        for id in state.pending.keys.sorted() where !failedThisRun.contains(id) {
            guard let pending = state.pending[id] else { continue }
            try await reconcile(pending.summary, force: pending.forceDownload)
            await publishProgress()
        }
    }

    /// Walks every local-time month of history, newest first, resuming at the
    /// first month this pass has neither completed nor left unsettled.
    private func historyPass(starting newPass: HistoryPass?) async throws {
        if let newPass {
            state.pass = newPass
        } else if state.pass == nil {
            state.pass = HistoryPass(kind: state.backfillFinished == nil ? .backfill : .deepScan, started: clock.now)
        }
        try await save()

        // One ascending request finds the earliest activity. It is asked again
        // on every pass, so an old ride uploaded later widens the history. The
        // earliest local record is included too, so a record whose month Garmin
        // no longer lists can still be found removed.
        let earliestRemote = try await list(ActivityQuery(start: 0, limit: 1, order: .ascending)).first?.startDate
        let earliestLocal = known.filter { !tombstoned.contains($0.key) }.compactMap(\.value.summary.startDate).min()
        let thisMonth = CalendarMonth(containing: today)
        if let earliest = [earliestRemote, earliestLocal].compactMap({ $0 }).min() {
            let oldest = min(CalendarMonth(containing: earliest), thisMonth)
            var month: CalendarMonth? = thisMonth
            while let current = month, current >= oldest {
                if Task.isCancelled { throw Stop.cancelled }
                defer { month = current.previous }
                guard let pass = state.pass, !pass.completed.contains(current), !pass.unsettled.contains(current) else { continue }
                // The newest month is open-ended, which takes in anything
                // dated after today.
                let range = DateRange(current, openEnded: current == thisMonth)
                if let settled = try await settle(range) {
                    try await apply(settled.entries, redownload: pass.redownload)
                    try await inferRemovals(in: range, listed: settled.entries)
                    state.pass?.completed.insert(current)
                } else {
                    state.pass?.unsettled.insert(current)
                    report.unsettledMonths.append(current)
                }
                try await save()
            }
        }

        let finished = state.pass
        state.pass = nil
        state.lastPassFinished = clock.now
        if state.backfillFinished == nil { state.backfillFinished = clock.now }
        state.unsettledMonths = finished?.unsettled ?? []
        report.pass = .finished(finished?.kind ?? .deepScan)
        try await save()
    }

    private func publishProgress() async {
        let progress = SyncProgress(added: report.added.count, updated: report.revised.count)
        guard progress != lastProgress else { return }
        lastProgress = progress
        await onProgress?(progress)
    }

    // MARK: Listing

    struct Listing {
        var entries: [Int64: GarminSummary] = [:]
        var pages = 0
        /// Every page shared at least one entry with the overlap of the page
        /// before, so no entry can have slipped between them.
        var joined = true
    }

    /// One listing of a range: offset pages with an overlap, until a short page.
    private func listRange(_ range: DateRange) async throws -> Listing {
        let size = configuration.pageSize
        let overlap = configuration.pageOverlap
        var listing = Listing()
        var offset = 0
        var previous: [GarminSummary] = []
        while true {
            let page = try await list(ActivityQuery(start: offset, limit: size, order: .descending, startDate: range.start, endDate: range.end))
            listing.pages += 1
            if !previous.isEmpty, overlap > 0 {
                let tail = Set(previous.suffix(overlap).map(\.activityID))
                if !page.contains(where: { tail.contains($0.activityID) }) { listing.joined = false }
            }
            for entry in page { listing.entries[entry.activityID] = entry }
            if page.count < size { return listing }
            guard listing.pages < configuration.maximumPagesPerListing else {
                throw Stop.remote(.unexpectedResponse(UnexpectedResponse(status: 200, reason: .status)))
            }
            offset += size - overlap
            previous = page
        }
    }

    /// Lists a range until two listings in a row return the same set of
    /// identities, both with joined pages. After the first two differ it is
    /// listed again up to three more times: at most five listings. Returns nil
    /// when it does not settle.
    private func settle(_ range: DateRange) async throws -> Listing? {
        var previous = try await listRange(range)
        for _ in 0...configuration.maximumRelistings {
            let current = try await listRange(range)
            if previous.joined, current.joined, Set(previous.entries.keys) == Set(current.entries.keys) {
                return current
            }
            previous = current
        }
        return nil
    }

    // MARK: Reconciling

    /// Reconciles listed entries, newest first.
    private func apply(_ entries: [Int64: GarminSummary], redownload: Redownload) async throws {
        let ordered = entries.values.sorted {
            ($0.startTimeLocal ?? "", $0.activityID) > ($1.startTimeLocal ?? "", $1.activityID)
        }
        for entry in ordered {
            try await reconcile(entry, force: redownload.includes(entry.identity))
            await publishProgress()
        }
    }

    /// Compares one listed entry with the library's record of the same identity.
    ///
    /// - Tombstoned: ignored, never brought back.
    /// - Unknown: downloaded and ingested as a new record.
    /// - Known: the file is downloaded again when the start, duration or
    ///   distance changed, on request, or when an earlier attempt failed. A new
    ///   hash is a new revision; the same hash changes nothing but the summary.
    ///   Otherwise a changed summary only updates the metadata.
    private func reconcile(_ entry: GarminSummary, force: Bool) async throws {
        let id = entry.activityID
        let identity = entry.identity
        if tombstoned.contains(id) {
            state.pending[id] = nil
            return
        }
        guard !failedThisRun.contains(id) else { return }

        if let existing = known[id], existing.removedAtSource {
            do {
                try await library.markPresentAtSource(identity)
                known[id]?.removedAtSource = false
                report.presentAgain.append(identity)
            } catch {
                return fail(entry, force: force, reason: .libraryRejected)
            }
        }

        let existing = known[id]
        let wantsFile = existing == nil
            || force
            || existing?.contentHash == nil
            || state.pending[id] != nil
            || existing?.summary.fileTriggers != entry.fileTriggers

        if !wantsFile {
            if let existing, existing.summary != entry {
                do {
                    try await library.updateSummary(entry, for: identity)
                    known[id]?.summary = entry
                    report.summariesUpdated.append(identity)
                } catch {
                    fail(entry, force: force, reason: .libraryRejected)
                }
            }
            return
        }

        let original: Data
        do {
            let download = try await self.download(id)
            original = try GarminOriginal.extract(from: download)
        } catch is ZipError {
            return fail(entry, force: force, reason: .unreadableDownload)
        } catch Stop.remote(let error) {
            return fail(entry, force: force, reason: SyncFailure(error))
        }
        let hash = ContentHash(of: original)

        do {
            if let existing, existing.contentHash == hash {
                if existing.summary != entry {
                    try await library.updateSummary(entry, for: identity)
                    report.summariesUpdated.append(identity)
                }
                report.unchangedDownloads.append(identity)
            } else {
                try await library.ingestOriginal(original, contentHash: hash, as: identity, summary: entry)
                if existing == nil { report.added.append(identity) } else { report.revised.append(identity) }
            }
        } catch {
            return fail(entry, force: force, reason: .libraryRejected)
        }
        known[id] = KnownGarminActivity(summary: entry, contentHash: hash, removedAtSource: false)
        state.pending[id] = nil
    }

    private func fail(_ entry: GarminSummary, force: Bool, reason: SyncFailure) {
        let id = entry.activityID
        let earlier = state.pending[id]
        state.pending[id] = PendingActivity(
            summary: entry,
            forceDownload: force || (earlier?.forceDownload ?? false),
            attempts: (earlier?.attempts ?? 0) + 1,
            lastFailure: reason
        )
        failedThisRun.insert(id)
        report.failures[entry.identity] = reason
    }

    /// After a complete listing of `range`: every known, untombstoned record
    /// whose local start date is in the range and that the listing lacks is
    /// removed at the source. Retries waiting for such activities are dropped.
    private func inferRemovals(in range: DateRange, listed: [Int64: GarminSummary]) async throws {
        for id in state.pending.keys.sorted() {
            guard listed[id] == nil, let date = state.pending[id]?.summary.startDate, range.contains(date) else { continue }
            state.pending[id] = nil
        }
        for id in known.keys.sorted() {
            guard let record = known[id], listed[id] == nil, !record.removedAtSource, !tombstoned.contains(id),
                  let date = record.summary.startDate, range.contains(date) else { continue }
            do {
                try await library.markRemovedAtSource(.garminActivity(id))
                known[id]?.removedAtSource = true
                report.removedAtSource.append(.garminActivity(id))
            } catch {
                report.failures[.garminActivity(id)] = .libraryRejected
            }
        }
    }

    // MARK: Requests

    private func list(_ query: ActivityQuery) async throws -> [GarminSummary] {
        try await pace()
        do {
            return try await remote.listActivities(query)
        } catch {
            throw stop(for: error)
        }
    }

    private func download(_ id: Int64) async throws -> Data {
        try await pace()
        do {
            return try await remote.downloadOriginal(id: id)
        } catch {
            throw stop(for: error)
        }
    }

    /// Waits until the request interval has passed since the last request.
    private func pace() async throws {
        if Task.isCancelled { throw Stop.cancelled }
        if let lastRequest {
            let next = lastRequest.addingTimeInterval(configuration.requestInterval)
            if clock.now < next {
                do { try await clock.sleep(until: next) } catch { throw Stop.cancelled }
            }
        }
        lastRequest = clock.now
        report.requests += 1
    }

    private func stop(for error: GarminError) -> Stop {
        switch error {
        case .rateLimited(let retryAfter):
            .rateLimited(until: clock.now.addingTimeInterval(retryAfter ?? configuration.defaultRateLimitWait))
        case .keyRejected: .keyRefused
        case .tokenExpired: .tokenRefused
        case .network(.cancelled): .cancelled
        default: .remote(error)
        }
    }

    private func save() async throws {
        do { try await library.saveSyncState(state) } catch { throw Stop.library }
    }
}

extension SyncFailure {
    init(_ error: GarminError) {
        switch error {
        case .network: self = .network
        case .unexpectedResponse(let response): self = .server(status: response.status)
        default: self = .server(status: 0)
        }
    }
}
