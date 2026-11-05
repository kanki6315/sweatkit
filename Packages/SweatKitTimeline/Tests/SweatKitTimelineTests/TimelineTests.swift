import Foundation
import SweatKitModel
import Testing
@testable import SweatKitTimeline

private let british = Locale(identifier: "en_GB")

@Suite struct LapCrossingTests {
    private let laps = [10, 20, 30]

    @Test func passingOverABoundaryCrossesIt() {
        #expect(LapCrossing.crossed(from: 5, to: 15, boundaries: laps) == 0..<1)
        #expect(LapCrossing.crossed(from: 15, to: 5, boundaries: laps) == 0..<1)
        #expect(LapCrossing.crossed(from: 9.5, to: 10.5, boundaries: laps) == 0..<1)
    }

    @Test func landingOnABoundaryCrossesIt() {
        #expect(LapCrossing.crossed(from: 5, to: 10, boundaries: laps) == 0..<1)
        #expect(LapCrossing.crossed(from: 15, to: 10, boundaries: laps) == 0..<1)
    }

    /// The tap came on landing, so moving on from the boundary is silent in
    /// both directions.
    @Test func leavingABoundaryDoesNotCrossItAgain() {
        #expect(LapCrossing.crossed(from: 10, to: 15, boundaries: laps).isEmpty)
        #expect(LapCrossing.crossed(from: 10, to: 5, boundaries: laps).isEmpty)
    }

    @Test func aFastMoveCrossesSeveral() {
        #expect(LapCrossing.crossed(from: 5, to: 35, boundaries: laps) == 0..<3)
        #expect(LapCrossing.crossed(from: 35, to: 5, boundaries: laps) == 0..<3)
        #expect(LapCrossing.crossed(from: 15, to: 30, boundaries: laps) == 1..<3)
    }

    @Test func movingBetweenBoundariesCrossesNone() {
        #expect(LapCrossing.crossed(from: 12, to: 18, boundaries: laps).isEmpty)
        #expect(LapCrossing.crossed(from: 12, to: 12, boundaries: laps).isEmpty)
        #expect(LapCrossing.crossed(from: 5, to: 15, boundaries: []).isEmpty)
    }
}

@Suite struct TickStepTests {
    /// An hour in at most four labels. Every 15 minutes would be
    /// 3,600 / 900 + 1 = 5 labels, so the step is 30 minutes, which is 3.
    @Test func timeStepIsTheSmallestThatFits() {
        #expect(TimelineTicks.step(span: 3600, maximumCount: 4, mode: .time) == 1800)
        #expect(TimelineTicks.step(span: 600, maximumCount: 4, mode: .time) == 300)
        #expect(TimelineTicks.step(span: 18_000, maximumCount: 5, mode: .time) == 7200)
    }

    /// 37.5 km in at most five labels. Every 5 km would be 8 labels, and
    /// every 10 km is 4.
    @Test func distanceStepIsOneTwoOrFiveTimesAPowerOfTen() {
        #expect(TimelineTicks.step(span: 37.5, maximumCount: 5, mode: .distance) == 10)
        #expect(TimelineTicks.step(span: 3.2, maximumCount: 5, mode: .distance) == 1)
        #expect(TimelineTicks.step(span: 0.9, maximumCount: 4, mode: .distance) == 0.5)
    }
}

@Suite struct TickTests {
    private func fractions(_ ticks: [TimelineTick]) -> [Double] {
        ticks.map { ($0.fraction * 10_000).rounded() / 10_000 }
    }

    /// An hour, whole, in at most four labels: every 30 minutes.
    @Test func timeLabelsAreClocks() {
        let axis = TimelineAxis(mode: .time, count: 3601, distance: nil)
        let ticks = TimelineTicks.ticks(
            axis: axis, viewport: TimelineViewport(lower: 0, upper: 3600), mode: .time,
            distance: nil, units: .metric, maximumCount: 4, locale: british
        )
        #expect(ticks == [
            TimelineTick(fraction: 0, label: "0:00"),
            TimelineTick(fraction: 0.5, label: "30:00"),
            TimelineTick(fraction: 1, label: "1:00:00"),
        ])
    }

    /// Zoomed in to 15:00–25:00, 600 s, in at most four labels: every 5
    /// minutes, at 900, 1,200 and 1,500 s.
    @Test func labelsFollowTheViewport() {
        let axis = TimelineAxis(mode: .time, count: 3601, distance: nil)
        let ticks = TimelineTicks.ticks(
            axis: axis, viewport: TimelineViewport(lower: 900, upper: 1500), mode: .time,
            distance: nil, units: .metric, maximumCount: 4, locale: british
        )
        #expect(ticks == [
            TimelineTick(fraction: 0, label: "15:00"),
            TimelineTick(fraction: 0.5, label: "20:00"),
            TimelineTick(fraction: 1, label: "25:00"),
        ])
    }

    /// 3,751 samples at 10 m/s cover 37,500 m. Labels every 10 km sit at
    /// 0, 10,000, 20,000 and 30,000 of 37,500 m: 0, 0.2667, 0.5333 and 0.8.
    @Test func distanceLabelsAreKilometres() {
        let distance = (0...3750).map { Double($0) * 10 }
        let axis = TimelineAxis(mode: .distance, count: distance.count, distance: distance)
        let ticks = TimelineTicks.ticks(
            axis: axis, viewport: TimelineViewport(lower: 0, upper: 37_500), mode: .distance,
            distance: distance, units: .metric, maximumCount: 5, locale: british
        )
        #expect(ticks.map(\.label) == ["0 km", "10 km", "20 km", "30 km"])
        #expect(fractions(ticks) == [0, 0.2667, 0.5333, 0.8])
    }

    /// The same ride is 37,500 / 1,609.344 = 23.3 miles. Every 2 miles would
    /// be 12 labels, and every 5 is 5. Five miles is 8,046.72 m, 0.2146 of
    /// the way.
    @Test func distanceLabelsAreMilesInImperial() {
        let distance = (0...3750).map { Double($0) * 10 }
        let axis = TimelineAxis(mode: .distance, count: distance.count, distance: distance)
        let ticks = TimelineTicks.ticks(
            axis: axis, viewport: TimelineViewport(lower: 0, upper: 37_500), mode: .distance,
            distance: distance, units: .imperial, maximumCount: 5, locale: british
        )
        #expect(ticks.map(\.label) == ["0 mi", "5 mi", "10 mi", "15 mi", "20 mi"])
        #expect(fractions(ticks) == [0, 0.2146, 0.4292, 0.6437, 0.8583])
    }

    /// A short walk of 900 m at 1 m/s in at most four labels: every 0.5 km,
    /// so the labels keep one decimal place.
    @Test func smallStepsKeepTheirDecimals() {
        let distance = (0...900).map { Double($0) }
        let axis = TimelineAxis(mode: .distance, count: distance.count, distance: distance)
        let ticks = TimelineTicks.ticks(
            axis: axis, viewport: TimelineViewport(lower: 0, upper: 900), mode: .distance,
            distance: distance, units: .metric, maximumCount: 4, locale: british
        )
        #expect(ticks.map(\.label) == ["0.0 km", "0.5 km"])
    }

    /// 201 seconds with a stop over seconds 50 to 99, collapsed, so the axis
    /// is 150 long. The labels state true elapsed time, 0 to 200 s, every
    /// minute at most five times: 0:00, 1:00, 2:00 and 3:00.
    /// - 0:00 is at 0.
    /// - 1:00 is inside the stop, on the seam at 50 of 150: 0.3333.
    /// - 2:00 is sample 120 at 120 − 50 = 70: 0.4667. That is 0.1333 after
    ///   the label before it, closer than the 0.2 that five evenly spread
    ///   labels keep, so it is dropped.
    /// - 3:00 is sample 180 at 130: 0.8667.
    @Test func collapsedLabelsStateTrueTimeAndDoNotCrowdASeam() {
        let axis = TimelineAxis(mode: .time, count: 201, distance: nil, collapsing: [50..<100])
        let ticks = TimelineTicks.ticks(
            axis: axis, viewport: TimelineViewport(lower: 0, upper: 150), mode: .time,
            distance: nil, units: .metric, maximumCount: 5, locale: british
        )
        #expect(ticks.map(\.label) == ["0:00", "1:00", "3:00"])
        #expect(fractions(ticks) == [0, 0.3333, 0.8667])
    }

    /// 0 10 30 m: 20 m is halfway between samples 1 and 2.
    @Test func seriesLookupsInterpolate() {
        let series: [Double] = [0, 10, 30]
        #expect(TimelineTicks.value(series, at: 1.5) == 20)
        #expect(TimelineTicks.sample(series, at: 20) == 1.5)
        #expect(TimelineTicks.sample(series, at: 0) == 0)
        #expect(TimelineTicks.sample(series, at: 40) == 2)
    }
}

@Suite struct TimelineDataTests {
    @Test func rejectsBadInput() {
        #expect(throws: TimelineData.Problem.tooFewSamples) {
            try TimelineData(elevation: [1], distance: nil)
        }
        #expect(throws: TimelineData.Problem.countMismatch) {
            try TimelineData(elevation: [1, 2, 3], distance: [0, 1])
        }
        #expect(throws: TimelineData.Problem.invalidElevation(sample: 1)) {
            try TimelineData(elevation: [1, .infinity, 3], distance: nil)
        }
        #expect(throws: TimelineData.Problem.invalidDistance(sample: 2)) {
            try TimelineData(elevation: [1, 2, 3], distance: [0, 5, 4])
        }
        #expect(throws: TimelineData.Problem.invalidDistance(sample: 0)) {
            try TimelineData(elevation: [1, 2, 3], distance: [-1, 5, 6])
        }
        #expect(throws: TimelineData.Problem.invalidDistance(sample: 1)) {
            try TimelineData(elevation: [1, 2, 3], distance: [0, .nan, 6])
        }
    }

    @Test func rejectsBadStops() {
        let elevation: [Double?] = [1, 2, 3, 4, 5, 6]
        #expect(throws: TimelineData.Problem.invalidStop(index: 0)) {
            try TimelineData(elevation: elevation, distance: nil, stops: [3..<3])
        }
        #expect(throws: TimelineData.Problem.invalidStop(index: 1)) {
            try TimelineData(elevation: elevation, distance: nil, stops: [1..<3, 2..<4])
        }
        #expect(throws: TimelineData.Problem.invalidStop(index: 1)) {
            try TimelineData(elevation: elevation, distance: nil, stops: [3..<4, 1..<2])
        }
        #expect(throws: TimelineData.Problem.invalidStop(index: 0)) {
            try TimelineData(elevation: elevation, distance: nil, stops: [4..<7])
        }
    }

    @Test func rejectsBadLapBoundaries() {
        let elevation: [Double?] = [1, 2, 3, 4, 5, 6]
        #expect(throws: TimelineData.Problem.invalidLapBoundary(index: 1)) {
            try TimelineData(elevation: elevation, distance: nil, lapBoundaries: [2, 2])
        }
        #expect(throws: TimelineData.Problem.invalidLapBoundary(index: 0)) {
            try TimelineData(elevation: elevation, distance: nil, lapBoundaries: [6])
        }
        #expect(throws: TimelineData.Problem.invalidLapBoundary(index: 0)) {
            try TimelineData(elevation: elevation, distance: nil, lapBoundaries: [-1])
        }
    }

    /// Missing elevation, touching stops and a stop that runs to the end are
    /// all fine.
    @Test func acceptsValidData() throws {
        let data = try TimelineData(
            elevation: [1, nil, 3, 4, 5, 6],
            distance: [0, 0, 5, 5, 9, 9],
            stops: [0..<2, 2..<3, 4..<6],
            lapBoundaries: [2, 4]
        )
        #expect(data.count == 6)
    }
}

@Suite struct DescriptionTests {
    /// Seven boundaries make eight laps.
    @Test func summaryNamesTheRangesLapsAndStops() {
        let summary = TimelineDescription.summary(
            elevation: 12...240, overlay: (.power, 0...612), lapBoundaries: 7, stops: 3,
            sport: .cycling, units: .metric, locale: british
        )
        #expect(summary == "Elevation from 12 to 240 metres. Power from 0 to 612 watts. 8 laps. 3 stops.")
    }

    /// 1 m/s is 1,000 s per kilometre, 16:40, and 2.5 m/s is 400 s, 6:40.
    @Test func paceIsDescribedAsPace() {
        let summary = TimelineDescription.summary(
            elevation: 5...9, overlay: (.pace, 1...2.5), lapBoundaries: 0, stops: 1,
            sport: .walking, units: .metric, locale: british
        )
        #expect(summary == "Elevation from 5 to 9 metres. Pace from 16 minutes 40 seconds per kilometre "
            + "to 6 minutes 40 seconds per kilometre. 1 stop.")
    }

    @Test func missingSeriesAreSaidToBeMissing() {
        #expect(TimelineDescription.summary(
            elevation: nil, overlay: nil, lapBoundaries: 0, stops: 0,
            sport: .cycling, units: .metric, locale: british
        ) == "No elevation data.")
        #expect(TimelineDescription.summary(
            elevation: nil, overlay: (.heartRate, nil), lapBoundaries: 0, stops: 0,
            sport: .cycling, units: .metric, locale: british
        ) == "No elevation data. No heart rate data.")
    }

    /// 754 s at 5 m/s is 3,770 m.
    @Test func positionIsDistanceAndTime() {
        let distance = (0...1000).map { Double($0) * 5 }
        #expect(TimelineDescription.position(sample: 754, distance: distance, units: .metric, locale: british)
            == "3.77 kilometres, 12 minutes 34 seconds")
        #expect(TimelineDescription.position(sample: 754, distance: nil, units: .metric, locale: british)
            == "12 minutes 34 seconds")
    }
}
