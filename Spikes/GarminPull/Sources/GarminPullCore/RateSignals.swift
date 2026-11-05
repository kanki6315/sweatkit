import Foundation
import SweatKitGarmin

/// Picks out headers that suggest a rate limit. Garmin documents none for the
/// Personal tier, so this looks for every common convention.
public func rateHeaders(_ headers: [String: String]) -> [String: String] {
    headers.filter { name, _ in
        let name = name.lowercased()
        return name == "retry-after" || name.contains("ratelimit") || name.contains("rate-limit")
            || name.contains("quota") || name.contains("throttl")
    }
}

/// Wraps a transport so requests go one at a time, at least `interval` apart,
/// and nothing is sent after the first 429. JSON bodies can be saved to replace
/// the hand-written test samples, and error bodies to explain refusals. A
/// successful token response is never saved.
public actor PacedTransport: GarminTransport {
    public let interval: Duration
    private let base: any GarminTransport
    private var lastSent: ContinuousClock.Instant?
    private var stopped = false
    private let bodies: URL?
    private var saved = 0

    public struct Stopped: Error, CustomStringConvertible {
        public var description: String { "Stopped after a 429; no further requests are sent." }
    }

    public init(_ base: any GarminTransport = URLSessionTransport(), interval: Duration = .seconds(3), saveJSONBodiesTo bodies: URL? = nil) {
        self.base = base
        self.interval = interval
        self.bodies = bodies
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if stopped { throw Stopped() }
        if let lastSent {
            let wait = interval - (ContinuousClock.now - lastSent)
            if wait > .zero { try await Task.sleep(for: wait) }
        }
        lastSent = .now
        let (data, response) = try await base.send(request)
        if response.statusCode == 429 { stopped = true }
        if let bodies, let path = request.url?.path() {
            let succeeded = (200..<300).contains(response.statusCode)
            let isJSON = response.value(forHTTPHeaderField: "Content-Type")?.contains("json") == true
            // Error bodies explain refusals; a successful token body holds the token.
            if !succeeded || (isJSON && !path.contains("token")) {
                saved += 1
                let name = path.split(separator: "/").suffix(2).joined(separator: "-")
                let suffix = succeeded ? "json" : "error-\(response.statusCode).txt"
                try? data.write(to: bodies.appending(path: "\(String(format: "%02d", saved))-\(name).\(suffix)"))
            }
        }
        return (data, response)
    }
}

/// Appends each exchange to a JSON Lines file. The exchanges hold no secrets.
public final class ExchangeRecorder: Sendable {
    struct Line: Encodable {
        var method: String
        var target: String
        var status: Int
        var bytes: Int
        var headers: [String: String]
        var rateHeaders: [String: String]
    }

    private let url: URL?

    public init(url: URL?) {
        self.url = url
    }

    public func record(_ exchange: GarminExchange) {
        let line = Line(method: exchange.method, target: exchange.target, status: exchange.status, bytes: exchange.bytes, headers: exchange.headers, rateHeaders: rateHeaders(exchange.headers))
        guard let url, var data = try? JSONEncoder().encode(line) else { return }
        data.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}
