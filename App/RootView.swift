import SwiftUI

/// Three browsing tabs and a native bottom search control.
struct RootView: View {
    private enum Destination { case activities, routes, trends, search }
    @State private var selectedTab = Destination.activities
    @State private var searchPresented = false
    @State private var showsSettings = false
    @State private var feedFilters = ActivityFeedFilters()
    @AppStorage(AppTheme.preferenceKey) private var accent = AppTheme.cyan.rawValue
    let library: LibraryModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Activities", systemImage: "figure.outdoor.cycle", value: Destination.activities) {
                NavigationStack {
                    ActivityFeedView(model: library, filters: feedFilters, showSettings: { showsSettings = true })
                }
            }
            Tab("Routes", systemImage: "point.topleft.down.to.point.bottomright.curvepath", value: Destination.routes) {
                screen("Routes") {
                    RoutesView(libraryModel: library)
                }
            }
            Tab("Trends", systemImage: "chart.xyaxis.line", value: Destination.trends) {
                screen("Trends") {
                    TrendsView(model: library)
                }
            }
            Tab("Search", systemImage: "magnifyingglass", value: Destination.search, role: searchTabRole) {
                NavigationStack {
                    ActivityFeedView(model: library, filters: feedFilters, showSettings: { showsSettings = true })
                        .searchable(text: $feedFilters.search, isPresented: $searchPresented, prompt: "Search activity titles")
                }
            }
        }
        .onChange(of: selectedTab) { _, destination in
            searchPresented = destination == .search
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
    }

    private var searchTabRole: TabRole {
        if #available(iOS 27.0, *) { return .prominent }
        return .search
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
