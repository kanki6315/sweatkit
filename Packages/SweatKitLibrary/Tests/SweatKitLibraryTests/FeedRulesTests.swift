import Foundation
import SweatKitAnalysis
@testable import SweatKitLibrary
import SweatKitModel
import SweatKitStore
import Testing

/// Metrics with the given figures and nothing else available.
private func metrics(
    timer: Metric<TimeInterval> = .available(90),
    moving: Metric<TimeInterval> = .available(80),
    distance: Metric<Double> = .available(200),
    ascent: Metric<Double> = .available(12),
    averagePower: Metric<Double> = .unavailable(.noPower)
) -> ActivityMetrics {
    let none = Metric<Double>.unavailable(.noStream)
    return ActivityMetrics(
        time: TimeMetrics(elapsed: .available(100), timer: timer, timerIsSummaryOnly: false, moving: moving),
        distance: distance,
        ascent: ascent,
        descent: none,
        power: PowerMetrics(
            coverage: none, average: averagePower, averageShowsCoverage: false, weighted: none,
            intensity: none, load: none, variability: none, work: .unavailable(.noPower)
        ),
        heartRate: HeartRateMetrics(coverage: none, average: none, load: none),
        load: .unavailable(.noStream),
        promptsForThresholdPower: false,
        timeInPowerZones: .unavailable(.noStream),
        timeInHeartRateZones: .unavailable(.noStream),
        timeInGradientBands: .unavailable(.noStream),
        cyclingEfficiency: none,
        onFootEfficiency: none,
        splits: .unavailable(.noStream),
        bestDistances: []
    )
}

/// 1 January 2027, 00:00 UTC.
private let midnight = Date(timeIntervalSince1970: 1_798_761_600)
private let hour = 3600.0
private let source = SourceIdentity(source: .garmin, externalID: "1")

private func row(
    sport: Sport = .walking,
    utcOffset: Int? = 0,
    metrics: ActivityMetrics,
    existing: ActivityRecord? = nil
) -> ActivityRecord {
    FeedRules.row(
        members: [source], primary: source,
        facts: ActivityFacts(ActivityRecord(members: [source], primary: source, sport: sport, start: midnight, utcOffset: utcOffset, elapsedTime: 100, title: "")),
        start: midnight, elapsed: 100, metrics: metrics, existing: existing
    )
}

@Suite struct TitleTests {
    /// Night runs from 21:00 to 04:59, morning to 11:59, afternoon to 16:59
    /// and evening to 20:59.
    @Test(arguments: [
        (0, "Night"), (4, "Night"), (5, "Morning"), (11, "Morning"), (12, "Afternoon"),
        (16, "Afternoon"), (17, "Evening"), (20, "Evening"), (21, "Night"), (23, "Night"),
    ])
    func theTimeOfDayFollowsTheLocalHour(_ hourOfDay: Int, _ word: String) {
        let start = midnight.addingTimeInterval(Double(hourOfDay) * hour)
        #expect(FeedRules.title(sport: .cycling, start: start, utcOffset: 0) == "\(word) ride")
        // The last second of the hour is still that hour.
        #expect(FeedRules.title(sport: .cycling, start: start.addingTimeInterval(hour - 1), utcOffset: 0) == "\(word) ride")
    }

    @Test func theHourIsTheActivitysOwnNotUTCs() {
        // 02:00 UTC is 21:00 the day before five hours west, and 11:30 in
        // a zone nine and a half hours east.
        let start = midnight.addingTimeInterval(2 * hour)
        #expect(FeedRules.localHour(of: start, utcOffset: -5 * 3600) == 21)
        #expect(FeedRules.localHour(of: start, utcOffset: 9 * 3600 + 1800) == 11)
        #expect(FeedRules.title(sport: .running, start: start, utcOffset: -5 * 3600) == "Night run")
        #expect(FeedRules.title(sport: .running, start: start, utcOffset: 9 * 3600 + 1800) == "Morning run")
        // A date before 1970 still has an hour between 0 and 23.
        #expect(FeedRules.localHour(of: Date(timeIntervalSince1970: -1), utcOffset: 0) == 23)
    }

    @Test func eachSportHasItsNoun() {
        let start = midnight.addingTimeInterval(8 * hour)
        #expect(FeedRules.title(sport: .cycling, start: start, utcOffset: 0) == "Morning ride")
        #expect(FeedRules.title(sport: .walking, start: start, utcOffset: 0) == "Morning walk")
        #expect(FeedRules.title(sport: .running, start: start, utcOffset: 0) == "Morning run")
        #expect(FeedRules.title(sport: .hiking, start: start, utcOffset: 0) == "Morning hike")
        #expect(FeedRules.title(sport: .other, start: start, utcOffset: 0) == "Morning activity")
    }

    @Test func virtualAndIndoorAreNamed() {
        let start = midnight.addingTimeInterval(18 * hour)
        #expect(FeedRules.title(sport: .cycling, isIndoor: true, isVirtual: true, start: start, utcOffset: 0) == "Evening virtual ride")
        #expect(FeedRules.title(sport: .cycling, isIndoor: true, start: start, utcOffset: 0) == "Evening indoor ride")
        #expect(FeedRules.title(sport: .running, isIndoor: true, start: start, utcOffset: 0) == "Evening indoor run")
    }

    @Test func anUnknownOffsetLeavesTheTimeOfDayOut() {
        #expect(FeedRules.title(sport: .cycling, start: midnight, utcOffset: nil) == "Ride")
        #expect(FeedRules.title(sport: .cycling, isIndoor: true, isVirtual: true, start: midnight, utcOffset: nil) == "Virtual ride")
        #expect(FeedRules.title(sport: .other, start: midnight, utcOffset: nil) == "Activity")
    }

    /// The spec's own example: "Morning ride, Richmond Park".
    @Test func aLocalityFollowsAfterAComma() {
        let start = midnight.addingTimeInterval(8 * hour)
        #expect(FeedRules.title(sport: .cycling, start: start, utcOffset: 0, locality: "Richmond Park") == "Morning ride, Richmond Park")
        #expect(FeedRules.title(sport: .cycling, start: start, utcOffset: 0, locality: "") == "Morning ride")
    }
}

/// "Unavailable is its own state, never zero", in the feed row.
@Suite struct FeedRowTests {
    @Test func availableFiguresFillTheRow() {
        let row = row(metrics: metrics())
        #expect(row.elapsedTime == 100)
        #expect(row.timerTime == 90)
        #expect(row.movingTime == 80)
        #expect(row.distance == 200)
        #expect(row.ascent == 12)
        // 80 s over 0.2 km is 400 s per kilometre.
        #expect(row.headline == .init(kind: "averagePace", value: .available(400)))
        #expect(row.title == "Night walk")
        #expect(!row.isHidden)
    }

    @Test func unavailableFiguresStayUnavailable() {
        let row = row(metrics: metrics(
            timer: .unavailable(.notStated),
            moving: .unavailable(.pausePositionsUnknown),
            distance: .unavailable(.noDistance),
            ascent: .unavailable(.noAltitude)
        ))
        #expect(row.timerTime == nil)
        #expect(row.movingTime == nil)
        #expect(row.distance == nil)
        #expect(row.ascent == nil)
        // The pace says why, with the first reason that applies.
        #expect(row.headline == .init(kind: "averagePace", value: .unavailable(.pausePositionsUnknown)))
    }

    @Test func paceIsUnavailableWithoutADistanceToDivideBy() {
        #expect(FeedRules.averagePace(metrics(distance: .unavailable(.noDistance))) == .unavailable(.noDistance))
        #expect(FeedRules.averagePace(metrics(distance: .available(0))) == .unavailable(.zeroDenominator))
        // Timer time is not used in place of a moving time that is unknown.
        #expect(FeedRules.averagePace(metrics(moving: .unavailable(.pausePositionsUnknown))) == .unavailable(.pausePositionsUnknown))
    }

    @Test func aRideWithPowerHasItAsItsHeadline() {
        let row = row(sport: .cycling, metrics: metrics(averagePower: .available(187.5)))
        #expect(row.headline == .init(kind: "averagePower", value: .available(187.5)))
        // A recorded average of 0 W is a measurement, not a missing value.
        #expect(FeedRules.headline(sport: .cycling, metrics: metrics(averagePower: .available(0)))
            == .init(kind: "averagePower", value: .available(0)))
    }

    @Test func aRideWithoutPowerAndAnyOtherSportHaveNoHeadline() {
        #expect(row(sport: .cycling, metrics: metrics()).headline == nil)
        #expect(row(sport: .other, metrics: metrics(averagePower: .available(150))).headline == nil)
    }

    @Test func aHikeTakesThePaceHeadline() {
        #expect(row(sport: .hiking, metrics: metrics()).headline?.kind == "averagePace")
        #expect(row(sport: .running, metrics: metrics()).headline?.kind == "averagePace")
    }

    @Test func aGeneratedTitleIsGeneratedAgainAndAWrittenOneIsKept() {
        var existing = row(sport: .cycling, metrics: metrics())
        #expect(existing.title == "Night ride")
        // The same activity turns out to be a walk: the title follows.
        #expect(row(sport: .walking, metrics: metrics(), existing: existing).title == "Night walk")

        existing.title = "Lap of the park"
        existing.isHidden = true
        let rebuilt = row(sport: .walking, metrics: metrics(), existing: existing)
        #expect(rebuilt.title == "Lap of the park")
        #expect(rebuilt.isHidden)
    }
}

@Suite struct PipelineVersionsTests {
    private let original = ContentHash(of: Data("an original".utf8))

    @Test func currentHoldsEveryOneOfAnalysissVersions() {
        let current = PipelineVersions.current.algorithms
        #expect(current["analysis.time"] == AlgorithmVersion.time)
        #expect(current["analysis.distance"] == AlgorithmVersion.distance)
        #expect(current["analysis.elevation"] == AlgorithmVersion.elevation)
        #expect(current["analysis.zones"] == AlgorithmVersion.zones)
        #expect(current["analysis.power"] == AlgorithmVersion.power)
        #expect(current["analysis.weightedPower"] == AlgorithmVersion.weightedPower)
        #expect(current["analysis.powerCurve"] == AlgorithmVersion.powerCurve)
        #expect(current["analysis.heartRate"] == AlgorithmVersion.heartRate)
        #expect(current["analysis.load"] == AlgorithmVersion.load)
        #expect(current["analysis.efficiency"] == AlgorithmVersion.efficiency)
        #expect(current["analysis.splits"] == AlgorithmVersion.splits)
        #expect(current["analysis.bestDistances"] == AlgorithmVersion.bestDistances)
        // Analysis's twelve and this package's two.
        #expect(current.count == 14)
        #expect(PipelineVersions.current.streamRules == 1)
    }

    @Test(arguments: PipelineVersions.current.algorithms.keys.sorted())
    func changingAnyOneAlgorithmChangesTheCombinedVersion(_ name: String) throws {
        var changed = PipelineVersions.current
        changed.algorithms[name] = try #require(changed.algorithms[name]) + 1
        #expect(changed.combinedAlgorithmVersion != PipelineVersions.current.combinedAlgorithmVersion)
        // Only the algorithms: the input revision is another matter.
        #expect(changed.inputRevision(original: original) == PipelineVersions.current.inputRevision(original: original))
    }

    @Test func raisingOneVersionAndLoweringAnotherStillChangesIt() {
        var changed = PipelineVersions.current
        changed.algorithms["analysis.elevation"] = AlgorithmVersion.elevation + 1
        changed.algorithms["analysis.zones"] = AlgorithmVersion.zones - 1
        #expect(changed.combinedAlgorithmVersion != PipelineVersions.current.combinedAlgorithmVersion)
    }

    @Test func addingOrRemovingAnAlgorithmChangesIt() {
        var added = PipelineVersions.current
        added.algorithms["analysis.somethingNew"] = 1
        var removed = PipelineVersions.current
        removed.algorithms["analysis.powerCurve"] = nil
        let all = [PipelineVersions.current, added, removed].map(\.combinedAlgorithmVersion)
        #expect(Set(all).count == 3)
    }

    @Test func theCombinedVersionIsStableAndNeverNegative() {
        #expect(PipelineVersions.current.combinedAlgorithmVersion == PipelineVersions.current.combinedAlgorithmVersion)
        #expect(PipelineVersions.current.combinedAlgorithmVersion >= 0)
        #expect(PipelineVersions(decoder: 1, streamRules: 1, algorithms: [:]).combinedAlgorithmVersion >= 0)
    }

    @Test func theInputRevisionChangesWithTheOriginalTheDecoderAndTheStreamRules() {
        let current = PipelineVersions.current
        var decoder = current
        decoder.decoder += 1
        var rules = current
        rules.streamRules += 1
        let revisions = [
            current.inputRevision(original: original),
            current.inputRevision(original: ContentHash(of: Data("another original".utf8))),
            decoder.inputRevision(original: original),
            rules.inputRevision(original: original),
        ]
        #expect(Set(revisions).count == 4)
        // Neither changes the algorithm version.
        #expect(decoder.combinedAlgorithmVersion == current.combinedAlgorithmVersion)
        #expect(rules.combinedAlgorithmVersion == current.combinedAlgorithmVersion)
    }
}
