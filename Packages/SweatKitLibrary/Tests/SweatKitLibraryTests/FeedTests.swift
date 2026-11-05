import Foundation
import SweatKitAnalysis
import SweatKitLibrary
import SweatKitModel
import SweatKitStore
import SweatKitTestSupport
import Testing

/// The feed after the store is closed and opened again from disk.
@Suite struct FeedAfterReopenTests {
    let temporary = TemporaryLibrary()

    @Test func theFeedListsTheFourActivitiesNewestFirstAfterReopening() async throws {
        try await temporary.withFixtures()
        let before: [ActivityRecord]
        do {
            // A scope of its own, so this store is closed before the next opens.
            let library = try temporary.open()
            before = try await library.feed(limit: 10).activities
        }

        let library = try temporary.open()
        let page = try await library.feed(limit: 10)
        let feed = page.activities
        #expect(page.next == nil)
        #expect(feed == before)

        let expected = try FixtureFacts.newestFirst.map(FixtureFacts.of)
        #expect(feed.map(\.id) == (try expected.map { try fileIdentity($0.fixture) }))
        #expect(feed.map(\.start) == expected.map { Date(timeIntervalSince1970: $0.start) })
        #expect(feed.map(\.title) == ["Virtual ride", "Night walk", "Afternoon walk", "Morning ride"])
        #expect(feed.map { $0.headline?.kind } == ["weightedPower", "averagePace", "averagePace", "weightedPower"])
        // Each headline has a value: every ride here has power, and every
        // walk has a moving time and a distance.
        #expect(feed.allSatisfy { $0.headline?.value.value != nil })
    }

    @Test func theFeedPagesAndFiltersThroughTheLibrary() async throws {
        let library = try await temporary.withFixtures().open()
        let first = try await library.feed(limit: 3)
        #expect(first.activities.count == 3)
        let next = try #require(first.next)
        let second = try await library.feed(limit: 3, after: next)
        #expect(second.activities.map(\.title) == ["Morning ride"])
        #expect(second.next == nil)

        let walks = try await library.feed(FeedFilter(sports: [.walking]), limit: 10)
        #expect(walks.activities.map(\.title) == ["Night walk", "Afternoon walk"])
        let indoor = try await library.feed(FeedFilter(setting: .indoor), limit: 10)
        #expect(indoor.activities.map(\.title) == ["Virtual ride"])
    }
}

/// The headline and the unavailable values of real activities, against the
/// spec's rules.
@Suite struct HeadlineTests {
    let temporary = TemporaryLibrary()

    /// M5 routes the independently tested weighted metric into the feed.
    @Test(arguments: [Fixtures.FIT.outdoorRide, .zwiftRide])
    func aRidesHeadlineIsItsWeightedPower(_ fixture: Fixtures.FIT) async throws {
        let library = try await temporary.withFixtures().open()
        let id = try fileIdentity(fixture)
        let row = try #require(try await library.activity(id))
        let expected = try #require(try await library.metrics(for: id)?.power.weighted.value)

        #expect(row.headline?.kind == FeedRules.weightedPowerHeadline)
        #expect(close(row.headline?.value.value, expected))
        // A plausible figure for an hour or two on a bike, and never a zero.
        #expect((50...400).contains(expected))
    }

    /// With no threshold power set, load and intensity stay unavailable,
    /// while starter zones and the headline are available.
    @Test func aRideWithNoThresholdPowerKeepsItsHeadlineAndSaysWhatIsMissing() async throws {
        let library = try await temporary.withFixtures().open()
        let id = try fileIdentity(.outdoorRide)
        #expect(try await library.profile() == AthleteProfile())
        let row = try #require(try await library.activity(id))
        let metrics = try #require(try await library.metrics(for: id))

        #expect(row.headline?.kind == FeedRules.weightedPowerHeadline)
        #expect(row.headline?.value == metrics.power.weighted)
        #expect(metrics.power.average.value != nil)

        // Power is on 5,337 of 5,347 records over 89 minutes, so weighted
        // power is available. Intensity and load need a personal threshold;
        // zone displays can use starter values.
        #expect(metrics.power.weighted.value != nil)
        #expect(metrics.power.intensity == .unavailable(.noThresholdPower))
        #expect(metrics.power.load == .unavailable(.noThresholdPower))
        #expect(metrics.timeInPowerZones.value?.seconds.count == 7)
        // "A ride with no threshold power set falls through to heart rate",
        // which has no threshold either, "and prompts the user to set a
        // threshold". Load is unavailable, never estimated and never zero.
        #expect(metrics.heartRate.load == .unavailable(.noThresholdHeartRate))
        #expect(metrics.load == .unavailable(.noThresholdHeartRate))
        #expect(metrics.promptsForThresholdPower)

        // What does not depend on the profile is all there.
        #expect(row.timerTime != nil && row.movingTime != nil && row.distance != nil && row.ascent != nil)
    }

    /// A walk has no power metrics at all, and its headline is its pace:
    /// moving time over distance, in seconds per kilometre.
    @Test(arguments: [Fixtures.FIT.walk, .walkPitlane])
    func aWalksHeadlineIsItsAveragePace(_ fixture: Fixtures.FIT) async throws {
        let library = try await temporary.withFixtures().open()
        let id = try fileIdentity(fixture)
        let row = try #require(try await library.activity(id))
        let metrics = try #require(try await library.metrics(for: id))

        let moving = try #require(row.movingTime)
        let distance = try #require(row.distance)
        #expect(row.headline?.kind == FeedRules.averagePaceHeadline)
        #expect(close(row.headline?.value.value, moving / (distance / 1000)))
        // Between a brisk walk and a stroll: 6 to 15 minutes per kilometre.
        #expect((360...900).contains(try #require(row.headline?.value.value)))

        #expect(metrics.power.average == .unavailable(.notDefinedForSport))
        #expect(metrics.power.weighted == .unavailable(.notDefinedForSport))
        #expect(metrics.timeInPowerZones == .unavailable(.notDefinedForSport))
        #expect(!metrics.promptsForThresholdPower)
        #expect(metrics.load == .unavailable(.noThresholdHeartRate))
    }
}
