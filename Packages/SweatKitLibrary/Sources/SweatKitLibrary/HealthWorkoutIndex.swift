import Foundation

/// An interval tree: queries prune entire subtrees outside the sample's span.
/// Inclusive endpoints preserve HealthKit's existing overlap semantics.
public struct HealthWorkoutIndex: Sendable {
    private struct Entry: Sendable {
        var id: UUID
        var span: DateInterval
        var maximumEnd: Date
    }
    private var entries: [Entry]

    public init(_ workouts: [UUID: DateInterval]) {
        entries = workouts.map { Entry(id: $0.key, span: $0.value, maximumEnd: $0.value.end) }
            .sorted { $0.span.start < $1.span.start }
        func augment(_ lower: Int, _ upper: Int) -> Date {
            guard lower < upper else { return .distantPast }
            let middle = (lower + upper) / 2
            let end = max(entries[middle].span.end, augment(lower, middle), augment(middle + 1, upper))
            entries[middle].maximumEnd = end
            return end
        }
        _ = augment(0, entries.count)
    }

    public func overlapping(start: Date, end: Date) -> Set<UUID> {
        var result: Set<UUID> = []
        func visit(_ lower: Int, _ upper: Int) {
            guard lower < upper else { return }
            let middle = (lower + upper) / 2
            guard entries[middle].maximumEnd >= start else { return }
            visit(lower, middle)
            let entry = entries[middle]
            guard entry.span.start <= end else { return }
            if entry.span.end >= start { result.insert(entry.id) }
            visit(middle + 1, upper)
        }
        visit(0, entries.count)
        return result
    }
}
