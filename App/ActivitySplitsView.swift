import SwiftUI
import SweatKitAnalysis
import SweatKitModel

/// Splits retain kilometre boundaries in both unit systems. Pace and ascent
/// respect the selected units; the title makes those boundaries explicit.
struct ActivitySplitsView: View {
    let splits: Metric<[Split]>
    let units: UnitSystem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Kilometre splits").font(.headline)
            Text("Pace uses timer time, excluding recorded pauses.")
                .font(.caption).foregroundStyle(.secondary)
            if let values = splits.value {
                ForEach(values.filter { $0.distance > 0 }, id: \.index) { split in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Km \(split.index + 1)").font(.headline)
                            if split.distance < 1000 {
                                Text("\(Int(split.distance.rounded())) m").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(duration(split.duration)).font(.subheadline)
                        }
                        ViewThatFits(in: .horizontal) {
                            HStack { self.values(split); Spacer(minLength: 0) }
                            VStack(alignment: .leading, spacing: 6) { self.values(split) }
                        }.font(.subheadline)
                    }
                    .accessibilityElement(children: .combine)
                    Divider()
                }
            } else {
                Text(splits.reason == .pausePositionsUnknown ? "Splits need reliable pause timing." : "No distance samples for splits.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }.monospacedDigit().padding(14)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder private func values(_ split: Split) -> some View {
        Text(split.pace.value.map { "\(duration($0 * (units == .metric ? 1 : 1.609344))) /\(units == .metric ? "km" : "mi")" } ?? "Pace unavailable")
        Text(split.averageHeartRate.value.map { "\(Int($0.rounded())) bpm" } ?? "No heart-rate samples")
        Text(split.ascent.value.map { "Ascent \(Int(($0 * (units == .metric ? 1 : 3.28084)).rounded())) \(units == .metric ? "m" : "ft")" } ?? "No elevation samples")
            .accessibilityLabel(split.ascent.value.map { "Ascent \(Int(($0 * (units == .metric ? 1 : 3.28084)).rounded())) \(units == .metric ? "metres" : "feet")" } ?? "Ascent unavailable")
    }
    private func duration(_ seconds: Double) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
    }
}
