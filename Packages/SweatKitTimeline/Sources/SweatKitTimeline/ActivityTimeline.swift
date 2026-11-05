import Foundation
import SweatKitModel
import SwiftUI

/// The glass timeline that floats at the bottom of the detail screen, and the
/// screen's main control.
///
/// It draws the elevation profile with one overlay series on top, on a
/// distance or time axis, with detected stops shaded or collapsed and lap
/// boundaries as tick marks.
///
/// - Dragging scrubs: it writes the sample under the finger to `scrubSample`.
/// - Pinching zooms, and two fingers moved together pan. A drag held at
///   either edge of a zoomed timeline pans as well.
/// - Pressing and holding, then dragging, selects a range and writes it to
///   `selection`. The caller supplies that range's stats, which are shown
///   above the chart. Pressing and holding without dragging clears it.
/// - The cursor crossing a lap boundary during a scrub gives a haptic tap.
///
/// The chart is reduced to one column per point of width from tables built
/// off the main thread, and is not redrawn while scrubbing: only the cursor
/// moves.
///
/// For VoiceOver the timeline is one adjustable element. Swiping up and down
/// moves the cursor, the zoom gesture zooms, actions set and clear the
/// selection, and the chart is offered as an audio graph with a description.
public struct ActivityTimeline: View {
    /// How long a press is held before it starts a selection.
    static let holdDuration = Duration.milliseconds(450)
    /// How far a finger can drift, in points, and still be holding.
    static let holdSlop: CGFloat = 10
    /// The width of the zone at each edge where a held drag pans.
    static let edgeZone: CGFloat = 28
    /// How fast a drag held at the very edge pans, in viewports per second.
    static let edgePanSpeed = 0.8
    /// The height of the chart, without its axis labels.
    static let chartHeight: CGFloat = 92

    private let data: TimelineData
    private let overlay: TimelineOverlay?
    @Binding private var scrubSample: Double
    @Binding private var selection: ClosedRange<Int>?
    private let selectionStats: RangeStats?
    private let axisMode: TimelineAxisMode
    private let collapsesStops: Bool
    private let sport: Sport
    private let units: UnitSystem

    @State private var prepared: PreparedTimeline?
    @State private var preparedOverlay: (overlay: PreparedOverlay, data: UUID)?
    /// The visible stretch of the axis, or nil for all of it.
    @State private var viewport: TimelineViewport?
    @State private var touch = TouchState()
    @State private var lapTaps = 0
    @State private var selectionTaps = 0
    /// Where a selection made with VoiceOver actions starts.
    @State private var spokenAnchor: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption2) private var labelHeight: CGFloat = 18
    @ScaledMetric(relativeTo: .caption2) private var tickLabelWidth: CGFloat = 50

    /// - Parameters:
    ///   - data: The activity's elevation, distance, stops and laps.
    ///   - overlay: The series drawn over the elevation, or nil for none.
    ///   - scrubSample: The sample under the cursor. Fractional values sit
    ///     between samples. The same binding can drive `FlyoverMap`.
    ///   - selection: The selected range of samples, or nil. The timeline
    ///     sets and clears it, and the caller may too.
    ///   - selectionStats: The stats of `selection`, worked out by the
    ///     caller. Until they are supplied the range's stats show as dashes.
    ///   - axisMode: Distance or time. An activity with no distance is drawn
    ///     on the time axis whatever this says.
    ///   - collapsesStops: Whether detected stops are closed up.
    ///   - sport: Decides whether a range shows power, and the cadence unit
    ///     VoiceOver reads.
    public init(
        data: TimelineData,
        overlay: TimelineOverlay?,
        scrubSample: Binding<Double>,
        selection: Binding<ClosedRange<Int>?>,
        selectionStats: RangeStats? = nil,
        axisMode: TimelineAxisMode = .distance,
        collapsesStops: Bool = false,
        sport: Sport,
        units: UnitSystem = .metric
    ) {
        self.data = data
        self.overlay = overlay
        self._scrubSample = scrubSample
        self._selection = selection
        self.selectionStats = selectionStats
        self.axisMode = axisMode
        self.collapsesStops = collapsesStops
        self.sport = sport
        self.units = units
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if selection != nil { selectionRow }
            chart
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .modifier(FloatingPanel())
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: selection != nil)
        .sensoryFeedback(.impact(weight: .light), trigger: lapTaps)
        .sensoryFeedback(.selection, trigger: selectionTaps)
        .task(id: data.id) {
            let made = await PreparedTimeline.make(data)
            guard !Task.isCancelled else { return }
            prepared = made
        }
        .task(id: OverlayRequest(data: data.id, overlay: overlay?.id)) {
            guard let overlay else {
                preparedOverlay = nil
                return
            }
            let made = await PreparedOverlay.make(overlay, data: data)
            guard !Task.isCancelled else { return }
            preparedOverlay = (made, data.id)
        }
        .onChange(of: data.id) {
            touch.cancel()
            viewport = nil
            spokenAnchor = nil
        }
        .onChange(of: resolvedKey) { old, new in
            // Keep the same samples on screen when the axis changes.
            guard let prepared = current, let old, let new, let visible = viewport else { return }
            viewport = visible.converted(from: prepared.axis(old), to: prepared.axis(new))
        }
        .onChange(of: scrubSample) { _, sample in
            // Follow a cursor that playback moves off screen.
            guard let frame = currentFrame, let visible = viewport, !touch.isPinching else { return }
            let revealed = visible.clamped(to: frame.limits)
                .revealing(frame.axis.position(ofSample: sample), limits: frame.limits)
            if revealed != visible { viewport = revealed }
        }
    }

    // MARK: State

    private struct OverlayRequest: Hashable {
        var data: UUID
        var overlay: UUID?
    }

    /// The tables for the data now shown, or nil while they are being built.
    private var current: PreparedTimeline? {
        prepared?.data.id == data.id ? prepared : nil
    }

    /// The overlay's tables. While a newly chosen overlay is being prepared
    /// the one before it stays up, as long as it belongs to the same data.
    private var currentOverlay: PreparedOverlay? {
        guard overlay != nil, let preparedOverlay, preparedOverlay.data == data.id else { return nil }
        return preparedOverlay.overlay
    }

    private var resolvedKey: AxisKey? {
        current?.resolve(AxisKey(mode: axisMode, collapsesStops: collapsesStops))
    }

    private var currentFrame: Frame? {
        guard let prepared = current, let key = resolvedKey else { return nil }
        let axis = prepared.axis(key)
        return Frame(axis: axis, limits: ViewportLimits(axis: axis), width: touch.width)
    }

    private func visible(_ limits: ViewportLimits) -> TimelineViewport {
        (viewport ?? .full(limits)).clamped(to: limits)
    }

    // MARK: Chart

    private var chart: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            if let prepared = current, let key = resolvedKey, width > 0 {
                let axis = prepared.axis(key)
                let frame = Frame(axis: axis, limits: ViewportLimits(axis: axis), width: width)
                let visible = visible(frame.limits)
                ZStack(alignment: .topLeading) {
                    TimelineChart(renderer: TimelineChartRenderer(
                        prepared: prepared,
                        overlay: currentOverlay,
                        key: key,
                        viewport: visible,
                        units: units,
                        locale: locale,
                        chartHeight: Self.chartHeight,
                        tickLabelWidth: tickLabelWidth,
                        increasedContrast: contrast == .increased
                    ))
                    .equatable()
                    selectionBand(frame: frame, visible: visible)
                    cursor(frame: frame, visible: visible)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { dragChanged($0, frame: frame) }
                        .onEnded { _ in dragEnded() }
                )
                .onPinch { pinchChanged($0, frame: frame) }
                .onChange(of: width, initial: true) { touch.width = width }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Timeline")
                .accessibilityValue(TimelineDescription.position(
                    sample: scrubSample, distance: data.distance, units: units, locale: locale
                ))
                .accessibilityAdjustableAction { direction in
                    adjust(direction, frame: frame)
                }
                .accessibilityZoomAction { action in
                    let anchor = axis.position(ofSample: scrubSample)
                    let scale: Double = action.direction == .zoomIn ? 2 : 0.5
                    viewport = self.visible(frame.limits).zoomed(by: scale, around: anchor, limits: frame.limits)
                }
                .accessibilityAction(named: "Start selection here") {
                    spokenAnchor = scrubSample
                    select(from: scrubSample, to: scrubSample)
                }
                .accessibilityAction(named: "End selection here") {
                    select(from: spokenAnchor ?? Double(selection?.lowerBound ?? 0), to: scrubSample)
                }
                .accessibilityAction(named: "Clear selection") {
                    spokenAnchor = nil
                    selection = nil
                }
                .accessibilityChartDescriptor(TimelineChartDescriptor(
                    prepared: prepared, overlay: currentOverlay, key: key,
                    sport: sport, units: units, locale: locale
                ))
            }
        }
        .frame(height: Self.chartHeight + labelHeight)
    }

    /// The scrub cursor, in the accent colour. It is the only part of the
    /// timeline that moves during a scrub.
    @ViewBuilder
    private func cursor(frame: Frame, visible: TimelineViewport) -> some View {
        let fraction = visible.fraction(of: frame.axis.position(ofSample: scrubSample))
        if fraction >= 0, fraction <= 1 {
            let width: CGFloat = contrast == .increased ? 4 : 3
            Capsule()
                .fill(.tint)
                .frame(width: width, height: Self.chartHeight + 4)
                .offset(x: fraction * frame.width - width / 2, y: -2)
                .allowsHitTesting(false)
        }
    }

    /// The selected range, as a neutral band with an edge at each end.
    @ViewBuilder
    private func selectionBand(frame: Frame, visible: TimelineViewport) -> some View {
        if let selection {
            let start = visible.fraction(of: frame.axis.position(ofSample: Double(selection.lowerBound)))
            let end = visible.fraction(of: frame.axis.position(ofSample: Double(selection.upperBound)))
            if end >= 0, start <= 1 {
                let left = min(max(start, 0), 1) * frame.width
                let right = min(max(end, 0), 1) * frame.width
                Rectangle()
                    .fill(.primary.opacity(contrast == .increased ? 0.3 : 0.2))
                    .overlay(alignment: .leading) {
                        if start >= 0 { Rectangle().fill(.primary.opacity(0.8)).frame(width: 1) }
                    }
                    .overlay(alignment: .trailing) {
                        if end <= 1 { Rectangle().fill(.primary.opacity(0.8)).frame(width: 1) }
                    }
                    .frame(width: max(right - left, 1), height: Self.chartHeight)
                    .offset(x: left)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: Selection stats

    private var selectionRow: some View {
        HStack(alignment: .top, spacing: 8) {
            let slots = StatSlots.range(selectionStats, sport: sport, units: units, locale: locale)
            if dynamicTypeSize.isAccessibilitySize {
                // At the accessibility sizes the slots would stack into a
                // column taller than the chart, so they stay in one row that
                // scrolls sideways.
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 20) {
                        ForEach(slots) { StatSlotView(slot: $0, style: .compact) }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            } else {
                StatGridLayout(maximumColumns: 5, spacing: 8, rowSpacing: 4) {
                    ForEach(slots) { StatSlotView(slot: $0, style: .compact) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                spokenAnchor = nil
                selection = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // The button's touch area reaches into the panel's padding, so
            // the symbol lines up with the chart's right edge.
            .padding(.trailing, -11)
            .accessibilityLabel("Clear selection")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Selection")
    }

    // MARK: Scrubbing

    /// Moves the cursor, with a haptic tap when it crosses a lap boundary.
    private func scrub(to sample: Double) {
        let clamped = min(max(sample, 0), Double(data.count - 1))
        guard clamped != scrubSample else { return }
        if !LapCrossing.crossed(from: scrubSample, to: clamped, boundaries: data.lapBoundaries).isEmpty {
            lapTaps += 1
        }
        scrubSample = clamped
    }

    private func select(from anchor: Double, to sample: Double) {
        let last = Double(data.count - 1)
        let low = Int(min(max(min(anchor, sample), 0), last).rounded())
        let high = Int(min(max(max(anchor, sample), 0), last).rounded())
        selection = low...high
    }

    private func sample(at x: CGFloat, frame: Frame) -> Double {
        let fraction = frame.width > 0 ? min(max(x / frame.width, 0), 1) : 0
        return frame.axis.sample(at: visible(frame.limits).position(atFraction: fraction))
    }

    private func dragChanged(_ value: DragGesture.Value, frame: Frame) {
        touch.frame = frame
        touch.location = value.location
        if touch.isPinching { touch.mode = .cancelled }
        if touch.mode == nil {
            // The finger has just come down. If it stays put it is a hold,
            // which starts a selection.
            touch.mode = .scrubbing
            touch.startLocation = value.location
            touch.startScrub = scrubSample
            touch.holdTask = Task {
                try? await Task.sleep(for: Self.holdDuration)
                guard !Task.isCancelled, case .scrubbing = touch.mode, let frame = touch.frame else { return }
                let anchor = sample(at: touch.location.x, frame: frame)
                touch.mode = .selecting(anchor: anchor)
                spokenAnchor = nil
                select(from: anchor, to: anchor)
                selectionTaps += 1
            }
        }
        let drift = hypot(value.location.x - touch.startLocation.x, value.location.y - touch.startLocation.y)
        if drift > Self.holdSlop { touch.holdTask?.cancel() }
        apply(value.location, frame: frame)
        updateEdgePan()
    }

    private func dragEnded() {
        if case .selecting = touch.mode, let selection, selection.lowerBound == selection.upperBound {
            // A hold with no drag selects nothing, which clears the selection.
            self.selection = nil
        }
        touch.cancel()
    }

    /// Puts the cursor, and the moving end of a selection, under the finger.
    private func apply(_ location: CGPoint, frame: Frame) {
        switch touch.mode {
        case .scrubbing:
            scrub(to: sample(at: location.x, frame: frame))
        case .selecting(let anchor):
            let sample = sample(at: location.x, frame: frame)
            select(from: anchor, to: sample)
            scrub(to: sample)
        case .cancelled, nil:
            break
        }
    }

    /// While a drag is held in an edge zone of a zoomed timeline, pans the
    /// viewport that way and keeps the cursor under the finger.
    private func updateEdgePan() {
        guard touch.edgeTask == nil, edgePanRate() != 0 else { return }
        touch.edgeTask = Task {
            let clock = ContinuousClock()
            var last = clock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                guard !Task.isCancelled, let frame = touch.frame else { break }
                let now = clock.now
                let elapsed = Double((now - last).components.attoseconds) / 1e18
                    + Double((now - last).components.seconds)
                last = now
                let rate = edgePanRate()
                guard rate != 0 else { break }
                let visible = visible(frame.limits)
                viewport = visible.panned(by: rate * Self.edgePanSpeed * visible.span * elapsed, limits: frame.limits)
                apply(touch.location, frame: frame)
            }
            if !Task.isCancelled { touch.edgeTask = nil }
        }
    }

    /// The edge-pan rate for the finger's place, or 0 when there is nothing
    /// to pan: no drag, or the viewport is already at that end.
    private func edgePanRate() -> Double {
        guard let frame = touch.frame else { return 0 }
        switch touch.mode {
        case .scrubbing, .selecting: break
        case .cancelled, nil: return 0
        }
        let rate = TimelineViewport.edgePanRate(x: touch.location.x, width: frame.width, zone: Self.edgeZone)
        let visible = visible(frame.limits)
        if rate < 0, visible.lower > 0 { return rate }
        if rate > 0, visible.upper < frame.limits.total { return rate }
        return 0
    }

    // MARK: Zooming

    private func pinchChanged(_ pinch: PinchValue, frame: Frame) {
        guard frame.width > 0 else { return }
        if pinch.ended {
            touch.pinch = nil
            return
        }
        if touch.pinch == nil {
            // A second finger has landed. The first one moved the cursor when
            // it came down, so put the cursor back and stop scrubbing.
            touch.holdTask?.cancel()
            touch.edgeTask?.cancel()
            touch.edgeTask = nil
            if case .scrubbing = touch.mode { scrubSample = touch.startScrub }
            if case .selecting = touch.mode, let selection, selection.lowerBound == selection.upperBound {
                // Two fingers that rested before moving started a selection
                // of nothing. Take it away again.
                self.selection = nil
            }
            if touch.mode != nil { touch.mode = .cancelled }
        }
        if touch.pinch == nil || touch.pinch?.touches != pinch.touches {
            // Start again from here when the number of fingers changes, so
            // the middle of the fingers jumping does not move the timeline.
            touch.pinch = TouchState.Pinch(
                viewport: visible(frame.limits), x: pinch.x, scale: pinch.scale, touches: pinch.touches
            )
        }
        guard let start = touch.pinch, start.scale > 0 else { return }
        viewport = start.viewport.pinched(
            scale: pinch.scale / start.scale,
            startFraction: start.x / frame.width,
            currentFraction: pinch.x / frame.width,
            limits: frame.limits
        )
    }

    // MARK: VoiceOver

    /// Moves the cursor a twentieth of what is on screen, so zooming in
    /// gives finer steps.
    private func adjust(_ direction: AccessibilityAdjustmentDirection, frame: Frame) {
        let visible = visible(frame.limits)
        let step = visible.span / 20
        let position = frame.axis.position(ofSample: scrubSample)
        let target: Double
        switch direction {
        case .increment: target = position + step
        case .decrement: target = position - step
        @unknown default: return
        }
        let limited = min(max(target, 0), frame.limits.total)
        viewport = viewport.map { $0.clamped(to: frame.limits).revealing(limited, limits: frame.limits) }
        scrub(to: frame.axis.sample(at: limited))
    }
}

/// What the gestures need to turn a point into a sample.
private struct Frame {
    var axis: TimelineAxis
    var limits: ViewportLimits
    var width: CGFloat
}

/// What the fingers on the timeline are doing. Kept out of view state so
/// that tracking a touch does not itself redraw anything.
@MainActor
private final class TouchState {
    enum Mode: Equatable {
        case scrubbing
        case selecting(anchor: Double)
        /// A pinch took over. The drag is ignored until the finger lifts.
        case cancelled
    }

    struct Pinch {
        var viewport: TimelineViewport
        var x: Double
        var scale: Double
        var touches: Int
    }

    var mode: Mode?
    var startLocation = CGPoint.zero
    var startScrub = 0.0
    var location = CGPoint.zero
    var width: CGFloat = 0
    var frame: Frame?
    var holdTask: Task<Void, Never>?
    var edgeTask: Task<Void, Never>?
    var pinch: Pinch?

    var isPinching: Bool { pinch != nil }

    /// Ends the drag in progress.
    func cancel() {
        holdTask?.cancel()
        holdTask = nil
        edgeTask?.cancel()
        edgeTask = nil
        mode = nil
    }
}
