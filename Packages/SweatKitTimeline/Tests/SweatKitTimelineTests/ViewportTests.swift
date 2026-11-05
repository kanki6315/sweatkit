import Testing
@testable import SweatKitTimeline

/// An hour on the time axis: 3,601 samples, 3,600 s long. The closest zoom
/// shows 60 samples' worth, 3,600 × 60 / 3,600 = 60 s.
private let hour = ViewportLimits(axis: TimelineAxis(mode: .time, count: 3601, distance: nil))

@Suite struct ViewportLimitTests {
    @Test func closestZoomShowsAMinuteOfTime() {
        #expect(hour.total == 3600)
        #expect(hour.minimumSpan == 60)
    }

    /// 3,601 samples at a steady 10 m/s cover 36,000 m, so an average minute
    /// covers 36,000 × 60 / 3,600 = 600 m.
    @Test func closestZoomShowsAnAverageMinuteOfDistance() {
        let distance = (0...3600).map { Double($0) * 10 }
        let limits = ViewportLimits(axis: TimelineAxis(mode: .distance, count: 3601, distance: distance))
        #expect(limits.total == 36_000)
        #expect(limits.minimumSpan == 600)
    }

    /// 31 samples are 30 s, less than a minute, so there is nothing to zoom
    /// into: the minimum span is the whole axis.
    @Test func anActivityUnderAMinuteDoesNotZoom() {
        let limits = ViewportLimits(axis: TimelineAxis(mode: .time, count: 31, distance: nil))
        #expect(limits.minimumSpan == 30)
        let zoomed = TimelineViewport.full(limits).zoomed(by: 4, around: 15, limits: limits)
        #expect(zoomed == TimelineViewport(lower: 0, upper: 30))
    }
}

@Suite struct ViewportZoomTests {
    /// Zooming 2× shows 1,800 s. The anchor at 900 s was a quarter of the way
    /// across and stays there: 900 − 0.25 × 1,800 = 450.
    @Test func zoomKeepsTheAnchorInPlace() {
        let zoomed = TimelineViewport.full(hour).zoomed(by: 2, around: 900, limits: hour)
        #expect(zoomed == TimelineViewport(lower: 450, upper: 2250))
        #expect(zoomed.fraction(of: 900) == 0.25)
    }

    /// 3,600 / 1,000 is under the 60 s minimum, so the span stops at 60 s,
    /// centred on the anchor: 1,800 − 0.5 × 60 = 1,770.
    @Test func zoomInStopsAtTheMinimumSpan() {
        let zoomed = TimelineViewport.full(hour).zoomed(by: 1000, around: 1800, limits: hour)
        #expect(zoomed == TimelineViewport(lower: 1770, upper: 1830))
    }

    @Test func zoomOutStopsAtTheWholeAxis() {
        let zoomed = TimelineViewport(lower: 450, upper: 2250).zoomed(by: 0.1, around: 900, limits: hour)
        #expect(zoomed == TimelineViewport(lower: 0, upper: 3600))
    }

    @Test func zoomAtAnEdgeKeepsTheEdge() {
        let full = TimelineViewport.full(hour)
        #expect(full.zoomed(by: 2, around: 0, limits: hour) == TimelineViewport(lower: 0, upper: 1800))
        #expect(full.zoomed(by: 2, around: 3600, limits: hour) == TimelineViewport(lower: 1800, upper: 3600))
    }

    /// Zooming out 2× around the right edge of 0...1,800 would start at
    /// 1,800 − 3,600 = −1,800, which is pushed back to 0.
    @Test func zoomOutIsPushedBackInsideTheAxis() {
        let zoomed = TimelineViewport(lower: 0, upper: 1800).zoomed(by: 0.5, around: 1800, limits: hour)
        #expect(zoomed == TimelineViewport(lower: 0, upper: 3600))
    }
}

@Suite struct ViewportPanTests {
    /// With 1,800 s showing, the left edge can go no further than
    /// 3,600 − 1,800 = 1,800.
    @Test func panStopsAtEitherEnd() {
        let viewport = TimelineViewport(lower: 450, upper: 2250)
        #expect(viewport.panned(by: 300, limits: hour) == TimelineViewport(lower: 750, upper: 2550))
        #expect(viewport.panned(by: 2000, limits: hour) == TimelineViewport(lower: 1800, upper: 3600))
        #expect(viewport.panned(by: -1000, limits: hour) == TimelineViewport(lower: 0, upper: 1800))
    }

    /// 3,000 is 300 past the right edge of 900...2,700 and 100 is 800 before
    /// its left edge.
    @Test func revealMovesJustFarEnough() {
        let viewport = TimelineViewport(lower: 900, upper: 2700)
        #expect(viewport.revealing(3000, limits: hour) == TimelineViewport(lower: 1200, upper: 3000))
        #expect(viewport.revealing(100, limits: hour) == TimelineViewport(lower: 100, upper: 1900))
        #expect(viewport.revealing(1000, limits: hour) == viewport)
    }

    @Test func fractionsAndPositionsAreInverse() {
        let viewport = TimelineViewport(lower: 900, upper: 2700)
        #expect(viewport.fraction(of: 1350) == 0.25)
        #expect(viewport.position(atFraction: 0.75) == 2250)
    }
}

@Suite struct ViewportPinchTests {
    /// Fingers at the middle, spread 2×, not moved: the middle, 1,800 s,
    /// stays in the middle of the 1,800 s now showing.
    @Test func pinchZoomsAroundTheFingers() {
        let pinched = TimelineViewport.full(hour)
            .pinched(scale: 2, startFraction: 0.5, currentFraction: 0.5, limits: hour)
        #expect(pinched == TimelineViewport(lower: 900, upper: 2700))
    }

    /// The same pinch with the fingers moved to three quarters across:
    /// 1,800 s is now under them, so the left edge is 1,800 − 0.75 × 1,800.
    @Test func pinchFollowsTheFingers() {
        let pinched = TimelineViewport.full(hour)
            .pinched(scale: 2, startFraction: 0.5, currentFraction: 0.75, limits: hour)
        #expect(pinched == TimelineViewport(lower: 450, upper: 2250))
    }

    /// Two fingers moved left from the middle to a quarter across, without
    /// spreading, pan: 1,800 − 0.25 × 1,800 = 1,350.
    @Test func twoFingersMovedTogetherPan() {
        let pinched = TimelineViewport(lower: 900, upper: 2700)
            .pinched(scale: 1, startFraction: 0.5, currentFraction: 0.25, limits: hour)
        #expect(pinched == TimelineViewport(lower: 1350, upper: 3150))
    }
}

@Suite struct ViewportConversionTests {
    /// 201 samples with a stop over seconds 50 to 99. Collapsed, samples up
    /// to 50 sit at their index, samples 50 to 100 on the seam at 50, and
    /// sample i after that at i − 50, so the axis is 150 long.
    private let plain = TimelineAxis(mode: .time, count: 201, distance: nil)
    private let collapsed = TimelineAxis(mode: .time, count: 201, distance: nil, collapsing: [50..<100])

    /// Samples 20 and 180 sit at 20 and 180 − 50 = 130 once collapsed.
    @Test func sameSamplesStayOnScreenWhenStopsCollapse() {
        let viewport = TimelineViewport(lower: 20, upper: 180)
        #expect(viewport.converted(from: plain, to: collapsed) == TimelineViewport(lower: 20, upper: 130))
    }

    @Test func sameSamplesStayOnScreenWhenStopsExpand() {
        let viewport = TimelineViewport(lower: 20, upper: 130)
        #expect(viewport.converted(from: collapsed, to: plain) == TimelineViewport(lower: 20, upper: 180))
    }

    /// A right edge on the seam is the stop's last sample, 100.
    @Test func anEdgeOnASeamTakesTheStopWithIt() {
        let viewport = TimelineViewport(lower: 0, upper: 50)
        #expect(viewport.converted(from: collapsed, to: plain) == TimelineViewport(lower: 0, upper: 100))
    }
}

@Suite struct EdgePanTests {
    /// A 300-point timeline with 30-point edge zones.
    @Test func rateGrowsThroughTheEdgeZone() {
        let rate = { (x: Double) in TimelineViewport.edgePanRate(x: x, width: 300, zone: 30) }
        #expect(rate(150) == 0)
        #expect(rate(30) == 0)
        #expect(rate(15) == -0.5)
        #expect(rate(0) == -1)
        #expect(rate(-20) == -1)
        #expect(rate(270) == 0)
        #expect(rate(285) == 0.5)
        #expect(rate(300) == 1)
        #expect(rate(400) == 1)
    }

    @Test func aTimelineNarrowerThanItsZonesDoesNotPan() {
        #expect(TimelineViewport.edgePanRate(x: 5, width: 50, zone: 30) == 0)
    }
}
