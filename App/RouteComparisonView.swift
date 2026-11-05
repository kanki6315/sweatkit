import SwiftUI
import Charts
import SweatKitModel
import SweatKitLibrary
import SweatKitRouteMatching

struct RouteComparisonView: View {
    let route: LibraryRoute
    let subject: RouteEffort
    let library: ActivityLibrary?
    var units = UnitSystem.metric
    private var distanceDivisor: Double { units == .metric ? 1000 : 1609.344 }
    private var distanceLabel: String { units == .metric ? "Route distance (km)" : "Route distance (mi)" }
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var baselineID: SourceIdentity?
    @State private var clock = ComparisonClock.moving
    @State private var seconds = 0.0
    @State private var playing = false
    @State private var follow = false
    @State private var subjectStream: AnalysisStream?
    @State private var baselineStream: AnalysisStream?
    @State private var error: String?
    @State private var coloredRuns: [RouteColoredRun] = []
    @State private var routeLegend = "Route"
    @State private var channel = RouteChartMetric.power
    private var alternatives: [RouteEffort] { route.efforts.filter { $0.id != subject.id } }
    private var baseline: RouteEffort? {
        alternatives.first { $0.id == baselineID } ?? route.ranked.first { $0.id != subject.id } ?? alternatives.first
    }
    @State private var comparisonLoading = true
    @State private var comparison: EffortComparison?
    @State private var gapGrid: [ComparisonGridPoint] = []
    @State private var firstPlot: [PlotPoint] = []
    @State private var secondPlot: [PlotPoint] = []
    var body: some View {
        ScrollView {
            if let comparison, let baseline {
                let frame = comparison.ghost(at: seconds)
                VStack(alignment: .leading, spacing: 0) {
                    RouteMap(line: route.reference.line, frame: frame, satellite: true, follow: follow, coloredRuns: coloredRuns).frame(height: 300)
                        .overlay(alignment: .bottomTrailing) { Text(routeLegend).font(.caption2).padding(6).background(.regularMaterial, in: Capsule()).padding(.trailing, 12).padding(.bottom, 34) }
                    VStack(alignment: .leading, spacing: 12) {
                        if typeSize.isAccessibilitySize {
                            Text(baseline.id == route.ranked.first?.id ? "This effort vs best" : "Effort comparison").font(.title.bold())
                            clockPicker(comparison)
                        } else {
                            HStack(alignment: .top) {
                                Text(baseline.id == route.ranked.first?.id ? "This effort vs best" : "Effort comparison").font(.title2.bold())
                                Spacer(minLength: 8)
                                clockPicker(comparison).frame(width: 155)
                            }
                        }
                        Text("\(route.name) · \(subject.activity.start.formatted(.dateTime.day().month(.abbreviated))) vs \(baseline.activity.start.formatted(.dateTime.day().month(.abbreviated)))").font(.subheadline).foregroundStyle(Color.secondary)
                        SourceAttributionView(sources: subject.activity.members.map(\.source) + baseline.activity.members.map(\.source))
                        if !comparison.movingTimeIsAvailable { Text("Elapsed time for both efforts: pause positions are unknown.").font(.caption).foregroundStyle(Color.secondary) }
                        if typeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 12) { gapStats(comparison, frame) }
                        } else {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 12, alignment: .leading), count: 3), alignment: .leading, spacing: 12) {
                                gapStats(comparison, frame)
                            }
                        }
                        Text("Time gap · ahead / behind").font(.caption).foregroundStyle(Color.secondary)
                        Chart {
                            RuleMark(y: .value("Even", 0)).foregroundStyle(Color.secondary)
                            ForEach(gapGrid.indices, id: \.self) { i in
                                let point = gapGrid[i]
                                LineMark(x: .value(distanceLabel, point.routeDistance / distanceDivisor), y: .value("Seconds behind baseline", point.gap)).foregroundStyle(Color.primary)
                            }
                            RuleMark(x: .value("Cursor", frame.subjectRouteDistance / distanceDivisor)).foregroundStyle(Color.secondary)
                        }.frame(height: 110).padding(8).background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
                        Picker("Paired channel", selection: $channel) {
                            Text("Power").tag(RouteChartMetric.power)
                            Text("Heart rate").tag(RouteChartMetric.heartRate)
                        }.pickerStyle(.segmented)
                        Text("\(channel == .power ? "Power (W)" : "Heart rate (bpm)") · solid: subject · dashed: baseline").font(.caption).foregroundStyle(Color.secondary)
                        pairedChart(comparison, distance: frame.subjectRouteDistance)
                        if let error { Text(error).foregroundStyle(Color.secondary); Button("Reload charts") { Task { await loadStreams() } } }
                        summary(comparison, baseline)
                    }.padding(16)
                        .background(Color(uiColor: .systemGroupedBackground), in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
                        .padding(.top, -24)
                }.padding(.bottom, 12)
            } else if comparisonLoading { ProgressView("Preparing comparison")
            } else { ContentUnavailableView("Comparison unavailable", systemImage: "chart.xyaxis.line", description: Text("Both efforts must cover the full timed section.")) }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .ignoresSafeArea(edges: .top)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom) {
            if let comparison {
                HStack(spacing: 12) {
                    Button(playing ? "Pause" : "Play", systemImage: playing ? "pause.fill" : "play.fill") {
                        if seconds >= duration(comparison) { seconds = 0 }
                        playing.toggle()
                    }.labelStyle(.iconOnly).buttonStyle(.borderedProminent).buttonBorderShape(.circle).controlSize(.large)
                    ZStack {
                        miniTimeline(comparison).allowsHitTesting(false).opacity(0.55)
                        Slider(value: $seconds, in: 0...max(1, duration(comparison)), onEditingChanged: { _ in playing = false })
                            .tint(.primary).accessibilityLabel("Shared comparison clock")
                    }.frame(height: 44)
                    Text(routeTime(seconds)).font(.subheadline.bold()).monospacedDigit().frame(width: 76, alignment: .trailing)
                }.padding(12).background(.regularMaterial, in: Capsule()).padding(.horizontal)

            }
        }
        .toolbar {
            Menu("Comparison options", systemImage: "arrow.up.arrow.down") {
                if let baseline {
                    Picker("Compare against", selection: Binding(get: { Optional(baseline.id) }, set: { baselineID = $0 })) {
                        ForEach(alternatives) { effort in Text(effort.activity.start, style: .date).tag(Optional(effort.id)) }
                    }
                    Button("Best") { baselineID = route.ranked.first { $0.id != subject.id }?.id }
                    Button("Previous") { baselineID = alternatives.filter { $0.activity.start < subject.activity.start }.max { $0.activity.start < $1.activity.start }?.id }
                        .disabled(!alternatives.contains { $0.activity.start < subject.activity.start })
                }
                Toggle("Follow subject", isOn: $follow)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task(id: baseline?.id) {
            seconds = 0; playing = false
            await loadStreams()
        }
        .task(id: "\(baseline?.id.description ?? "")-\(clock)") {
            comparisonLoading = true
            comparison = nil; gapGrid = []; firstPlot = []; secondPlot = []
            guard let baseline else { comparisonLoading = false; return }
            let subjectAlignment = subject.alignment, baselineAlignment = baseline.alignment, requestedClock = clock
            let worker = Task.detached(priority: .userInitiated) {
                RouteComparison.compare(subjectAlignment, against: baselineAlignment, clock: requestedClock).value
            }
            let result = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard !Task.isCancelled else { return }
            comparison = result
            comparisonLoading = false
            if let result, !result.movingTimeIsAvailable, clock != .elapsed { clock = .elapsed }
            refreshPlots()
        }
        .onChange(of: clock) { seconds = 0; playing = false }
        .onChange(of: channel) { refreshPlots() }
        .onChange(of: units) { refreshPlots() }
        .onChange(of: scenePhase) { if scenePhase != .active { playing = false } }
        .task(id: playing) {
            guard playing, let comparison else { return }
            let origin = seconds
            let start = Date()
            while !Task.isCancelled, playing {
                seconds = min(duration(comparison), origin + Date().timeIntervalSince(start) * 30)
                if seconds >= duration(comparison) { playing = false; break }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        .onDisappear { playing = false }
    }
    private func duration(_ comparison: EffortComparison) -> Double { max(comparison.subjectTimes.duration, comparison.baselineTimes.duration) }
    @ViewBuilder private func gapStats(_ comparison: EffortComparison, _ frame: GhostFrame) -> some View {
        let point = comparison.grid.min { abs($0.routeDistance - frame.subjectRouteDistance) < abs($1.routeDistance - frame.subjectRouteDistance) }
        VStack(alignment: .leading) {
            Text(routeTime(point?.gap)).font(.title2.bold()).monospacedDigit().frame(minWidth: 85, alignment: .leading)
            Text(abs(point?.gap ?? 0) < 0.5 ? "even with baseline" : (point?.gap ?? 0) >= 0 ? "behind baseline" : "ahead of baseline").font(.caption).foregroundStyle(Color.secondary)
        }
        VStack(alignment: .leading) {
            Text(routeDistance(abs(frame.separation), units: units)).font(.title2.bold()).monospacedDigit().frame(minWidth: 85, alignment: .leading)
            Text(abs(frame.separation) < 0.5 ? "together" : frame.separation >= 0 ? "baseline is ahead" : "subject is ahead").font(.caption).foregroundStyle(Color.secondary)
        }
        VStack(alignment: .leading) {
            Text(routeDistance(frame.subjectRouteDistance, units: units)).font(.title2.bold()).monospacedDigit().frame(minWidth: 85, alignment: .leading)
            Text("route distance").font(.caption).foregroundStyle(Color.secondary)
        }
    }
    @ViewBuilder private func clockPicker(_ comparison: EffortComparison) -> some View {
        Picker("Clock", selection: $clock) {
            Text("Moving").tag(ComparisonClock.moving).disabled(!comparison.movingTimeIsAvailable)
            Text("Elapsed").tag(ComparisonClock.elapsed)
        }.pickerStyle(.segmented)
    }
    private func loadStreams() async {
        subjectStream = nil; baselineStream = nil; coloredRuns = []
        guard let library, let baseline else { return }
        do {
            let subjectData = try await library.analysisStream(for: subject.id)
            let baselineData = try await library.analysisStream(for: baseline.id)
            try Task.checkCancellation()
            subjectStream = subjectData; baselineStream = baselineData
            refreshPlots()
            if let stream = subjectStream {
                let profile = try await library.profile()
                let sport = subject.activity.sport, alignment = subject.alignment
                let drawing = await Task.detached(priority: .userInitiated) {
                    ComparisonRouteDrawing.prepare(stream: stream, sport: sport, profile: profile, alignment: alignment)
                }.value
                try Task.checkCancellation()
                coloredRuns = drawing.runs; routeLegend = drawing.legend
            }
            error = nil
        } catch is CancellationError {
        } catch { self.error = "Charts couldn’t load. \(error.localizedDescription)" }
    }
    private func sample(_ series: Series?, at time: Double) -> Double? {
        guard let series, time.isFinite, time >= 0 else { return nil }
        let before = Int(time.rounded(.down)), after = Int(time.rounded(.up))
        guard after < series.count, let a = series[before], let b = series[after] else { return nil }
        return a + (b - a) * (time - Double(before))
    }
    private struct PlotPoint: Identifiable, Sendable {
        let id: Int; let distance: Double; let clock: Double; let value: Double; let segment: Int
    }
    private func plot(_ comparison: EffortComparison, subject: Bool) -> [PlotPoint] {
        let stream = subject ? subjectStream : baselineStream
        let series = channel == .power ? stream?.power : stream?.heartRate
        var segment = 0
        return comparison.grid.enumerated().compactMap { index, point in
            guard let value = sample(series, at: subject ? point.subjectElapsedTime : point.baselineElapsedTime) else { segment += 1; return nil }
            return PlotPoint(id: index, distance: point.routeDistance / distanceDivisor, clock: subject ? point.subjectClock : point.baselineClock, value: value, segment: segment)
        }
    }
    private func refreshPlots() {
        guard let comparison else { return }
        gapGrid = reduced(comparison.grid, value: { $0.gap })
        firstPlot = reduced(plot(comparison, subject: true), value: { $0.value })
        secondPlot = reduced(plot(comparison, subject: false), value: { $0.value })
    }

    /// Bound chart work while retaining each bucket's endpoints and extrema.
    /// Plot points keep their original segment IDs so missing samples stay gaps.
    private func reduced<T>(_ points: [T], value: (T) -> Double, budget: Int = 600) -> [T] {
        guard points.count > budget else { return points }
        let width = Int(ceil(Double(points.count) / Double(budget / 4)))
        var output: [T] = []
        for start in stride(from: 0, to: points.count, by: width) {
            let end = min(start + width, points.count)
            let indices = start..<end
            let low = indices.min { value(points[$0]) < value(points[$1]) }!
            let high = indices.max { value(points[$0]) < value(points[$1]) }!
            output += Set([start, low, high, end - 1]).sorted().map { points[$0] }
        }
        return output
    }

    @ViewBuilder private func pairedChart(_ comparison: EffortComparison, distance: Double) -> some View {
        let first = firstPlot, second = secondPlot
        if first.isEmpty && second.isEmpty { Text("\(channel.rawValue) unavailable for both efforts.").foregroundStyle(Color.secondary) }
        else {
            Chart {
                ForEach(first) { point in
                    LineMark(x: .value(distanceLabel, point.distance), y: .value(channel.rawValue, point.value), series: .value("Segment", "subject-\(point.segment)")).foregroundStyle(Color.primary)
                }
                ForEach(second) { point in
                    LineMark(x: .value(distanceLabel, point.distance), y: .value(channel.rawValue, point.value), series: .value("Segment", "baseline-\(point.segment)")).foregroundStyle(Color.secondary).lineStyle(StrokeStyle(dash: [5, 3]))
                }
                RuleMark(x: .value("Cursor", distance / distanceDivisor)).foregroundStyle(Color.secondary)
            }.frame(height: 110).padding(8).background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
            .accessibilityLabel("\(channel.rawValue), \(channel == .power ? "watts" : "beats per minute"), by route distance. Solid subject, dashed baseline. Missing samples are gaps.")
            if first.isEmpty || second.isEmpty { Text("\(first.isEmpty ? "Subject" : "Baseline") \(channel.rawValue.lowercased()) unavailable.").font(.caption) }
        }
    }
    @ViewBuilder private func miniTimeline(_ comparison: EffortComparison) -> some View {
        let first = firstPlot, second = secondPlot
        if first.isEmpty && second.isEmpty { Text("Samples unavailable").font(.caption2).foregroundStyle(Color.secondary) }
        else {
            Chart {
                ForEach(first) { point in
                    LineMark(x: .value("Clock", point.clock), y: .value(channel.rawValue, point.value), series: .value("Segment", "s-\(point.segment)")).foregroundStyle(Color.primary).lineStyle(StrokeStyle(lineWidth: 1))
                }
                ForEach(second) { point in
                    LineMark(x: .value("Clock", point.clock), y: .value(channel.rawValue, point.value), series: .value("Segment", "b-\(point.segment)")).foregroundStyle(Color.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 2]))
                }
                RuleMark(x: .value("Cursor", seconds)).foregroundStyle(Color.primary).lineStyle(StrokeStyle(lineWidth: 2))
            }.chartXScale(domain: 0...max(1, duration(comparison))).chartXAxis(.hidden).chartYAxis(.hidden).accessibilityHidden(true)
        }
    }
    private struct SummaryRow: Identifiable {
        let title: String; let subject: String; let baseline: String; let difference: String
        var id: String { title }
    }
    private func summary(_ comparison: EffortComparison, _ baseline: RouteEffort) -> some View {
        let speedFactor = units == .metric ? 3.6 : 2.236936
        let timed = [
            SummaryRow(title: "\(comparison.clock == .moving ? "Moving" : "Elapsed") time", subject: routeTime(comparison.subjectTimes.duration), baseline: routeTime(comparison.baselineTimes.duration), difference: signedTime(comparison.subjectTimes.duration - comparison.baselineTimes.duration)),
            row("Speed (\(units == .metric ? "km/h" : "mph"))", comparison.section.length / comparison.subjectTimes.duration * speedFactor, comparison.section.length / comparison.baselineTimes.duration * speedFactor)
        ]
        let whole = [
            row("Weighted power (W)", subject.metrics?.power.weighted.value, baseline.metrics?.power.weighted.value),
            row("Heart rate (bpm)", subject.metrics?.heartRate.average.value, baseline.metrics?.heartRate.average.value),
            row("Efficiency", RouteChartMetric.efficiency.value(subject), RouteChartMetric.efficiency.value(baseline))
        ]
        return VStack(alignment: .leading, spacing: 12) {
            Text("Timed section").font(.headline)
            summaryTable(timed)
            Text("Whole-activity measurements").font(.headline)
            summaryTable(whole)
        }.padding().background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }
    @ViewBuilder private func summaryTable(_ rows: [SummaryRow]) -> some View {
        if typeSize.isAccessibilitySize {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 6) {
                    Text(row.title).font(.headline)
                    Text("Subject: \(row.subject)")
                    Text("Baseline: \(row.baseline)")
                    Text("Difference: \(row.difference)")
                }.monospacedDigit()
            }
        } else {
            Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 12) {
                GridRow {
                    Text("Metric").gridColumnAlignment(.leading)
                    Text("Subject"); Text("Baseline"); Text("Diff")
                }.foregroundStyle(Color.secondary)
                ForEach(rows) { row in
                    GridRow {
                        Text(row.title).foregroundStyle(Color.secondary)
                        Text(row.subject); Text(row.baseline); Text(row.difference)
                    }
                }
            }.font(.caption).monospacedDigit().frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func row(_ title: String, _ a: Double?, _ b: Double?) -> SummaryRow {
        SummaryRow(title: title, subject: number(a), baseline: number(b), difference: number(a.flatMap { a in b.map { a - $0 } }, signed: true))
    }
    private func signedTime(_ value: Double) -> String { (abs(value) < 0.5 ? "" : value > 0 ? "+" : "−") + routeTime(value) }
    private func number(_ value: Double?, signed: Bool = false) -> String {
        guard let value, value.isFinite else { return "Unavailable" }
        let normalized = abs(value) < 0.05 ? 0 : value
        return (signed && normalized > 0 ? "+" : "") + String(format: "%.1f", normalized)
    }
}
