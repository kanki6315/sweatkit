/// How far the timeline can zoom and pan.
struct ViewportLimits: Hashable, Sendable {
    /// At the closest zoom the timeline shows what an average minute of the
    /// activity covers: 60 seconds on the time axis, and a minute's average
    /// distance on the distance axis.
    static let closestZoomSamples = 60.0

    /// The length of the axis.
    var total: Double
    /// The shortest stretch of axis the timeline will show.
    var minimumSpan: Double

    init(total: Double, minimumSpan: Double) {
        self.total = total
        self.minimumSpan = minimumSpan
    }

    init(axis: TimelineAxis) {
        total = axis.total
        minimumSpan = axis.total * min(1, Self.closestZoomSamples / Double(axis.count - 1))
    }
}

/// The stretch of the axis that is on screen, in axis units.
struct TimelineViewport: Hashable, Sendable {
    var lower: Double
    var upper: Double

    var span: Double { upper - lower }

    /// The whole axis.
    static func full(_ limits: ViewportLimits) -> TimelineViewport {
        TimelineViewport(lower: 0, upper: limits.total)
    }

    /// How far across the viewport a position is: 0 at the left edge and 1 at
    /// the right. Outside that range the position is off screen.
    func fraction(of position: Double) -> Double {
        span > 0 ? (position - lower) / span : 0
    }

    /// The position at a fraction of the way across the viewport.
    func position(atFraction fraction: Double) -> Double {
        lower + fraction * span
    }

    /// The nearest viewport inside the limits: no shorter than the minimum
    /// span, no longer than the axis, and not past either end. The left edge
    /// is kept where it can be.
    func clamped(to limits: ViewportLimits) -> TimelineViewport {
        let newSpan = min(max(span, limits.minimumSpan), limits.total)
        let newLower = min(max(lower, 0), limits.total - newSpan)
        return TimelineViewport(lower: newLower, upper: newLower + newSpan)
    }

    /// Zooms by `scale`, where 2 shows half as much, keeping `anchor` at the
    /// same place on screen unless a limit moves it.
    func zoomed(by scale: Double, around anchor: Double, limits: ViewportLimits) -> TimelineViewport {
        guard scale > 0, span > 0 else { return clamped(to: limits) }
        let newSpan = min(max(span / scale, limits.minimumSpan), limits.total)
        let newLower = anchor - fraction(of: anchor) * newSpan
        return TimelineViewport(lower: newLower, upper: newLower + newSpan).clamped(to: limits)
    }

    /// The viewport a pinch leads to, starting from this one. The position
    /// that was under the fingers at `startFraction` across the viewport is
    /// now under them at `currentFraction`, so moving both fingers pans while
    /// spreading them zooms.
    func pinched(scale: Double, startFraction: Double, currentFraction: Double, limits: ViewportLimits) -> TimelineViewport {
        guard scale > 0, span > 0 else { return clamped(to: limits) }
        let anchor = position(atFraction: startFraction)
        let newSpan = min(max(span / scale, limits.minimumSpan), limits.total)
        let newLower = anchor - currentFraction * newSpan
        return TimelineViewport(lower: newLower, upper: newLower + newSpan).clamped(to: limits)
    }

    /// Moves the viewport along the axis, stopping at either end.
    func panned(by delta: Double, limits: ViewportLimits) -> TimelineViewport {
        TimelineViewport(lower: lower + delta, upper: upper + delta).clamped(to: limits)
    }

    /// Moves the viewport just far enough to show `position`, without
    /// changing the zoom.
    func revealing(_ position: Double, limits: ViewportLimits) -> TimelineViewport {
        if position < lower { return panned(by: position - lower, limits: limits) }
        if position > upper { return panned(by: position - upper, limits: limits) }
        return self
    }

    /// The viewport on another axis that shows the same samples, for when the
    /// axis mode or the collapsing of stops changes.
    func converted(from old: TimelineAxis, to new: TimelineAxis) -> TimelineViewport {
        let first = old.sample(at: lower)
        let last = old.sample(at: upper)
        return TimelineViewport(
            lower: new.position(ofSample: first),
            upper: new.position(ofSample: last)
        ).clamped(to: ViewportLimits(axis: new))
    }

    /// How fast a drag held near an edge pans the viewport, from -1 at or
    /// past the left edge to 1 at or past the right, and 0 outside both edge
    /// zones. `x`, `width` and `zone` are in points.
    static func edgePanRate(x: Double, width: Double, zone: Double) -> Double {
        guard zone > 0, width > 2 * zone else { return 0 }
        if x < zone { return -min(1, (zone - x) / zone) }
        if x > width - zone { return min(1, (x - (width - zone)) / zone) }
        return 0
    }
}
