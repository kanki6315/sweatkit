import SwiftUI
import UniformTypeIdentifiers
import SweatKitLibrary
import SweatKitModel
import SweatKitStore

struct ActivityFeedView: View {
    @Bindable var model: LibraryModel
    @State private var thumbnailGeneration = 0
    @State private var showsImporter = false
    @State private var showsResults = false
    @State private var search = ""
    @State private var sport: Sport?
    @State private var limitsDates = false
    @State private var from = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var through = Date()
    @State private var showsDates = false
    @State private var setting: FeedFilter.Setting?

    var body: some View {
        List {
            if filtersActive {
                Section {
                    HStack {
                        Label(filterDescription, systemImage: "line.3.horizontal.decrease.circle.fill")
                            .font(.subheadline)
                        Spacer()
                        Button("Clear") { sport = nil; setting = nil; limitsDates = false; search = "" }
                    }
                }
            }
            if !model.staleIDs.isEmpty || model.isRecomputing {
                Section {
                    Text("\(model.staleIDs.count) activities need recalculation. Displayed results may be out of date.")
                    if model.isRecomputing { ProgressView("Recalculating activities") }
                    else { Button("Recalculate activities") { Task { await model.recompute() } } }
                }
            }
            if let health = model.health, health.enabled {
                Section {
                    Label(health.status, systemImage: "heart").font(.footnote).foregroundStyle(.secondary)
                    Button("Review Health access") { Task { await health.connect(); await model.reload() } }
                        .disabled(health.running)
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
                    Label(garmin.status, systemImage: "arrow.triangle.2.circlepath").font(.footnote).foregroundStyle(.secondary)
                    if let notice = garmin.expiryNotice() { Text(notice).font(.subheadline) }
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
            ForEach(weekStarts, id: \.self) { week in
                Section {
                    ForEach(activities(in: week), id: \.id) { activity in
                        NavigationLink {
                            ActivityDetailView(activity: activity, library: model.library, deleteActivity: model.permanentlyDelete)
                        } label: {
                            ActivityFeedRow(activity: activity, units: model.units, library: model.library, revision: model.revisions[activity.primary], removedAtSource: activity.members.contains { model.removedSources.contains($0) }, stale: model.staleIDs.contains(activity.id ?? activity.primary), prominent: activity.id == model.activities.first?.id)
                                .id(thumbnailGeneration)
                        }
                    }
                } header: { weekHeader(week) }
            }
            if model.hasMore {
                Button("Load more activities") { Task { await model.loadMore() } }
                    .disabled(model.isLoading)
                    .onAppear { Task { await model.loadMore() } }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppTheme.profileDidChange)) { _ in thumbnailGeneration += 1 }
        .listStyle(.plain)
        .overlay {
            if model.activities.isEmpty && !model.isImporting && model.error == nil && model.staleIDs.isEmpty {
                if model.isLoading { ProgressView("Opening library") }
                else if !search.isEmpty || sport != nil || setting != nil || limitsDates {
                    ContentUnavailableView {
                        Label("No matching activities", systemImage: "line.3.horizontal.decrease.circle")
                    } description: { Text("Try another title, sport or date range.") } actions: {
                        Button("Clear filters") { sport = nil; setting = nil; limitsDates = false; search = "" }
                    }
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
        .searchable(text: $search, placement: .toolbar, prompt: "Search activity titles")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Import FIT files", systemImage: "plus") { showsImporter = true }
                        .disabled(model.isImporting || model.library == nil)
                    Divider()
                    Button(limitsDates ? "Change date range" : "Filter by date") { showsDates = true }
                    if limitsDates { Button("Show all dates") { limitsDates = false } }
                    Picker("Sport", selection: $sport) {
                        Text("All sports").tag(nil as Sport?)
                        ForEach(Sport.allCases, id: \.self) { Text($0.rawValue.capitalized).tag(Optional($0)) }
                    }
                    Picker("Setting", selection: $setting) {
                        Text("Indoor and outdoor").tag(nil as FeedFilter.Setting?)
                        Text("Indoor").tag(Optional(FeedFilter.Setting.indoor))
                        Text("Outdoor").tag(Optional(FeedFilter.Setting.outdoor))
                    }
                } label: { Label(filtersActive ? "Filters active" : "Filter activities", systemImage: filtersActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease") }
            }

        }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): model.importFiles(urls)
            case .failure(let error): model.error = error.localizedDescription
            }
        }
        .sheet(isPresented: $showsDates) {
            NavigationStack {
                Form {
                    Toggle("Limit date range", isOn: $limitsDates)
                    DatePicker("From", selection: $from, in: ...through, displayedComponents: .date)
                    DatePicker("Through", selection: $through, in: from..., displayedComponents: .date)
                }
                .navigationTitle("Activity dates")
                .toolbar { Button("Done") { showsDates = false } }
                .presentationDetents([.medium])
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
        .task(id: feedFilter) {
            model.filter = feedFilter
            await model.reload()
        }
    }
    private var filtersActive: Bool { sport != nil || setting != nil || limitsDates || !search.isEmpty }
    private var filterDescription: String {
        [sport?.rawValue.capitalized, setting.map { $0 == .indoor ? "Indoor" : "Outdoor" },
         limitsDates ? "Selected dates" : nil, search.isEmpty ? nil : "Title search"].compactMap { $0 }.joined(separator: " · ")
    }
    private var feedFilter: FeedFilter {
        let start = Calendar.current.startOfDay(for: from)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: through)) ?? through
        return FeedFilter(sports: sport.map { [$0] }, dates: limitsDates ? start..<max(start.addingTimeInterval(1), end) : nil,
                          setting: setting, titleContains: search)
    }
    private var weekStarts: [Date] {
        Set(model.activities.compactMap { Calendar.current.dateInterval(of: .weekOfYear, for: $0.start)?.start }).sorted(by: >)
    }
    private func activities(in week: Date) -> [ActivityRecord] {
        model.activities.filter { Calendar.current.dateInterval(of: .weekOfYear, for: $0.start)?.start == week }
    }
    @ViewBuilder private func weekHeader(_ week: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(weekTitle(week)).font(.title3.bold()).foregroundStyle(Color.primary)
            if let summary = model.weekSummaries[week] {
                Text("\(summary.count) \(summary.count == 1 ? "activity" : "activities") · \(weekDistance(summary)) · \(summary.missingMovingTime == summary.count ? "No moving time" : Duration.seconds(summary.movingTime).formatted(.time(pattern: .hourMinute))) · \(summary.missingAscent == summary.count ? "No ascent" : String(format: "%.0f %@ ascent", summary.ascent * (model.units == .metric ? 1 : 3.28084), model.units == .metric ? "m" : "ft"))")
                    .font(.caption).monospacedDigit()
                if summary.missingDistance > 0 || summary.missingMovingTime > 0 || summary.missingAscent > 0 {
                    Text("Totals include recorded values only; some figures are missing.").font(.caption)
                }
            }
        }.textCase(nil)
    }
    private func weekTitle(_ week: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(week, equalTo: .now, toGranularity: .weekOfYear) { return "This week" }
        if let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: .now),
           calendar.isDate(week, equalTo: previous, toGranularity: .weekOfYear) { return "Last week" }
        return "Week of \(week.formatted(date: .abbreviated, time: .omitted))"
    }
    private func weekDistance(_ week: FeedWeekSummary) -> String {
        guard week.missingDistance < week.count else { return "No distance" }
        return String(format: "%.1f %@", week.distance / (model.units == .metric ? 1000 : 1609.344), model.units == .metric ? "km" : "mi")
    }

}

struct ActivityFeedRow: View {
    let activity: ActivityRecord
    let units: UnitSystem
    var library: ActivityLibrary?
    var revision: ContentHash?
    var removedAtSource = false
    var stale = false
    var prominent = false
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .leading, spacing: prominent ? 12 : 8) {
            if prominent, let library {
                ActivityThumbnail(activity: activity, library: library, revision: revision)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            HStack(alignment: .top, spacing: 12) {
                if !prominent, !typeSize.isAccessibilitySize, let library {
                    ActivityThumbnail(activity: activity, library: library, revision: revision, compact: true)
                        .frame(width: 68, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                VStack(alignment: .leading, spacing: 6) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 12) {
                            Text(activity.title).font(prominent ? .title3.bold() : .headline)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            headline
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(activity.title).font(.headline)
                            headline
                        }
                    }
                    Text("\(activity.isVirtual ? "Virtual " : activity.isIndoor ? "Indoor " : "")\(activity.sport.rawValue.capitalized) · \(sourceNames)")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(activity.start, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                        .font(.caption).foregroundStyle(.secondary)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { metrics }
                        VStack(alignment: .leading, spacing: 4) { metrics }
                    }.font(.subheadline)
                }
            }
            if stale { Label("Results need recalculation", systemImage: "arrow.clockwise").font(.caption) }
            if removedAtSource {
                Label("Removed at source · kept on this device", systemImage: "archivebox")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .monospacedDigit()
    }
    @ViewBuilder private var headline: some View {
        if let headline = activity.headline, let value = headline.value.value {
            VStack(alignment: .trailing, spacing: 2) {
                Text(headline.kind == "averagePower" ? String(format: "%.0f W", value) : pace(value))
                    .font(.title3.weight(.semibold)).fixedSize()
                Text(headline.kind == "averagePower" ? "average" : "pace")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
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
