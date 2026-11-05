import Foundation
import SweatKitIngest
import SweatKitModel
import Testing

/// Small hand-made activities for the stream-rule tests. Every time is given
/// in seconds after `start`, and only whole seconds and quarters are used, so
/// each one is exact in a `Date`.
enum Synthetic {
    /// A whole second, so a sample at `at(3)` sits exactly on grid second 3.
    static let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    static func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    /// An activity stated to run for `elapsed` seconds from `start`.
    ///
    /// With no timer events and a stated timer time equal to elapsed time it
    /// is "treated as unpaused" under the spec's Time table, so nothing in
    /// the stream is affected by pauses unless a test passes events.
    static func activity(
        elapsed: TimeInterval,
        events: [TimerEvent] = [],
        samples: [NativeSample]
    ) -> RecordedActivity {
        RecordedActivity(
            sport: .cycling,
            stated: StatedSummary(start: start, end: at(elapsed), timerTime: elapsed),
            timerEvents: events,
            stream: NativeStream(samples: samples)
        )
    }

    static func event(_ kind: TimerEvent.Kind, _ seconds: TimeInterval) -> TimerEvent {
        TimerEvent(kind: kind, timestamp: at(seconds))
    }

    /// The stream of `activity`, which must have one.
    static func stream(
        _ activity: RecordedActivity,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> AnalysisStream {
        try #require(StreamNormaliser.analysisStream(from: activity), sourceLocation: sourceLocation)
    }
}

let measured = SampleQuality.measured
let interpolated = SampleQuality.interpolated
let missing = SampleQuality.missing

/// Checks a series second by second. Nil is a missing second. Filled values
/// are compared within `tolerance`, because a straight line can be computed
/// in more than one order.
func expectValues(
    _ series: Series,
    _ expected: [Double?],
    tolerance: Double = 1e-9,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(series.count == expected.count, sourceLocation: sourceLocation)
    for (second, want) in expected.enumerated() where second < series.count {
        switch (series[second], want) {
        case (nil, nil):
            continue
        case let (got?, want?):
            #expect(
                abs(got - want) <= tolerance,
                "second \(second) is \(got), expected \(want)",
                sourceLocation: sourceLocation
            )
        case let (got, want):
            Issue.record(
                "second \(second) is \(String(describing: got)), expected \(String(describing: want))",
                sourceLocation: sourceLocation
            )
        }
    }
}

/// Whether a second holds `expected`, within `tolerance`. A missing second
/// never does.
func isClose(_ value: Double?, _ expected: Double, tolerance: Double = 1e-9) -> Bool {
    guard let value else { return false }
    return abs(value - expected) <= tolerance
}

extension Series {
    /// The seconds that are not missing.
    var presentSeconds: [Int] {
        quality.indices.filter { quality[$0] != .missing }
    }
}
