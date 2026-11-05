import Foundation
import SweatKitModel
import SwiftUI
import Synchronization

/// Counts for a harness to read. Not for the app.
@_spi(Diagnostics) public enum TimelineDiagnostics {
    private static let draws = Atomic<Int>(0)

    /// How many times any timeline's chart has been drawn. Scrubbing moves
    /// only the cursor, so this stays still during a scrub and rises during a
    /// zoom or pan.
    public static var chartDrawCount: Int { draws.load(ordering: .relaxed) }

    static func countChartDraw() { draws.add(1, ordering: .relaxed) }
}

/// Draws everything in the timeline that does not move with the cursor: the
/// stops, the elevation profile, the overlay, the lap ticks and the axis
/// labels.
///
/// Two renderers that are equal draw the same picture, which is how the
/// timeline skips this work while scrubbing.
struct TimelineChartRenderer: Equatable, Sendable {
    /// The height of a lap tick, at the top of the chart.
    static let lapTickHeight: CGFloat = 7
    /// The height of a collapsed stop's seam mark, at the bottom.
    static let seamHeight: CGFloat = 6
    /// The share of the plot under the lowest point of the elevation, so the
    /// profile has some body even where it is lowest.
    static let elevationFloor = 0.12

    let prepared: PreparedTimeline
    let overlay: PreparedOverlay?
    /// The axis in use, already resolved.
    let key: AxisKey
    let viewport: TimelineViewport
    let units: UnitSystem
    let locale: Locale
    /// The height of the chart. The axis labels are drawn under it.
    let chartHeight: CGFloat
    /// About how wide one axis label is at the current text size.
    let tickLabelWidth: CGFloat
    let increasedContrast: Bool

    static func == (lhs: TimelineChartRenderer, rhs: TimelineChartRenderer) -> Bool {
        lhs.prepared === rhs.prepared && lhs.overlay === rhs.overlay && lhs.key == rhs.key
            && lhs.viewport == rhs.viewport && lhs.units == rhs.units && lhs.locale == rhs.locale
            && lhs.chartHeight == rhs.chartHeight && lhs.tickLabelWidth == rhs.tickLabelWidth
            && lhs.increasedContrast == rhs.increasedContrast
    }

    func draw(in context: inout GraphicsContext, size: CGSize) {
        TimelineDiagnostics.countChartDraw()
        let width = size.width
        guard width > 0, viewport.span > 0 else { return }
        let axis = prepared.axis(key)
        // One column per point of width is all the screen can show.
        let columns = max(1, Int(width.rounded(.down)))

        var chart = context
        chart.clip(to: Path(CGRect(x: 0, y: 0, width: width, height: chartHeight)))
        drawStops(in: &chart, axis: axis, width: width)
        drawElevation(in: &chart, axis: axis, width: width, columns: columns)
        drawOverlay(in: &chart, axis: axis, width: width, columns: columns)
        drawLaps(in: &chart, axis: axis, width: width)

        var baseline = Path()
        baseline.move(to: CGPoint(x: 0, y: chartHeight))
        baseline.addLine(to: CGPoint(x: width, y: chartHeight))
        context.stroke(baseline, with: .style(.primary.opacity(increasedContrast ? 0.6 : 0.25)), lineWidth: 0.5)
        drawTicks(in: &context, axis: axis, width: width)
    }

    // MARK: Layers

    private var plotTop: CGFloat { Self.lapTickHeight + 3 }

    /// A stop is a faint band, however narrow. A collapsed stop is a short
    /// mark on the baseline where its seam is.
    private func drawStops(in context: inout GraphicsContext, axis: TimelineAxis, width: CGFloat) {
        var bands = Path()
        var seams = Path()
        for stop in prepared.data.stops {
            let start = viewport.fraction(of: axis.positions[stop.lowerBound]) * width
            let end = viewport.fraction(of: axis.positions[min(stop.upperBound, axis.count - 1)]) * width
            guard end >= 0, start <= width else { continue }
            if key.collapsesStops {
                seams.addRect(CGRect(x: start - 0.5, y: chartHeight - Self.seamHeight, width: 1, height: Self.seamHeight))
            } else {
                bands.addRect(CGRect(x: start, y: plotTop, width: max(end - start, 1), height: chartHeight - plotTop))
            }
        }
        context.fill(bands, with: .style(.primary.opacity(increasedContrast ? 0.2 : 0.1)))
        context.fill(seams, with: .style(.primary.opacity(increasedContrast ? 0.9 : 0.55)))
    }

    private func drawElevation(in context: inout GraphicsContext, axis: TimelineAxis, width: CGFloat, columns: Int) {
        guard let range = prepared.elevationRange else { return }
        let scale = ValueScale.elevation(range)
        let reduced = TimelineReduction.reduce(
            prepared.elevationTable(key), axis: axis, viewport: viewport, columns: columns
        )
        let plotHeight = chartHeight - plotTop
        let y = { (value: Double) -> CGFloat in
            let share = Self.elevationFloor + (1 - Self.elevationFloor) * scale.height(of: value)
            return chartHeight - share * plotHeight
        }
        var area = Path()
        var line = Path()
        for run in reduced.runs {
            guard let first = run.first, let last = run.last else { continue }
            if run.count == 1 {
                // A lone second of elevation between gaps is a sliver.
                area.addRect(CGRect(x: first.x * width - 0.5, y: y(first.value), width: 1, height: chartHeight - y(first.value)))
                continue
            }
            area.move(to: CGPoint(x: first.x * width, y: chartHeight))
            line.move(to: CGPoint(x: first.x * width, y: y(first.value)))
            for point in run {
                area.addLine(to: CGPoint(x: point.x * width, y: y(point.value)))
                line.addLine(to: CGPoint(x: point.x * width, y: y(point.value)))
            }
            area.addLine(to: CGPoint(x: last.x * width, y: chartHeight))
            area.closeSubpath()
        }
        context.fill(area, with: .style(.primary.opacity(increasedContrast ? 0.3 : 0.18)))
        context.stroke(line, with: .style(.primary.opacity(increasedContrast ? 0.85 : 0.4)), lineWidth: 1)
    }

    /// One path per colour band. A segment takes the band of the point it
    /// starts at.
    private func drawOverlay(in context: inout GraphicsContext, axis: TimelineAxis, width: CGFloat, columns: Int) {
        guard let overlay, let overview = overlay.overviewRange else { return }
        let reduced = TimelineReduction.reduce(
            overlay.table(collapsesStops: key.collapsesStops),
            bands: overlay.bands(collapsesStops: key.collapsesStops),
            axis: axis, viewport: viewport, columns: columns
        )
        let scale = ValueScale.overlay(overview: overview, visible: reduced.visibleRange)
        let top = plotTop + 2, bottom = chartHeight - 3
        let place = { (point: ReducedSeries.Point) in
            CGPoint(x: point.x * width, y: bottom - scale.height(of: point.value) * (bottom - top))
        }
        var paths: [Int?: Path] = [:]
        for run in reduced.runs {
            if run.count == 1 {
                // A lone second between gaps is a dot.
                let at = place(run[0])
                paths[run[0].band, default: Path()].move(to: at)
                paths[run[0].band, default: Path()].addLine(to: at)
                continue
            }
            var previous: Int??
            for index in 0..<(run.count - 1) {
                let band = run[index].band
                if previous != .some(band) { paths[band, default: Path()].move(to: place(run[index])) }
                paths[band, default: Path()].addLine(to: place(run[index + 1]))
                previous = band
            }
        }
        let style = StrokeStyle(lineWidth: increasedContrast ? 2.5 : 1.75, lineCap: .round, lineJoin: .round)
        for band in paths.keys.sorted(by: { ($0 ?? -1) < ($1 ?? -1) }) {
            guard let path = paths[band] else { continue }
            if let color = overlay.color(for: band) {
                context.stroke(path, with: .color(color), style: style)
            } else {
                context.stroke(path, with: .style(.primary), style: style)
            }
        }
    }

    private func drawLaps(in context: inout GraphicsContext, axis: TimelineAxis, width: CGFloat) {
        var ticks = Path()
        for boundary in prepared.data.lapBoundaries {
            let x = viewport.fraction(of: axis.positions[boundary]) * width
            guard x >= 0, x <= width else { continue }
            ticks.addRect(CGRect(x: x - 0.75, y: 0, width: 1.5, height: Self.lapTickHeight))
        }
        context.fill(ticks, with: .style(.primary.opacity(increasedContrast ? 1 : 0.7)))
    }

    private func drawTicks(in context: inout GraphicsContext, axis: TimelineAxis, width: CGFloat) {
        let ticks = TimelineTicks.ticks(
            axis: axis, viewport: viewport, mode: key.mode, distance: prepared.data.distance,
            units: units, maximumCount: max(2, Int(width / (tickLabelWidth * 1.5))), locale: locale
        )
        var edge = -CGFloat.infinity
        for tick in ticks {
            let text = context.resolve(
                Text(tick.label)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(increasedContrast ? .primary : .secondary)
            )
            let size = text.measure(in: CGSize(width: CGFloat.infinity, height: .infinity))
            // Keep the first and last labels inside the chart.
            let centre = min(max(tick.fraction * width, size.width / 2), width - size.width / 2)
            guard centre - size.width / 2 >= edge + 6 else { continue }
            context.draw(text, at: CGPoint(x: centre, y: chartHeight + 3), anchor: .top)
            edge = centre + size.width / 2
        }
    }
}

/// The part of the timeline that stays still while scrubbing. SwiftUI skips
/// it when its renderer is unchanged.
struct TimelineChart: View, Equatable {
    let renderer: TimelineChartRenderer

    var body: some View {
        Canvas { context, size in
            renderer.draw(in: &context, size: size)
        }
    }
}
