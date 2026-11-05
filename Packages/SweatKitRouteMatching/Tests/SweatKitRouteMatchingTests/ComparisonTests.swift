import Foundation
import SweatKitModel
import SweatKitRouteMatching
import Testing

/// "Comparing two efforts". Efforts here are mappings written by hand on a
/// 250 m line, whose timed section runs from 25 m to 225 m: 200 m, so the
/// 10 m grid has 21 points at 25, 35 ... 225 m.
@Suite struct ComparisonTests {
    /// A steady 10 m/s from end to end: at `d` metres after `d / 10` seconds.
    /// Start mark at 2.5 s, end mark at 22.5 s, route time 20 s.
    private let steady = alignment(
        [mapped(0, t: 0), mapped(50, t: 5), mapped(100, t: 10), mapped(150, t: 15), mapped(200, t: 20), mapped(250, t: 25)],
        referenceLength: 250
    )

    /// 5 m/s for the first 100 m, then 10 m/s: at `d` metres after `d / 5`
    /// seconds up to 100 m, and `20 + (d - 100) / 10` beyond. Start mark at
    /// 5 s, end mark at 32.5 s, route time 27.5 s.
    private let slowStart = alignment(
        [mapped(0, t: 0), mapped(100, t: 20), mapped(250, t: 35)],
        referenceLength: 250
    )

    /// A steady 10 m/s with a 30 s stop at 100 m: elapsed 0, 10, 40, 55 s and
    /// moving 0, 10, 10, 25 s.
    private let stopped = alignment(
        [
            mapped(0, elapsed: 0, moving: 0),
            mapped(100, elapsed: 10, moving: 10),
            mapped(100, elapsed: 40, moving: 10),
            mapped(250, elapsed: 55, moving: 25),
        ],
        referenceLength: 250
    )

    /// A steady 10 m/s seen through two samples.
    private let nonStop = alignment([mapped(0, t: 0), mapped(250, t: 25)], referenceLength: 250)

    private func compare(
        _ subject: Alignment,
        _ baseline: Alignment,
        clock: ComparisonClock = .moving
    ) throws -> EffortComparison {
        try #require(RouteComparison.compare(subject, against: baseline, clock: clock).value)
    }

    // MARK: The clock

    /// "The clock is moving time by default, with elapsed time as an option
    /// ... If either effort lacks reliable pause positions, elapsed time is
    /// used for both and the moving-time option is disabled."
    @Test(arguments: [
        (ComparisonClock.moving, true, true, ComparisonClock.moving),
        (.moving, false, true, .elapsed),
        (.moving, true, false, .elapsed),
        (.moving, false, false, .elapsed),
        (.elapsed, true, true, .elapsed),
        (.elapsed, false, true, .elapsed),
        (.elapsed, true, false, .elapsed),
    ])
    func theClockIsTheRequestedOneUnlessEitherEffortLacksPausePositions(
        requested: ComparisonClock,
        subjectReliable: Bool,
        baselineReliable: Bool,
        expected: ComparisonClock
    ) {
        let clock = RouteComparison.clock(
            requested: requested,
            subjectPausePositionsAreReliable: subjectReliable,
            baselinePausePositionsAreReliable: baselineReliable
        )
        #expect(clock == expected)
    }

    @Test func movingTimeIsTheDefaultClock() throws {
        let comparison = try #require(RouteComparison.compare(steady, against: slowStart).value)
        #expect(comparison.clock == .moving)
        #expect(comparison.movingTimeIsAvailable)
        #expect(comparison.subjectTimes.clock == .moving)
        #expect(comparison.baselineTimes.clock == .moving)
    }

    @Test func elapsedTimeIsAnOption() throws {
        let comparison = try compare(steady, slowStart, clock: .elapsed)
        #expect(comparison.clock == .elapsed)
        #expect(comparison.movingTimeIsAvailable)
        #expect(comparison.subjectTimes.clock == .elapsed)
    }

    // MARK: The 10 m grid

    @Test func theGridRunsFromTheStartMarkToTheEndMarkEvery10Metres() throws {
        let comparison = try compare(steady, slowStart)
        #expect(comparison.section == TimedSection(start: 25, end: 225))
        #expect(comparison.grid.count == 21)
        #expect(comparison.grid.map(\.routeDistance) == stride(from: 25.0, through: 225, by: 10).map { $0 })
    }

    @Test func theEndMarkClosesTheGridWhenTheLastStepFallsShort() throws {
        // A 255 m line: section 25 to 230, 205 m. Steps reach 225 m, and the
        // end mark at 230 m is added: 22 points.
        // Subject at 10 m/s, baseline at 5 m/s. At the end mark, 205 m into
        // the section: 20.5 s against 41 s, gap -20.5 s.
        let fast = alignment([mapped(0, t: 0), mapped(255, t: 25.5)], referenceLength: 255)
        let slow = alignment([mapped(0, t: 0), mapped(255, t: 51)], referenceLength: 255)
        let comparison = try compare(fast, slow)
        #expect(comparison.grid.count == 22)
        #expect(comparison.grid[20].routeDistance == 225)
        #expect(comparison.grid[21].routeDistance == 230)
        #expect(close(comparison.grid[21].gap, -20.5, within: 1e-9))
        #expect(close(comparison.subjectTimes.duration, 20.5, within: 1e-9))
        #expect(close(comparison.baselineTimes.duration, 41, within: 1e-9))
    }

    // MARK: The time gap

    /// "The gap at each grid point is the difference in time since the start
    /// of the timed section."
    @Test func theGapIsWorkedOutAtEveryGridPoint() throws {
        // Subject `steady`, baseline `slowStart`. Time since the start mark
        // at `d` metres:
        //   subject:  (d - 25) / 10
        //   baseline: (d - 25) / 5 up to 100 m, where it reads 15 s;
        //             15 + (d - 100) / 10 beyond.
        // Gap, subject minus baseline:
        //   up to 100 m: (d - 25) / 10 - (d - 25) / 5 = -(d - 25) / 10,
        //     so 0, -1, -2 ... -7 s at 25, 35 ... 95 m.
        //   beyond 100 m: (d - 25) / 10 - 15 - (d - 100) / 10 = -7.5 s,
        //     at every point from 105 m to 225 m.
        let comparison = try compare(steady, slowStart)
        let expected: [Double] = [0, -1, -2, -3, -4, -5, -6, -7] + Array(repeating: -7.5, count: 13)
        #expect(comparison.grid.count == expected.count)
        for (point, gap) in zip(comparison.grid, expected) {
            #expect(close(point.gap, gap, within: 1e-9), "gap at \(point.routeDistance) m")
        }
    }

    @Test func eachGridPointCarriesBothClocks() throws {
        let comparison = try compare(steady, slowStart)
        // 35 m: subject 1 s, baseline 2 s.
        #expect(close(comparison.grid[1].subjectClock, 1, within: 1e-9))
        #expect(close(comparison.grid[1].baselineClock, 2, within: 1e-9))
        // 105 m: subject 8 s, baseline 15 + 0.5 = 15.5 s.
        #expect(close(comparison.grid[8].subjectClock, 8, within: 1e-9))
        #expect(close(comparison.grid[8].baselineClock, 15.5, within: 1e-9))
        // 225 m: subject 20 s, baseline 15 + 12.5 = 27.5 s.
        #expect(close(comparison.grid[20].subjectClock, 20, within: 1e-9))
        #expect(close(comparison.grid[20].baselineClock, 27.5, within: 1e-9))
    }

    @Test func bothClocksReadZeroAtTheStartMark() throws {
        let comparison = try compare(steady, slowStart)
        #expect(close(comparison.grid[0].subjectClock, 0, within: 1e-9))
        #expect(close(comparison.grid[0].baselineClock, 0, within: 1e-9))
        #expect(close(comparison.grid[0].gap, 0, within: 1e-9))
    }

    @Test func theLastGapIsTheDifferenceBetweenTheTwoRouteTimes() throws {
        let comparison = try compare(steady, slowStart)
        // 2.5 s to 22.5 s against 5 s to 32.5 s: 20 s against 27.5 s.
        #expect(close(comparison.subjectTimes.start, 2.5, within: 1e-9))
        #expect(close(comparison.subjectTimes.end, 22.5, within: 1e-9))
        #expect(close(comparison.baselineTimes.start, 5, within: 1e-9))
        #expect(close(comparison.baselineTimes.end, 32.5, within: 1e-9))
        let last = try #require(comparison.grid.last)
        #expect(close(last.gap, comparison.subjectTimes.duration - comparison.baselineTimes.duration, within: 1e-9))
        #expect(close(last.gap, -7.5, within: 1e-9))
    }

    @Test func aSlowerSubjectHasAPositiveGap() throws {
        // The same two efforts the other way round: the subject is behind by
        // 7.5 s at the end.
        let comparison = try compare(slowStart, steady)
        let last = try #require(comparison.grid.last)
        #expect(close(last.gap, 7.5, within: 1e-9))
        #expect(close(comparison.grid[3].gap, 3, within: 1e-9))
    }

    @Test func anEffortAgainstItselfHasNoGap() throws {
        let comparison = try compare(slowStart, slowStart)
        #expect(comparison.grid.allSatisfy { abs($0.gap) < 1e-9 })
    }

    // MARK: Stops

    /// "Aligning the charts by distance means a stop at a traffic light does
    /// not shift everything after it."
    @Test func onElapsedTimeAStopIsAStepInTheGapNotAShift() throws {
        // `stopped` against `nonStop`, both 10 m/s when moving. Up to the
        // stop at 100 m they are level: gap 0 at 25 ... 95 m. The stop costs
        // 30 s of elapsed time, so from 105 m on the gap is 30 s. At 105 m:
        //   subject 40 + 0.5 = 40.5 s, less 2.5 s at the start mark = 38 s;
        //   baseline 10.5 - 2.5 = 8 s.
        let comparison = try compare(stopped, nonStop, clock: .elapsed)
        let expected = Array(repeating: 0.0, count: 8) + Array(repeating: 30.0, count: 13)
        for (point, gap) in zip(comparison.grid, expected) {
            #expect(close(point.gap, gap, within: 1e-9), "gap at \(point.routeDistance) m")
        }
        #expect(close(comparison.grid[8].subjectClock, 38, within: 1e-9))
        #expect(close(comparison.subjectTimes.duration, 50, within: 1e-9))
        #expect(close(comparison.baselineTimes.duration, 20, within: 1e-9))
    }

    @Test func onMovingTimeTheStopDisappears() throws {
        // Moving time stands still through the stop, so the two efforts are
        // level all the way.
        let comparison = try compare(stopped, nonStop, clock: .moving)
        #expect(comparison.clock == .moving)
        #expect(comparison.grid.allSatisfy { abs($0.gap) < 1e-9 })
        #expect(close(comparison.subjectTimes.duration, 20, within: 1e-9))
    }

    @Test func eachGridPointCarriesTheElapsedTimeForReadingTheCharts() throws {
        // Whatever the clock, the paired charts read each activity's stream
        // at its own elapsed second. At 105 m the stopped effort is at
        // 40.5 s elapsed, though its moving clock reads 10.5 s there.
        let comparison = try compare(stopped, nonStop, clock: .moving)
        #expect(close(comparison.grid[8].subjectElapsedTime, 40.5, within: 1e-9))
        #expect(close(comparison.grid[8].baselineElapsedTime, 10.5, within: 1e-9))
        // At the start mark both are at 2.5 s elapsed.
        #expect(close(comparison.grid[0].subjectElapsedTime, 2.5, within: 1e-9))
        #expect(close(comparison.grid[0].baselineElapsedTime, 2.5, within: 1e-9))
    }

    // MARK: Unreliable pause positions

    @Test func withoutReliablePausePositionsOnTheBaselineBothEffortsUseElapsedTime() throws {
        // The baseline's moving times are meaningless and must not be read.
        let unreliable = alignment(
            [mapped(0, elapsed: 0, moving: 0), mapped(250, elapsed: 25, moving: 0)],
            referenceLength: 250,
            pausePositionsAreReliable: false
        )
        let comparison = try compare(stopped, unreliable, clock: .moving)
        #expect(comparison.clock == .elapsed)
        #expect(!comparison.movingTimeIsAvailable)
        #expect(comparison.subjectTimes.clock == .elapsed)
        #expect(comparison.baselineTimes.clock == .elapsed)
        // Elapsed gap, as in the stop test: 30 s at the end. The subject's
        // own moving time would have made it 0.
        let last = try #require(comparison.grid.last)
        #expect(close(last.gap, 30, within: 1e-9))
    }

    @Test func withoutReliablePausePositionsOnTheSubjectBothEffortsUseElapsedTime() throws {
        let unreliable = alignment(
            [mapped(0, elapsed: 0, moving: 0), mapped(250, elapsed: 25, moving: 0)],
            referenceLength: 250,
            pausePositionsAreReliable: false
        )
        let comparison = try compare(unreliable, stopped, clock: .moving)
        #expect(comparison.clock == .elapsed)
        #expect(!comparison.movingTimeIsAvailable)
        // The subject took 20 s and the stopped baseline 50 s of elapsed time.
        let last = try #require(comparison.grid.last)
        #expect(close(last.gap, -30, within: 1e-9))
    }

    // MARK: Unavailable

    @Test func anEffortThatDoesNotCoverTheTimedSectionCannotBeCompared() {
        // Starts at 40 m, past the 25 m mark.
        let late = alignment([mapped(40, t: 0), mapped(250, t: 21)], referenceLength: 250)
        #expect(RouteComparison.compare(late, against: steady).reason == .timedSectionNotCovered)
        #expect(RouteComparison.compare(steady, against: late).reason == .timedSectionNotCovered)
        #expect(RouteComparison.compare(steady, against: late).value == nil)
    }

    @Test func effortsOnALineWithNoTimedSectionCannotBeCompared() {
        let short = alignment([mapped(0, t: 0), mapped(40, t: 4)], referenceLength: 40)
        #expect(RouteComparison.compare(short, against: short).reason == .referenceLineTooShort)
    }

    // MARK: The ghost marker

    /// "Both markers run on one clock, the time since each effort entered the
    /// timed section. The distance between them on the map is the real gap at
    /// that moment."
    @Test func bothMarkersStartOnTheStartMarkAtZero() throws {
        let frame = try compare(steady, slowStart).ghost(at: 0)
        #expect(close(frame.subjectRouteDistance, 25, within: 1e-9))
        #expect(close(frame.baselineRouteDistance, 25, within: 1e-9))
        #expect(close(frame.separation, 0, within: 1e-9))
    }

    @Test func eachMarkerIsWhereItsEffortWasAtThatMomentOfItsOwnClock() throws {
        // 10 s after each entered the section:
        //   subject, 10 m/s: 25 + 100 = 125 m.
        //   baseline, 5 m/s for its first 15 s: 25 + 50 = 75 m.
        // The ghost is 50 m behind.
        let frame = try compare(steady, slowStart).ghost(at: 10)
        #expect(close(frame.subjectRouteDistance, 125, within: 1e-9))
        #expect(close(frame.baselineRouteDistance, 75, within: 1e-9))
        #expect(close(frame.separation, -50, within: 1e-9))
    }

    @Test func theSeparationIsPositiveWhenTheGhostIsAhead() throws {
        // The other way round, the ghost is the steady effort: 50 m ahead.
        let frame = try compare(slowStart, steady).ghost(at: 10)
        #expect(close(frame.subjectRouteDistance, 75, within: 1e-9))
        #expect(close(frame.baselineRouteDistance, 125, within: 1e-9))
        #expect(close(frame.separation, 50, within: 1e-9))
    }

    @Test func aMarkerWaitsAtTheEndMarkOnceItsEffortHasFinished() throws {
        let comparison = try compare(steady, slowStart)
        // 20 s: the subject reaches the end mark. The baseline reached 100 m
        // at 15 s and has done 5 s more at 10 m/s: 150 m.
        let atSubjectFinish = comparison.ghost(at: 20)
        #expect(close(atSubjectFinish.subjectRouteDistance, 225, within: 1e-9))
        #expect(close(atSubjectFinish.baselineRouteDistance, 150, within: 1e-9))
        #expect(close(atSubjectFinish.separation, -75, within: 1e-9))
        // 25 s: the subject waits at 225 m. The baseline is at
        // 100 + 10 * 10 = 200 m.
        let later = comparison.ghost(at: 25)
        #expect(close(later.subjectRouteDistance, 225, within: 1e-9))
        #expect(close(later.baselineRouteDistance, 200, within: 1e-9))
        #expect(close(later.separation, -25, within: 1e-9))
        // 27.5 s and after: both at the end mark.
        for clockTime in [27.5, 40.0] {
            let done = comparison.ghost(at: clockTime)
            #expect(close(done.subjectRouteDistance, 225, within: 1e-9))
            #expect(close(done.baselineRouteDistance, 225, within: 1e-9))
            #expect(close(done.separation, 0, within: 1e-9))
        }
    }

    @Test func beforeZeroBothMarkersWaitOnTheStartMark() throws {
        let frame = try compare(steady, slowStart).ghost(at: -5)
        #expect(close(frame.subjectRouteDistance, 25, within: 1e-9))
        #expect(close(frame.baselineRouteDistance, 25, within: 1e-9))
    }

    @Test func onElapsedTimeAStoppedMarkerStandsStill() throws {
        // `stopped` enters at 2.5 s, reaches 100 m at 10 s (clock 7.5 s) and
        // stands there until 40 s (clock 37.5 s). `nonStop` finishes its 200 m
        // in 20 s.
        let comparison = try compare(stopped, nonStop, clock: .elapsed)
        // Clock 5 s: both 50 m into the section, at 75 m.
        let before = comparison.ghost(at: 5)
        #expect(close(before.subjectRouteDistance, 75, within: 1e-9))
        #expect(close(before.separation, 0, within: 1e-9))
        // Clock 20 s: the subject is standing at 100 m; the ghost has just
        // finished at 225 m, 125 m ahead.
        let during = comparison.ghost(at: 20)
        #expect(close(during.subjectRouteDistance, 100, within: 1e-9))
        #expect(close(during.baselineRouteDistance, 225, within: 1e-9))
        #expect(close(during.separation, 125, within: 1e-9))
        // Clock 38.5 s: 1 s after setting off again, at 110 m.
        let after = comparison.ghost(at: 38.5)
        #expect(close(after.subjectRouteDistance, 110, within: 1e-9))
    }

    /// "The charts, the gap and the ghost always use the same choice."
    @Test func theGhostRunsOnTheComparisonsClock() throws {
        // On moving time the stop takes no time: at clock 10 s both markers
        // are 100 m into the section, at 125 m.
        let frame = try compare(stopped, nonStop, clock: .moving).ghost(at: 10)
        #expect(close(frame.subjectRouteDistance, 125, within: 1e-9))
        #expect(close(frame.baselineRouteDistance, 125, within: 1e-9))
        #expect(close(frame.separation, 0, within: 1e-9))
    }

    // MARK: From tracks

    @Test func twoRidesOfOneRoadAreComparedEndToEnd() throws {
        // A 255 m road, ridden at 10 m/s and at 5 m/s with a sample every
        // 51 m. Section 25 to 230 m, 205 m: 20.5 s against 41 s. The grid is
        // 25, 35 ... 225 m and the end mark at 230 m: 22 points.
        //   At 125 m, 100 m in: 10 s against 20 s, gap -10 s.
        //   At 230 m: 20.5 s against 41 s, gap -20.5 s.
        // Ghost at clock 10 s: the subject is 100 m in at 125 m and the ghost
        // 50 m in at 75 m, 50 m behind.
        let points = Course.eastRoad(to: 255, step: 51)
        let line = try #require(referenceLine(points))
        let fast = RouteAlignment.align(track(points, speed: 10), to: line)
        let slow = RouteAlignment.align(track(points, speed: 5), to: line)
        let comparison = try compare(fast, slow)
        #expect(comparison.grid.count == 22)
        #expect(close(comparison.grid[10].routeDistance, 125, within: 0.001))
        #expect(close(comparison.grid[10].gap, -10, within: 0.001))
        #expect(close(comparison.grid[21].routeDistance, 230, within: 0.001))
        #expect(close(comparison.grid[21].gap, -20.5, within: 0.001))
        #expect(close(comparison.subjectTimes.duration, 20.5, within: 0.001))
        #expect(close(comparison.baselineTimes.duration, 41, within: 0.001))
        let frame = comparison.ghost(at: 10)
        #expect(close(frame.subjectRouteDistance, 125, within: 0.01))
        #expect(close(frame.baselineRouteDistance, 75, within: 0.01))
        #expect(close(frame.separation, -50, within: 0.01))
    }
}
