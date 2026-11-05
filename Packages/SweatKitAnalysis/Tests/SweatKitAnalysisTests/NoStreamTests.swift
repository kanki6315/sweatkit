import Foundation
import SweatKitModel
import Testing
@testable import SweatKitAnalysis

/// "Activity with no stream: all three times come from the stated metadata,
/// and moving time equals timer time."
@Suite struct NoStreamTests {
    private func metrics(_ stated: StatedSummary, sport: Sport = .cycling) -> ActivityMetrics {
        ActivityAnalysis.metrics(for: ActivityInput(
            sport: sport,
            recording: .summaryOnly(stated),
            profile: makeProfile(thresholdPower: 200, thresholdHeartRate: 160),
            activityDate: testStart
        ))
    }

    private let full = StatedSummary(
        start: testStart,
        end: testStart.addingTimeInterval(3600),
        timerTime: 3000,
        distance: 25_000,
        ascent: 300
    )

    @Test func allThreeTimesComeFromTheStatedMetadata() {
        // Elapsed = end - start = 3600. Timer = the stated 3000. Moving = timer.
        let time = metrics(full).time
        #expect(time.elapsed == .available(3600))
        #expect(time.timer == .available(3000))
        #expect(time.moving == .available(3000))
    }

    @Test func timerAndMovingAreUnavailableWhenNoTimerTimeIsStated() {
        var stated = full
        stated.timerTime = nil
        let time = metrics(stated).time
        #expect(time.elapsed == .available(3600))
        #expect(time.timer == .unavailable(.notStated))
        #expect(time.moving == .unavailable(.notStated))
    }

    @Test func elapsedIsUnavailableWhenTheEndIsNotStated() {
        var stated = full
        stated.end = nil
        let time = metrics(stated).time
        #expect(time.elapsed == .unavailable(.notStated))
        #expect(time.timer == .available(3000))
    }

    @Test func elapsedIsUnavailableWhenTheStartIsNotStated() {
        var stated = full
        stated.start = nil
        #expect(metrics(stated).time.elapsed == .unavailable(.notStated))
    }

    @Test func everyStreamMetricIsUnavailableNotZero() {
        let result = metrics(full)
        #expect(result.distance == .unavailable(.noStream))
        #expect(result.ascent == .unavailable(.noStream))
        #expect(result.descent == .unavailable(.noStream))
        #expect(result.power.coverage == .unavailable(.noStream))
        #expect(result.power.average == .unavailable(.noStream))
        #expect(result.power.averageShowsCoverage == false)
        #expect(result.power.weighted == .unavailable(.noStream))
        #expect(result.power.intensity == .unavailable(.noStream))
        #expect(result.power.load == .unavailable(.noStream))
        #expect(result.power.variability == .unavailable(.noStream))
        #expect(result.power.work == .unavailable(.noStream))
        #expect(result.heartRate.coverage == .unavailable(.noStream))
        #expect(result.heartRate.average == .unavailable(.noStream))
        #expect(result.heartRate.load == .unavailable(.noStream))
        #expect(result.load == .unavailable(.noStream))
        #expect(result.promptsForThresholdPower == false)
        #expect(result.timeInPowerZones == .unavailable(.noStream))
        #expect(result.timeInHeartRateZones == .unavailable(.noStream))
        #expect(result.timeInGradientBands == .unavailable(.noStream))
        #expect(result.cyclingEfficiency == .unavailable(.noStream))
        #expect(result.onFootEfficiency == .unavailable(.noStream))
        #expect(result.splits == .unavailable(.noStream))
    }

    @Test func bestDistancesAreListedAndUnavailable() {
        let best = metrics(full, sport: .running).bestDistances
        #expect(best.map(\.distance) == [1000, 5000, 10_000])
        #expect(best.map(\.time) == Array(repeating: .unavailable(.noStream), count: 3))
    }

    @Test func thePowerCurveIsUnavailable() {
        let input = ActivityInput(sport: .cycling, recording: .summaryOnly(full), activityDate: testStart)
        let curve = ActivityAnalysis.powerCurve(for: input, durations: [5, 60])
        #expect(curve == [
            PowerCurvePoint(duration: 5, power: .unavailable(.noStream)),
            PowerCurvePoint(duration: 60, power: .unavailable(.noStream)),
        ])
    }
}
