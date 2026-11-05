import SwiftUI

/// Everything the timeline draws from, worked out once per activity: the four
/// axes and the elevation's running totals. Building it reads every sample,
/// so the timeline builds it off the main thread and keeps it.
final class PreparedTimeline: Sendable {
    let data: TimelineData
    let count: Int
    private let time: TimelineAxis
    private let timeCollapsed: TimelineAxis
    private let distance: TimelineAxis?
    private let distanceCollapsed: TimelineAxis?
    private let elevation: SeriesTable
    private let elevationCollapsed: SeriesTable

    init(_ data: TimelineData) {
        self.data = data
        count = data.count
        time = TimelineAxis(mode: .time, count: data.count, distance: nil)
        timeCollapsed = TimelineAxis(mode: .time, count: data.count, distance: nil, collapsing: data.stops)
        if let distance = data.distance {
            self.distance = TimelineAxis(mode: .distance, count: data.count, distance: distance)
            distanceCollapsed = TimelineAxis(mode: .distance, count: data.count, distance: distance, collapsing: data.stops)
        } else {
            distance = nil
            distanceCollapsed = nil
        }
        elevation = SeriesTable(values: data.elevation, count: data.count)
        elevationCollapsed = SeriesTable(values: data.elevation, count: data.count, excluding: data.stops)
    }

    /// Builds the tables off the main thread.
    static func make(_ data: TimelineData) async -> PreparedTimeline {
        await Task.detached(priority: .userInitiated) { PreparedTimeline(data) }.value
    }

    /// The axis that is actually used for a request. An activity with no
    /// distance, or none covered, falls back to the time axis. Stops stay
    /// uncollapsed when collapsing them would leave nothing to show.
    func resolve(_ key: AxisKey) -> AxisKey {
        var resolved = key
        if resolved.mode == .distance, (distance?.total ?? 0) <= 0 { resolved.mode = .time }
        if resolved.collapsesStops, stored(resolved).total <= 0 { resolved.collapsesStops = false }
        return resolved
    }

    func axis(_ key: AxisKey) -> TimelineAxis {
        stored(resolve(key))
    }

    func elevationTable(_ key: AxisKey) -> SeriesTable {
        resolve(key).collapsesStops ? elevationCollapsed : elevation
    }

    /// The range of the whole elevation profile.
    var elevationRange: ClosedRange<Double>? { elevation.range }

    private func stored(_ key: AxisKey) -> TimelineAxis {
        switch (key.mode, key.collapsesStops) {
        case (.time, false): time
        case (.time, true): timeCollapsed
        case (.distance, false): distance ?? time
        case (.distance, true): distanceCollapsed ?? timeCollapsed
        }
    }
}

/// The overlay's running totals and band counts, worked out once per overlay
/// off the main thread.
final class PreparedOverlay: Sendable {
    let kind: TimelineOverlay.Kind
    let colors: [Color]
    private let table: SeriesTable
    private let tableCollapsed: SeriesTable
    private let bands: BandTable?
    private let bandsCollapsed: BandTable?

    init(_ overlay: TimelineOverlay, data: TimelineData) {
        kind = overlay.kind
        colors = overlay.bandColors
        table = SeriesTable(values: overlay.values, count: data.count)
        tableCollapsed = SeriesTable(values: overlay.values, count: data.count, excluding: data.stops)
        overviewRange = table.overviewRange(windows: ValueScale.overviewWindows)
        if let bands = overlay.bands {
            self.bands = BandTable(bands: bands, values: overlay.values, count: data.count)
            bandsCollapsed = BandTable(bands: bands, values: overlay.values, count: data.count, excluding: data.stops)
        } else {
            bands = nil
            bandsCollapsed = nil
        }
    }

    static func make(_ overlay: TimelineOverlay, data: TimelineData) async -> PreparedOverlay {
        await Task.detached(priority: .userInitiated) { PreparedOverlay(overlay, data: data) }.value
    }

    func table(collapsesStops: Bool) -> SeriesTable {
        collapsesStops ? tableCollapsed : table
    }

    func bands(collapsesStops: Bool) -> BandTable? {
        collapsesStops ? bandsCollapsed : bands
    }

    /// The range of the whole series.
    var range: ClosedRange<Double>? { table.range }

    /// The range of the series at full zoom-out, which sets its scale.
    let overviewRange: ClosedRange<Double>?

    /// The colour the caller gave a band, or nil when it gave none.
    func color(for band: Int?) -> Color? {
        guard let band, colors.indices.contains(band) else { return nil }
        return colors[band]
    }
}
