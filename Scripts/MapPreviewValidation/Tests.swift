import Foundation
import MapKit
@preconcurrency import MapLibre
import Synchronization
import Testing
@testable import MapPreviewHarness

/// Blocks at the SDK transport boundary, without changing the simulator's
/// networking or any other app. Online requests still use production throttling.
final class NetworkGate: URLProtocol, @unchecked Sendable {
    struct State { var offline = false; var onlineRequests = 0; var blockedRequests = 0 }
    static let state = Mutex(State())
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ThumbnailMapNetwork.self]
        return URLSession(configuration: configuration)
    }()
    private var download: URLSessionDataTask?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let offline = Self.state.withLock { state in
            if state.offline { state.blockedRequests += 1 } else { state.onlineRequests += 1 }
            return state.offline
        }
        if offline {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        download = Self.session.dataTask(with: request) { data, response, error in
            if let error { self.client?.urlProtocol(self, didFailWithError: error) }
            else if let response, let data {
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: data)
                self.client?.urlProtocolDidFinishLoading(self)
            }
        }
        download?.resume()
    }
    override func stopLoading() { download?.cancel() }
}

@Test @MainActor func snapshotsRegenerateOffline() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [NetworkGate.self]
    let cache = ThumbnailMapCache(networkConfiguration: configuration)
    let marker = URL.documentsDirectory.appending(path: "map-preview-offline-ready")
    let offlineOnly = FileManager.default.fileExists(atPath: marker.path)
    NetworkGate.state.withLock { $0 = NetworkGate.State(offline: offlineOnly) }
    if !offlineOnly {
        while MLNOfflineStorage.shared.packs == nil { try await Task.sleep(for: .milliseconds(50)) }
        for pack in MLNOfflineStorage.shared.packs ?? [] {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                MLNOfflineStorage.shared.removePack(pack) { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            MLNOfflineStorage.shared.clearAmbientCache { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }
    let center = MKMapPoint(CLLocationCoordinate2D(latitude: 40.771, longitude: -73.974))
    let rect = MKMapRect(x: center.x - 12_000, y: center.y - 6_000, width: 24_000, height: 12_000)
    let output = URL.documentsDirectory.appending(path: "MapPreviewValidation")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    if !offlineOnly {
        for dark in [false, true] {
            let snapshot = try await cache.snapshot(rect: rect, size: CGSize(width: 720, height: 360), dark: dark)
            try #require(snapshot.image.pngData()).write(to: output.appending(path: "online-\(dark).png"))
        }
    }
    let downloaded = NetworkGate.state.withLock { state in state.offline = true; return state.onlineRequests }
    #expect(offlineOnly ? downloaded == 0 : downloaded > 0)
    // No PNG/memory snapshot cache in this service: every call invokes the renderer.
    // Different dimensions force a genuinely new output from retained resources.
    for dark in [false, true] {
        let snapshot = try await cache.snapshot(rect: rect, size: CGSize(width: 700, height: 350), dark: dark)
        #expect(snapshot.image.size == CGSize(width: 700, height: 350))
        let centerPixel = snapshot.point(for: center.coordinate)
        #expect(abs(centerPixel.x - 350) < 1)
        #expect(abs(centerPixel.y - 175) < 1)
        let png = try #require(snapshot.image.pngData())
        #expect(png.count > 10_000) // A blank background must not count as success.
        try png.write(to: output.appending(path: "offline-\(dark).png"))
    }
    #expect(NetworkGate.state.withLock { $0.onlineRequests } == downloaded)
    let packs = try #require(MLNOfflineStorage.shared.packs)
    #expect(packs.count >= 2)
    #expect(packs.allSatisfy { $0.state == .complete })
    try Data().write(to: marker)
    print("OFFLINE SNAPSHOTS PASSED (relaunch: \(offlineOnly)): \(downloaded) online requests, \(NetworkGate.state.withLock { $0.blockedRequests }) blocked; output \(output.path)")
}

@Test func imageCacheEvictsOldestAndSurvivesRecreation() async throws {
    let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let first = root.appending(path: "first.png")
    let second = root.appending(path: "second.png")
    let third = root.appending(path: "third.png")
    let cache = ThumbnailImageCache(budget: 8)
    try Data([1, 1, 1, 1]).write(to: first)
    try await Task.sleep(for: .milliseconds(20))
    try Data([2, 2, 2, 2]).write(to: second)
    try await Task.sleep(for: .milliseconds(20))
    #expect(await cache.read(first) == Data([1, 1, 1, 1]))
    try await Task.sleep(for: .milliseconds(20))
    try Data([3, 3, 3, 3]).write(to: third)
    try await cache.trim(directory: root)
    let reopened = ThumbnailImageCache(budget: 8)
    #expect(await reopened.read(second) == nil)
    #expect(await reopened.read(first) != nil)
    #expect(await reopened.read(third) != nil)
}
