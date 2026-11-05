import Foundation
import SweatKitAnalysis
import SweatKitModel
import SweatKitTimeline
import SweatKitTrackCleanup
import Testing
@testable import SweatKitDetail

@Suite("Route for the flyover")
struct RouteTests {
    @Test func eachVertexTakesTheBandOfItsSample() throws {
        // Threshold 200 W. Five seconds at 100 W, one with no power, then
        // four at 300 W. 10-second means of the values present:
        //   0...4: 100 → 0.5, zone 0
        //   5: no value → no band, drawn as noValueBand 7
        //   6: (5 × 100 + 300) / 6 = 133.3 → 0.667, zone 1
        //   7: (500 + 600) / 7 = 157.1 → 0.786, zone 2
        //   8: (500 + 900) / 8 = 175 → 0.875, zone 2
        //   9: (500 + 1200) / 9 = 188.9 → 0.944, zone 3
        let stream = makeStream(
            count: 10,
            positions: zigzag(10),
            power: run(100, 5) + [nil] + run(300, 4),
            speed: run(13, 10)
        )
        let detail = DetailPreparation.prepare(makeInput(stream, profile: makeProfile(thresholdPower: 200)))
        let route = try #require(detail.route(for: .power).value)
        #expect(route.sampleIndices == Array(0..<10))
        #expect(route.bands == [0, 0, 0, 0, 0, 7, 1, 2, 2, 3])
        #expect(try #require(detail.route(for: .plain).value).bands == Array(repeating: 0, count: 10))
    }

    @Test func anUnavailableOverlayHasNoRouteButTheOthersDo() {
        let stream = makeStream(count: 10, positions: zigzag(10), power: run(200, 10), speed: run(13, 10))
        let detail = DetailPreparation.prepare(makeInput(stream))
        #expect(detail.route(for: .power).reason == .noThresholdPower)
        #expect(detail.route(for: .plain).value != nil)
    }

    @Test func aVirtualRideHasNoRoute() {
        let stream = makeStream(count: 10, positions: zigzag(10), power: run(200, 10), altitude: run(10, 10))
        let detail = DetailPreparation.prepare(makeInput(stream, virtual: true, profile: makeProfile(thresholdPower: 200)))
        #expect(detail.line.reason == .virtualActivity)
        for overlay in RouteOverlay.allCases {
            #expect(detail.route(for: overlay).reason == .virtualActivity)
        }
        // The charts are still there.
        #expect(detail.timeline?.count == 10)
        #expect(detail.timelineOverlays[.power] != nil)
    }

    @Test func anIndoorRideHasNoRoute() {
        let stream = makeStream(count: 10, positions: zigzag(10), altitude: run(10, 10))
        let detail = DetailPreparation.prepare(makeInput(stream, indoor: true))
        #expect(detail.line.reason == .indoorActivity)
        #expect(detail.timeline != nil)
    }

    @Test func aStreamWithNoPositionsHasNoRoute() throws {
        let stream = makeStream(
            count: 10,
            pauses: .known(paused: [4..<6]),
            heartRate: run(140, 10),
            altitude: run(10, 10)
        )
        let detail = DetailPreparation.prepare(makeInput(stream, sport: .walking))
        #expect(detail.line.reason == .noUsablePositions)
        #expect(detail.route(for: .plain).reason == .noUsablePositions)
        // The timeline still has its data, and the paused span is its only stop.
        let timeline = try #require(detail.timeline)
        #expect(timeline.stops == [4..<6])
        #expect(timeline.distance == nil)
    }

    @Test func oneUsablePositionIsNoRoute() {
        let stream = makeStream(count: 3, positions: [Coordinate(latitude: 51, longitude: 0), nil, nil])
        #expect(DetailPreparation.prepare(makeInput(stream)).line.reason == .noUsablePositions)
    }
}

@Suite("Timeline data")
struct TimelineDataTests {
    @Test func stopsFromCollapsedPointsAndPausedSpans() {
        let a = Coordinate(latitude: 51, longitude: 0)
        let points = [
            CleanedPosition(coordinate: a, sampleIndex: 0),
            CleanedPosition(coordinate: a, sampleIndex: 2, coveredSamples: 2...5),   // a collapsed stop: seconds 2..<6
            CleanedPosition(coordinate: a, sampleIndex: 6),
            CleanedPosition(coordinate: a, sampleIndex: 12, coveredSamples: 12...13), // seconds 12..<14
            CleanedPosition(coordinate: a, sampleIndex: 18, coveredSamples: 18...25), // runs past the end
        ]
        let stops = DetailPreparation.stops(
            collapsed: points,
            pauses: .known(paused: [6..<8, 13..<15]),
            count: 20
        )
        // 2..<6 and the pause 6..<8 touch, so they merge into 2..<8.
        // 12..<14 and the pause 13..<15 overlap: 12..<15.
        // 18..<26 is cut to the stream's 20 seconds: 18..<20.
        #expect(stops == [2..<8, 12..<15, 18..<20])
    }

    @Test func unknownPausePositionsAddNoStops() {
        let stops = DetailPreparation.stops(collapsed: [], pauses: .unknown(statedTimerTime: 100), count: 20)
        #expect(stops.isEmpty)
    }

    @Test func aCollapsedStopReachesTheTimeline() throws {
        // A walk: three seconds heading north at about 2.2 m/s, four seconds
        // standing still at 0.1 m/s (below the 0.5 m/s floor, and within
        // 10 m of where the stop began), then five more seconds walking.
        // Seconds 9 and 10 are paused.
        let step = 0.00002
        var positions: [Coordinate?] = []
        var speed: [Double?] = []
        for second in 0..<12 {
            let along = second < 3 ? Double(second) : second <= 6 ? 3 : Double(second - 3)
            positions.append(Coordinate(latitude: 51 + along * step, longitude: 0))
            speed.append(second >= 3 && second <= 6 ? 0.1 : 2.2)
        }
        let stream = makeStream(
            count: 12,
            pauses: .known(paused: [9..<11]),
            positions: positions,
            speed: speed,
            altitude: run(10, 12)
        )
        let timeline = try #require(DetailPreparation.prepare(makeInput(stream, sport: .walking)).timeline)
        // The stop collapses into its first point, second 3, which stands
        // for seconds 3...6: the half-open stop 3..<7.
        #expect(timeline.stops == [3..<7, 9..<11])
    }

    @Test func lapBoundariesFromTheDevicesLaps() {
        // The first lap's start (0) and one past the end mark nothing;
        // duplicates count once; order does not matter.
        let distance = Series([0, 400, 800, 1200])
        #expect(DetailPreparation.lapBoundaries(lapStarts: [0, 300, 120, 120, 5000], distance: distance, count: 1000) == [120, 300])
    }

    @Test func lapBoundariesFromKilometreSplits() {
        // 400 m a second: 0, 400, 800, 1200, 1600, 2000, 2400, 2800.
        // 1 km is first reached at second 3 (1200 m); 2 km exactly at
        // second 5, which opens the next split; 3 km is never reached.
        let distance = Series((0..<8).map { Double($0) * 400 })
        #expect(DetailPreparation.lapBoundaries(lapStarts: [], distance: distance, count: 8) == [3, 5])
        // A device lap list that marks nothing inside the stream falls back
        // to splits too.
        #expect(DetailPreparation.lapBoundaries(lapStarts: [0], distance: distance, count: 8) == [3, 5])
    }

    @Test func kilometreSplitsAcrossAGapAndAJump() {
        // Second 2 has no distance. 1 km is first reached at second 3
        // (1100 m); then a jump from 1100 to 3500 m crosses the 2 and 3 km
        // marks in one second, which opens only one boundary, at second 4.
        let distance = Series([0, 900, nil, 1100, 3500, 3600])
        #expect(DetailPreparation.lapBoundaries(lapStarts: [], distance: distance, count: 6) == [3, 4])
    }

    @Test func noDistanceAndNoLapsHasNoBoundaries() {
        #expect(DetailPreparation.lapBoundaries(lapStarts: [], distance: Series(missingCount: 5), count: 5).isEmpty)
    }

    @Test func lapStartsFromRecordedLaps() {
        let laps = [
            RecordedLap(start: testStart, end: testStart.addingTimeInterval(12.7)),
            RecordedLap(start: testStart.addingTimeInterval(12.7), end: testStart.addingTimeInterval(30)),
        ]
        // 12.7 s after the start is inside grid second 12.
        #expect(DetailInput.lapStarts(of: laps, streamStart: testStart) == [0, 12])
    }

    @Test func axisDistanceFillsGapsAndNeverDecreases() {
        // Leading gap takes the first distance (5); the gap at second 3
        // takes the last before it (20); the dip to 18 is held at 20.
        let distance = Series([nil, 5, 20, nil, 18, 30])
        #expect(DetailPreparation.axisDistance(distance) == [5, 5, 20, 20, 20, 30])
        #expect(DetailPreparation.axisDistance(Series(missingCount: 3)) == nil)
    }

    @Test func elevationKeepsItsGaps() throws {
        let stream = makeStream(count: 4, altitude: [10, nil, 12, 13], distance: [0, 1, 2, 3])
        let timeline = try #require(DetailPreparation.prepare(makeInput(stream)).timeline)
        #expect(timeline.elevation == [10, nil, 12, 13])
        #expect(timeline.distance == [0, 1, 2, 3])
    }

    @Test func aOneSecondStreamHasNoTimeline() {
        #expect(DetailPreparation.prepare(makeInput(makeStream(count: 1))).timeline == nil)
    }

    @Test func overlaySeriesCarryTheRouteBands() throws {
        // Threshold 200 W, threshold heart rate 200 bpm.
        let stream = makeStream(
            count: 3,
            power: [100, nil, 300],
            heartRate: [162, 180, nil],
            speed: run(8, 3),
            cadence: run(90, 3)
        )
        let detail = DetailPreparation.prepare(makeInput(stream, profile: makeProfile(thresholdPower: 200, thresholdHeartRate: 200)))
        let power = try #require(detail.timelineOverlays[.power])
        #expect(power.values == [100, nil, 300]) // the readings, unsmoothed
        // Bands on 10-second means: 100 → 0.5, zone 0; none; (100 + 300) / 2
        // = 200 → 1.0, zone 3. The missing second is noValueBand 7.
        #expect(power.bands == [0, 7, 3])
        let heartRate = try #require(detail.timelineOverlays[.heartRate])
        #expect(heartRate.bands == [1, 2, 5]) // 0.81 → 1, 0.90 → 2, none → 5
        #expect(detail.timelineOverlays[.speed]?.bands == [2, 2, 2]) // steady speed: middle band
        #expect(detail.timelineOverlays[.pace] == nil)               // a ride shows speed
        #expect(detail.timelineOverlays[.cadence]?.bands == nil)     // never zoned
        #expect(detail.timelineOverlay(for: .gradient) == nil)
        #expect(detail.timelineOverlay(for: .paceOrSpeed)?.kind == .speed)
    }

    @Test func aWalkHasPaceAndNoPowerSeries() {
        let stream = makeStream(count: 3, power: run(200, 3), speed: run(1.4, 3))
        let detail = DetailPreparation.prepare(makeInput(stream, sport: .walking))
        #expect(detail.timelineOverlays[.pace] != nil)
        #expect(detail.timelineOverlays[.speed] == nil)
        #expect(detail.timelineOverlays[.power] == nil)
    }

    @Test func anUnzonedOverlayIsDrawnWithoutBands() {
        let stream = makeStream(count: 3, power: run(200, 3))
        #expect(DetailPreparation.prepare(makeInput(stream)).timelineOverlays[.power]?.bands == nil)
    }
}

extension TimelineOverlay: @retroactive Equatable {
    public static func == (lhs: TimelineOverlay, rhs: TimelineOverlay) -> Bool {
        lhs.kind == rhs.kind && lhs.values == rhs.values && lhs.bands == rhs.bands
    }
}
