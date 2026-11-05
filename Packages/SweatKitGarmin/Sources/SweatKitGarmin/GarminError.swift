import Foundation

/// The failures the spec's recovery flows tell apart.
public enum GarminError: Error, Sendable, Equatable {
    /// The token endpoint refused the Personal API key: it is wrong, expired or
    /// deleted. Garmin does not say which. The user needs to enter a new key.
    case keyRejected(status: Int)

    /// A data endpoint refused a token that had just been issued. The client
    /// renews an expired token on its own, so this means renewal did not help.
    case tokenExpired

    /// Garmin answered 429. `retryAfter` is in seconds, when the response said.
    /// Garmin documents no limits for the Personal tier.
    case rateLimited(retryAfter: TimeInterval?)

    /// The request did not complete: offline, timed out, TLS failure and so on.
    case network(URLError.Code)

    /// Garmin answered, but not with something the client can use.
    case unexpectedResponse(UnexpectedResponse)

    /// A request could not be built from the arguments given, such as a negative
    /// offset or an end date before the start date.
    case invalidRequest
}

/// What was wrong with a response. Holds no body content, so it is safe to log.
public struct UnexpectedResponse: Sendable, Equatable {
    public enum Reason: Sendable, Equatable {
        /// A status the client has no specific handling for.
        case status
        /// The body is not the JSON the endpoint documents.
        case undecodableBody
        /// The token response has no token field. Holds the body's key names only.
        case noTokenField(keys: [String])
        /// A download returned no bytes.
        case emptyBody
    }

    public var status: Int
    public var reason: Reason

    public init(status: Int, reason: Reason) {
        self.status = status
        self.reason = reason
    }
}
