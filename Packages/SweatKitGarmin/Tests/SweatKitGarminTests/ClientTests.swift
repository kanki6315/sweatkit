import Foundation
import Synchronization
@testable import SweatKitGarmin
import Testing

/// Answers requests from a script, in order, and keeps what was sent.
actor ScriptedTransport: GarminTransport {
    enum Step {
        case respond(status: Int, body: Data, headers: [String: String] = [:])
        case fail(any Error)
    }

    private var steps: [Step]
    private(set) var requests: [URLRequest] = []

    init(_ steps: [Step]) {
        self.steps = steps
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !steps.isEmpty else { throw URLError(.resourceUnavailable) }
        switch steps.removeFirst() {
        case .respond(let status, let body, let headers):
            let response = HTTPURLResponse(url: request.url ?? URL(filePath: "/"), statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)
            return (body, try #require(response))
        case .fail(let error):
            throw error
        }
    }

    var authorizations: [String] { requests.map { $0.value(forHTTPHeaderField: "Authorization") ?? "" } }
    var targets: [String] { requests.map { $0.url?.path() ?? "" } }
}

final class TestClock: Sendable {
    private let current = Mutex(Date(timeIntervalSince1970: 1_800_000_000))
    var now: Date { current.withLock { $0 } }
    func advance(_ seconds: TimeInterval) { current.withLock { $0.addTimeInterval(seconds) } }
}

final class ExchangeLog: Sendable {
    private let entries = Mutex<[GarminExchange]>([])
    var all: [GarminExchange] { entries.withLock { $0 } }
    func append(_ exchange: GarminExchange) { entries.withLock { $0.append(exchange) } }
}

let key = "sample-key-0123456789"
let tokenPath = "/personalapitoken-service/personal-api/personal-api-key/token"
let searchPath = "/activitylist-service/activities/search/activities"

func tokenStep(_ value: String, expiresIn: Int = 86400) -> ScriptedTransport.Step {
    .respond(status: 200, body: Data(#"{"access_token":"\#(value)","token_type":"Bearer","expires_in":\#(expiresIn)}"#.utf8))
}

let emptyPage = ScriptedTransport.Step.respond(status: 200, body: Data("[]".utf8))

@Suite struct ClientTests {
    let clock = TestClock()

    func client(_ transport: ScriptedTransport, log: ExchangeLog? = nil) -> GarminClient {
        let clock = clock
        var observer: GarminClient.Observer?
        if let log { observer = { log.append($0) } }
        return GarminClient(apiKey: key, transport: transport, now: { clock.now }, observer: observer)
    }

    @Test func exchangesTheKeyOnceAndReusesTheToken() async throws {
        let transport = ScriptedTransport([tokenStep("t1"), emptyPage, emptyPage])
        let client = client(transport)
        _ = try await client.activities(.newest)
        _ = try await client.activities(.earliest)
        #expect(await transport.targets == [tokenPath, searchPath, searchPath])
        #expect(await transport.authorizations == ["ApiKey \(key)", "Bearer t1", "Bearer t1"])
        #expect(await client.tokenExpiry == clock.now.addingTimeInterval(86400))
    }

    @Test func renewsATokenShortlyBeforeItExpires() async throws {
        let transport = ScriptedTransport([tokenStep("t1", expiresIn: 3600), emptyPage, emptyPage, tokenStep("t2"), emptyPage])
        let client = client(transport)
        _ = try await client.activities(.newest)
        clock.advance(3600 - GarminClient.renewalMargin - 1)
        _ = try await client.activities(.newest)
        clock.advance(2)
        _ = try await client.activities(.newest)
        #expect(await transport.authorizations == ["ApiKey \(key)", "Bearer t1", "Bearer t1", "ApiKey \(key)", "Bearer t2"])
    }

    @Test func aRefusedTokenIsRenewedOnceAndTheCallRetried() async throws {
        let transport = ScriptedTransport([
            tokenStep("t1"),
            .respond(status: 401, body: Data()),
            tokenStep("t2"),
            .respond(status: 200, body: try sample("activities-month")),
        ])
        let entries = try await client(transport).activities(.newest)
        #expect(entries.count == 2)
        #expect(await transport.authorizations == ["ApiKey \(key)", "Bearer t1", "ApiKey \(key)", "Bearer t2"])
    }

    @Test func aFreshTokenThatIsAlsoRefusedIsTokenExpired() async throws {
        let transport = ScriptedTransport([tokenStep("t1"), .respond(status: 401, body: Data()), tokenStep("t2"), .respond(status: 401, body: Data())])
        await #expect(throws: GarminError.tokenExpired) { try await client(transport).activities(.newest) }
        #expect(await transport.requests.count == 4)
    }

    @Test(arguments: [400, 401, 403])
    func aRefusedKeyIsKeyRejected(status: Int) async throws {
        let transport = ScriptedTransport([.respond(status: status, body: Data())])
        await #expect(throws: GarminError.keyRejected(status: status)) { try await client(transport).activities(.newest) }
        #expect(await transport.requests.count == 1)
    }

    /// A key deleted after its token was issued: the data call is refused, and so
    /// is the renewal, which is the key's problem rather than the token's.
    @Test func aKeyDeletedMidSessionIsKeyRejected() async throws {
        let transport = ScriptedTransport([tokenStep("t1"), .respond(status: 401, body: Data()), .respond(status: 401, body: Data())])
        await #expect(throws: GarminError.keyRejected(status: 401)) { try await client(transport).activities(.newest) }
    }

    @Test func rateLimitingCarriesRetryAfter() async throws {
        let transport = ScriptedTransport([tokenStep("t1"), .respond(status: 429, body: Data(), headers: ["Retry-After": "120"])])
        await #expect(throws: GarminError.rateLimited(retryAfter: 120)) { try await client(transport).activities(.newest) }

        let onToken = ScriptedTransport([.respond(status: 429, body: Data())])
        await #expect(throws: GarminError.rateLimited(retryAfter: nil)) { try await client(onToken).activities(.newest) }
    }

    @Test func retryAfterAsAnHTTPDate() async throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        let header = formatter.string(from: clock.now.addingTimeInterval(90))
        let transport = ScriptedTransport([tokenStep("t1"), .respond(status: 429, body: Data(), headers: ["Retry-After": header])])
        await #expect(throws: GarminError.rateLimited(retryAfter: 90)) { try await client(transport).activities(.newest) }
    }

    @Test func networkFailuresKeepTheirCode() async throws {
        let transport = ScriptedTransport([.fail(URLError(.notConnectedToInternet))])
        await #expect(throws: GarminError.network(.notConnectedToInternet)) { try await client(transport).activities(.newest) }

        let midway = ScriptedTransport([tokenStep("t1"), .fail(URLError(.timedOut))])
        await #expect(throws: GarminError.network(.timedOut)) { try await client(midway).activity(id: 1) }
    }

    @Test func unexpectedStatusesAndBodies() async throws {
        let serverError = ScriptedTransport([tokenStep("t1"), .respond(status: 500, body: Data())])
        await #expect(throws: GarminError.unexpectedResponse(UnexpectedResponse(status: 500, reason: .status))) {
            try await client(serverError).activities(.newest)
        }

        let notJSON = ScriptedTransport([tokenStep("t1"), .respond(status: 200, body: Data("<html>".utf8))])
        await #expect(throws: GarminError.unexpectedResponse(UnexpectedResponse(status: 200, reason: .undecodableBody))) {
            try await client(notJSON).activities(.newest)
        }

        let wrongShape = ScriptedTransport([tokenStep("t1"), .respond(status: 200, body: Data(#"{"activityId":"x"}"#.utf8))])
        await #expect(throws: GarminError.unexpectedResponse(UnexpectedResponse(status: 200, reason: .undecodableBody))) {
            try await client(wrongShape).activity(id: 1)
        }
    }

    @Test func downloadsReturnTheBytesAsServed() async throws {
        let bytes = Data([0x50, 0x4B, 0x03, 0x04, 0x00, 0x01, 0x02])
        let transport = ScriptedTransport([
            tokenStep("t1"),
            .respond(status: 200, body: bytes, headers: ["Content-Type": "application/x-zip-compressed", "Content-Disposition": #"attachment; filename="24906063494.zip""#]),
        ])
        let file = try await client(transport).originalFile(activityID: 24906063494)
        #expect(file == ActivityFile(activityID: 24906063494, data: bytes, contentType: "application/x-zip-compressed", suggestedFilename: "24906063494.zip"))
    }

    @Test func anEmptyDownloadIsUnexpected() async throws {
        let transport = ScriptedTransport([tokenStep("t1"), .respond(status: 200, body: Data())])
        await #expect(throws: GarminError.unexpectedResponse(UnexpectedResponse(status: 200, reason: .emptyBody))) {
            try await client(transport).originalFile(activityID: 1)
        }
    }

    @Test func concurrentCallsShareOneTokenExchange() async throws {
        let transport = ScriptedTransport([tokenStep("t1"), emptyPage, emptyPage, emptyPage])
        let client = client(transport)
        async let a = client.activities(.newest)
        async let b = client.activities(.earliest)
        async let c = client.activity(id: 1).activityId
        _ = try await (a, b)
        _ = try? await c
        #expect(await transport.targets.filter { $0 == tokenPath }.count == 1)
    }

    @Test func validateKeyAlwaysExchangesAFreshToken() async throws {
        let transport = ScriptedTransport([tokenStep("t1"), tokenStep("t2")])
        let client = client(transport)
        try await client.validateKey()
        try await client.validateKey()
        #expect(await transport.targets == [tokenPath, tokenPath])
        #expect(await client.tokenResponseKeys == ["access_token", "expires_in", "token_type"])
    }

    @Test func theObserverSeesEveryResponseAndNoSecret() async throws {
        let log = ExchangeLog()
        let transport = ScriptedTransport([
            tokenStep("secret-token-value"),
            .respond(status: 429, body: Data(), headers: ["Retry-After": "60", "Set-Cookie": "session=abc", "X-RateLimit-Remaining": "0"]),
        ])
        _ = try? await client(transport, log: log).activities(.newest)

        let exchanges = log.all
        #expect(exchanges.map(\.status) == [200, 429])
        #expect(exchanges.map(\.method) == ["POST", "GET"])
        #expect(exchanges[1].headers["retry-after"] == "60")
        #expect(exchanges[1].headers["x-ratelimit-remaining"] == "0")
        #expect(exchanges[1].headers["set-cookie"] == "<redacted>")
        let everything = exchanges.map { "\($0)" }.joined()
        #expect(!everything.contains(key))
        #expect(!everything.contains("secret-token-value"))
    }
}
