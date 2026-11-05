import SweatKitAnalysis
import SweatKitFlyover
import SweatKitModel
import SweatKitTimeline
import SweatKitTrackCleanup

/// Turns one activity's analysis stream into what the detail screen's views
/// take. Pure and synchronous: no interface, storage or network.
public enum DetailPreparation {
    /// Everything the detail screen needs for one activity.
    public static func prepare(_ input: DetailInput) -> PreparedDetail {
        let input = input.normalised()
        let stream = input.stream

        var bands: [RouteOverlay: Metric<OverlayBands>] = [:]
        for overlay in RouteOverlay.allCases {
            bands[overlay] = ColourBanding.bands(for: overlay, input: input)
        }
        let candidates = RouteOverlay.defaultCandidates(sport: input.sport, hasPowerMeter: hasPowerMeter(input))
        let defaultOverlay = candidates.first { bands[$0]?.value != nil } ?? .plain

        let track = cleanedTrack(input)
        let line = simplifiedLine(track)
        var routes: [RouteOverlay: Metric<FlyoverRoute>] = [:]
        for overlay in RouteOverlay.allCases {
            routes[overlay] = route(line: line, bands: bands[overlay] ?? .unavailable(.noUsablePositions))
        }

        let stops = self.stops(collapsed: track.value?.points ?? [], pauses: stream.pauses, count: stream.count)
        let laps = lapBoundaries(lapStarts: input.lapStarts, distance: stream.distance, count: stream.count)
        let timeline = try? TimelineData(
            elevation: (0..<stream.count).map { stream.altitude[$0].flatMap { $0.isFinite ? $0 : nil } },
            distance: axisDistance(stream.distance),
            stops: stops,
            lapBoundaries: laps
        )

        return PreparedDetail(
            input: input,
            defaultOverlay: defaultOverlay,
            bands: bands,
            line: line,
            routes: routes,
            timeline: timeline,
            timelineOverlays: timelineOverlays(input, bands: bands),
            cursorPower: input.sport.family == .cycling
                ? ColourBanding.trailingMean(stream.power, seconds: DetailRules.cursorPowerSeconds)
                : Array(repeating: nil, count: stream.count)
        )
    }

    /// A ride has a power meter when its power channel has any value.
    public static func hasPowerMeter(_ input: DetailInput) -> Bool {
        input.sport.family == .cycling && ColourBanding.hasValue(input.stream.power)
    }

    // MARK: Route

    /// Track cleanup's steps 1 and 2, or why the activity has no route.
    /// Virtual comes before indoor, and both before looking at positions.
    static func cleanedTrack(_ input: DetailInput) -> Metric<CleanedPositions> {
        if input.isVirtual { return .unavailable(.virtualActivity) }
        if input.isIndoor { return .unavailable(.indoorActivity) }
        let track = TrackCleanup.clean(input.stream, sport: input.sport)
        guard track.points.count >= 2 else { return .unavailable(.noUsablePositions) }
        return .available(track)
    }

    static func simplifiedLine(_ track: Metric<CleanedPositions>) -> Metric<SimplifiedLine> {
        switch track {
        case .available(let track):
            let line = TrackCleanup.simplify(track)
            return line.vertices.count >= 2 ? .available(line) : .unavailable(.noUsablePositions)
        case .unavailable(let reason):
            return .unavailable(reason)
        }
    }

    /// The line with each vertex given the band of its own sample, or
    /// `noValueBand` where that sample has none.
    ///
    /// A vertex that stands for a collapsed stop takes the band of the stop's
    /// first second, where the recorder came to rest, because that is the
    /// sample it was recorded in.
    static func route(line: Metric<SimplifiedLine>, bands: Metric<OverlayBands>) -> Metric<FlyoverRoute> {
        guard let line = line.value else { return .unavailable(line.reason ?? .noUsablePositions) }
        guard let bands = bands.value else { return .unavailable(bands.reason ?? .noUsablePositions) }
        do {
            return .available(try FlyoverRoute(
                vertices: line.coordinates,
                bands: line.sampleIndices.map(bands.viewBand(at:)),
                sampleIndices: line.sampleIndices
            ))
        } catch {
            // Cleanup keeps at least two valid, strictly increasing samples,
            // so this is a stream with an invalid coordinate in it.
            return .unavailable(.noUsablePositions)
        }
    }

    // MARK: Timeline

    /// The stops the timeline can collapse: every stop track cleanup
    /// collapsed, as the half-open range of seconds its point stands for,
    /// together with the paused spans when their positions are known. They
    /// are cut to the stream, sorted, and merged where they overlap or touch.
    ///
    /// Unknown pause positions add nothing, since where the pauses were is
    /// not known.
    public static func stops(collapsed points: [CleanedPosition], pauses: PauseData, count: Int) -> [Range<Int>] {
        var spans = points
            .filter { $0.coveredSamples.count > 1 }
            .map { $0.coveredSamples.lowerBound..<($0.coveredSamples.upperBound + 1) }
        if case .known(let paused) = pauses { spans += paused }
        let cut = spans
            .map { max($0.lowerBound, 0)..<min($0.upperBound, count) }
            .filter { !$0.isEmpty }
            .sorted { $0.lowerBound < $1.lowerBound }
        var merged: [Range<Int>] = []
        for span in cut {
            if let last = merged.last, span.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, span.upperBound)
            } else {
                merged.append(span)
            }
        }
        return merged
    }

    /// The second at which each lap after the first starts.
    ///
    /// From the device's laps when they mark at least one boundary inside
    /// the stream. Otherwise a split every `AnalysisRules.splitDistance`
    /// metres: the first second whose distance is at or past each mark, the
    /// rule the analysis package's splits use, so a second exactly on a mark
    /// opens the next split. With neither, there are none.
    public static func lapBoundaries(lapStarts: [Int], distance: Series, count: Int) -> [Int] {
        let device = Array(Set(lapStarts.filter { $0 > 0 && $0 < count })).sorted()
        if !device.isEmpty { return device }
        let length = AnalysisRules.splitDistance
        var boundaries: [Int] = []
        var next = length
        for second in 0..<min(count, distance.count) {
            guard let metres = distance[second], metres.isFinite, metres >= next else { continue }
            if second > 0 { boundaries.append(second) }
            while metres >= next { next += length }
        }
        return boundaries
    }

    /// The distance the timeline's distance axis is laid out by, or nil when
    /// the stream has no distance.
    ///
    /// The timeline needs a distance for every second, never decreasing, and
    /// cannot take a gap. Reading: a missing second takes the last distance
    /// before it, seconds before the first distance take the first, and a
    /// distance lower than the one before it is held at that one. This is
    /// layout only: the cursor and range stats read the stream itself, so a
    /// missing distance still shows as missing there.
    public static func axisDistance(_ distance: Series) -> [Double]? {
        guard let first = (0..<distance.count).lazy.compactMap({ distance[$0] }).first(where: \.isFinite) else {
            return nil
        }
        var result: [Double] = []
        result.reserveCapacity(distance.count)
        var current = max(first, 0)
        for second in 0..<distance.count {
            if let value = distance[second], value.isFinite { current = max(current, value) }
            result.append(current)
        }
        return result
    }

    /// The overlay series for every kind the activity has values for.
    ///
    /// The values are the stream's own, unsmoothed, so the line shows what
    /// was recorded. The bands are the matching route overlay's, so a second
    /// has the same colour on the timeline as on the map; a zoned overlay
    /// that is unavailable, such as power with no threshold power, is drawn
    /// unzoned. No colours are given: the effort palette is the caller's.
    static func timelineOverlays(
        _ input: DetailInput,
        bands: [RouteOverlay: Metric<OverlayBands>]
    ) -> [TimelineOverlay.Kind: TimelineOverlay] {
        let stream = input.stream
        let speedKind: TimelineOverlay.Kind = input.sport.family == .onFoot ? .pace : .speed
        let kinds: [(TimelineOverlay.Kind, Series, RouteOverlay?)] = [
            (.power, stream.power, .power),
            (.heartRate, stream.heartRate, .heartRate),
            (speedKind, stream.speed, .paceOrSpeed),
            (.cadence, stream.cadence, nil),
        ]
        var overlays: [TimelineOverlay.Kind: TimelineOverlay] = [:]
        for (kind, series, routeOverlay) in kinds where ColourBanding.hasValue(series) {
            if kind == .power, input.sport.family != .cycling { continue }
            overlays[kind] = TimelineOverlay(
                kind: kind,
                values: ColourBanding.values(of: series),
                bands: routeOverlay.flatMap { bands[$0]?.value?.viewBands }
            )
        }
        return overlays
    }
}
