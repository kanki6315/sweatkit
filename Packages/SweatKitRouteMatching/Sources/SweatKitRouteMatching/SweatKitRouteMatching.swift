import SweatKitModel

/// Repeated-route detection and alignment, and effort-against-effort
/// comparison. Pure Swift, with no interface or network code. The spec's
/// "Repeated-route comparison" section is the contract.
///
/// The work is split the way the spec splits it:
///
/// - `RouteDetection` is step 1: resampling, grid cells, the candidate gates
///   and the shared-cell shortlist.
/// - `RouteAlignment` is step 2: the ordered forward-only mapping onto a
///   reference line, the five measures and the join, review or reject outcome.
/// - `RouteMatcher` runs both steps for one activity against every known route.
/// - `TimedSection` and `Alignment.sectionTimes` give the clock origin.
/// - `RouteComparison` puts two efforts on the 10 m distance grid and on the
///   ghost marker's shared clock.
///
/// Every threshold lives in `MatchingRules`.
public enum SweatKitRouteMatching {
    /// The version of the matching rules, for `Provenance.algorithmVersion`.
    /// It changes whenever a rule or a starting value in `MatchingRules` does.
    public static let algorithmVersion = 3
}
