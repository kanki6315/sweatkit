import Testing

/// The builders the other suites rely on, checked against shapes whose
/// measurements are known. These pass before any behaviour exists.
@Suite struct HelperTests {
    @Test func polylinePutsAPointEveryStepAndOnEveryCorner() {
        // 40 m east then 40 m north at a 20 m step: 5 points.
        let points = Course.polyline([P(0, 0), P(40, 0), P(40, 40)], step: 20)
        #expect(points == [P(0, 0), P(20, 0), P(40, 0), P(40, 20), P(40, 40)])
    }

    @Test func squareLapsHaveFortyPointsALap() {
        // 800 m a lap at 20 m: 40 steps, so 2 laps are 81 points and 3 are 121.
        #expect(Course.squareLaps(2).count == 81)
        #expect(Course.squareLaps(3).count == 121)
        // Both start and finish on the corner, and pass it after each lap.
        #expect(Course.squareLaps(2)[0] == P(0, 0))
        #expect(Course.squareLaps(2)[40] == P(0, 0))
        #expect(Course.squareLaps(2)[80] == P(0, 0))
        // Anticlockwise goes east first; clockwise goes north first.
        #expect(Course.squareLaps(1)[1] == P(20, 0))
        #expect(Course.squareLapsClockwise(1)[1] == P(0, 20))
    }

    @Test func outAndBackIndicesAreWhereTheDocSaysTheyAre() {
        let points = Course.outAndBack()
        #expect(points.count == 202)
        #expect(points[50] == P(500, 0))
        #expect(points[100] == P(1000, 0))
        #expect(points[101] == P(1000, 10))
        #expect(points[151] == P(500, 10))
        #expect(points[201] == P(0, 10))
    }

    @Test func figureOfEightPassesTheCentreThreeTimes() {
        let points = Course.figureOfEight()
        #expect(points.count == 81)
        #expect(points[0] == P(0, 0))
        #expect(points[40] == P(0, 0))
        #expect(points[80] == P(0, 0))
        // First lobe to the north-east, second to the south-west.
        #expect(points[10] == P(200, 0))
        #expect(points[50] == P(0, -200))
        // Swapped, the south-west lobe comes first.
        #expect(Course.figureOfEight(secondLobeFirst: true)[10] == P(0, -200))
    }

    @Test func steadyTrackTimesAreDistanceOverSpeed() {
        // 100 m at 5 m/s is 20 s.
        let steady = track(Course.eastRoad(to: 100), speed: 5)
        #expect(steady.points.count == 6)
        #expect(steady.points[5].elapsedTime == 20)
        #expect(steady.points[5].movingTime == 20)
    }

    @Test func driftIsSeededBoundedAndSlow() {
        let first = Noise.drift(count: 200, maxStep: 2, bound: 8, seed: 7)
        let again = Noise.drift(count: 200, maxStep: 2, bound: 8, seed: 7)
        let other = Noise.drift(count: 200, maxStep: 2, bound: 8, seed: 8)
        #expect(first == again)
        #expect(first != other)
        #expect(first.allSatisfy { abs($0) <= 8 })
        #expect(zip(first, first.dropFirst()).allSatisfy { abs($1 - $0) <= 2 })
        #expect(first[0] == 0)
    }

    @Test func theFrameRoundTrips() {
        let plane = Plane.equator
        let back = plane.point(plane.coordinate(P(123, -456)))
        #expect(close(back.e, 123, within: 1e-6))
        #expect(close(back.n, -456, within: 1e-6))
    }
}
