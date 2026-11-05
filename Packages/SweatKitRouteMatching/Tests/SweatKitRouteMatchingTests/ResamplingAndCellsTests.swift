import Foundation
import SweatKitModel
import SweatKitRouteMatching
import Testing

/// Step 1.1: "Resample each cleaned track to one point every 25 m and record
/// the 50 m grid cells it passes through."
@Suite struct ResamplingTests {
    let plane = Plane.equator

    private func resampled(_ points: [P]) -> [P] {
        RouteDetection.resample(track(points)).map(plane.point)
    }

    private func expectPoints(_ actual: [P], _ expected: [P]) {
        #expect(actual.count == expected.count)
        for (a, e) in zip(actual, expected) {
            #expect(close(a.e, e.e, within: 0.01) && close(a.n, e.n, within: 0.01), "\(a) is not \(e)")
        }
    }

    @Test func aPointEvery25MetresWhateverTheOriginalSpacing() {
        // A 110 m straight recorded unevenly at 0, 40 and 110 m. One point
        // every 25 m from the start: 0, 25, 50, 75, 100. The next would be at
        // 125 m, past the end, and nothing is added for the last 10 m.
        expectPoints(
            resampled([P(0, 0), P(40, 0), P(110, 0)]),
            [P(0, 0), P(25, 0), P(50, 0), P(75, 0), P(100, 0)]
        )
    }

    @Test func spacingIsMeasuredAlongTheTrackRoundACorner() {
        // 40 m east, then 70 m north: 110 m in all.
        //   25 m: still on the first leg, (25, 0).
        //   50 m: 40 m east + 10 m north, (40, 10).
        //   75 m: 40 + 35, (40, 35).
        //  100 m: 40 + 60, (40, 60).
        expectPoints(
            resampled([P(0, 0), P(40, 0), P(40, 70)]),
            [P(0, 0), P(25, 0), P(40, 10), P(40, 35), P(40, 60)]
        )
    }

    @Test func denseTracksAreThinned() {
        // 60 m recorded every 5 m (13 points) leaves 0, 25 and 50 m.
        expectPoints(
            resampled(Course.eastRoad(to: 60, step: 5)),
            [P(0, 0), P(25, 0), P(50, 0)]
        )
    }

    @Test func aTrackShorterThanTheSpacingKeepsOnlyItsStart() {
        // 20 m long: the only whole multiple of 25 m on it is 0.
        expectPoints(resampled([P(0, 0), P(20, 0)]), [P(0, 0)])
    }

    @Test func aSinglePointResamplesToItself() {
        expectPoints(resampled([P(7, 9)]), [P(7, 9)])
    }

    @Test func anEmptyTrackResamplesToNothing() {
        #expect(RouteDetection.resample(track([])).isEmpty)
    }

    @Test func theSpacingComesFromTheRules() {
        // At a 50 m spacing a 110 m straight gives 0, 50 and 100 m.
        var rules = MatchingRules.standard
        rules.resampleSpacing = 50
        let points = RouteDetection.resample(track([P(0, 0), P(110, 0)]), rules: rules).map(plane.point)
        expectPoints(points, [P(0, 0), P(50, 0), P(100, 0)])
    }
}

/// The 50 m grid. Test tracks keep every resampled point at least 5 m from a
/// cell edge, and never end a whole number of 25 m steps from their start, so
/// the expected cells do not hang on rounding.
@Suite struct GridCellTests {
    let plane = Plane.equator

    private func cell(_ e: Double, _ n: Double) -> GridCell {
        RouteDetection.cell(containing: plane.coordinate(P(e, n)))
    }

    @Test func aCellIsFiftyMetresSquareCountedFromTheOrigin() {
        // column = floor(east / 50), row = floor(north / 50).
        #expect(cell(10, 25) == GridCell(column: 0, row: 0))   // 0.2, 0.5
        #expect(cell(60, 25) == GridCell(column: 1, row: 0))   // 1.2, 0.5
        #expect(cell(130, 270) == GridCell(column: 2, row: 5)) // 2.6, 5.4
    }

    @Test func cellsWestAndSouthRoundDownNotTowardsZero() {
        // floor(-15 / 50) = floor(-0.3) = -1, floor(-25 / 50) = -1.
        #expect(cell(-15, -25) == GridCell(column: -1, row: -1))
        // floor(-90 / 50) = floor(-1.8) = -2, floor(-60 / 50) = floor(-1.2) = -2.
        #expect(cell(-90, -60) == GridCell(column: -2, row: -2))
    }

    @Test func aRoadRecordsEveryCellItsResampledPointsFallIn() {
        // East along north = 25 from east = 10 to 220, 210 m. Resampled at
        // 10, 35, 60, 85, 110, 135, 160, 185, 210, in columns
        // 0, 0, 1, 1, 2, 2, 3, 3, 4. All in row floor(25 / 50) = 0.
        let cells = RouteDetection.cells(of: track(Course.eastRoad(from: 10, to: 220, north: 25, step: 10)))
        #expect(cells == Set((0...4).map { GridCell(column: $0, row: 0) }))
    }

    @Test func cellsIgnoreTheDirectionOfTravel() {
        // The same road ridden west resamples at 220, 195, 170, 145, 120, 95,
        // 70, 45, 20, in columns 4, 3, 3, 2, 2, 1, 1, 0, 0: the same five cells.
        let east = Course.eastRoad(from: 10, to: 220, north: 25, step: 10)
        let west = Array(east.reversed())
        #expect(RouteDetection.cells(of: track(west)) == Set((0...4).map { GridCell(column: $0, row: 0) }))
        #expect(RouteDetection.cells(of: track(west)) == RouteDetection.cells(of: track(east)))
    }

    @Test func aRoadNorthRecordsRows() {
        // North along east = 80 from north = -90 to 70, 160 m. Resampled at
        // -90, -65, -40, -15, 10, 35, 60, in rows -2, -2, -1, -1, 0, 0, 1.
        // Column floor(80 / 50) = 1.
        let cells = RouteDetection.cells(of: track(Course.polyline([P(80, -90), P(80, 70)], step: 10)))
        #expect(cells == Set((-2...1).map { GridCell(column: 1, row: $0) }))
    }

    @Test func theCellSizeComesFromTheRules() {
        // With 100 m cells the same resampled points, 10 to 210, are in columns
        // floor(10..85 / 100) = 0, floor(110..185 / 100) = 1, floor(210 / 100) = 2.
        var rules = MatchingRules.standard
        rules.cellSize = 100
        let road = track(Course.eastRoad(from: 10, to: 220, north: 25, step: 10))
        let cells = RouteDetection.cells(of: road, rules: rules)
        #expect(cells == Set((0...2).map { GridCell(column: $0, row: 0) }))
    }

    @Test func aPositionAlwaysFallsInTheSameCell() {
        // The grid is fixed to the ground, so two tracks through one spot
        // agree on its cell wherever they started.
        // Both pass through (130, 270) and run on 10 m past it.
        let fromTheWest = track([P(30, 270), P(140, 270)])
        let fromTheSouth = track([P(130, 220), P(130, 280)])
        let shared = RouteDetection.cells(of: fromTheWest).intersection(RouteDetection.cells(of: fromTheSouth))
        // fromTheWest resamples at east 30, 55, 80, 105, 130: columns 0, 1, 1,
        // 2, 2 of row 5. fromTheSouth at north 220, 245, 270: rows 4, 4, 5 of
        // column 2. The one cell in both is column 2, row 5.
        #expect(shared == [GridCell(column: 2, row: 5)])
    }
}

@Suite struct TrackSignatureTests {
    let plane = Plane.equator

    @Test func aSignatureRecordsSportLengthEndsAndCells() throws {
        // The road from the cell test: 210 m long, five cells.
        let road = track(Course.eastRoad(from: 10, to: 220, north: 25, step: 10), family: .onFoot)
        let signature = try #require(TrackSignature(track: road))
        #expect(signature.sportFamily == .onFoot)
        #expect(close(signature.length, 210, within: 0.001))
        #expect(signature.start == plane.coordinate(P(10, 25)))
        #expect(signature.finish == plane.coordinate(P(220, 25)))
        #expect(signature.cells == Set((0...4).map { GridCell(column: $0, row: 0) }))
    }

    @Test func aTrackWithoutACourseHasNoSignature() {
        #expect(TrackSignature(track: track([])) == nil)
        #expect(TrackSignature(track: track([P(0, 0)])) == nil)
    }
}
