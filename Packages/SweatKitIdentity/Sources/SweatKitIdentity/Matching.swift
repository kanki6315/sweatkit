import Foundation
import SweatKitModel

/// What the automatic match rule reads from one source record.
public struct MatchCandidate: Hashable, Codable, Sendable {
    public var identity: SourceIdentity
    public var sport: Sport
    public var start: Date
    /// Elapsed seconds, pauses included.
    public var elapsed: TimeInterval
    /// Metres, or nil when the record states no distance.
    public var distance: Double?
    public var isIndoor: Bool
    /// The identities of other source records that this record's own source
    /// identifiers name, such as the Garmin activity a Health workout says it
    /// was written from. Empty when it names none.
    public var linkedIdentities: Set<SourceIdentity>

    public init(
        identity: SourceIdentity,
        sport: Sport,
        start: Date,
        elapsed: TimeInterval,
        distance: Double? = nil,
        isIndoor: Bool = false,
        linkedIdentities: Set<SourceIdentity> = []
    ) {
        self.identity = identity
        self.sport = sport
        self.start = start
        self.elapsed = elapsed
        self.distance = distance
        self.isIndoor = isIndoor
        self.linkedIdentities = linkedIdentities
    }
}

/// The tolerances of the automatic match rule. The spec's values are
/// starting values, so they live here and nowhere else.
public struct MatchTolerances: Hashable, Codable, Sendable {
    /// The most two start times may differ by, in seconds.
    public var startDifference: TimeInterval
    /// The most two elapsed durations may differ by, as a fraction of the
    /// longer one.
    public var durationFraction: Double
    /// The most two distances may differ by, as a fraction of the longer one.
    public var distanceFraction: Double

    public init(startDifference: TimeInterval, durationFraction: Double, distanceFraction: Double) {
        self.startDifference = startDifference
        self.durationFraction = durationFraction
        self.distanceFraction = distanceFraction
    }

    /// "Start times are within 2 minutes."
    public static let standardStartDifference: TimeInterval = 2 * 60
    /// "Elapsed durations are within 5%."
    public static let standardDurationFraction: Double = 0.05
    /// "Distances are within 5%."
    public static let standardDistanceFraction: Double = 0.05

    /// The spec's starting values.
    public static let standard = MatchTolerances(
        startDifference: standardStartDifference,
        durationFraction: standardDurationFraction,
        distanceFraction: standardDistanceFraction
    )
}

/// Why two records were matched automatically.
public enum MatchBasis: String, Codable, Sendable, CaseIterable {
    /// One record's source identifier names the other. This settles the match
    /// on its own.
    case sourceIdentifier
    /// Sport family, start, duration and, outdoors, distance all agree.
    case tolerances
}

/// What the automatic rule says about two source records.
public enum MatchOutcome: Hashable, Codable, Sendable {
    /// The records are merged automatically.
    case sameActivity(MatchBasis)
    /// The records overlap in time but fail the rule. They stay separate and
    /// are flagged for the user, who merges them or keeps both.
    case possibleDuplicate
    /// The records fail the rule and do not overlap in time.
    case unrelated

    /// Applies the automatic match rule to two records. The outcome is the
    /// same whichever record is given first.
    ///
    /// A source identifier is checked first: when either record's
    /// `linkedIdentities` holds the other's identity, the outcome is
    /// `.sameActivity(.sourceIdentifier)` whatever the tolerances say.
    ///
    /// Otherwise the records match, as `.sameActivity(.tolerances)`, only
    /// when all of these hold:
    /// - the sport families are equal,
    /// - the start times differ by no more than `startDifference`,
    /// - the elapsed durations differ by no more than `durationFraction`,
    /// - when both records are outdoor, the distances differ by no more than
    ///   `distanceFraction`,
    /// - the two records overlap in time.
    ///
    /// Records that fail are `.possibleDuplicate` when they overlap in time,
    /// except negligible boundary overlaps between adjacent same-provider
    /// sessions (at most 30 seconds and 1% of the shorter recording, with
    /// starts more than the start tolerance apart). Those remain unrelated.
    ///
    /// Readings taken where the spec is ambiguous or silent:
    /// - "Within" includes the limit: a start difference of exactly 120 s
    ///   passes, and so does a difference of exactly 5%.
    /// - "Within 5%" is measured against the larger of the two values: the
    ///   difference is at most 5% of the larger. This is symmetric.
    /// - "For outdoor activities only" means the distance test applies only
    ///   when both records are outdoor. If either is indoor it is skipped.
    /// - When the distance test applies and either distance is nil, the test
    ///   fails. A missing distance is not zero and cannot be shown to agree.
    /// - "Overlap in time" compares the half-open spans from `start` to
    ///   `start + elapsed`. Spans that only touch do not overlap.
    /// - Overlapping records of different sport families are still flagged,
    ///   because the spec flags every overlapping pair that fails the rule.
    /// - Two short records that agree on everything and start within
    ///   `startDifference` of each other, but where one ends before the
    ///   other starts, are separate recordings and are `.unrelated`.
    /// - A record whose elapsed time is zero or less covers no time and
    ///   overlaps nothing, so it never matches on the tolerances.
    /// - Two records of sport `.other` are of one family, `.other`, by the
    ///   literal rule, so they can match.
    public static func between(
        _ first: MatchCandidate,
        _ second: MatchCandidate,
        tolerances: MatchTolerances = .standard
    ) -> MatchOutcome {
        if first.linkedIdentities.contains(second.identity)
            || second.linkedIdentities.contains(first.identity) {
            return .sameActivity(.sourceIdentifier)
        }
        guard overlapInTime(first, second) else { return .unrelated }
        if passesTolerances(first, second, tolerances: tolerances) {
            return .sameActivity(.tolerances)
        }
        // Adjacent sessions from one provider can overlap by a few seconds
        // at a recording boundary. Do not turn that sliver into a duplicate
        // prompt. Contained partial recordings and cross-provider overlaps
        // retain the existing review behavior.
        let overlap = min(first.start.addingTimeInterval(first.elapsed), second.start.addingTimeInterval(second.elapsed))
            .timeIntervalSince(max(first.start, second.start))
        if first.identity.source == second.identity.source,
           abs(first.start.timeIntervalSince(second.start)) > tolerances.startDifference,
           overlap <= 30, overlap / min(first.elapsed, second.elapsed) <= 0.01 {
            return .unrelated
        }
        return .possibleDuplicate
    }

    /// Whether the two records agree on sport family, start, duration and,
    /// when both are outdoor, distance.
    private static func passesTolerances(
        _ first: MatchCandidate,
        _ second: MatchCandidate,
        tolerances: MatchTolerances
    ) -> Bool {
        guard first.sport.family == second.sport.family else { return false }
        guard abs(first.start.timeIntervalSince(second.start)) <= tolerances.startDifference else {
            return false
        }
        guard isWithin(tolerances.durationFraction, first.elapsed, second.elapsed) else { return false }
        if first.isIndoor || second.isIndoor {
            return true
        }
        guard let firstDistance = first.distance, let secondDistance = second.distance else {
            return false
        }
        return isWithin(tolerances.distanceFraction, firstDistance, secondDistance)
    }

    /// Whether two values differ by no more than `fraction` of the larger.
    private static func isWithin(_ fraction: Double, _ first: Double, _ second: Double) -> Bool {
        abs(first - second) <= fraction * max(first, second)
    }

    /// Whether the half-open spans of the two records share any time. A
    /// record with no elapsed time covers no time, so it overlaps nothing.
    private static func overlapInTime(_ first: MatchCandidate, _ second: MatchCandidate) -> Bool {
        guard first.elapsed > 0, second.elapsed > 0 else { return false }
        let firstEnd = first.start.addingTimeInterval(first.elapsed)
        let secondEnd = second.start.addingTimeInterval(second.elapsed)
        return first.start < secondEnd && second.start < firstEnd
    }
}

/// The automatic rule applied to every pair in a set of records.
public struct MatchScan: Hashable, Codable, Sendable {
    /// One automatic "same activity" link for every pair the rule merges,
    /// ordered by link name.
    public var links: [LinkRecord]
    /// Every pair flagged as a possible duplicate, in ascending order.
    public var possibleDuplicates: [IdentityPair]

    public init(links: [LinkRecord], possibleDuplicates: [IdentityPair]) {
        self.links = links
        self.possibleDuplicates = possibleDuplicates
    }

    /// Compares every pair of `records` with `MatchOutcome.between`.
    ///
    /// Each link is built by `LinkRecord.automatic` with `time` and `device`,
    /// so two devices scanning the same records write records of the same
    /// names. The result does not depend on the order of `records`.
    ///
    /// The scan does not read existing links. A pair the user has already
    /// merged or kept separate is settled by the link in effect, where a
    /// user-made link beats an automatic one. `awaitingReview(given:)`
    /// leaves such pairs out of the flagged list.
    ///
    /// The spec does not say what one identity given twice means. A record
    /// is never compared with another of the same identity, so no link from
    /// a record to itself is written. If the two copies differ and one
    /// matches a third record where the other is only flagged, the pair is
    /// linked and not flagged.
    public static func scan(
        _ records: [MatchCandidate],
        at time: Date,
        device: DeviceID,
        tolerances: MatchTolerances = .standard
    ) -> MatchScan {
        var linked: Set<IdentityPair> = []
        var flagged: Set<IdentityPair> = []
        for (index, first) in records.enumerated() {
            for second in records[(index + 1)...] where second.identity != first.identity {
                let pair = IdentityPair(first.identity, second.identity)
                switch MatchOutcome.between(first, second, tolerances: tolerances) {
                case .sameActivity:
                    linked.insert(pair)
                case .possibleDuplicate:
                    flagged.insert(pair)
                case .unrelated:
                    break
                }
            }
        }
        // Only reachable when one identity is given twice with different
        // values. A pair that matched is merged, so it is not also flagged.
        flagged.subtract(linked)
        let links = linked
            .map { LinkRecord.automatic(pair: $0, kind: .sameActivity, time: time, device: device) }
            .sorted { ($0.name, $0.pair) < ($1.name, $1.pair) }
        return MatchScan(links: links, possibleDuplicates: flagged.sorted())
    }

    /// The flagged pairs the user has not yet dealt with, in ascending
    /// order: `possibleDuplicates` without every pair that has a user-made
    /// link among `links`.
    ///
    /// "The user merges them or keeps both." The spec does not say how the
    /// flag is then cleared. This takes the literal reading: a user-made
    /// link of either kind on the pair clears it, and nothing else does. An
    /// automatic link on the pair does not, because the user has not looked
    /// at it.
    public func awaitingReview(given links: some Sequence<LinkRecord>) -> [IdentityPair] {
        let reviewed = Set(links.lazy.filter { $0.maker == .user }.map(\.pair))
        return possibleDuplicates.filter { !reviewed.contains($0) }
    }
}
