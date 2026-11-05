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
    ///   with no stated end still uses the stated start.
    /// - The result is nil when a start or an end is still unknown, or when
    ///   the end is before the start.
    /// - `count` is the end minus the start in whole grid seconds. Reading: a
    ///   part second at the end is rounded up, so the grid covers the whole of
    ///   elapsed time. An elapsed time of 100.5 s is 101 grid seconds.
    /// - The grid is fixed by the start and the end alone. An activity with no
    ///   samples gets a grid with every channel missing. Samples never extend
    ///   it and their absence never shortens it.
    /// - A sample belongs to grid second floor((timestamp - start) /
    ///   gridInterval). A sample before the start, or at or after second
    ///   `count`, is left off the grid. Reading: this follows from the sample
    ///   at second t describing t to t + 1, and it means a sample stamped
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
    ///    t + 1. A fall in distance is not a speed.
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
    ///   at any speed.
    /// - Gradient is the altitude change between the ends divided by the
    ///   distance between them. It is missing when the clipped window covers
    ///   less than `gradientMinimumTravel`. A window of exactly that length is
    ///   valid.
    /// - Reading: a gradient is measured when the altitude at its second is
    ///   measured, and interpolated when that altitude is interpolated.
    public static func analysisStream(from activity: RecordedActivity) -> AnalysisStream? {
        fatalError("unimplemented")
    }
}
