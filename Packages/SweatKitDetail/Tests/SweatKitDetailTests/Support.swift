import Foundation
import SweatKitModel
@testable import SweatKitDetail

/// The start of every synthetic stream, and the activity date.
let testStart = Date(timeIntervalSince1970: 1_750_000_000)

/// `count` seconds of one value. A nil value is a run of missing seconds.
func run(_ value: Double?, _ count: Int) -> [Double?] {
    Array(repeating: value, count: count)
}

/// A stream with the given channels and every other channel missing.
func makeStream(
    count: Int,
    pauses: PauseData = .known(paused: []),
    positions: [Coordinate?]? = nil,
    power: [Double?]? = nil,
    heartRate: [Double?]? = nil,
    speed: [Double?]? = nil,
    cadence: [Double?]? = nil,
    altitude: [Double?]? = nil,
    distance: [Double?]? = nil,
    gradient: [Double?]? = nil
) -> AnalysisStream {
    var stream = AnalysisStream(rulesVersion: 1, start: testStart, count: count, pauses: pauses)
    if let positions {
        stream.latitude = Series(positions.map { $0?.latitude })
        stream.longitude = Series(positions.map { $0?.longitude })
    }
    if let power { stream.power = Series(power) }
    if let heartRate { stream.heartRate = Series(heartRate) }
    if let speed { stream.speed = Series(speed) }
    if let cadence { stream.cadence = Series(cadence) }
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
    virtual: Bool = false,
    lapStarts: [Int] = [],
    profile: AthleteProfile = AthleteProfile()
) -> DetailInput {
    DetailInput(
        stream: stream,
        sport: sport,
        isIndoor: indoor,
        isVirtual: virtual,
        lapStarts: lapStarts,
        profile: profile,
        activityDate: testStart
    )
}

/// Positions heading north from 51° N, 0.0001° of latitude (about 11 m) a
/// second, swinging 0.0001° of longitude (about 7 m) east and back every
/// second. Every point is several metres off the line between its
/// neighbours, so simplification keeps every one.
func zigzag(_ count: Int) -> [Coordinate?] {
    (0..<count).map { Coordinate(latitude: 51 + Double($0) * 0.0001, longitude: $0.isMultiple(of: 2) ? 0 : 0.0001) }
}
