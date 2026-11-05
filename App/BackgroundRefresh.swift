import BackgroundTasks
import Foundation

/// Quick app refresh plus a separate processing task for resumable history.
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

extension BackgroundRefresh {
    static let processingIdentifier = "com.arjunakankipati.sweatkit.processing"

    static func registerProcessing() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: processingIdentifier, using: .main) { task in
            MainActor.assumeIsolated {
                let worker = Task { @MainActor in
                    // Schedule the next opportunity before starting interruptible work.
                    scheduleProcessing()
                    let model = AppServices.library
                    await model.open()
                    async let garmin: Void? = model.garmin?.sync(.routine, continued: false)
                    async let health: Void? = model.health?.sync(continued: false)
                    _ = await (garmin, health)
                    let garminSucceeded = model.garmin.map { !$0.connected || (!$0.running && $0.lastSyncSucceeded) } ?? true
                    let healthSucceeded = model.health.map { !$0.enabled || (!$0.running && $0.lastSyncSucceeded) } ?? true
                    task.expirationHandler = nil
                    task.setTaskCompleted(success: !Task.isCancelled && model.library != nil && garminSucceeded && healthSucceeded)
                }
                task.expirationHandler = { worker.cancel() }
            }
        }
    }

    static func scheduleProcessing() {
        let request = BGProcessingTaskRequest(identifier: processingIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        // Health checkpoints are local; Garmin retains retries when offline.
        request.requiresNetworkConnectivity = false
        do { try BGTaskScheduler.shared.submit(request) }
        catch { /* iOS may defer work; checkpoints are also retried on launch. */ }
    }
}
