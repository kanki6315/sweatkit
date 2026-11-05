import Foundation
import SweatKitLibrary
import SweatKitModel
import SweatKitStore
import Testing

/// Synthetic persistence coverage, not the representative FIT/device benchmark.
@Suite struct LibraryScaleTests {
    let temporary = TemporaryLibrary()

    @Test func fiveHundredDistinctWorkoutsSurviveRestartAndPagedFiltering() async throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var identities: Set<SourceIdentity> = []
        do {
            let library = try temporary.open()
            for index in 0..<500 {
                let date = start.addingTimeInterval(Double(index) * 86_400)
                let snapshot = HealthSnapshot(workoutID: UUID(), activity: RecordedActivity(
                    sport: index.isMultiple(of: 2) ? .cycling : .walking,
                    stated: StatedSummary(start: date, end: date.addingTimeInterval(600),
                        timerTime: 600, distance: 1000)),
                    sourceName: "Scale fixture", sourceBundleIdentifier: "test.scale")
                try await library.importHealthSnapshot(snapshot)
                identities.insert(snapshot.identity)
            }
        }
        let reopened = try temporary.open()
        var seen: Set<SourceIdentity> = []
        var cursor: FeedCursor?
        var previous = Date.distantFuture
        repeat {
            let page = try await reopened.feed(limit: 37, after: cursor)
            for row in page.activities {
                #expect(row.start < previous)
                previous = row.start
                #expect(seen.insert(row.primary).inserted)
                #expect(row.distance == 1000)
                #expect(row.timerTime == 600)
            }
            cursor = page.next
        } while cursor != nil
        #expect(seen == identities)
        let weeks = try await reopened.weeklySummaries()
        #expect(weeks.reduce(0) { $0 + $1.count } == 500)
        #expect(weeks.reduce(0.0) { $0 + $1.distance } == 500_000)
        let walks = try await reopened.weeklySummaries(FeedFilter(sports: [.walking]))
        #expect(walks.reduce(0) { $0 + $1.count } == 250)
        #expect(try await reopened.store.sourceRecords().count == 500)
    }
}
