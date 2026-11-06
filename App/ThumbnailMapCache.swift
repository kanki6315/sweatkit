// MapKit callbacks predate Sendable annotations; all snapshot access stays on MainActor.
@preconcurrency import MapKit

/// Short-lived Apple imagery for feed previews. Never persisted or prefetched.
/// The activity-derived route is cached separately by ThumbnailRenderer.
@MainActor final class ThumbnailMapCache {
    static let shared = ThumbnailMapCache()

    private struct Key: Hashable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
        let pixelWidth: Double
        let pixelHeight: Double
        let dark: Bool
    }
    private struct Entry {
        let snapshot: MKMapSnapshotter.Snapshot
        let expires: Date
        var accessed: Date
    }
    // The callback transfers ownership of an immutable snapshot. Consumers only
    // read it on MainActor; MapKit has not annotated Snapshot as Sendable.
    private struct SnapshotResult: @unchecked Sendable {
        let snapshot: MKMapSnapshotter.Snapshot
        init(_ snapshot: MKMapSnapshotter.Snapshot) { self.snapshot = snapshot }
    }
    private struct Request {
        let task: Task<SnapshotResult, Error>
        var consumers: Set<UUID>
    }

    private var entries: [Key: Entry] = [:]
    private var requests: [Key: Request] = [:]
    private var active = 0
    // Engineering limits, not an Apple-specified retention period.
    private let lifetime: TimeInterval = 15 * 60
    private let capacity = 24

    func snapshot(rect: MKMapRect, size: CGSize, dark: Bool) async throws -> MKMapSnapshotter.Snapshot {
        try Task.checkCancellation()
        let key = Key(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height,
                      pixelWidth: size.width, pixelHeight: size.height, dark: dark)
        let now = Date()
        entries = entries.filter { $0.value.expires > now }
        if var entry = entries[key] {
            entry.accessed = now
            entries[key] = entry
            return entry.snapshot
        }
        let consumer = UUID()
        let task: Task<SnapshotResult, Error>
        if var request = requests[key] {
            request.consumers.insert(consumer)
            requests[key] = request
            task = request.task
        } else {
            task = Task { SnapshotResult(try await self.render(rect: rect, size: size, dark: dark, key: key)) }
            requests[key] = Request(task: task, consumers: [consumer])
        }
        defer { release(key, consumer: consumer) }
        return try await withTaskCancellationHandler {
            let result = try await task.value
            try Task.checkCancellation()
            return result.snapshot
        } onCancel: {
            Task { @MainActor in self.release(key, consumer: consumer) }
        }
    }

    private func release(_ key: Key, consumer: UUID) {
        guard var request = requests[key], request.consumers.remove(consumer) != nil else { return }
        if request.consumers.isEmpty {
            request.task.cancel()
            requests[key] = nil
        } else {
            requests[key] = request
        }
    }

    private func render(rect: MKMapRect, size: CGSize, dark: Bool, key: Key) async throws -> MKMapSnapshotter.Snapshot {
        // Waiting requests remain cancellable; local route preparation never waits here.
        while active >= 3 { try await Task.sleep(for: .milliseconds(50)) }
        try Task.checkCancellation()
        active += 1
        defer { active -= 1 }
        let options = MKMapSnapshotter.Options()
        options.mapRect = rect
        options.pointOfInterestFilter = .excludingAll
        options.size = size
        options.scale = 1
        options.traitCollection = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        let snapshotter = MKMapSnapshotter(options: options)
        let timeout = Task { @MainActor in
            try await Task.sleep(for: .seconds(12))
            snapshotter.cancel()
        }
        defer { timeout.cancel() }
        let result: SnapshotResult = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                snapshotter.start(with: .main) { snapshot, error in
                    if let snapshot { continuation.resume(returning: SnapshotResult(snapshot)) }
                    else { continuation.resume(throwing: error ?? URLError(.cannotLoadFromNetwork)) }
                }
            }
        } onCancel: {
            Task { @MainActor in snapshotter.cancel() }
        }
        try Task.checkCancellation()
        let snapshot = result.snapshot
        let expires = Date().addingTimeInterval(lifetime)
        entries[key] = Entry(snapshot: snapshot, expires: expires, accessed: Date())
        if entries.count > capacity, let oldest = entries.min(by: { $0.value.accessed < $1.value.accessed })?.key {
            entries[oldest] = nil
        }
        // Expire even if no further requests arrive. This task holds no imagery.
        Task { @MainActor in
            do { try await Task.sleep(for: .seconds(lifetime)) } catch { return }
            if entries[key]?.expires == expires { entries[key] = nil }
        }
        return snapshot
    }
}
