import Foundation
import SweatKitModel

/// Two efforts at one point of the route-distance grid.
public struct ComparisonGridPoint: Hashable, Codable, Sendable {
    /// The route distance of this grid point, in metres.
    public var routeDistance: Double
    /// The subject's time since it entered the timed section, on the
    /// comparison's clock.
    public var subjectClock: TimeInterval
    /// The baseline's time since it entered the timed section, on the
    /// comparison's clock.
    public var baselineClock: TimeInterval
    /// The time gap: `subjectClock` minus `baselineClock`. Positive when the
    /// subject is behind the baseline, negative when it is ahead.
    public var gap: TimeInterval
    /// The subject's elapsed time since its activity started, whatever the
    /// comparison's clock. The paired charts read each channel of the
    /// subject's analysis stream at this second.
    public var subjectElapsedTime: TimeInterval
    /// The same for the baseline.
    public var baselineElapsedTime: TimeInterval

    public init(
        routeDistance: Double,
        subjectClock: TimeInterval,
        baselineClock: TimeInterval,
        gap: TimeInterval,
        subjectElapsedTime: TimeInterval,
        baselineElapsedTime: TimeInterval
    ) {
        self.routeDistance = routeDistance
        self.subjectClock = subjectClock
        self.baselineClock = baselineClock
        self.gap = gap
        self.subjectElapsedTime = subjectElapsedTime
        self.baselineElapsedTime = baselineElapsedTime
    }
}

/// Where the two markers are at one moment of the shared clock.
public struct GhostFrame: Hashable, Codable, Sendable {
    /// The route distance of the subject's marker.
    public var subjectRouteDistance: Double
    /// The route distance of the baseline's marker, the ghost.
    public var baselineRouteDistance: Double
    /// The real gap at this moment, in metres along the route:
    /// `baselineRouteDistance` minus `subjectRouteDistance`. Positive when the
    /// ghost is ahead of the subject.
    public var separation: Double

    public init(subjectRouteDistance: Double, baselineRouteDistance: Double, separation: Double) {
        self.subjectRouteDistance = subjectRouteDistance
        self.baselineRouteDistance = baselineRouteDistance
        self.separation = separation
    }
}

/// Two efforts on the same route, compared over the timed section.
///
/// The subject is the effort being looked at. The baseline is what it is
/// compared against: the best, the previous one, or one picked from the list.
public struct EffortComparison: Hashable, Sendable {
    /// The clock the comparison runs on. The charts, the gap and the ghost
    /// all use it, and so do both efforts.
    public let clock: ComparisonClock
    /// False when either effort lacks reliable pause positions. Elapsed time
    /// is then used for both, and the moving-time option is disabled.
    public let movingTimeIsAvailable: Bool
    /// The timed section both efforts are measured over.
    public let section: TimedSection
    /// The subject's crossing times, on `clock`.
    public let subjectTimes: SectionTimes
    /// The baseline's crossing times, on `clock`.
    public let baselineTimes: SectionTimes
    /// Both efforts on the route-distance grid, from the start mark to the
    /// end mark.
    public let grid: [ComparisonGridPoint]
    /// The subject's alignment, as passed in.
    public let subject: Alignment
    /// The baseline's alignment, as passed in.
    public let baseline: Alignment

    /// Where both markers are when the shared clock reads `clockTime` seconds.
    ///
    /// Both markers run on one clock, the time since each effort entered the
    /// timed section. An effort's marker is at the start mark at 0, moves in a
    /// straight line of route distance against clock time between its mapped
    /// points, and reaches the end mark when the clock reads the effort's own
    /// duration. Before 0 it waits at the start mark, and after its duration
    /// it stays at the end mark. Where several points share one clock time,
    /// the marker is at the furthest of them.
    public func ghost(at clockTime: TimeInterval) -> GhostFrame {
        fatalError("unimplemented")
    }
}

/// Effort against effort.
public enum RouteComparison {
    /// The clock a comparison runs on.
    ///
    /// The requested clock, except that when either effort lacks reliable
    /// pause positions elapsed time is used for both.
    public static func clock(
        requested: ComparisonClock,
        subjectPausePositionsAreReliable: Bool,
        baselinePausePositionsAreReliable: Bool
    ) -> ComparisonClock {
        fatalError("unimplemented")
    }

    /// Compares two efforts that are aligned with the same reference line.
    ///
    /// The clock is settled by `clock(requested:...)`, and moving time is the
    /// default request.
    ///
    /// The grid starts at the timed section's start mark and steps
    /// `rules.comparisonGridSpacing` metres at a time while it stays at or
    /// before the end mark. The spec says only "a 10 m grid of route
    /// distance". This reading anchors the grid on the start mark, where both
    /// clocks read 0, and adds the end mark as a final point when the last
    /// step falls short of it, so the last gap is always the difference
    /// between the two route times.
    ///
    /// At each grid point each effort's time is
    /// `Alignment.time(atRouteDistance:clock:)`, less its time at the start
    /// mark.
    ///
    /// Unavailable when the reference line is too short for a timed section
    /// (`referenceLineTooShort`) or either effort does not cross both marks
    /// (`timedSectionNotCovered`). Both alignments must have the same
    /// reference length; the subject's is the one used.
    public static func compare(
        _ subject: Alignment,
        against baseline: Alignment,
        clock requested: ComparisonClock = .moving,
        rules: MatchingRules = .standard
    ) -> Metric<EffortComparison> {
        fatalError("unimplemented")
    }
}
