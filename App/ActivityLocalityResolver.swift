import Foundation
import MapKit
import SweatKitLibrary
import SweatKitModel

/// One best-effort lookup at a time, after the feed is already visible. Imports
/// and sync never wait for Apple's geocoder. A later refresh retries failures.
@MainActor
final class ActivityLocalityResolver {
    private var queued: [SourceIdentity] = []
    private var scheduled: Set<SourceIdentity> = []
    private var visited: Set<SourceIdentity> = []
    private var retryAfter: [SourceIdentity: Date] = [:]
    private var worker: Task<Void, Never>?

    func enqueue(_ ids: [SourceIdentity], library: ActivityLibrary, didChange: @escaping @MainActor () async -> Void) {
        for id in ids where !scheduled.contains(id) && !visited.contains(id) && (retryAfter[id] ?? .distantPast) <= .now {
            queued.append(id)
            scheduled.insert(id)
        }
        guard worker == nil, !queued.isEmpty else { return }
        worker = Task {
            var changed = false
            while !queued.isEmpty && !Task.isCancelled {
                let id = queued.removeFirst()
                visited.insert(id)
                do {
                    if let request = try await library.localityRequest(for: id) {
                        let location = CLLocation(latitude: request.coordinate.latitude, longitude: request.coordinate.longitude)
                        guard let geocoder = MKReverseGeocodingRequest(location: location) else {
                            scheduled.remove(id)
                            retryAfter[id] = .now.addingTimeInterval(300)
                            continue
                        }
                        let items = try await geocoder.mapItems
                        try Task.checkCancellation()
                        // Use a locality, never a street address or the user's
                        // current position. No location permission is requested.
                        let name = items.lazy.compactMap { $0.addressRepresentations?.cityName }.first
                        if try await library.setLocality(name, for: request) { changed = true }
                        // Keep large libraries from issuing a burst of requests.
                        try await Task.sleep(for: .seconds(1))
                    }
                } catch {
                    // Offline or rate-limited geocoding must not replace an
                    // import/sync result with an unrelated network error.
                    retryAfter[id] = .now.addingTimeInterval(300)
                }
                scheduled.remove(id)
            }
            visited.removeAll()
            worker = nil
            if changed && !Task.isCancelled { await didChange() }
        }
    }
}
