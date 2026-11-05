import SweatKitModel
import SweatKitTimeline
import Testing
@testable import SweatKitDetail

@Suite("Stats at the cursor")
struct CursorStatsTests {
    let stream = makeStream(
        count: 5,
        power: [100, 200, nil, 400, 500],
        heartRate: [120, 121, 122, nil, 124],
        speed: [5, 6, 7, 8, 9],
        cadence: [80, 81, nil, 83, 84],
        altitude: [10, 11, 12, 13, nil],
        distance: [0, 6, nil, 21, 30],
        gradient: [0.01, 0.02, 0.03, 0.04, 0.05]
    )

    @Test func threeSecondPowerAtTheStartAndAcrossAGap() {
        let detail = DetailPreparation.prepare(makeInput(stream))
        #expect(detail.cursorStats(at: 0).power == 100) // window cut at second 0: 100 / 1
        #expect(detail.cursorStats(at: 1).power == 150) // (100 + 200) / 2
        #expect(detail.cursorStats(at: 2).power == nil) // no power of its own
        #expect(detail.cursorStats(at: 3).power == 300) // seconds 1...3: (200 + 400) / 2, the gap in neither sum nor count
        #expect(detail.cursorStats(at: 4).power == 450) // seconds 2...4: (400 + 500) / 2
    }

    @Test func everyStatIsTheStreamsOwnAndMissingStaysMissing() {
        let detail = DetailPreparation.prepare(makeInput(stream))
        #expect(detail.cursorStats(at: 2) == CursorStats(
            distance: nil,
            elapsedTime: 2,
            speed: 7,
            power: nil,
            heartRate: 122,
            cadence: nil,
            elevation: 12,
            gradient: 0.03
        ))
        #expect(detail.cursorStats(at: 3).heartRate == nil)
        #expect(detail.cursorStats(at: 4).elevation == nil)
    }

    @Test func aScrubPastEitherEndIsClamped() {
        let detail = DetailPreparation.prepare(makeInput(stream))
        #expect(detail.cursorStats(at: -3).elapsedTime == 0)
        #expect(detail.cursorStats(at: 99).elapsedTime == 4)
    }

    @Test func powerIsForCyclingOnly() {
        let detail = DetailPreparation.prepare(makeInput(stream, sport: .walking))
        #expect(detail.cursorStats(at: 1).power == nil)
        #expect(detail.cursorStats(at: 1).cadence == 81)
    }
}

@Suite("Stats for a selected range")
struct RangeStatsTests {
    // Cycling, so the ascent threshold is 1.5 m.
    let stream = makeStream(
        count: 6,
        power: [100, 200, nil, 400, 500, 600],
        heartRate: [120, 130, 140, 150, 160, 170],
        altitude: [100, 101, 103, 102, 104, 100],
        distance: [0, 10, 20, nil, 40, 50]
    )

    @Test func aMiddleRange() {
        let detail = DetailPreparation.prepare(makeInput(stream))
        // Seconds 2...4.
        // Time: 3 seconds.
        // Distance: last present 40 (second 4) minus first present 20 (second 2) = 20.
        // Ascent over 103, 102, 104: 102 is a 1 m dip, under the threshold,
        //   so low = 102, high = 103; 104 is 2 m above the low, at least
        //   1.5, so a climb of 2 m counts.
        // Average power: (400 + 500) / 2, the missing second left out = 450.
        // Average heart rate: (140 + 150 + 160) / 3 = 150.
        #expect(detail.rangeStats(2...4) == RangeStats(time: 3, distance: 20, ascent: 2, averagePower: 450, averageHeartRate: 150))
    }

    @Test func theWholeActivity() {
        let detail = DetailPreparation.prepare(makeInput(stream))
        // Ascent over 100, 101, 103, 102, 104, 100: 101 is 1 m up, under the
        // threshold; 103 is 3 m above the low of 100, a climb of 3; 102 is a
        // 1 m dip, not enough to end it; 104 is a new high, +1; 100 is a 4 m
        // fall, a descent. 3 + 1 = 4.
        // Average power (100 + 200 + 400 + 500 + 600) / 5 = 360.
        // Average heart rate (120 + ... + 170) / 6 = 145.
        #expect(detail.rangeStats(0...5) == RangeStats(time: 6, distance: 50, ascent: 4, averagePower: 360, averageHeartRate: 145))
        // A range past either end is cut to the stream.
        #expect(detail.rangeStats(-4...40) == detail.rangeStats(0...5))
    }

    @Test func aRangeWithoutDistance() {
        let detail = DetailPreparation.prepare(makeInput(stream))
        // Second 3 alone has no distance.
        #expect(detail.rangeStats(3...3).distance == nil)
        #expect(detail.rangeStats(3...3).time == 1)
    }

    @Test func aRangeOutsideTheStreamIsEmpty() {
        let detail = DetailPreparation.prepare(makeInput(stream))
        #expect(detail.rangeStats(10...12) == RangeStats())
    }

    @Test func noAltitudeAndOffABike() {
        let walk = makeStream(count: 3, power: run(200, 3), heartRate: run(100, 3))
        let detail = DetailPreparation.prepare(makeInput(walk, sport: .walking))
        let stats = detail.rangeStats(0...2)
        #expect(stats.ascent == nil)       // no altitude: unavailable, not 0
        #expect(stats.averagePower == nil) // power is for cycling only
        #expect(stats.averageHeartRate == 100)
    }

    @Test func ascentUsesTheWalkingThreshold() {
        // On foot the threshold is 3 m: a 2 m rise does not count, a 3 m
        // rise does.
        let walk = makeStream(count: 3, altitude: [100, 102, 103])
        let detail = DetailPreparation.prepare(makeInput(walk, sport: .walking))
        #expect(detail.rangeStats(0...1).ascent == 0)
        #expect(detail.rangeStats(0...2).ascent == 3)
    }
}
