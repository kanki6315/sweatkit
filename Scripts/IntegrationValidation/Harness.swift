import SwiftUI
import SweatKitLibrary
import SweatKitIngest
import SweatKitModel

@main struct RoutesHarness: App {
    @State private var model = LibraryModel()
    @State private var ready = false
    @State private var error: String?
    var body: some Scene {
        WindowGroup {
            Group {
                if ready { RootView(library: model) }
                else { Text(error ?? "Loading fixtures") }
            }
            .tint(AppTheme.cyan.color)
            .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("dark") ? .dark : .light)
            .task {
                do {
                    let root = URL.documentsDirectory.appending(path: "RouteHarnessLibrary")
                    if ProcessInfo.processInfo.arguments.contains("empty") || ProcessInfo.processInfo.arguments.contains("review") { try? FileManager.default.removeItem(at: root) }
                    let library = try ActivityLibrary(root: root)
                    try? FileManager.default.removeItem(at: root.appending(path: "route-decisions-v1.json"))
                    if ProcessInfo.processInfo.arguments.contains("review") {
                        for index in 0..<2 {
                            let start = Date(timeIntervalSince1970: 1_800_000_000 + Double(index) * 86400)
                            let samples = (0...100).map { second in
                                NativeSample(timestamp: start.addingTimeInterval(Double(second)),
                                    position: Coordinate(latitude: (5 + Double(index) * 14) / 111_195, longitude: (10 + Double(second) * 20) / 111_195),
                                    distance: Double(second) * 20, speed: 20)
                            }
                            let activity = RecordedActivity(sport: .cycling, stated: StatedSummary(start: start, end: start.addingTimeInterval(100), timerTime: 100), stream: NativeStream(samples: samples))
                            try await library.importHealthSnapshot(HealthSnapshot(workoutID: UUID(), activity: activity, sourceName: "Synthetic review fixture", sourceBundleIdentifier: "test.routes.review"))
                        }
                    } else if !ProcessInfo.processInfo.arguments.contains("empty") {
                        let url = Bundle.main.url(forResource: "outdoor-ride", withExtension: "fit")!
                        let data = try Data(contentsOf: url)
                        try await library.importFile(data)
                        var recorded = try FITActivityDecoder.decode(data)
                        let shift = 86400.0 * 7
                        recorded.stated.start = recorded.stated.start?.addingTimeInterval(shift)
                        recorded.stated.end = recorded.stated.end?.addingTimeInterval(shift)
                        for i in recorded.stream.samples.indices { recorded.stream.samples[i].timestamp += shift }
                        for i in recorded.timerEvents.indices { recorded.timerEvents[i].timestamp += shift }
                        let start = recorded.stated.start!
                        recorded.stated.end = recorded.stated.end.map { start.addingTimeInterval($0.timeIntervalSince(start) * 0.9) }
                        recorded.stated.timerTime = recorded.stated.timerTime.map { $0 * 0.9 }
                        for i in recorded.stream.samples.indices {
                            recorded.stream.samples[i].timestamp = start.addingTimeInterval(recorded.stream.samples[i].timestamp.timeIntervalSince(start) * 0.9)
                            recorded.stream.samples[i].speed = recorded.stream.samples[i].speed.map { $0 / 0.9 }
                        }
                        for i in recorded.timerEvents.indices { recorded.timerEvents[i].timestamp = start.addingTimeInterval(recorded.timerEvents[i].timestamp.timeIntervalSince(start) * 0.9) }
                        try await library.importHealthSnapshot(HealthSnapshot(workoutID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, activity: recorded, sourceName: "Fixture", sourceBundleIdentifier: "test.routes"))
                    }
                    if ProcessInfo.processInfo.arguments.contains("error") { try Data("invalid".utf8).write(to: root.appending(path: "route-decisions-v1.json")) }
                    for name in ["walk", "zwift-ride"] {
                        let data = try Data(contentsOf: Bundle.main.url(forResource: name, withExtension: "fit")!)
                        try await library.importFile(data)
                    }
                    await model.useFixtureLibrary(library)
                    ready = true
                } catch { self.error = String(describing: error) }
            }
        }
    }
}
