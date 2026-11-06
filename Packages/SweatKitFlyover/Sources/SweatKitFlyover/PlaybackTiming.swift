/// Playback traverses the elapsed 1 Hz sample grid, including recorded pauses
/// and missing sensor spans. Timer time and visually collapsed stops never
/// change this clock. Route availability does not affect chart playback.
public enum PlaybackTiming: String, CaseIterable, Hashable, Sendable {
    case overview, halfSpeed, quarterSpeed, recorded

    public var label: String {
        switch self {
        case .overview: "1×"
        case .halfSpeed: "0.5×"
        case .quarterSpeed: "0.25×"
        case .recorded: "Recorded time"
        }
    }

    /// Advance to the last available sample, never beyond the stats grid.
    /// Real elapsed wall time is retained across dropped frames. The caller
    /// stops the clock on pause, scrubbing, backgrounding or activity changes.
    public func advance(sample: Double, sampleCount: Int, wallSeconds: Double) -> Double {
        let end = Double(max(0, sampleCount - 1))
        guard end > 0 else { return 0 }
        let current = sample.isFinite ? min(max(sample, 0), end) : 0
        guard wallSeconds.isFinite, wallSeconds > 0 else { return current }
        let duration: Double
        switch self {
        case .overview: duration = 30
        case .halfSpeed: duration = 60
        case .quarterSpeed: duration = 120
        case .recorded: duration = end
        }
        return min(end, current + wallSeconds * end / duration)
    }
}
