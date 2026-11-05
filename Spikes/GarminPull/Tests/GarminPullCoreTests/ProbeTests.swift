import Foundation
@testable import GarminPullCore
import SweatKitGarmin
import Testing

/// Answers every request with the same status.
struct FixedTransport: GarminTransport {
    var status: Int
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(url: request.url ?? URL(filePath: "/"), statusCode: status, httpVersion: nil, headerFields: nil)
        return (Data("[]".utf8), try #require(response))
    }
}

@Suite struct ProbeTests {
    @Test func monthsCoverEveryDay() throws {
        let november = try #require(CalendarMonth("2026-11"))
        #expect(november.firstDay?.description == "2026-11-01")
        #expect(november.lastDay?.description == "2026-11-30")
        #expect(CalendarMonth("2028-02")?.lastDay?.description == "2028-02-29")
        #expect(CalendarMonth("2100-02")?.lastDay?.description == "2100-02-28")
        #expect(CalendarMonth("2026-13") == nil)
        #expect(CalendarMonth("2026-01")?.previous == CalendarMonth("2025-12"))
        #expect(november.query(start: 99) == ActivityQuery(start: 99, startDate: november.firstDay, endDate: november.lastDay))
    }

    @Test func picksOutRateHeaders() {
        let headers = ["retry-after": "120", "x-ratelimit-remaining": "0", "ratelimit-policy": "100;w=3600", "content-type": "application/json"]
        #expect(rateHeaders(headers) == ["retry-after": "120", "x-ratelimit-remaining": "0", "ratelimit-policy": "100;w=3600"])
    }

    @Test func pacingSpacesRequests() async throws {
        let transport = PacedTransport(FixedTransport(status: 200), interval: .milliseconds(200))
        let request = URLRequest(url: try #require(URL(string: "https://example.invalid/")))
        let started = ContinuousClock.now
        _ = try await transport.send(request)
        _ = try await transport.send(request)
        #expect(ContinuousClock.now - started >= .milliseconds(200))
    }

    @Test func nothingIsSentAfterA429() async throws {
        let transport = PacedTransport(FixedTransport(status: 429), interval: .zero)
        let request = URLRequest(url: try #require(URL(string: "https://example.invalid/")))
        let (_, first) = try await transport.send(request)
        #expect(first.statusCode == 429)
        await #expect(throws: PacedTransport.Stopped.self) { try await transport.send(request) }
    }
}
