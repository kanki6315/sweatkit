import Foundation
import SweatKitAnalysis
import SweatKitFlyover
import SweatKitModel
import SweatKitTimeline
import SweatKitTrackCleanup

/// Everything the detail screen's views take for one activity, prepared once.
///
/// Every array is indexed by grid second, and so is a scrub position: the
/// route's sample indices, the timeline's arrays and `cursorStats(at:)` all
/// share it.
public struct PreparedDetail: Sendable {
    public let input: DetailInput

    /// The overlay the screen opens with: the spec's table default, or the
    /// first fallback in `RouteOverlay.defaultCandidates` that is available.
    public let defaultOverlay: RouteOverlay
    /// Every overlay's bands, or why it is unavailable.
    public let bands: [RouteOverlay: Metric<OverlayBands>]

    /// The cleaned and simplified line, or why there is no route: a virtual
    /// or indoor activity, or too few usable positions. With no route the
    /// screen shows charts only.
    public let line: Metric<SimplifiedLine>
    /// The route for each overlay, coloured by that overlay's bands, or why
    /// there is none: the line's reason first, then the overlay's.
    public let routes: [RouteOverlay: Metric<FlyoverRoute>]

    /// The timeline's base data, or nil for a stream shorter than the two
    /// seconds a timeline needs.
    public let timeline: TimelineData?
    /// One overlay series per kind the activity has values for, with the
    /// bands of the matching route overlay when it is available. Cadence is
    /// never zoned. Speed is offered off foot and pace on foot.
    public let timelineOverlays: [TimelineOverlay.Kind: TimelineOverlay]

    /// The 3-second power at each second, cycling only.
    let cursorPower: [Double?]

    init(
        input: DetailInput,
        defaultOverlay: RouteOverlay,
        bands: [RouteOverlay: Metric<OverlayBands>],
        line: Metric<SimplifiedLine>,
        routes: [RouteOverlay: Metric<FlyoverRoute>],
        timeline: TimelineData?,
        timelineOverlays: [TimelineOverlay.Kind: TimelineOverlay],
        cursorPower: [Double?]
    ) {
        self.input = input
        self.defaultOverlay = defaultOverlay
        self.bands = bands
        self.line = line
        self.routes = routes
        self.timeline = timeline
        self.timelineOverlays = timelineOverlays
        self.cursorPower = cursorPower
    }

    /// The route coloured by `overlay`.
    public func route(for overlay: RouteOverlay) -> Metric<FlyoverRoute> {
        routes[overlay] ?? .unavailable(.noUsablePositions)
    }

    /// The timeline kind that matches a route overlay, if any. The timeline
    /// has no gradient or plain series.
    public func timelineKind(for overlay: RouteOverlay) -> TimelineOverlay.Kind? {
        switch overlay {
        case .power: .power
        case .heartRate: .heartRate
        case .paceOrSpeed: input.sport.family == .onFoot ? .pace : .speed
        case .gradient, .plain: nil
        }
    }

    /// The timeline series that matches a route overlay, if the activity has
    /// one.
    public func timelineOverlay(for overlay: RouteOverlay) -> TimelineOverlay? {
        timelineKind(for: overlay).flatMap { timelineOverlays[$0] }
    }

    // MARK: Stats

    /// The values at `second`, clamped to the stream. Each is the stream's own
    /// value at that second and nil where it has none. Elapsed time is the
    /// second itself, pauses included. Power is the 3-second power and is
    /// given for cycling only, as the spec's table lists it.
    public func cursorStats(at second: Int) -> CursorStats {
        let stream = input.stream
        guard stream.count > 0 else { return CursorStats() }
        let t = min(max(second, 0), stream.count - 1)
        return CursorStats(
            distance: stream.distance[t],
            elapsedTime: TimeInterval(t),
            speed: stream.speed[t],
            power: cursorPower[t],
            heartRate: stream.heartRate[t],
            cadence: stream.cadence[t],
            elevation: stream.altitude[t],
            gradient: stream.gradient[t]
        )
    }

    /// The stats of the seconds in `range`, cut to the stream.
    ///
    /// - Time is the number of seconds selected, pauses included, so
    ///   selecting the whole activity gives its elapsed time.
    /// - Distance is the last distance in the range minus the first. Nil when
    ///   the range has no distance.
    /// - Ascent, average power and average heart rate are the analysis
    ///   package's own metrics of a stream cut to the range, so they follow
    ///   its rules exactly: ascent by peak and valley with the sport's
    ///   threshold, the averages over the seconds that have values, and power
    ///   for cycling only.
    public func rangeStats(_ range: ClosedRange<Int>) -> RangeStats {
        let stream = input.stream
        let lower = max(range.lowerBound, 0)
        let upper = min(range.upperBound, stream.count - 1)
        guard lower <= upper else { return RangeStats() }

        var distance: Double?
        if let first = (lower...upper).first(where: { stream.distance[$0] != nil }),
           let last = (lower...upper).last(where: { stream.distance[$0] != nil }),
           let start = stream.distance[first], let end = stream.distance[last] {
            distance = end - start
        }

        let metrics = ActivityAnalysis.metrics(for: ActivityInput(
            sport: input.sport,
            isIndoor: input.isIndoor,
            isVirtual: input.isVirtual,
            recording: .stream(Self.substream(of: stream, lower...upper)),
            profile: input.profile,
            activityDate: input.activityDate
        ))
        return RangeStats(
            time: TimeInterval(upper - lower + 1),
            distance: distance,
            ascent: metrics.ascent.value,
            averagePower: metrics.power.average.value,
            averageHeartRate: metrics.heartRate.average.value
        )
    }

    /// The stream cut to `range`, with only the channels range stats read.
    /// Its pause data is left as no pauses: none of those metrics reads it.
    static func substream(of stream: AnalysisStream, _ range: ClosedRange<Int>) -> AnalysisStream {
        var cut = AnalysisStream(
            rulesVersion: stream.rulesVersion,
            start: stream.start.addingTimeInterval(TimeInterval(range.lowerBound)),
            count: range.count
        )
        func slice(_ series: Series) -> Series {
            Series(values: Array(series.values[range]), quality: Array(series.quality[range]))
        }
        cut.altitude = slice(stream.altitude)
        cut.power = slice(stream.power)
        cut.heartRate = slice(stream.heartRate)
        return cut
    }
}
