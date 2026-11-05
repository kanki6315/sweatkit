import Foundation
import SweatKitModel
import Testing
@testable import SweatKitAnalysis

/// "Splits: pace, heart rate and ascent per km, for walking, running and
/// hiking."
///
/// The rule under test: a second belongs to the split its cumulative
/// distance falls in, a second exactly on a kilometre mark opens the next
/// split, and a split's duration is its count of timer seconds.
@Suite struct SplitTests {
    /// 376 s at 4 m/s: second t holds 4t metres, so second 250 holds exactly
    /// 1000 m and the last second, 375, holds 1500 m.
    ///
    /// - Split 0 is seconds 0...249: 250 s, a whole kilometre.
    /// - Split 1 is seconds 250...375: 126 s, 1500 - 1000 = 500 m.
    ///
    /// Heart rate is 150 through split 0 and 160 through split 1. Altitude
    /// steps from 100 m to 110 m at second 100 (in split 0) and to 115 m at
    /// second 300 (in split 1).
    private var steady: AnalysisStream {
        makeStream(
            count: 376,
            heartRate: run(150, 250) + run(160, 126),
            altitude: run(100, 100) + run(110, 200) + run(115, 76),
            distance: ramp(376, perSecond: 4)
        )
    }

    @Test func eachKilometreIsASplitAndTheRestIsAPartSplit() throws {
        let splits = try #require(analyse(steady, sport: .running).splits.value)
        #expect(splits.map(\.index) == [0, 1])
        #expect(splits.map(\.distance) == [1000, 500])
    }

    @Test func aSecondExactlyOnAKilometreMarkOpensTheNextSplit() throws {
        // Second 250 holds exactly 1000 m. In split 1 it makes the durations
        // 250 s and 126 s; in split 0 they would be 251 s and 125 s.
        let splits = try #require(analyse(steady, sport: .running).splits.value)
        #expect(splits.map(\.duration) == [250, 126])
    }

    @Test func paceIsSecondsPerKilometre() throws {
        // Split 0: 250 s over 1 km = 250 s/km.
        // Split 1: 126 s over 0.5 km = 252 s/km.
        let splits = try #require(analyse(steady, sport: .running).splits.value)
        try #require(splits.count == 2)
        expectClose(splits[0].pace, 250)
        expectClose(splits[1].pace, 252)
    }

    @Test func heartRateIsAveragedPerSplit() throws {
        let splits = try #require(analyse(steady, sport: .running).splits.value)
        try #require(splits.count == 2)
        expectClose(splits[0].averageHeartRate, 150)
        expectClose(splits[1].averageHeartRate, 160)
    }

    @Test func ascentIsCreditedToTheSplitWhereItIsCounted() throws {
        // +10 m is counted at second 100, in split 0. +5 m is counted at
        // second 300, in split 1. Together they are the activity's 15 m.
        let metrics = analyse(steady, sport: .running)
        let splits = try #require(metrics.splits.value)
        try #require(splits.count == 2)
        #expect(splits[0].ascent == .available(10))
        #expect(splits[1].ascent == .available(5))
        #expect(metrics.ascent == .available(15))
    }

    @Test func pausedSecondsAreNotInASplitsDuration() throws {
        // 100 s at 4 m/s (0 to 396 m), 50 s paused at 400 m, then 4 m/s
        // again: second t >= 150 holds 400 + 4(t - 150) metres, so second 300
        // holds exactly 1000 m and the last second, 350, holds 1200 m.
        //
        // Split 0 is seconds 0...299: 300 seconds, 50 of them paused, so
        // 250 s. Split 1 is seconds 300...350: 51 s and 200 m.
        //
        // Heart rate is 150 while running and 90 while paused. Split 0
        // averages its timer seconds only: 150.
        let moving = (150..<351).map { Optional(400 + 4 * Double($0 - 150)) }
        let stream = makeStream(
            count: 351,
            pauses: .known(paused: [100..<150]),
            heartRate: run(150, 100) + run(90, 50) + run(150, 201),
            distance: ramp(100, perSecond: 4) + run(400, 50) + moving
        )
        let splits = try #require(analyse(stream, sport: .running).splits.value)
        try #require(splits.count == 2)
        #expect(splits.map(\.duration) == [250, 51])
        #expect(splits.map(\.distance) == [1000, 200])
        expectClose(splits[0].pace, 250)
        expectClose(splits[0].averageHeartRate, 150)
    }

    @Test func aSecondWithMissingDistanceTakesTheLastDistanceBeforeIt() throws {
        // The steady run with distance missing for seconds 240...259.
        // Second 239 holds 956 m, so the 20 missing seconds stay in split 0.
        // Second 260 holds 1040 m and opens split 1.
        // Split 0 is seconds 0...259: 260 s. Split 1 is 260...375: 116 s.
        let distance = ramp(240, perSecond: 4) + run(nil, 20) + (260..<376).map { Optional(4 * Double($0)) }
        let stream = makeStream(count: 376, distance: distance)
        let splits = try #require(analyse(stream, sport: .running).splits.value)
        #expect(splits.map(\.duration) == [260, 116])
        #expect(splits.map(\.distance) == [1000, 500])
    }

    @Test func aSplitWithoutHeartRateOrAltitudeSaysSo() throws {
        let stream = makeStream(count: 376, distance: ramp(376, perSecond: 4))
        let splits = try #require(analyse(stream, sport: .running).splits.value)
        try #require(splits.count == 2)
        #expect(splits[0].averageHeartRate == .unavailable(.noHeartRate))
        #expect(splits[0].ascent == .unavailable(.noAltitude))
        expectClose(splits[0].pace, 250)
    }

    @Test(arguments: [Sport.walking, .running, .hiking])
    func splitsAreForWalkingRunningAndHiking(sport: Sport) throws {
        let splits = try #require(analyse(steady, sport: sport).splits.value)
        #expect(splits.count == 2)
    }

    @Test(arguments: [Sport.cycling, .other])
    func splitsAreNotDefinedOffFoot(sport: Sport) {
        #expect(analyse(steady, sport: sport).splits == .unavailable(.notDefinedForSport))
    }

    @Test func splitsAreUnavailableWithoutDistance() {
        let stream = makeStream(count: 100, heartRate: run(150, 100))
        #expect(analyse(stream, sport: .running).splits == .unavailable(.noDistance))
    }
}
