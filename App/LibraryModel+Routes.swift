import Foundation
import SweatKitLibrary

extension LibraryModel {
    /// Rebuild after import/sync, identity edits, restoration and profile changes.
    /// The matching work runs off the main actor; opening the Routes tab also
    /// refreshes, making failures retryable without depending on this warm-up.
    func scheduleRouteMatching() {
        routeRefreshTask?.cancel()
        guard let library else { return }
        routeCatalog = RouteCatalog(routes: [], reviews: [])
        routeRefreshTask = Task(priority: .utility) {
            do {
                let result = try await library.routes()
                try Task.checkCancellation()
                routeCatalog = result
            }
            catch { /* Routes presents actionable errors on its own refresh. */ }
        }
    }
    func scheduleRecordBadges() {
        historyRefreshTask?.cancel()
        recordBadges = [:]
        guard let library else { return }
        let ids = activities.compactMap(\.id)
        historyRefreshTask = Task(priority: .utility) {
            do {
                let history = try await library.trendsHistory()
                let badges = await Task.detached(priority: .utility) {
                    Dictionary(uniqueKeysWithValues: ids.map { ($0, TrendsAggregation.recordBadges(for: $0, in: history.activities)) })
                }.value
                try Task.checkCancellation()
                recordBadges = badges
            } catch { /* Missing badges never imply a record or block browsing. */ }
        }
    }
}
