import SweatKitFlyover
import SweatKitModel
import SweatKitTimeline
import SwiftUI

@main
struct HarnessApp: App {
    var body: some Scene {
        WindowGroup { HarnessView() }
    }
}

enum FileChoice: String, CaseIterable, Identifiable {
    case ride = "outdoor-ride"
    case zwift = "zwift-ride"
    case walk = "walk"
    case pitlane = "walk-pitlane"
    case fiveHours = "five-hours"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ride: "Outdoor ride (1.6 h)"
        case .zwift: "Zwift ride (0.7 h)"
        case .walk: "Walk (0.7 h)"
        case .pitlane: "Pit-lane walk (10 h)"
        case .fiveHours: "Ride repeated to 5 h"
        }
    }
}

@MainActor @Observable
final class HarnessModel {
    var file = FileChoice.ride
    var overlayChoice = OverlayChoice.power
    var axisMode = TimelineAxisMode.distance
    var collapsesStops = false
    var units = UnitSystem.metric
    var backdrop = Backdrop.map
    var showsPanels = true
    var scrub = 0.0
    var selection: ClosedRange<Int>?

    private(set) var activity: LoadedActivity?
    private(set) var overlay: TimelineOverlay?
    private(set) var route: (route: FlyoverRoute, colors: [Color])?
    private(set) var rangeStats: RangeStats?
    private(set) var loadError: String?
    private(set) var isSweeping = false

    let monitor = FrameMonitor()
    @ObservationIgnored private var loaded: [FileChoice: LoadedActivity] = [:]
    /// A cursor and selection to start with, as shares of the activity, set
    /// from launch arguments for taking screenshots.
    @ObservationIgnored private var startScrub: Double?
    @ObservationIgnored private var startSelection: (Double, Double)?

    init() {
        let defaults = UserDefaults.standard
        if let value = defaults.string(forKey: "file"), let choice = FileChoice(rawValue: value) { file = choice }
        if let value = defaults.string(forKey: "overlay"), let choice = OverlayChoice(rawValue: value) { overlayChoice = choice }
        if let value = defaults.string(forKey: "axis"), let choice = TimelineAxisMode(rawValue: value) { axisMode = choice }
        if let value = defaults.string(forKey: "units"), let choice = UnitSystem(rawValue: value) { units = choice }
        if let value = defaults.string(forKey: "backdrop"), let choice = Backdrop(rawValue: value) { backdrop = choice }
        collapsesStops = defaults.bool(forKey: "collapse")
        if defaults.object(forKey: "scrub") != nil { startScrub = defaults.double(forKey: "scrub") }
        if let parts = defaults.string(forKey: "select")?.split(separator: ",").compactMap({ Double($0) }), parts.count == 2 {
            startSelection = (parts[0], parts[1])
        }
        monitor.onFrame = { [weak self] seconds in self?.advanceSweep(seconds) }
        monitor.start()
    }

    func load() async {
        let file = self.file
        do {
            let activity: LoadedActivity
            if let cached = loaded[file] {
                activity = cached
            } else {
                activity = try await Task.detached {
                    if file == .fiveHours {
                        let ride = try ActivityLoader.load(resource: FileChoice.ride.rawValue)
                        return try ActivityLoader.repeated(ride, to: 18_000, name: file.rawValue)
                    }
                    return try ActivityLoader.load(resource: file.rawValue)
                }.value
                loaded[file] = activity
            }
            guard self.file == file else { return }
            if activity.sport.family != .cycling, overlayChoice == .power { overlayChoice = .speed }
            self.activity = activity
            let last = Double(activity.stream.count - 1)
            scrub = (startScrub ?? 0) * last
            selection = startSelection.map { Int($0.0 * last)...Int($0.1 * last) }
            startScrub = nil
            startSelection = nil
            rangeStats = nil
            loadError = nil
            await buildOverlay()
        } catch {
            loadError = "\(file.rawValue): \(error)"
        }
    }

    func buildOverlay() async {
        guard let activity else { return }
        let choice = overlayChoice
        let built = await Task.detached {
            let overlay = ActivityLoader.overlay(choice, for: activity)
            return (overlay, ActivityLoader.route(for: activity, overlay: overlay))
        }.value
        guard self.activity?.name == activity.name, overlayChoice == choice else { return }
        overlay = built.0
        route = built.1
    }

    func updateRangeStats() async {
        guard let activity, let selection else {
            rangeStats = nil
            return
        }
        let stats = await Task.detached { ActivityLoader.rangeStats(selection, in: activity) }.value
        if !Task.isCancelled { rangeStats = stats }
    }

    var cursorStats: CursorStats {
        activity.map { ActivityLoader.cursorStats(at: scrub, in: $0) } ?? CursorStats()
    }

    // MARK: Sweep

    /// Scrubs from start to end in 20 seconds at a steady rate, measuring
    /// throughout. Repeatable, unlike a hand drag.
    func toggleSweep() {
        if isSweeping {
            isSweeping = false
            monitor.endMeasuring()
        } else {
            scrub = 0
            isSweeping = true
            monitor.beginMeasuring()
        }
    }

    /// Measures until tapped again, for scrubbing, pinching and panning by
    /// hand.
    func toggleMeasuring() {
        if monitor.isMeasuring { monitor.endMeasuring() } else { monitor.beginMeasuring() }
    }

    private func advanceSweep(_ seconds: Double) {
        guard isSweeping, let activity else { return }
        let last = Double(activity.stream.count - 1)
        scrub = min(last, scrub + last / 20 * seconds)
        if scrub >= last {
            isSweeping = false
            monitor.endMeasuring()
        }
    }
}
