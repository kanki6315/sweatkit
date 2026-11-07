import SweatKitModel

/// One activity's metrics, computed from its analysis stream. Pure Swift,
/// with no interface, network, storage or FIT code. The spec's "Analysis
/// metrics" section is the contract.
///
/// Two readings apply throughout, because the spec leaves them open:
///
/// - A metric that the spec defines "over timer time" or "by timer time"
///   (coverage, weighted power and what follows from it, the power curve,
///   load from heart rate, moving time, splits and best distances) reads only
///   the seconds outside the paused spans. Every other metric (distance,
///   ascent and descent, time in zones, average power, average heart rate,
///   work, on-foot efficiency) reads every second of the stream that has a
///   value, paused or not. That is the literal reading of "the seconds that
///   have them", and it is why those metrics stay available when pause
///   positions are unknown.
/// - A metric that follows from another carries that metric's reason when it
///   is unavailable, so the reason shown is always the root cause.
///
/// When several reasons apply to one metric the first of these wins: no
/// stream, not defined for the sport, pause positions unknown, the channel
/// has no values, then the metric's own conditions in the order its
/// documentation lists them.
///
/// A stream is read defensively. Paused spans are cut to the grid and merged
/// where they overlap, a channel shorter than the stream is missing past its
/// end, and a channel longer than the stream is cut to it.
public enum ActivityAnalysis {
    /// Every metric of one activity.
    public static func metrics(for input: ActivityInput) -> ActivityMetrics {
        switch input.recording {
        case .stream(let stream):
            StreamAnalysis(input: input, stream: stream).metrics()
        case .summaryOnly(let stated):
            summaryMetrics(stated)
        }
    }

    /// Only the measurements used during range selection; skips splits, zones,
    /// load, best distances and weighted power.
    public static func rangeMeasurements(for input: ActivityInput) -> (ascent: Metric<Double>, averagePower: Metric<Double>, averageHeartRate: Metric<Double>) {
        guard case .stream(let stream) = input.recording else {
            return (.unavailable(.noStream), .unavailable(.noStream), .unavailable(.noStream))
        }
        let analysis = StreamAnalysis(input: input, stream: stream)
        return (analysis.elevation().map(\.ascent),
            input.sport == .cycling ? analysis.average(of: analysis.power, orElse: .noPower) : .unavailable(.notDefinedForSport),
            analysis.average(of: analysis.heartRate, orElse: .noHeartRate))
    }

    /// The best mean power for each duration, in the order given.
    ///
    /// The spec names no set of durations, so the caller chooses them. Each
    /// duration is a whole number of seconds. A window is valid when it sits
    /// inside one unbroken timer span and at least
    /// `AnalysisRules.curveMinimumPresentShare` of its seconds have power; a
    /// window shorter than `AnalysisRules.curveCompleteBelowSeconds` must
    /// have power at every second. A window's mean is the sum of its present
    /// values divided by the number of present values.
    ///
    /// A point is unavailable with `.noStream`, `.notDefinedForSport` (power
    /// is cycling only), `.pausePositionsUnknown`, `.noPower`, or
    /// `.noValidWindow` when no valid window of that duration exists. A
    /// duration below one second has no window.
    public static func powerCurve(for input: ActivityInput, durations: [Int]) -> [PowerCurvePoint] {
        switch input.recording {
        case .stream(let stream):
            StreamAnalysis(input: input, stream: stream).powerCurve(durations: durations)
        case .summaryOnly:
            durations.map { PowerCurvePoint(duration: $0, power: .unavailable(.noStream)) }
        }
    }
}
