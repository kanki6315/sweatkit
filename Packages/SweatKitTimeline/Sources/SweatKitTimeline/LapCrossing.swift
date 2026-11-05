enum LapCrossing {
    /// The lap boundaries the cursor crosses in one move, as a range of
    /// indices into `boundaries`, which is sorted.
    ///
    /// The cursor crosses a boundary when it passes over it or lands on it.
    /// Moving on from a boundary it already sits on is not a second crossing,
    /// so each pass over a boundary counts once in either direction.
    static func crossed(from old: Double, to new: Double, boundaries: [Int]) -> Range<Int> {
        guard old != new, old.isFinite, new.isFinite else { return 0..<0 }
        if new > old {
            // Boundaries b with old < b <= new.
            let first = partition(boundaries) { Double($0) <= old }
            let end = partition(boundaries) { Double($0) <= new }
            return first..<end
        } else {
            // Boundaries b with new <= b < old.
            let first = partition(boundaries) { Double($0) < new }
            let end = partition(boundaries) { Double($0) < old }
            return first..<end
        }
    }

    /// The number of leading elements for which `isBefore` holds, given that
    /// it holds for a prefix of the array and for nothing after.
    private static func partition(_ values: [Int], isBefore: (Int) -> Bool) -> Int {
        var low = 0, high = values.count
        while low < high {
            let middle = (low + high) / 2
            if isBefore(values[middle]) { low = middle + 1 } else { high = middle }
        }
        return low
    }
}
