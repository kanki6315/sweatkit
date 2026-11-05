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
        .task(id: "\(revision?.hex ?? activity.primary.description)-\(scheme)-\(compact)") {
            finished = false
            preview = try? await ThumbnailRenderer.shared.image(activity: activity, library: library, dark: scheme == .dark, compact: compact)
            finished = true
        }
    }
}

@MainActor private final class ThumbnailRenderer {
    static let shared = ThumbnailRenderer()
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private struct Drawing: Sendable {
        var coordinates: [Coordinate]
        var sparkline: [DetailChartPoint]
        var routeSeconds: [Int]
        var bands: OverlayBands?
        var overlay: RouteOverlay
    }

    func image(activity: ActivityRecord, library: ActivityLibrary, dark: Bool, compact: Bool) async throws -> UIImage? {
        while active >= 3 { await withCheckedContinuation { waiters.append($0) } }
        active += 1
        defer {
            active -= 1
            if !waiters.isEmpty { waiters.removeFirst().resume() }
        }
        try Task.checkCancellation()
        guard let source = try await library.store.sourceRecord(activity.primary), let id = activity.id else { return nil }
        let profile = try await library.profile()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let profileHash = ContentHash(of: try encoder.encode(profile))
        let key = ContentHash(of: Data("thumbnail-v3|\(profileHash.hex)|\(source.currentRevision.hex)|\(activity.sport.rawValue)|\(activity.isIndoor)|\(activity.isVirtual)|\(dark)|\(compact)".utf8))
        let destination = library.store.thumbnailURL(for: source.currentRevision, variant: key)
        if let cached = UIImage(contentsOfFile: destination.path) { return cached }
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
                : RouteOverlay.defaultCandidates(sport: activity.sport, hasPowerMeter: (0..<stream.count).contains { stream.power[$0] != nil })
            let bands = candidates.compactMap { ColourBanding.bands(for: $0, input: input).value }.first
            return Drawing(coordinates: route,
                sparkline: DetailChartSeries.points((0..<series.count).map { series[$0] }, budget: 180), routeSeconds: routeSeconds, bands: bands, overlay: bands?.overlay ?? .plain)
        }.value
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
            let options = MKMapSnapshotter.Options()
            let mapPoints = drawing.coordinates.map { MKMapPoint(CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)) }
            let bounds = mapPoints.reduce(MKMapRect.null) { $0.union(MKMapRect(x: $1.x, y: $1.y, width: 1, height: 1)) }
            options.mapRect = bounds.insetBy(dx: -max(bounds.width * 0.15, 100), dy: -max(bounds.height * 0.15, 100))
            options.pointOfInterestFilter = .excludingAll
            options.size = size
            options.scale = 1
            options.traitCollection = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
            let snapshotter = MKMapSnapshotter(options: options)
            let snapshot = try await snapshotter.start()
            try Task.checkCancellation()
            image = renderer.image { context in
                snapshot.image.draw(at: .zero)
                let path = UIBezierPath()
                for (index, coordinate) in drawing.coordinates.enumerated() {
                    let point = snapshot.point(for: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude))
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                path.lineWidth = 9
                UIColor(white: 0.04, alpha: 0.55).setStroke()
                path.stroke()
                for index in 1..<drawing.coordinates.count {
                    let segment = UIBezierPath()
                    let a = drawing.coordinates[index - 1], b = drawing.coordinates[index]
                    segment.move(to: snapshot.point(for: CLLocationCoordinate2D(latitude: a.latitude, longitude: a.longitude)))
                    segment.addLine(to: snapshot.point(for: CLLocationCoordinate2D(latitude: b.latitude, longitude: b.longitude)))
                    segment.lineWidth = 6
                    segment.lineCapStyle = .round
                    color(at: drawing.routeSeconds[index - 1]).setStroke()
                    segment.stroke()
                }
                if let start = drawing.coordinates.first {
                    let point = snapshot.point(for: CLLocationCoordinate2D(latitude: start.latitude, longitude: start.longitude))
                    let marker = UIBezierPath(ovalIn: CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14))
                    UIColor.white.setFill(); marker.fill()
                    UIColor.darkGray.setStroke(); marker.lineWidth = 3; marker.stroke()
                }
            }
        } else {
            guard !drawing.sparkline.isEmpty else { return nil }
            image = renderer.image { context in
                (dark ? UIColor(white: 0.12, alpha: 1) : UIColor(white: 0.94, alpha: 1)).setFill()
                context.fill(CGRect(origin: .zero, size: size))
                let low = drawing.sparkline.map(\.value).min() ?? 0
                let high = drawing.sparkline.map(\.value).max() ?? 1
                let last = Double(max(1, stream.count - 1))
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
