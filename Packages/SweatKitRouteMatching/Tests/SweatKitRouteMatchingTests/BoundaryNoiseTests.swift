import Testing
import SweatKitModel
import SweatKitRouteMatching

@Suite struct BoundaryNoiseTests {
    @Test func smallGPSShiftAcrossGridBoundaryStillReachesAlignment() throws {
        let a = track(Course.eastRoad(to: 2000, north: -2))
        let b = track(Course.eastRoad(to: 2000, north: 2))
        let reference = try #require(RouteReference(track: a))
        let match = try #require(RouteMatcher.match(b, against: [reference]).first)
        #expect(match.outcome == .join)
    }

    @Test func nearbyParallelRoadStillDoesNotJoin() throws {
        let a = track(Course.eastRoad(to: 2000, north: -2))
        let b = track(Course.eastRoad(to: 2000, north: 18))
        let reference = try #require(RouteReference(track: a))
        let matches = RouteMatcher.match(b, against: [reference])
        #expect(matches.allSatisfy { $0.outcome != .join })
    }
}
