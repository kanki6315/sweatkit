import SweatKitModel

extension AnalysisStream {
    /// The stream with every channel exactly `count` seconds long: a channel
    /// shorter than the stream is missing past its end, and one longer is cut
    /// to it, as the analysis package reads a stream. A well-formed stream
    /// comes back unchanged.
    func normalised() -> AnalysisStream {
        guard !isConsistent else { return self }
        var stream = self
        let count = max(self.count, 0)
        stream.count = count
        for channel in Channel.allCases {
            let series = self[channel]
            var values = Array(series.values.prefix(count))
            var quality = Array(series.quality.prefix(count))
            if values.count < count {
                values += Array(repeating: 0, count: count - values.count)
                quality += Array(repeating: .missing, count: count - quality.count)
            }
            stream[channel] = Series(values: values, quality: quality)
        }
        return stream
    }
}

extension DetailInput {
    /// The input with its stream normalised.
    func normalised() -> DetailInput {
        guard !stream.isConsistent else { return self }
        var input = self
        input.stream = stream.normalised()
        return input
    }
}
