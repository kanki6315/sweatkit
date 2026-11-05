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
    private var comparison: EffortComparison? {
        guard let baseline else { return nil }
        return RouteComparison.compare(subject.alignment, against: baseline.alignment, clock: clock).value
    }
    var body: some View {
        ScrollView {
            if let comparison, let baseline {
                let frame = comparison.ghost(at: seconds)
                VStack(alignment: .leading, spacing: 0) {
                    RouteMap(line: route.reference.line, frame: frame, satellite: true, follow: follow, coloredRuns: coloredRuns).frame(height: 300)
                        .overlay(alignment: .bottomTrailing) { Text(routeLegend).font(.caption2).padding(6).background(.regularMaterial, in: Capsule()).padding(.trailing, 12).padding(.bottom, 34) }
                    VStack(alignment: .leading, spacing: 16) {
                        if typeSize.isAccessibilitySize {
                            Text("Effort comparison").font(.title.bold())
                            clockPicker(comparison)
                        } else {
                            HStack(alignment: .top) {
                                Text("Effort comparison").font(.title2.bold())
                                Spacer(minLength: 8)
                                clockPicker(comparison).frame(width: 155)
                            }
                        }
                        Text("\(route.name) · \(subject.activity.start.formatted(.dateTime.day().month(.abbreviated))) vs \(baseline.activity.start.formatted(.dateTime.day().month(.abbreviated)))").font(.subheadline).foregroundStyle(Color.secondary)
                        if !comparison.movingTimeIsAvailable { Text("Elapsed time for both efforts: pause positions are unknown.").font(.caption).foregroundStyle(Color.secondary) }
                        if typeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 12) { gapStats(comparison, frame) }
                        } else {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 12, alignment: .leading), count: 3), alignment: .leading, spacing: 12) {
                                gapStats(comparison, frame)
                            }
                        }
                        Text("Time gap (seconds) · negative = ahead, positive = behind").font(.caption).foregroundStyle(Color.secondary)
                        Chart {
                            RuleMark(y: .value("Even", 0)).foregroundStyle(Color.secondary)
                            ForEach(comparison.grid.indices, id: \.self) { i in
                                let point = comparison.grid[i]
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
                    }.padding(20)
                        .background(Color(uiColor: .systemGroupedBackground), in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
                        .padding(.top, -24)
                }.padding(.bottom, 12)
            } else { ContentUnavailableView("Comparison unavailable", systemImage: "chart.xyaxis.line", description: Text("Both efforts must cover the full timed section.")) }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .ignoresSafeArea(edges: .top)
        .toolbarBackground(.hidden, for: .navigationBar)
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
            if let comparison, !comparison.movingTimeIsAvailable { clock = .elapsed }
            await loadStreams()
        }
        .onChange(of: clock) { seconds = 0; playing = false }
        .task(id: playing) {
            guard playing else { return }
            let origin = seconds
            let start = Date()
            while !Task.isCancelled, playing, let comparison {
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
            Text(abs(point?.gap ?? 0) < 0.5 ? "even with baseline" : (point?.gap ?? 0) >= 0 ? "behind baseline" : "ahead of baseline").foregroundStyle(Color.secondary)
        }
        VStack(alignment: .leading) {
            Text(routeDistance(abs(frame.separation), units: units)).font(.title2.bold()).monospacedDigit().frame(minWidth: 85, alignment: .leading)
            Text(abs(frame.separation) < 0.5 ? "together" : frame.separation >= 0 ? "baseline is ahead" : "subject is ahead").foregroundStyle(Color.secondary)
        }
        VStack(alignment: .leading) {
            Text(routeDistance(frame.subjectRouteDistance, units: units)).font(.title2.bold()).monospacedDigit().frame(minWidth: 85, alignment: .leading)
            Text("route distance").foregroundStyle(Color.secondary)
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
            subjectStream = try await library.analysisStream(for: subject.id)
            baselineStream = try await library.analysisStream(for: baseline.id)
            if let stream = subjectStream {
                let profile = try await library.profile()
                let sport = subject.activity.sport, alignment = subject.alignment
                let drawing = await Task.detached(priority: .userInitiated) {
                    ComparisonRouteDrawing.prepare(stream: stream, sport: sport, profile: profile, alignment: alignment)
                }.value
                coloredRuns = drawing.runs; routeLegend = drawing.legend
            }
            error = nil
        } catch { self.error = "Charts couldn’t load. \(error.localizedDescription)" }
    }
    private func sample(_ series: Series?, at time: Double) -> Double? {
        guard let series, time.isFinite, time >= 0 else { return nil }
        let before = Int(time.rounded(.down)), after = Int(time.rounded(.up))
        guard after < series.count, let a = series[before], let b = series[after] else { return nil }
        return a + (b - a) * (time - Double(before))
    }
    private struct PlotPoint: Identifiable {
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
    @ViewBuilder private func pairedChart(_ comparison: EffortComparison, distance: Double) -> some View {
        let first = plot(comparison, subject: true), second = plot(comparison, subject: false)
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
        let first = plot(comparison, subject: true), second = plot(comparison, subject: false)
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
        return VStack(alignment: .leading, spacing: 16) {
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
