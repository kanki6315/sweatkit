import SwiftUI
import SweatKitLibrary
import SweatKitStore

@main struct PlaybackHarness: App {
    @State private var library: ActivityLibrary?
    @State private var activities: [ActivityRecord] = []
    @State private var error: String?
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                List {
                    ForEach(activities, id: \.id) { activity in
                        NavigationLink(activity.isVirtual ? "Indoor fixture" : activity.sport.family == .cycling ? "Ride fixture" : "Walk fixture") {
                            ActivityDetailView(activity: activity, library: library)
                        }
                    }
                    if let error { Text(error) }
                }.task {
                    guard library == nil else { return }
                    do {
                        let value = try ActivityLibrary(root: URL.documentsDirectory.appending(path: "PlaybackFixtures"))
                        for name in ["outdoor-ride", "walk", "zwift-ride"] {
                            try await value.importFile(Data(contentsOf: Bundle.main.url(forResource: name, withExtension: "fit")!))
                        }
                        activities = try await value.feed(.init(), limit: 10).activities
                        library = value
                    } catch { self.error = String(describing: error) }
                }
            }
        }
    }
}
