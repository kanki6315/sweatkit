import Foundation
import SweatKitLibrary
import SweatKitModel
import SweatKitStore
import Testing

@Suite struct WeeklyFeedTests {
    let temporary = TemporaryLibrary()
    @Test func totalsCoverTheWholeWeekNotJustTheLoadedPage() async throws {
        let library = try temporary.open()
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = Date(timeIntervalSince1970: 1_730_073_600) // 28 Oct 2024, Monday
        for index in 0..<71 {
            let identity = SourceIdentity(source: .garmin, externalID: String(index))
            try await library.store.importOriginal(Data("record-\(index)".utf8), as: identity, at: start)
            try await library.store.saveActivity(ActivityRecord(members: [identity], primary: identity,
                sport: .cycling, start: start.addingTimeInterval(Double(index)), elapsedTime: 100,
                movingTime: index == 0 ? nil : 90, distance: index == 0 ? nil : 1000,
                ascent: index == 0 ? nil : 10, title: "Ride", isHidden: index == 70))
        }
        #expect(try await library.feed(limit: 50).activities.count == 50)
        let week = try #require(try await library.weeklySummaries(calendar: calendar).first)
        #expect(week.count == 70)
        #expect(week.distance == 69_000)
        #expect(week.movingTime == 6210)
        #expect(week.ascent == 690)
        #expect(week.missingDistance == 1 && week.missingMovingTime == 1 && week.missingAscent == 1)
        #expect(try await library.weeklySummaries(FeedFilter(sports: [.walking]), calendar: calendar).isEmpty)
    }
}
