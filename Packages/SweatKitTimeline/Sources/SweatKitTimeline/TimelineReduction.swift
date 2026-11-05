/// Running totals over one series, built once per activity, so that the mean
/// of any run of samples is two lookups however long the run is.
///
/// This is the part of the reduction that reads every sample. It is done
/// ahead of time, off the main thread. Reducing to the columns on screen then
/// costs the same for a 5-hour ride as for a 5-minute one.
struct SeriesTable: Sendable {
    /// `sums[i]` is the total of the present values before sample `i`.
    private let sums: [Double]
    /// `present[i]` is the number of samples before `i` that have a value.
    private let present: [Int]
    /// `shown[i]` is the number of samples before `i` that are not excluded.
    private let shown: [Int]
    /// The smallest and largest present value, or nil when there is none.
    let range: ClosedRange<Double>?

    /// - Parameters:
    ///   - values: One value per sample. A value that is nil or not finite is
    ///     missing. A series shorter than `count` is missing past its end.
    ///   - excluded: Samples left out altogether, sorted and not overlapping.
    ///     Collapsed stops are excluded, so a stop adds nothing to the column
    ///     at its seam and is not drawn as a gap either.
    init(values: [Double?], count: Int, excluding excluded: [Range<Int>] = []) {
        var sums = [Double](repeating: 0, count: count + 1)
        var present = [Int](repeating: 0, count: count + 1)
        var shown = [Int](repeating: 0, count: count + 1)
        var lowest = Double.infinity, highest = -Double.infinity
        var excludedIndex = 0
        for sample in 0..<count {
            while excludedIndex < excluded.count, excluded[excludedIndex].upperBound <= sample { excludedIndex += 1 }
            let isExcluded = excludedIndex < excluded.count && excluded[excludedIndex].contains(sample)
            var sum = sums[sample], presentCount = present[sample], shownCount = shown[sample]
            if !isExcluded {
                shownCount += 1
                if sample < values.count, let value = values[sample], value.isFinite {
                    sum += value
                    presentCount += 1
                    lowest = min(lowest, value)
                    highest = max(highest, value)
                }
            }
            sums[sample + 1] = sum
            present[sample + 1] = presentCount
            shown[sample + 1] = shownCount
        }
        self.sums = sums
        self.present = present
        self.shown = shown
        self.range = lowest <= highest ? lowest...highest : nil
    }

    /// The range of the series as an overview shows it: the lowest and
    /// highest mean over consecutive windows, when the whole series is cut
    /// into at most `windows` windows of equal length. Nil when there is no
    /// value. A one-second spike moves this far less than it moves `range`.
    func overviewRange(windows: Int) -> ClosedRange<Double>? {
        let count = sums.count - 1
        guard count > 0, windows > 0 else { return nil }
        let length = (count + windows - 1) / windows
        var lowest = Double.infinity, highest = -Double.infinity
        for start in stride(from: 0, to: count, by: length) {
            guard let mean = mean(start..<min(start + length, count)) else { continue }
            lowest = min(lowest, mean)
            highest = max(highest, mean)
        }
        return lowest <= highest ? lowest...highest : nil
    }

    /// How many of the samples are not excluded.
    func shownCount(_ samples: Range<Int>) -> Int {
        shown[samples.upperBound] - shown[samples.lowerBound]
    }

    /// How many of the samples have a value.
    func presentCount(_ samples: Range<Int>) -> Int {
        present[samples.upperBound] - present[samples.lowerBound]
    }

    /// The mean of the values the samples have, or nil when none has one.
    func mean(_ samples: Range<Int>) -> Double? {
        let count = presentCount(samples)
        guard count > 0 else { return nil }
        return (sums[samples.upperBound] - sums[samples.lowerBound]) / Double(count)
    }
}

/// Running counts of each colour band, so that the commonest band in any run
/// of samples is one lookup per band.
struct BandTable: Sendable {
    /// The bands that occur, in increasing order.
    let bands: [Int]
    /// `counts[b][i]` is how many counted samples before `i` are in `bands[b]`.
    private let counts: [[Int]]

    /// Counts a sample only when it has a value and is not excluded, so the
    /// band of a column is the band of the values its mean is taken from.
    init(bands: [Int], values: [Double?], count: Int, excluding excluded: [Range<Int>] = []) {
        let limit = min(count, bands.count, values.count)
        let distinct = Set(bands.prefix(limit)).sorted()
        var slot: [Int: Int] = [:]
        for (index, band) in distinct.enumerated() { slot[band] = index }
        var counts = [[Int]](repeating: [Int](repeating: 0, count: count + 1), count: distinct.count)
        var excludedIndex = 0
        for sample in 0..<count {
            for band in counts.indices { counts[band][sample + 1] = counts[band][sample] }
            while excludedIndex < excluded.count, excluded[excludedIndex].upperBound <= sample { excludedIndex += 1 }
            let isExcluded = excludedIndex < excluded.count && excluded[excludedIndex].contains(sample)
            guard !isExcluded, sample < limit, let value = values[sample], value.isFinite,
                  let index = slot[bands[sample]]
            else { continue }
            counts[index][sample + 1] += 1
        }
        self.bands = distinct
        self.counts = counts
    }

    /// The band most of the samples are in, or nil when none is counted. Of
    /// two equally common bands the lower wins.
    func commonest(_ samples: Range<Int>) -> Int? {
        var best: Int?
        var bestCount = 0
        for (index, band) in bands.enumerated() {
            let count = counts[index][samples.upperBound] - counts[index][samples.lowerBound]
            if count > bestCount {
                best = band
                bestCount = count
            }
        }
        return best
    }
}

/// A series reduced to what the timeline's width can show.
struct ReducedSeries: Hashable, Sendable {
    struct Point: Hashable, Sendable {
        /// How far across the viewport the point is: 0 at the left edge and 1
        /// at the right. The points just outside the viewport, which carry
        /// the line to its edges, are below 0 or above 1.
        var x: Double
        var value: Double
        /// The colour band, for a zoned series.
        var band: Int?

        init(x: Double, value: Double, band: Int? = nil) {
            self.x = x
            self.value = value
            self.band = band
        }
    }

    /// Runs of points, each joined by a line. A gap in the data ends one run
    /// and starts the next, so missing seconds are never bridged.
    var runs: [[Point]]

    /// The lowest and highest value among the points inside the viewport, or
    /// nil when there is none.
    var visibleRange: ClosedRange<Double>? {
        var lowest = Double.infinity, highest = -Double.infinity
        for run in runs {
            for point in run where point.x >= 0 && point.x <= 1 {
                lowest = min(lowest, point.value)
                highest = max(highest, point.value)
            }
        }
        return lowest <= highest ? lowest...highest : nil
    }
}

enum TimelineReduction {
    /// Reduces a series to at most one point per column of the viewport.
    ///
    /// The viewport is cut into `columns` equal columns, and each sample
    /// belongs to the column its axis position falls in. A column's point is
    /// the mean of the values its samples have, drawn midway between its
    /// first and last sample, in the commonest band of those values. A column
    /// whose samples all lack a value is a gap, which ends the run. A column
    /// with no sample at all, as when zoomed in past one sample per column,
    /// is skipped and the line passes over it. One sample on each side of the
    /// viewport is added so the line reaches both edges.
    static func reduce(
        _ table: SeriesTable,
        bands: BandTable? = nil,
        axis: TimelineAxis,
        viewport: TimelineViewport,
        columns: Int
    ) -> ReducedSeries {
        guard viewport.span > 0, columns > 0 else { return ReducedSeries(runs: []) }
        var runs: [[ReducedSeries.Point]] = []
        var run: [ReducedSeries.Point] = []

        func add(_ samples: Range<Int>) {
            guard table.shownCount(samples) > 0 else { return }
            guard let mean = table.mean(samples) else {
                if !run.isEmpty { runs.append(run) }
                run = []
                return
            }
            let middle = (axis.positions[samples.lowerBound] + axis.positions[samples.upperBound - 1]) / 2
            run.append(ReducedSeries.Point(
                x: viewport.fraction(of: middle),
                value: mean,
                band: bands?.commonest(samples)
            ))
        }

        var start = axis.firstSample(atOrAfter: viewport.lower)
        if start > 0 { add((start - 1)..<start) }
        for column in 0..<columns {
            let end: Int
            if column == columns - 1 {
                // The last column includes a sample that sits on the right edge.
                end = axis.firstSample(after: viewport.upper)
            } else {
                let edge = viewport.lower + viewport.span * Double(column + 1) / Double(columns)
                end = axis.firstSample(atOrAfter: edge)
            }
            if end > start {
                add(start..<end)
                start = end
            }
        }
        if start < axis.count { add(start..<(start + 1)) }
        if !run.isEmpty { runs.append(run) }
        return ReducedSeries(runs: runs)
    }
}

/// Maps a value to a height, from 0 at the bottom of its scale to 1 at the
/// top. The scale is fixed for the whole activity, so the picture does not
/// rescale while scrubbing, zooming or panning.
struct ValueScale: Hashable, Sendable {
    /// Elevation is drawn over a span of at least this many metres, so a flat
    /// walk looks flat instead of filling the chart with its few metres of
    /// rise.
    static let minimumElevationSpan = 50.0

    var lower: Double
    var upper: Double

    /// The scale for an elevation profile: from its lowest point, over its
    /// own span or the minimum span, whichever is larger.
    static func elevation(_ range: ClosedRange<Double>) -> ValueScale {
        ValueScale(
            lower: range.lowerBound,
            upper: max(range.upperBound, range.lowerBound + minimumElevationSpan)
        )
    }

    /// How many windows an overlay's overview range is taken over. More than
    /// a phone has points across, so at full zoom-out nothing drawn is
    /// outside it.
    static let overviewWindows = 600

    /// The scale for an overlay: its overview range, widened to hold
    /// whatever is on screen.
    ///
    /// Power has one-second spikes several times its usual level. Scaling to
    /// them would press the rest of the line flat, so the scale is set by
    /// the overview instead. It only moves when zooming in brings a value
    /// outside the overview range into view, and then only far enough to
    /// show it, so nothing is ever cut off.
    static func overlay(overview: ClosedRange<Double>, visible: ClosedRange<Double>?) -> ValueScale {
        ValueScale(
            lower: min(overview.lowerBound, visible?.lowerBound ?? overview.lowerBound),
            upper: max(overview.upperBound, visible?.upperBound ?? overview.upperBound)
        )
    }

    /// The height of a value. A scale with no span puts everything halfway.
    func height(of value: Double) -> Double {
        upper > lower ? (value - lower) / (upper - lower) : 0.5
    }
}
