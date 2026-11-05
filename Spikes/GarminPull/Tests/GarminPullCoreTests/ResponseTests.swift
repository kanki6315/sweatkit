import Foundation
@testable import GarminPullCore
import Testing

func sample(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Samples"))
    return try Data(contentsOf: url)
}

@Suite struct ResponseTests {
    @Test func decodesAMonthListingAndIgnoresUnknownFields() throws {
        let entries = try ActivityListEntry.decodeList(sample("activities-month"))
        #expect(entries.map(\.activityId) == [24906063494, 24830689204])

        let zwift = entries[0]
        #expect(zwift.activityType?.typeKey == "virtual_ride")
        #expect(zwift.manufacturer == "ZWIFT")
        #expect(zwift.startDate == CalendarDate(year: 2026, month: 10, day: 14))
        #expect(zwift.avgPower == 182)

        // The walk has no power: absent, not zero.
        #expect(entries[1].avgPower == nil)
    }

    @Test func decodesAnEmptyListing() throws {
        #expect(try ActivityListEntry.decodeList(Data("[]".utf8)).isEmpty)
    }

    @Test func decodesTheActivitySummaryMetadata() throws {
        let detail = try ActivityDetail.decode(sample("activity-detail"))
        #expect(detail.activityId == 24172582403)
        #expect(detail.activityTypeDTO?.typeKey == "road_biking")
        #expect(detail.startDate == CalendarDate(year: 2026, month: 8, day: 23))
        #expect(detail.metadataDTO?.isOriginal == true)
        #expect(detail.metadataDTO?.fileFormat?.formatKey == "fit")
        #expect(detail.metadataDTO?.lastUpdateDate == "2026-08-23T16:02:10.0")
        #expect(detail.metadataDTO?.trimmed == false)
    }

    @Test func parsesTheAssumedTokenShape() throws {
        let token = try TokenResponse.parse(sample("token"))
        #expect(token.accessToken == "sample-access-token-not-real")
        #expect(token.tokenType == "Bearer")
        #expect(token.expiresIn == 86400)
        #expect(token.keys == ["access_token", "expires_in", "token_type"])
    }

    @Test func parsesCamelCaseTokenFields() throws {
        let token = try TokenResponse.parse(Data(#"{"accessToken":"t","expiresIn":3600}"#.utf8))
        #expect(token.accessToken == "t")
        #expect(token.expiresIn == 3600)
        #expect(token.tokenType == nil)
    }

    @Test func unrecognisedTokenBodyNamesKeysButNotValues() {
        let body = Data(#"{"jwt":"secret-value","ttl":86400}"#.utf8)
        #expect {
            try TokenResponse.parse(body)
        } throws: { error in
            let text = "\(error)"
            return text.contains("jwt") && text.contains("ttl") && !text.contains("secret-value")
        }
        #expect(throws: TokenResponse.ParseError.self) { try TokenResponse.parse(Data("not json".utf8)) }
    }

    @Test func collectsRateHeadersCaseInsensitively() {
        let signals = RateSignals(status: 429, headers: [
            "Retry-After": "120",
            "X-RateLimit-Remaining": "0",
            "RateLimit-Policy": "100;w=3600",
            "Content-Type": "application/json",
        ])
        #expect(signals.isRateLimited)
        #expect(signals.retryAfterSeconds == 120)
        #expect(signals.headers == ["retry-after": "120", "x-ratelimit-remaining": "0", "ratelimit-policy": "100;w=3600"])
        #expect(RateSignals(status: 200, headers: ["Content-Type": "application/json"]).headers.isEmpty)
    }

    @Test func logHidesCookies() {
        let headers = loggableHeaders(["Set-Cookie": "session=abc", "Content-Type": "application/zip"])
        #expect(headers == ["set-cookie": "<redacted>", "content-type": "application/zip"])
    }
}
