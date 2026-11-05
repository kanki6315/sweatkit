import Foundation
import SweatKitModel

extension StreamAnalysis {
    /// The spec's "Time" table for an activity with a stream.
    func timeMetrics() -> TimeMetrics {
        let elapsed = Metric<TimeInterval>.available(TimeInterval(count))
        guard let timer else {
            return TimeMetrics(
                elapsed: elapsed,
                timer: statedTimerTime.map(Metric.available) ?? .unavailable(.notStated),
                timerIsSummaryOnly: statedTimerTime != nil,
                moving: .unavailable(.pausePositionsUnknown)
            )
        }
        return TimeMetrics(
            elapsed: elapsed,
            timer: .available(TimeInterval(timer.timerSeconds)),
            timerIsSummaryOnly: false,
            moving: .available(TimeInterval(timer.timerSeconds - stoppedSeconds(in: timer)))
        )
    }

    /// The timer seconds whose speed is below the sport's floor. None
    /// indoors, and none for a sport the spec gives no floor. A second with
    /// missing speed is moving, so a stream without speed has none either.
    private func stoppedSeconds(in timer: TimerGrid) -> Int {
        guard !isIndoor, let floor = movingSpeedFloor else { return 0 }
        return timer.seconds.count { second in
            speed[second].map { $0 < floor } ?? false
        }
    }

    /// Metres per second, or nil for a sport that is neither on foot nor on
    /// a bike.
    private var movingSpeedFloor: Double? {
        switch sport.family {
        case .cycling: AnalysisRules.movingSpeedFloorCycling
        case .onFoot: AnalysisRules.movingSpeedFloorOnFoot
        case .other: nil
        }
    }
}

extension ActivityAnalysis {
    /// The metrics of an activity with no stream: its three times from the
    /// stated metadata, and everything else unavailable.
    ///
    /// Elapsed time is the stated end minus the stated start. The spec does
    /// not say what a stated end before the stated start means; it is read
    /// as not stating an elapsed time, since a negative time is not one.
    static func summaryMetrics(_ stated: StatedSummary) -> ActivityMetrics {
        let elapsed: Metric<TimeInterval>
        if let start = stated.start, let end = stated.end, end >= start {
            elapsed = .available(end.timeIntervalSince(start))
        } else {
            elapsed = .unavailable(.notStated)
        }
        let timer: Metric<TimeInterval> = stated.timerTime.map(Metric.available) ?? .unavailable(.notStated)
        let reason = UnavailableReason.noStream
        return ActivityMetrics(
            time: TimeMetrics(elapsed: elapsed, timer: timer, timerIsSummaryOnly: false, moving: timer),
            distance: .unavailable(reason),
            ascent: .unavailable(reason),
            descent: .unavailable(reason),
            power: PowerMetrics(unavailable: reason),
            heartRate: HeartRateMetrics(
                coverage: .unavailable(reason),
                average: .unavailable(reason),
                load: .unavailable(reason)
            ),
            load: .unavailable(reason),
            promptsForThresholdPower: false,
            timeInPowerZones: .unavailable(reason),
            timeInHeartRateZones: .unavailable(reason),
            timeInGradientBands: .unavailable(reason),
            cyclingEfficiency: .unavailable(reason),
            onFootEfficiency: .unavailable(reason),
            splits: .unavailable(reason),
            bestDistances: AnalysisRules.bestDistances.map { BestDistance(distance: $0, time: .unavailable(reason)) }
        )
    }
}

extension PowerMetrics {
    /// Every power metric unavailable for one reason, and no coverage note.
    init(unavailable reason: UnavailableReason) {
        self.init(
            coverage: .unavailable(reason),
            average: .unavailable(reason),
            averageShowsCoverage: false,
            weighted: .unavailable(reason),
            intensity: .unavailable(reason),
            load: .unavailable(reason),
            variability: .unavailable(reason),
            work: .unavailable(reason)
        )
    }
}
