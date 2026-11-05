import Foundation
import Testing
import SweatKitAnalysis
import SweatKitLibrary
import SweatKitModel
import SweatKitStore
import SweatKitTestSupport

@Suite struct TrendsTests {
    let calendar: Calendar = { var c = Calendar(identifier: .iso8601); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }()
    let day = Date(timeIntervalSince1970: 1_735_689_600) // 2025-01-01 UTC
    func row(_ offset: Double = 0, power: Double = 200, id: String = "a") -> TrendActivity {
        let identity = SourceIdentity(source: .file, externalID: id)
        let record = ActivityRecord(members: [identity], primary: identity, sport: .cycling,
            start: day.addingTimeInterval(offset * 86400), elapsedTime: 1200, timerTime: 1200,
            movingTime: 1200, distance: 10_000, ascent: 100, title: id)
        let input = ActivityInput(sport: .cycling, recording: .summaryOnly(StatedSummary()), activityDate: record.start)
        var metrics = ActivityAnalysis.metrics(for: input)
        metrics.time.timer = .available(1200)
        metrics.power.variability = .available(1.09)
        metrics.cyclingEfficiency = .available(2)
        return TrendActivity(activity: record, metrics: metrics,
            curve: [PowerCurvePoint(duration: 1200, power: .available(power))])
    }
    @Test func rollingWindowAndFutureExclusion() {
        let rows = [row(-90, power: 300), row(-90.001, power: 900, id: "old"), row(1, power: 1000, id: "future")]
        #expect(TrendsAggregation.estimate(rows, on: day, calendar: calendar) == 285)
        #expect(TrendsAggregation.estimate([row(-91)], on: day, calendar: calendar) == nil)
    }
    @Test func missingIsNotZeroAndStaleIsExcluded() {
        var a = row(); a.activity.distance = nil
        let total = TrendsAggregation.total([a, row(id: "b")], measure: .distance)
        #expect(total.known == 10_000); #expect(total.missing == 1); #expect(total.complete == nil)
        #expect(TrendsAggregation.total([a], measure: .load).complete == nil)
        a.isStale = true
        #expect(TrendsAggregation.records([a]).isEmpty)
        #expect(TrendsAggregation.curve([a]).allSatisfy { $0.power.value == nil })
    }
    @Test func steadyBoundaryAndTies() {
        var a = row(); var b = row(1, id: "b")
        #expect(TrendsAggregation.efficiency([a]).count == 1)
        a.metrics?.power.variability = .available(1.10)
        b.metrics?.time.timer = .available(1199)
        #expect(TrendsAggregation.efficiency([a, b]).isEmpty)
        #expect(TrendsAggregation.records([b, a]).first { $0.key == "power.1200" }?.activity.id == a.activity.id)
        #expect(TrendsAggregation.recordBadges(for: b.activity.id!, in: [a,b]).isEmpty)
    }
    @Test func fastestRecordsStaySeparatedBySportAndSimultaneousRidesHaveUniquePoints() {
        var a = row(); var b = row(id: "b"); var c = row(id: "c")
        #expect(Set(TrendsAggregation.efficiency([a,b]).map(\.id)).count == 2)
        a.activity.sport = .running; b.activity.sport = .running; c.activity.sport = .walking
        a.metrics?.bestDistances = [.init(distance: 5000, time: .available(1500))]
        b.metrics?.bestDistances = [.init(distance: 5000, time: .available(1400))]
        c.metrics?.bestDistances = [.init(distance: 5000, time: .available(1300))]
        let fastest = TrendsAggregation.records([a,b,c]).filter { $0.key.hasPrefix("distance.") }
        #expect(fastest.count == 2)
        #expect(fastest.first { $0.activity.sport == .running }?.value == 1400)
        #expect(fastest.first { $0.activity.sport == .walking }?.value == 1300)
    }
    @Test func filtersExcludeHiddenAndVirtualIsIndoor() {
        var a = row(); a.activity.isVirtual = true
        var b = row(id: "b"); b.activity.isHidden = true
        let history = TrendsHistory(activities: [a,b], profile: AthleteProfile())
        #expect(history.matching(FeedFilter(setting: .indoor)).count == 1)
        #expect(history.matching(FeedFilter(setting: .outdoor)).isEmpty)
        #expect(history.matching(FeedFilter(dates: day..<day.addingTimeInterval(1))).count == 1)
    }
    @Test func emptyPeriodsAndYearComparison() {
        let rows = [row(), row(31, id: "feb"), row(-366, id: "prior")]
        let result = TrendsAggregation.volume(rows, range: day..<day.addingTimeInterval(90 * 86400), period: .month, measure: .distance, calendar: calendar)
        #expect(result.count == 3)
        #expect(result[0].total.known == 10_000)
        #expect(result[0].lastYear.known == 10_000)
        #expect(result[2].total.count == 0)
    }
    @Test func dailyLoadIncludesMissingAndHandlesDST() {
        var c = calendar; c.timeZone = TimeZone(identifier: "America/New_York")!
        let start = c.date(from: DateComponents(year: 2025, month: 3, day: 9))!
        var a = row(); a.activity.start = start.addingTimeInterval(3600)
        let days = TrendsAggregation.dailyLoad([a], range: start..<c.date(byAdding: .day, value: 1, to: start)!, calendar: c)
        let target = days.first { $0.start == start }!
        #expect(target.end.timeIntervalSince(target.start) == 23 * 3600)
        #expect(target.total.missing == 1)
        #expect(target.total.complete == nil)
    }
    @Test func revisedSourceReplacesCurveAndDeletionRemovesRecords() async throws {
        let temp = TemporaryLibrary(); let library = try temp.open()
        let id = SourceIdentity(source: .garmin, externalID: "trend-revision")
        _ = try await library.importFile(try Fixtures.FIT.outdoorRide.data(), as: id)
        let first = try await library.trendsHistory()
        _ = try await library.importFile(try Fixtures.FIT.zwiftRide.data(), as: id)
        let changed = try await library.trendsHistory()
        #expect(changed.activities.count == 1)
        #expect(changed.activities.first?.curve != first.activities.first?.curve)
        #expect(changed.activities.first?.activity.isVirtual == true)
        try await library.permanentlyDelete(id)
        #expect(try await library.trendsHistory().activities.isEmpty)
    }
    @Test func representativeYearAggregationBenchmark() {
        let rows = (0..<365).map { row(Double($0), power: Double(200 + $0 % 100), id: "\($0)") }
        let end = day.addingTimeInterval(365 * 86400)
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for measure in TrendMeasure.allCases {
                _ = TrendsAggregation.volume(rows, range: day..<end, period: .week, measure: measure, calendar: calendar)
            }
            _ = TrendsAggregation.thresholds(rows, range: day..<end, calendar: calendar)
            _ = TrendsAggregation.curve(rows)
            _ = TrendsAggregation.records(rows)
            _ = TrendsAggregation.regression(TrendsAggregation.efficiency(rows))
            _ = TrendsAggregation.dailyLoad(rows, range: day..<end, calendar: calendar)
        }
        print("TRENDS_HOST_YEAR 365 compact summaries, all aggregations: \(elapsed)")
        #expect(elapsed < .seconds(1))
    }
    @Test func cacheSurvivesReopenAndVisibilityAndThresholdInvalidate() async throws {
        let temp = TemporaryLibrary()
        let library = try temp.open()
        _ = try await library.importFile(try Fixtures.FIT.outdoorRide.data())
        let first = try await library.trendsHistory()
        let item = try #require(first.activities.first)
        let id = try #require(item.activity.id)
        #expect(!item.curve.isEmpty)
        let cached = try #require(try await library.store.derivedResults(owner: .activity(id)).first { $0.kind.hasPrefix("trends.") })
        _ = try await library.trendsHistory()
        let again = try await library.store.derivedResult(owner: .activity(id), kind: cached.kind)
        #expect(again?.computedAt == cached.computedAt)
        let reopened = try temp.open()
        #expect(try await reopened.trendsHistory().activities.first?.curve == item.curve)
        var profile = try await library.profile()
        profile.thresholdPowerHistory = [.init(effectiveFrom: item.activity.start, watts: 250)]
        _ = try await library.saveProfile(profile)
        let stale = try await library.trendsHistory()
        #expect(stale.activities.first?.isStale == true)
        #expect(stale.activities.first?.metrics == nil)
        try await library.decide(.hidden(true), for: id)
        #expect(try await library.trendsHistory().activities.isEmpty)
    }
}
