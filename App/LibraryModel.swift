import Foundation
import Observation
import SweatKitModel
import SweatKitLibrary
import SweatKitStore

/// Owns the persistent library and the visible page, shared by all app screens.
@MainActor @Observable
final class LibraryModel {
    private(set) var health: HealthConnection?
    private(set) var garmin: GarminConnection?
    private(set) var library: ActivityLibrary?
    private(set) var staleIDs: Set<SourceIdentity> = []
    private(set) var isRecomputing = false
    private(set) var possibleDuplicateCount = 0
    private(set) var units = UnitSystem.metric
    private(set) var weekSummaries: [Date: FeedWeekSummary] = [:]
    private(set) var revisions: [SourceIdentity: ContentHash] = [:]
    private(set) var removedSources: Set<SourceIdentity> = []
    private(set) var activities: [ActivityRecord] = []
    private(set) var isLoading = false
    private(set) var isImporting = false
    private(set) var importProgress: ImportProgress?
    private(set) var outcomes: [ImportFileOutcome] = []
    var error: String?
    var filter = FeedFilter()
    private var cursor: FeedCursor?
    private var generation = 0
    var routeRefreshTask: Task<Void, Never>?
    private var importTask: Task<Void, Never>?
    private let localityResolver = ActivityLocalityResolver()
    var hasMore: Bool { cursor != nil }

    func open() async {
        guard library == nil else { return }
        do {
            let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                   appropriateFor: nil, create: true)
                .appendingPathComponent("SweatKit", isDirectory: true)
            let opened = try ActivityLibrary(root: root)
            library = opened
            garmin = GarminConnection(library: opened, root: root)
            health = HealthConnection(library: opened, root: root)
            await garmin?.recoverDeletionCleanup()
            await reload()
        } catch { self.error = error.localizedDescription }
    }

    func reload() async {
        generation += 1
        let request = generation
        guard let library else { return }
        isLoading = true
        do {
            let page = try await library.feed(filter, limit: 50)
            let profile = try await library.profile()
            let duplicates = try await library.possibleDuplicates()
            let sources = try await library.store.sourceRecords()
            let weeks = try await library.weeklySummaries(filter)
            let stale = try await library.staleActivities()
            guard request == generation else { return }
            activities = page.activities
            staleIDs = Set(stale.map(\.id))
            weekSummaries = Dictionary(uniqueKeysWithValues: weeks.map { ($0.start, $0) })
            units = profile.units
            possibleDuplicateCount = duplicates.count
            revisions = Dictionary(uniqueKeysWithValues: sources.map { ($0.identity, $0.currentRevision) })
            removedSources = Set(sources.filter { $0.state == .removedAtSource }.map(\.identity))
            cursor = page.next
            error = nil
            resolveLocalities()
            scheduleRouteMatching()
        } catch {
            guard request == generation else { return }
            self.error = error.localizedDescription
        }
        if request == generation { isLoading = false }
    }

    func loadMore() async {
        guard let library, let cursor, !isLoading else { return }
        let request = generation
        isLoading = true
        defer { if request == generation { isLoading = false } }
        do {
            let page = try await library.feed(filter, limit: 50, after: cursor)
            guard request == generation else { return }
            let existing = Set(activities.compactMap(\.id))
            activities += page.activities.filter { !existing.contains($0.id ?? $0.primary) }
            self.cursor = page.next
            resolveLocalities()
        } catch { if request == generation { self.error = error.localizedDescription } }
    }

    func importFiles(_ urls: [URL]) {
        guard let library, !isImporting else { return }
        isImporting = true
        outcomes = []
        importProgress = nil
        importTask = Task {
            let scoped = urls.filter { $0.startAccessingSecurityScopedResource() }
            defer {
                scoped.forEach { $0.stopAccessingSecurityScopedResource() }
                isImporting = false
                importTask = nil
            }
            outcomes = await library.importFiles(urls.map(ImportFile.init(url:))) { [self] progress in
                Task { @MainActor in self.importProgress = progress }
            }
            await reload()
        }
    }

    func recompute() async {
        guard let library, !isRecomputing else { return }
        isRecomputing = true
        defer { isRecomputing = false }
        do {
            let report = try await library.recompute()
            await reload()
            if !report.failures.isEmpty {
                error = "\(report.failures.count) activities couldn't be recalculated. Their originals are kept; try recalculating again."
            }
        } catch { self.error = error.localizedDescription }
    }

    private func resolveLocalities() {
        guard let library else { return }
        localityResolver.enqueue(activities.compactMap(\.id), library: library) { [weak self] in
            await self?.reload()
        }
    }

    func permanentlyDelete(_ id: SourceIdentity) async throws {
        guard let library else { throw LibraryError.unknownActivity(id) }
        if let garmin { try await garmin.permanentlyDelete(id) }
        else { try await library.permanentlyDelete(id) }
        await reload()
    }

    func cancelImport() { importTask?.cancel() }
}
