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
            NavigationStack {
                if ready { RoutesView(libraryModel: model).navigationTitle("Routes") }
                else { Text(error ?? "Loading fixtures") }
            }
            .tint(AppTheme.cyan.color)
            .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("dark") ? .dark : .light)
            .task {
                do {
                    let root = URL.documentsDirectory.appending(path: "RouteHarnessLibrary")
                    try? FileManager.default.removeItem(at: root)
                    UserDefaults.standard.set(false, forKey: "routes.includeOlderHistory")
                    let library = try ActivityLibrary(root: root)
                    if !ProcessInfo.processInfo.arguments.contains("empty") {
                        let count = ProcessInfo.processInfo.arguments.contains("review") ? 6 : 5
                        for index in 0..<count {
                            let start = Date().addingTimeInterval(-Double(index + 1) * 86400)
                            let offset = index == 5 ? -14.0 : 0
                            let samples = (0...1000).map { second in
                                NativeSample(timestamp: start.addingTimeInterval(Double(second)),
                                    position: Coordinate(latitude: 42.34 + offset / 111_195, longitude: -71.12 + Double(second) * 2 / 82_200),
                                    distance: Double(second) * 2, speed: 2)
                            }
                            let activity = RecordedActivity(sport: .cycling, stated: StatedSummary(start: start, end: start.addingTimeInterval(1000), timerTime: 1000), stream: NativeStream(samples: samples))
                            let snapshot = HealthSnapshot(workoutID: UUID(), activity: activity, sourceName: "Synthetic route fixture", sourceBundleIdentifier: "test.routes")
                            try await library.importHealthSnapshot(snapshot)
                            if let request = try await library.localityRequest(for: snapshot.identity) {
                                try await library.setLocality("Brookline", for: request)
                            }
                        }
                    }
                    if ProcessInfo.processInfo.arguments.contains("error") { try Data("invalid".utf8).write(to: root.appending(path: "route-decisions-v1.json")) }
                    await model.useFixtureLibrary(library)
                    ready = true
                } catch { self.error = String(describing: error) }
            }
        }
    }
}
