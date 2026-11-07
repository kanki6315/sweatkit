import Foundation

/// MapLibre uses this transport only. Four in-flight requests means four requests,
/// including HTTP/2 streams (URLSession's connection limit alone cannot ensure that).
final class ThumbnailMapNetwork: URLProtocol, @unchecked Sendable {
    private static let scheduler = Scheduler()
    private var cancelled = false
    private var downloadTask: URLSessionDataTask?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == "https" || request.url?.scheme == "http"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.scheduler.enqueue(self) }
    override func stopLoading() { Self.scheduler.cancel(self) }

    /// Each serialized region/snapshot job has its own conservative download cap.
    static func beginDownload() { scheduler.resetBudget() }

    private final class Scheduler: @unchecked Sendable {
        private let queue = DispatchQueue(label: "SweatKit.map-downloads")
        private let session: URLSession = {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = []
            configuration.urlCache = nil
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 30
            return URLSession(configuration: configuration)
        }()
        private var pending: [ThumbnailMapNetwork] = []
        private var active = 0
        private var requests = 0
        private var bytes = 0

        func resetBudget() { queue.async { self.requests = 0; self.bytes = 0 } }
        func enqueue(_ transport: ThumbnailMapNetwork) {
            queue.async { self.pending.append(transport); self.pump() }
        }
        func cancel(_ transport: ThumbnailMapNetwork) {
            queue.async {
                transport.cancelled = true
                transport.downloadTask?.cancel()
                self.pending.removeAll { $0 === transport }
            }
        }
        private func pump() {
            while active < 4, !pending.isEmpty {
                let transport = pending.removeFirst()
                guard !transport.cancelled else { continue }
                // Count all resources, not just tiles. Leave room below provider limits.
                guard requests < 2_800, bytes < 48_000_000 else {
                    transport.client?.urlProtocol(transport, didFailWithError: URLError(.dataLengthExceedsMaximum))
                    continue
                }
                requests += 1
                active += 1
                var request = transport.request
                request.setValue("SweatKit/1.0 (activity map previews)", forHTTPHeaderField: "User-Agent")
                transport.downloadTask = session.dataTask(with: request) { data, response, error in
                    self.queue.async {
                        self.active -= 1
                        self.bytes += data?.count ?? 0
                        if !transport.cancelled {
                            if let error {
                                transport.client?.urlProtocol(transport, didFailWithError: error)
                            } else if self.bytes > 48_000_000 {
                                transport.client?.urlProtocol(transport, didFailWithError: URLError(.dataLengthExceedsMaximum))
                            } else if let response, let data {
                                transport.client?.urlProtocol(transport, didReceive: response, cacheStoragePolicy: .notAllowed)
                                transport.client?.urlProtocol(transport, didLoad: data)
                                transport.client?.urlProtocolDidFinishLoading(transport)
                            } else {
                                transport.client?.urlProtocol(transport, didFailWithError: URLError(.badServerResponse))
                            }
                        }
                        transport.downloadTask = nil
                        self.pump()
                    }
                }
                transport.downloadTask?.resume()
            }
        }
    }
}
