import Foundation

/// One request and what came back, with nothing secret in it.
public struct Exchange: Sendable, Encodable {
    public var request: String
    public var status: Int
    public var milliseconds: Int
    public var bytes: Int
    public var headers: [String: String]
    public var rateHeaders: [String: String]
}

public enum ClientError: Error, CustomStringConvertible {
    case rateLimited(Exchange)
    case unauthorized(Exchange)
    case http(Exchange, bodyPreview: String)
    case notHTTP

    public var description: String {
        switch self {
        case .rateLimited(let e):
            "STOPPED: 429 Too Many Requests on \(e.request). Rate headers: \(e.rateHeaders.isEmpty ? "none" : "\(e.rateHeaders)"). No further requests were made."
        case .unauthorized(let e):
            "HTTP \(e.status) on \(e.request): the key or token was refused. Check the key has not expired or been deleted."
        case .http(let e, let preview):
            "HTTP \(e.status) on \(e.request): \(preview)"
        case .notHTTP:
            "The response was not HTTP."
        }
    }
}

/// Sends one request at a time, at least `minimumInterval` apart, logs every
/// exchange and refuses to send anything after the first 429.
public actor PacedClient {
    public let minimumInterval: Duration
    private let session: URLSession
    private let log: URL?
    private var lastSent: ContinuousClock.Instant?
    private var stopped = false
    public private(set) var exchanges: [Exchange] = []

    public init(minimumInterval: Duration = .seconds(3), log: URL? = nil) {
        self.minimumInterval = minimumInterval
        self.log = log
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 60
        session = URLSession(configuration: configuration)
    }

    public func send(_ request: URLRequest) async throws -> (Data, Exchange) {
        if stopped { throw CancellationError() }
        if let lastSent {
            let wait = minimumInterval - (ContinuousClock.now - lastSent)
            if wait > .zero { try await Task.sleep(for: wait) }
        }
        lastSent = .now
        let started = ContinuousClock.now
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.notHTTP }

        let headers = http.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            result["\(pair.key)"] = "\(pair.value)"
        }
        let signals = RateSignals(status: http.statusCode, headers: headers)
        let elapsed = ContinuousClock.now - started
        let exchange = Exchange(
            request: redacted(request),
            status: http.statusCode,
            milliseconds: Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000),
            bytes: data.count,
            headers: loggableHeaders(headers),
            rateHeaders: signals.headers
        )
        exchanges.append(exchange)
        append(exchange)

        switch http.statusCode {
        case 200..<300:
            return (data, exchange)
        case 429:
            stopped = true
            throw ClientError.rateLimited(exchange)
        case 401, 403:
            stopped = true
            throw ClientError.unauthorized(exchange)
        default:
            // Error bodies are short; the first 300 bytes are enough to read the cause.
            throw ClientError.http(exchange, bodyPreview: String(decoding: data.prefix(300), as: UTF8.self))
        }
    }

    private func append(_ exchange: Exchange) {
        guard let log, var line = try? JSONEncoder().encode(exchange) else { return }
        line.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: log) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: log)
        }
    }
}
