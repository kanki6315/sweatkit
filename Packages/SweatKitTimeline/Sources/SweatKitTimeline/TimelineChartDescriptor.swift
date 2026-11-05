import Accessibility
import Foundation
import SweatKitModel
import SwiftUI

/// The timeline as an audio graph: VoiceOver can describe it and play the
/// elevation profile and the overlay as tones.
struct TimelineChartDescriptor: AXChartDescriptorRepresentable {
    /// How many points each series is played from.
    static let columns = 120

    let prepared: PreparedTimeline
    let overlay: PreparedOverlay?
    /// The axis in use, already resolved.
    let key: AxisKey
    let sport: Sport
    let units: UnitSystem
    let locale: Locale

    var summary: String {
        TimelineDescription.summary(
            elevation: prepared.elevationRange,
            overlay: overlay.map { ($0.kind, $0.range) },
            lapBoundaries: prepared.data.lapBoundaries.count,
            stops: prepared.data.stops.count,
            sport: sport, units: units, locale: locale
        )
    }

    func makeChartDescriptor() -> AXChartDescriptor {
        let axis = prepared.axis(key)
        let viewport = TimelineViewport(lower: 0, upper: axis.total)
        let units = units, locale = locale, sport = sport, mode = key.mode
        let distance = prepared.data.distance

        // The x value of a point is its true elapsed time or distance.
        let xValue = { (fraction: Double) -> Double in
            let sample = axis.sample(at: viewport.position(atFraction: min(max(fraction, 0), 1)))
            guard mode == .distance, let distance else { return sample }
            return TimelineTicks.value(distance, at: sample) - distance[0]
        }
        let xAxis = AXNumericDataAxisDescriptor(
            title: mode == .distance ? "Distance" : "Elapsed time",
            range: 0...max(xValue(1), 1),
            gridlinePositions: []
        ) { value in
            mode == .distance
                ? StatFormatter.distance(value, units: units, locale: locale).spoken
                : StatFormatter.elapsedTime(value).spoken
        }

        var series: [AXDataSeriesDescriptor] = []
        var lowest = Double.infinity, highest = -Double.infinity
        func add(_ name: String, _ reduced: ReducedSeries, describe: (Double) -> String) {
            let points = reduced.runs.joined().filter { $0.x >= 0 && $0.x <= 1 }
            guard !points.isEmpty else { return }
            for point in points {
                lowest = min(lowest, point.value)
                highest = max(highest, point.value)
            }
            series.append(AXDataSeriesDescriptor(
                name: name,
                isContinuous: true,
                dataPoints: points.map {
                    AXDataPoint(x: xValue($0.x), y: $0.value, additionalValues: [], label: describe($0.value))
                }
            ))
        }
        add("Elevation", TimelineReduction.reduce(
            prepared.elevationTable(key), axis: axis, viewport: viewport, columns: Self.columns
        )) { StatFormatter.elevation($0, units: units, locale: locale).spoken }
        if let overlay {
            add(TimelineDescription.name(of: overlay.kind), TimelineReduction.reduce(
                overlay.table(collapsesStops: key.collapsesStops), axis: axis, viewport: viewport, columns: Self.columns
            )) { TimelineDescription.stat($0, kind: overlay.kind, sport: sport, units: units, locale: locale).spoken }
        }

        let yTitle = overlay.map { "Elevation and \(TimelineDescription.name(of: $0.kind).lowercased())" } ?? "Elevation"
        let yAxis = AXNumericDataAxisDescriptor(
            title: yTitle,
            range: lowest <= highest ? lowest...max(highest, lowest + 1) : 0...1,
            gridlinePositions: []
        ) { value in
            StatFormatter.decimal(value, places: 0, locale: locale)
        }
        return AXChartDescriptor(
            title: "Timeline",
            summary: summary,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: series
        )
    }
}
