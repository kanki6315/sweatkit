import Foundation
import SweatKitModel
import Testing
@testable import SweatKitAnalysis

/// "Best distances: fastest 1 km, 5 km and 10 km by timer time, for walking
/// and running."
///
/// The rule under test: the fewest timer seconds between two seconds of the
/// stream whose cumulative distances differ by at least the distance.
@Suite struct BestDistanceTests {
    private func best(_ stream: AnalysisStream, sport: Sport = .running) -> [Metric<TimeInterval>] {
        analyse(stream, sport: sport).bestDistances.map(\.time)
    }

    @Test func thereIsOneEntryPerDistanceInOrder() {
        let stream = makeStream(count: 201, distance: ramp(201, perSecond: 5))
        #expect(analyse(stream, sport: .running).bestDistances.map(\.distance) == [1000, 5000, 10_000])
    }

    @Test func aSteadyKilometreTakesItsDistanceOverItsSpeed() {
        // 5 m/s: second 0 holds 0 m and second 200 holds 1000 m, 200 s apart.
        // The run stops there, so 5 km and 10 km are not covered.
        let stream = makeStream(count: 201, distance: ramp(201, perSecond: 5))
        #expect(best(stream) == [
            .available(200),
            .unavailable(.distanceNotCovered),
            .unavailable(.distanceNotCovered),
        ])
    }

    @Test func fiveMetresShortOfAKilometreIsNotCovered() {
        // 200 samples at 5 m/s end at 995 m.
        let stream = makeStream(count: 200, distance: ramp(200, perSecond: 5))
        #expect(best(stream)[0] == .unavailable(.distanceNotCovered))
    }

    @Test func allThreeDistancesOfASteadyTenKilometres() {
        // 5 m/s for 2001 samples reaches 10,000 m at second 2000.
        // 1 km = 200 s, 5 km = 1000 s, 10 km = 2000 s.
        let stream = makeStream(count: 2001, distance: ramp(2001, perSecond: 5))
        #expect(best(stream) == [.available(200), .available(1000), .available(2000)])
    }

    @Test func theFastestStretchIsFoundInsideTheActivity() {
        // 100 s at 2 m/s (to 200 m), 200 s at 5 m/s (to 1200 m), 100 s at
        // 2 m/s (to 1400 m). Second 100 holds 200 m and second 300 holds
        // 1200 m: 1000 m in 200 s. Nothing is faster, because 1000 m at the
        // top speed of 5 m/s takes 200 s. From the start it would be 260 s.
        func metres(_ t: Int) -> Double {
            if t <= 100 { return 2 * Double(t) }
            if t <= 300 { return 200 + 5 * Double(t - 100) }
            return 1200 + 2 * Double(t - 300)
        }
        let distance = (0...400).map { Optional(metres($0)) }
        let stream = makeStream(count: 401, distance: distance)
        #expect(best(stream)[0] == .available(200))
    }

    @Test func aPauseInsideTheStretchAddsNoTime() {
        // 100 s at 5 m/s (second 100 holds 500 m), 60 s paused at 500 m,
        // then 5 m/s again: second t >= 160 holds 500 + 5(t - 160), so
        // second 260 holds 1000 m. Seconds 0 to 260 span 260 s, 60 of them
        // paused: 200 s of timer time.
        let after = (160...260).map { Optional(500 + 5 * Double($0 - 160)) }
        let stream = makeStream(
            count: 261,
            pauses: .known(paused: [100..<160]),
            distance: ramp(100, perSecond: 5) + run(500, 60) + after
        )
        #expect(best(stream)[0] == .available(200))
    }

    @Test func bestDistancesAreForWalkingAndRunning() {
        let stream = makeStream(count: 201, distance: ramp(201, perSecond: 5))
        #expect(best(stream, sport: .walking)[0] == .available(200))
        #expect(best(stream, sport: .running)[0] == .available(200))
    }

    @Test(arguments: [Sport.hiking, .cycling, .other])
    func bestDistancesAreNotDefinedForOtherSports(sport: Sport) {
        // Hiking has splits but no best distances.
        let stream = makeStream(count: 201, distance: ramp(201, perSecond: 5))
        #expect(best(stream, sport: sport) == Array(repeating: .unavailable(.notDefinedForSport), count: 3))
    }

    @Test func bestDistancesAreUnavailableWithoutDistance() {
        let stream = makeStream(count: 300, heartRate: run(150, 300))
        #expect(best(stream) == Array(repeating: .unavailable(.noDistance), count: 3))
    }
}
