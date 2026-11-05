import Foundation
@testable import GarminPullCore
import Testing

@Suite struct RequestTests {
    let endpoints = Endpoints()
    let key = "sample-key-0123456789"
    let token = "sample-token-abcdef"

    func query(_ request: URLRequest) -> [String: String] {
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    @Test func tokenRequestMatchesThePersonalAPIPage() {
        let request = endpoints.token(apiKey: key)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://personal.connectapi.garmin.com/personalapitoken-service/personal-api/personal-api-key/token")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "ApiKey \(key)")
    }

    @Test func newestIsTheDocumentedDefaultPage() {
        let request = endpoints.search(.newest, accessToken: token)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path() == "/activitylist-service/activities/search/activities")
        #expect(query(request) == ["start": "0", "limit": "99", "sortOrder": "desc"])
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(token)")
    }

    @Test func earliestAsksForOneEntryAscending() {
        #expect(query(endpoints.search(.earliest, accessToken: token)) == ["start": "0", "limit": "1", "sortOrder": "asc"])
    }

    @Test func monthCoversEveryDayInclusive() {
        let november = query(endpoints.search(.month(CalendarMonth(year: 2026, month: 11)), accessToken: token))
        #expect(november["startDate"] == "2026-11-01")
        #expect(november["endDate"] == "2026-11-30")
        #expect(november["limit"] == "99")

        // 2028 is a leap year; 2100 is not.
        #expect(CalendarMonth(year: 2028, month: 2).lastDay.description == "2028-02-29")
        #expect(CalendarMonth(year: 2100, month: 2).lastDay.description == "2100-02-28")
        #expect(CalendarMonth(year: 2026, month: 12).lastDay.description == "2026-12-31")
    }

    @Test func monthSecondPageOffsetsBy99() {
        #expect(query(endpoints.search(.month(CalendarMonth(year: 2026, month: 10), start: 99), accessToken: token))["start"] == "99")
    }

    @Test func activityAndDownloadPaths() {
        #expect(endpoints.activity(id: 24172582403, accessToken: token).url?.path() == "/activity-service/activity/24172582403")
        let download = endpoints.download(id: 24906063494, accessToken: token)
        #expect(download.url?.path() == "/download-service/files/activity/24906063494")
        #expect(download.value(forHTTPHeaderField: "Authorization") == "Bearer \(token)")
    }

    @Test func redactedRequestsHoldNoSecret() {
        let requests = [
            endpoints.token(apiKey: key),
            endpoints.search(.month(CalendarMonth(year: 2026, month: 1)), accessToken: token),
            endpoints.download(id: 1, accessToken: token),
        ]
        for request in requests {
            let text = redacted(request)
            #expect(!text.contains(key))
            #expect(!text.contains(token))
        }
        #expect(redacted(requests[1]) == "GET /activitylist-service/activities/search/activities?start=0&limit=99&sortOrder=desc&startDate=2026-01-01&endDate=2026-01-31")
    }

    @Test func parsesCalendarInputs() {
        #expect(CalendarMonth("2026-09") == CalendarMonth(year: 2026, month: 9))
        #expect(CalendarMonth("2026-13") == nil)
        #expect(CalendarDate(prefixOf: "2026-10-14 18:02:11") == CalendarDate(year: 2026, month: 10, day: 14))
        #expect(CalendarDate(prefixOf: "2026-08-23T07:41:02.0") == CalendarDate(year: 2026, month: 8, day: 23))
        #expect(CalendarDate(prefixOf: "yesterday") == nil)
    }
}
