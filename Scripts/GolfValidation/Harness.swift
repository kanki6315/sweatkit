import SwiftUI
import SweatKitLibrary
import SweatKitModel
import SweatKitStore

@main struct GolfHarness: App {
    @State private var library: ActivityLibrary?
    @State private var activity: ActivityRecord?
    @State private var error: String?
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                if let library, let activity {
                    NavigationLink("Open synthetic golf recording") {
                        ActivityDetailView(activity: activity, library: library)
                    }
                } else { Text(error ?? "Preparing synthetic recording") }
            }
            .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("dark") ? .dark : .light)
            .task {
                do {
                    let store = try ActivityLibrary(root: URL.documentsDirectory.appending(path: UUID().uuidString))
                    let start = Date(timeIntervalSince1970: 1_700_000_000)
                    let empty = ProcessInfo.processInfo.arguments.contains("empty")
                    // Test data only: two separated clusters prove no connecting line
                    // or chart interpolation is introduced across the gap.
                    let times = [0, 1, 2, 1800, 1801, 1802]
                    let samples = empty ? [] : times.map { second in
                        NativeSample(timestamp: start.addingTimeInterval(Double(second)),
                            position: Coordinate(latitude: 35.1 + Double(second) * 0.000001,
                                                 longitude: -80.9 + Double(second) * 0.000001),
                            altitude: Double(second % 3) + 50, speed: 0,
                            heartRate: Double(second % 3) + 100)
                    }
                    let native = RecordedActivity(sport: .other,
                        stated: StatedSummary(start: start, end: start.addingTimeInterval(3600),
                                              timerTime: 3500, distance: empty ? nil : 2500),
                        stream: NativeStream(samples: samples))
                    let snapshot = HealthSnapshot(workoutID: UUID(), activity: native,
                        sourceName: "Synthetic test recorder", sourceBundleIdentifier: "test.golf",
                        sourceSportName: "Golf")
                    let result = try await store.importHealthSnapshot(snapshot)
                    library = store
                    activity = result.activity
                } catch { self.error = String(describing: error) }
            }
        }
    }
}
