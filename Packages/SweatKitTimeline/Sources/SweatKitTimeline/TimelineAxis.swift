/// Where each sample sits along the x-axis, before zoom.
///
/// A position is in axis units: seconds on the time axis and metres on the
/// distance axis, both starting at 0 for the first sample. Positions never
/// decrease. With stops collapsed, the seconds inside a stop add nothing, so
/// a stop from second `a` up to second `b` puts samples `a` through `b` at
/// one position, the seam.
struct TimelineAxis: Sendable {
    /// The position of each sample.
    let positions: [Double]

    init(positions: [Double]) {
        precondition(positions.count >= 2, "An axis needs at least two samples")
        self.positions = positions
    }

    /// - Parameters:
    ///   - distance: Cumulative metres per sample. Ignored on the time axis.
    ///     On the distance axis a nil distance gives an axis of no length.
    ///   - stops: The stops to collapse, sorted and not overlapping. Empty
    ///     keeps every second.
    init(mode: TimelineAxisMode, count: Int, distance: [Double]?, collapsing stops: [Range<Int>] = []) {
        precondition(count >= 2, "An axis needs at least two samples")
        var positions = [Double](repeating: 0, count: count)
        var stopIndex = 0
        var running = 0.0
        for sample in 0..<(count - 1) {
            // The step from this sample to the next is this sample's second.
            while stopIndex < stops.count, stops[stopIndex].upperBound <= sample { stopIndex += 1 }
            let stopped = stopIndex < stops.count && stops[stopIndex].contains(sample)
            if !stopped {
                switch mode {
                case .time:
                    running += 1
                case .distance:
                    if let distance { running += max(0, distance[sample + 1] - distance[sample]) }
                }
            }
            positions[sample + 1] = running
        }
        self.positions = positions
    }

    var count: Int { positions.count }

    /// The position of the last sample, which is the length of the axis.
    var total: Double { positions[positions.count - 1] }

    /// The position of a sample. A fractional sample sits between its
    /// neighbours.
    func position(ofSample sample: Double) -> Double {
        let clamped = min(max(sample, 0), Double(count - 1))
        let index = Int(clamped.rounded(.down))
        guard index < count - 1 else { return total }
        let fraction = clamped - Double(index)
        return positions[index] + fraction * (positions[index + 1] - positions[index])
    }

    /// The sample at a position. Where several samples share the position, as
    /// at a collapsed stop, it is the last of them, so the cursor leaves a
    /// seam from the stop's far side.
    func sample(at position: Double) -> Double {
        let clamped = min(max(position, 0), total)
        let next = firstSample(after: clamped)
        guard next < count else { return Double(count - 1) }
        let index = next - 1
        let fraction = (clamped - positions[index]) / (positions[next] - positions[index])
        return Double(index) + fraction
    }

    /// The first sample at or right of a position, or `count` when every
    /// sample is left of it.
    func firstSample(atOrAfter position: Double) -> Int {
        var low = 0, high = positions.count
        while low < high {
            let middle = (low + high) / 2
            if positions[middle] < position { low = middle + 1 } else { high = middle }
        }
        return low
    }

    /// The first sample right of a position, or `count` when there is none.
    func firstSample(after position: Double) -> Int {
        var low = 0, high = positions.count
        while low < high {
            let middle = (low + high) / 2
            if positions[middle] <= position { low = middle + 1 } else { high = middle }
        }
        return low
    }
}

/// Which axis a timeline is drawn on.
struct AxisKey: Hashable, Sendable {
    var mode: TimelineAxisMode
    var collapsesStops: Bool
}
