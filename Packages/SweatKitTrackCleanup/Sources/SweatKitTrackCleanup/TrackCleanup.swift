import SweatKitModel

/// The spec's track cleanup, from "Activity detail and flyover". Before
/// drawing, the app:
///
/// 1. drops points that imply an impossible speed,
/// 2. collapses jitter while stopped into a single point,
/// 3. simplifies the line to about 2 m tolerance for rendering, keeping a map
///    from each drawn vertex back to its sample.
///
/// `clean` runs steps 1 and 2, in that order, and `simplify` runs step 3 on
/// its result. Each step is also available on its own.
public enum TrackCleanup {
    /// Steps 1 and 2: the stream's positions with impossible speeds dropped,
    /// then stops collapsed, using the limits for the sport's family.
    public static func clean(_ stream: AnalysisStream, sport: Sport) -> CleanedPositions {
        let family = sport.family
        let possible = droppingImpossibleSpeeds(
            positions(in: stream),
            limit: CleanupRules.impossibleSpeed(for: family)
        )
        let collapsed = collapsingStops(
            possible,
            speed: stream.speed,
            stoppedBelow: CleanupRules.stoppedSpeed(for: family)
        )
        let reliable = if case .known = stream.pauses { true } else { false }
        return CleanedPositions(points: collapsed, sport: sport, pausePositionsAreReliable: reliable)
    }

    /// Step 3: the cleaned positions simplified to `tolerance` metres.
    public static func simplify(
        _ track: CleanedPositions,
        tolerance: Double = CleanupRules.simplificationTolerance
    ) -> SimplifiedLine {
        SimplifiedLine(vertices: simplified(track.points, tolerance: tolerance), tolerance: tolerance)
    }

    // MARK: The steps

    /// Every second of the stream that has a position, in order. A second
    /// without one is skipped, never read as 0, 0.
    ///
    /// Positions the stream filled across a short gap are interpolated, not
    /// measured, but they are positions all the same and are kept.
    public static func positions(in stream: AnalysisStream) -> [CleanedPosition] {
        (0..<stream.count).compactMap { second in
            stream.coordinate(at: second).map { CleanedPosition(coordinate: $0, sampleIndex: second) }
        }
    }

    /// Step 1: drops every point that implies a speed above `limit` metres
    /// per second. With no limit, every point is kept.
    ///
    /// Readings, where the spec is silent:
    /// - A point's implied speed is its distance from the last point kept,
    ///   divided by the seconds between them. Measuring from the last kept
    ///   point, not the previous recorded one, is what lets a spike be
    ///   dropped without also dropping the good point after it, and the
    ///   seconds between include any without a position.
    /// - A speed exactly at the limit is possible.
    /// - A run of impossible points is dropped whole: each is measured from
    ///   the same last kept point, until one is near enough to it.
    /// - The first point is always kept, having nothing before it. A bad
    ///   first fix would therefore stand, and the points after it would be
    ///   dropped until one is reachable from it.
    public static func droppingImpossibleSpeeds(_ points: [CleanedPosition], limit: Double?) -> [CleanedPosition] {
        guard let limit else { return points }
        var kept: [CleanedPosition] = []
        kept.reserveCapacity(points.count)
        for point in points {
            if let last = kept.last {
                let seconds = Double(point.sampleIndex - last.sampleIndex)
                let metres = TrackGeodesy.distance(from: last.coordinate, to: point.coordinate)
                if metres > limit * seconds { continue }
            }
            kept.append(point)
        }
        return kept
    }

    /// Step 2: collapses each stop into its first point.
    ///
    /// A point is stopped when the speed in its second is below
    /// `stoppedBelow`. A second with missing speed is not stopped, as in the
    /// moving-time rule. With no threshold, nothing is stopped.
    ///
    /// Readings, where the spec is silent:
    /// - A stop is a run of consecutive points, as they stand after step 1,
    ///   that are all stopped. Seconds without a position, or dropped in
    ///   step 1, between two stopped points do not break the run.
    /// - The single point a stop collapses into is its first: where the
    ///   recorder came to rest. It is a recorded fix, unmoved, so it keeps a
    ///   real coordinate and second; the rest of the stop's seconds are in
    ///   its `coveredSamples`.
    /// - A stop of one point is left as it is, and a stop at the very start
    ///   or end of the track collapses like any other.
    /// - Pauses play no part: a paused second is stopped only if its speed
    ///   says so.
    public static func collapsingStops(
        _ points: [CleanedPosition],
        speed: Series,
        stoppedBelow floor: Double?
    ) -> [CleanedPosition] {
        guard let floor else { return points }
        func isStopped(_ point: CleanedPosition) -> Bool {
            guard point.sampleIndex < speed.count, let value = speed[point.sampleIndex] else { return false }
            return value < floor
        }
        var result: [CleanedPosition] = []
        result.reserveCapacity(points.count)
        var stopStart: CleanedPosition?
        var stopEnd = 0
        func closeStop() {
            if let start = stopStart {
                result.append(CleanedPosition(
                    coordinate: start.coordinate,
                    sampleIndex: start.sampleIndex,
                    coveredSamples: start.sampleIndex...stopEnd
                ))
                stopStart = nil
            }
        }
        for point in points {
            if isStopped(point) {
                if stopStart == nil { stopStart = point }
                stopEnd = point.coveredSamples.upperBound
            } else {
                closeStop()
                result.append(point)
            }
        }
        closeStop()
        return result
    }

    /// Step 3: the points simplified by Douglas-Peucker to `tolerance` metres.
    ///
    /// The first and last points are always kept. Between two kept points,
    /// the point farthest from the segment joining them is kept when it is
    /// more than `tolerance` away, and the search repeats on each side.
    /// Distance is to the great-circle segment, so a point beyond either end
    /// is measured to that end. Kept points are not moved, so each vertex
    /// keeps its second.
    ///
    /// Reading: a point exactly at the tolerance is within it and is dropped.
    public static func simplified(_ points: [CleanedPosition], tolerance: Double) -> [CleanedPosition] {
        guard points.count > 2 else { return points }
        var keep = Array(repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        // An explicit stack, so a long track cannot overflow the call stack.
        var spans = [(first: 0, last: points.count - 1)]
        while let span = spans.popLast() {
            guard span.last - span.first > 1 else { continue }
            let start = points[span.first].coordinate
            let end = points[span.last].coordinate
            var farthest = span.first
            var farthestDistance = -1.0
            for index in (span.first + 1)..<span.last {
                let distance = TrackGeodesy.distance(from: points[index].coordinate, toSegmentFrom: start, to: end)
                if distance > farthestDistance {
                    farthest = index
                    farthestDistance = distance
                }
            }
            if farthestDistance > tolerance {
                keep[farthest] = true
                spans.append((span.first, farthest))
                spans.append((farthest, span.last))
            }
        }
        return points.indices.filter { keep[$0] }.map { points[$0] }
    }
}
