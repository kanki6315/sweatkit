import SwiftUI
import Charts
import SweatKitAnalysis
import SweatKitLibrary
import SweatKitModel
import SweatKitStore

struct TrendsView: View {
    let model: LibraryModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var history: TrendsHistory?
    @State private var error: String?
    @State private var loading = true
    @State private var sport = "Rides"
    @State private var dateWindow = "Last 12 months"
    @State private var setting = "All settings"
    @State private var measure = TrendMeasure.distance
    @State private var period = TrendPeriod.week
    @State private var comparison = "90 days"
    @State private var recordWindow = "This year"
    @State private var showFilters = false
    @State private var presentation = TrendsPresentation()
    @State private var selection: TrendsSelection?
    @State private var retry = 0
    private var configuration: String { "\(sport)|\(dateWindow)|\(setting)|\(measure)|\(period)|\(comparison)|\(recordWindow)" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text([sport, dateWindow, setting == "All settings" ? nil : setting]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if loading { ProgressView("Preparing history…").frame(maxWidth: .infinity) }
                else if let error {
                    ContentUnavailableView {
                        Label("History couldn’t load", systemImage: "exclamationmark.triangle")
                    } description: { Text(error) } actions: { Button("Try again") { retry += 1 } }
                } else if presentation.rows.isEmpty {
                    ContentUnavailableView("No activities in this range", systemImage: "chart.xyaxis.line",
                        description: Text("Change the filters or import more history from Activities."))
                } else {
                    if presentation.staleCount > 0 {
                        Text("\(presentation.staleCount) activities need recalculation. Their old results are excluded.")
                            .font(.footnote)
                        Button("Recalculate") { Task { await model.recompute() } }.disabled(model.isRecomputing)
                    }
                    volume
                    power
                    thresholds
                    efficiency
                    records
                    calendar
                    Text("Sources: \(sourceSummary(presentation.rows.map(\.activity)))")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Empty periods mean no matching activities in this library.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Trends")
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            Button("Filter trends", systemImage: "line.3.horizontal.decrease") { showFilters = true }
        } }
        .sheet(isPresented: $showFilters) { filters }
        .navigationDestination(item: $selection) { selected in
            List(selected.activities, id: \.primary) { row in
                NavigationLink {
                    ActivityDetailView(activity: row, library: model.library, deleteActivity: model.permanentlyDelete)
                } label: {
                    VStack(alignment: .leading) {
                        Text(row.title)
                        Text("\(row.start.formatted(.dateTime.day().month().year())) · \(sourceSummary([row]))").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.navigationTitle(selected.title)
        }
        .task(id: "\(model.trendsRevision)|\(retry)") { await load() }
        .task(id: configuration) { await prepare() }
    }

    private func load() async {
        guard let library = model.library else { loading = false; return }
        loading = true; error = nil
        do {
            let loaded = try await library.trendsHistory()
            try Task.checkCancellation()
            history = loaded
            await prepare()
            loading = false
        } catch is CancellationError { }
        catch { self.error = error.localizedDescription; loading = false }
    }
    private func prepare() async {
        guard let history else { return }
        let requestedConfiguration = configuration
        let requestedRevision = model.trendsRevision
        let options = TrendsOptions(sport: sport, dateWindow: dateWindow, setting: setting,
            measure: measure, period: period, comparison: comparison, recordWindow: recordWindow)
        let result = await Task.detached { TrendsPresentation.make(history, options: options) }.value
        guard !Task.isCancelled, requestedConfiguration == configuration,
              requestedRevision == model.trendsRevision else { return }
        presentation = result
    }
    private var filters: some View {
        NavigationStack {
            Form {
                Picker("Sport", selection: $sport) {
                    ForEach(["All sports", "Rides", "Walks", "Runs", "Hikes"], id: \.self) { Text($0) }
                }
                Picker("Date range", selection: $dateWindow) {
                    ForEach(["Last 6 weeks", "Last 90 days", "Last 12 months", "This year", "All time"], id: \.self) { Text($0) }
                }
                Picker("Setting", selection: $setting) {
                    ForEach(["All settings", "Indoor", "Outdoor"], id: \.self) { Text($0) }
                }
            }.navigationTitle("Trend filters")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showFilters = false } } }
        }.presentationDetents([.medium, .large])
    }
    private func panel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16, content: content)
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
    }
    private func heading(_ title: String) -> some View { Text(title).font(.title2.bold()) }
    private func note(_ text: String) -> some View { Text(text).font(.footnote).foregroundStyle(.secondary) }
    private var volume: some View {
        VStack(alignment: .leading, spacing: 12) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading) { heading("Volume"); periodPicker }
                measurePicker.pickerStyle(.menu)
            } else {
                HStack { heading("Volume"); Spacer(); periodPicker }
                measurePicker.pickerStyle(.segmented)
            }
            panel {
                if let latest = presentation.buckets.last {
                    if typeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 12) { totals(latest) }
                    } else {
                        HStack(alignment: .top, spacing: 12) { totals(latest) }
                    }
                }
                Chart(presentation.buckets) { bucket in
                    if let value = bucket.total.complete {
                        BarMark(x: .value("Period", bucket.start), y: .value(measure.rawValue, scaled(value)))
                            .foregroundStyle(bucket.id == presentation.buckets.last?.id ? Color.primary : Color.secondary.opacity(0.65))
                    }
                    if let value = bucket.lastYear.complete, bucket.lastYear.count > 0 {
                        RectangleMark(x: .value("Period", bucket.start), y: .value("Last year", scaled(value)), width: .fixed(18), height: .fixed(2))
                            .foregroundStyle(Color.primary)
                    }
                }.chartYAxis { AxisMarks(position: .leading) }
                    .chartXAxis { AxisMarks { AxisValueLabel() } }
                    .chartScrollableAxes(.horizontal)
                    .chartXVisibleDomain(length: period == .week ? 12 * 7 * 86400 : period == .month ? 365 * 86400 : 5 * 365 * 86400)
                    .chartScrollPosition(initialX: presentation.buckets.suffix(12).first?.start ?? Date())
                    .frame(height: 180).accessibilityLabel("\(measure.rawValue) by \(period.rawValue.lowercased()). Incomplete periods omitted.")
                chartLegend(first: period.rawValue, second: "Same period last year", firstIsBar: true)
                if presentation.buckets.contains(where: { $0.total.missing > 0 }) {
                    note("\(presentation.buckets.filter { $0.total.missing > 0 }.count) incomplete periods omitted.")
                }
                Menu("Explore periods") {
                    ForEach(presentation.buckets.reversed()) { bucket in
                        Button(bucket.start.formatted(date: .abbreviated, time: .omitted)) {
                            select("Activities", from: bucket.start, to: bucket.end)
                        }
                    }
                }
            }
        }
    }
    private var periodPicker: some View {
        Picker("Period", selection: $period) {
            ForEach(TrendPeriod.allCases, id: \.self) { Text($0.rawValue) }
        }.pickerStyle(.menu)
    }
    private var measurePicker: some View {
        Picker("Volume measure", selection: $measure) {
            ForEach(TrendMeasure.allCases, id: \.self) { Text($0.rawValue) }
        }
    }
    private var comparisonPicker: some View {
        Picker("Compare six weeks with", selection: $comparison) {
            ForEach(["90 days", "This year", "All time"], id: \.self) { Text($0) }
        }
    }
    private var recordPicker: some View {
        Picker("Record window", selection: $recordWindow) {
            Text("This year").tag("This year"); Text("All time").tag("All time")
        }.pickerStyle(.menu)
    }
    @ViewBuilder private func totals(_ bucket: TrendBucket) -> some View {
        totalLabel(bucket.total, "This period")
        totalLabel(bucket.previous, "Previous period")
        totalLabel(bucket.lastYear, "Same period last year")
    }
    private func totalLabel(_ total: TrendTotal, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(total.count == 0 ? "—" : total.complete.map { scaled($0).formatted(.number.precision(.fractionLength(0...1))) } ?? "Incomplete")
                .font(.title2.bold()).monospacedDigit()
            Text("\(unit) · \(label)").font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if total.missing > 0 { Text("\(total.missing) unavailable").font(.caption) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var unit: String {
        switch measure { case .distance: model.units == .metric ? "km" : "mi"; case .time: "h"; case .ascent: model.units == .metric ? "m" : "ft"; case .load: "load" }
    }
    private func scaled(_ value: Double) -> Double {
        switch measure { case .distance: value / (model.units == .metric ? 1000 : 1609.344); case .time: value / 3600; case .ascent: value * (model.units == .metric ? 1 : 3.28084); case .load: value }
    }
    private var power: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("Power curve")
            if typeSize.isAccessibilitySize { comparisonPicker.pickerStyle(.menu) }
            else { comparisonPicker.pickerStyle(.segmented) }
            panel {
                chartLegend(first: "Last 6 weeks", second: comparison == "90 days" ? "Last 90 days" : comparison, dashed: true)
                if presentation.curve.allSatisfy({ $0.power.value == nil }) { note("No valid power windows in this range.") }
                else {
                    Chart {
                        ForEach(presentation.curve, id: \.duration) { point in
                            if let value = point.power.value {
                                LineMark(x: .value("Seconds", point.duration), y: .value("Watts", value), series: .value("Window", "Comparison-\(curveSegment(presentation.curve, at: point.duration))"))
                                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4])).foregroundStyle(Color.secondary)
                            }
                        }
                        ForEach(presentation.recentCurve, id: \.duration) { point in
                            if let value = point.power.value {
                                LineMark(x: .value("Seconds", point.duration), y: .value("Watts", value), series: .value("Window", "6 weeks-\(curveSegment(presentation.recentCurve, at: point.duration))"))
                                    .foregroundStyle(Color.primary)
                            }
                        }
                        if let estimate = presentation.estimate {
                            RuleMark(y: .value("Estimated threshold", estimate)).lineStyle(StrokeStyle(dash: [2, 4]))
                                .foregroundStyle(Color.secondary).annotation(position: .bottom, alignment: .leading) {
                                    Text("Estimate \(Int(estimate)) W").font(.caption)
                                }
                        }
                    }.chartXScale(domain: 5...3600, type: .log)
                        .chartXAxis {
                            AxisMarks(values: [5, 60, 300, 1200, 3600]) { tick in
                                AxisValueLabel {
                                    if let seconds = tick.as(Int.self) {
                                        Text(seconds < 60 ? "\(seconds)s" : seconds < 3600 ? "\(seconds / 60)m" : "1h")
                                    }
                                }
                            }
                        }
                        .chartYAxis { AxisMarks(position: .leading) }
                        .chartYAxisLabel("Watts")
                        .frame(height: 200)
                }
                Button("Explore power activities") {
                    selection = TrendsSelection(title: "Power activities", activities: presentation.rows.filter { $0.curve.contains { $0.power.value != nil } }.map(\.activity))
                }.font(.footnote)
            }
        }
    }
    private func curveSegment(_ points: [PowerCurvePoint], at duration: Int) -> Int {
        points.prefix { $0.duration < duration }.filter { $0.power.value == nil }.count
    }
    private var thresholds: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("Threshold power")
            panel {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 20) { thresholdLabels }
                    VStack(alignment: .leading) { thresholdLabels }
                }
                if presentation.thresholds.isEmpty { note("A valid 20-minute power window in the preceding 90 days is needed for an estimate.") }
                Chart {
                    ForEach(presentation.thresholds.indices, id: \.self) { index in
                        let point = presentation.thresholds[index]
                        LineMark(x: .value("Date", point.date), y: .value("Estimate W", point.value),
                            series: .value("Estimate segment", thresholdSegment(at: index)))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4])).foregroundStyle(Color.secondary)
                        PointMark(x: .value("Date", point.date), y: .value("Estimate W", point.value))
                            .symbolSize(3).foregroundStyle(Color.secondary)
                    }
                    ForEach(presentation.setThresholds) { point in
                        LineMark(x: .value("Date", point.date), y: .value("Set W", point.value))
                            .interpolationMethod(.stepEnd).foregroundStyle(Color.primary)
                    }
                }.chartYScale(domain: .automatic(includesZero: false)).frame(height: 160)
                if let estimate = presentation.estimate, let current = presentation.currentThreshold, estimate > current {
                    note("The estimate is above your set threshold. Review your threshold in Settings if appropriate.")
                }
                chartLegend(first: "Your threshold", second: "Estimate", dashed: true)
                DisclosureGroup("How the estimate works") {
                    note("95% of your best valid 20-minute power in the preceding 90 days. It never changes your settings automatically.")
                }.font(.footnote)
            }
        }
    }
    private func thresholdSegment(at index: Int) -> Int {
        guard index > 0 else { return 0 }
        return (1...index).filter {
            presentation.thresholds[$0].date.timeIntervalSince(presentation.thresholds[$0 - 1].date) > 36 * 3600
        }.count
    }
    @ViewBuilder private var thresholdLabels: some View {
        VStack(alignment: .leading) {
            Text(presentation.currentThreshold.map { "\(Int($0)) W" } ?? "Not set").font(.title2.bold()).monospacedDigit()
            note("Your threshold")
        }
        VStack(alignment: .leading) {
            Text(presentation.estimate.map { "\(Int($0)) W" } ?? "Unavailable").font(.title2.bold()).monospacedDigit()
            note("Estimate from best 20 min")
        }
    }
    private var efficiency: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("Efficiency")
            panel {
                note("Weighted power per heartbeat on rides of at least 20 minutes, with variability below 1.10. This compares output on similar efforts; it isn’t a fitness score.")
                if presentation.efficiency.isEmpty { note("No qualifying rides with power and heart rate in this range.") }
                else {
                    Chart {
                        ForEach(presentation.efficiency) { point in
                            PointMark(x: .value("Date", point.date), y: .value("W / bpm", point.value)).foregroundStyle(Color.secondary)
                        }
                        ForEach(presentation.regression) { point in
                            LineMark(x: .value("Date", point.date), y: .value("Trend", point.value)).foregroundStyle(Color.primary)
                        }
                    }.chartYScale(domain: .automatic(includesZero: false)).frame(height: 180)
                    Button("Explore steady rides") { selection = TrendsSelection(title: "Steady rides", activities: presentation.efficiency.compactMap(\.activity)) }
                }
            }
        }
    }
    private var records: some View {
        VStack(alignment: .leading, spacing: 12) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading) { heading("Records"); recordPicker }
            } else {
                HStack { heading("Records"); Spacer(); recordPicker }
            }
            panel {
                if presentation.records.isEmpty { note("No eligible records in this range.") }
                ForEach(presentation.records) { record in
                    NavigationLink {
                        ActivityDetailView(activity: record.activity, library: model.library, deleteActivity: model.permanentlyDelete)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            if typeSize.isAccessibilitySize {
                                VStack(alignment: .leading) {
                                    Text(record.title).fixedSize(horizontal: false, vertical: true)
                                    Text(recordValue(record)).bold().monospacedDigit()
                                }
                            } else {
                                HStack {
                                    Text(record.title).fixedSize(horizontal: false, vertical: true)
                                    Spacer()
                                    Text(recordValue(record)).bold().monospacedDigit().fixedSize()
                                }
                            }
                            Text("\(record.activity.start.formatted(date: .abbreviated, time: .omitted)) · \(record.activity.title) · \(sourceSummary([record.activity]))")
                                .font(.caption).foregroundStyle(Color.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }.foregroundStyle(Color.primary).frame(minHeight: 44)
                    }.buttonStyle(.plain)
                    if record.id != presentation.records.last?.id { Divider() }
                }
            }
        }
    }
    private func recordValue(_ record: TrendRecord) -> String {
        if record.unit == "s" { return Duration.seconds(record.value).formatted(.time(pattern: .hourMinuteSecond)) }
        if record.unit == "m" {
            let distance = record.key == "longestRide"
            let divisor = distance ? (model.units == .metric ? 1000.0 : 1609.344) : (model.units == .metric ? 1.0 : 0.3048)
            let suffix = distance ? (model.units == .metric ? "km" : "mi") : (model.units == .metric ? "m" : "ft")
            return "\((record.value / divisor).formatted(.number.precision(.fractionLength(0...1)))) \(suffix)"
        }
        return "\(Int(record.value)) \(record.unit)"
    }
    private var calendarCellSize: CGFloat { typeSize.isAccessibilitySize ? 80 : 44 }
    private var calendar: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("Load calendar")
            panel {
                note("Daily load · columns are weeks, starting \(Calendar.current.weekdaySymbols[Calendar.current.firstWeekday - 1]). Scroll through the selected range.")
                HStack(alignment: .top, spacing: 8) {
                    VStack(spacing: 5) {
                        Color.clear.frame(height: typeSize.isAccessibilitySize ? 80 : 36)
                        ForEach(0..<7) { offset in
                            Text(Calendar.current.veryShortWeekdaySymbols[(Calendar.current.firstWeekday - 1 + offset) % 7])
                                .font(.caption).frame(width: typeSize.isAccessibilitySize ? 36 : 18, height: calendarCellSize)
                        }
                    }.frame(width: typeSize.isAccessibilitySize ? 36 : 18).accessibilityHidden(true)
                    ScrollView(.horizontal) {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 5) {
                                ForEach(Array(stride(from: 0, to: presentation.days.count, by: 7)), id: \.self) { index in
                                    VStack(spacing: 0) {
                                        Text(presentation.days[index].start, format: .dateTime.month(.abbreviated))
                                        Text(presentation.days[index].start, format: .dateTime.day())
                                    }.font(.caption2).fixedSize(horizontal: false, vertical: true)
                                        .frame(width: calendarCellSize, height: typeSize.isAccessibilitySize ? 80 : 36)
                                }
                            }.accessibilityHidden(true)
                            LazyHGrid(rows: Array(repeating: GridItem(.fixed(calendarCellSize), spacing: 5), count: 7), spacing: 5) {
                                ForEach(presentation.days) { day in
                                    Button { select(day.start.formatted(date: .abbreviated, time: .omitted), from: day.start, to: day.end) } label: {
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(day.total.missing > 0 || day.total.count == 0 ? Color(uiColor: .tertiarySystemFill) : Color.orange.opacity(0.25 + min(day.total.known / 200, 1) * 0.75))
                                            .overlay { if day.total.missing > 0 { Image(systemName: "circle.fill").font(.caption2).foregroundStyle(Color.primary) } }
                                            .frame(width: calendarCellSize, height: calendarCellSize)
                                    }.buttonStyle(.plain)
                                        .accessibilityLabel("\(day.start.formatted(date: .complete, time: .omitted)), \(day.total.count) activities, \(day.total.missing > 0 ? "load unavailable" : "load \(Int(day.total.known))")")
                                }
                            }
                        }
                    }
                }
                note("Less → more · dot: load unavailable. Tap a day for activities.")
            }
        }
    }
    private func sourceSummary(_ activities: [ActivityRecord]) -> String {
        let sources = Set(activities.map { $0.primary.source })
        return SourceKind.allCases.filter(sources.contains).map {
            switch $0 { case .garmin: "Garmin"; case .healthKit: "Apple Health"; case .file: "FIT file" }
        }.joined(separator: " · ")
    }
    private func chartLegend(first: String, second: String, firstIsBar: Bool = false, dashed: Bool = false) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) { legendItem(first, secondary: firstIsBar, bar: firstIsBar); legendItem(second, secondary: dashed, dashed: dashed) }
            VStack(alignment: .leading, spacing: 6) { legendItem(first, secondary: firstIsBar, bar: firstIsBar); legendItem(second, secondary: dashed, dashed: dashed) }
        }.font(.caption).foregroundStyle(.secondary)
    }
    private func legendItem(_ title: String, secondary: Bool, bar: Bool = false, dashed: Bool = false) -> some View {
        HStack(spacing: 6) {
            if bar { Rectangle().fill(Color.secondary).frame(width: 10, height: 8) }
            else {
                Path { path in path.move(to: .zero); path.addLine(to: CGPoint(x: 20, y: 0)) }
                    .stroke(secondary ? Color.secondary : Color.primary, style: StrokeStyle(lineWidth: 2, dash: dashed ? [4, 3] : []))
                    .frame(width: 20, height: 2)
            }
            Text(title)
        }.accessibilityElement(children: .combine)
    }
    private func select(_ title: String, from start: Date, to end: Date) {
        selection = TrendsSelection(title: title, activities: presentation.rows.filter { $0.activity.start >= start && $0.activity.start < end }.map(\.activity))
    }
}

private struct TrendsSelection: Identifiable, Hashable {
    var title: String
    var activities: [ActivityRecord]
    var id: String { title }
}
private struct TrendsOptions: Sendable {
    var sport: String; var dateWindow: String; var setting: String
    var measure: TrendMeasure; var period: TrendPeriod; var comparison: String; var recordWindow: String
}
private struct TrendsPresentation: Sendable {
    var rows: [TrendActivity] = []
    var buckets: [TrendBucket] = []
    var days: [TrendBucket] = []
    var curve: [PowerCurvePoint] = []
    var recentCurve: [PowerCurvePoint] = []
    var thresholds: [TrendPoint] = []
    var setThresholds: [TrendPoint] = []
    var efficiency: [TrendPoint] = []
    var regression: [TrendPoint] = []
    var records: [TrendRecord] = []
    var estimate: Double?
    var currentThreshold: Double?
    var staleCount = 0
    static func make(_ history: TrendsHistory, options: TrendsOptions, now: Date = Date(), calendar: Calendar = .current) -> Self {
        let year = calendar.dateInterval(of: .year, for: now)!.start
        let end = now.addingTimeInterval(0.001)
        let sports: [String: Sport] = ["Rides": .cycling, "Walks": .walking, "Runs": .running, "Hikes": .hiking]
        let all = history.matching(FeedFilter(sports: sports[options.sport].map { [$0] },
            setting: options.setting == "All settings" ? nil : options.setting == "Indoor" ? .indoor : .outdoor))
        let first = all.map { $0.activity.start }.min() ?? year
        let start: Date
        switch options.dateWindow {
        case "Last 6 weeks": start = calendar.date(byAdding: .day, value: -42, to: now)!
        case "Last 90 days": start = calendar.date(byAdding: .day, value: -90, to: now)!
        case "This year": start = year
        case "All time": start = min(first, now)
        default: start = calendar.date(byAdding: .year, value: -1, to: now)!
        }
        var result = Self()
        result.rows = all.filter { $0.activity.start >= start && $0.activity.start < end }
        result.staleCount = result.rows.filter(\.isStale).count
        result.buckets = TrendsAggregation.volume(all, range: start..<end, period: options.period, measure: options.measure, calendar: calendar)
        let comparisonStart = options.comparison == "All time" ? first : options.comparison == "This year" ? year : calendar.date(byAdding: .day, value: -90, to: now)!
        result.curve = TrendsAggregation.curve(result.rows.filter { $0.activity.start >= comparisonStart })
        let sixWeeks = calendar.date(byAdding: .day, value: -42, to: now)!
        result.recentCurve = TrendsAggregation.curve(result.rows.filter { $0.activity.start >= sixWeeks })
        result.thresholds = TrendsAggregation.thresholds(all, range: start..<end, calendar: calendar)
        result.currentThreshold = history.profile.thresholdPower(on: now)
        result.estimate = TrendsAggregation.estimate(result.rows, on: now, calendar: calendar)
        result.setThresholds = ([start] + history.profile.thresholdPowerHistory.map(\.effectiveFrom).filter { $0 > start && $0 < end } + [now]).sorted().compactMap { date in
            history.profile.thresholdPower(on: date).map { TrendPoint(date: date, value: $0, activity: nil) }
        }
        result.efficiency = TrendsAggregation.efficiency(result.rows)
        result.regression = TrendsAggregation.regression(result.efficiency)
        result.records = TrendsAggregation.records(result.rows.filter { options.recordWindow == "All time" || $0.activity.start >= year })
        result.days = TrendsAggregation.dailyLoad(result.rows, range: start..<end, calendar: calendar)
        return result
    }
}
