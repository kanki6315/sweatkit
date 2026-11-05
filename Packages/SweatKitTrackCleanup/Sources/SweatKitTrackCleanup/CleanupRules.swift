import SweatKitModel

/// Every number track cleanup uses. Speeds are metres per second and
/// distances are metres. None of them is written inline anywhere else.
public enum CleanupRules {
    /// Above this, a bike could not have covered the distance between two
    /// fixes.
    ///
    /// The spec says only "an impossible speed". 30 m/s (108 km/h) is this
    /// package's reading: above the fastest descents an amateur rides, so a
    /// real fix is never dropped, and far below the hundreds of metres a GPS
    /// spike jumps in a second.
    public static let impossibleSpeedCycling = 30.0

    /// Above this, nobody on foot could have covered the distance between two
    /// fixes.
    ///
    /// The spec gives no number. 12 m/s (43 km/h) is this package's reading:
    /// about a sprinter's top speed, and well above the 5 to 6 m/s that one
    /// second of ordinary GPS wobble adds to a walk.
    public static let impossibleSpeedOnFoot = 12.0

    /// A second on a bike with a speed below this is stopped.
    ///
    /// The spec does not say what "stopped" means for cleanup. This package
    /// reads it as the spec's own stopped second in the moving-time rule:
    /// below 1.0 m/s on a bike.
    public static let stoppedSpeedCycling = 1.0

    /// A second on foot with a speed below this is stopped. The moving-time
    /// rule's 0.5 m/s, read the same way as `stoppedSpeedCycling`.
    public static let stoppedSpeedOnFoot = 0.5

    /// A slow run collapses only while its points stay within this many
    /// metres of the point where the run began.
    ///
    /// The spec says "jitter while stopped" and gives no distance. Speed alone
    /// cannot tell standing still from walking slowly, and slow walking still
    /// counts, so a stop must also stay in one place. 10 m is a starting
    /// value, to be tuned against real recordings: wider than the metre or
    /// few of GPS wobble while standing, and narrow enough that slow walking
    /// is kept at about this resolution.
    public static let stopRadius = 10.0

    /// The spec's "about 2 m" tolerance for the drawn line: a point within
    /// this distance of the simplified line is left out.
    public static let simplificationTolerance = 2.0

    /// The impossible speed for a sport family, or nil for none.
    ///
    /// "Other" sports have no limit: they include anything from a swim to a
    /// drive, the app shows them as summary stats only, and no single number
    /// is impossible for all of them. Reading: their points are all kept.
    public static func impossibleSpeed(for family: SportFamily) -> Double? {
        switch family {
        case .cycling: impossibleSpeedCycling
        case .onFoot: impossibleSpeedOnFoot
        case .other: nil
        }
    }

    /// The stopped speed for a sport family, or nil when the family has no
    /// stopped seconds.
    ///
    /// The moving-time rule names a floor for bikes and for on foot only, so
    /// "other" sports are never stopped and never collapse.
    public static func stoppedSpeed(for family: SportFamily) -> Double? {
        switch family {
        case .cycling: stoppedSpeedCycling
        case .onFoot: stoppedSpeedOnFoot
        case .other: nil
        }
    }
}
