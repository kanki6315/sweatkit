import Foundation
import SweatKitModel

/// Everything the detail screen is prepared from: one activity's analysis
/// stream and the facts about it that change how it is drawn.
public struct DetailInput: Hashable, Sendable {
    public var stream: AnalysisStream
    public var sport: Sport
    public var isIndoor: Bool
    /// Virtual rides carry made-up positions, so they have no route.
    public var isVirtual: Bool
    /// The grid second at which each of the device's laps starts, in any
    /// order. The first lap's start, and any start outside the stream, marks
    /// no boundary. `lapStarts(of:streamStart:)` converts recorded laps.
    public var lapStarts: [Int]
    public var profile: AthleteProfile
    /// The date whose threshold power applies.
    public var activityDate: Date

    public init(
        stream: AnalysisStream,
        sport: Sport,
        isIndoor: Bool = false,
        isVirtual: Bool = false,
        lapStarts: [Int] = [],
        profile: AthleteProfile = AthleteProfile(),
        activityDate: Date
    ) {
        self.stream = stream
        self.sport = sport
        self.isIndoor = isIndoor
        self.isVirtual = isVirtual
        self.lapStarts = lapStarts
        self.profile = profile
        self.activityDate = activityDate
    }

    /// The grid second each recorded lap starts in. Grid second t covers the
    /// interval from t to t + 1 seconds after the stream start, so a lap
    /// starting part-way through a second starts in that second.
    public static func lapStarts(of laps: [RecordedLap], streamStart: Date) -> [Int] {
        laps.map { Int($0.start.timeIntervalSince(streamStart).rounded(.down)) }
    }
}

/// Why something on the detail screen is unavailable.
extension UnavailableReason {
    /// A virtual activity's positions are made up, so it has no route.
    public static let virtualActivity = UnavailableReason(rawValue: "detail.virtualActivity")
    /// An indoor activity has no route.
    public static let indoorActivity = UnavailableReason(rawValue: "detail.indoorActivity")
    /// Fewer than two positions survive track cleanup, so there is no line
    /// to draw.
    public static let noUsablePositions = UnavailableReason(rawValue: "detail.noUsablePositions")
}
