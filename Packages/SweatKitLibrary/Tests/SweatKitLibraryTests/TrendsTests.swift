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
    @Test func powerComparisonWindowIsIndependentOfVolumeWindow() {
        var hidden = row(-10, power: 999, id: "hidden"); hidden.activity.isHidden = true
        var stale = row(-10, power: 888, id: "stale"); stale.isStale = true
        let history = TrendsHistory(activities: [row(-400, power: 400, id: "old"),
            row(-10, power: 200, id: "recent"), row(1, power: 900, id: "future"), hidden, stale], profile: AthleteProfile())
        var options = TrendsOptions(sport: "Rides", dateWindow: "Last 6 weeks", setting: "All settings",
            measure: .distance, period: .week, comparison: "All time", recordWindow: "This year")
        let allTime = TrendsPresentation.make(history, options: options, now: day, calendar: calendar)
        #expect(!allTime.rows.contains { $0.activity.title == "old" })
        #expect(allTime.curve.first { $0.duration == 1200 }?.power.value == 400)
        #expect(allTime.recentCurve.first { $0.duration == 1200 }?.power.value == 200)
        #expect(Set(allTime.powerActivities.map { $0.activity.title }) == ["old", "recent"])
        options.comparison = "90 days"
        let recent = TrendsPresentation.make(history, options: options, now: day, calendar: calendar)
        #expect(recent.curve.first { $0.duration == 1200 }?.power.value == 200)
        #expect(recent.powerActivities.map { $0.activity.title } == ["recent"])
    }

    @Test func recentPowerSourcesUseExactWindowAndExcludeStaleHiddenFuture() {
        var stale = row(-1, power: 900, id: "stale"); stale.isStale = true
        var hidden = row(-2, power: 800, id: "hidden"); hidden.activity.isHidden = true
        let history = TrendsHistory(activities: [row(-42, power: 300, id: "boundary"),
            row(-42.001, power: 600, id: "outside"), row(-1, power: 200, id: "recent"),
            row(1, power: 1000, id: "future"), stale, hidden], profile: AthleteProfile())
        let options = TrendsOptions(sport: "Rides", dateWindow: "This year", setting: "All settings",
            measure: .distance, period: .week, comparison: "This year", recordWindow: "This year")
        let result = TrendsPresentation.make(history, options: options, now: day, calendar: calendar)
        #expect(Set(result.recentPowerActivities.map { $0.activity.title }) == ["boundary", "recent"])
        #expect(result.recentCurve.first { $0.duration == 1200 }?.power.value == 300)
        #expect(result.powerActivities.isEmpty)
        #expect(result.curve.allSatisfy { $0.power.value == nil })
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
        #expect(changed.id != first.id)
        #expect(changed.activities.count == 1)
        #expect(changed.activities.first?.curve != first.activities.first?.curve)
        #expect(changed.activities.first?.activity.isVirtual == true)
        try await library.permanentlyDelete(id)
        #expect(try await library.trendsHistory().activities.isEmpty)
    }
    @Test func presentationCacheReusesAndInvalidates() async {
        let cache = TrendsPresentationCache()
        var profile = AthleteProfile()
        profile.thresholdPowerHistory = [.init(effectiveFrom: day.addingTimeInterval(-86400), watts: 250)]
        var history = TrendsHistory(activities: [row()], profile: profile)
        var options = TrendsOptions(sport: "Rides", dateWindow: "Last 90 days", setting: "All settings",
                                    measure: .distance, period: .week, comparison: "90 days", recordWindow: "All time")
        let first = await cache.presentation(history, options: options, now: day, calendar: calendar)
        let reused = await cache.presentation(history, options: options, now: day.addingTimeInterval(1), calendar: calendar)
        #expect(reused.setThresholds.last?.date == first.setThresholds.last?.date)
        let later = await cache.presentation(history, options: options, now: day.addingTimeInterval(60), calendar: calendar)
        #expect(later.setThresholds.last?.date == day.addingTimeInterval(60))
        options.measure = .time
        let time = await cache.presentation(history, options: options, now: day, calendar: calendar)
        #expect(time.buckets.reduce(0) { $0 + $1.total.known } == 1200)
        history.activities = []
        let deleted = await cache.presentation(history, options: options, now: day, calendar: calendar)
        #expect(deleted.rows.isEmpty)
        #expect(deleted.records.isEmpty)
    }

    @Test func diskCachesSurviveRestartAndExpireSafely() async throws {
        let temp = TemporaryLibrary()
        let library = try temp.open()
        _ = try await library.importFile(try Fixtures.FIT.outdoorRide.data())
        var profile = try await library.profile()
        profile.thresholdPowerHistory = [.init(effectiveFrom: .distantPast, watts: 250)]
        _ = try await library.saveProfile(profile)
        let history = try await library.trendsHistory()
        let options = TrendsOptions(sport: "Rides", dateWindow: "All time", setting: "All settings",
                                    measure: .distance, period: .week, comparison: "All time", recordWindow: "All time")
        let first = await TrendsPresentationCache().presentation(history, options: options, now: day,
                                                                 calendar: calendar, store: library.store)
        let reopened = try temp.open()
        let restored = try await reopened.trendsHistory()
        #expect(restored.id == history.id)
        let cached = await TrendsPresentationCache().presentation(restored, options: options, now: day.addingTimeInterval(1),
                                                                  calendar: calendar, store: reopened.store)
        #expect(cached.setThresholds.last?.date == first.setThresholds.last?.date)
        let expired = await TrendsPresentationCache().presentation(restored, options: options, now: day.addingTimeInterval(60),
                                                                   calendar: calendar, store: reopened.store)
        #expect(expired.setThresholds.last?.date == day.addingTimeInterval(60))
        let generation = try await reopened.store.trendsCacheGeneration()
        let key = ContentHash(of: Data("late calculation".utf8))
        let id = try #require(restored.activities.first?.activity.id)
        try await reopened.permanentlyDelete(id)
        try await reopened.store.saveTrendsCache(Data("old result".utf8), key: key, generation: generation)
        #expect(try await reopened.store.readTrendsCache(key: key, generation: generation) == nil)
        let afterDelete = try temp.open()
        #expect(try await afterDelete.trendsHistory().activities.isEmpty)
    }

    @Test func diskHistoryRejectsCorruptionAndAlgorithmChanges() async throws {
        let temp = TemporaryLibrary()
        let library = try temp.open()
        _ = try await library.importFile(try Fixtures.FIT.outdoorRide.data())
        let first = try await library.trendsHistory()
        let directory = temp.root.appendingPathComponent("LocalMetadata/TrendsCache")
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for file in files where file.lastPathComponent != "generation" { try Data("broken".utf8).write(to: file) }
        let reopened = try temp.open()
        let repaired = try await reopened.trendsHistory()
        #expect(repaired.id != first.id)
        #expect(repaired.activities.count == first.activities.count)
        #expect(repaired.activities.first?.curve == first.activities.first?.curve)
        var versions = PipelineVersions.current
        versions.decoder += 1
        let upgraded = try temp.open(versions: versions)
        let rebuilt = try await upgraded.trendsHistory()
        #expect(rebuilt.id != repaired.id)
        #expect(rebuilt.activities.first?.isStale == true)
        let excluded = try temp.root.appendingPathComponent("LocalMetadata").resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(excluded.isExcludedFromBackup == true)
    }

    @Test func diskCacheBoundsStorageAndInvalidatesDirectStoreWrites() async throws {
        let temp = TemporaryLibrary(); let library = try temp.open()
        let generation = try await library.store.trendsCacheGeneration()
        for index in 0..<20 {
            try await library.store.saveTrendsCache(Data([UInt8(index)]), key: ContentHash(of: Data("\(index)".utf8)), generation: generation)
        }
        let directory = temp.root.appendingPathComponent("LocalMetadata/TrendsCache")
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 13)
        try await library.store.saveProfile(AthleteProfile())
        #expect(try await library.store.trendsCacheGeneration() != generation)
    }

    @Test func concurrentHistoryRequestsShareSnapshot() async throws {
        let temp = TemporaryLibrary(); let library = try temp.open()
        _ = try await library.importFile(try Fixtures.FIT.outdoorRide.data())
        async let first = library.trendsHistory()
        async let second = library.trendsHistory()
        let (a, b) = try await (first, second)
        #expect(a.id == b.id)
        #expect(try await library.trendsHistory().id == a.id)
    }

    @Test func slidingThresholdsMatchRollingEstimateAcrossDSTAndGaps() {
        var c = calendar; c.timeZone = TimeZone(identifier: "America/New_York")!
        var rows = (-100...160).map { row(Double($0), power: Double(200 + ($0 * $0) % 170), id: "\($0)") }
        rows[110].isStale = true
        rows[111].curve = []
        rows.append(row(-90, power: 900, id: "boundary"))
        let end = day.addingTimeInterval(300 * 86400)
        let points = TrendsAggregation.thresholds(rows.reversed(), range: day..<end, calendar: c)
        var date = day
        var expected: [TrendPoint] = []
        while date < end {
            if let value = TrendsAggregation.estimate(rows, on: date, calendar: c) {
                expected.append(TrendPoint(date: date, value: value))
            }
            date = c.date(byAdding: .day, value: 1, to: date)!
        }
        #expect(points.map(\.date) == expected.map(\.date))
        #expect(points.map(\.value) == expected.map(\.value))
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
        let reused = try await library.trendsHistory()
        #expect(reused.id == first.id)
        let again = try await library.store.derivedResult(owner: .activity(id), kind: cached.kind)
        #expect(again?.computedAt == cached.computedAt)
        let reopened = try temp.open()
        #expect(try await reopened.trendsHistory().activities.first?.curve == item.curve)
        #expect(try await reopened.trendsHistory().id == first.id)
        var profile = try await library.profile()
        profile.thresholdPowerHistory = [.init(effectiveFrom: item.activity.start, watts: 250)]
        _ = try await library.saveProfile(profile)
        let stale = try await library.trendsHistory()
        #expect(stale.id != first.id)
        #expect(stale.activities.first?.isStale == true)
        #expect(stale.activities.first?.metrics == nil)
        try await library.decide(.hidden(true), for: id)
        #expect(try await library.trendsHistory().activities.isEmpty)
    }
}
