import Foundation
import SweatKitModel
import Testing
@testable import SweatKitAnalysis

/// The start of every synthetic stream, and the activity date.
let testStart = Date(timeIntervalSince1970: 1_750_000_000)

/// `count` seconds of one value. A nil value is a run of missing seconds.
func run(_ value: Double?, _ count: Int) -> [Double?] {
    Array(repeating: value, count: count)
}

/// A value that grows by `perSecond` each second from 0, such as cumulative
/// distance at a steady speed: second t holds `perSecond * t`.
func ramp(_ count: Int, perSecond: Double) -> [Double?] {
    (0..<count).map { Double($0) * perSecond }
}

/// A stream with the given channels and every other channel missing.
func makeStream(
    count: Int,
    pauses: PauseData = .known(paused: []),
    power: [Double?]? = nil,
    heartRate: [Double?]? = nil,
    speed: [Double?]? = nil,
    altitude: [Double?]? = nil,
    distance: [Double?]? = nil,
    gradient: [Double?]? = nil
) -> AnalysisStream {
    var stream = AnalysisStream(rulesVersion: 1, start: testStart, count: count, pauses: pauses)
    if let power { stream.power = Series(power) }
    if let heartRate { stream.heartRate = Series(heartRate) }
    if let speed { stream.speed = Series(speed) }
    if let altitude { stream.altitude = Series(altitude) }
    if let distance { stream.distance = Series(distance) }
    if let gradient { stream.gradient = Series(gradient) }
    precondition(stream.isConsistent, "Every channel needs one value per second")
    return stream
}

/// A profile whose threshold power, when given, has always been in effect.
func makeProfile(
    thresholdPower: Double? = nil,
    thresholdHeartRate: Double? = nil,
    maxHeartRate: Double? = nil
) -> AthleteProfile {
    AthleteProfile(
        thresholdPowerHistory: thresholdPower.map {
            [AthleteProfile.ThresholdPower(effectiveFrom: Date(timeIntervalSince1970: 0), watts: $0)]
        } ?? [],
        maxHeartRate: maxHeartRate,
        statedThresholdHeartRate: thresholdHeartRate
    )
}

func makeInput(
    _ stream: AnalysisStream,
    sport: Sport = .cycling,
    indoor: Bool = false,
    profile: AthleteProfile = AthleteProfile()
) -> ActivityInput {
    ActivityInput(
        sport: sport,
        isIndoor: indoor,
        recording: .stream(stream),
        profile: profile,
        activityDate: testStart
    )
}

/// The metrics of an outdoor ride unless told otherwise.
func analyse(
    _ stream: AnalysisStream,
    sport: Sport = .cycling,
    indoor: Bool = false,
    profile: AthleteProfile = AthleteProfile()
) -> ActivityMetrics {
    ActivityAnalysis.metrics(for: makeInput(stream, sport: sport, indoor: indoor, profile: profile))
}

/// Expects an available value within `tolerance` of `expected`.
func expectClose(
    _ metric: Metric<Double>,
    _ expected: Double,
    tolerance: Double = 1e-9,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    guard let value = metric.value else {
        Issue.record(
            "Expected \(expected), but the metric is unavailable: \(metric.reason?.rawValue ?? "no reason")",
            sourceLocation: sourceLocation
        )
        return
    }
    #expect(abs(value - expected) <= tolerance, "\(value) is not \(expected)", sourceLocation: sourceLocation)
}

/// Expects available work of `kilojoules`, within a rounding error, with the
/// given label.
func expectWork(
    _ metric: Metric<Work>,
    kilojoules: Double,
    isRecordedOnly: Bool,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    guard let work = metric.value else {
        Issue.record(
            "Expected \(kilojoules) kJ, but work is unavailable: \(metric.reason?.rawValue ?? "no reason")",
            sourceLocation: sourceLocation
        )
        return
    }
    #expect(
        abs(work.kilojoules - kilojoules) <= 1e-9,
        "\(work.kilojoules) kJ is not \(kilojoules) kJ",
        sourceLocation: sourceLocation
    )
    #expect(work.isRecordedOnly == isRecordedOnly, sourceLocation: sourceLocation)
}
