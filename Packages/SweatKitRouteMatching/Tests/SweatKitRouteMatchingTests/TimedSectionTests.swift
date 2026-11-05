import Foundation
import SweatKitModel
import SweatKitRouteMatching
import Testing

/// "The timed section runs from 25 m after the start of the reference line to
/// 25 m before its end. An effort's clock starts when it crosses the 25 m mark
/// and stops when it crosses the mark 25 m before the end. Each crossing time
/// is interpolated between the samples on either side of the mark. A first or
/// last mapped point that sits exactly on a mark supplies the time directly."
@Suite struct TimedSectionTests {
    // MARK: The section

    @Test func theSectionRunsFrom25MetresInTo25MetresFromTheEnd() throws {
        // 1000 m line: 25 to 975, 950 m long.
        let section = try #require(TimedSection(referenceLength: 1000))
        #expect(section.start == 25)
        #expect(section.end == 975)
        #expect(section.length == 950)
    }

    @Test func aLineTooShortToHoldASectionHasNone() {
        // 50 m: the marks would both be at 25 m. 40 m: they would cross.
        #expect(TimedSection(referenceLength: 50) == nil)
        #expect(TimedSection(referenceLength: 40) == nil)
        #expect(TimedSection(referenceLength: 0) == nil)
    }

    @Test func aLineJustLongEnoughHasAShortSection() throws {
        // 60 m line: 25 to 35.
        let section = try #require(TimedSection(referenceLength: 60))
        #expect(section.start == 25)
        #expect(section.end == 35)
        #expect(section.length == 10)
    }

    @Test func theMarksComeFromTheEndTolerance() throws {
        var rules = MatchingRules.standard
        rules.endTolerance = 10
        let section = try #require(TimedSection(referenceLength: 100, rules: rules))
        #expect(section.start == 10)
        #expect(section.end == 90)
    }

    @Test func aRouteTimeIsTheEndCrossingLessTheStartCrossing() {
        #expect(SectionTimes(clock: .elapsed, start: 103, end: 293).duration == 190)
    }

    // MARK: Time at a route distance

    @Test func aCrossingIsInterpolatedBetweenTheSamplesEitherSide() {
        // Samples at 10 m (100 s) and 40 m (106 s). The 25 m mark is half way
        // between them: 100 + (25 - 10) / (40 - 10) * 6 = 103 s.
        let effort = alignment([mapped(10, t: 100), mapped(40, t: 106)], referenceLength: 1000)
        #expect(effort.time(atRouteDistance: 25, clock: .elapsed) == 103)
    }

    @Test func interpolationIsInProportionToRouteDistance() throws {
        // Samples at 20 m (10 s) and 60 m (30 s). At 25 m, an eighth of the
        // way: 10 + (5 / 40) * 20 = 12.5 s.
        let effort = alignment([mapped(20, t: 10), mapped(60, t: 30)], referenceLength: 1000)
        let time = try #require(effort.time(atRouteDistance: 25, clock: .elapsed))
        #expect(close(time, 12.5, within: 1e-9))
    }

    @Test func aFirstPointExactlyOnTheMarkSuppliesTheTimeDirectly() {
        let effort = alignment([mapped(25, t: 7), mapped(60, t: 12)], referenceLength: 1000)
        #expect(effort.time(atRouteDistance: 25, clock: .elapsed) == 7)
    }

    @Test func aLastPointExactlyOnTheMarkSuppliesTheTimeDirectly() {
        let effort = alignment([mapped(900, t: 280), mapped(975, t: 300)], referenceLength: 1000)
        #expect(effort.time(atRouteDistance: 975, clock: .elapsed) == 300)
    }

    @Test func anySampleExactlyOnTheDistanceSuppliesItsTime() {
        let effort = alignment([mapped(0, t: 0), mapped(50, t: 5), mapped(100, t: 12)], referenceLength: 1000)
        #expect(effort.time(atRouteDistance: 50, clock: .elapsed) == 5)
    }

    @Test func aFirstPointBeyondTheDistanceHasNoTimeForIt() {
        // The effort began at 30 m. It never crossed 25 m.
        let effort = alignment([mapped(30, t: 0), mapped(60, t: 6)], referenceLength: 1000)
        #expect(effort.time(atRouteDistance: 25, clock: .elapsed) == nil)
    }

    @Test func aDistanceNeverReachedHasNoTime() {
        let effort = alignment([mapped(0, t: 0), mapped(900, t: 90)], referenceLength: 1000)
        #expect(effort.time(atRouteDistance: 975, clock: .elapsed) == nil)
        #expect(alignment([], referenceLength: 1000).time(atRouteDistance: 25, clock: .elapsed) == nil)
    }

    @Test func aStopOnTheDistanceCountsFromTheFirstArrival() {
        // The effort reaches 25 m at 5 s and stands there until 65 s.
        let effort = alignment(
            [mapped(0, t: 0), mapped(25, t: 5), mapped(25, t: 65), mapped(50, t: 70)],
            referenceLength: 1000
        )
        #expect(effort.time(atRouteDistance: 25, clock: .elapsed) == 5)
    }

    @Test func aStopBeforeTheDistanceIsOverByTheTimeItIsReached() {
        // The effort stands at 20 m from 4 s to 64 s, then reaches 40 m at
        // 68 s. The samples either side of 25 m are (20 m, 64 s) and
        // (40 m, 68 s): 64 + (5 / 20) * 4 = 65 s.
        let effort = alignment(
            [mapped(0, t: 0), mapped(20, t: 4), mapped(20, t: 64), mapped(40, t: 68)],
            referenceLength: 1000
        )
        #expect(effort.time(atRouteDistance: 25, clock: .elapsed) == 65)
    }

    @Test func eachClockIsInterpolatedFromItsOwnTimes() {
        // 100 m covered in 20 s elapsed, of which 10 s were moving.
        // At 25 m: 5 s elapsed, 2.5 s moving.
        let effort = alignment(
            [mapped(0, elapsed: 0, moving: 0), mapped(100, elapsed: 20, moving: 10)],
            referenceLength: 1000
        )
        #expect(effort.time(atRouteDistance: 25, clock: .elapsed) == 5)
        #expect(effort.time(atRouteDistance: 25, clock: .moving) == 2.5)
    }

    // MARK: Section times

    @Test func sectionTimesAreTheTwoInterpolatedCrossings() throws {
        // 1000 m line, marks at 25 m and 975 m.
        // Start: between (10 m, 100 s) and (40 m, 106 s): 103 s.
        // End: between (960 m, 290 s) and (990 m, 296 s):
        //   290 + (15 / 30) * 6 = 293 s.
        // Route time: 293 - 103 = 190 s.
        let effort = alignment(
            [mapped(10, t: 100), mapped(40, t: 106), mapped(960, t: 290), mapped(990, t: 296)],
            referenceLength: 1000
        )
        let times = try #require(effort.sectionTimes(clock: .elapsed).value)
        #expect(times.clock == .elapsed)
        #expect(times.start == 103)
        #expect(times.end == 293)
        #expect(times.duration == 190)
    }

    @Test func anEffortSittingExactlyOnBothMarksIsTimedFromItsOwnEnds() throws {
        // The latest start and earliest finish a full effort may have.
        let effort = alignment([mapped(25, t: 0), mapped(500, t: 60), mapped(975, t: 130)], referenceLength: 1000)
        let times = try #require(effort.sectionTimes(clock: .elapsed).value)
        #expect(times.start == 0)
        #expect(times.end == 130)
    }

    @Test func movingSectionTimesUseTheMovingClock() throws {
        // A 30 s stop at 500 m: elapsed 0, 50, 80, 130 s; moving 0, 50, 50,
        // 100 s. Constant 10 m/s otherwise, so the marks are crossed at
        // 2.5 s, and at 127.5 s elapsed or 97.5 s moving.
        let effort = alignment(
            [
                mapped(0, elapsed: 0, moving: 0),
                mapped(500, elapsed: 50, moving: 50),
                mapped(500, elapsed: 80, moving: 50),
                mapped(1000, elapsed: 130, moving: 100),
            ],
            referenceLength: 1000
        )
        let elapsed = try #require(effort.sectionTimes(clock: .elapsed).value)
        #expect(close(elapsed.start, 2.5, within: 1e-9))
        #expect(close(elapsed.end, 127.5, within: 1e-9))
        #expect(close(elapsed.duration, 125, within: 1e-9))
        let moving = try #require(effort.sectionTimes(clock: .moving).value)
        #expect(moving.clock == .moving)
        #expect(close(moving.start, 2.5, within: 1e-9))
        #expect(close(moving.end, 97.5, within: 1e-9))
        #expect(close(moving.duration, 95, within: 1e-9))
    }

    @Test func anEffortThatStartsPastTheMarkHasNoRouteTime() {
        let late = alignment([mapped(30, t: 0), mapped(1000, t: 100)], referenceLength: 1000)
        #expect(late.sectionTimes(clock: .elapsed).reason == .timedSectionNotCovered)
        #expect(late.sectionTimes(clock: .elapsed).value == nil)
    }

    @Test func anEffortThatStopsShortOfTheMarkHasNoRouteTime() {
        let early = alignment([mapped(0, t: 0), mapped(970, t: 100)], referenceLength: 1000)
        #expect(early.sectionTimes(clock: .elapsed).reason == .timedSectionNotCovered)
    }

    @Test func aLineWithNoTimedSectionGivesNoRouteTime() {
        let short = alignment([mapped(0, t: 0), mapped(40, t: 8)], referenceLength: 40)
        #expect(short.sectionTimes(clock: .elapsed).reason == .referenceLineTooShort)
    }

    /// "The effort is left out of moving-time rankings and statistics, and is
    /// listed with its elapsed time."
    @Test func withoutReliablePausePositionsOnlyElapsedTimeIsAvailable() throws {
        let effort = alignment(
            [mapped(0, elapsed: 0, moving: 0), mapped(1000, elapsed: 100, moving: 80)],
            referenceLength: 1000,
            pausePositionsAreReliable: false
        )
        #expect(effort.sectionTimes(clock: .moving).reason == .movingClockUnavailable)
        // 10 m/s: marks crossed at 2.5 s and 97.5 s.
        let elapsed = try #require(effort.sectionTimes(clock: .elapsed).value)
        #expect(close(elapsed.duration, 95, within: 1e-9))
    }

    // MARK: From a track

    /// "A start 20 m late joins and is timed over the timed section."
    @Test func aStart20MetresLateIsTimedOverTheTimedSection() throws {
        // A 2000 m route: marks at 25 m and 1975 m, 1950 m apart.
        // The late effort starts at 20 m and rides at 5 m/s, with a sample
        // every 20 m: it is at east x at (x - 20) / 5 seconds.
        //   Start mark: between (20 m, 0 s) and (40 m, 4 s): 0 + (5 / 20) * 4 = 1 s.
        //   End mark: between (1960 m, 388 s) and (1980 m, 392 s):
        //     388 + (15 / 20) * 4 = 391 s.
        //   Route time 390 s, which is 1950 m at 5 m/s.
        let line = try #require(referenceLine(Course.eastRoad(to: 2000)))
        let late = RouteAlignment.align(track(Course.eastRoad(from: 20, to: 2000), speed: 5), to: line)
        let times = try #require(late.sectionTimes(clock: .elapsed).value)
        #expect(close(times.start, 1, within: 0.001))
        #expect(close(times.end, 391, within: 0.001))
        #expect(close(times.duration, 390, within: 0.001))

        // The route's own first effort, from 0 m at 5 m/s, crosses the marks
        // at 25 / 5 = 5 s and 1975 / 5 = 395 s: the same 390 s. The late start
        // costs nothing.
        let full = RouteAlignment.align(track(Course.eastRoad(to: 2000), speed: 5), to: line)
        let fullTimes = try #require(full.sectionTimes(clock: .elapsed).value)
        #expect(close(fullTimes.start, 5, within: 0.001))
        #expect(close(fullTimes.duration, 390, within: 0.001))
    }

    @Test func aStart30MetresLateHasNoRouteTime() throws {
        let line = try #require(referenceLine(Course.eastRoad(to: 2000)))
        let late = RouteAlignment.align(track(Course.eastRoad(from: 30, to: 2000, step: 10)), to: line)
        #expect(late.sectionTimes(clock: .elapsed).reason == .timedSectionNotCovered)
    }
}
