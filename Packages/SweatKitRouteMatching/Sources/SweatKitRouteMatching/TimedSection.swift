import Foundation
import SweatKitModel

/// The clock a time is read on.
public enum ComparisonClock: String, Codable, Sendable, CaseIterable {
    /// Moving time. The default, when both efforts have reliable pause
    /// positions.
    case moving
    /// Elapsed time.
    case elapsed
}

/// The part of a reference line that times are measured over.
///
/// A full effort may begin up to 25 m after the start of the line and stop up
/// to 25 m before its end, so the timed section runs between those two marks
/// and every full effort covers it.
public struct TimedSection: Hashable, Codable, Sendable {
    /// The route distance of the start mark: `rules.endTolerance` after the
    /// start of the line.
    public var start: Double
    /// The route distance of the end mark: `rules.endTolerance` before the
    /// end of the line.
    public var end: Double

    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }

    /// The timed section of a reference line of this length.
    ///
    /// The spec does not cover a line too short to hold a section. Nil when
    /// the end mark would not lie after the start mark, which is a line no
    /// longer than twice `rules.endTolerance`.
    public init?(referenceLength: Double, rules: MatchingRules = .standard) {
        fatalError("unimplemented")
    }

    /// The length of the section in metres.
    public var length: Double {
        fatalError("unimplemented")
    }
}

/// When an effort crossed the two marks of the timed section, on one clock.
public struct SectionTimes: Hashable, Codable, Sendable {
    /// The clock that both times are read on.
    public var clock: ComparisonClock
    /// The time at which the effort crossed the start mark, in seconds since
    /// the activity started. The effort's clock starts here.
    public var start: TimeInterval
    /// The time at which the effort crossed the end mark, in seconds since
    /// the activity started. The effort's clock stops here.
    public var end: TimeInterval

    public init(clock: ComparisonClock, start: TimeInterval, end: TimeInterval) {
        self.clock = clock
        self.start = start
        self.end = end
    }

    /// The effort's time over the timed section: `end` minus `start`. This is
    /// the route time that rankings and statistics use.
    public var duration: TimeInterval {
        fatalError("unimplemented")
    }
}

/// Why a route time or a comparison is unavailable.
extension UnavailableReason {
    /// The effort does not cross both marks of the timed section, so it is
    /// not a full effort and has no route time.
    public static let timedSectionNotCovered = UnavailableReason(rawValue: "routeMatching.timedSectionNotCovered")
    /// The reference line is too short to hold a timed section.
    public static let referenceLineTooShort = UnavailableReason(rawValue: "routeMatching.referenceLineTooShort")
    /// Moving time was asked for and the effort's pause positions are not
    /// reliable. The effort is listed with its elapsed time instead.
    public static let movingClockUnavailable = UnavailableReason(rawValue: "routeMatching.movingClockUnavailable")
}

extension Alignment {
    /// The time at which the effort first reached a route distance, in
    /// seconds since the activity started, on the given clock.
    ///
    /// The time is interpolated in a straight line between the samples either
    /// side: the last point whose route distance is below `distance` and the
    /// first point whose route distance is at or beyond it. A first point that
    /// sits exactly on `distance` supplies its time directly, and so does any
    /// point that lands exactly on it.
    ///
    /// Where the effort stood still, or was held at one route distance, the
    /// spec does not say which sample counts. The first arrival is used, so a
    /// stop is charged to the stretch after it.
    ///
    /// Nil when the first point is already beyond `distance`, when no point
    /// reaches it, or when the alignment has no points. This is plain
    /// interpolation of the stored clock: it does not check whether pause
    /// positions are reliable.
    public func time(atRouteDistance distance: Double, clock: ComparisonClock) -> TimeInterval? {
        fatalError("unimplemented")
    }

    /// When the effort crossed each mark of the timed section.
    ///
    /// Each crossing is `time(atRouteDistance:clock:)` at the mark.
    /// Unavailable, in this order of checks, when:
    ///
    /// - the reference line is too short for a timed section
    ///   (`referenceLineTooShort`),
    /// - `clock` is moving time and the pause positions are not reliable
    ///   (`movingClockUnavailable`),
    /// - the effort does not cross both marks (`timedSectionNotCovered`).
    public func sectionTimes(clock: ComparisonClock, rules: MatchingRules = .standard) -> Metric<SectionTimes> {
        fatalError("unimplemented")
    }
}
