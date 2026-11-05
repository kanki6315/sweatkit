import SwiftUI

@main
struct SweatKitApp: App {
    @State private var library = LibraryModel()

    var body: some Scene {
        WindowGroup {
            RootView(library: library)
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            await library.open()
            await library.garmin?.sync(.quick)
            await BackgroundRefresh.schedule()
        }
    }
}
