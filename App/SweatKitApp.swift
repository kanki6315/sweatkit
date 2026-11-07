import SwiftUI

@main
struct SweatKitApp: App {
    @UIApplicationDelegateAdaptor(SweatKitAppDelegate.self) private var delegate
    @State private var library = AppServices.library

    var body: some Scene {
        WindowGroup {
            RootView(library: library)
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            await library.open()
            async let garminRefresh: Void? = library.garmin?.sync(.quick, continued: false)
            async let healthRefresh: Void? = library.health?.sync(continued: false)
            _ = await (garminRefresh, healthRefresh)
            await library.cloud?.sync()
            await BackgroundRefresh.schedule()
        }
    }
}
