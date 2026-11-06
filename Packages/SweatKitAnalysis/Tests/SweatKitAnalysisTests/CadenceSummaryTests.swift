import SweatKitModel
import SweatKitAnalysis
import Testing

@Suite struct CadenceSummaryTests {
    @Test func timerMeanIncludesZeroAndInterpolationButNotPausesOrMissing() {
        var stream = makeStream(count: 5, pauses: .known(paused: [1..<2]))
        stream.cadence = Series(values: [120, 240, 0, 999, 180],
            quality: [.measured, .measured, .measured, .missing, .interpolated])
        let result = CadenceSummary.calculate(stream: stream)
        // (120 + 0 + 180) / 3, with 3 present of 4 timer seconds.
        #expect(result.average == .available(100))
        #expect(result.coverage == .available(0.75))
    }

    @Test func unknownPausesAndEmptyTimerAreUnavailable() {
        #expect(CadenceSummary.calculate(stream: makeStream(count: 3, pauses: .unknown(statedTimerTime: 2))).average == .unavailable(.pausePositionsUnknown))
        #expect(CadenceSummary.calculate(stream: makeStream(count: 3, pauses: .known(paused: [0..<3]))).average == .unavailable(.zeroDenominator))
    }

    @Test func absentInvalidAndShortChannelsNeverInventZeroCadence() {
        var stream = makeStream(count: 5)
        stream.cadence = Series([nil, .infinity, -1])
        let absent = CadenceSummary.calculate(stream: stream)
        #expect(absent.average == .unavailable(.noCadence))
        #expect(absent.coverage == .available(0))
        stream.cadence = Series([90])
        let partial = CadenceSummary.calculate(stream: stream)
        #expect(partial.average == .available(90))
        #expect(partial.coverage == .available(0.2))
    }
}
