import Foundation
import SweatKitModel

/// A label under the timeline.
struct TimelineTick: Hashable, Sendable {
    /// How far across the viewport the label sits, from 0 to 1.
    var fraction: Double
    var label: String
}

enum TimelineTicks {
    /// The steps a time axis can be labelled in, in seconds.
    static let timeSteps: [Double] = [
        1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600, 7200, 10_800, 21_600, 43_200, 86_400,
    ]

    /// The smallest step, from 1, 2 or 5 times a power of ten between 0.01
    /// and 1000 (or from `timeSteps`), that labels `span` with at most
    /// `maximumCount` labels. Counting both ends, a span holds
    /// `span / step + 1` labels at most.
    static func step(span: Double, maximumCount: Int, mode: TimelineAxisMode) -> Double {
        let fits = { (step: Double) in (span / step).rounded(.down) + 1 <= Double(max(2, maximumCount)) }
        switch mode {
        case .time:
            return timeSteps.first(where: fits) ?? timeSteps[timeSteps.count - 1]
        case .distance:
            for exponent in -2...3 {
                for multiple in [1.0, 2.0, 5.0] {
                    let step = multiple * pow(10, Double(exponent))
                    if fits(step) { return step }
                }
            }
            return 5000
        }
    }

    /// The labels for what the viewport shows.
    ///
    /// A label states the true elapsed time or distance of the sample at its
    /// place, at round values. With stops collapsed, the values that fall
    /// inside a stop all land on its seam, so a label is dropped when it
    /// would sit closer to the one before it than evenly spread labels do.
    ///
    /// - Parameter distance: Cumulative metres per sample, needed for the
    ///   distance axis.
    static func ticks(
        axis: TimelineAxis,
        viewport: TimelineViewport,
        mode: TimelineAxisMode,
        distance: [Double]?,
        units: UnitSystem,
        maximumCount: Int,
        locale: Locale = .current
    ) -> [TimelineTick] {
        guard viewport.span > 0 else { return [] }
        let firstSample = axis.sample(at: viewport.lower)
        let lastSample = axis.sample(at: viewport.upper)

        // The true value at each end, in the unit the labels use.
        let unit: Double
        let low: Double, high: Double
        switch mode {
        case .time:
            unit = 1
            low = firstSample
            high = lastSample
        case .distance:
            guard let distance else { return [] }
            unit = units == .metric ? StatFormatter.metresPerKilometre : StatFormatter.metresPerMile
            low = (value(distance, at: firstSample) - distance[0]) / unit
            high = (value(distance, at: lastSample) - distance[0]) / unit
        }
        guard high > low else { return [] }

        let step = step(span: high - low, maximumCount: maximumCount, mode: mode)
        let spacing = 1 / Double(max(2, maximumCount)) * 0.999
        var ticks: [TimelineTick] = []
        var multiple = (low / step).rounded(.up)
        while multiple * step <= high {
            let value = multiple * step
            multiple += 1
            let sample: Double
            let label: String
            switch mode {
            case .time:
                sample = value
                label = StatFormatter.clock(Int(value.rounded()))
            case .distance:
                guard let distance else { return [] }
                sample = self.sample(distance, at: distance[0] + value * unit)
                let places = step >= 1 ? 0 : step >= 0.1 ? 1 : 2
                label = StatFormatter.decimal(value, places: places, locale: locale)
                    + (units == .metric ? " km" : " mi")
            }
            let fraction = viewport.fraction(of: axis.position(ofSample: sample))
            guard fraction >= -1e-9, fraction <= 1 + 1e-9 else { continue }
            if let last = ticks.last, fraction - last.fraction < spacing { continue }
            ticks.append(TimelineTick(fraction: min(max(fraction, 0), 1), label: label))
        }
        return ticks
    }

    /// A series' value at a fractional sample, between its neighbours.
    static func value(_ series: [Double], at sample: Double) -> Double {
        let clamped = min(max(sample, 0), Double(series.count - 1))
        let index = Int(clamped.rounded(.down))
        guard index < series.count - 1 else { return series[series.count - 1] }
        return series[index] + (clamped - Double(index)) * (series[index + 1] - series[index])
    }

    /// The first fractional sample at which a never-decreasing series reaches
    /// `target`.
    static func sample(_ series: [Double], at target: Double) -> Double {
        var low = 0, high = series.count
        while low < high {
            let middle = (low + high) / 2
            if series[middle] < target { low = middle + 1 } else { high = middle }
        }
        guard low > 0 else { return 0 }
        guard low < series.count else { return Double(series.count - 1) }
        let before = series[low - 1], after = series[low]
        return Double(low - 1) + (target - before) / (after - before)
    }
}
