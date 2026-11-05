import SweatKitModel
@testable import SweatKitTrackCleanup
import Testing

/// Step 2's radius: a slow run collapses only while it stays near the point
/// where it began, so slow walking is kept and jitter in one place is not.
@Suite struct StopRadiusTests {
    @Test func theRadiusIsTenMetres() {
        #expect(CleanupRules.stopRadius == 10)
    }

    @Test func aSlowWalkIsKeptAtAboutOneRadius() {
        // 0.3 m/s on foot is below the 0.5 m/s floor, so every second is
        // slow. Second i is at 0.3 * i m east, for 0 to 204 s (61.2 m).
        // From the anchor at 0: 0.3 * 33 = 9.9 m is within 10 m, and
        // 0.3 * 34 = 10.2 m is beyond, so second 34 is kept and anchors the
        // next stop. The same happens every 34 s: seconds 0, 34, 68, 102,
        // 136, 170 and 204, each 10.2 m on from the last. Second 204 is
        // 10.2 m from 170, so the last point is kept too.
        let seconds = steadyEast(count: 205, speed: 0.3)
        let cleaned = TrackCleanup.clean(makeStream(seconds), sport: .walking)
        #expect(cleaned.points.map(\.sampleIndex) == [0, 34, 68, 102, 136, 170, 204])
        #expect(cleaned.points.map(\.coveredSamples) == [
            0...33, 34...67, 68...101, 102...135, 136...169, 170...203, 204...204,
        ])
        // Six steps of 10.2 m: 61.2 m, the whole walk.
        #expect(close(cleaned.length, 61.2))
    }

    @Test func aSlowWalkAtFourTenthsKeepsItsLengthWithinTheRadius() {
        // 0.4 m/s for 300 s: 120 m in a straight line. 0.4 * 25 = 10 m lands
        // on the radius itself, where rounding decides the side, so this
        // test pins only what holds either way: each kept point is 10 or
        // 10.4 m past the one before (25 or 26 s of walking), and the last
        // kept point is within 10 m of the end, so the length is between
        // 110 and 120 m.
        let seconds = steadyEast(count: 301, speed: 0.4)
        let cleaned = TrackCleanup.clean(makeStream(seconds), sport: .walking)
        let gaps = zip(cleaned.points, cleaned.points.dropFirst()).map { $1.sampleIndex - $0.sampleIndex }
        #expect(gaps.allSatisfy { $0 == 25 || $0 == 26 })
        #expect(cleaned.length > 110 - 1e-6 && cleaned.length <= 120 + 1e-6)
        // 120 m in steps of 10 to 10.4 m is 11 or 12 steps, so 12 or 13 points.
        #expect((12...13).contains(cleaned.points.count))
    }

    @Test func jitterInsideTheRadiusStillCollapses() {
        // Ten seconds standing with speed 0 and jitter of about a metre:
        // every point is within 10 m of the first, so one point stands for
        // seconds 0 to 9.
        let seconds = (0..<10).map { index -> Second in
            let wobble = StopTests.jitter[index % StopTests.jitter.count]
            return Second(east: wobble.east, north: wobble.north, speed: 0)
        }
        let cleaned = TrackCleanup.clean(makeStream(seconds), sport: .walking)
        #expect(cleaned.points.map(\.sampleIndex) == [0])
        #expect(cleaned.points[0].coveredSamples == 0...9)
    }

    @Test func aStopThenASlowWalkThenAStop() {
        // Seconds 0-9 stand at 0 with jitter of about a metre (speed 0.1).
        // Seconds 10-145 walk east at 0.3 m/s, second i at 0.3 * (i - 9) m,
        // so second 145 is at 40.8 m. Seconds 146-155 stand near 40.8 m with
        // the same jitter (speed 0.1).
        //
        // Anchor second 0. The walk is within 10 m of it until 0.3 * 33
        // = 9.9 m at second 42; second 43 at 10.2 m is kept. Then every 34 s
        // as in the slow walk: 77 (20.4 m), 111 (30.6 m), 145 (40.8 m). The
        // second stop's jitter is within about a metre of 145 and collapses
        // into it.
        var seconds: [Second] = []
        for index in 0..<10 {
            let wobble = StopTests.jitter[index % StopTests.jitter.count]
            seconds.append(Second(east: wobble.east, north: wobble.north, speed: 0.1))
        }
        for index in 10...145 {
            seconds.append(Second(east: 0.3 * Double(index - 9), speed: 0.3))
        }
        for index in 146...155 {
            let wobble = StopTests.jitter[1 + index % (StopTests.jitter.count - 1)]
            seconds.append(Second(east: 40.8 + wobble.east, north: wobble.north, speed: 0.1))
        }
        let cleaned = TrackCleanup.clean(makeStream(seconds), sport: .walking)
        #expect(cleaned.points.map(\.sampleIndex) == [0, 43, 77, 111, 145])
        #expect(cleaned.points.map(\.coveredSamples) == [0...42, 43...76, 77...110, 111...144, 145...155])
        // 0 -> 10.2 -> 20.4 -> 30.6 -> 40.8 m: 40.8 m, the slow stretch kept.
        #expect(close(cleaned.length, 40.8))
    }

    @Test func aPointExactlyAtTheRadiusCollapses() {
        // "Within the radius" includes the radius itself: a slow point whose
        // measured distance from the anchor equals the radius collapses, and
        // one a millimetre further is kept. The radius is set to the ruler's
        // own distance to second 1 so that the two are exactly equal.
        let seconds = [
            Second(east: 0, speed: 0),
            Second(east: 7, north: 3, speed: 0),
            Second(east: 7.001, north: 3, speed: 0),
        ]
        let points = TrackCleanup.positions(in: makeStream(seconds))
        let radius = TrackGeodesy.distance(from: points[0].coordinate, to: points[1].coordinate)
        let speed = Series([0, 0, 0])
        let atRadius = TrackCleanup.collapsingStops(Array(points.prefix(2)), speed: speed, stoppedBelow: 0.5, radius: radius)
        #expect(atRadius.map(\.sampleIndex) == [0])
        #expect(atRadius[0].coveredSamples == 0...1)
        // Second 2 is 7.001 m east and 3 m north: sqrt(7.001^2 + 9) is about
        // 0.0009 m beyond the radius, so it is kept.
        let beyond = TrackCleanup.collapsingStops([points[0], points[2]], speed: speed, stoppedBelow: 0.5, radius: radius)
        #expect(beyond.map(\.sampleIndex) == [0, 2])
    }
}
