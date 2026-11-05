import SwiftUI

/// The three tabs. Settings opens from the profile button on each.
struct RootView: View {
    @State private var showsSettings = false

    var body: some View {
        TabView {
            Tab("Activities", systemImage: "list.bullet") {
                screen("Activities") {
                    ContentUnavailableView(
                        "No activities yet",
                        systemImage: "figure.outdoor.cycle",
                        description: Text("Activities from Garmin, Apple Health and FIT files will appear here.")
                    )
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
                    ContentUnavailableView(
                        "No trends yet",
                        systemImage: "chart.xyaxis.line",
                        description: Text("Volume, power and records build up as activities are added.")
                    )
                }
            }
        }
        .sheet(isPresented: $showsSettings) {
            SettingsView()
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
    RootView()
}
