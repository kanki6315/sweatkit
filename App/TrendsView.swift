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
    @State private var selectedPowerDuration: Int?
    @State private var selectedPeriodStart: Date?
    @State private var preparedSelectionContext = ""
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
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        if let summary = selected.summary {
                            Text(summary).font(.title2.bold()).monospacedDigit()
                        }
                        Text(selected.context).font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }
                Section("\(selected.activities.count) \(selected.activities.count == 1 ? "activity" : "activities")") {
                    ForEach(selected.activities, id: \.primary) { row in
                        NavigationLink {
                            ActivityDetailView(activity: row, library: model.library, deleteActivity: model.permanentlyDelete)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(row.title).font(.headline)
                                Text("\(row.start.formatted(.dateTime.day().month().year())) · \(sourceSummary([row]))")
                                    .font(.caption).foregroundStyle(.secondary)
                                if let detail = selected.details[row.primary.description] {
                                    Text(detail).font(.title3.weight(.semibold)).monospacedDigit()
                                }
                                Text(activitySummary(row, omittingDistance: selected.omitDistance))
                                    .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                            }.padding(.vertical, 4)
                        }
                    }
                }
            }.navigationTitle(selected.title).navigationBarTitleDisplayMode(.inline)
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
        let result = await model.trendsPresentationCache.presentation(history, options: options, store: model.library?.store)
        guard !Task.isCancelled, requestedConfiguration == configuration,
              requestedRevision == model.trendsRevision else { return }
        presentation = result
        let context = "\(requestedRevision)|\(requestedConfiguration)"
        if preparedSelectionContext != context {
            selectedPowerDuration = nil
            selectedPeriodStart = nil
            preparedSelectionContext = context
        }
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
                if let latest = selectedPeriod ?? presentation.buckets.last {
                    if typeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 12) { totals(latest) }
                    } else {
                        HStack(alignment: .top, spacing: 12) { totals(latest) }
                    }
                }
                Chart(presentation.buckets) { bucket in
                    if let value = bucket.total.complete {
                        BarMark(x: .value("Period", bucket.start), y: .value(measure.rawValue, scaled(value)))
                            .foregroundStyle(bucket.start == (selectedPeriodStart ?? presentation.buckets.last?.start) ? Color.primary : Color.secondary.opacity(0.65))
                    }
                    if let value = bucket.lastYear.complete, bucket.lastYear.count > 0 {
                        RectangleMark(x: .value("Period", bucket.start), y: .value("Last year", scaled(value)), width: .fixed(18), height: .fixed(2))
                            .foregroundStyle(Color.primary)
                    }
                }.chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: typeSize.isAccessibilitySize ? 3 : 5)) }
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: typeSize.isAccessibilitySize ? 2 : 4)) { AxisValueLabel() } }
                    .chartScrollableAxes(.horizontal)
                    .chartXVisibleDomain(length: period == .week ? 12 * 7 * 86400 : period == .month ? 365 * 86400 : 5 * 365 * 86400)
                    .chartScrollPosition(initialX: presentation.buckets.suffix(12).first?.start ?? Date())
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            if let frame = proxy.plotFrame {
                                Rectangle().fill(.clear).contentShape(Rectangle())
                                    .gesture(SpatialTapGesture().onEnded { tap in
                                        let plot = geometry[frame]
                                        guard plot.contains(tap.location),
                                              let date: Date = proxy.value(atX: tap.location.x - plot.minX) else { return }
                                        selectedPeriodStart = presentation.buckets.min {
                                            abs($0.start.timeIntervalSince(date)) < abs($1.start.timeIntervalSince(date))
                                        }?.start
                                    })
                            }
                        }
                    }
                    .accessibilityIdentifier("volume-chart")
                    .frame(height: typeSize.isAccessibilitySize ? 280 : 180).accessibilityLabel("\(measure.rawValue) by \(period.rawValue.lowercased()). Incomplete periods omitted.")
                chartLegend(first: period.rawValue, second: "Same period last year", firstIsBar: true)
                if presentation.buckets.contains(where: { $0.total.missing > 0 }) {
                    note("\(presentation.buckets.filter { $0.total.missing > 0 }.count) incomplete periods omitted.")
                }
                periodInspection
            }
        }
    }
    private var selectedPeriod: TrendBucket? {
        presentation.buckets.first { $0.start == selectedPeriodStart }
    }
    private var periodInspection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(selectedPeriod.map { periodTitle($0.start) } ?? "Select a period")
                    .font(.headline)
                    .accessibilityIdentifier("period-readout")
                Spacer()
                if selectedPeriod != nil {
                    Button { selectedPeriodStart = nil } label: {
                        Image(systemName: "xmark").frame(width: 44, height: 44)
                    }.accessibilityLabel("Clear period selection")
                }
            }
            if let bucket = selectedPeriod {
                Text("\(bucket.start.formatted(date: .abbreviated, time: .omitted)) – \(bucket.end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
                Text(bucket.total.count == 0 ? "No matching activities" : bucket.total.complete.map {
                    "\(scaled($0).formatted(.number.precision(.fractionLength(0...1)))) \(unit) · \(bucket.total.count) \(bucket.total.count == 1 ? "activity" : "activities")"
                } ?? "\(bucket.total.missing) activities unavailable · Incomplete total")
                    .font(.subheadline).monospacedDigit()
                Button {
                    select(periodTitle(bucket.start), from: bucket.start, to: bucket.end)
                } label: {
                    HStack { Text("View activities"); Spacer(); Image(systemName: "chevron.right").font(.caption.weight(.semibold)) }
                        .frame(minHeight: 44)
                }.accessibilityIdentifier("view-period-activities")
            } else {
                note("Tap a bar to see its activities. Swipe the chart to browse history.")
            }
            // Explicit steps also expose empty/incomplete buckets and avoid requiring a chart gesture.
            HStack {
                Button { movePeriod(-1) } label: { Label("Previous", systemImage: "chevron.left").frame(minHeight: 44) }
                    .disabled(presentation.buckets.isEmpty || selectedPeriodStart == presentation.buckets.first?.start)
                Spacer()
                Button { movePeriod(1) } label: { Label("Next", systemImage: "chevron.right").frame(minHeight: 44) }
                    .disabled(presentation.buckets.isEmpty || selectedPeriodStart == presentation.buckets.last?.start)
            }.font(.subheadline)
        }
    }
    private func movePeriod(_ offset: Int) {
        let buckets = presentation.buckets
        guard !buckets.isEmpty else { return }
        let index = buckets.firstIndex { $0.start == selectedPeriodStart } ?? (buckets.count - 1)
        selectedPeriodStart = buckets[max(0, min(buckets.count - 1, index + (selectedPeriodStart == nil ? 0 : offset)))].start
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
        totalLabel(bucket.total, selectedPeriodStart == nil ? "This period" : "Selected period")
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
                if supportedPowerDurations.isEmpty { note("No valid power windows in this range.") }
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
                        if selectedPowerDuration != nil {
                            RuleMark(x: .value("Duration", powerDuration)).foregroundStyle(Color.secondary)
                        }
                        ForEach(presentation.curve, id: \.duration) { point in
                            if let value = point.power.value {
                                PointMark(x: .value("Seconds", point.duration), y: .value("Watts", value))
                                    .symbolSize(selectedPowerDuration != nil && point.duration == powerDuration ? 65 : 22)
                                    .foregroundStyle(Color.primary)
                            }
                        }
                        if let estimate = presentation.estimate {
                            RuleMark(y: .value("Estimated threshold", estimate)).lineStyle(StrokeStyle(dash: [2, 4]))
                                .foregroundStyle(Color.secondary).annotation(position: .bottom, alignment: .leading) {
                                    if !typeSize.isAccessibilitySize { Text("Estimate \(Int(estimate)) W").font(.caption) }
                                }
                        }
                    }.chartXScale(domain: 5...3600, type: .log)
                        .chartXAxis {
                            AxisMarks(values: typeSize.isAccessibilitySize ? [5, 3600] : [5, 60, 300, 1200, 3600]) { tick in
                                AxisValueLabel {
                                    if let seconds = tick.as(Int.self) {
                                        Text(seconds < 60 ? "\(seconds)s" : seconds < 3600 ? "\(seconds / 60)m" : "1h")
                                    }
                                }
                            }
                        }
                        .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: typeSize.isAccessibilitySize ? 3 : 5)) }
                        .chartYAxisLabel("Watts")
                        .chartXSelection(value: Binding(get: { selectedPowerDuration }, set: { value in
                            // Charts clears its transient selection on lift; retain our inspection.
                            if let value { selectedPowerDuration = value }
                        }))
                        .chartOverlay { proxy in
                            GeometryReader { geometry in
                                if let frame = proxy.plotFrame {
                                    Rectangle().fill(.clear).contentShape(Rectangle())
                                        .simultaneousGesture(SpatialTapGesture().onEnded { tap in
                                            let plot = geometry[frame]
                                            guard plot.contains(tap.location),
                                                  let seconds: Double = proxy.value(atX: tap.location.x - plot.minX) else { return }
                                            selectedPowerDuration = Int(seconds.rounded())
                                        })
                                }
                            }
                        }
                        .accessibilityIdentifier("power-chart")
                        .frame(height: typeSize.isAccessibilitySize ? 300 : 200)
                    if typeSize.isAccessibilitySize, let estimate = presentation.estimate {
                        note("Estimated threshold: \(Int(estimate)) W")
                    }
                    powerInspection
                }

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
    private func durationLabel(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds) sec" : "\(seconds / 60) min"
    }
    private var powerDuration: Int {
        let durations = supportedPowerDurations
        let requested = selectedPowerDuration ?? 1200
        return durations.min { abs(log(Double($0) / Double(max(1, requested)))) < abs(log(Double($1) / Double(max(1, requested)))) } ?? 1200
    }
    private func powerRows(at duration: Int) -> [(row: TrendActivity, watts: Double)] {
        rankedPowerRows(presentation.powerActivities, at: duration)
    }
    private func rankedPowerRows(_ activities: [TrendActivity], at duration: Int) -> [(row: TrendActivity, watts: Double)] {
        activities.compactMap { row in
            guard !row.isStale, let watts = row.curve.first(where: { $0.duration == duration })?.power.value else { return nil }
            return (row, watts)
        }.sorted {
            if $0.watts != $1.watts { return $0.watts > $1.watts }
            if $0.row.activity.start != $1.row.activity.start { return $0.row.activity.start < $1.row.activity.start }
            return $0.row.activity.primary.description < $1.row.activity.primary.description
        }
    }
    private var powerInspection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(selectedPowerDuration == nil ? "Select a duration" : durationLabel(powerDuration))
                    .font(.headline).monospacedDigit()
                    .accessibilityIdentifier("power-duration-readout")
                    .accessibilityElement()
                    .accessibilityLabel("Power duration")
                    .accessibilityValue(selectedPowerDuration == nil ? "No selection" : durationLabel(powerDuration))
                    .accessibilityAdjustableAction { direction in
                        let durations = supportedPowerDurations
                        guard !durations.isEmpty else { return }
                        let current = durations.firstIndex(of: powerDuration) ?? 0
                        selectedPowerDuration = durations[max(0, min(durations.count - 1, current + (direction == .increment ? 1 : -1)))]
                    }
                Spacer()
                if selectedPowerDuration != nil {
                    Button { selectedPowerDuration = nil } label: {
                        Image(systemName: "xmark").frame(width: 44, height: 44)
                    }.accessibilityLabel("Clear power selection")
                        .accessibilityIdentifier("clear-power-selection")
                }
            }
            if selectedPowerDuration != nil {
                powerSource("Last 6 weeks", rows: presentation.recentPowerActivities)
                Divider()
                powerSource(comparison == "90 days" ? "Last 90 days" : comparison, rows: presentation.powerActivities)
                Button { selectPowerActivities() } label: {
                    HStack {
                        Text("View power activities")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }.frame(minHeight: 44)
                }.accessibilityIdentifier("view-power-activities")
            } else {
                note("Tap the curve to compare power and open its source activities.")
            }
        }
    }
    private var supportedPowerDurations: [Int] {
        Set((presentation.curve + presentation.recentCurve).filter { $0.power.value != nil }.map(\.duration)).sorted()
    }
    @ViewBuilder private func powerSource(_ title: String, rows: [TrendActivity]) -> some View {
        let best = rankedPowerRows(rows, at: powerDuration).first
        VStack(alignment: .leading, spacing: 6) {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
            layout {
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                if !typeSize.isAccessibilitySize { Spacer() }
                Text(best.map { "\($0.watts.formatted(.number.precision(.fractionLength(0)))) W" } ?? "Unavailable")
                    .font(.headline).monospacedDigit()
            }
            if let best {
                NavigationLink {
                    ActivityDetailView(activity: best.row.activity, library: model.library, deleteActivity: model.permanentlyDelete)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(best.row.activity.title).font(.body)
                            Text(best.row.activity.start.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityHint("Opens source activity for \(title)")
                    .accessibilityIdentifier("power-source-\(title)")
            }
        }
    }
    private func selectPowerActivities() {
        let rows = powerRows(at: powerDuration)
        selection = TrendsSelection(title: "\(durationLabel(powerDuration)) power", activities: rows.map { $0.row.activity },
            context: "\(sport) · \(setting) · \(comparison) · Highest power first",
            details: Dictionary(uniqueKeysWithValues: rows.map {
                ($0.row.activity.primary.description, "\(durationLabel(powerDuration)) · \($0.watts.formatted(.number.precision(.fractionLength(0)))) W")
            }))
    }
    private func periodTitle(_ date: Date) -> String {
        switch period {
        case .week: "Week of \(date.formatted(.dateTime.month(.abbreviated).day().year()))"
        case .month: date.formatted(.dateTime.month(.wide).year())
        case .year: date.formatted(.dateTime.year())
        }
    }
    private func activitySummary(_ row: ActivityRecord, omittingDistance: Bool = false) -> String {
        let distance = row.distance.map { "\(($0 / (model.units == .metric ? 1000 : 1609.344)).formatted(.number.precision(.fractionLength(1)))) \(model.units == .metric ? "km" : "mi")" } ?? "No distance"
        let time = row.movingTime.map { Duration.seconds($0).formatted(.time(pattern: .hourMinuteSecond)) + " moving" } ?? "Moving time unavailable"
        return omittingDistance ? time : "\(distance) · \(time)"
    }
    private func select(_ title: String, from start: Date, to end: Date) {
        let rows = presentation.rows.filter { $0.activity.start >= start && $0.activity.start < end }
        let total = TrendsAggregation.total(rows, measure: measure)
        let value = scaled(total.known).formatted(.number.precision(.fractionLength(0...1)))
        let summary = total.count == 0 ? "No activities" : total.missing == 0 ? "\(value) \(unit) total" : "\(value) \(unit) recorded · \(total.missing) unavailable"
        let details = Dictionary(uniqueKeysWithValues: rows.map { row in
            let contribution = TrendsAggregation.total([row], measure: measure)
            return (row.activity.primary.description, contribution.complete.map {
                "\(measure.rawValue): \(scaled($0).formatted(.number.precision(.fractionLength(0...1)))) \(unit)"
            } ?? "\(measure.rawValue) unavailable")
        })
        selection = TrendsSelection(title: title, activities: rows.map(\.activity),
            context: "\(sport) · \(setting) · \(measure == .time ? "Moving time" : measure.rawValue)", summary: summary, details: details, omitDistance: measure == .distance)
    }
}

private struct TrendsSelection: Identifiable, Hashable {
    var title: String
    var activities: [ActivityRecord]
    var context: String = ""
    var summary: String? = nil
    var details: [String: String] = [:]
    var omitDistance = false
    var id: String { title }
}
