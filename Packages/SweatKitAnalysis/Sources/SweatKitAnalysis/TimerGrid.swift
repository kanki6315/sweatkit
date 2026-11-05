import SweatKitModel

/// Which grid seconds the timer ran for, when pause positions are known.
///
/// The paused spans are read defensively: each is cut to the grid, empty ones
/// are dropped, and spans that touch or overlap are merged. A well-formed
/// stream needs none of that, and gets the same answer.
struct TimerGrid {
    /// Elapsed seconds.
    let count: Int
    /// The unbroken timer spans, in order. None is empty.
    let spans: [Range<Int>]
    /// The grid seconds the timer ran for, in order: the stream with its
    /// paused spans removed and the rest joined.
    let seconds: [Int]
    /// `secondsBefore[t]` is the number of timer seconds in `0..<t`. It has
    /// `count + 1` entries.
    let secondsBefore: [Int]

    init(count: Int, paused: [Range<Int>]) {
        self.count = count
        let cut = paused
            .map { min(max($0.lowerBound, 0), count)..<min(max($0.upperBound, 0), count) }
            .filter { !$0.isEmpty }
            .sorted { $0.lowerBound < $1.lowerBound }

        var spans: [Range<Int>] = []
        var cursor = 0
        for span in cut {
            if span.lowerBound > cursor {
                spans.append(cursor..<span.lowerBound)
            }
            cursor = max(cursor, span.upperBound)
        }
        if cursor < count {
            spans.append(cursor..<count)
        }
        self.spans = spans
        self.seconds = spans.flatMap { Array($0) }

        var before = Array(repeating: 0, count: count + 1)
        for span in spans {
            for second in span {
                before[second + 1] = 1
            }
        }
        for second in 0..<count {
            before[second + 1] += before[second]
        }
        self.secondsBefore = before
    }

    /// Timer time, in whole seconds.
    var timerSeconds: Int { seconds.count }

    /// Whether the timer ran through grid second `second`.
    func isRunning(_ second: Int) -> Bool {
        secondsBefore[second + 1] > secondsBefore[second]
    }
}
