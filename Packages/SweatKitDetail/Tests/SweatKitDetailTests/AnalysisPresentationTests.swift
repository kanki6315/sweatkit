import SweatKitDetail
import SweatKitModel
import Testing

@Suite struct AnalysisPresentationTests {
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
    @Test func onFootStopsBreakPaceLines() throws {
        let stream = makeStream(count: 5, speed: [1, 0, 2, nil, 3])
        let input = DetailInput(stream: stream, sport: .walking, activityDate: testStart)
        let chart = try #require(DetailAnalysisPresentation.prepare(DetailPreparation.prepare(input)).charts.first { $0.kind == .speed })
        #expect(chart.points.map(\.second) == [0, 2, 4])
        #expect(Set(chart.points.map(\.segment)).count == 3)
    }

}
