import Foundation
import SweatKitModel
import SweatKitRouteMatching
import Testing

/// Steps 1.2 and 1.3, on signatures written out by hand so that each gate is
/// tested alone and exactly at its threshold.
///
/// "Pick candidates: same sport family, total distance within 10%, start and
/// finish each within 200 m. Shortlist candidates that share at least 85% of
/// their grid cells."
@Suite struct DetectionGateTests {
    let plane = Plane.equator

    /// `count` cells in a row, starting at column `first`.
    private func row(_ first: Int, count: Int) -> Set<GridCell> {
        Set((first..<first + count).map { GridCell(column: $0, row: 0) })
    }

    /// A 1000 m course from (0, 0) to (1000, 0) in 20 cells, unless told
    /// otherwise.
    private func signature(
        family: SportFamily = .cycling,
        length: Double = 1000,
        start: P = P(0, 0),
        finish: P = P(1000, 0),
        cells: Set<GridCell>? = nil
    ) -> TrackSignature {
        TrackSignature(
            sportFamily: family,
            length: length,
            start: plane.coordinate(start),
            finish: plane.coordinate(finish),
            cells: cells ?? row(0, count: 20)
        )
    }

    private func gates(_ candidate: TrackSignature, _ reference: TrackSignature? = nil) -> DetectionGates {
        RouteDetection.gates(candidate: candidate, reference: reference ?? signature())
    }

    // MARK: All gates

    @Test func anIdenticalSignaturePassesEveryGate() {
        let result = gates(signature())
        #expect(result.sameSportFamily)
        #expect(result.distanceWithinTolerance)
        #expect(result.startWithinTolerance)
        #expect(result.finishWithinTolerance)
        #expect(result.sharedCellFraction == 1)
        #expect(result.sharesEnoughCells)
        #expect(result.isCandidate)
        #expect(result.isShortlisted)
    }

    // MARK: Sport family

    @Test func aDifferentSportFamilyIsNotACandidate() {
        let result = gates(signature(family: .onFoot))
        #expect(!result.sameSportFamily)
        #expect(!result.isCandidate)
        #expect(!result.isShortlisted)
    }

    // MARK: Total distance within 10%

    @Test(arguments: [
        (1090.0, true),  // 90 m over, and 10% of 1000 m is 100 m
        (910.0, true),   // 90 m under
        (1100.0, true),  // exactly 10% over: "within 10%" includes 10%
        (900.0, true),   // exactly 10% under
        (1110.0, false), // 110 m over
        (890.0, false),  // 110 m under
    ])
    func totalDistanceMustBeWithinTenPercent(length: Double, passes: Bool) {
        let result = gates(signature(length: length))
        #expect(result.distanceWithinTolerance == passes)
        #expect(result.isCandidate == passes)
    }

    @Test func theTenPercentIsOfTheReferenceDistance() {
        // 1105 m against a 1000 m reference: 105 m apart, limit 100 m. Fails.
        #expect(!gates(signature(length: 1105), signature(length: 1000)).distanceWithinTolerance)
        // 1000 m against a 1105 m reference: 105 m apart, limit 110.5 m. Passes.
        #expect(gates(signature(length: 1000), signature(length: 1105)).distanceWithinTolerance)
    }

    // MARK: Start and finish each within 200 m

    @Test(arguments: [
        (P(199, 0), true),    // 199 m east
        (P(0, -199), true),   // 199 m south
        (P(120, 120), true),  // sqrt(120^2 + 120^2) = 169.7 m
        (P(201, 0), false),   // 201 m east
        (P(150, 150), false), // sqrt(150^2 + 150^2) = 212.1 m
    ])
    func theStartMustBeWithin200Metres(start: P, passes: Bool) {
        let result = gates(signature(start: start))
        #expect(result.startWithinTolerance == passes)
        #expect(result.finishWithinTolerance)
        #expect(result.isCandidate == passes)
    }

    @Test(arguments: [
        (P(1199, 0), true),    // 199 m beyond the reference finish at (1000, 0)
        (P(801, 0), true),     // 199 m short of it
        (P(1000, 199), true),  // 199 m north of it
        (P(1201, 0), false),   // 201 m beyond
        (P(1150, 150), false), // 212.1 m away
    ])
    func theFinishMustBeWithin200Metres(finish: P, passes: Bool) {
        let result = gates(signature(finish: finish))
        #expect(result.finishWithinTolerance == passes)
        #expect(result.startWithinTolerance)
        #expect(result.isCandidate == passes)
    }

    // MARK: Shared cells at least 85%

    @Test func seventeenOfTwentyCellsIsExactlyEnough() {
        // Columns 0..<20 against 3..<23: columns 3...19 are shared, 17 cells.
        // 17 / 20 = 0.85, and "at least 85%" includes 85%.
        let result = gates(signature(cells: row(3, count: 20)))
        #expect(close(result.sharedCellFraction, 0.85, within: 1e-12))
        #expect(result.sharesEnoughCells)
        #expect(result.isShortlisted)
    }

    @Test func sixteenOfTwentyCellsIsNotEnough() {
        // Columns 0..<20 against 4..<24: 16 shared. 16 / 20 = 0.80.
        let result = gates(signature(cells: row(4, count: 20)))
        #expect(close(result.sharedCellFraction, 0.80, within: 1e-12))
        #expect(!result.sharesEnoughCells)
        #expect(result.isCandidate)
        #expect(!result.isShortlisted)
    }

    @Test func theShareIsOfWhicheverTrackHasMoreCells() {
        // 20 cells against 23 that contain them: 20 / 23 = 0.8696. Enough.
        #expect(close(RouteDetection.sharedCellFraction(row(0, count: 20), row(0, count: 23)), 20.0 / 23.0, within: 1e-12))
        #expect(gates(signature(cells: row(0, count: 23))).sharesEnoughCells)
        // 20 cells against 25 that contain them: 20 / 25 = 0.80. Not enough,
        // though every one of the smaller track's cells is shared.
        #expect(close(RouteDetection.sharedCellFraction(row(0, count: 20), row(0, count: 25)), 0.80, within: 1e-12))
        #expect(!gates(signature(cells: row(0, count: 25))).sharesEnoughCells)
    }

    @Test func theShareDoesNotDependOnWhichTrackIsWhich() {
        let small = row(0, count: 20), large = row(0, count: 25)
        #expect(RouteDetection.sharedCellFraction(small, large) == RouteDetection.sharedCellFraction(large, small))
    }

    @Test func tracksWithNoCellInCommonShareNothing() {
        #expect(RouteDetection.sharedCellFraction(row(0, count: 20), row(40, count: 20)) == 0)
        #expect(RouteDetection.sharedCellFraction([], []) == 0)
        #expect(RouteDetection.sharedCellFraction(row(0, count: 5), []) == 0)
    }

    @Test func sharedCellsAloneDoNotShortlist() {
        // Every cell shared, but the finish is 300 m away: not a candidate, so
        // not shortlisted.
        let result = gates(signature(finish: P(1300, 0)))
        #expect(result.sharesEnoughCells)
        #expect(!result.isCandidate)
        #expect(!result.isShortlisted)
    }

    // MARK: Shortlist

    @Test func theShortlistNamesEachReferenceThatPasses() {
        let references = [
            signature(),                         // passes
            signature(family: .onFoot),          // wrong sport family
            signature(length: 1050),             // passes: 50 m apart, limit 105 m
            signature(cells: row(40, count: 20)), // no shared cells
        ]
        #expect(RouteDetection.shortlist(candidate: signature(), references: references) == [0, 2])
        #expect(RouteDetection.shortlist(candidate: signature(), references: []).isEmpty)
    }
}

/// Step 1 on whole tracks. "Detection is cheap and deliberately loose. Cell
/// overlap ignores order, so it cannot tell two laps from three, or an
/// out-and-back from a one-way trip. It only nominates candidates."
///
/// Courses sit at offsets such as 10 m and 30 m so that no resampled point
/// lands on a cell edge.
@Suite struct DetectionCaseTests {
    private func gates(_ candidate: [P], _ reference: [P], candidateFamily: SportFamily = .cycling) throws -> DetectionGates {
        let candidateSignature = try #require(TrackSignature(track: track(candidate, family: candidateFamily)))
        let referenceSignature = try #require(TrackSignature(track: track(reference)))
        return RouteDetection.gates(candidate: candidateSignature, reference: referenceSignature)
    }

    @Test func aRepeatOfTheSameRoadIsShortlisted() throws {
        // 2000 m of road, ridden again 3 m further north. Same row of cells.
        // The two may differ by the one cell at the very end of the road, and
        // 40 / 41 = 0.976.
        let result = try gates(
            Course.eastRoad(from: 10, to: 2010, north: 23),
            Course.eastRoad(from: 10, to: 2010, north: 20)
        )
        #expect(result.isCandidate)
        #expect(result.sharedCellFraction >= 0.97)
        #expect(result.isShortlisted)
    }

    @Test func theSameRoadInAnotherSportFamilyIsNotACandidate() throws {
        let road = Course.eastRoad(from: 10, to: 2010, north: 20)
        let result = try gates(road, road, candidateFamily: .onFoot)
        #expect(!result.sameSportFamily)
        #expect(!result.isShortlisted)
    }

    /// Parallel roads within 50 m of each other. Detection cannot tell them
    /// apart when they run through the same cells, so it nominates the pair
    /// and leaves the decision to alignment.
    @Test func aParallelRoad40MetresAwayInTheSameCellsIsShortlisted() throws {
        // North 5 and north 45 are both in row 0. Starts and finishes are
        // 40 m apart, and the lengths are equal.
        let result = try gates(
            Course.eastRoad(from: 10, to: 2010, north: 45),
            Course.eastRoad(from: 10, to: 2010, north: 5)
        )
        #expect(result.sharedCellFraction >= 0.97)
        #expect(result.isShortlisted)
    }

    /// Two laps against three laps of the same circuit.
    @Test func cellsCannotTellTwoLapsFromThreeButDistanceCan() throws {
        // An 800 m lap resamples to the same 32 positions on every lap, so
        // both tracks record the same cells. 2 laps are 1600 m and 3 are
        // 2400 m: 800 m apart against a limit of 10% of 1600 m = 160 m.
        let result = try gates(
            Course.squareLaps(3, corner: P(10, 10)),
            Course.squareLaps(2, corner: P(10, 10))
        )
        #expect(result.sharedCellFraction == 1)
        #expect(result.startWithinTolerance)
        #expect(result.finishWithinTolerance)
        #expect(!result.distanceWithinTolerance)
        #expect(!result.isShortlisted)
    }

    @Test func twoLapsAreNotACandidateForAThreeLapRoute() throws {
        // 800 m apart against a limit of 10% of 2400 m = 240 m.
        let result = try gates(
            Course.squareLaps(2, corner: P(10, 10)),
            Course.squareLaps(3, corner: P(10, 10))
        )
        #expect(result.sharedCellFraction == 1)
        #expect(!result.distanceWithinTolerance)
        #expect(!result.isShortlisted)
    }

    /// An out-and-back against a one-way trip on the same road.
    @Test func cellsCannotTellAnOutAndBackFromAOneWayTripButTheGatesCan() throws {
        // The one-way road runs from east 30 to 1030 at north 15. The
        // out-and-back returns along north 25, in the same row of cells, so
        // every cell is shared. It is 2010 m against 1000 m, and it finishes
        // at (30, 25), 1000 m from the one-way finish at (1030, 15).
        let result = try gates(
            Course.outAndBack(start: P(30, 15)),
            Course.eastRoad(from: 30, to: 1030, north: 15, step: 10)
        )
        #expect(result.sharedCellFraction == 1)
        #expect(result.startWithinTolerance)
        #expect(!result.finishWithinTolerance)
        #expect(!result.distanceWithinTolerance)
        #expect(!result.isShortlisted)
    }

    @Test func aOneWayTripIsNotACandidateForAnOutAndBackRoute() throws {
        // 1000 m against 2010 m: 1010 m apart, limit 201 m.
        let result = try gates(
            Course.eastRoad(from: 30, to: 1030, north: 15, step: 10),
            Course.outAndBack(start: P(30, 15))
        )
        #expect(!result.distanceWithinTolerance)
        #expect(!result.finishWithinTolerance)
        #expect(!result.isShortlisted)
    }

    /// Order is invisible to detection: a circuit run the other way round has
    /// the same sport, distance, start, finish and cells. Alignment has to
    /// turn it away.
    @Test func aCircuitRunTheOtherWayIsShortlisted() throws {
        let result = try gates(
            Course.squareLapsClockwise(1, corner: P(10, 10)),
            Course.squareLaps(1, corner: P(10, 10))
        )
        #expect(result.sharedCellFraction == 1)
        #expect(result.isShortlisted)
    }

    @Test func aFigureOfEightWithItsLobesSwappedIsShortlisted() throws {
        // Same two lobes, same 1600 m, same start and finish at the centre.
        let result = try gates(
            Course.figureOfEight(centre: P(10, 10), secondLobeFirst: true),
            Course.figureOfEight(centre: P(10, 10))
        )
        #expect(result.sharedCellFraction == 1)
        #expect(result.isShortlisted)
    }

    @Test func aRoadRiddenTheOtherWayFailsTheStartAndFinishGates() throws {
        // The start is at the reference's finish, 1000 m from its start, and
        // the finish likewise. The cells are the same bar perhaps the one at
        // the very end: at least 20 / 21 = 0.952.
        let road = Course.eastRoad(from: 30, to: 1030, north: 15, step: 10)
        let result = try gates(Array(road.reversed()), road)
        #expect(result.sharedCellFraction >= 0.95)
        #expect(result.distanceWithinTolerance)
        #expect(!result.startWithinTolerance)
        #expect(!result.finishWithinTolerance)
        #expect(!result.isShortlisted)
    }

    /// "A start 1 km into a known route must not join."
    @Test func aStartOneKilometreInIsNotACandidate() throws {
        // A 3000 m route joined at its 1000 m point: the start is 1000 m from
        // the route's start, and 2000 m against 3000 m is 1000 m apart with a
        // limit of 300 m. It shares 2000 m of the 3000 m of cells, about 0.67.
        let result = try gates(
            Course.eastRoad(from: 1010, to: 3010, north: 20),
            Course.eastRoad(from: 10, to: 3010, north: 20)
        )
        #expect(!result.startWithinTolerance)
        #expect(result.finishWithinTolerance)
        #expect(!result.distanceWithinTolerance)
        #expect(!result.sharesEnoughCells)
        #expect(!result.isShortlisted)
    }

    /// "A start 20 m late joins." Detection must let it through.
    @Test func aStartTwentyMetresLateIsShortlisted() throws {
        // 1980 m against 2000 m: 20 m apart, limit 200 m. Start 20 m away,
        // finish in the same place, and the same row of cells bar perhaps the
        // one at the very end: at least 40 / 41 = 0.976.
        let result = try gates(
            Course.eastRoad(from: 30, to: 2010, north: 20),
            Course.eastRoad(from: 10, to: 2010, north: 20)
        )
        #expect(result.isCandidate)
        #expect(result.sharedCellFraction >= 0.97)
        #expect(result.isShortlisted)
    }
}
