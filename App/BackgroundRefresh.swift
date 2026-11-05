import BackgroundTasks
import Foundation

/// Opportunistic quick sync only. Foreground launch/refresh owns deep history.
@MainActor
enum BackgroundRefresh {
    static let identifier = "com.arjunakankipati.sweatkit.refresh"

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do { try BGTaskScheduler.shared.submit(request) }
        catch {
            // iOS may disable or defer refresh. Foreground sync remains usable.
            // Do not turn this optional scheduling failure into a library error.
        }
    }
}
