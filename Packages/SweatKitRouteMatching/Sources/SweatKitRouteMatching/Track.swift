import Foundation
import SweatKitModel

/// One position of a cleaned track, with the time it was reached.
///
/// A point carries two clocks so that a comparison can run on either without
/// this package working out which seconds were moving. That definition belongs
/// to the analysis rules.
public struct TrackPoint: Hashable, Codable, Sendable {
    public var coordinate: Coordinate
    /// Seconds of elapsed time since the activity started.
    public var elapsedTime: TimeInterval
    /// Seconds of moving time since the activity started. It never runs
    /// faster than elapsed time and stands still through a pause or a stop.
    /// It is read only when the track's pause positions are reliable.
    public var movingTime: TimeInterval

    public init(coordinate: Coordinate, elapsedTime: TimeInterval, movingTime: TimeInterval) {
        self.coordinate = coordinate
        self.elapsedTime = elapsedTime
        self.movingTime = movingTime
    }

    /// A point of a track with no stops, where both clocks agree.
    public init(coordinate: Coordinate, time: TimeInterval) {
        self.init(coordinate: coordinate, elapsedTime: time, movingTime: time)
    }
}

/// An activity's track after cleanup: impossible speeds dropped and jitter
/// while stopped collapsed. Cleanup happens before this package is called.
///
/// Points are in recorded order and their elapsed times never decrease.
public struct CleanedTrack: Hashable, Codable, Sendable {
    public var points: [TrackPoint]
    public var sportFamily: SportFamily
    /// False when the activity's pause data is incomplete. Its moving times
    /// are then not used, and any comparison that includes it runs on elapsed
    /// time.
    public var pausePositionsAreReliable: Bool

    public init(points: [TrackPoint], sportFamily: SportFamily, pausePositionsAreReliable: Bool = true) {
        self.points = points
        self.sportFamily = sportFamily
        self.pausePositionsAreReliable = pausePositionsAreReliable
    }

    /// The distance travelled: the sum of the distances between consecutive
    /// points, in metres. A track of fewer than two points has length 0.
    public var length: Double {
        Polyline(points.map(\.coordinate)).length
    }
}
