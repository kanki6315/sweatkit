import SweatKitAnalysis
import SweatKitModel

/// One overlay's colour band for every second of the stream. Band indices
/// only: the caller supplies one colour per band.
public struct OverlayBands: Hashable, Sendable {
    public let overlay: RouteOverlay
    /// The number of bands, numbered from 0. Band 0 is the lowest zone, the
    /// slowest speed or the steepest descent.
    public let bandCount: Int
    /// One entry per second of the stream. Nil where the second has no value,
    /// which is never folded into a band.
    public let bands: [Int?]

    public init(overlay: RouteOverlay, bandCount: Int, bands: [Int?]) {
        self.overlay = overlay
        self.bandCount = bandCount
        self.bands = bands
    }

    /// The index the flyover and the timeline are given for a second with no
    /// value. Neither view can take a missing band, but both draw a band
    /// they have no colour for in their neutral colour, so a caller that
    /// supplies exactly `bandCount` colours gets missing seconds drawn
    /// neutral, never in the lowest zone.
    public var noValueBand: Int { bandCount }

    /// The band of `second`, with `noValueBand` where it has none.
    public func viewBand(at second: Int) -> Int {
        guard bands.indices.contains(second) else { return noValueBand }
        return bands[second] ?? noValueBand
    }

    /// Every second's band in the form the views take.
    public var viewBands: [Int] { bands.map { $0 ?? noValueBand } }
}

/// The colour rules of the spec's "Route colouring" table, applied per
/// second.
public enum ColourBanding {
    /// The bands of one overlay, or the reason the overlay is unavailable.
    ///
    /// - Power: the zone of 10-second smoothed power as a share of the
    ///   threshold power in effect on the activity date, by
    ///   `ZoneScheme.power`. Cycling only, like every power metric.
    ///   Unavailable with `.notDefinedForSport`, `.noPower`,
    ///   `.noThresholdPower` or `.zeroDenominator`, in that order.
    /// - Heart rate: the zone of each second's heart rate as a share of the
    ///   profile's threshold heart rate, by `ZoneScheme.heartRate`.
    ///   Unavailable with `.noHeartRate`, `.noThresholdHeartRate` or
    ///   `.zeroDenominator`.
    /// - Pace or speed: see `paceBands(_:family:)`. Unavailable with
    ///   `.noSpeed`.
    /// - Gradient: the band of each second's gradient by
    ///   `ZoneScheme.gradient`. Unavailable with `.noGradient`.
    /// - Plain: band 0 for every second, the one colour.
    public static func bands(for overlay: RouteOverlay, input: DetailInput) -> Metric<OverlayBands> {
        let input = input.normalised()
        let stream = input.stream
        switch overlay {
        case .power:
            guard input.sport.family == .cycling else { return .unavailable(.notDefinedForSport) }
            guard hasValue(stream.power) else { return .unavailable(.noPower) }
            guard let threshold = input.profile.thresholdPower(on: input.activityDate) else {
                return .unavailable(.noThresholdPower)
            }
            guard threshold > 0 else { return .unavailable(.zeroDenominator) }
            let smoothed = trailingMean(stream.power, seconds: DetailRules.bandSmoothingSeconds)
            return .available(zoned(.power, smoothed, threshold: threshold, scheme: .power))
        case .heartRate:
            guard hasValue(stream.heartRate) else { return .unavailable(.noHeartRate) }
            guard let threshold = input.profile.thresholdHeartRate else {
                return .unavailable(.noThresholdHeartRate)
            }
            guard threshold > 0 else { return .unavailable(.zeroDenominator) }
            return .available(zoned(.heartRate, values(of: stream.heartRate), threshold: threshold, scheme: .heartRate))
        case .paceOrSpeed:
            guard hasValue(stream.speed) else { return .unavailable(.noSpeed) }
            return .available(paceBands(stream.speed, family: input.sport.family))
        case .gradient:
            guard hasValue(stream.gradient) else { return .unavailable(.noGradient) }
            return .available(zoned(.gradient, values(of: stream.gradient), threshold: 1, scheme: .gradient))
        case .plain:
            return .available(OverlayBands(overlay: .plain, bandCount: 1, bands: Array(repeating: 0, count: stream.count)))
        }
    }

    /// Bands of speed relative to the activity's own range.
    ///
    /// The spec gives no rule, so this is the reading:
    ///
    /// 1. Speed is smoothed like power, over the trailing
    ///    `DetailRules.bandSmoothingSeconds`, so that stretches stand out
    ///    rather than single seconds of GPS noise.
    /// 2. The range is taken from the smoothed seconds at or above the
    ///    sport's moving-speed floor, so stops do not drag the slow end down
    ///    to zero. With no floor for the sport, or no second at or above it,
    ///    every smoothed second counts.
    /// 3. The range runs from the `paceRangeLowerPercentile` to the
    ///    `paceRangeUpperPercentile` of those seconds, by nearest rank.
    /// 4. The range is cut into `DetailRules.paceBandCount` equal widths of
    ///    speed. A second below the range is in band 0, one above it is in
    ///    the top band, and one exactly on a cut belongs to the faster band.
    ///    When the range has no width every second is in the middle band.
    ///
    /// Bands go by speed, so band 0 is the slowest stretch whether it is
    /// shown as pace or as speed.
    public static func paceBands(_ speed: Series, family: SportFamily) -> OverlayBands {
        let count = DetailRules.paceBandCount
        let smoothed = trailingMean(speed, seconds: DetailRules.bandSmoothingSeconds)
        let present = smoothed.compactMap { $0 }
        let floor = movingFloor(for: family)
        let moving = floor.map { floor in present.filter { $0 >= floor } } ?? present
        let sorted = (moving.isEmpty ? present : moving).sorted()
        let low = percentile(sorted, DetailRules.paceRangeLowerPercentile)
        let high = percentile(sorted, DetailRules.paceRangeUpperPercentile)
        let bands = smoothed.map { value -> Int? in
            guard let value else { return nil }
            guard high > low else { return count / 2 }
            let band = Int(((value - low) * Double(count) / (high - low)).rounded(.down))
            return min(max(band, 0), count - 1)
        }
        return OverlayBands(overlay: .paceOrSpeed, bandCount: count, bands: bands)
    }

    /// The trailing mean over `seconds` seconds ending at each second.
    ///
    /// A second with no value of its own has no mean: a gap stays a gap.
    /// Otherwise the mean is of the values present in the window, so missing
    /// seconds are left out of both the sum and the count, as in the
    /// analysis package's window means. At the start of the stream the window
    /// is cut short at second 0.
    public static func trailingMean(_ series: Series, seconds: Int) -> [Double?] {
        let width = max(seconds, 1)
        return (0..<series.count).map { second -> Double? in
            guard series[second] != nil else { return nil }
            var sum = 0.0
            var present = 0
            for index in max(0, second - width + 1)...second {
                if let value = series[index] {
                    sum += value
                    present += 1
                }
            }
            return sum / Double(present)
        }
    }

    // MARK: Helpers

    static func hasValue(_ series: Series) -> Bool {
        series.quality.contains { $0 != .missing }
    }

    static func values(of series: Series) -> [Double?] {
        (0..<series.count).map { series[$0] }
    }

    /// The analysis package's moving-speed floor for a sport family, or nil
    /// when the family has none.
    static func movingFloor(for family: SportFamily) -> Double? {
        switch family {
        case .cycling: AnalysisRules.movingSpeedFloorCycling
        case .onFoot: AnalysisRules.movingSpeedFloorOnFoot
        case .other: nil
        }
    }

    /// The nearest-rank percentile of ascending values: the smallest value
    /// with at least `share` of the values at or below it.
    static func percentile(_ sorted: [Double], _ share: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let rank = Int((share * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank - 1, 0), sorted.count - 1)]
    }

    /// Each value's zone as a share of `threshold`, formed by one division as
    /// `ZoneScheme.index(of:)` requires.
    private static func zoned(
        _ overlay: RouteOverlay,
        _ values: [Double?],
        threshold: Double,
        scheme: ZoneScheme
    ) -> OverlayBands {
        OverlayBands(
            overlay: overlay,
            bandCount: scheme.zoneCount,
            bands: values.map { $0.map { scheme.index(of: $0 / threshold) } }
        )
    }
}
