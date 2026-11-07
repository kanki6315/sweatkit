import Foundation
import SweatKitModel

/// Builds the analysis stream from a recorded activity under the spec's
/// "Stream rules". The numbers come from `StreamRules`, and the stream
/// carries `StreamRules.version`.
public enum StreamNormaliser {
    /// The 1 Hz analysis stream of `activity`, or nil when the activity has no
    /// start or no end to put a grid on.
    ///
    /// Where the spec is ambiguous or silent, the reading taken is marked
    /// "Reading:" below.
    ///
    /// **Elapsed time and the grid**
    ///
    /// - The start is the stated start, and the end is the stated end. The
    ///   first sample stands in for a missing start and the last sample for a
    ///   missing end. Reading: each falls back on its own, so a stated start
    ///   with no stated end still uses the stated start. Reading: the first
    ///   and last samples are the earliest and the latest by timestamp, which
    ///   are the first and last in the stream whenever it is in time order.
    /// - The result is nil when a start or an end is still unknown, or when
    ///   the end is before the start.
    /// - `count` is the end minus the start in whole grid seconds. Reading: a
    ///   part second at the end is rounded up, so the grid covers the whole of
    ///   elapsed time. An elapsed time of 100.5 s is 101 grid seconds.
    /// - The grid is fixed by the start and the end alone. An activity with no
    ///   samples gets a grid with every channel missing. Samples never extend
    ///   it and their absence never shortens it.
    /// - A sample belongs to grid second floor((timestamp - start) /
    ///   gridInterval). A sample before the start, or at or after the actual
    ///   end, is left off the grid, including a fractional end. This follows
    ///   from the sample at second t describing t to t + 1: a sample stamped
    ///   exactly on the end is not on the grid. With the sample fallback the
    ///   last sample is always in that position.
    /// - Several samples in one second are averaged, channel by channel, over
    ///   the samples that have that channel. Latitude and longitude are
    ///   averaged separately. That second is measured.
    ///
    /// **Pause data**, from the "Time" table of "Analysis metrics"
    ///
    /// Timer events are read in time order, and each belongs to the grid
    /// second that contains its timestamp, like a sample. The timer is taken
    /// as running at the activity start, with or without a start event there.
    ///
    /// - A stop while the timer runs opens a paused span at the stop's second.
    ///   The next start is its matching start and closes the span at the
    ///   start's second, which is itself running. A start while the timer
    ///   already runs changes nothing.
    /// - Spans are clipped to the grid, and empty spans are dropped. A stop at
    ///   or after second `count` is outside the session and is ignored.
    /// - Complete: every stop inside the session has a matching start. The
    ///   result is `.known` with those spans.
    /// - A last stop with no matching start, and with no sample and no event
    ///   stamped later than it, is the normal end of a recording. Pause data
    ///   is still complete, and the span from that stop to the end of the grid
    ///   is paused. Reading: "at the session end" is taken to mean "with
    ///   nothing recorded after it", so the stop need not sit on the stated
    ///   end exactly. "Later" compares timestamps, so a sample stamped the
    ///   same instant as the stop is not after it.
    /// - Incomplete: a stop inside the session has no matching start while a
    ///   sample or an event is stamped later than it. A second stop after an
    ///   unmatched stop is such an event. The result is
    ///   `.unknown(statedTimerTime:)` with the stated timer time, if any.
    /// - No timer events at all: when the stated timer time is within
    ///   `unpausedTolerance` of elapsed time (the end minus the start, not
    ///   rounded; the boundary itself counts as within), the activity is
    ///   treated as unpaused, which is `.known(paused: [])`. Otherwise pause
    ///   data is incomplete.
    /// - Reading: a lone start event, with no stop, is pause data that shows
    ///   no pauses. It is complete, not absent.
    /// - Only timer events create pauses. A gap in the samples never does.
    ///
    /// **Filling gaps**
    ///
    /// - A gap is a run of grid seconds without a value in one channel, with a
    ///   valued second on each side. Its length is the number of seconds in
    ///   the run. Reading: a run before a channel's first value or after its
    ///   last has only one side, so it is not a gap and stays missing, for
    ///   hold-last channels too.
    /// - A gap of up to `longestFilledGap` seconds is filled by the channel's
    ///   `StreamRules.gapFill(for:)` and marked interpolated. Linear filling
    ///   runs in grid seconds between the two valued seconds. A longer gap is
    ///   missing throughout: no part of it is filled.
    /// - Latitude and longitude are filled together and share one quality.
    /// - Nothing is filled across a pause boundary. When pause data is known,
    ///   a gap is filled only if no paused span starts or ends between the
    ///   valued second before it and the valued second after it. Samples
    ///   recorded during a pause stay on the grid as measured.
    /// - Each channel is gridded and filled alone. A dropout in one never
    ///   touches another.
    ///
    /// **Speed**, second by second, from the first source that has a value:
    ///
    /// 1. The recorded speed in that second. Measured, and a recorded 0 is a
    ///    value.
    /// 2. The change in distance: (distance at t + 1 minus distance at t) /
    ///    gridInterval, from the distance channel after gap filling. Reading:
    ///    the forward difference, because the sample at t describes t to
    ///    t + 1. A fall in distance is not a speed, so that second goes on to
    ///    the next source.
    /// 3. The distance between the positions at t and t + 1 on a sphere of
    ///    `earthRadius`, divided by gridInterval, from the position channels
    ///    after gap filling.
    /// 4. Otherwise missing.
    ///
    /// Reading: a derived speed is measured when both values it was taken from
    /// are measured, and interpolated when either is interpolated.
    ///
    /// **Gradient**
    ///
    /// - A second needs altitude and distance, both after gap filling. Reading:
    ///   distance is the recorded distance only, so with no distance channel
    ///   the gradient is missing even where positions exist.
    /// - The window runs from `gradientWindow` / 2 behind the second's distance
    ///   to `gradientWindow` / 2 ahead of it. It is clipped to the unbroken run
    ///   of seconds around it that have both altitude and distance, so it
    ///   stops at missing data and at either end of the stream. Paused spans
    ///   do not cut it.
    /// - Altitude at each end of the window is read off the straight line
    ///   between the grid seconds either side of that distance. Reading: the
    ///   ends are interpolated, not snapped to samples, so the window is 30 m
    ///   at any speed. Reading: each end is looked for outwards from the
    ///   second, and is the first place the distance reaches the edge of the
    ///   window. So where several seconds share one distance, as when standing
    ///   still, the end reads the altitude of the one nearest in time.
    /// - Gradient is the altitude change between the ends divided by the
    ///   distance between them. It is missing when the clipped window covers
    ///   less than `gradientMinimumTravel`. A window of exactly that length is
    ///   valid.
    /// - Reading: a gradient is measured when the altitude at its second is
    ///   measured, and interpolated when that altitude is interpolated.
    public static func analysisStream(from activity: RecordedActivity) -> AnalysisStream? {
        let samples = activity.stream.samples
        let timestamps = samples.map(\.timestamp)
        guard let start = activity.stated.start ?? timestamps.min(),
              let end = activity.stated.end ?? timestamps.max()
        else { return nil }
        let elapsed = end.timeIntervalSince(start)
        guard elapsed >= 0,
              let count = Int(exactly: (elapsed / StreamRules.gridInterval).rounded(.up))
        else { return nil }
        let grid = Grid(start: start, end: end, count: count)

        let pauses = pauseData(of: activity, on: grid, elapsed: elapsed)
        let boundaries = PauseBoundaries(pauses, count: count)
        let seconds = timestamps.map(grid.second)

        var stream = AnalysisStream(
            rulesVersion: StreamRules.version,
            start: start,
            count: count,
            pauses: pauses
        )
        var recordedSpeed: [Double?] = []
        for channel in Channel.allCases {
            guard let value = recorded(channel) else { continue }
            let cells = average(of: samples, at: seconds, count: count, value: value)
            if channel == .speed {
                recordedSpeed = cells
            } else {
                stream[channel] = filled(cells, by: StreamRules.gapFill(for: channel), boundaries: boundaries)
            }
        }
        stream.speed = speed(recorded: recordedSpeed, in: stream)
        stream.gradient = gradient(altitude: stream.altitude, distance: stream.distance)
        return stream
    }

    // MARK: The grid

    /// The 1 Hz grid of one activity.
    private struct Grid {
        var start: Date
        var end: Date
        var count: Int

        /// How many whole grid seconds after the start `date` is. Negative
        /// before the start, and `count` or more at or after the end.
        func offset(of date: Date) -> Double {
            (date.timeIntervalSince(start) / StreamRules.gridInterval).rounded(.down)
        }

        /// The grid second that contains `date`, or nil when it is off the grid.
        func second(of date: Date) -> Int? {
            guard date >= start, date < end else { return nil }
            let offset = offset(of: date)
            guard offset >= 0, offset < Double(count) else { return nil }
            return Int(offset)
        }

        /// The grid second that contains `date`, moved onto the nearest end
        /// of the grid when it is outside. The end itself is `count`.
        func clampedSecond(of date: Date) -> Int {
            let offset = offset(of: date)
            guard offset > 0 else { return 0 }
            return offset < Double(count) ? Int(offset) : count
        }
    }

    /// How a channel is read off a native sample, or nil for a channel that
    /// is derived and not recorded.
    private static func recorded(_ channel: Channel) -> ((NativeSample) -> Double?)? {
        switch channel {
        case .latitude: { $0.position?.latitude }
        case .longitude: { $0.position?.longitude }
        case .altitude: { $0.altitude }
        case .distance: { $0.distance }
        case .speed: { $0.speed }
        case .heartRate: { $0.heartRate }
        case .power: { $0.power }
        case .cadence: { $0.cadence }
        case .temperature: { $0.temperature }
        case .runningStrideLength: { $0.runningStrideLength }
        case .runningGroundContactTime: { $0.runningGroundContactTime }
        case .runningVerticalOscillation: { $0.runningVerticalOscillation }

        case .gradient: nil
        }
    }

    /// One channel on the grid: for each second, the average over the samples
    /// in that second that have the channel, or nil when none has.
    private static func average(
        of samples: [NativeSample],
        at seconds: [Int?],
        count: Int,
        value: (NativeSample) -> Double?
    ) -> [Double?] {
        var sums = [Double](repeating: 0, count: count)
        var readings = [Int](repeating: 0, count: count)
        for (sample, second) in zip(samples, seconds) {
            guard let second, let value = value(sample) else { continue }
            sums[second] += value
            readings[second] += 1
        }
        return zip(sums, readings).map { $1 == 0 ? nil : $0 / Double($1) }
    }

    // MARK: Pause data

    private static func pauseData(
        of activity: RecordedActivity,
        on grid: Grid,
        elapsed: TimeInterval
    ) -> PauseData {
        let statedTimerTime = activity.stated.timerTime
        guard !activity.timerEvents.isEmpty else {
            if let statedTimerTime,
               abs(statedTimerTime - elapsed) <= StreamRules.unpausedTolerance * elapsed {
                return .known(paused: [])
            }
            return .unknown(statedTimerTime: statedTimerTime)
        }

        // Time order, with file order kept between events at one instant. A
        // stop at or after the end of the grid is outside the session.
        let events = activity.timerEvents.enumerated()
            .sorted { ($0.element.timestamp, $0.offset) < ($1.element.timestamp, $1.offset) }
            .map(\.element)
            .filter { $0.kind == .start || grid.offset(of: $0.timestamp) < Double(grid.count) }

        var paused: [Range<Int>] = []
        func pause(from stop: TimerEvent, to end: Int) {
            let first = grid.clampedSecond(of: stop.timestamp)
            if first < end { paused.append(first..<end) }
        }

        // The stop that paused the timer, while it is paused.
        var unmatched: TimerEvent?
        for event in events {
            switch (event.kind, unmatched) {
            case (.stop, nil):
                unmatched = event
            case (.start, let stop?):
                pause(from: stop, to: grid.clampedSecond(of: event.timestamp))
                unmatched = nil
            case (.stop, _?), (.start, nil):
                break
            }
        }

        if let stop = unmatched {
            let isFollowed = events.contains { $0.timestamp > stop.timestamp }
                || activity.stream.samples.contains { $0.timestamp > stop.timestamp }
            if isFollowed { return .unknown(statedTimerTime: statedTimerTime) }
            pause(from: stop, to: grid.count)
        }
        return .known(paused: paused)
    }

    /// Where paused spans start and end, for the rule that nothing is filled
    /// across a pause boundary.
    private struct PauseBoundaries {
        /// `upTo[k]` is how many span starts and ends lie at or before the
        /// start of second k.
        private var upTo: [Int]

        init(_ pauses: PauseData, count: Int) {
            var marks = [Int](repeating: 0, count: count + 1)
            if case .known(let paused) = pauses {
                for span in paused {
                    marks[span.lowerBound] += 1
                    marks[span.upperBound] += 1
                }
            }
            var total = 0
            upTo = marks.map { mark in
                total += mark
                return total
            }
        }

        /// Whether a paused span starts or ends after second `first` and at
        /// or before the start of second `second`.
        func separates(_ first: Int, _ second: Int) -> Bool {
            upTo[second] > upTo[first]
        }
    }

    // MARK: Filling gaps

    private static func filled(
        _ cells: [Double?],
        by fill: StreamRules.GapFill,
        boundaries: PauseBoundaries
    ) -> Series {
        var values = cells.map { $0 ?? 0 }
        var quality = cells.map { $0 == nil ? SampleQuality.missing : .measured }
        guard fill != .none else { return Series(values: values, quality: quality) }

        // The valued second before the run of empty seconds being crossed.
        var lastValued: (second: Int, value: Double)?
        for (second, cell) in cells.enumerated() {
            guard let value = cell else { continue }
            defer { lastValued = (second, value) }
            guard let before = lastValued else { continue }
            let gap = second - before.second - 1
            guard gap >= 1, gap <= StreamRules.longestFilledGap,
                  !boundaries.separates(before.second, second)
            else { continue }
            for index in (before.second + 1)..<second {
                switch fill {
                case .linear:
                    let share = Double(index - before.second) / Double(second - before.second)
                    values[index] = before.value + (value - before.value) * share
                case .holdLast:
                    values[index] = before.value
                case .none:
                    continue
                }
                quality[index] = .interpolated
            }
        }
        return Series(values: values, quality: quality)
    }

    // MARK: Speed

    private static func speed(recorded: [Double?], in stream: AnalysisStream) -> Series {
        var values = [Double](repeating: 0, count: stream.count)
        var quality = [SampleQuality](repeating: .missing, count: stream.count)
        for second in 0..<stream.count {
            if let speed = recorded[second] {
                values[second] = speed
                quality[second] = .measured
                continue
            }
            let next = second + 1
            guard next < stream.count else { continue }
            if let here = stream.distance[second], let there = stream.distance[next], there >= here {
                values[second] = (there - here) / StreamRules.gridInterval
                quality[second] = derived(from: stream.distance.quality, second, next)
            } else if let here = stream.coordinate(at: second), let there = stream.coordinate(at: next) {
                values[second] = metres(from: here, to: there) / StreamRules.gridInterval
                quality[second] = derived(from: stream.latitude.quality, second, next)
            }
        }
        return Series(values: values, quality: quality)
    }

    /// The quality of a value taken from two seconds of one channel, neither
    /// of them missing.
    private static func derived(from quality: [SampleQuality], _ first: Int, _ second: Int) -> SampleQuality {
        quality[first] == .measured && quality[second] == .measured ? .measured : .interpolated
    }

    /// The great-circle distance in metres between two positions, on a sphere
    /// of `StreamRules.earthRadius`.
    private static func metres(from start: Coordinate, to end: Coordinate) -> Double {
        let radians = Double.pi / 180
        let startLatitude = start.latitude * radians
        let endLatitude = end.latitude * radians
        let latitudeHalf = (endLatitude - startLatitude) / 2
        let longitudeHalf = (end.longitude - start.longitude) * radians / 2
        let haversine = sin(latitudeHalf) * sin(latitudeHalf)
            + cos(startLatitude) * cos(endLatitude) * sin(longitudeHalf) * sin(longitudeHalf)
        return 2 * StreamRules.earthRadius * asin(min(1, haversine.squareRoot()))
    }

    // MARK: Gradient

    private static func gradient(altitude: Series, distance: Series) -> Series {
        let count = altitude.count
        var values = [Double](repeating: 0, count: count)
        var quality = [SampleQuality](repeating: .missing, count: count)

        var second = 0
        while second < count {
            guard altitude[second] != nil, distance[second] != nil else {
                second += 1
                continue
            }
            // The unbroken run of seconds that have both channels.
            var last = second
            while last + 1 < count, altitude[last + 1] != nil, distance[last + 1] != nil {
                last += 1
            }
            for index in second...last {
                guard let value = gradient(at: index, in: second...last, altitude: altitude, distance: distance)
                else { continue }
                values[index] = value
                quality[index] = altitude.quality[index]
            }
            second = last + 1
        }
        return Series(values: values, quality: quality)
    }

    /// The gradient at `second`, whose window is kept inside `run`, where
    /// every second has altitude and distance. Nil when the window covers too
    /// little travel.
    private static func gradient(
        at second: Int,
        in run: ClosedRange<Int>,
        altitude: Series,
        distance: Series
    ) -> Double? {
        let centre = distance.values[second]
        let half = StreamRules.gradientWindow / 2
        let behind = windowEnd(
            at: centre - half, from: second, towards: run.lowerBound, altitude: altitude, distance: distance
        )
        let ahead = windowEnd(
            at: centre + half, from: second, towards: run.upperBound, altitude: altitude, distance: distance
        )
        let travel = ahead.distance - behind.distance
        guard travel >= StreamRules.gradientMinimumTravel, travel > 0 else { return nil }
        return (ahead.altitude - behind.altitude) / travel
    }

    /// One end of a gradient window: the place where the distance first
    /// reaches `edge`, going from second `start` towards second `limit`, and
    /// the altitude there, read off the line between the two seconds either
    /// side of it. When the run ends before the distance gets that far, the
    /// end is the run's last second.
    private static func windowEnd(
        at edge: Double,
        from start: Int,
        towards limit: Int,
        altitude: Series,
        distance: Series
    ) -> (distance: Double, altitude: Double) {
        let step = limit >= start ? 1 : -1
        // Distance is short of the edge while it is on the start's side of it.
        func isShort(_ index: Int) -> Bool {
            step > 0 ? distance.values[index] < edge : distance.values[index] > edge
        }

        var index = start
        while index != limit, isShort(index) {
            index += step
        }
        guard !isShort(index), index != start else {
            return (distance.values[index], altitude.values[index])
        }
        // The edge lies between the second before and this one.
        let inner = index - step
        let span = distance.values[index] - distance.values[inner]
        let share = (edge - distance.values[inner]) / span
        return (edge, altitude.values[inner] + (altitude.values[index] - altitude.values[inner]) * share)
    }
}
