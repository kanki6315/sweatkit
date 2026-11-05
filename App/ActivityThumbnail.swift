import SwiftUI
import MapKit
import SweatKitDetail
import SweatKitLibrary
import SweatKitModel
import SweatKitStore
import SweatKitTrackCleanup

struct ActivityThumbnail: View {
    let activity: ActivityRecord
    let library: ActivityLibrary
    let revision: ContentHash?
    @Environment(\.colorScheme) private var scheme
    @State private var preview: UIImage?
    @State private var finished = false

    var body: some View {
        Group {
            if let preview { Image(uiImage: preview).resizable().scaledToFill() }
            else if finished {
                Image(systemName: activity.sport.family == .cycling ? "figure.outdoor.cycle" : "figure.walk")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: .secondarySystemBackground))
            } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .clipped()
        .accessibilityHidden(true)
        .task(id: "\(revision?.hex ?? activity.primary.description)-\(scheme)") {
            finished = false
            preview = try? await ThumbnailRenderer.shared.image(activity: activity, library: library, dark: scheme == .dark)
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
    }

    func image(activity: ActivityRecord, library: ActivityLibrary, dark: Bool) async throws -> UIImage? {
        while active >= 3 { await withCheckedContinuation { waiters.append($0) } }
        active += 1
        defer {
            active -= 1
            if !waiters.isEmpty { waiters.removeFirst().resume() }
        }
        try Task.checkCancellation()
        guard let source = try await library.store.sourceRecord(activity.primary), let id = activity.id else { return nil }
        let key = ContentHash(of: Data("thumbnail-v1|\(source.currentRevision.hex)|\(activity.sport.rawValue)|\(activity.isIndoor)|\(activity.isVirtual)|\(dark)".utf8)).hex
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("SweatKitThumbnails")
        let destination = directory.appendingPathComponent(key + ".png")
        if let cached = UIImage(contentsOfFile: destination.path) { return cached }
        let stream = try await library.analysisStream(for: id)
        let drawing = await Task.detached(priority: .utility) {
            let route: [Coordinate]
            if activity.isIndoor || activity.isVirtual || !activity.sport.hasFullSupport { route = [] }
            else { route = TrackCleanup.simplify(TrackCleanup.clean(stream, sport: activity.sport)).coordinates }
            let series = (0..<stream.count).contains(where: { stream.power[$0] != nil }) ? stream.power : stream.heartRate
            return Drawing(coordinates: route,
                sparkline: DetailChartSeries.points((0..<series.count).map { series[$0] }, budget: 180))
        }.value
        try Task.checkCancellation()
        let size = CGSize(width: 288, height: 180)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let ink = dark ? UIColor.white : UIColor.black
        let image: UIImage
        if drawing.coordinates.count >= 2 {
            let options = MKMapSnapshotter.Options()
            let mapPoints = drawing.coordinates.map { MKMapPoint(CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)) }
            let bounds = mapPoints.reduce(MKMapRect.null) { $0.union(MKMapRect(x: $1.x, y: $1.y, width: 1, height: 1)) }
            options.mapRect = bounds.insetBy(dx: -max(bounds.width * 0.15, 100), dy: -max(bounds.height * 0.15, 100))
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
                path.lineWidth = 5
                (dark ? UIColor.black : UIColor.white).setStroke()
                path.stroke()
                path.lineWidth = 3
                ink.setStroke()
                path.stroke()
            }
        } else {
            guard !drawing.sparkline.isEmpty else { return nil }
            image = renderer.image { context in
                (dark ? UIColor(white: 0.12, alpha: 1) : UIColor(white: 0.94, alpha: 1)).setFill()
                context.fill(CGRect(origin: .zero, size: size))
                let low = drawing.sparkline.map(\.value).min() ?? 0
                let high = drawing.sparkline.map(\.value).max() ?? 1
                let last = Double(max(1, stream.count - 1))
                let path = UIBezierPath()
                var segment: Int?
                for point in drawing.sparkline {
                    let location = CGPoint(x: 10 + Double(point.second) / last * 268,
                        y: 170 - (point.value - low) / max(high - low, 1) * 160)
                    if segment != point.segment { path.move(to: location) } else { path.addLine(to: location) }
                    segment = point.segment
                }
                path.lineWidth = 3
                ink.setStroke()
                path.stroke()
            }
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let png = image.pngData() { try png.write(to: destination, options: .atomic) }
        return image
    }
}
