import SwiftUI
import SweatKitLibrary

@main struct TrendsHarness: App {
    @State private var model = LibraryModel()
    @State private var ready = false
    @State private var error: String?
    var body: some Scene {
        WindowGroup {
            Group {
                if ready { NavigationStack { TrendsView(model: model) } }
                else { Text(error ?? "Loading fixtures") }
            }
            .tint(AppTheme.cyan.color)
            .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("dark") ? .dark : .light)
            .task {
                do {
                    let library = try ActivityLibrary(root: URL.documentsDirectory.appending(path: "TrendsFixtures"))
                    for name in ["outdoor-ride", "walk", "zwift-ride"] {
                        let url = Bundle.main.url(forResource: name, withExtension: "fit")!
                        try await library.importFile(Data(contentsOf: url))
                    }
                    await model.useFixtureLibrary(library)
                    ready = true
                } catch { self.error = String(describing: error) }
            }
        }
    }
}
