import SwiftUI

/// Three browsing tabs, with title search integrated into Activities.
struct RootView: View {
    private enum Destination { case activities, routes, trends }
    @State private var selectedTab = Destination.activities
    @State private var showsSettings = false
    @State private var feedFilters = ActivityFeedFilters()
    @AppStorage(AppTheme.preferenceKey) private var accent = AppTheme.cyan.rawValue
    @AppStorage(AppAppearance.preferenceKey) private var appearance = AppAppearance.system.rawValue
    let library: LibraryModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Activities", systemImage: "figure.outdoor.cycle", value: Destination.activities) {
                NavigationStack {
                    ActivityFeedView(model: library, filters: feedFilters, showSettings: { showsSettings = true })
                        .searchable(text: $feedFilters.search, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search activity titles")
                        .scrollDismissesKeyboard(.immediately)
                }
            }
            Tab("Routes", systemImage: "point.topleft.down.to.point.bottomright.curvepath", value: Destination.routes) {
                screen {
                    RoutesView(libraryModel: library)
                }
            }
            Tab("Trends", systemImage: "chart.xyaxis.line", value: Destination.trends) {
                screen {
                    TrendsView(model: library)
                }
            }
        }
        .tint((AppTheme(rawValue: accent) ?? .cyan).color)
        .task(id: scenePhase) {
            if scenePhase == .active {
                library.refreshOnActivation()
            } else if scenePhase == .background {
                BackgroundRefresh.schedule()
                BackgroundRefresh.scheduleProcessing()
            }
        }
        .sheet(isPresented: $showsSettings) {
            SettingsView(model: library)
        }
        .preferredColorScheme((AppAppearance(rawValue: appearance) ?? .system).colorScheme)
    }

    private func screen(@ViewBuilder content: () -> some View) -> some View {
        NavigationStack {
            content()
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
