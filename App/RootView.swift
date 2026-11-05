import SwiftUI

/// The three tabs. Settings opens from the profile button on each.
struct RootView: View {
    @State private var showsSettings = false
    @AppStorage(AppTheme.preferenceKey) private var accent = AppTheme.cyan.rawValue
    let library: LibraryModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            Tab("Activities", systemImage: "list.bullet") {
                NavigationStack {
                    ActivityFeedView(model: library)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Settings", systemImage: "person.crop.circle") { showsSettings = true }
                            }
                        }
                }
            }
            Tab("Routes", systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
                screen("Routes") {
                    ContentUnavailableView(
                        "No routes yet",
                        systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                        description: Text("A course becomes a route the second time you do it.")
                    )
                }
            }
            Tab("Trends", systemImage: "chart.xyaxis.line") {
                screen("Trends") {
                    TrendsView(model: library)
                }
            }
        }
        .tint((AppTheme(rawValue: accent) ?? .cyan).color)
        .task(id: scenePhase) {
            if scenePhase == .active {
                await library.open()
                async let garminRefresh: Void? = library.garmin?.sync()
                async let healthRefresh: Void? = library.health?.sync()
                _ = await (garminRefresh, healthRefresh)
                await library.reload()
            } else if scenePhase == .background {
                BackgroundRefresh.schedule()
            }
        }
        .sheet(isPresented: $showsSettings) {
            SettingsView(model: library)
        }
    }

    private func screen(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        NavigationStack {
            content()
                .navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Settings", systemImage: "person.crop.circle") {
                            showsSettings = true
                        }
                    }
                }
        }
    }
}

#Preview {
    RootView(library: LibraryModel())
}
