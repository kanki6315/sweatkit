import Foundation
import SweatKitModel
import Testing
@testable import SweatKitFlyover

/// Metres per 0.001° of longitude on the equator, from the mean earth radius:
/// 6,371,008.8 m × 0.001 × π / 180.
private let metresPerMillidegree = 111.195_08

/// Vertices along the equator at the given longitudes, which makes lengths and
/// bearings easy to work out by hand.
private func equator(_ longitudes: [Double], bands: [Int]? = nil, samples: [Int]? = nil) throws -> FlyoverRoute {
    try FlyoverRoute(
        vertices: longitudes.map { Coordinate(latitude: 0, longitude: $0) },
        bands: bands ?? Array(repeating: 0, count: longitudes.count),
        sampleIndices: samples ?? Array(longitudes.indices)
    )
}

@Suite struct RouteValidationTests {
    @Test func rejectsBadInput() {
        let a = Coordinate(latitude: 0, longitude: 0), b = Coordinate(latitude: 0, longitude: 0.001)
        #expect(throws: FlyoverRoute.Problem.tooFewVertices) {
            try FlyoverRoute(vertices: [a], bands: [0], sampleIndices: [0])
        }
        #expect(throws: FlyoverRoute.Problem.countMismatch) {
            try FlyoverRoute(vertices: [a, b], bands: [0], sampleIndices: [0, 1])
        }
        #expect(throws: FlyoverRoute.Problem.invalidCoordinate(vertex: 1)) {
            try FlyoverRoute(vertices: [a, Coordinate(latitude: 91, longitude: 0)], bands: [0, 0], sampleIndices: [0, 1])
        }
        #expect(throws: FlyoverRoute.Problem.invalidCoordinate(vertex: 0)) {
            try FlyoverRoute(vertices: [Coordinate(latitude: .nan, longitude: 0), b], bands: [0, 0], sampleIndices: [0, 1])
        }
        #expect(throws: FlyoverRoute.Problem.negativeBand(vertex: 1)) {
            try FlyoverRoute(vertices: [a, b], bands: [0, -1], sampleIndices: [0, 1])
        }
        #expect(throws: FlyoverRoute.Problem.sampleIndicesNotIncreasing(vertex: 1)) {
            try FlyoverRoute(vertices: [a, b], bands: [0, 0], sampleIndices: [3, 3])
        }
        #expect(throws: FlyoverRoute.Problem.sampleIndicesNotIncreasing(vertex: 0)) {
            try FlyoverRoute(vertices: [a, b], bands: [0, 0], sampleIndices: [-1, 3])
        }
    }

    @Test func acceptsAValidRoute() throws {
        let route = try equator([0, 0.001, 0.002], samples: [4, 9, 20])
        #expect(route.sampleRange == 4...20)
    }
}

@Suite struct BandRunTests {
    /// Segment i takes band i, so the segments are 0 0 1 1 1 2 and the last
    /// vertex's band 0 colours nothing.
    @Test func splitsIntoMaximalRunsThatShareBoundaryVertices() {
        #expect(BandRuns.split([0, 0, 1, 1, 1, 2, 0]) == [
            BandRun(band: 0, vertices: 0...2),
            BandRun(band: 1, vertices: 2...5),
            BandRun(band: 2, vertices: 5...6),
        ])
    }

    @Test func oneBandIsOneRun() {
        #expect(BandRuns.split([3, 3, 3]) == [BandRun(band: 3, vertices: 0...2)])
    }

    @Test func aChangeOnTheLastVertexStartsNoRun() {
        #expect(BandRuns.split([1, 2]) == [BandRun(band: 1, vertices: 0...1)])
    }

    @Test func tooShortForARun() {
        #expect(BandRuns.split([1]).isEmpty)
        #expect(BandRuns.split([]).isEmpty)
    }

    /// Four vertices at 0, 1/3, 2/3 and 1. Runs are 0...2 in band 0 and 2...3
    /// in band 1, so both bands have a stop at 2/3: a hard edge.
    @Test func gradientStopsMeetAtBandEdges() throws {
        let geometry = RouteGeometry(route: try equator([0, 0.001, 0.002, 0.003], bands: [0, 0, 1, 1]))
        let stops = GradientStops.make(
            runs: BandRuns.split(geometry.route.bands),
            vertexLocations: geometry.vertexLocations(.vertexIndex)
        )
        #expect(stops.map(\.band) == [0, 0, 1, 1])
        #expect(stops.map(\.location) == [0, 2.0 / 3, 2.0 / 3, 1])
    }

    /// Segments of 1 and 3 millidegrees put the middle vertex a quarter of the
    /// way along by length, and halfway by vertex index.
    @Test func gradientLocationsByLengthOrByVertex() throws {
        let geometry = RouteGeometry(route: try equator([0, 0.001, 0.004]))
        #expect(geometry.vertexLocations(.vertexIndex) == [0, 0.5, 1])
        let byLength = geometry.vertexLocations(.projectedLength)
        #expect(abs(byLength[1] - 0.25) < 1e-9)
        #expect(byLength[2] == 1)
    }
}

@Suite struct ScrubMappingTests {
    let geometry: RouteGeometry

    init() throws {
        geometry = RouteGeometry(route: try equator([0, 0.001, 0.002, 0.003], samples: [0, 10, 30, 31]))
    }

    /// Sample 20 is halfway between the vertices from samples 10 and 30.
    @Test func sampleBetweenVerticesIsInterpolated() {
        let position = geometry.position(atSample: 20)
        #expect(position == RoutePosition(segment: 1, fraction: 0.5))
        #expect(geometry.sample(at: position) == 20)
        let coordinate = geometry.coordinate(at: position)
        #expect(abs(coordinate.longitude - 0.0015) < 1e-12)
        #expect(abs(geometry.distance(at: position) - 1.5 * metresPerMillidegree) < 0.01)
    }

    @Test func sampleOnAVertex() {
        #expect(geometry.position(atSample: 10) == RoutePosition(segment: 1, fraction: 0))
        #expect(geometry.position(atSample: 30.5) == RoutePosition(segment: 2, fraction: 0.5))
    }

    @Test func samplesOutsideTheRouteAreHeldAtTheEnds() {
        #expect(geometry.position(atSample: -5) == RoutePosition(segment: 0, fraction: 0))
        #expect(geometry.position(atSample: 31) == RoutePosition(segment: 2, fraction: 1))
        #expect(geometry.position(atSample: 1000) == RoutePosition(segment: 2, fraction: 1))
        #expect(geometry.position(atSample: .nan) == RoutePosition(segment: 0, fraction: 0))
    }

    @Test func vertexAndSampleMapBothWays() throws {
        for vertex in 0..<4 {
            let sample = try #require(geometry.sample(atVertex: vertex))
            let position = geometry.position(atSample: Double(sample))
            #expect(geometry.nearestVertex(to: position) == vertex)
        }
        #expect(geometry.sample(atVertex: 4) == nil)
        #expect(geometry.nearestVertex(to: RoutePosition(segment: 1, fraction: 0.6)) == 2)
        #expect(geometry.nearestVertex(to: RoutePosition(segment: 1, fraction: 0.4)) == 1)
    }

    @Test func distanceMapsToAPosition() {
        let position = geometry.position(atDistance: 1.5 * metresPerMillidegree)
        #expect(position.segment == 1)
        #expect(abs(position.fraction - 0.5) < 1e-4)
        #expect(geometry.position(atDistance: -1) == RoutePosition(segment: 0, fraction: 0))
        #expect(geometry.position(atDistance: 1e9) == RoutePosition(segment: 2, fraction: 1))
    }

    /// Equal segments: halfway along segment 1 is halfway along the line, and
    /// a quarter of the way along the run from vertex 1 to vertex 3.
    @Test func strokeFractionForDimmingAhead() {
        let middle = RoutePosition(segment: 1, fraction: 0.5)
        #expect(abs(geometry.strokeFraction(at: middle) - 0.5) < 1e-9)
        #expect(abs(geometry.strokeFraction(at: middle, vertices: 1...3) - 0.25) < 1e-9)
        #expect(geometry.strokeFraction(at: middle, vertices: 2...3) == 0)
        #expect(geometry.strokeFraction(at: middle, vertices: 0...1) == 1)
    }
}

@Suite struct FollowHeadingTests {
    /// North for 0.02° from (−0.02, 0) to (0, 0), then east along the equator
    /// to (0, 0.02). Each leg is about 2,224 m.
    let geometry: RouteGeometry
    let legLength = 20 * metresPerMillidegree

    init() throws {
        geometry = RouteGeometry(route: try FlyoverRoute(
            vertices: [
                Coordinate(latitude: -0.02, longitude: 0),
                Coordinate(latitude: 0, longitude: 0),
                Coordinate(latitude: 0, longitude: 0.02),
            ],
            bands: [0, 0, 0],
            sampleIndices: [0, 1, 2]
        ))
    }

    /// 1,000 m in, every look-ahead point is still on the northbound leg.
    @Test func straightNorth() throws {
        let heading = try #require(FollowHeading().target(on: geometry, at: geometry.position(atDistance: 1000)))
        #expect(abs(Geodesy.shortestTurn(from: 0, to: heading)) < 1e-6)
    }

    /// On the eastbound leg along the equator every point is due east.
    @Test func straightEast() throws {
        let heading = try #require(FollowHeading().target(on: geometry, at: geometry.position(atDistance: legLength + 500)))
        #expect(abs(heading - 90) < 1e-6)
    }

    /// 100 m before the corner the points are 50 to 200 m along the east leg,
    /// at bearings from atan(50/100) ≈ 26.6° to atan(200/100) ≈ 63.4°, so their
    /// mean lies between.
    @Test func cornerAheadIsAveraged() throws {
        let heading = try #require(FollowHeading().target(on: geometry, at: geometry.position(atDistance: legLength - 100)))
        #expect(heading > 26.5 && heading < 63.5)
    }

    /// At the very end there is nothing ahead.
    @Test func noTargetAtTheEnd() {
        #expect(FollowHeading().target(on: geometry, at: RoutePosition(segment: 1, fraction: 1)) == nil)
    }

    /// 5 m before the end only the end point is ahead, and it is closer than
    /// the 10 m minimum span.
    @Test func noTargetInTheLastMetres() {
        let position = geometry.position(atDistance: 2 * legLength - 5)
        #expect(FollowHeading().target(on: geometry, at: position) == nil)
    }
}

@Suite struct HeadingSmootherTests {
    @Test func firstTargetIsTakenAsIs() {
        var smoother = HeadingSmoother()
        #expect(smoother.step(towards: 400, seconds: 0.1) == 40)
    }

    /// From 350° to 10° the short way is +20°. In 0.1 s with a 0.8 s time
    /// constant it closes 1 − e^(−0.125) ≈ 11.75% of that: 2.35°, under the
    /// 9° the 90°/s limit allows.
    @Test func turnsTheShortWayAcrossNorth() throws {
        var smoother = HeadingSmoother(timeConstant: 0.8, maximumRate: 90)
        smoother.reset(to: 350)
        let step = smoother.step(towards: 10, seconds: 0.1)
        let heading = try #require(step)
        #expect(abs(heading - 352.350_06) < 1e-4)
    }

    /// From 0° to 170°, 11.75% would be 19.97°, so the 9° limit applies.
    @Test func turnRateIsLimited() throws {
        var smoother = HeadingSmoother(timeConstant: 0.8, maximumRate: 90)
        smoother.reset(to: 0)
        let step = smoother.step(towards: 170, seconds: 0.1)
        let heading = try #require(step)
        #expect(abs(heading - 9) < 1e-9)
    }

    @Test func settlesOverTime() {
        var smoother = HeadingSmoother()
        smoother.reset(to: 0)
        for _ in 0..<600 { smoother.step(towards: 120, seconds: 1.0 / 60) }
        #expect(smoother.hasSettled(on: 120))
    }

    @Test func nilTargetHoldsTheHeading() {
        var smoother = HeadingSmoother()
        smoother.reset(to: 45)
        #expect(smoother.step(towards: nil, seconds: 1) == 45)
        #expect(smoother.step(towards: 90, seconds: 0) == 45)
    }
}

@Test func reduceMotionReplacesFollowWithOverview() {
    let options = FlyoverOptions(cameraMode: .follow)
    #expect(options.effectiveCameraMode(reduceMotion: true) == .overview)
    #expect(options.effectiveCameraMode(reduceMotion: false) == .follow)
}
