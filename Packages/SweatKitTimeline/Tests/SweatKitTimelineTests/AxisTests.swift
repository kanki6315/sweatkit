import Testing
@testable import SweatKitTimeline

/// Ten seconds with a stop over seconds 3, 4 and 5. With the stop collapsed
/// the steps out of samples 3, 4 and 5 add nothing, so the positions are
/// 0 1 2 3 3 3 3 4 5 6: samples 3 to 6 share the seam at 3, and the axis is
/// 9 − 3 = 6 long.
private let collapsedTime = TimelineAxis(mode: .time, count: 10, distance: nil, collapsing: [3..<6])

@Suite struct TimeAxisTests {
    /// On the plain time axis sample i sits at i seconds.
    @Test func plainTimeAxisIsTheSampleIndex() {
        let axis = TimelineAxis(mode: .time, count: 10, distance: nil)
        #expect(axis.positions == [0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
        #expect(axis.total == 9)
        #expect(axis.position(ofSample: 2.5) == 2.5)
        #expect(axis.sample(at: 4.25) == 4.25)
    }

    @Test func positionsAndSamplesAreClampedToTheAxis() {
        let axis = TimelineAxis(mode: .time, count: 10, distance: nil)
        #expect(axis.position(ofSample: -3) == 0)
        #expect(axis.position(ofSample: 40) == 9)
        #expect(axis.sample(at: -3) == 0)
        #expect(axis.sample(at: 100) == 9)
        #expect(axis.sample(at: 9) == 9)
    }

    @Test func collapsedStopPutsItsSamplesOnOneSeam() {
        #expect(collapsedTime.positions == [0, 1, 2, 3, 3, 3, 3, 4, 5, 6])
        #expect(collapsedTime.total == 6)
        #expect(collapsedTime.position(ofSample: 3) == 3)
        #expect(collapsedTime.position(ofSample: 4.5) == 3)
        #expect(collapsedTime.position(ofSample: 6) == 3)
        // Halfway from sample 6 at 3 to sample 7 at 4.
        #expect(collapsedTime.position(ofSample: 6.5) == 3.5)
        #expect(collapsedTime.position(ofSample: 9) == 6)
    }

    /// Left of the seam the cursor is before the stop. On the seam it is the
    /// last sample there, 6, so the next move leaves from the stop's far side.
    @Test func cursorJumpsAcrossACollapsedStop() {
        #expect(collapsedTime.sample(at: 2.5) == 2.5)
        #expect(collapsedTime.sample(at: 3) == 6)
        #expect(collapsedTime.sample(at: 3.5) == 6.5)
        #expect(collapsedTime.sample(at: 6) == 9)
    }

    /// A stop over seconds 0 and 1 of five: positions 0 0 0 1 2. The left
    /// edge is then sample 2, the first moving second.
    @Test func leadingStopCollapsesToTheLeftEdge() {
        let axis = TimelineAxis(mode: .time, count: 5, distance: nil, collapsing: [0..<2])
        #expect(axis.positions == [0, 0, 0, 1, 2])
        #expect(axis.sample(at: 0) == 2)
    }

    @Test func searchesFindTheEdgesOfASeam() {
        #expect(collapsedTime.firstSample(atOrAfter: 3) == 3)
        #expect(collapsedTime.firstSample(after: 3) == 7)
        #expect(collapsedTime.firstSample(atOrAfter: 6.5) == 10)
        #expect(collapsedTime.firstSample(atOrAfter: 0) == 0)
    }
}

@Suite struct DistanceAxisTests {
    /// Sample i sits at its distance from the start: 0, 10, 30, 30, 30, 60 m.
    /// The rider stands still over samples 2 to 4.
    @Test func distanceAxisIsMetresFromTheStart() {
        let axis = TimelineAxis(mode: .distance, count: 6, distance: [0, 10, 30, 30, 30, 60])
        #expect(axis.positions == [0, 10, 30, 30, 30, 60])
        // Halfway from 10 m to 30 m.
        #expect(axis.position(ofSample: 1.5) == 20)
        #expect(axis.sample(at: 20) == 1.5)
        // 30 m is shared by samples 2, 3 and 4, and the last of them is 4.
        #expect(axis.sample(at: 30) == 4)
        // Halfway from 30 m to 60 m.
        #expect(axis.sample(at: 45) == 4.5)
    }

    /// The axis starts at 0 wherever the recorded distance starts.
    @Test func distanceIsMeasuredFromTheFirstSample() {
        let axis = TimelineAxis(mode: .distance, count: 3, distance: [100, 110, 130])
        #expect(axis.positions == [0, 10, 30])
    }

    /// Distance 0 10 30 32 35 65 with a stop over seconds 2 and 3. The steps
    /// are 10, 20, 2, 3 and 30. Collapsing drops the 2 and the 3 that GPS
    /// drift added during the stop, leaving positions 0 10 30 30 30 60.
    @Test func collapsingDropsTheDriftInsideAStop() {
        let distance: [Double] = [0, 10, 30, 32, 35, 65]
        let plain = TimelineAxis(mode: .distance, count: 6, distance: distance)
        #expect(plain.positions == [0, 10, 30, 32, 35, 65])
        let collapsed = TimelineAxis(mode: .distance, count: 6, distance: distance, collapsing: [2..<4])
        #expect(collapsed.positions == [0, 10, 30, 30, 30, 60])
        #expect(collapsed.sample(at: 30) == 4)
        #expect(collapsed.sample(at: 45) == 4.5)
    }
}

@Suite struct AxisChoiceTests {
    @Test func noDistanceFallsBackToTime() throws {
        let prepared = PreparedTimeline(try TimelineData(elevation: [1, 2, 3, 4], distance: nil))
        #expect(prepared.resolve(AxisKey(mode: .distance, collapsesStops: false)) == AxisKey(mode: .time, collapsesStops: false))
        #expect(prepared.axis(AxisKey(mode: .distance, collapsesStops: false)).total == 3)
    }

    /// An indoor ride that recorded a distance of zero throughout has
    /// nothing to lay a distance axis out by.
    @Test func noDistanceCoveredFallsBackToTime() throws {
        let prepared = PreparedTimeline(try TimelineData(elevation: [1, 2, 3, 4], distance: [0, 0, 0, 0]))
        #expect(prepared.resolve(AxisKey(mode: .distance, collapsesStops: true)) == AxisKey(mode: .time, collapsesStops: true))
    }

    /// When every second is inside a stop, collapsing would leave an axis of
    /// no length, so the stops stay.
    @Test func collapsingEverythingIsRefused() throws {
        let data = try TimelineData(elevation: [1, 2, 3, 4], distance: [0, 5, 10, 15], stops: [0..<4])
        let prepared = PreparedTimeline(data)
        #expect(prepared.resolve(AxisKey(mode: .time, collapsesStops: true)) == AxisKey(mode: .time, collapsesStops: false))
        #expect(prepared.resolve(AxisKey(mode: .distance, collapsesStops: true)) == AxisKey(mode: .distance, collapsesStops: false))
        #expect(prepared.axis(AxisKey(mode: .distance, collapsesStops: true)).total == 15)
    }

    @Test func usableRequestsAreKept() throws {
        let data = try TimelineData(elevation: [1, 2, 3, 4], distance: [0, 5, 10, 15], stops: [1..<2])
        let prepared = PreparedTimeline(data)
        let key = AxisKey(mode: .distance, collapsesStops: true)
        #expect(prepared.resolve(key) == key)
        // The 5 m step out of sample 1 is dropped: 0 5 5 10.
        #expect(prepared.axis(key).positions == [0, 5, 5, 10])
    }
}
