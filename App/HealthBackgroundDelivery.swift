import Foundation
import HealthKit
import Observation
import UIKit

@MainActor
enum AppServices {
    static let library = LibraryModel()
}

/// Install observers before returning from launch, including a HealthKit wake
/// that creates no active scene. Never request authorization from this path.
@MainActor
final class SweatKitAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BackgroundRefresh.registerProcessing()
        HealthBackgroundDelivery.shared.start()
        return true
    }
}

@MainActor @Observable
final class HealthBackgroundDelivery {
    static let shared = HealthBackgroundDelivery()
    private(set) var status: String?
    private let store = HKHealthStore()
    private var queries: [HKObserverQuery] = []
    private var completions: [HealthDeliveryCompletion] = []
    private var worker: Task<Void, Never>?
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid

    func start() {
        guard UserDefaults.standard.bool(forKey: "healthReadRequested"), HKHealthStore.isHealthDataAvailable() else { return }
        if queries.isEmpty {
            for type in HealthConnection.observedTypes {
                let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, error in
                    let delivery = HealthDeliveryCompletion(completion)
                    Task { @MainActor in
                        guard let self else { delivery.complete(); return }
                        if error != nil {
                            self.status = "Health background updates are unavailable. Open the app and refresh; saved progress is kept."
                            delivery.complete()
                            return
                        }
                        self.receive(delivery)
                    }
                }
                queries.append(query)
                store.execute(query)
            }
        }
        status = nil
        // Re-register after permission review and on each process launch.
        // A delivery failure never means read permission was denied.
        for type in HealthConnection.observedTypes {
            store.enableBackgroundDelivery(for: type, frequency: .immediate) { [weak self] success, _ in
                if !success {
                    Task { @MainActor in
                        self?.status = "Some Health background updates could not be enabled. Foreground refresh remains available."
                    }
                }
            }
        }
    }

    func pause() { worker?.cancel() }

    private func receive(_ completion: HealthDeliveryCompletion) {
        completions.append(completion)
        guard worker == nil else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Health refresh") { [weak self] in
            Task { @MainActor in self?.worker?.cancel() }
        }
        worker = Task {
            defer {
                completions.forEach { $0.complete() }
                completions.removeAll()
                worker = nil
                if backgroundTask != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTask)
                    backgroundTask = .invalid
                }
            }
            // Bound observer work even when background-task time is unavailable.
            let deadline = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(20)) } catch { return }
                if UIApplication.shared.applicationState != .active { self?.worker?.cancel() }
            }
            defer { deadline.cancel() }
            while !completions.isEmpty && !Task.isCancelled {
                let batch = completions
                completions.removeAll()
                let model = AppServices.library
                await model.open()
                if let health = model.health {
                    await health.sync(continued: false) { batch.forEach { $0.complete() } }
                }
                // Open failures and cancellation retain old anchors. A normal
                // foreground refresh always retries them, with no read prompts.
                batch.forEach { $0.complete() }
                if UIApplication.shared.applicationState == .active { await model.reload() }
            }
        }
    }
}

