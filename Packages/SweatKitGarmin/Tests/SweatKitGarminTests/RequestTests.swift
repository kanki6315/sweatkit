import Foundation
@testable import SweatKitGarmin
import Testing

func date(_ year: Int, _ month: Int, _ day: Int) throws -> CalendarDate {
    try #require(CalendarDate(year: year, month: month, day: day))
}

func queryItems(_ request: URLRequest) -> [String: String] {
    let items = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems ?? []
    return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
}

@Suite struct RequestTests {
    let endpoints = GarminEndpoints()
    let key = "sample-key-0123456789"
    let token = "sample-token-abcdef"

    @Test func tokenRequestMatchesThePersonalAPIPage() throws {
        let request = try endpoints.token(apiKey: key)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://personal.connectapi.garmin.com/personalapitoken-service/personal-api/personal-api-key/token")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "ApiKey \(key)")
        // The live endpoint answered `Accept: application/json` with 406.
        #expect(request.value(forHTTPHeaderField: "Accept") == "*/*")
    }

    @Test func newestIsTheDocumentedDefaultPage() throws {
        let request = try endpoints.activities(.newest, accessToken: token)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path() == "/activitylist-service/activities/search/activities")
        #expect(queryItems(request) == ["start": "0", "limit": "99", "sortOrder": "desc"])
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(token)")
    }

    @Test func earliestAsksForOneEntryAscending() throws {
        #expect(queryItems(try endpoints.activities(.earliest, accessToken: token)) == ["start": "0", "limit": "1", "sortOrder": "asc"])
    }

    @Test func dateRangeIsSentAsInclusiveLocalDates() throws {
        let query = ActivityQuery(startDate: try date(2026, 11, 1), endDate: try date(2026, 11, 30))
        #expect(queryItems(try endpoints.activities(query, accessToken: token)) == [
            "start": "0", "limit": "99", "sortOrder": "desc", "startDate": "2026-11-01", "endDate": "2026-11-30",
        ])
    }

    @Test func nextPageOffsetsByTheLimit() throws {
        let query = ActivityQuery(limit: 99).nextPage.nextPage
        #expect(query.start == 198)
        #expect(queryItems(try endpoints.activities(query, accessToken: token))["start"] == "198")
    }

    @Test func refusesQueriesThatCannotBeRight() throws {
        #expect(throws: GarminError.invalidRequest) { try endpoints.activities(ActivityQuery(start: -1), accessToken: token) }
        #expect(throws: GarminError.invalidRequest) { try endpoints.activities(ActivityQuery(limit: 0), accessToken: token) }
        let backwards = ActivityQuery(startDate: try date(2026, 2, 1), endDate: try date(2026, 1, 31))
        #expect(throws: GarminError.invalidRequest) { try endpoints.activities(backwards, accessToken: token) }
    }

    @Test func activityAndDownloadPaths() throws {
        #expect(try endpoints.activity(id: 24172582403, accessToken: token).url?.path() == "/activity-service/activity/24172582403")
        let download = try endpoints.originalFile(activityID: 24906063494, accessToken: token)
        #expect(download.url?.path() == "/download-service/files/activity/24906063494")
        #expect(download.value(forHTTPHeaderField: "Authorization") == "Bearer \(token)")
    }

    @Test func loggableTargetsHoldNoSecret() throws {
        let requests = [
            try endpoints.token(apiKey: key),
            try endpoints.activities(ActivityQuery(startDate: try date(2026, 1, 1), endDate: try date(2026, 1, 31)), accessToken: token),
            try endpoints.originalFile(activityID: 1, accessToken: token),
        ]
        for request in requests {
            #expect(!loggable(request).contains(key))
            #expect(!loggable(request).contains(token))
        }
        #expect(loggable(requests[1]) == "/activitylist-service/activities/search/activities?start=0&limit=99&sortOrder=desc&startDate=2026-01-01&endDate=2026-01-31")
    }

    @Test func calendarDatesAreValidated() throws {
        #expect(CalendarDate(year: 2028, month: 2, day: 29) != nil)
        #expect(CalendarDate(year: 2026, month: 2, day: 29) == nil)
        #expect(CalendarDate(year: 2026, month: 4, day: 31) == nil)
        #expect(CalendarDate(year: 2026, month: 13, day: 1) == nil)
        #expect(try date(2026, 1, 31) < (try date(2026, 2, 1)))
    }

    @Test func readsGarminStartTimes() throws {
        #expect(CalendarDate(prefixOf: "2026-10-14 18:02:11") == (try date(2026, 10, 14)))
        #expect(CalendarDate(prefixOf: "2026-08-23T07:41:02.0") == (try date(2026, 8, 23)))
        #expect(CalendarDate(prefixOf: "2026-8-23 07:41") == nil)
        #expect(CalendarDate(prefixOf: "yesterday") == nil)
        #expect(CalendarDate(prefixOf: "") == nil)
    }
}
