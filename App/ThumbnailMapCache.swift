@preconcurrency import MapLibre
import MapKit
import SweatKitModel

/// Shared, persistent OpenFreeMap resources for activity-feed images only.
/// MapLibre snapshots and offline packs use the same SDK database, so styles,
/// glyphs, sprites and tiles remain usable after the finished PNG is evicted.
@MainActor final class ThumbnailMapCache {
    static let shared = ThumbnailMapCache()
    static let styleVersion = "openfreemap-v1"
    private let storage: MLNOfflineStorage
    private var active = false
    private struct Request {
        let task: Task<SnapshotResult, Error>
        var consumers: Set<UUID>
    }
    private var snapshots: [String: Request] = [:]
    private var retryAfter: [String: Date] = [:]

    private struct PackContext: Codable {
        let key: String
        var accessed: Date
        var bytes: UInt64
    }
    // MapLibre's immutable result is used only on MainActor.
    private struct SnapshotResult: @unchecked Sendable { let value: MLNMapSnapshot }

    init(networkConfiguration: URLSessionConfiguration? = nil) {
        let configuration = networkConfiguration ?? URLSessionConfiguration.ephemeral
        if networkConfiguration == nil { configuration.protocolClasses = [ThumbnailMapNetwork.self] }
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.httpAdditionalHeaders = ["User-Agent": "SweatKit/1.0 (activity map previews)"]
        MLNNetworkConfiguration.sharedManager.sessionConfiguration = configuration
        storage = .shared
        storage.setMaximumAmbientCacheSize(32 * 1024 * 1024) { _ in }
    }

    func snapshot(rect: MKMapRect, size: CGSize, dark: Bool) async throws -> MLNMapSnapshot {
        let key = "\(Self.styleVersion)|\(rect.origin.x)|\(rect.origin.y)|\(rect.size.width)|\(rect.size.height)|\(size.width)|\(size.height)|\(dark)"
        try Task.checkCancellation()
        if let retry = retryAfter[key], retry > Date() { throw URLError(.resourceUnavailable) }
        let consumer = UUID()
        let task: Task<SnapshotResult, Error>
        if var existing = snapshots[key] {
            existing.consumers.insert(consumer)
            snapshots[key] = existing
            task = existing.task
        } else {
            task = Task { SnapshotResult(value: try await self.render(rect: rect, size: size, dark: dark)) }
            snapshots[key] = Request(task: task, consumers: [consumer])
        }
        defer { release(key, consumer: consumer) }
        return try await withTaskCancellationHandler {
            do {
                let result = try await task.value.value
                retryAfter[key] = nil
                try Task.checkCancellation()
                return result
            } catch {
                if !(error is CancellationError) {
                    retryAfter = retryAfter.filter { $0.value > Date() }
                    retryAfter[key] = Date().addingTimeInterval(60)
                }
                throw error
            }
        } onCancel: {
            Task { @MainActor in self.release(key, consumer: consumer) }
        }
    }

    private func release(_ key: String, consumer: UUID) {
        guard var request = snapshots[key], request.consumers.remove(consumer) != nil else { return }
        if request.consumers.isEmpty {
            request.task.cancel()
            snapshots[key] = nil
        } else { snapshots[key] = request }
    }

    private func render(rect: MKMapRect, size: CGSize, dark: Bool) async throws -> MLNMapSnapshot {
        while active { try await Task.sleep(for: .milliseconds(100)) }
        try Task.checkCancellation()
        active = true
        defer { active = false }
        ThumbnailMapNetwork.beginDownload()
        let style = URL(string: "https://tiles.openfreemap.org/styles/\(dark ? "dark" : "positron")")!
        let center = MKMapPoint(x: rect.midX, y: rect.midY).coordinate
        let zoom = max(0, min(16, log2(MKMapSize.world.width / rect.width * size.width / 512)))
        let bounds = MLNCoordinateBounds(
            sw: MKMapPoint(x: rect.minX, y: rect.maxY).coordinate,
            ne: MKMapPoint(x: rect.maxX, y: rect.minY).coordinate)
        let camera = MLNMapCamera(lookingAtCenter: center, altitude: 1_000, pitch: 0, heading: 0)
        let options = MLNMapSnapshotOptions(styleURL: style, camera: camera, size: size)
        options.zoomLevel = zoom
        options.scale = 1
        options.showsLogo = false
        // Attribution lives in the feed, where it remains legible even for 68pt icons.
        options.showsAttribution = false
        let pack = try await preparePack(style: style, bounds: bounds, zoom: zoom, rect: rect)
        defer { pack.suspend() }
        let snapshotter = MLNMapSnapshotter(options: options)
        var result: Result<MLNMapSnapshot, Error>?
        snapshotter.start { snapshot, error in
            if let snapshot { result = .success(snapshot) }
            else { result = .failure(error ?? URLError(.cannotLoadFromNetwork)) }
        }
        defer { snapshotter.cancel() }
        let deadline = Date().addingTimeInterval(20)
        while result == nil {
            guard Date() < deadline else { throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(50))
        }
        return try result!.get()
    }

    private func preparePack(style: URL, bounds: MLNCoordinateBounds, zoom: Double, rect: MKMapRect) async throws -> MLNOfflinePack {
        let deadline = Date().addingTimeInterval(35)
        while storage.packs == nil {
            guard Date() < deadline else { throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(50))
        }
        // Cover neighboring zooms for compact/large regeneration, not a whole city
        // at street-level detail. One source, at most a few hundred tiles per job.
        let low = max(0, floor(zoom) - 1)
        let high = min(16, ceil(zoom) + 1)
        let key = ContentHash(of: Data("\(Self.styleVersion)|\(style)|\(rect)|\(low)|\(high)".utf8)).hex
        let pack: MLNOfflinePack
        if let existing = storage.packs?.first(where: { context($0)?.key == key }) {
            pack = existing
        } else {
            try await trimPacks()
            let region = MLNTilePyramidOfflineRegion(styleURL: style, bounds: bounds, fromZoomLevel: low, toZoomLevel: high)
            let data = try JSONEncoder().encode(PackContext(key: key, accessed: Date(), bytes: 48_000_000))
            pack = try await withCheckedThrowingContinuation { continuation in
                storage.addPack(for: region, withContext: data) { pack, error in
                    if let pack { continuation.resume(returning: pack) }
                    else { continuation.resume(throwing: error ?? URLError(.cannotCreateFile)) }
                }
            }
        }
        do {
            pack.requestProgress()
            while pack.state == .unknown {
                guard Date() < deadline else { throw URLError(.timedOut) }
                try await Task.sleep(for: .milliseconds(50))
            }
            if pack.state != .complete {
                pack.resume()
                defer { pack.suspend() }
                while pack.state != .complete {
                    guard Date() < deadline else { throw URLError(.timedOut) }
                    guard pack.progress.countOfTilesCompleted < 2_800,
                          pack.progress.countOfBytesCompleted < 48_000_000 else {
                        throw URLError(.dataLengthExceedsMaximum)
                    }
                    try await Task.sleep(for: .milliseconds(100))
                }
            }
            let data = try JSONEncoder().encode(PackContext(key: key, accessed: Date(), bytes: pack.progress.countOfBytesCompleted))
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                pack.setContext(data) { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
            return pack
        } catch {
            // Failed/cancelled packs must not pin partially downloaded resources
            // indefinitely. Removing a pack leaves reusable data in ambient cache.
            pack.suspend()
            await withCheckedContinuation { continuation in
                storage.removePack(pack) { _ in continuation.resume() }
            }
            throw error
        }
    }

    private func context(_ pack: MLNOfflinePack) -> PackContext? {
        try? JSONDecoder().decode(PackContext.self, from: pack.context)
    }

    private func trimPacks() async throws {
        var packs = (storage.packs ?? []).compactMap { pack in context(pack).map { (pack, $0) } }
            .sorted { $0.1.accessed < $1.1.accessed }
        var total = packs.reduce(UInt64(0)) { $0 + $1.1.bytes }
        // Reserve a full job's space. The SDK deduplicates resources across packs;
        // summing pack sizes deliberately overestimates actual disk usage.
        while packs.count >= 64 || total > 208 * 1024 * 1024 {
            let (pack, metadata) = packs.removeFirst()
            total -= metadata.bytes
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                storage.removePack(pack) { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
        }
    }
}
