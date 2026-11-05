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

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                if presentation.charts.isEmpty {
                    ContentUnavailableView("No chart samples", systemImage: "chart.xyaxis.line",
                        description: Text("This recording has no visible samples for these charts."))
                }
                ForEach(presentation.charts) { chart in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(label(chart.kind)).font(.headline)
                        Chart {
                            ForEach(chart.points) { point in
                                LineMark(x: .value("Elapsed minutes", Double(point.second) / 60),
                                         y: .value(label(chart.kind), value(point.value, kind: chart.kind)),
                                         series: .value("Continuous recording", point.segment))
                                    .foregroundStyle(Color.primary)
                                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                                    .symbol(.circle).symbolSize(3)
                            }
                            RuleMark(x: .value("Cursor", scrub / 60)).foregroundStyle(.secondary)
                        }
                        .chartXScale(domain: 0...max(1, Double(detail.input.stream.count - 1) / 60))
                        .chartXAxisLabel("Elapsed minutes")
                        .chartXSelection(value: Binding<Double?>(get: { scrub / 60 }, set: {
                            if let minutes = $0 { scrub = max(0, min(Double(detail.input.stream.count - 1), minutes * 60)) }
                        }))
                        .frame(height: 180)
                        .accessibilityLabel(label(chart.kind))
                        .accessibilityHint("Chart of recorded values over elapsed time. Gaps mean no data.")
                    }
                }
                if let metrics {
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
                if !presentation.laps.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Laps").font(.title2.bold())
                        ForEach(presentation.laps) { lap in
                            Button {
                                selection = lap.range
                                scrub = Double(lap.range.lowerBound)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Lap \(lap.id)").font(.headline)
                                    Text("\(duration(lap.stats.time)) · \(distance(lap.stats.distance))")
                                    if detail.input.sport.family == .cycling {
                                        Text("Average power: \(number(lap.stats.averagePower, suffix: " W"))")
                                            .font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Text("Average heart rate: \(number(lap.stats.averageHeartRate, suffix: " bpm"))")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                            }.tint(.primary)
                            Divider()
                        }
                    }
                }
                Text("Gaps are missing samples. Charts preserve peaks and troughs when reduced for display.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding()
        }
        .monospacedDigit()
    }

    @ViewBuilder private func zones(_ title: String, metric: Metric<TimeInZones>, colors: [RampColor]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title2.bold())
            if let zones = metric.value {
                ForEach(zones.seconds.indices, id: \.self) { index in
                    HStack {
                        RoundedRectangle(cornerRadius: 3).fill(colors[index % colors.count].color)
                            .overlay { RoundedRectangle(cornerRadius: 3).stroke(Color.primary, lineWidth: 1) }
                            .frame(width: 20, height: 20).accessibilityHidden(true)
                        Text(title == "Gradient bands" ? ["Descent", "Flat", "Climb 2–5%", "Climb 5–8%", "Climb over 8%"][index] : "Zone \(index + 1)")
                        Spacer()
                        Text(duration(Double(zones.seconds[index])))
                    }
                }
                LabeledContent("Missing data", value: duration(Double(zones.missing)))
                    .foregroundStyle(.secondary)
            } else {
                Text(unavailable(metric.reason)).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func unavailable(_ reason: UnavailableReason?) -> String {
        switch reason?.rawValue {
        case let value? where value.lowercased().contains("threshold"): "Set the applicable threshold in Settings to calculate zones."
        default: "Unavailable for this recording. Missing values are not counted as zero."
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
        }
    }
    private func value(_ value: Double, kind: DetailChartSeries.Kind) -> Double {
        switch kind {
        case .speed:
            detail.input.sport.family == .onFoot
                ? (units == .metric ? 1000 : 1609.344) / value / 60
                : value * (units == .metric ? 3.6 : 2.236936)
        case .elevation: value * (units == .metric ? 1 : 3.28084)
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
