import SweatKitAnalysis
import SweatKitDetail
import SweatKitModel
import Testing

@Suite struct AnalysisPresentationTests {
    @Test func fiveHourAnalysisPresentationRemainsBounded() {
        let stream = makeStream(count: 18000, power: Array(repeating: 200, count: 18000))
        let start = ContinuousClock.now
        let detail = DetailPreparation.prepare(DetailInput(stream: stream, sport: .cycling, activityDate: testStart))
        let presentation = DetailAnalysisPresentation.prepare(detail)
        print("Five-hour detail plus analysis preparation: \(start.duration(to: .now))")
        #expect(presentation.charts.allSatisfy { $0.points.count <= 1200 })
        #expect(presentation.powerCurve.allSatisfy { $0.power.value == 200 })
    }

    @Test func powerCurveUsesActivityWindowsAndMarksLongDurationsUnavailable() throws {
        let stream = makeStream(count: 300, power: Array(repeating: 200, count: 300))
        let detail = DetailPreparation.prepare(DetailInput(stream: stream, sport: .cycling, activityDate: testStart))
        let curve = DetailAnalysisPresentation.prepare(detail).powerCurve
        #expect(curve.filter { $0.duration <= 300 }.allSatisfy { $0.power.value == 200 })
        #expect(curve.filter { $0.duration > 300 }.allSatisfy { $0.power.reason == .noValidWindow })
    }

    @Test func paceScaleKeepsRawNearStopValuesAndConvertsUnits() throws {
        #expect(PaceChartScale.minutesPerUnit(speed: 0, units: .metric) == nil)
        #expect(PaceChartScale.minutesPerUnit(speed: -.infinity, units: .metric) == nil)
        #expect(PaceChartScale.minutesPerUnit(speed: 2, units: .metric) == 1000.0 / 120)
        #expect(PaceChartScale.ceiling(units: .imperial) == 30 * 1.609344)
        let slow = 1000.0 / (800 * 60)
        #expect(PaceChartScale.minutesPerUnit(speed: slow, units: .metric) == 800)
        let stream = makeStream(count: 5, speed: [2, slow, nil, 1, 0])
        let detail = DetailPreparation.prepare(DetailInput(stream: stream, sport: .running, activityDate: testStart))
        let chart = try #require(DetailAnalysisPresentation.prepare(detail).charts.first { $0.kind == .speed })
        #expect(chart.points.map(\.value) == [2, slow, 1])
        #expect(chart.points[1].segment != chart.points[2].segment)
        #expect(detail.input.stream.speed[1] == slow)
    }

    @Test func runningFormChartsPreserveGapsAndAreAbsentForOtherSports() {
        var stream = makeStream(count: 3)
        stream.runningStrideLength = Series([1.1, nil, 1.2])
        stream.runningGroundContactTime = Series([0.24, nil, 0.25])
        stream.runningVerticalOscillation = Series([0.08, nil, 0.09])
        let kinds: Set<DetailChartSeries.Kind> = [.runningStrideLength, .runningGroundContactTime, .runningVerticalOscillation]
        func charts(_ sport: Sport) -> [DetailChartSeries] {
            DetailAnalysisPresentation.prepare(DetailPreparation.prepare(DetailInput(stream: stream, sport: sport, activityDate: testStart))).charts.filter { kinds.contains($0.kind) }
        }
        #expect(charts(.running).count == 3)
        #expect(charts(.running).allSatisfy { $0.points.map(\.second) == [0, 2] && $0.points[0].segment != $0.points[1].segment })
        #expect(charts(.walking).isEmpty)
        #expect(charts(.cycling).isEmpty)
        stream.runningStrideLength = Series(missingCount: 3)
        stream.runningGroundContactTime = Series(missingCount: 3)
        stream.runningVerticalOscillation = Series(missingCount: 3)
        #expect(charts(.running).isEmpty)
    }

    @Test func reductionKeepsSpikesAndValleysInTheirOriginalOrder() {
        let values: [Double?] = [10, 11, 1000, 9, -100, 12, 13, 14]
        let points = DetailChartSeries.points(values, budget: 4)
        #expect(points.map(\.second) == [0, 2, 4, 7])
        #expect(points.map(\.value) == [10, 1000, -100, 14])
    }
    @Test func missingDataSplitsLinesEvenWithinOneBucket() {
        let points = DetailChartSeries.points([1, 2, nil, 3, 4, .infinity, 5], budget: 4)
        #expect(points.map(\.second) == [0, 1, 3, 4, 6])
        #expect(points[1].segment != points[2].segment)
        #expect(points[3].segment != points[4].segment)
        #expect(DetailChartSeries.points([nil, nil]).isEmpty)
    }
    @Test func continuousFiveHourSeriesHasBoundedDisplaySize() {
        let values = (0..<18000).map { Optional(Double($0 % 400)) }
        let points = DetailChartSeries.points(values)
        #expect(points.count <= 1200)
        #expect(points.first?.second == 0)
        #expect(points.last?.second == 17999)
        #expect(Set(points.map(\.second)).count == points.count)
    }
    @Test func lapsCoverRecordedBoundariesWithoutInventingLaps() {
        let stream = makeStream(count: 7, power: [100, 100, 100, 200, 200, 200, 200])
        let input = DetailInput(stream: stream, sport: .cycling, lapStarts: [0, 3], activityDate: testStart)
        let laps = DetailAnalysisPresentation.prepare(DetailPreparation.prepare(input)).laps
        #expect(laps.map(\.range) == [0...2, 3...6])
        #expect(laps.map(\.stats.time) == [3, 4])
        #expect(laps.map(\.stats.averagePower) == [100, 200])
        let unmarked = DetailInput(stream: stream, sport: .cycling, activityDate: testStart)
        #expect(DetailAnalysisPresentation.prepare(DetailPreparation.prepare(unmarked)).laps.isEmpty)
    }
    @Test func explicitLapEndsPreserveGapsAndTrailingUnlappedSamples() {
        let stream = makeStream(count: 10, power: [999, 100, 100, 999, 200, 200, 200, 999, 999, 999])
        let laps = [RecordedLap(start: testStart.addingTimeInterval(1), end: testStart.addingTimeInterval(3)),
                    RecordedLap(start: testStart.addingTimeInterval(4), end: testStart.addingTimeInterval(7))]
        let input = DetailInput(stream: stream, sport: .cycling, lapStarts: [1, 4], recordedLaps: laps, activityDate: testStart)
        let shown = DetailAnalysisPresentation.prepare(DetailPreparation.prepare(input)).laps
        #expect(shown.map(\.range) == [1...2, 4...6])
        #expect(shown.map(\.stats.time) == [2, 3])
        #expect(shown.map(\.stats.averagePower) == [100, 200])
    }

    @Test func lapBoundsClampToStreamAndInvalidLapsDoNotInventValues() {
        let stream = makeStream(count: 8)
        let offsets: [(Double, Double)] = [(-2, 2.8), (2.8, 5.7), (5.7, 20), (6, 6), (9, 12), (7, 3)]
        let recorded = offsets.map { RecordedLap(start: testStart.addingTimeInterval($0.0), end: testStart.addingTimeInterval($0.1)) }
        let input = DetailInput(stream: stream, sport: .walking, recordedLaps: recorded, activityDate: testStart)
        let shown = DetailAnalysisPresentation.prepare(DetailPreparation.prepare(input)).laps
        #expect(shown.map(\.range) == [0...1, 2...4, 5...7])
        #expect(shown.map(\.id) == [1, 2, 3])
        let empty = DetailInput(stream: stream, sport: .walking, lapStarts: [0, 4], recordedLaps: [], activityDate: testStart)
        #expect(DetailAnalysisPresentation.prepare(DetailPreparation.prepare(empty)).laps.isEmpty)
    }

    @Test func onFootStopsBreakPaceLines() throws {
        let stream = makeStream(count: 5, speed: [1, 0, 2, nil, 3])
        let input = DetailInput(stream: stream, sport: .walking, activityDate: testStart)
        let chart = try #require(DetailAnalysisPresentation.prepare(DetailPreparation.prepare(input)).charts.first { $0.kind == .speed })
        #expect(chart.points.map(\.second) == [0, 2, 4])
        #expect(Set(chart.points.map(\.segment)).count == 3)
    }

}
