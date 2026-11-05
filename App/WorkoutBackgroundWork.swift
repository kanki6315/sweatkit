import BackgroundTasks
import UIKit

/// Keeps an in-process operation alive without tying its lifetime to a view.
/// Each request has a unique identifier so a late launch cannot attach to a new run.
@MainActor
final class WorkoutBackgroundWork {
    static let prefix = "com.arjunakankipati.sweatkit.workout"
    private let identifier = "\(prefix).\(UUID().uuidString)"
    private let title: String
    private let cancel: @MainActor () -> Void
    private var task: BGContinuedProcessingTask?
    private var fallback = UIBackgroundTaskIdentifier.invalid
    private var finished = false
    private var completed: Int64 = 0
    private var total: Int64 = 1

    init(title: String, continued: Bool, cancel: @escaping @MainActor () -> Void) {
        self.title = title
        self.cancel = cancel
        BackgroundRefresh.scheduleProcessing()
        // Covers submission/launch latency and devices that refuse continuation.
        if UIApplication.shared.applicationState == .active {
            fallback = UIApplication.shared.beginBackgroundTask(withName: title) { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.cancel()
                    self.finish(success: false)
                }
            }
        }
        guard continued, UIApplication.shared.applicationState == .active else { return }
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { [weak self] task in
            MainActor.assumeIsolated {
                guard let self else { task.setTaskCompleted(success: false); return }
                guard let continuedTask = task as? BGContinuedProcessingTask, !self.finished else {
                    task.setTaskCompleted(success: false)
                    return
                }
                self.task = continuedTask
                continuedTask.expirationHandler = { [weak self] in
                    Task { @MainActor in
                        guard let self else { return }
                        self.cancel()
                        self.finish(success: false)
                    }
                }
                self.update(completed: Int(self.completed), total: Int(self.total))
                self.endFallback()
            }
        }
        guard registered else { return }
        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: title,
                                                       subtitle: "Processing workouts")
        // Work has already started; do not leave a second queued operation behind.
        request.strategy = .fail
        do { try BGTaskScheduler.shared.submit(request) }
        catch { /* The finite background assertion and saved checkpoints remain usable. */ }
    }

    func update(completed: Int, total: Int) {
        guard !finished else { return }
        self.completed = Int64(completed)
        self.total = Int64(max(total, completed + 1))
        task?.progress.totalUnitCount = self.total
        task?.progress.completedUnitCount = self.completed
        task?.updateTitle(title, subtitle: "\(completed) workouts processed")
    }

    func finish(success: Bool) {
        guard !finished else { return }
        finished = true
        if let task {
            task.expirationHandler = nil
            if success { task.progress.completedUnitCount = task.progress.totalUnitCount }
            task.setTaskCompleted(success: success)
            self.task = nil
        } else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        }
        endFallback()
    }

    private func endFallback() {
        if fallback != .invalid {
            UIApplication.shared.endBackgroundTask(fallback)
            fallback = .invalid
        }
    }
}
