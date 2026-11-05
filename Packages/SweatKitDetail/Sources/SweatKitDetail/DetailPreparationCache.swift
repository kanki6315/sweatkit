/// A small LRU of prepared activities. Full input equality invalidates entries
/// when samples, laps, profile thresholds, or activity metadata change.
/// Isolated from the main actor so comparison and preparation cannot block gestures.
public actor DetailPreparationCache {
    public static let shared = DetailPreparationCache()
    private struct Entry {
        let input: DetailInput
        let detail: PreparedDetail
    }
    private var entries: [Entry] = []
    private let capacity: Int

    public init(capacity: Int = 2) { self.capacity = max(0, capacity) }

    public func prepare(_ input: DetailInput) throws -> (detail: PreparedDetail, cacheHit: Bool) {
        try Task.checkCancellation()
        if let index = entries.firstIndex(where: { $0.input == input }) {
            let entry = entries.remove(at: index)
            entries.append(entry)
            return (entry.detail, true)
        }
        let detail = DetailPreparation.prepare(input)
        try Task.checkCancellation()
        // Avoid retaining unusually long recordings in addition to the live view.
        if capacity > 0, input.stream.count <= 100_000 {
            entries.append(Entry(input: input, detail: detail))
            if entries.count > capacity { entries.removeFirst() }
        }
        return (detail, false)
    }

    public func removeAll() { entries.removeAll() }
}
