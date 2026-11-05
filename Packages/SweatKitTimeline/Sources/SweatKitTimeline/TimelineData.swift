import Foundation
import SwiftUI

/// What the timeline's x-axis measures.
public enum TimelineAxisMode: String, Hashable, Sendable, CaseIterable {
    case distance
    case time
}

/// One activity's per-second data for the timeline: the elevation profile,
/// the distance that the distance axis is laid out by, the detected stops and
/// the lap boundaries.
///
/// Every array has one entry per second of the analysis stream, and a sample
/// index is an index into them. Build it once per activity and keep it: the
/// timeline tells two values apart by identity, not by comparing their
/// contents, and prepares its drawing tables again for each new one.
public struct TimelineData: Sendable {
    /// Why the data was rejected.
    public enum Problem: Error, Hashable, Sendable {
        /// A timeline needs at least two samples.
        case tooFewSamples
        /// Distance must have one entry per elevation sample.
        case countMismatch
        /// An elevation is not finite.
        case invalidElevation(sample: Int)
        /// A distance is not finite, is negative, or is less than the one
        /// before it.
        case invalidDistance(sample: Int)
        /// Stops are non-empty half-open ranges inside the samples, sorted
        /// and not overlapping.
        case invalidStop(index: Int)
        /// Lap boundaries are sample indices, strictly increasing.
        case invalidLapBoundary(index: Int)
    }

    /// Metres, or nil where the second has no elevation. A missing second is
    /// drawn as a gap.
    public let elevation: [Double?]
    /// Cumulative metres at each second, never decreasing. Nil when the
    /// activity has no distance, which leaves only the time axis.
    public let distance: [Double]?
    /// The detected stops, as half-open ranges of seconds.
    public let stops: [Range<Int>]
    /// The sample at which each lap after the first starts.
    public let lapBoundaries: [Int]

    /// Tells one prepared activity from another without comparing arrays.
    let id = UUID()

    public init(
        elevation: [Double?],
        distance: [Double]?,
        stops: [Range<Int>] = [],
        lapBoundaries: [Int] = []
    ) throws(Problem) {
        let count = elevation.count
        guard count >= 2 else { throw .tooFewSamples }
        if let index = elevation.firstIndex(where: { $0.map { !$0.isFinite } ?? false }) {
            throw .invalidElevation(sample: index)
        }
        if let distance {
            guard distance.count == count else { throw .countMismatch }
            var previous = 0.0
            for (index, value) in distance.enumerated() {
                guard value.isFinite, value >= previous else { throw .invalidDistance(sample: index) }
                previous = value
            }
        }
        var end = 0
        for (index, stop) in stops.enumerated() {
            guard !stop.isEmpty, stop.lowerBound >= end, stop.upperBound <= count else {
                throw .invalidStop(index: index)
            }
            end = stop.upperBound
        }
        var last = -1
        for (index, boundary) in lapBoundaries.enumerated() {
            guard boundary > last, boundary < count else { throw .invalidLapBoundary(index: index) }
            last = boundary
        }
        self.elevation = elevation
        self.distance = distance
        self.stops = stops
        self.lapBoundaries = lapBoundaries
    }

    /// The number of samples, which is the activity's elapsed seconds.
    public var count: Int { elevation.count }
}

/// The one series drawn over the elevation profile, with its colours.
///
/// The timeline draws the colours it is given and never chooses one for data.
/// Like `TimelineData`, build it once per choice of overlay and keep it.
public struct TimelineOverlay: Sendable {
    public enum Kind: String, Hashable, Sendable, CaseIterable {
        /// Watts.
        case power
        /// Beats per minute.
        case heartRate
        /// Metres per second.
        case speed
        /// Metres per second as well, so that faster is drawn higher and a
        /// stop needs no infinite value. Only the description differs from
        /// `speed`.
        case pace
        /// Revolutions per minute on a bike, steps per minute on foot.
        case cadence
    }

    public let kind: Kind
    /// One value per second, or nil where the second has none. A missing
    /// second is drawn as a gap, never as zero. A series shorter than the
    /// timeline's data is missing past its end.
    public let values: [Double?]
    /// The colour band of each second, for a zoned overlay. Nil draws the
    /// whole series in the neutral label colour.
    public let bands: [Int]?
    /// One colour per band. A band with no colour is drawn in the neutral
    /// label colour.
    public let bandColors: [Color]

    let id = UUID()

    public init(kind: Kind, values: [Double?], bands: [Int]? = nil, bandColors: [Color] = []) {
        self.kind = kind
        self.values = values
        self.bands = bands
        self.bandColors = bandColors
    }
}
