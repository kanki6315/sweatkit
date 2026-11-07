import SwiftUI
import MapKit
import SweatKitDetail
import SweatKitLibrary
import SweatKitModel
import SweatKitStore
import SweatKitTrackCleanup
import SweatKitPalette

struct ActivityThumbnail: View {
    let activity: ActivityRecord
    let library: ActivityLibrary
    let revision: ContentHash?
    var compact = false
    @Environment(\.colorScheme) private var scheme
    @State private var preview: UIImage?
    @State private var finished = false
    @State private var requestedKey: String?

    private var thumbnailKey: String { "\(revision?.hex ?? activity.primary.description)-\(scheme)-\(compact)" }

    var body: some View {
        Group {
            if let preview { Image(uiImage: preview).resizable().scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: .secondarySystemBackground)) }
            else if finished {
                Image(systemName: activity.sport.family == .cycling ? "figure.outdoor.cycle" : "figure.walk")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: .secondarySystemBackground))
            } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .clipped()
        .accessibilityHidden(true)
        .task(id: thumbnailKey) {
            if requestedKey != thumbnailKey {
                preview = nil
                requestedKey = thumbnailKey
            }
            finished = false
            do {
                let image = try await ThumbnailRenderer.shared.image(activity: activity, library: library, dark: scheme == .dark, compact: compact) { image in
                    guard !Task.isCancelled else { return }
                    // Keep an existing enriched preview while the task resumes.
                    if preview == nil { preview = image }
                }
                guard !Task.isCancelled else { return }
                if let image { preview = image }
                finished = true
            } catch {
                guard !Task.isCancelled else { return }
                // Preserve the local route if map loading or cache persistence fails.
                finished = true
            }
        }
    }
}

@MainActor private final class ThumbnailRenderer {
    static let shared = ThumbnailRenderer()

    private struct Drawing: Sendable {
        var coordinates: [Coordinate]
        var sparkline: [DetailChartPoint]
        var routeSeconds: [Int]
        var bands: OverlayBands?
        var overlay: RouteOverlay
    }

    private final class PreparedDrawing {
        let drawing: Drawing
        let sampleCount: Int
        init(_ drawing: Drawing, sampleCount: Int) {
            self.drawing = drawing
            self.sampleCount = sampleCount
        }
    }
    // Cache only activity-derived geometry, never Apple map imagery. Revisiting
    // rows should not decode and analyse hours of samples again.
    private let drawings: NSCache<NSString, PreparedDrawing> = {
        let cache = NSCache<NSString, PreparedDrawing>()
        cache.countLimit = 100
        cache.totalCostLimit = 16 * 1024 * 1024
        return cache
    }()

    func image(activity: ActivityRecord, library: ActivityLibrary, dark: Bool, compact: Bool,
               onPreview: (UIImage) -> Void) async throws -> UIImage? {
        try Task.checkCancellation()
        guard let source = try await library.store.sourceRecord(activity.primary), let id = activity.id else { return nil }
        let profile = try await library.profile()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let profileHash = ContentHash(of: try encoder.encode(profile))
        let key = ContentHash(of: Data("route-thumbnail-v4|\(profileHash.hex)|\(source.currentRevision.hex)|\(activity.sport.rawValue)|\(activity.isIndoor)|\(activity.isVirtual)|\(dark)|\(compact)".utf8))
        let destination = library.store.thumbnailURL(for: source.currentRevision, variant: key)
        let cachedData = await Task.detached(priority: .utility) {
            try? Data(contentsOf: destination)
        }.value
        let cached = cachedData.flatMap { UIImage(data: $0) }
        if let cached { onPreview(cached) }
        // Indoor previews are complete on disk; they need no map enrichment.
        if let cached, activity.isIndoor || activity.isVirtual || !activity.sport.hasFullSupport { return cached }
        let prepared: PreparedDrawing
        if let existing = drawings.object(forKey: key.hex as NSString) {
            prepared = existing
        } else {
            let stream = try await library.analysisStream(for: id)
            let drawing = await Task.detached(priority: .utility) {
                let route: [Coordinate]
                let routeSeconds: [Int]
                if activity.isIndoor || activity.isVirtual || !activity.sport.hasFullSupport { route = []; routeSeconds = [] }
                else {
                    let line = TrackCleanup.simplify(TrackCleanup.clean(stream, sport: activity.sport))
                    route = line.coordinates
                    routeSeconds = line.sampleIndices
                }
                let hasPower = (0..<stream.count).contains { stream.power[$0] != nil }
                let series = hasPower ? stream.power : stream.heartRate
                let input = DetailInput(stream: stream, sport: activity.sport, profile: profile, activityDate: activity.start)
                let candidates = route.isEmpty
                    ? (hasPower ? [RouteOverlay.power, .plain] : [.heartRate, .plain])
                    : RouteOverlay.defaultCandidates(sport: activity.sport, hasPowerMeter: hasPower)
                let bands = candidates.lazy.compactMap { ColourBanding.bands(for: $0, input: input).value }.first
                return Drawing(coordinates: route,
                    sparkline: DetailChartSeries.points((0..<series.count).map { series[$0] }, budget: 180), routeSeconds: routeSeconds, bands: bands, overlay: bands?.overlay ?? .plain)
            }.value
            try Task.checkCancellation()
            prepared = PreparedDrawing(drawing, sampleCount: stream.count)
            drawings.setObject(prepared, forKey: key.hex as NSString,
                               cost: drawing.coordinates.count * 32 + drawing.sparkline.count * 32 + stream.count * 16)
        }
        let drawing = prepared.drawing
        try Task.checkCancellation()
        let size = compact ? CGSize(width: 216, height: 216) : CGSize(width: 720, height: 360)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let ink = dark ? UIColor.white : UIColor.black
        let palette: [RampColor] = switch drawing.overlay {
        case .power: EffortPalette.power
        case .heartRate: EffortPalette.heartRate
        case .paceOrSpeed: EffortPalette.pace
        case .gradient: EffortPalette.gradient
        case .plain: []
        }
        func color(at second: Int) -> UIColor {
            guard let bands = drawing.bands, bands.bands.indices.contains(second),
                  let band = bands.bands[second], palette.indices.contains(band) else { return ink }
            let rgb = palette[band].components
            return UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        }
        let image: UIImage
        if drawing.coordinates.count >= 2 {
            let mapPoints = drawing.coordinates.map { MKMapPoint(CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)) }
            let bounds = mapPoints.reduce(MKMapRect.null) { $0.union(MKMapRect(x: $1.x, y: $1.y, width: 1, height: 1)) }
            let padded = bounds.insetBy(dx: -max(bounds.width * 0.15, 100), dy: -max(bounds.height * 0.15, 100))
            // Fit the same north-up Mercator framing before and after map loading.
            let width = max(padded.width, padded.height * size.width / size.height)
            let height = width * size.height / size.width
            let rect = MKMapRect(x: padded.midX - width / 2, y: padded.midY - height / 2, width: width, height: height)
            func render(snapshot: MKMapSnapshotter.Snapshot?) -> UIImage {
                func point(for coordinate: Coordinate) -> CGPoint {
                    let location = CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
                    if let snapshot { return snapshot.point(for: location) }
                    let point = MKMapPoint(location)
                    return CGPoint(x: (point.x - rect.minX) / rect.width * size.width,
                                   y: (point.y - rect.minY) / rect.height * size.height)
                }
                return renderer.image { context in
                    if let snapshot { snapshot.image.draw(at: .zero) }
                    else {
                        (dark ? UIColor(white: 0.12, alpha: 1) : UIColor(white: 0.94, alpha: 1)).setFill()
                        context.fill(CGRect(origin: .zero, size: size))
                    }
                    let path = UIBezierPath()
                    for (index, coordinate) in drawing.coordinates.enumerated() {
                        let point = point(for: coordinate)
                        if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                    path.lineWidth = 9
                    UIColor(white: 0.04, alpha: 0.55).setStroke()
                    path.stroke()
                    for index in 1..<drawing.coordinates.count {
                        let segment = UIBezierPath()
                        let a = drawing.coordinates[index - 1], b = drawing.coordinates[index]
                        segment.move(to: point(for: a))
                        segment.addLine(to: point(for: b))
                        segment.lineWidth = 6
                        segment.lineCapStyle = .round
                        color(at: drawing.routeSeconds[index - 1]).setStroke()
                        segment.stroke()
                    }
                    if let start = drawing.coordinates.first {
                        let point = point(for: start)
                        let marker = UIBezierPath(ovalIn: CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14))
                        UIColor.white.setFill(); marker.fill()
                        UIColor.darkGray.setStroke(); marker.lineWidth = 3; marker.stroke()
                    }
                }
            }
            let local = cached ?? render(snapshot: nil)
            onPreview(local)
            if cached == nil, let png = local.pngData() {
                try? await library.store.saveThumbnail(png, for: source.currentRevision, variant: key)
            }
            try Task.checkCancellation()
            guard let snapshot = try? await ThumbnailMapCache.shared.snapshot(rect: rect, size: size, dark: dark) else {
                return local
            }
            try Task.checkCancellation()
            return render(snapshot: snapshot)
        } else {
            if let cached { return cached }
            guard !drawing.sparkline.isEmpty else { return nil }
            image = renderer.image { context in
                (dark ? UIColor(white: 0.12, alpha: 1) : UIColor(white: 0.94, alpha: 1)).setFill()
                context.fill(CGRect(origin: .zero, size: size))
                let low = drawing.sparkline.map(\.value).min() ?? 0
                let high = drawing.sparkline.map(\.value).max() ?? 1
                let last = Double(max(1, prepared.sampleCount - 1))
                var previous: CGPoint?
                var segment: Int?
                for point in drawing.sparkline {
                    let location = CGPoint(x: 16 + Double(point.second) / last * (size.width - 32),
                        y: size.height - 16 - (point.value - low) / max(high - low, 1) * (size.height - 32))
                    if segment == point.segment, let previous {
                        let path = UIBezierPath()
                        path.move(to: previous); path.addLine(to: location)
                        path.lineWidth = 5; path.lineCapStyle = .round
                        color(at: point.second).setStroke(); path.stroke()
                    }
                    previous = location
                    segment = point.segment
                }

            }
        }
        if let png = image.pngData() { try await library.store.saveThumbnail(png, for: source.currentRevision, variant: key) }
        return image
    }
}
