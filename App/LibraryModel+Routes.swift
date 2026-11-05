import Foundation

extension LibraryModel {
    /// Rebuild after import/sync, identity edits, restoration and profile changes.
    /// The matching work runs off the main actor; opening the Routes tab also
    /// refreshes, making failures retryable without depending on this warm-up.
    func scheduleRouteMatching() {
        routeRefreshTask?.cancel()
        guard let library else { return }
        routeRefreshTask = Task(priority: .utility) {
            do { _ = try await library.routes() }
            catch { /* Routes presents actionable errors on its own refresh. */ }
        }
    }
}
