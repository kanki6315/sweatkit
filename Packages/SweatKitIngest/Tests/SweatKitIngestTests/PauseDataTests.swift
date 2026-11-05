import Foundation
import SweatKitIngest
import SweatKitModel
import Testing

/// The pause rows of the "Time" table in "Analysis metrics": complete pause
/// data, incomplete pause data and "treated as unpaused". Also stream rule 8:
/// paused spans stay in elapsed time.
@Suite struct PauseDataTests {
    /// The pause data of an activity stated to run `elapsed` seconds, with a
    /// heart-rate sample at each of `sampleSeconds`.
    private func pauses(
        elapsed: TimeInterval = 100,
        timerTime: TimeInterval? = nil,
        events: [TimerEvent],
        sampleSeconds: some Sequence<Int>
    ) throws -> PauseData {
        let activity = RecordedActivity(
            sport: .cycling,
            stated: StatedSummary(start: Synthetic.start, end: Synthetic.at(elapsed), timerTime: timerTime),
            timerEvents: events,
            stream: NativeStream(samples: sampleSeconds.map {
                NativeSample(timestamp: Synthetic.at(Double($0)), heartRate: 120)
            })
        )
        return try Synthetic.stream(activity).pauses
    }

    private func start(_ seconds: TimeInterval) -> TimerEvent { Synthetic.event(.start, seconds) }
    private func stop(_ seconds: TimeInterval) -> TimerEvent { Synthetic.event(.stop, seconds) }

    // MARK: Complete

    @Test func everyStopWithAMatchingStartIsComplete() throws {
        let events = [start(0), stop(20), start(30), stop(50), start(55)]
        // Stopped from 20 to 30 s and from 50 to 55 s.
        #expect(try pauses(events: events, sampleSeconds: 0..<100) == .known(paused: [20..<30, 50..<55]))
    }

    /// Stream rule 8: paused spans stay in elapsed time.
    @Test func pausedSpansStayInElapsedTime() throws {
        let activity = Synthetic.activity(
            elapsed: 100,
            events: [start(0), stop(20), start(30)],
            samples: [NativeSample(timestamp: Synthetic.start, heartRate: 120)]
        )
        let stream = try Synthetic.stream(activity)
        // Still 100 samples: the 10 paused seconds are on the grid.
        #expect(stream.count == 100)
        #expect(stream.pauses == .known(paused: [20..<30]))
    }

    @Test func recordingThatEndsOnAStopIsComplete() throws {
        // One pause from 40 to 50 s, then the final stop exactly on the
        // stated end. The last sample carries the same timestamp as that stop.
        let events = [start(0), stop(40), start(50), stop(100)]
        #expect(try pauses(events: events, sampleSeconds: 0...100) == .known(paused: [40..<50]))
    }

    /// Reading: "a final stop at the session end, with nothing recorded after
    /// it" is taken as any last stop with nothing stamped later than it. The
    /// time from that stop to the stated end is paused.
    @Test func finalStopBeforeTheStatedEndWithNothingAfterItIsComplete() throws {
        // Stop pressed at 95 s, saved at 100 s. The last sample is at 95 s,
        // the same instant as the stop, which is not after it.
        let events = [start(0), stop(95)]
        #expect(try pauses(events: events, sampleSeconds: 0...95) == .known(paused: [95..<100]))
    }

    /// Reading: a start event with no stop is pause data that shows no pauses.
    @Test func loneStartEventIsCompleteWithNoPauses() throws {
        // No stated timer time, so "treated as unpaused" cannot be the reason.
        #expect(try pauses(events: [start(0)], sampleSeconds: 0..<100) == .known(paused: []))
    }

    /// Reading: the timer is running at the activity start, with or without
    /// a start event there.
    @Test func firstEventCanBeAStop() throws {
        #expect(try pauses(events: [stop(20), start(30)], sampleSeconds: 0..<100) == .known(paused: [20..<30]))
    }

    /// Reading: a timer event belongs to the grid second that contains its
    /// timestamp, like a sample.
    @Test func eventsBelongToTheGridSecondThatContainsThem() throws {
        // 20.5 s is inside second 20 and 30.75 s inside second 30.
        let events = [start(0), stop(20.5), start(30.75)]
        #expect(try pauses(events: events, sampleSeconds: 0..<100) == .known(paused: [20..<30]))
    }

    @Test func stopAndStartInTheSameSecondLeaveNoSpan() throws {
        // Both inside second 20, so no whole second was paused.
        let events = [start(0), stop(20.25), start(20.75)]
        #expect(try pauses(events: events, sampleSeconds: 0..<100) == .known(paused: []))
    }

    /// A stop stamped after the stated end is not "inside the session". Zwift
    /// writes its final stop this way.
    @Test func stopAfterTheStatedEndIsIgnored() throws {
        let events = [start(0), stop(130)]
        #expect(try pauses(events: events, sampleSeconds: 0...100) == .known(paused: []))
    }

    /// Reading: events are read in time order, whatever order they arrive in.
    @Test func eventsAreReadInTimeOrder() throws {
        let events = [start(30), stop(20), start(0)]
        #expect(try pauses(events: events, sampleSeconds: 0..<100) == .known(paused: [20..<30]))
    }

    // MARK: Incomplete

    @Test func stopWithNoMatchingStartWhileSamplesContinueIsIncomplete() throws {
        // Stopped at 40 s and never started again, yet samples run to the
        // end. A later sensor sample does not prove the timer restarted.
        let events = [start(0), stop(40)]
        #expect(
            try pauses(timerTime: 80, events: events, sampleSeconds: 0..<100)
                == .unknown(statedTimerTime: 80)
        )
    }

    @Test func oneLaterSampleIsEnoughToMakeAStopUnmatched() throws {
        // The last sample is 1 s after the stop.
        let events = [start(0), stop(40)]
        #expect(
            try pauses(timerTime: 80, events: events, sampleSeconds: 0...41)
                == .unknown(statedTimerTime: 80)
        )
    }

    @Test func incompletePauseDataWithNoStatedTimerTimeCarriesNone() throws {
        let events = [start(0), stop(40)]
        #expect(try pauses(events: events, sampleSeconds: 0..<100) == .unknown(statedTimerTime: nil))
    }

    /// "...while samples or events continue after it." The second stop is an
    /// event after the first, which has no matching start.
    @Test func stopWithNoMatchingStartWhileEventsContinueIsIncomplete() throws {
        // No sample is later than the first stop.
        let events = [start(0), stop(40), stop(70)]
        #expect(
            try pauses(timerTime: 40, events: events, sampleSeconds: 0...40)
                == .unknown(statedTimerTime: 40)
        )
    }

    @Test func anUnmatchedStopMakesEarlierMatchedPausesUnknownToo() throws {
        // The pause from 20 to 30 s is matched, but the stop at 60 s is not,
        // and samples continue. Pause data is one state for the whole activity.
        let events = [start(0), stop(20), start(30), stop(60)]
        #expect(
            try pauses(timerTime: 50, events: events, sampleSeconds: 0..<100)
                == .unknown(statedTimerTime: 50)
        )
    }

    // MARK: No pause events

    /// Treated as unpaused: no pause events, and stated timer time within 1%
    /// of elapsed time.
    @Test(arguments: [991.0, 1000.0, 1009.0])
    func noEventsAndTimerTimeWithinOnePercentIsTreatedAsUnpaused(_ timerTime: TimeInterval) throws {
        // Elapsed 1,000 s, so 1% is 10 s. 991 and 1,009 are 9 s away.
        // A timer time longer than elapsed happens: the Zwift fixture has it.
        #expect(
            try pauses(elapsed: 1000, timerTime: timerTime, events: [], sampleSeconds: 0..<1000)
                == .known(paused: [])
        )
    }

    /// Reading: "within 1%" includes exactly 1%.
    @Test(arguments: [990.0, 1010.0])
    func timerTimeExactlyOnePercentFromElapsedIsWithin(_ timerTime: TimeInterval) throws {
        // Elapsed 1,000 s, and both are exactly 10 s away.
        #expect(
            try pauses(elapsed: 1000, timerTime: timerTime, events: [], sampleSeconds: 0..<1000)
                == .known(paused: [])
        )
    }

    @Test(arguments: [989.0, 1011.0, 600.0])
    func noEventsAndTimerTimeOutsideOnePercentIsIncomplete(_ timerTime: TimeInterval) throws {
        // Elapsed 1,000 s, so 1% is 10 s. 989 and 1,011 are 11 s away.
        #expect(
            try pauses(elapsed: 1000, timerTime: timerTime, events: [], sampleSeconds: 0..<1000)
                == .unknown(statedTimerTime: timerTime)
        )
    }

    @Test func noEventsAndNoStatedTimerTimeIsIncomplete() throws {
        #expect(try pauses(events: [], sampleSeconds: 0..<100) == .unknown(statedTimerTime: nil))
    }

    /// A long hole in the samples looks like a pause, but with no events the
    /// stated timer time decides, not the samples.
    @Test func holeInTheSamplesDoesNotStandInForPauseEvents() throws {
        // Samples stop for 400 s, and timer time is stated as 600 of 1,000 s.
        let seconds = Array(0..<300) + Array(700..<1000)
        #expect(
            try pauses(elapsed: 1000, timerTime: 600, events: [], sampleSeconds: seconds)
                == .unknown(statedTimerTime: 600)
        )
    }
}
