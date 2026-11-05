import Testing
@testable import SweatKitTimeline

private typealias Point = ReducedSeries.Point

@Suite struct SeriesTableTests {
    /// 1, 9 and 5 are present: their mean is 15 / 3 = 5.
    @Test func meanIsOverTheValuesPresent() {
        let table = SeriesTable(values: [1, nil, 9, 5], count: 4)
        #expect(table.presentCount(0..<4) == 3)
        #expect(table.shownCount(0..<4) == 4)
        #expect(table.mean(0..<4) == 5)
        #expect(table.mean(2..<4) == 7)
        #expect(table.mean(1..<2) == nil)
        #expect(table.range == 1...9)
    }

    /// With sample 2 excluded, 1 and 5 are left: mean 3, range 1 to 5.
    @Test func excludedSamplesCountForNothing() {
        let table = SeriesTable(values: [1, nil, 9, 5], count: 4, excluding: [2..<3])
        #expect(table.shownCount(0..<4) == 3)
        #expect(table.presentCount(0..<4) == 2)
        #expect(table.mean(0..<4) == 3)
        #expect(table.range == 1...5)
    }

    @Test func aShortSeriesIsMissingPastItsEnd() {
        let table = SeriesTable(values: [2, 4], count: 4)
        #expect(table.presentCount(0..<4) == 2)
        #expect(table.mean(0..<4) == 3)
        #expect(table.mean(2..<4) == nil)
    }

    @Test func aValueThatIsNotFiniteIsMissing() {
        let table = SeriesTable(values: [.nan, 4, .infinity], count: 3)
        #expect(table.presentCount(0..<3) == 1)
        #expect(table.mean(0..<3) == 4)
        #expect(table.range == 4...4)
    }

    @Test func aSeriesWithNoValuesHasNoRange() {
        #expect(SeriesTable(values: [nil, nil], count: 2).range == nil)
    }
}

@Suite struct BandTableTests {
    /// Band 0 twice, band 1 three times, band 2 once.
    @Test func commonestBandWins() {
        let table = BandTable(bands: [0, 0, 1, 1, 1, 2], values: [1, 1, 1, 1, 1, 1], count: 6)
        #expect(table.bands == [0, 1, 2])
        #expect(table.commonest(0..<6) == 1)
        #expect(table.commonest(5..<6) == 2)
    }

    /// Samples 0 to 3 hold two of band 0 and two of band 1.
    @Test func lowerBandWinsATie() {
        let table = BandTable(bands: [0, 0, 1, 1, 1, 2], values: [1, 1, 1, 1, 1, 1], count: 6)
        #expect(table.commonest(0..<4) == 0)
    }

    /// Only seconds with a value are counted. Samples 2 and 3 have none, so
    /// band 1 is counted once, at sample 4, against twice for band 0.
    @Test func secondsWithoutAValueAreNotCounted() {
        let table = BandTable(bands: [0, 0, 1, 1, 1, 2], values: [1, 1, nil, nil, 1, 1], count: 6)
        #expect(table.commonest(0..<6) == 0)
        #expect(table.commonest(2..<4) == nil)
    }

    /// Bands need not be small or contiguous.
    @Test func bandsAreKeptAsGiven() {
        let table = BandTable(bands: [7, 7, 300], values: [1, 1, 1], count: 3)
        #expect(table.bands == [7, 300])
        #expect(table.commonest(0..<3) == 7)
        #expect(table.commonest(2..<3) == 300)
    }
}

@Suite struct ReductionTests {
    /// Eight seconds holding 1 to 8, the whole 7 s axis in four columns. The
    /// column edges are at 1.75, 3.5 and 5.25 s, so the columns hold samples
    /// 0–1, 2–3, 4–5 and 6–7. Their means are 1.5, 3.5, 5.5 and 7.5, each
    /// midway between its two samples: 0.5, 2.5, 4.5 and 6.5 s of 7.
    @Test func eachColumnIsTheMeanOfItsSamples() {
        let axis = TimelineAxis(mode: .time, count: 8, distance: nil)
        let table = SeriesTable(values: [1, 2, 3, 4, 5, 6, 7, 8], count: 8)
        let reduced = TimelineReduction.reduce(table, axis: axis, viewport: TimelineViewport(lower: 0, upper: 7), columns: 4)
        #expect(reduced.runs == [[
            Point(x: 0.5 / 7, value: 1.5),
            Point(x: 2.5 / 7, value: 3.5),
            Point(x: 4.5 / 7, value: 5.5),
            Point(x: 6.5 / 7, value: 7.5),
        ]])
    }

    /// Samples 2 and 3 fill the second column and have no value, so the line
    /// breaks there: missing is a gap, never zero.
    @Test func aColumnWithNoValuesIsAGap() {
        let axis = TimelineAxis(mode: .time, count: 8, distance: nil)
        let table = SeriesTable(values: [1, 2, nil, nil, 5, 6, 7, 8], count: 8)
        let reduced = TimelineReduction.reduce(table, axis: axis, viewport: TimelineViewport(lower: 0, upper: 7), columns: 4)
        #expect(reduced.runs == [
            [Point(x: 0.5 / 7, value: 1.5)],
            [Point(x: 4.5 / 7, value: 5.5), Point(x: 6.5 / 7, value: 7.5)],
        ])
    }

    /// A column with some values is their mean: 1 alone in the first column
    /// and 4 alone in the second.
    @Test func aColumnWithSomeValuesIsDrawnFromThem() {
        let axis = TimelineAxis(mode: .time, count: 8, distance: nil)
        let table = SeriesTable(values: [1, nil, nil, 4, 5, 6, 7, 8], count: 8)
        let reduced = TimelineReduction.reduce(table, axis: axis, viewport: TimelineViewport(lower: 0, upper: 7), columns: 4)
        #expect(reduced.runs.count == 1)
        #expect(reduced.runs[0].map(\.value) == [1, 4, 5.5, 7.5])
    }

    /// Zoomed in to seconds 2 to 4 with eight columns, a quarter second
    /// each. Samples 2, 3 and 4 fall in columns 0, 4 and 7, at 0, 0.5 and 1
    /// across, and the columns between hold nothing. Samples 1 and 5, a
    /// second outside each edge, are half a viewport away: −0.5 and 1.5.
    @Test func zoomedInPastOneSamplePerColumnKeepsEverySample() {
        let axis = TimelineAxis(mode: .time, count: 8, distance: nil)
        let table = SeriesTable(values: [1, 2, 3, 4, 5, 6, 7, 8], count: 8)
        let reduced = TimelineReduction.reduce(table, axis: axis, viewport: TimelineViewport(lower: 2, upper: 4), columns: 8)
        #expect(reduced.runs == [[
            Point(x: -0.5, value: 2),
            Point(x: 0, value: 3),
            Point(x: 0.5, value: 4),
            Point(x: 1, value: 5),
            Point(x: 1.5, value: 6),
        ]])
    }

    /// A missing second between two present ones breaks the line when each
    /// sample has its own column.
    @Test func zoomedInGapBreaksTheLine() {
        let axis = TimelineAxis(mode: .time, count: 8, distance: nil)
        let table = SeriesTable(values: [1, 2, 3, nil, 5, 6, 7, 8], count: 8)
        let reduced = TimelineReduction.reduce(table, axis: axis, viewport: TimelineViewport(lower: 2, upper: 4), columns: 8)
        #expect(reduced.runs == [
            [Point(x: -0.5, value: 2), Point(x: 0, value: 3)],
            [Point(x: 1, value: 5), Point(x: 1.5, value: 6)],
        ])
    }

    /// Ten seconds holding 0, 10 … 90 with a stop over seconds 3 to 5,
    /// collapsed: positions 0 1 2 3 3 3 3 4 5 6, in three columns with edges
    /// at 2 and 4.
    /// - Column 0 holds samples 0 and 1: mean 5, at 0.5 of 6.
    /// - Column 1 holds samples 2 to 6, of which 3, 4 and 5 are in the stop
    ///   and left out: mean (20 + 60) / 2 = 40, midway between positions 2
    ///   and 3, at 2.5 of 6.
    /// - Column 2 holds samples 7 to 9: mean 80, midway between 4 and 6.
    @Test func collapsedStopsAddNothingToTheirColumn() {
        let axis = TimelineAxis(mode: .time, count: 10, distance: nil, collapsing: [3..<6])
        let values = (0..<10).map { Double($0) * 10 }
        let table = SeriesTable(values: values, count: 10, excluding: [3..<6])
        let reduced = TimelineReduction.reduce(table, axis: axis, viewport: TimelineViewport(lower: 0, upper: 6), columns: 3)
        #expect(reduced.runs == [[
            Point(x: 0.5 / 6, value: 5),
            Point(x: 2.5 / 6, value: 40),
            Point(x: 5.0 / 6, value: 80),
        ]])
    }

    /// The stop's own seconds have no value here. They are hidden, not
    /// missing, so the line carries on across the seam.
    @Test func aCollapsedStopIsNotAGap() {
        let axis = TimelineAxis(mode: .time, count: 10, distance: nil, collapsing: [3..<6])
        let values: [Double?] = [0, 10, 20, nil, nil, nil, 60, 70, 80, 90]
        let table = SeriesTable(values: values, count: 10, excluding: [3..<6])
        let reduced = TimelineReduction.reduce(table, axis: axis, viewport: TimelineViewport(lower: 0, upper: 6), columns: 3)
        #expect(reduced.runs.count == 1)
        #expect(reduced.runs[0].map(\.value) == [5, 40, 80])
    }

    /// The four columns hold bands 0 0, 1 1, 1 1 and 2 2.
    @Test func eachPointTakesItsColumnsCommonestBand() {
        let axis = TimelineAxis(mode: .time, count: 8, distance: nil)
        let values: [Double?] = [1, 2, 3, 4, 5, 6, 7, 8]
        let table = SeriesTable(values: values, count: 8)
        let bands = BandTable(bands: [0, 0, 1, 1, 1, 1, 2, 2], values: values, count: 8)
        let reduced = TimelineReduction.reduce(table, bands: bands, axis: axis, viewport: TimelineViewport(lower: 0, upper: 7), columns: 4)
        #expect(reduced.runs[0].map(\.band) == [0, 1, 1, 2])
    }

    /// On the distance axis a column is a stretch of road. Distance 0 10 20
    /// 30 40 50 60 70 m in two columns with the edge at 35 m: samples 0 to 3
    /// and 4 to 7.
    @Test func columnsFollowTheDistanceAxis() {
        let axis = TimelineAxis(mode: .distance, count: 8, distance: [0, 10, 20, 30, 40, 50, 60, 70])
        let table = SeriesTable(values: [1, 2, 3, 4, 5, 6, 7, 8], count: 8)
        let reduced = TimelineReduction.reduce(table, axis: axis, viewport: TimelineViewport(lower: 0, upper: 70), columns: 2)
        #expect(reduced.runs == [[
            Point(x: 15.0 / 70, value: 2.5),
            Point(x: 55.0 / 70, value: 6.5),
        ]])
    }

    /// The work per redraw does not grow with the activity: a 5-hour ride,
    /// 18,000 samples, reduces to no more points than columns plus the two
    /// neighbours.
    @Test func aFiveHourRideReducesToTheWidth() {
        let count = 18_000
        let axis = TimelineAxis(mode: .time, count: count, distance: nil)
        let table = SeriesTable(values: (0..<count).map { Double($0 % 300) }, count: count)
        let reduced = TimelineReduction.reduce(table, axis: axis, viewport: TimelineViewport(lower: 0, upper: Double(count - 1)), columns: 400)
        #expect(reduced.runs.count == 1)
        #expect(reduced.runs[0].count == 400)
    }

    @Test func nothingToDrawWithoutAViewportOrColumns() {
        let axis = TimelineAxis(mode: .time, count: 8, distance: nil)
        let table = SeriesTable(values: [1, 2, 3, 4, 5, 6, 7, 8], count: 8)
        #expect(TimelineReduction.reduce(table, axis: axis, viewport: TimelineViewport(lower: 3, upper: 3), columns: 4).runs.isEmpty)
        #expect(TimelineReduction.reduce(table, axis: axis, viewport: TimelineViewport(lower: 0, upper: 7), columns: 0).runs.isEmpty)
    }
}

@Suite struct ValueScaleTests {
    /// A 20 m profile is drawn over 50 m, so 110 m is 10 / 50 of the way up.
    @Test func aFlatProfileIsDrawnOverAtLeastFiftyMetres() {
        let scale = ValueScale.elevation(100...120)
        #expect(scale == ValueScale(lower: 100, upper: 150))
        #expect(scale.height(of: 110) == 0.2)
    }

    @Test func aHillyProfileUsesItsOwnSpan() {
        let scale = ValueScale.elevation(0...400)
        #expect(scale == ValueScale(lower: 0, upper: 400))
        #expect(scale.height(of: 100) == 0.25)
    }

    /// 1 to 8 in four windows of two: the means are 1.5, 3.5, 5.5 and 7.5.
    @Test func overviewRangeIsOverWindowMeans() {
        let table = SeriesTable(values: [1, 2, 3, 4, 5, 6, 7, 8], count: 8)
        #expect(table.overviewRange(windows: 4) == 1.5...7.5)
        // Three windows are 8 / 3 rounded up, 3 long: 1 2 3, 4 5 6 and 7 8.
        #expect(table.overviewRange(windows: 3) == 2...7.5)
        // With a window per sample it is the range of the values.
        #expect(table.overviewRange(windows: 600) == 1...8)
    }

    /// Steady 100 W with one second at 900 W, in windows of two: the spike's
    /// window averages 500 W, so the overview stops at 500 where the raw
    /// range reaches 900. Windows with no value are passed over.
    @Test func aSpikeMovesTheOverviewLessThanTheRange() {
        let table = SeriesTable(values: [100, 100, 900, 100, nil, nil, 100, 100], count: 8)
        #expect(table.range == 100...900)
        #expect(table.overviewRange(windows: 4) == 100...500)
        #expect(SeriesTable(values: [nil, nil], count: 2).overviewRange(windows: 4) == nil)
    }

    /// An overlay is scaled to its overview range until something outside it
    /// is on screen. Then the scale grows just far enough to hold it.
    @Test func anOverlayScaleHoldsWhateverIsOnScreen() {
        #expect(ValueScale.overlay(overview: 100...500, visible: 120...300) == ValueScale(lower: 100, upper: 500))
        #expect(ValueScale.overlay(overview: 100...500, visible: 100...900) == ValueScale(lower: 100, upper: 900))
        #expect(ValueScale.overlay(overview: 100...500, visible: 0...300) == ValueScale(lower: 0, upper: 500))
        #expect(ValueScale.overlay(overview: 100...500, visible: nil) == ValueScale(lower: 100, upper: 500))
        #expect(ValueScale(lower: 0, upper: 200).height(of: 50) == 0.25)
        #expect(ValueScale(lower: 50, upper: 50).height(of: 50) == 0.5)
    }

    /// Only the points inside the viewport count as on screen. The two
    /// neighbours outside it, at −0.5 and 1.5, do not.
    @Test func visibleRangeLeavesOutTheNeighbours() {
        let series = ReducedSeries(runs: [
            [ReducedSeries.Point(x: -0.5, value: 900), ReducedSeries.Point(x: 0, value: 3)],
            [ReducedSeries.Point(x: 1, value: 5), ReducedSeries.Point(x: 1.5, value: 0)],
        ])
        #expect(series.visibleRange == 3...5)
        #expect(ReducedSeries(runs: []).visibleRange == nil)
    }
}
