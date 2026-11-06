import SwiftUI
import SweatKitLibrary
import SweatKitModel
import SweatKitStore

@main struct ScrollHarness: App {
    @State private var model = LibraryModel()
    @State private var ready = false
    @State private var status = "Preparing scroll fixtures"
    var body: some Scene {
        WindowGroup {
            Group {
                if ready { RootView(library: model) }
                else { Text(status) }
            }
            .task {
                guard !ready else { return }
                do {
                    let root = URL.documentsDirectory.appending(path: "ScrollLibrary")
                    try? FileManager.default.removeItem(at: root)
                    let library = try ActivityLibrary(root: root)
                    for index in 0..<110 {
                        let start = Date(timeIntervalSince1970: 1_790_000_000 - Double(index) * 86400)
                        let samples = (0...60).map { second in
                            NativeSample(timestamp: start.addingTimeInterval(Double(second)),
                                         distance: Double(second) * 3, speed: 3, heartRate: Double(120 + second % 30))
                        }
                        let activity = RecordedActivity(sport: .walking,
                            stated: StatedSummary(start: start, end: start.addingTimeInterval(60), timerTime: 60),
                            stream: NativeStream(samples: samples))
                        try await library.importHealthSnapshot(HealthSnapshot(workoutID: UUID(), activity: activity,
                            sourceName: "Scroll fixture", sourceBundleIdentifier: "test.scroll"))
                    }
                    await model.useFixtureLibrary(library)
                    guard model.activities.count == 50 else { throw Check.failed("Initial page") }
                    await model.loadMore()
                    let ids = model.activities.map(\.id)
                    guard ids.count == 100 else { throw Check.failed("Second page") }
                    await model.reload(scheduleCloud: false)
                    guard model.activities.map(\.id) == ids else { throw Check.failed("Refresh discarded loaded pages") }
                    await model.loadMore()
                    guard model.activities.count == 110, !model.hasMore else { throw Check.failed("Final page") }
                    model.filter = FeedFilter(titleContains: "NoSuchActivity")
                    await model.reload(scheduleCloud: false)
                    guard model.activities.isEmpty else { throw Check.failed("Filter reset") }
                    model.filter = FeedFilter()
                    await model.reload(scheduleCloud: false)
                    guard model.activities.count == 50 else { throw Check.failed("Filter page reset") }
                    ready = true
                } catch { status = "Regression failed: \(error)" }
            }
        }
    }
    enum Check: Error { case failed(String) }
}
