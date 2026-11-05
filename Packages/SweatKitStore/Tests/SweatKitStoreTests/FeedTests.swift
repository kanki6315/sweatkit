import Foundation
import SweatKitModel
import SweatKitStore
import Testing

/// 500 activities built in the test, with the expected feed worked out from
/// the feed's rules over the same values.
struct FeedLibrary {
    static let activityCount = 500
    static let firstGarminID = 100_000
    /// Pairs of activities share a start time, so ties need the ID to order them.
    static let secondsBetweenPairs: TimeInterval = 7 * 3_600
    static let sports: [Sport] = [.cycling, .walking, .running, .hiking, .other]
    static let indoorEvery = 3
    static let hiddenEvery = 50
    static let hiddenRemainder = 7
    static let parkEvery = 7
    static let cafeEvery = 11

    let library = TemporaryLibrary()
    let store: LibraryStore
    let activities: [ActivityRecord]

    init() async throws {
        store = try library.open()
        var activities: [ActivityRecord] = []
        for index in 0..<Self.activityCount {
            let identity = garmin(Self.firstGarminID + index)
            _ = try await store.importOriginal(Data("feed original \(index)".utf8), as: identity, at: referenceDate)
            let sport = Self.sports[index % Self.sports.count]
            var title = "\(sport.rawValue.capitalized) \(index)"
            if index % Self.parkEvery == 0 { title += ", Richmond Park" }
            if index % Self.cafeEvery == 0 { title += ", Café stop" }
            let activity = ActivityRecord(
                members: [identity],
                primary: identity,
                sport: sport,
                start: referenceDate.addingTimeInterval(Double(index / 2) * Self.secondsBetweenPairs),
                utcOffset: 3_600,
                elapsedTime: 3_600 + Double(index),
                timerTime: 3_500 + Double(index),
                movingTime: index % 4 == 0 ? nil : 3_400,
                distance: sport == .other ? nil : 20_000 + Double(index),
                ascent: index % 9 == 0 ? nil : 150,
                isIndoor: index % Self.indoorEvery == 0,
                isVirtual: index % (Self.indoorEvery * 2) == 0,
                title: title,
                headline: sport == .cycling
                    ? .init(kind: "averagePower", value: index % 2 == 0 ? .available(200) : .unavailable(UnavailableReason(rawValue: "noPower")))
                    : nil,
                isHidden: index % Self.hiddenEvery == Self.hiddenRemainder
            )
            try await store.saveActivity(activity)
            activities.append(activity)
        }
        self.activities = activities
    }

    /// The visible activities matching `filter`, newest first, ties by ID.
    func expected(_ filter: FeedFilter) -> [ActivityRecord] {
        activities
            .filter { !$0.isHidden }
            .filter { activity in filter.sports.map { $0.contains(activity.sport) } ?? true }
            .filter { activity in filter.dates.map { $0.contains(activity.start) } ?? true }
            .filter { activity in
                switch filter.setting {
                case .indoor: activity.isIndoor
                case .outdoor: !activity.isIndoor
                case nil: true
                }
            }
            .filter { activity in
                guard let text = filter.titleContains, !text.isEmpty else { return true }
                return activity.title.localizedStandardContains(text)
            }
            // Every activity here has one member, so its ID is its primary.
            .sorted { ($0.start, $0.primary) > ($1.start, $1.primary) }
    }

    /// Every page of the feed, following each page's cursor.
    func allPages(_ filter: FeedFilter, limit: Int) async throws -> [FeedPage] {
        var pages: [FeedPage] = []
        var cursor: FeedCursor?
        repeat {
            let page = try await store.feed(filter, limit: limit, after: cursor)
            pages.append(page)
            cursor = page.next
        } while cursor != nil
        return pages
    }
}

@Suite(.serialized) struct FeedTests {
    static let pageSize = 50
    /// An odd page size, so page boundaries fall between activities that
    /// share a start time.
    static let oddPageSize = 7
    /// Generous on a Mac; the point is to catch a query that scans or faults badly.
    static let firstPageBudget: TimeInterval = 0.25

    @Test func newestFirstWithPaging() async throws {
        let feed = try await FeedLibrary()
        let expected = feed.expected(FeedFilter())
        #expect(expected.count == FeedLibrary.activityCount - FeedLibrary.activityCount / FeedLibrary.hiddenEvery)

        for limit in [Self.pageSize, Self.oddPageSize] {
            let pages = try await feed.allPages(FeedFilter(), limit: limit)
            #expect(pages.dropLast().allSatisfy { $0.activities.count == limit })
            #expect(pages.last?.next == nil)
            #expect(pages.flatMap(\.activities) == expected)
        }
    }

    @Test func eachFilterAloneAndCombined() async throws {
        let feed = try await FeedLibrary()
        let middle = referenceDate.addingTimeInterval(50 * FeedLibrary.secondsBetweenPairs)
        let late = referenceDate.addingTimeInterval(180 * FeedLibrary.secondsBetweenPairs)
        let filters: [FeedFilter] = [
            FeedFilter(sports: [.cycling]),
            FeedFilter(sports: [.walking, .hiking]),
            FeedFilter(sports: []),
            FeedFilter(dates: middle..<late),
            FeedFilter(setting: .indoor),
            FeedFilter(setting: .outdoor),
            FeedFilter(titleContains: "richmond park"),
            FeedFilter(titleContains: "CAFE"),
            FeedFilter(titleContains: ""),
            FeedFilter(titleContains: "no such title"),
            FeedFilter(sports: [.cycling, .running], dates: middle..<late, setting: .outdoor, titleContains: "park"),
            FeedFilter(sports: [.walking], setting: .indoor, titleContains: "café"),
        ]
        for filter in filters {
            let expected = feed.expected(filter)
            let pages = try await feed.allPages(filter, limit: Self.oddPageSize)
            #expect(pages.flatMap(\.activities) == expected, "\(filter)")
        }
        // The filters are not vacuous. Every fifth activity is a ride, and the
        // hidden ones (index 7 modulo 50) are all runs.
        #expect(feed.expected(filters[0]).count == FeedLibrary.activityCount / FeedLibrary.sports.count)
        #expect(!feed.expected(filters[10]).isEmpty)
    }

    @Test func storedFieldsComeBackUnchanged() async throws {
        let feed = try await FeedLibrary()
        for activity in feed.activities.prefix(FeedLibrary.sports.count * 2) {
            let id = try #require(activity.id)
            #expect(try await feed.store.activity(id) == activity)
            #expect(try await feed.store.sourceRecord(id)?.activityID == id)
        }
    }

    @Test func firstPageTime() async throws {
        let clock = ContinuousClock()
        var feed: FeedLibrary?
        let buildTime = try await clock.measure { feed = try await FeedLibrary() }
        let library = try #require(feed)

        var firstPage = FeedPage(activities: [], next: nil)
        let firstPageTime = try await clock.measure {
            firstPage = try await library.store.feed(limit: Self.pageSize)
        }
        var wholeFeed = FeedPage(activities: [], next: nil)
        let wholeFeedTime = try await clock.measure {
            wholeFeed = try await library.store.feed(limit: FeedLibrary.activityCount)
        }
        var filteredPage = FeedPage(activities: [], next: nil)
        let filteredTime = try await clock.measure {
            filteredPage = try await library.store.feed(FeedFilter(sports: [.cycling], setting: .outdoor, titleContains: "park"), limit: Self.pageSize)
        }

        #expect(firstPage.activities.count == Self.pageSize)
        #expect(wholeFeed.activities.count == library.expected(FeedFilter()).count)
        #expect(!filteredPage.activities.isEmpty)
        #expect(seconds(firstPageTime) < Self.firstPageBudget)
        recordMeasurement(
            """
            \(FeedLibrary.activityCount) activities
            build seconds (import + save, one at a time): \(seconds(buildTime))
            first page of \(Self.pageSize) seconds: \(seconds(firstPageTime))
            all \(wholeFeed.activities.count) visible as one page seconds: \(seconds(wholeFeedTime))
            filtered first page seconds: \(seconds(filteredTime))
            """,
            named: "feed-timing.txt"
        )
    }
}

@Suite struct ActivityTests {
    @Test func theIDIsTheLowestMember() async throws {
        let library = TemporaryLibrary()
        let store = try library.open()
        try await storeGarminRecord(9, in: store)
        let file = try await store.importFile(Data("a file".utf8), at: referenceDate).record.identity
        let activity = ActivityRecord(members: [garmin(9), file], primary: garmin(9), sport: .cycling, start: referenceDate, elapsedTime: 60, title: "Ride")

        let id = try await store.saveActivity(activity)

        // File identities sort before Garmin ones.
        #expect(id == file)
        #expect(try await store.activity(file)?.members == [file, garmin(9)])
        #expect(try await store.activity(file)?.primary == garmin(9))
        #expect(try await store.sourceRecord(garmin(9))?.activityID == file)
    }

    @Test func tiesAreOrderedByIdentityAcrossPages() async throws {
        let library = TemporaryLibrary()
        let store = try library.open()
        // Numeric-aware ordering would put 9 before 10; identity order is
        // character by character, so "10" < "100" < "9".
        let ids = [9, 10, 100, 2]
        for id in ids {
            try await storeGarminRecord(id, in: store)
            try await store.saveActivity(ActivityRecord(members: [garmin(id)], primary: garmin(id), sport: .walking, start: referenceDate, elapsedTime: 60, title: "Walk"))
        }
        let expected = ids.map(garmin).sorted(by: >)

        var found: [SourceIdentity] = []
        var cursor: FeedCursor?
        repeat {
            let page = try await store.feed(limit: 1, after: cursor)
            found += page.activities.compactMap(\.id)
            cursor = page.next
        } while cursor != nil

        #expect(found == expected)
        #expect(expected.map(\.externalID) == ["9", "2", "100", "10"])
        #expect(try await store.sourceRecords().map(\.identity) == expected.reversed())
    }

    @Test func savingAgainReplacesTheFields() async throws {
        let library = TemporaryLibrary()
        let store = try library.open()
        try await storeGarminRecord(1, in: store)
        var activity = ActivityRecord(members: [garmin(1)], primary: garmin(1), sport: .walking, start: referenceDate, elapsedTime: 60, title: "Walk")
        try await store.saveActivity(activity)
        activity.title = "Evening walk"
        activity.distance = 1_200
        activity.headline = .init(kind: "averagePace", value: .available(0.75))

        try await store.saveActivity(activity)

        #expect(try await store.activity(garmin(1)) == activity)
        #expect(try await store.feed(limit: FeedTests.pageSize).activities == [activity])
    }

    @Test func membersMustBeStoredAndPrimaryAmongThem() async throws {
        let library = TemporaryLibrary()
        let store = try library.open()
        try await storeGarminRecord(1, in: store)
        try await storeGarminRecord(2, in: store)

        await #expect(throws: StoreError.unknownSourceRecord(garmin(3))) {
            try await store.saveActivity(ActivityRecord(members: [garmin(3)], primary: garmin(3), sport: .walking, start: referenceDate, elapsedTime: 1, title: ""))
        }
        await #expect(throws: StoreError.invalidMembers) {
            try await store.saveActivity(ActivityRecord(members: [garmin(1)], primary: garmin(2), sport: .walking, start: referenceDate, elapsedTime: 1, title: ""))
        }
        await #expect(throws: StoreError.invalidMembers) {
            try await store.saveActivity(ActivityRecord(members: [], primary: garmin(1), sport: .walking, start: referenceDate, elapsedTime: 1, title: ""))
        }
        try await store.saveActivity(ActivityRecord(members: [garmin(2)], primary: garmin(2), sport: .walking, start: referenceDate, elapsedTime: 1, title: ""))
        // Garmin 1 would make a new activity that takes Garmin 2 from its own.
        await #expect(throws: StoreError.memberOfAnotherActivity(garmin(2))) {
            try await store.saveActivity(ActivityRecord(members: [garmin(1), garmin(2)], primary: garmin(1), sport: .walking, start: referenceDate, elapsedTime: 1, title: ""))
        }
    }
}
