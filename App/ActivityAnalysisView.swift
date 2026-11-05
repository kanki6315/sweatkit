import SwiftUI
import Charts
import SweatKitAnalysis
import SweatKitDetail
import SweatKitModel
import SweatKitPalette

struct ActivityAnalysisView: View {
    let presentation: DetailAnalysisPresentation
    let detail: PreparedDetail
    let metrics: ActivityMetrics?
    let units: UnitSystem
    @Binding var scrub: Double
    @Binding var selection: ClosedRange<Int>?

    var chartsOnly = false
    var historicalCurve: [PowerCurvePoint] = []
    var historicalCurveError: String?
    var historicalCurveLoading = false
    @Binding var historyWindow: Int

    init(presentation: DetailAnalysisPresentation, detail: PreparedDetail, metrics: ActivityMetrics?, units: UnitSystem, scrub: Binding<Double>, selection: Binding<ClosedRange<Int>?>, chartsOnly: Bool = false, historicalCurve: [PowerCurvePoint] = [], historicalCurveError: String? = nil, historicalCurveLoading: Bool = false, historyWindow: Binding<Int> = .constant(90)) {
        self.presentation = presentation; self.detail = detail; self.metrics = metrics; self.units = units
        self._scrub = scrub; self._selection = selection; self.chartsOnly = chartsOnly
        self.historicalCurve = historicalCurve; self.historicalCurveError = historicalCurveError; self.historicalCurveLoading = historicalCurveLoading; self._historyWindow = historyWindow
    }
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var fullPaceRange = false
    @ScaledMetric(relativeTo: .body) private var summaryColumnWidth: CGFloat = 105

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if !chartsOnly, let metrics { summary(metrics) }
                if presentation.charts.isEmpty {
                    ContentUnavailableView("No chart samples", systemImage: "chart.xyaxis.line",
                        description: Text("This recording has no visible samples for these charts."))
                }
                if !chartsOnly, let metrics {
                    if detail.input.sport.family == .cycling {
                        zones("Power zones", metric: metrics.timeInPowerZones, colors: EffortPalette.power)
                    }
                    zones("Heart-rate zones", metric: metrics.timeInHeartRateZones, colors: EffortPalette.heartRate)
                    if ResolvedZones.heartRate(profile: detail.input.profile).isStarter ||
                        (detail.input.sport.family == .cycling && ResolvedZones.power(profile: detail.input.profile, on: detail.input.activityDate).isStarter) {
                        Text("Starter zones use assumed thresholds where your profile has none: 200 W for power and 170 bpm for heart rate. Personalize zones in Settings.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    zones("Gradient bands", metric: metrics.timeInGradientBands, colors: EffortPalette.gradient)
                }
                if !chartsOnly, !presentation.powerCurve.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Power curve").font(.headline)
                            Spacer()
                            Picker("Historical power window", selection: $historyWindow) {
                                Text("90 days").tag(90)
                                Text("This year").tag(365)
                                Text("All time").tag(0)
                            }.pickerStyle(.menu).font(.caption)
                        }
                        Text(historicalCurveLoading ? "Loading historical comparison…" : historicalCurve.isEmpty ? (historicalCurveError ?? "No earlier power curve in this window") : "This activity — · Historical best – –")
                            .font(.caption).foregroundStyle(.secondary)
                        Chart {
                            ForEach(historicalCurve.filter { $0.power.value != nil }, id: \.duration) { point in
                                LineMark(x: .value("Duration, seconds", point.duration), y: .value("Power, W", point.power.value!), series: .value("Curve", "Historical best"))
                                    .foregroundStyle(Color.secondary).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            }
                            ForEach(presentation.powerCurve.filter { $0.power.value != nil }, id: \.duration) { point in
                            LineMark(x: .value("Duration, seconds", point.duration), y: .value("Power, W", point.power.value!), series: .value("Curve", "Activity"))
                                .foregroundStyle(Color.primary).lineStyle(StrokeStyle(lineWidth: 2))
                            }
                        }
                        .chartXScale(type: .log).frame(height: 160)
                        DisclosureGroup("All best efforts") {
                        ForEach(presentation.powerCurve, id: \.duration) { point in
                            VStack(alignment: .leading, spacing: 4) {
                                LabeledContent(duration(Double(point.duration)), value: number(point.power.value, suffix: " W"))
                                if let reason = point.power.reason { Text(unavailable(reason)).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                        }.font(.subheadline)
                    }.padding(16).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                }
                if !chartsOnly, !presentation.laps.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Laps").font(.headline)
                        ForEach(presentation.laps) { lap in
                            Button {
                                selection = lap.range
                                scrub = Double(lap.range.lowerBound)
                            } label: {
                                ViewThatFits(in: .horizontal) {
                                    HStack(spacing: 12) {
                                        Text(String(lap.id)).frame(width: 24, alignment: .leading)
                                        Text(distance(lap.stats.distance)).frame(maxWidth: .infinity, alignment: .trailing)
                                        Text(duration(lap.stats.time)).frame(maxWidth: .infinity, alignment: .trailing)
                                        if detail.input.sport.family == .cycling {
                                            Text(number(lap.stats.averagePower, suffix: " W")).frame(maxWidth: .infinity, alignment: .trailing)
                                        }
                                        Text(number(lap.stats.averageHeartRate, suffix: " bpm")).frame(maxWidth: .infinity, alignment: .trailing)
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Lap \(lap.id) · \(distance(lap.stats.distance)) · \(duration(lap.stats.time))")
                                        Text("\(number(lap.stats.averagePower, suffix: " W")) · \(number(lap.stats.averageHeartRate, suffix: " bpm"))")
                                    }
                                }.font(.caption).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .accessibilityElement(children: .combine)
                            }.tint(.primary)
                            Divider()
                        }
                    }
                }
                if !chartsOnly, let metrics, detail.input.sport == .walking || detail.input.sport == .running {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Best efforts in this activity").font(.title2.bold())
                        ForEach(metrics.bestDistances, id: \.distance) { effort in
                            VStack(alignment: .leading, spacing: 4) {
                                LabeledContent(distance(effort.distance), value: duration(effort.time.value))
                                if let reason = effort.time.reason { Text(unavailable(reason)).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
                ForEach(presentation.charts) { chart in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(label(chart.kind)).font(.headline)
                            Spacer()
                            Text(cursorValue(chart.kind)).font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary).frame(minWidth: 72, alignment: .trailing)
                        }
                        if isPace(chart.kind) {
                            Toggle("Full pace range", isOn: $fullPaceRange).font(.subheadline)
                            Text(fullPaceRange ? "Full recorded range. Gaps indicate missing samples or zero speed." : "Scale limited to \(PaceChartScale.ceiling(units: units), specifier: "%.1f") min/\(units == .metric ? "km" : "mi"). Slower samples appear as triangles at the limit; cursor values remain exact. Gaps indicate missing samples or zero speed.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Chart {
                            ForEach(chart.points) { point in
                                if chartsOnly && chart.kind == .power {
                                    RectangleMark(x: .value("Elapsed minutes", Double(point.second) / 60),
                                        yStart: .value("Baseline", 0), yEnd: .value("Power", point.value), width: .fixed(2))
                                        .foregroundStyle(powerColor(at: point.second))
                                }
                                LineMark(x: .value("Elapsed minutes", Double(point.second) / 60),
                                         y: .value(label(chart.kind), plottedValue(point.value, kind: chart.kind)),
                                         series: .value("Continuous recording", point.segment))
                                    .foregroundStyle(Color.primary)
                                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                                    .symbol(.circle).symbolSize(3)
                                if isPace(chart.kind), !fullPaceRange,
                                   value(point.value, kind: chart.kind) > PaceChartScale.ceiling(units: units) {
                                    PointMark(x: .value("Elapsed minutes", Double(point.second) / 60),
                                              y: .value("Beyond pace scale", PaceChartScale.ceiling(units: units)))
                                        .symbol(.triangle).symbolSize(24).foregroundStyle(Color.primary)
                                }
                            }
                            RuleMark(x: .value("Cursor", scrub / 60)).foregroundStyle(Color.secondary)
                        }
                        .chartXScale(domain: 0...max(1, Double(detail.input.stream.count - 1) / 60))
                        .chartXAxisLabel("Elapsed minutes")
                        .chartXSelection(value: Binding<Double?>(get: { scrub / 60 }, set: {
                            if let minutes = $0 { scrub = max(0, min(Double(detail.input.stream.count - 1), minutes * 60)) }
                        }))
                        .frame(height: chartsOnly ? 140 : 180)
                        .accessibilityLabel(label(chart.kind))
                        .accessibilityHint("Chart of recorded values over elapsed time. Gaps mean no data.")
                    }
                }
                Text("Gaps are missing samples. Charts preserve peaks and troughs when reduced for display.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding()
        }
        .monospacedDigit()
        .background(Color(uiColor: chartsOnly ? .systemBackground : .systemGroupedBackground))
    }

    private func powerColor(at second: Int) -> Color {
        guard let bands = detail.bands[.power]?.value, bands.bands.indices.contains(second),
              let band = bands.bands[second], EffortPalette.power.indices.contains(band) else { return .secondary }
        return EffortPalette.power[band].color
    }
    private func isPace(_ kind: DetailChartSeries.Kind) -> Bool {
        kind == .speed && detail.input.sport.family == .onFoot
    }
    private func plottedValue(_ raw: Double, kind: DetailChartSeries.Kind) -> Double {
        let converted = value(raw, kind: kind)
        return isPace(kind) && !fullPaceRange ? min(converted, PaceChartScale.ceiling(units: units)) : converted
    }
    private func cursorValue(_ kind: DetailChartSeries.Kind) -> String {
        let stream = detail.input.stream
        let series: Series
        switch kind {
        case .power: series = stream.power
        case .heartRate: series = stream.heartRate
        case .speed: series = stream.speed
        case .cadence: series = stream.cadence
        case .elevation: series = stream.altitude
        case .runningStrideLength: series = stream.runningStrideLength
        case .runningGroundContactTime: series = stream.runningGroundContactTime
        case .runningVerticalOscillation: series = stream.runningVerticalOscillation
        }
        let index = Int(scrub)
        guard index >= 0, index < series.count, let raw = series[index], raw.isFinite else { return "No data" }
        if isPace(kind) && raw <= 0 { return "Stopped" }
        return String(format: "%.1f", value(raw, kind: kind))
    }

    private func summary(_ metrics: ActivityMetrics) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Summary").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: summaryColumnWidth), alignment: .topLeading)], alignment: .leading, spacing: 14) {
                summaryValue("Moving time", text: duration(metrics.time.moving.value), reason: metrics.time.moving.reason)
                summaryValue("Distance", text: distance(metrics.distance.value), reason: metrics.distance.reason)
                summaryValue("Ascent", text: number(metrics.ascent.value.map { $0 * (units == .metric ? 1 : 3.28084) }, suffix: units == .metric ? " m" : " ft"), reason: metrics.ascent.reason)
                if detail.input.sport.family == .cycling {
                    summaryValue("Weighted power", text: number(metrics.power.weighted.value, suffix: " W"), reason: metrics.power.weighted.reason)
                    summaryValue("Average power", text: number(metrics.power.average.value, suffix: " W"), reason: metrics.power.average.reason)
                    summaryValue("Intensity", text: metrics.power.intensity.value.map { String(format: "%.2f", $0) } ?? "—", reason: metrics.power.intensity.reason)
                    summaryValue(metrics.power.work.value?.isRecordedOnly == true ? "Recorded work" : "Work", text: number(metrics.power.work.value?.kilojoules, suffix: " kJ"), reason: metrics.power.work.reason)
                    summaryValue("Variability", text: metrics.power.variability.value.map { String(format: "%.2f", $0) } ?? "—", reason: metrics.power.variability.reason)
                }
                summaryValue(metrics.load.value?.source == .heartRate ? "Heart-rate load" : "Load", text: number(metrics.load.value?.value, suffix: ""), reason: metrics.load.reason)
                summaryValue("Average heart rate", text: number(metrics.heartRate.average.value, suffix: " bpm"), reason: metrics.heartRate.average.reason)
            }
            if metrics.power.averageShowsCoverage, let coverage = metrics.power.coverage.value {
                Text("Power coverage: \(coverage * 100, specifier: "%.0f")% of timer time.").font(.footnote).foregroundStyle(.secondary)
            }
        }.padding(16).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }
    private func summaryValue(_ label: String, text: String, reason: UnavailableReason?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text).font(.title3.bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
            if let reason { Text(unavailable(reason)).font(.caption).foregroundStyle(.secondary) }
        }.accessibilityElement(children: .combine)
    }

    private func zoneDescription(_ title: String, index: Int) -> String {
        if title == "Gradient bands" { return ["Descent · below −2%", "Flat · −2 to 2%", "Climb · 2–5%", "Climb · 5–8%", "Climb · over 8%"][index] }
        let power = title == "Power zones"
        let resolved = power ? ResolvedZones.power(profile: detail.input.profile, on: detail.input.activityDate) : ResolvedZones.heartRate(profile: detail.input.profile)
        let bounds = resolved.absoluteBounds
        let name = power ? ["Recovery", "Endurance", "Tempo", "Threshold", "VO₂ max", "Anaerobic", "Neuromuscular"][index] : ["Recovery", "Endurance", "Tempo", "Threshold", "Above threshold"][index]
        let range: String
        if index == 0 { range = "<\(Int(bounds[0].rounded(.up)))" }
        else if index == bounds.count { range = "≥\(Int(bounds[index - 1].rounded(.up)))" }
        else { range = "\(Int(bounds[index - 1].rounded(.up)))–\(Int(bounds[index].rounded(.up)) - 1)" }
        return "\(name) · \(range) \(power ? "W" : "bpm")"
    }

    @ViewBuilder private func zones(_ title: String, metric: Metric<TimeInZones>, colors: [RampColor]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                if title == "Power zones", let threshold = detail.input.profile.thresholdPower(on: detail.input.activityDate) {
                    Text("Threshold \(threshold, specifier: "%.0f") W").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let zones = metric.value {
                ForEach(zones.seconds.indices, id: \.self) { index in
                    HStack(alignment: .center, spacing: 8) {
                        Text(title == "Gradient bands" ? "" : "Z\(index + 1)")
                            .font(.caption2.weight(.semibold)).frame(width: title == "Gradient bands" ? 8 : 24, height: 18)
                            .background(colors[index % colors.count].color.opacity(0.25), in: RoundedRectangle(cornerRadius: 4))
                            .overlay { RoundedRectangle(cornerRadius: 4).stroke(colors[index % colors.count].color, lineWidth: 1) }
                        VStack(alignment: .leading, spacing: 5) {
                            Text(zoneDescription(title, index: index)).font(.caption).foregroundStyle(.secondary)
                            GeometryReader { geometry in
                                Capsule().fill(Color.secondary.opacity(0.12))
                                Capsule().fill(colors[index % colors.count].color)
                                    .overlay { Capsule().stroke(Color.primary.opacity(0.3), lineWidth: 0.5) }
                                    .frame(width: max(0, geometry.size.width * Double(zones.seconds[index]) / Double(max(1, zones.seconds.reduce(0, +)))))
                            }.frame(height: 5).accessibilityHidden(true)
                        }
                        Text(duration(Double(zones.seconds[index]))).font(.caption.monospacedDigit()).frame(minWidth: 52, alignment: .trailing)
                        Text("\(100 * Double(zones.seconds[index]) / Double(max(1, zones.seconds.reduce(0, +))), specifier: "%.0f")%")
                            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary).frame(width: 30, alignment: .trailing)
                    }.frame(minHeight: typeSize.isAccessibilitySize ? 50 : 30)
                        .accessibilityElement(children: .combine)
                }
                LabeledContent("Missing data", value: duration(Double(zones.missing)))
                    .foregroundStyle(.secondary)
            } else {
                Text(unavailable(metric.reason)).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func unavailable(_ reason: UnavailableReason?) -> String {
        switch reason {
        case .noThresholdPower: "Set threshold power for this activity date in Settings."
        case .noThresholdHeartRate: "Set threshold or maximum heart rate in Settings."
        case .pausePositionsUnknown: "Pause timing is unknown."
        case .tooLittlePower: "Too little recorded power for weighted power."
        case .tooFewValidWindows: "Too few complete power windows."
        case .lowHeartRateCoverage: "Heart-rate coverage is too low for load."
        case .noValidWindow: "No eligible window of this duration."
        case .distanceNotCovered: "Distance not covered."
        case .noDistance: "No recorded distance samples."
        case .noPower: "No recorded power."
        case .noHeartRate: "No recorded heart rate."
        case .noAltitude: "No recorded elevation."
        case .noGradient: "No gradient samples."
        default: "Unavailable for this recording."
        }
    }

    private func label(_ kind: DetailChartSeries.Kind) -> String {
        switch kind {
        case .power: "Power (W)"
        case .heartRate: "Heart rate (bpm)"
        case .speed:
            detail.input.sport.family == .onFoot
                ? (units == .metric ? "Pace (min/km)" : "Pace (min/mi)")
                : (units == .metric ? "Speed (km/h)" : "Speed (mph)")
        case .cadence: detail.input.sport.family == .cycling ? "Cadence (rpm)" : "Cadence (steps/min)"
        case .elevation: units == .metric ? "Elevation (m)" : "Elevation (ft)"
        case .runningStrideLength: units == .metric ? "Stride length (m)" : "Stride length (ft)"
        case .runningGroundContactTime: "Ground contact time (ms)"
        case .runningVerticalOscillation: units == .metric ? "Vertical oscillation (cm)" : "Vertical oscillation (in)"
        }
    }
    private func value(_ value: Double, kind: DetailChartSeries.Kind) -> Double {
        switch kind {
        case .speed:
            detail.input.sport.family == .onFoot
                ? (units == .metric ? 1000 : 1609.344) / value / 60
                : value * (units == .metric ? 3.6 : 2.236936)
        case .elevation, .runningStrideLength: value * (units == .metric ? 1 : 3.28084)
        case .runningGroundContactTime: value * 1000
        case .runningVerticalOscillation: value * (units == .metric ? 100 : 39.370079)
        default: value
        }
    }
    private func duration(_ seconds: Double?) -> String {
        seconds.map { Duration.seconds($0).formatted(.time(pattern: .hourMinuteSecond)) } ?? "No data"
    }
    private func number(_ value: Double?, suffix: String) -> String { value.map { String(format: "%.0f", $0) + suffix } ?? "No data" }
    private func distance(_ metres: Double?) -> String {
        metres.map { String(format: "%.2f %@", $0 / (units == .metric ? 1000 : 1609.344), units == .metric ? "km" : "mi") } ?? "No distance"
    }
}
