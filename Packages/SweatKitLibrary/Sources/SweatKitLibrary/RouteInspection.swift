import Foundation
import SweatKitModel
import SweatKitRouteMatching

/// On-demand evidence from the same cleaned track and rules used by grouping.
/// This is diagnostic, not a new membership decision or a persisted GPS export.
public struct RouteInspection: Sendable {
    public let coordinates: [Coordinate]
    public let detection: DetectionGates
    public let shortlisted: Bool
    public let measures: AlignmentMeasures?
    public let explicitMembership: Bool?
}

extension ActivityLibrary {
    public func inspectRoute(activity id: SourceIdentity, against route: LibraryRoute) async throws -> RouteInspection {
        guard let row = try await activity(id), !row.isHidden else { throw RouteEditError.unavailable }
        let stream = try await analysisStream(for: id)
        let track = await Self.routeTrack(stream, row: row)
        try Task.checkCancellation()
        guard try await activity(id) == row, let signature = TrackSignature(track: track) else {
            throw RouteEditError.unavailable
        }
        let decisions = try routeDecisions().decisions
        let explicit = decisions.compactMap { decision -> Bool? in
            guard decision.route == route.id,
                  case .membership(let member, let included) = decision.value,
                  row.members.contains(member) else { return nil }
            return included
        }.last
        return await Task.detached(priority: .userInitiated) {
            let match = RouteMatcher.match(track, against: [route.reference]).first
            return RouteInspection(coordinates: track.points.map(\.coordinate),
                detection: RouteDetection.gates(candidate: signature, reference: route.reference.signature),
                shortlisted: match != nil, measures: match?.measures, explicitMembership: explicit)
        }.value
    }
}
