import Foundation
import SweatKitModel

/// One point of an effort after it has been mapped onto a reference line.
public struct MappedPoint: Hashable, Codable, Sendable {
    /// The route distance of the position this point was matched to, in
    /// metres from the start of the reference line. It never decreases from
    /// one point to the next.
    public var routeDistance: Double
    /// The straight-line distance from the point to its matched position, in
    /// metres. Never negative.
    public var distanceFromLine: Double
    /// The sideways distance from the reference line, with its sign: positive
    /// when the point is to the right of the line's direction of travel and
    /// negative when it is to the left.
    ///
    /// It is the part of the offset from the matched position to the point
    /// that is perpendicular to the line there. For a point matched inside a
    /// straight piece of the line its size equals `distanceFromLine`. For a
    /// point matched to an end of the line, or held back by the forward-only
    /// rule, it can be smaller. Where the matched position is a corner of the
    /// line, the direction is that of the piece that begins at the corner, or
    /// of the last piece at the line's end.
    public var sideOffset: Double
    /// How far the track itself had travelled when it reached this point, in
    /// metres from the track's first point. It never decreases from one
    /// point to the next.
    public var trackDistance: Double
    /// The point's elapsed time, carried over from the track.
    public var elapsedTime: TimeInterval
    /// The point's moving time, carried over from the track.
    public var movingTime: TimeInterval

    public init(
        routeDistance: Double,
        distanceFromLine: Double,
        sideOffset: Double,
        trackDistance: Double,
        elapsedTime: TimeInterval,
        movingTime: TimeInterval
    ) {
        self.routeDistance = routeDistance
        self.distanceFromLine = distanceFromLine
        self.sideOffset = sideOffset
        self.trackDistance = trackDistance
        self.elapsedTime = elapsedTime
        self.movingTime = movingTime
    }
}

/// An effort mapped onto a route's reference line. This is what an effort
/// stores, and what timing and comparison read.
public struct Alignment: Hashable, Codable, Sendable {
    /// One mapped point for each point of the track, in the track's order.
    public var points: [MappedPoint]
    /// The length of the reference line the track was mapped onto, in metres.
    public var referenceLength: Double
    /// The distance the track itself travelled, in metres.
    public var trackLength: Double
    /// Carried over from the track.
    public var pausePositionsAreReliable: Bool

    public init(
        points: [MappedPoint],
        referenceLength: Double,
        trackLength: Double,
        pausePositionsAreReliable: Bool = true
    ) {
        self.points = points
        self.referenceLength = referenceLength
        self.trackLength = trackLength
        self.pausePositionsAreReliable = pausePositionsAreReliable
    }

    /// The five measures of this alignment.
    public func measures(rules: MatchingRules = .standard) -> AlignmentMeasures {
        AlignmentMeasures(points: points, referenceLength: referenceLength, trackLength: trackLength, rules: rules)
    }
}

/// The five measures the spec takes from a mapping.
public enum AlignmentMeasure: String, Codable, Sendable, CaseIterable {
    case proximity
    case ends
    case coverage
    case lengthRatio
    case sideOffset
}

/// The values of the five measures for one alignment.
///
/// The spec names the measures and their thresholds but not how each is
/// worked out from the mapping. The definitions here are this package's
/// reading. They all rest on one idea: a mapped point is **on the line** when
/// its `distanceFromLine` is at most `rules.proximityDistance`. The spec's
/// "mapped point" and "mapped stretch" are read as a point on the line and a
/// stretch between two of them.
public struct AlignmentMeasures: Hashable, Codable, Sendable {
    /// Proximity: the share of the effort's points that are on the line. An
    /// effort with no points has proximity 0.
    public var proximity: Double
    /// Ends, at the start: the route distance of the first point on the line.
    /// The spec's "within 25 m of the start" is read along the route, because
    /// the timed section depends on it. The reference length when no point is
    /// on the line.
    public var startGap: Double
    /// Ends, at the finish: the reference length minus the route distance of
    /// the last point on the line. The reference length when no point is on
    /// the line.
    public var endGap: Double
    /// Coverage: the share of the timed section's length that was mapped.
    ///
    /// The stretch of line between the route distances of two consecutive
    /// points is mapped when both points are on the line. Everything else is
    /// unmapped: the stretch before the first point on the line, the stretch
    /// after the last, and the stretch between two points on the line that
    /// have points off the line between them.
    ///
    /// Only the part of each stretch inside the timed section counts. The
    /// ends rule already lets a full effort begin `rules.endTolerance` late
    /// and stop as early, so those two ends of the line are judged by that
    /// rule alone and do not count against coverage as well.
    ///
    /// On a reference line too short to hold a timed section, coverage is
    /// measured over the whole line.
    public var coverage: Double
    /// The longest unmapped stretch inside the timed section, in metres. 0
    /// when the whole section is mapped. Measured over the whole line when
    /// the line is too short to hold a timed section.
    ///
    /// Two unmapped stretches that meet at a single point on the line are
    /// measured separately, because the effort did touch the line between
    /// them.
    public var longestUnmappedStretch: Double
    /// Length ratio: the distance the track travelled between the two marks
    /// of the timed section, divided by the section's length.
    ///
    /// The track's distance at each mark is read where the effort first
    /// reached that route distance, in a straight line between the points
    /// either side, as crossing times are. Riding before the first mark or
    /// on past the second therefore does not count.
    ///
    /// An effort that does not reach a mark is measured over as much of the
    /// section as its points span, so that a late start or an early finish
    /// fails the ends rule alone. 0 when its points span none of the section.
    ///
    /// On a reference line too short to hold a timed section, it is the
    /// whole track's length divided by the whole line's.
    public var lengthRatio: Double
    /// Side offset: the average signed `sideOffset` over the 200 m stretch
    /// where that average is furthest from zero. Positive is to the right.
    ///
    /// A stretch starts at the route distance of a point and runs
    /// `rules.sideOffsetStretch` metres forward. It counts only when it fits
    /// inside the reference line. Its average is the plain mean of the side
    /// offsets of every point, on the line or not, whose route distance lies
    /// in the stretch, both ends included. When the reference line is shorter
    /// than one stretch, a single stretch covers the whole line. 0 when no
    /// stretch counts or the effort has no points.
    public var worstSideOffset: Double

    public init(
        proximity: Double,
        startGap: Double,
        endGap: Double,
        coverage: Double,
        longestUnmappedStretch: Double,
        lengthRatio: Double,
        worstSideOffset: Double
    ) {
        self.proximity = proximity
        self.startGap = startGap
        self.endGap = endGap
        self.coverage = coverage
        self.longestUnmappedStretch = longestUnmappedStretch
        self.lengthRatio = lengthRatio
        self.worstSideOffset = worstSideOffset
    }

    /// The measures of a mapping, by the definitions on each property.
    public init(
        points: [MappedPoint],
        referenceLength: Double,
        trackLength: Double,
        rules: MatchingRules = .standard
    ) {
        // Coverage and the length ratio are measured over the timed section,
        // or over the whole line when it is too short to hold one.
        let section = TimedSection(referenceLength: referenceLength, rules: rules)
        let measured = section.map { $0.start...$0.end } ?? 0...max(referenceLength, 0)
        let measuredLength = measured.upperBound - measured.lowerBound
        /// The length of the part of a stretch of line that lies in `measured`.
        func measuredPart(from start: Double, to end: Double) -> Double {
            max(0, min(end, measured.upperBound) - max(start, measured.lowerBound))
        }

        // Proximity, ends and coverage, in one pass over the points in order.
        var onLineCount = 0
        var mappedLength = 0.0
        var longestUnmapped = 0.0
        var firstOnLine: Double?
        var lastOnLine: Double?
        var previousWasOnLine = false
        for point in points {
            guard point.distanceFromLine <= rules.proximityDistance else {
                previousWasOnLine = false
                continue
            }
            onLineCount += 1
            if let last = lastOnLine {
                let stretch = measuredPart(from: last, to: point.routeDistance)
                if previousWasOnLine {
                    mappedLength += stretch
                } else {
                    longestUnmapped = max(longestUnmapped, stretch)
                }
            } else {
                // The stretch before the first point on the line.
                firstOnLine = point.routeDistance
                longestUnmapped = max(longestUnmapped, measuredPart(from: 0, to: point.routeDistance))
            }
            lastOnLine = point.routeDistance
            previousWasOnLine = true
        }

        proximity = points.isEmpty ? 0 : Double(onLineCount) / Double(points.count)
        if let firstOnLine, let lastOnLine {
            startGap = firstOnLine
            endGap = max(0, referenceLength - lastOnLine)
            // The stretch after the last point on the line.
            longestUnmappedStretch = max(longestUnmapped, measuredPart(from: lastOnLine, to: referenceLength))
            coverage = measuredLength > 0 ? mappedLength / measuredLength : 0
        } else {
            startGap = referenceLength
            endGap = referenceLength
            longestUnmappedStretch = measuredLength
            coverage = 0
        }

        if let section, let first = points.first, let last = points.last {
            // As much of the section as the effort's points span.
            let from = max(section.start, first.routeDistance)
            let to = min(section.end, last.routeDistance)
            if to > from,
               let atStart = Self.trackDistance(of: points, atRouteDistance: from),
               let atEnd = Self.trackDistance(of: points, atRouteDistance: to) {
                lengthRatio = (atEnd - atStart) / (to - from)
            } else {
                lengthRatio = 0
            }
        } else if section != nil {
            lengthRatio = 0
        } else {
            lengthRatio = referenceLength > 0 ? trackLength / referenceLength : 0
        }
        worstSideOffset = Self.worstSideOffset(of: points, referenceLength: referenceLength, rules: rules)
    }

    /// How far the track had travelled when the effort first reached a route
    /// distance, read in a straight line between the points either side.
    /// Nil when the first point is already beyond it or no point reaches it.
    private static func trackDistance(of points: [MappedPoint], atRouteDistance distance: Double) -> Double? {
        let arrival = firstIndex(in: points.count) { points[$0].routeDistance >= distance }
        guard arrival < points.count else { return nil }
        let after = points[arrival]
        if after.routeDistance == distance { return after.trackDistance }
        guard arrival > 0 else { return nil }
        let before = points[arrival - 1]
        let fraction = (distance - before.routeDistance) / (after.routeDistance - before.routeDistance)
        return before.trackDistance + fraction * (after.trackDistance - before.trackDistance)
    }

    /// The side offset measure, by the definition on `worstSideOffset`. Of two
    /// stretches whose averages are equally far from zero, the one that
    /// starts first is reported.
    private static func worstSideOffset(
        of points: [MappedPoint],
        referenceLength: Double,
        rules: MatchingRules
    ) -> Double {
        guard !points.isEmpty else { return 0 }
        // A mapping is already in order of route distance. One written by
        // hand might not be, and the average does not depend on the order.
        let isOrdered = zip(points, points.dropFirst()).allSatisfy { $0.routeDistance <= $1.routeDistance }
        let ordered = isOrdered ? points : points.sorted { $0.routeDistance < $1.routeDistance }

        // sums[i] is the total side offset of the first i points.
        var sums = [0.0]
        sums.reserveCapacity(ordered.count + 1)
        for point in ordered {
            sums.append((sums.last ?? 0) + point.sideOffset)
        }

        // A line shorter than one stretch is averaged whole.
        guard referenceLength >= rules.sideOffsetStretch else {
            return (sums.last ?? 0) / Double(ordered.count)
        }

        var worst = 0.0
        var first = 0
        // One past the last point inside the stretch.
        var end = 0
        while first < ordered.count {
            let start = ordered[first].routeDistance
            let finish = start + rules.sideOffsetStretch
            // Later points start later still, so none of their stretches fit.
            guard finish <= referenceLength else { break }
            if end < first { end = first }
            while end < ordered.count, ordered[end].routeDistance <= finish {
                end += 1
            }
            if end > first {
                let mean = (sums[end] - sums[first]) / Double(end - first)
                if abs(mean) > abs(worst) { worst = mean }
            }
            // Every point at this route distance starts the same stretch.
            var next = first + 1
            while next < ordered.count, ordered[next].routeDistance == start {
                next += 1
            }
            first = next
        }
        return worst
    }

    /// The measures that fall short of what joining automatically needs.
    ///
    /// - Proximity passes when `proximity >= rules.joinProximity`.
    /// - Ends pass when `startGap <= rules.endTolerance` and
    ///   `endGap <= rules.endTolerance`.
    /// - Coverage passes when `coverage >= rules.minimumCoverage` and
    ///   `longestUnmappedStretch <= rules.longestUnmappedStretch`.
    /// - Length ratio passes when `lengthRatio >= 1 - rules.lengthRatioTolerance`
    ///   and `lengthRatio <= 1 + rules.lengthRatioTolerance`.
    /// - Side offset passes when the size of `worstSideOffset` is at most
    ///   `rules.maximumSideOffset`.
    ///
    /// The comparisons are written exactly this way so that a value sitting
    /// on a threshold passes.
    public func failedMeasures(rules: MatchingRules = .standard) -> Set<AlignmentMeasure> {
        var failed: Set<AlignmentMeasure> = []
        if !(proximity >= rules.joinProximity) {
            failed.insert(.proximity)
        }
        if !(startGap <= rules.endTolerance && endGap <= rules.endTolerance) {
            failed.insert(.ends)
        }
        if !(coverage >= rules.minimumCoverage && longestUnmappedStretch <= rules.longestUnmappedStretch) {
            failed.insert(.coverage)
        }
        if !(lengthRatio >= 1 - rules.lengthRatioTolerance && lengthRatio <= 1 + rules.lengthRatioTolerance) {
            failed.insert(.lengthRatio)
        }
        if !(abs(worstSideOffset) <= rules.maximumSideOffset) {
            failed.insert(.sideOffset)
        }
        return failed
    }

    /// Whether all five measures pass. This is what the spec means by an
    /// activity aligning with a route.
    public func allPass(rules: MatchingRules = .standard) -> Bool {
        failedMeasures(rules: rules).isEmpty
    }

    /// The outcome for these measures.
    ///
    /// The spec's table does not say which row wins when two apply. This
    /// reading makes the three outcomes cover every case exactly once:
    ///
    /// 1. Reject when proximity is under `rules.reviewProximity`, or the ends
    ///    or coverage fail. Rejection comes first: a late start, an early
    ///    finish or a long detour is never offered for review.
    /// 2. Otherwise join when all five measures pass and the activity aligns
    ///    with no other route.
    /// 3. Otherwise manual review. What is left is exactly the spec's review
    ///    row: proximity from 70% up to but not including 90%, a stretch
    ///    consistently to one side, a failed length ratio, or a second route.
    ///
    /// - Parameter alignsWithAnotherRoute: True when all five measures also
    ///   pass against a different route.
    public func outcome(
        alignsWithAnotherRoute: Bool = false,
        rules: MatchingRules = .standard
    ) -> AlignmentOutcome {
        let failed = failedMeasures(rules: rules)
        if !(proximity >= rules.reviewProximity) || failed.contains(.ends) || failed.contains(.coverage) {
            return .reject
        }
        if failed.isEmpty && !alignsWithAnotherRoute {
            return .join
        }
        return .manualReview
    }
}

/// What alignment decides about an activity and a route.
public enum AlignmentOutcome: String, Codable, Sendable, CaseIterable {
    /// The activity joins the route.
    case join
    /// The app asks the user. It does not guess.
    case manualReview
    /// The activity does not belong to the route. It stays an ordinary
    /// activity, and may wait as a possible new route.
    case reject
}

/// Step 2 of matching.
public enum RouteAlignment {
    /// Maps each point of a track to a position along a reference line, in
    /// order.
    ///
    /// The spec's "each point of the candidate" is read as each point of the
    /// cleaned track itself, not the 25 m resampling that detection uses, so
    /// that every sample keeps its time for the timed section and the
    /// comparison grid.
    ///
    /// The first point searches route distances from 0 to
    /// `rules.searchWindow`. Every later point searches from the previous
    /// point's route distance to that distance plus `rules.searchWindow`. The
    /// search never runs past the end of the line. Within its range a point is
    /// matched to the position on the line closest to it, and of several
    /// equally close positions the one with the smallest route distance. Route
    /// distance therefore only moves forward, and a spot the line visits twice
    /// maps to a different route distance on each pass.
    ///
    /// Two positions are equally close when their distances differ by less
    /// than a thousandth of a millimetre, so that rounding does not decide
    /// between the two passes of a road ridden out and back.
    ///
    /// The result has one mapped point for each point of the track.
    public static func map(
        _ track: CleanedTrack,
        onto line: ReferenceLine,
        rules: MatchingRules = .standard
    ) -> [MappedPoint] {
        let course = Polyline(line.points)
        var mapped: [MappedPoint] = []
        mapped.reserveCapacity(track.points.count)
        // Where the previous point was matched: its route distance and the
        // piece of the line it was found on. The first point starts from the
        // start of the line.
        var previousDistance = 0.0
        var previousPiece = 0
        var previousCoordinate: Coordinate?
        var travelled = 0.0
        for point in track.points {
            if let previousCoordinate {
                travelled += Geodesy.distance(from: previousCoordinate, to: point.coordinate)
            }
            previousCoordinate = point.coordinate
            let furthest = min(previousDistance + max(0, rules.searchWindow), course.length)
            let match = closestPosition(
                to: point.coordinate,
                on: course,
                from: previousDistance,
                to: furthest,
                startingAtPiece: previousPiece
            )
            mapped.append(MappedPoint(
                routeDistance: match.routeDistance,
                distanceFromLine: match.distance,
                sideOffset: match.sideOffset,
                trackDistance: travelled,
                elapsedTime: point.elapsedTime,
                movingTime: point.movingTime
            ))
            previousDistance = match.routeDistance
            previousPiece = match.piece
        }
        return mapped
    }

    /// A position on the line that a point was matched to.
    private struct Match {
        var routeDistance: Double
        var distance: Double
        var sideOffset: Double
        /// The piece of the line the position was found on: the one from
        /// `points[piece]` to `points[piece + 1]`.
        var piece: Int
    }

    /// The position closest to `coordinate` among those whose route distance
    /// lies from `nearest` to `furthest`, looking at the pieces of the line in
    /// order from `firstPiece`, which is the piece that holds `nearest`.
    private static func closestPosition(
        to coordinate: Coordinate,
        on course: Polyline,
        from nearest: Double,
        to furthest: Double,
        startingAtPiece firstPiece: Int
    ) -> Match {
        let frame = LocalFrame(origin: coordinate)
        let pieceCount = max(0, course.points.count - 1)
        var best: Match?
        var bestOffset = LocalFrame.Vector(east: 0, north: 0)

        var piece = firstPiece
        while piece < pieceCount {
            let pieceStart = course.cumulative[piece]
            // Past the window. The first piece is always looked at: it holds
            // the previous match.
            if piece > firstPiece, pieceStart > furthest { break }
            let pieceLength = course.cumulative[piece + 1] - pieceStart
            guard pieceLength > 0 else {
                piece += 1
                continue
            }
            // The part of this piece that lies inside the window, as
            // fractions of the piece.
            let lowest = min(1, max(0, (nearest - pieceStart) / pieceLength))
            let highest = max(lowest, min(1, (furthest - pieceStart) / pieceLength))

            // Where the point falls along the piece, in a flat frame centred
            // on the point itself.
            let from = frame.vector(to: course.points[piece])
            let along = frame.vector(to: course.points[piece + 1]) - from
            let alongSquared = along.dot(along)
            let projected = alongSquared > 0 ? -from.dot(along) / alongSquared : 0
            let fraction = min(highest, max(lowest, projected))

            let position = Geodesy.interpolate(from: course.points[piece], to: course.points[piece + 1], fraction: fraction)
            let distance = Geodesy.distance(from: coordinate, to: position)
            // Of equally close positions the first found has the smallest
            // route distance, so a later one must be clearly closer to win.
            if best.map({ distance < $0.distance - Geodesy.samePositionTolerance }) ?? true {
                // Never before the previous match, and never past the window.
                let routeDistance = min(max(pieceStart + fraction * pieceLength, nearest), max(nearest, furthest))
                best = Match(routeDistance: routeDistance, distance: distance, sideOffset: 0, piece: piece)
                bestOffset = LocalFrame.Vector(
                    east: -(from.east + fraction * along.east),
                    north: -(from.north + fraction * along.north)
                )
            }
            piece += 1
        }

        guard var match = best else {
            // No piece with any length lies ahead, which a reference line
            // cannot produce. The point is held where the previous one was.
            let held = course.coordinate(at: nearest) ?? coordinate
            return Match(
                routeDistance: nearest,
                distance: Geodesy.distance(from: coordinate, to: held),
                sideOffset: 0,
                piece: min(firstPiece, max(0, pieceCount - 1))
            )
        }

        // The direction of the line at the matched position. At a corner it
        // is that of the piece that begins there; at the end of the line it
        // is that of the last piece.
        var directionPiece = match.piece
        if course.cumulative[match.piece + 1] - match.routeDistance <= Geodesy.samePositionTolerance {
            var next = match.piece + 1
            while next < pieceCount, !(course.cumulative[next + 1] - course.cumulative[next] > 0) {
                next += 1
            }
            if next < pieceCount { directionPiece = next }
        }
        let direction = frame.vector(to: course.points[directionPiece + 1]) - frame.vector(to: course.points[directionPiece])
        let directionLength = direction.length
        if directionLength > 0 {
            // The part of the offset that points to the right of travel.
            match.sideOffset = (bestOffset.east * direction.north - bestOffset.north * direction.east) / directionLength
        }
        return match
    }

    /// The alignment of a track with a reference line: the mapping from
    /// `map`, with the line's length, the track's length and the track's
    /// pause reliability.
    public static func align(
        _ track: CleanedTrack,
        to line: ReferenceLine,
        rules: MatchingRules = .standard
    ) -> Alignment {
        Alignment(
            points: map(track, onto: line, rules: rules),
            referenceLength: line.length,
            trackLength: track.length,
            pausePositionsAreReliable: track.pausePositionsAreReliable
        )
    }

    /// The outcome of one activity against each of several routes, given its
    /// measures against each. The result is in the same order.
    ///
    /// An activity aligns with a route when all five measures pass. When it
    /// aligns with two or more routes, each of those is sent to manual review
    /// instead of joining. A route it does not align with gets the outcome its
    /// own measures give, whatever happens on the others.
    public static func outcomes(
        for measures: [AlignmentMeasures],
        rules: MatchingRules = .standard
    ) -> [AlignmentOutcome] {
        let aligned = measures.map { $0.allPass(rules: rules) }
        let alignedCount = aligned.count { $0 }
        return measures.indices.map { index in
            // Another route counts only when it is not this one.
            let others = alignedCount - (aligned[index] ? 1 : 0)
            return measures[index].outcome(alignsWithAnotherRoute: others > 0, rules: rules)
        }
    }
}
