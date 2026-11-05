import Foundation
@testable import SweatKitGarmin
import Testing

func sample(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Samples"))
    return try Data(contentsOf: url)
}

@Suite struct ResponseTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func decodesASearchPageAndIgnoresUnknownFields() throws {
        let entries = try JSONDecoder().decode([ActivitySummary].self, from: sample("activities-month"))
        #expect(entries.map(\.activityId) == [24906063494, 24830689204])

        let zwift = entries[0]
        #expect(zwift.activityType?.typeKey == "virtual_ride")
        #expect(zwift.manufacturer == "ZWIFT")
        #expect(zwift.startDate == CalendarDate(year: 2026, month: 10, day: 14))
        #expect(zwift.startTime == Date(timeIntervalSince1970: 1_792_112_531))
        #expect(zwift.elapsedDuration == 2408)
        #expect(zwift.avgPower == 182)

        // The walk has no power and no begin timestamp: absent, not zero.
        #expect(entries[1].avgPower == nil)
        #expect(entries[1].startTime == nil)
    }

    @Test func decodesTheActivityMetadata() throws {
        let detail = try JSONDecoder().decode(ActivityDetail.self, from: sample("activity-detail"))
        #expect(detail.activityId == 24172582403)
        #expect(detail.activityTypeDTO?.typeKey == "road_biking")
        #expect(detail.startDate == CalendarDate(year: 2026, month: 8, day: 23))
        #expect(detail.metadataDTO?.isOriginal == true)
        #expect(detail.metadataDTO?.fileFormat?.formatKey == "fit")
        #expect(detail.metadataDTO?.lastUpdateDate == "2026-08-23T16:02:10.0")
        #expect(detail.metadataDTO?.trimmed == false)
    }

    @Test func tokenUsesTheStatedLifetime() throws {
        let token = try AccessToken.parse(sample("token"), status: 200, now: now)
        #expect(token.value == "sample-access-token-not-real")
        #expect(token.expiresAt == now.addingTimeInterval(86400))
        #expect(token.keys == ["access_token", "expires_in", "token_type"])
    }

    @Test func tokenAcceptsCamelCaseAndStringLifetimes() throws {
        let token = try AccessToken.parse(Data(#"{"accessToken":"t","expiresIn":"3600"}"#.utf8), status: 200, now: now)
        #expect(token.value == "t")
        #expect(token.expiresAt == now.addingTimeInterval(3600))
    }

    /// The FAQ's 24 hours applies when the body states no lifetime.
    @Test func tokenFallsBackToTheDocumentedLifetime() throws {
        let token = try AccessToken.parse(Data(#"{"access_token":"t"}"#.utf8), status: 200, now: now)
        #expect(token.expiresAt == now.addingTimeInterval(24 * 60 * 60))
        let zero = try AccessToken.parse(Data(#"{"access_token":"t","expires_in":0}"#.utf8), status: 200, now: now)
        #expect(zero.expiresAt == now.addingTimeInterval(24 * 60 * 60))
    }

    @Test func unrecognisedTokenBodyNamesKeysButNotValues() {
        let body = Data(#"{"jwt":"secret-value","ttl":86400}"#.utf8)
        #expect(throws: GarminError.unexpectedResponse(UnexpectedResponse(status: 200, reason: .noTokenField(keys: ["jwt", "ttl"])))) {
            try AccessToken.parse(body, status: 200, now: now)
        }
        #expect(throws: GarminError.unexpectedResponse(UnexpectedResponse(status: 200, reason: .undecodableBody))) {
            try AccessToken.parse(Data("not json".utf8), status: 200, now: now)
        }
    }

    @Test func tokenDescriptionHidesTheValue() throws {
        let token = try AccessToken.parse(sample("token"), status: 200, now: now)
        #expect(!"\(token)".contains(token.value))
    }

    @Test func readsContentDispositionFilenames() {
        #expect(filename(fromContentDisposition: #"attachment; filename="24906063494.zip""#) == "24906063494.zip")
        #expect(filename(fromContentDisposition: "attachment; FILENAME=a.fit") == "a.fit")
        #expect(filename(fromContentDisposition: "attachment") == nil)
    }
}
