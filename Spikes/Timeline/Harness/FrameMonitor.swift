import Observation
import QuartzCore

/// Throwaway: measures how often the main thread delivers frames, from a
/// CADisplayLink asking for 120 Hz. MapKit draws its map on its own render
/// thread, so this catches main-thread stalls (overlay rebuilds, camera and
/// marker updates) but not a slow map render. Use the Graphics HUD in
/// Settings › Developer for that.
@MainActor @Observable
final class FrameMonitor: NSObject {
    /// Frames per second over the last quarter second.
    private(set) var currentFPS = 0.0
    /// The lowest quarter-second rate seen while measuring.
    private(set) var worstFPS: Double?
    /// The longest single frame seen while measuring, in milliseconds.
    private(set) var longestFrame: Double?
    /// Frames longer than 25 ms, one and a half 60 Hz frames, while measuring.
    private(set) var hitches = 0
    private(set) var isMeasuring = false

    /// Called on every frame with the seconds since the last one, for driving
    /// a sweep.
    @ObservationIgnored var onFrame: ((Double) -> Void)?

    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var lastTimestamp: CFTimeInterval?
    @ObservationIgnored private var windowStart: CFTimeInterval?
    @ObservationIgnored private var windowFrames = 0

    func start() {
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func beginMeasuring() {
        worstFPS = nil
        longestFrame = nil
        hitches = 0
        windowStart = nil
        windowFrames = 0
        isMeasuring = true
    }

    func endMeasuring() {
        isMeasuring = false
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        if let last = lastTimestamp {
            let interval = now - last
            onFrame?(interval)
            if isMeasuring {
                let milliseconds = interval * 1000
                longestFrame = max(longestFrame ?? 0, milliseconds)
                if milliseconds > 25 { hitches += 1 }
            }
        }
        lastTimestamp = now

        guard let start = windowStart else {
            windowStart = now
            windowFrames = 0
            return
        }
        windowFrames += 1
        let elapsed = now - start
        if elapsed >= 0.25 {
            currentFPS = Double(windowFrames) / elapsed
            if isMeasuring { worstFPS = min(worstFPS ?? .infinity, currentFPS) }
            windowStart = now
            windowFrames = 0
        }
    }
}
