import SweatKitModel

/// How this package measures the ground.
///
/// The spec does not say how a distance between two positions is measured.
/// This package measures on a sphere of the mean earth radius, the same model
/// the flyover uses. Every length, offset and threshold check goes through
/// it, so two tracks are always compared with one ruler.
public enum Geodesy {
    /// The mean earth radius in metres.
    public static let earthRadius = 6_371_008.8

    /// The great-circle distance between two positions, in metres.
    public static func distance(from a: Coordinate, to b: Coordinate) -> Double {
        fatalError("unimplemented")
    }
}
