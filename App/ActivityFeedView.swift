import SwiftUI
import UniformTypeIdentifiers
import SweatKitModel
import SweatKitStore

struct ActivityFeedView: View {
    @Bindable var model: LibraryModel
    @State private var showsImporter = false
    @State private var showsResults = false
    @State private var search = ""
    @State private var sport: Sport?
    @State private var setting: FeedFilter.Setting?

    var body: some View {
        List {
            if let health = model.health, health.enabled {
                Section {
                    Text(health.status).font(.subheadline)
                    if health.running { Button("Pause Health refresh") { health.pause() } }
                }
            }
            if model.possibleDuplicateCount > 0, let library = model.library {
                NavigationLink {
                    LibraryReviewView(library: library)
                } label: {
                    Label("Review \(model.possibleDuplicateCount) possible duplicates", systemImage: "square.on.square")
                }
            }
            if let garmin = model.garmin, garmin.connected {
                Section {
                    Text(garmin.status).font(.subheadline)
                    if garmin.running { Button("Pause sync") { garmin.pause() } }
                }
            }
            if model.isImporting {
                Section {
                    ProgressView("Importing files", value: Double(model.importProgress?.completed ?? 0),
                                 total: Double(max(model.importProgress?.total ?? 1, 1)))
                    Button("Cancel remaining imports", role: .cancel) { model.cancelImport() }
                }
            }
            if !model.outcomes.isEmpty {
                Button("Review last import (\(model.outcomes.count) files)") { showsResults = true }
            }
            if let error = model.error {
                Section {
                    Text(error)
                    Button("Try again") { Task { await model.open(); await model.reload() } }
                }
            }
            ForEach(model.activities, id: \.id) { activity in
                NavigationLink {
                    ActivityDetailView(activity: activity, library: model.library)
                } label: {
                    ActivityFeedRow(activity: activity, units: model.units, removedAtSource: activity.members.contains { model.removedSources.contains($0) })
                }
            }
            if model.hasMore {
                Button("Load more activities") { Task { await model.loadMore() } }
                    .disabled(model.isLoading)
                    .onAppear { Task { await model.loadMore() } }
            }
        }
        .overlay {
            if model.activities.isEmpty && !model.isImporting && model.error == nil {
                if model.isLoading { ProgressView("Opening library") }
                else if !search.isEmpty || sport != nil || setting != nil {
                    ContentUnavailableView.search(text: search)
                } else {
                    ContentUnavailableView {
                        Label("Your activities start here", systemImage: "figure.outdoor.cycle")
                    } description: {
                        Text("Import FIT files from your device to browse your rides and walks.")
                    } actions: {
                        Button("Import FIT files") { showsImporter = true }.buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .navigationTitle("Activities")
        .searchable(text: $search, prompt: "Search activity titles")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("Sport", selection: $sport) {
                        Text("All sports").tag(nil as Sport?)
                        ForEach(Sport.allCases, id: \.self) { Text($0.rawValue.capitalized).tag(Optional($0)) }
                    }
                    Picker("Setting", selection: $setting) {
                        Text("Indoor and outdoor").tag(nil as FeedFilter.Setting?)
                        Text("Indoor").tag(Optional(FeedFilter.Setting.indoor))
                        Text("Outdoor").tag(Optional(FeedFilter.Setting.outdoor))
                    }
                } label: { Label("Filter activities", systemImage: "line.3.horizontal.decrease") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Import FIT files", systemImage: "plus") { showsImporter = true }
                    .disabled(model.isImporting || model.library == nil)
            }
        }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): model.importFiles(urls)
            case .failure(let error): model.error = error.localizedDescription
            }
        }
        .sheet(isPresented: $showsResults) {
            NavigationStack {
                List(model.outcomes, id: \.index) { outcome in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(outcome.name).font(.headline)
                        switch outcome.result {
                        case .success(let result):
                            Text(result.change == .alreadyInLibrary ? "Already in your library" : "Imported")
                                .foregroundStyle(.secondary)
                        case .failure(let error):
                            Text(error.localizedDescription)
                            Text("Choose the original FIT file and import it again.").foregroundStyle(.secondary)
                        }
                    }
                }
                .navigationTitle("Import results")
                .toolbar { Button("Done") { showsResults = false } }
            }
        }
        .refreshable {
            await model.garmin?.sync()
            await model.health?.sync()
            await model.reload()
        }
        .task { await model.open() }
        .onAppear { Task { if model.library != nil { await model.reload() } } }
        .task(id: FeedFilter(sports: sport.map { [$0] }, setting: setting, titleContains: search)) {
            model.filter = FeedFilter(sports: sport.map { [$0] }, setting: setting, titleContains: search)
            await model.reload()
        }
    }
}

struct ActivityFeedRow: View {
    let activity: ActivityRecord
    let units: UnitSystem
    var removedAtSource = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(activity.title).font(.headline)
            Text(activity.start, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                .font(.subheadline).foregroundStyle(.secondary)
            if let headline = activity.headline, let value = headline.value.value {
                Text(headline.kind == "averagePower" ? String(format: "%.0f W average", value) : pace(value))
                    .font(.title3.weight(.semibold))
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { metrics }
                VStack(alignment: .leading, spacing: 4) { metrics }
            }
            Text("\(activity.sport.rawValue.capitalized) · \(sourceNames)")
                .font(.caption).foregroundStyle(.secondary)
            if removedAtSource {
                Label("Removed at source · kept on this device", systemImage: "archivebox")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .monospacedDigit()
    }
    private var sourceNames: String {
        Set(activity.members.map(\.source)).sorted { $0.rawValue < $1.rawValue }.map {
            switch $0 {
            case .garmin: "Garmin"
            case .healthKit: "Apple Health"
            case .file: "FIT file"
            }
        }.joined(separator: " · ")
    }
    private func pace(_ secondsPerKilometre: Double) -> String {
        let seconds = Int((secondsPerKilometre * (units == .metric ? 1 : 1.609344)).rounded())
        return String(format: "%d:%02d /%@", seconds / 60, seconds % 60, units == .metric ? "km" : "mi")
    }
    @ViewBuilder private var metrics: some View {
        Text(activity.distance.map { String(format: "%.1f %@", $0 / (units == .metric ? 1000 : 1609.344), units == .metric ? "km" : "mi") } ?? "No distance")
        Text(activity.movingTime.map { Duration.seconds($0).formatted(.time(pattern: .hourMinute)) } ?? "No moving time")
        Text(activity.ascent.map { String(format: "%.0f %@ ascent", $0 * (units == .metric ? 1 : 3.28084), units == .metric ? "m" : "ft") } ?? "No ascent")
    }
}
