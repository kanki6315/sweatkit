import SwiftUI
import UniformTypeIdentifiers
import SweatKitLibrary
import SweatKitModel
import SweatKitStore

/// Keeps title search and Activities filters together across navigation.
@MainActor @Observable final class ActivityFeedFilters {
    var search = ""
    var sport: Sport?
    var limitsDates = false
    var from = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    var through = Date()
    var setting: FeedFilter.Setting?
}

struct ActivityFeedView: View {
    @Bindable var model: LibraryModel
    @Bindable var filters: ActivityFeedFilters
    var showSettings: () -> Void
    @State private var selectedActivity: ActivityRecord?
    @ScaledMetric(relativeTo: .subheadline) private var statusIconSize = 20.0
    @State private var thumbnailGeneration = 0
    @State private var showsImporter = false
    @State private var showsResults = false
    @State private var showsDates = false

    var body: some View {
        let sections = weekSections
        let prefetchID = model.activities.dropLast(12).last?.id
        List {
            if filtersActive {
                Section {
                    HStack {
                        Label(filterDescription, systemImage: "line.3.horizontal.decrease.circle.fill")
                            .font(.subheadline)
                        Spacer()
                        Button("Clear") { filters.sport = nil; filters.setting = nil; filters.limitsDates = false; filters.search = "" }
                    }
                }
            }
            libraryStatus
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
            ForEach(sections, id: \.start) { section in
                Section {
                    ForEach(section.activities, id: \.id) { activity in
                        Button {
                            selectedActivity = activity
                        } label: {
                            ActivityFeedRow(activity: activity, units: model.units, library: model.library, revision: model.revisions[activity.primary], removedAtSource: activity.members.contains { model.removedSources.contains($0) }, stale: model.staleIDs.contains(activity.id ?? activity.primary), prominent: activity.id == model.activities.first?.id, records: model.recordBadges[activity.id ?? activity.primary] ?? [], route: model.routeCatalog.membership(of: activity.id ?? activity.primary))
                                .id(thumbnailGeneration)
                        }
                        .onAppear {
                            if activity.id == prefetchID { Task { await model.loadMore() } }
                        }
                        .buttonStyle(.plain)
                        .listRowSeparator(model.activities.first?.id == activity.id ? .hidden : .visible)
                        .accessibilityIdentifier(activity.isIndoor || activity.isVirtual ? "indoor-activity-row" : "outdoor-activity-row")
                    }
                } header: { weekHeader(section.start) }
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
                else if !filters.search.isEmpty || filters.sport != nil || filters.setting != nil || filters.limitsDates {
                    ContentUnavailableView {
                        Label("No matching activities", systemImage: "line.3.horizontal.decrease.circle")
                    } description: { Text("Try another title, sport or date range.") } actions: {
                        Button("Clear filters") { filters.sport = nil; filters.setting = nil; filters.limitsDates = false; filters.search = "" }
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
        .toolbarTitleDisplayMode(.inlineLarge)
        .navigationDestination(item: $selectedActivity) { activity in
            ActivityDetailView(activity: activity, library: model.library, deleteActivity: model.permanentlyDelete)
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button("Import FIT files", systemImage: "plus") { showsImporter = true }
                        .disabled(model.isImporting || model.library == nil)
                    Divider()
                    Button(filters.limitsDates ? "Change date range" : "Filter by date") { showsDates = true }
                    if filters.limitsDates { Button("Show all dates") { filters.limitsDates = false } }
                    Picker("Sport", selection: $filters.sport) {
                        Text("All sports").tag(nil as Sport?)
                        ForEach(Sport.allCases, id: \.self) { Text($0.rawValue.capitalized).tag(Optional($0)) }
                    }
                    Picker("Setting", selection: $filters.setting) {
                        Text("Indoor and outdoor").tag(nil as FeedFilter.Setting?)
                        Text("Indoor").tag(Optional(FeedFilter.Setting.indoor))
                        Text("Outdoor").tag(Optional(FeedFilter.Setting.outdoor))
                    }
                } label: { Label(filtersActive ? "Filters active" : "Filter activities", systemImage: filtersActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease") }
                .tint(.primary)
                Button("Settings", systemImage: "person", action: showSettings)
                    .tint(.primary)
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
                    Toggle("Limit date range", isOn: $filters.limitsDates)
                    DatePicker("From", selection: $filters.from, in: ...filters.through, displayedComponents: .date)
                    DatePicker("Through", selection: $filters.through, in: filters.from..., displayedComponents: .date)
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
    // Keep background work together so the activity feed remains the focus.
    @ViewBuilder private var libraryStatus: some View {
        Section {
            if !model.staleIDs.isEmpty || model.isRecomputing {
                HStack(alignment: .top, spacing: 12) {
                    statusIcon("arrow.clockwise", busy: model.isRecomputing)
                    VStack(alignment: .leading, spacing: 4) {
                        if model.isRecomputing {
                            Text("Recalculating activities").font(.subheadline.weight(.medium))
                        } else {
                            Button("Recalculate activities") { Task { await model.recompute() } }
                                .font(.subheadline.weight(.medium))
                                .buttonStyle(.borderless)
                                .frame(minHeight: 44, alignment: .topLeading)
                        }
                        Text("\(model.staleIDs.count) activities need recalculation. Displayed results may be out of date.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
                .listRowSeparator(.hidden)
            }
            if let health = model.health, health.enabled {
                DisclosureGroup {
                    Button("Review Health access") { Task { await health.connect(); await model.reload() } }
                        .disabled(health.running)
                    if health.running { Button("Pause Health refresh") { health.pause() } }
                } label: {
                    statusLabel(health.status, icon: "heart", busy: health.running)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .listRowSeparator(.hidden)
            }
            if let garmin = model.garmin, garmin.connected {
                if garmin.running {
                    DisclosureGroup {
                        Button("Pause sync") { garmin.pause() }
                    } label: {
                        statusLabel(garmin.status, icon: "arrow.triangle.2.circlepath", busy: true)
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                    .listRowSeparator(.hidden)
                } else {
                    statusLabel(garmin.status, icon: "arrow.triangle.2.circlepath", busy: false)
                        .foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)
                }
                // Keep expiry notices visible alongside sync status.
                if let notice = garmin.expiryNotice() {
                    Text(notice).font(.footnote).foregroundStyle(.secondary)
                }
            }
            if model.possibleDuplicateCount > 0, let library = model.library {
                NavigationLink {
                    LibraryReviewView(library: library)
                } label: {
                    statusLabel("Review \(model.possibleDuplicateCount) possible duplicates",
                                icon: "square.on.square", busy: false)
                }
                .listRowSeparator(.hidden)
            }
        }
    }

    private func statusLabel(_ text: String, icon: String, busy: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            statusIcon(icon, busy: busy)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private func statusIcon(_ symbol: String, busy: Bool) -> some View {
        ZStack {
            if busy {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: symbol)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: statusIconSize, height: statusIconSize)
        .accessibilityHidden(true)
    }

    private var filtersActive: Bool { filters.sport != nil || filters.setting != nil || filters.limitsDates || !filters.search.isEmpty }
    private var filterDescription: String {
        [filters.sport?.rawValue.capitalized, filters.setting.map { $0 == .indoor ? "Indoor" : "Outdoor" },
         filters.limitsDates ? "Selected dates" : nil, filters.search.isEmpty ? nil : "Title search"].compactMap { $0 }.joined(separator: " · ")
    }
    private var feedFilter: FeedFilter {
        let start = Calendar.current.startOfDay(for: filters.from)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: filters.through)) ?? filters.through
        return FeedFilter(sports: filters.sport.map { [$0] }, dates: filters.limitsDates ? start..<max(start.addingTimeInterval(1), end) : nil,
                          setting: filters.setting, titleContains: filters.search)
    }
    private var weekSections: [(start: Date, activities: [ActivityRecord])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: model.activities) {
            calendar.dateInterval(of: .weekOfYear, for: $0.start)?.start ?? calendar.startOfDay(for: $0.start)
        }
        return grouped.keys.sorted(by: >).map { (start: $0, activities: grouped[$0] ?? []) }
    }
    @ViewBuilder private func weekHeader(_ week: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text(weekTitle(week)).font(.title3.bold()).foregroundStyle(Color.primary)
                    Spacer(minLength: 8)
                    if let summary = model.weekSummaries[week] { Text(weekTotals(summary)).font(.subheadline).monospacedDigit() }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(weekTitle(week)).font(.title3.bold()).foregroundStyle(Color.primary)
                    if let summary = model.weekSummaries[week] { Text(weekTotals(summary)).font(.caption).monospacedDigit() }
                }
            }
            if let summary = model.weekSummaries[week], summary.missingDistance > 0 || summary.missingMovingTime > 0 || summary.missingAscent > 0 {
                Text("Totals include recorded values only; some figures are missing.").font(.caption)
            }
        }.textCase(nil)
    }
    private func weekTotals(_ summary: FeedWeekSummary) -> String {
        "\(weekDistance(summary)) · \(summary.missingMovingTime == summary.count ? "No moving time" : Duration.seconds(summary.movingTime).formatted(.time(pattern: .hourMinute))) · \(summary.missingAscent == summary.count ? "No ascent" : String(format: "%.0f %@", summary.ascent * (model.units == .metric ? 1 : 3.28084), model.units == .metric ? "m" : "ft"))"
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
    var records: [TrendRecord] = []
    var route: LibraryRoute?
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if prominent, let library {
                ActivityThumbnail(activity: activity, library: library, revision: revision)
                    .aspectRatio(2, contentMode: .fit)
                    .overlay(alignment: .topLeading) {
                        Text(featureDate)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color(uiColor: .secondarySystemBackground).opacity(0.95), in: Capsule())
                            .padding(12)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            }
            HStack(alignment: .top, spacing: 12) {
                if !prominent, !typeSize.isAccessibilitySize, let library {
                    ActivityThumbnail(activity: activity, library: library, revision: revision, compact: true)
                        .frame(width: 68, height: 68)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        activityContent
                        headline
                    }
                    .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        activityContent.frame(maxWidth: .infinity, alignment: .leading)
                        headline
                    }
                    .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                }
            }
        }
        .padding(.vertical, 8)
        .monospacedDigit()
        .contentShape(Rectangle())
    }

    private var activityContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(activity.title)
                .font(prominent ? .title3.bold() : .headline)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 5) {
                    Text(metadata)
                    SourceAttributionView(sources: activity.members.map(\.source))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(metadata)
                    SourceAttributionView(sources: activity.members.map(\.source))
                }
            }
            .font(.subheadline).foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { metrics }
                VStack(alignment: .leading, spacing: 4) { metrics }
            }.font(.subheadline)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { badges }
                VStack(alignment: .leading, spacing: 6) { badges }
            }
            if stale { Label("Results need recalculation", systemImage: "arrow.clockwise").font(.caption).foregroundStyle(.secondary) }
            if removedAtSource {
                Label("Removed at source · kept on this device", systemImage: "archivebox")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var featureDate: String {
        let time = activity.start.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(activity.start) { return "Today, \(time)" }
        if Calendar.current.isDateInYesterday(activity.start) { return "Yesterday, \(time)" }
        return activity.start.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    private var metadata: String {
        let sportName = activity.sport == .other ? (activity.sourceSportName ?? "Other") : activity.sport.rawValue.capitalized
        let sport = activity.isVirtual ? "Virtual ride" : activity.isIndoor ? "Indoor " + sportName : sportName
        return prominent ? sport : "\(sport) · \(activity.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))"
    }

    @ViewBuilder private var badges: some View {
        if !stale, !records.isEmpty {
            Label(records.count == 1 ? records[0].title + " record" : "\(records.count) personal records", systemImage: "star.fill")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 5)
                .background(Color(uiColor: .secondarySystemFill), in: RoundedRectangle(cornerRadius: 6))
        }
        if let route {
            Label(route.rank(of: activity.id ?? activity.primary).map { "\(route.name) · #\($0) of \(route.ranked.count)" } ?? route.name,
                  systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 5)
                .background(Color(uiColor: .secondarySystemFill), in: RoundedRectangle(cornerRadius: 6))
        }
    }
    @ViewBuilder private var headline: some View {
        if let headline = activity.headline {
            let isPower = headline.kind == "averagePower" || headline.kind == "weightedPower"
            VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
                Group {
                    if let value = headline.value.value {
                        if isPower {
                            Text(String(format: "%.0f", value)).font(.title2.weight(.semibold))
                                + Text(" W").font(.subheadline)
                        } else {
                            Text(pace(value)).font(.title2.weight(.semibold))
                                + Text(units == .metric ? "/km" : "/mi").font(.subheadline)
                        }
                    } else {
                        Text("—").font(.title2.weight(.semibold))
                    }
                }
                .fixedSize()
                Text(headline.kind == "weightedPower" ? "weighted" : isPower ? "average" : "pace")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func pace(_ secondsPerKilometre: Double) -> String {
        let seconds = Int((secondsPerKilometre * (units == .metric ? 1 : 1.609344)).rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
    @ViewBuilder private var metrics: some View {
        Text(activity.distance.map { String(format: "%.1f %@", $0 / (units == .metric ? 1000 : 1609.344), units == .metric ? "km" : "mi") } ?? "No distance")
        Text(activity.movingTime.map { Duration.seconds($0).formatted(.time(pattern: .hourMinute)) } ?? "No moving time")
        Text(activity.ascent.map { String(format: "%.0f %@", $0 * (units == .metric ? 1 : 3.28084), units == .metric ? "m" : "ft") } ?? "No ascent")
    }
}
