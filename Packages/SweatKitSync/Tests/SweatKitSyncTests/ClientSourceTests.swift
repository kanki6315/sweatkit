import Foundation
import SweatKitGarmin
import SweatKitModel
@testable import SweatKitSync
import Testing

/// Answers HTTP requests from a script, in order. Lets the adapter and
/// `GarminClient`'s token handling run with no network.
actor ScriptedTransport: GarminTransport {
    private var steps: [(status: Int, body: Data)]
    private(set) var requests: [URLRequest] = []

    init(_ steps: [(status: Int, body: Data)]) { self.steps = steps }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !steps.isEmpty else { throw URLError(.resourceUnavailable) }
        let step = steps.removeFirst()
        return (step.body, HTTPURLResponse(url: request.url!, statusCode: step.status, httpVersion: "HTTP/1.1", headerFields: nil)!)
    }

    var paths: [String] { requests.map { $0.url?.path() ?? "" } }
    var authorizations: [String] { requests.map { $0.value(forHTTPHeaderField: "Authorization") ?? "" } }
}

/// The sync engine over `GarminClientSource` and a real `GarminClient`. The key
/// is a made-up string; nothing leaves the process.
@Suite struct ClientSourceTests {
    let token = "/personalapitoken-service/personal-api/personal-api-key/token"
    let search = "/activitylist-service/activities/search/activities"
    let file = "/download-service/files/activity/1"
    let entry = Data(#"[{"activityId":1,"activityName":"Ride","startTimeLocal":"2026-11-01 08:00:00","startTimeGMT":"2026-11-01 08:00:00","duration":3600.0,"elapsedDuration":3600.0,"distance":30000.0,"activityType":{"typeKey":"road_biking"}}]"#.utf8)
    let original = fitBytes(1, version: 1)

    func engine(_ transport: ScriptedTransport, library: InMemoryGarminLibrary) -> GarminSync {
        let client = GarminClient(apiKey: "not-a-real-key", transport: transport, now: { t0 })
        return GarminSync(remote: GarminClientSource(client: client), library: library, clock: TestClock(), calendar: utc)
    }

    @Test func aRefusedKeyStopsTheRunAsKeyRefused() async {
        let transport = ScriptedTransport([(401, Data())])
        let library = InMemoryGarminLibrary(state: settledState())
        let report = await engine(transport, library: library).run(.quick)
        #expect(report.outcome == .keyRefused)
        #expect(await transport.paths == [token])
        #expect(await library.actions.isEmpty)
    }

    @Test func aRefusedTokenIsRenewedAndTheRunCarriesOn() async {
        // The first token is refused by the search; the client gets a second
        // and repeats the search. The ride is then downloaded and ingested.
        let zip = makeZip([ZipItem(name: "1_ACTIVITY.fit", data: original, method: .deflated)])
        let transport = ScriptedTransport([
            (200, Data("first-token".utf8)),
            (401, Data()),
            (200, Data("second-token".utf8)),
            (200, entry),
            (200, zip),
        ])
        let library = InMemoryGarminLibrary(state: settledState())

        let report = await engine(transport, library: library).run(.quick)

        #expect(report.outcome == .completed)
        #expect(report.added == ids(1))
        #expect(await transport.paths == [token, search, token, search, file])
        #expect(await transport.authorizations.filter { $0.hasPrefix("Bearer") } == ["Bearer first-token", "Bearer second-token", "Bearer second-token"])
        #expect(await library.actions == [.ingest(1, ContentHash(of: original))])
        let summary = await library.records[.garminActivity(1)]?.summary
        #expect(summary?.typeKey == "road_biking")
        #expect(summary?.startDate == date("2026-11-01"))
    }

    @Test func aTokenRefusedAgainAfterRenewalStopsTheRunAsTokenRefused() async {
        let transport = ScriptedTransport([
            (200, Data("first-token".utf8)),
            (401, Data()),
            (200, Data("second-token".utf8)),
            (401, Data()),
        ])
        let report = await engine(transport, library: InMemoryGarminLibrary(state: settledState())).run(.quick)
        #expect(report.outcome == .tokenRefused)
    }

    @Test func aRateLimitFromGarminIsHonoured() async {
        let transport = ScriptedTransport([(200, Data("token".utf8)), (429, Data())])
        let library = InMemoryGarminLibrary(state: settledState())
        let report = await engine(transport, library: library).run(.quick)
        guard case .rateLimited = report.outcome else { Issue.record("expected a rate limit, got \(report.outcome)"); return }
        #expect(await library.state?.rateLimitedUntil != nil)
    }
}
