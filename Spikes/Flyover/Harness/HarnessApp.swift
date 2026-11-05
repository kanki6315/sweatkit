import SweatKitFlyover
import SwiftUI

@main
struct HarnessApp: App {
    var body: some Scene {
        WindowGroup { HarnessView() }
    }
}

enum RouteChoice: String, CaseIterable, Identifiable {
    case ride = "outdoor-ride"
    case walk = "walk"
    case pitlane = "walk-pitlane"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .ride: "Ride"
        case .walk: "Walk"
        case .pitlane: "Pit lane"
        }
    }
    var colouring: RouteBuilder.Colouring {
        self == .ride ? .power(threshold: 250) : .relativePace
    }
}

@MainActor @Observable
final class HarnessModel {
    var choice = RouteChoice.ride
    var tolerance = 2.0
    var options = FlyoverOptions()
    var scrub = 0.0
    var sweepSeconds = 60.0
    private(set) var isSweeping = false
    private(set) var built: RouteBuilder.Built?
    private(set) var track: FitTrack?
    private(set) var loadError: String?
    private(set) var isLoading = false

    let monitor = FrameMonitor()
    @ObservationIgnored private var tracks: [RouteChoice: FitTrack] = [:]

    init() {
        monitor.onFrame = { [weak self] seconds in self?.advanceSweep(seconds) }
        monitor.start()
    }

    func load() async {
        let choice = self.choice
        if let cached = tracks[choice] {
            show(cached)
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let track = try await Task.detached { try FitTrack.load(resource: choice.rawValue) }.value
            tracks[choice] = track
            if self.choice == choice { show(track) }
        } catch {
            loadError = "\(choice.rawValue): \(error)"
        }
    }

    private func show(_ track: FitTrack) {
        self.track = track
        scrub = Double(track.points[0].sample)
        rebuild()
    }

    func rebuild() {
        guard let track else { return }
        do {
            built = try RouteBuilder.build(track, colouring: choice.colouring, tolerance: tolerance)
            loadError = nil
        } catch {
            loadError = "\(error)"
        }
    }

    var sampleRange: ClosedRange<Double> {
        guard let range = built?.route.sampleRange else { return 0...1 }
        return Double(range.lowerBound)...Double(range.upperBound)
    }

    func toggleSweep() {
        if isSweeping {
            isSweeping = false
            monitor.endMeasuring()
        } else {
            scrub = sampleRange.lowerBound
            isSweeping = true
            monitor.beginMeasuring()
        }
    }

    private func advanceSweep(_ seconds: Double) {
        guard isSweeping else { return }
        let range = sampleRange
        let step = (range.upperBound - range.lowerBound) / sweepSeconds * seconds
        scrub = min(range.upperBound, scrub + step)
        if scrub >= range.upperBound {
            isSweeping = false
            monitor.endMeasuring()
        }
    }
}
