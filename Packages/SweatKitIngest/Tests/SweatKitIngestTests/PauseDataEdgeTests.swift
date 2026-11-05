import Foundation
import SweatKitIngest
import SweatKitModel
import Testing

/// Pause cases the first round of tests left open: events that repeat, events
/// outside the stated times, and elapsed time that is not a whole number or
/// comes from the samples.
///
/// Each expected value is worked out in the comment beside it, before the
/// implementation was run, from the "Time" table of "Analysis metrics" or
/// from the reading written in `StreamNormaliser`'s doc comment.
@Suite struct PauseDataEdgeTests {
    /// The pause data of an activity stated to run 100 s, with a heart-rate
    /// sample at each of `sampleSeconds`.
    private func pauses(
        timerTime: TimeInterval? = nil,
        events: [TimerEvent],
        sampleSeconds: some Sequence<Int>
    ) throws -> PauseData {
        let activity = RecordedActivity(
            sport: .cycling,
            stated: StatedSummary(start: Synthetic.start, end: Synthetic.at(100), timerTime: timerTime),
            timerEvents: events,
            stream: NativeStream(samples: sampleSeconds.map {
                NativeSample(timestamp: Synthetic.at(Double($0)), heartRate: 120)
            })
        )
        return try Synthetic.stream(activity).pauses
    }

    private func start(_ seconds: TimeInterval) -> TimerEvent { Synthetic.event(.start, seconds) }
    private func stop(_ seconds: TimeInterval) -> TimerEvent { Synthetic.event(.stop, seconds) }

    // MARK: Repeated events

    /// "Every stop inside the session has a matching start." Both stops are
    /// followed by the start at 30 s, and the timer was already stopped when
    /// the second one came.
    @Test func secondStopBeforeTheStartChangesNothing() throws {
        let events = [start(0), stop(20), stop(25), start(30)]
        // Stopped at 20 s, running again at 30 s.
        #expect(try pauses(events: events, sampleSeconds: 0..<100) == .known(paused: [20..<30]))
    }

    @Test func startWhileTheTimerRunsChangesNothing() throws {
        let events = [start(0), start(10), stop(20), start(30)]
        // The start at 10 s finds the timer running. One pause, 20 to 30 s.
        #expect(try pauses(events: events, sampleSeconds: 0..<100) == .known(paused: [20..<30]))
    }

    // MARK: Events outside the stated times

    /// The stop at 90 s is inside the session and has its matching start, so
    /// pause data is complete. Elapsed time ends at 100 s, so the paused span
    /// ends there too.
    @Test func pauseThatRunsPastTheStatedEndStopsAtTheEndOfTheGrid() throws {
        let events = [start(0), stop(90), start(120)]
        #expect(try pauses(events: events, sampleSeconds: 0..<90) == .known(paused: [90..<100]))
    }

    /// Reading: spans are clipped to the grid at the start as well.
    @Test func pauseThatBeginsBeforeTheStatedStartBeginsAtSecondZero() throws {
        // Stopped 5 s before the stated start, running again at 3 s.
        let events = [stop(-5), start(3)]
        #expect(try pauses(events: events, sampleSeconds: 3..<100) == .known(paused: [0..<3]))
    }

    /// Reading: "nothing recorded after it" counts every sample, wherever it
    /// is stamped, so one after the stated end still follows the stop.
    @Test func sampleAfterTheStatedEndStillFollowsAnUnmatchedStop() throws {
        // Stop at 95 s with no matching start. Samples run to 95 s, and one
        // more is stamped at 130 s, after the stated end at 100 s.
        let events = [start(0), stop(95)]
        #expect(
            try pauses(timerTime: 95, events: events, sampleSeconds: Array(0...95) + [130])
                == .unknown(statedTimerTime: 95)
        )
    }

    /// Reading: a stop after the stated end is ignored altogether, so it is
    /// not an event that continues after an earlier stop.
    @Test func stopAfterTheStatedEndDoesNotFollowAnUnmatchedStop() throws {
        // Stop at 95 s, and a second stop at 130 s, outside the session.
        // Nothing else is later than the first, so it is the normal end of
        // the recording, and 95 to 100 s is paused.
        let events = [start(0), stop(95), stop(130)]
        #expect(try pauses(events: events, sampleSeconds: 0...95) == .known(paused: [95..<100]))
    }

    /// Pause events are there, so "pause events are absent" does not apply,
    /// and no stop is inside the session, so every one that is has its
    /// matching start. Complete, with no pauses.
    @Test func loneStopAfterTheStatedEndIsCompleteWithNoPauses() throws {
        // No stated timer time, so "treated as unpaused" cannot be the reason.
        #expect(try pauses(events: [stop(130)], sampleSeconds: 0..<100) == .known(paused: []))
    }

    // MARK: Elapsed time behind "within 1%"

    /// "Elapsed time: the activity's own start and end." The 1% is of that,
    /// not of the grid's whole number of seconds.
    @Test func onePercentIsMeasuredAgainstUnroundedElapsedTime() throws {
        // Elapsed 99.5 s, stated timer time 100.5 s: 1.0 s apart.
        // 1% of 99.5 s is 0.995 s, so 1.0 s is outside it.
        // Against the 100 grid seconds it would be 0.5 s apart and inside.
        let activity = RecordedActivity(
            sport: .cycling,
            stated: StatedSummary(start: Synthetic.start, end: Synthetic.at(99.5), timerTime: 100.5),
            stream: NativeStream(samples: [NativeSample(timestamp: Synthetic.start, heartRate: 120)])
        )
        let stream = try Synthetic.stream(activity)
        #expect(stream.count == 100)
        #expect(stream.pauses == .unknown(statedTimerTime: 100.5))
    }

    /// "The first and last samples are the fallback": elapsed time from the
    /// samples is what the stated timer time is held against.
    @Test(arguments: zip([995.0, 600.0], [PauseData.known(paused: []), .unknown(statedTimerTime: 600)]))
    func onePercentUsesElapsedTimeFromTheSamplesWhenNoneIsStated(
        _ timerTime: TimeInterval,
        _ expected: PauseData
    ) throws {
        // Nothing stated but the timer time. Samples at 0 to 1,000 s, so
        // elapsed time is 1,000 s and 1% is 10 s. 995 is 5 s away, inside.
        // 600 is 400 s away, outside.
        let activity = RecordedActivity(
            sport: .cycling,
            stated: StatedSummary(timerTime: timerTime),
            stream: NativeStream(samples: (0...1000).map {
                NativeSample(timestamp: Synthetic.at(Double($0)), heartRate: 120)
            })
        )
        let stream = try Synthetic.stream(activity)
        #expect(stream.count == 1000)
        #expect(stream.pauses == expected)
    }
}
