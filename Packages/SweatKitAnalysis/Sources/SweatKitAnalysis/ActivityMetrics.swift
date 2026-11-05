import Foundation
import SweatKitModel

/// Every metric of one activity. Anything that can be unavailable is a
/// `Metric`, never a zero.
///
/// An activity with no stream has its three times and nothing else: every
/// other metric is unavailable with `.noStream`, and every flag is false. The
/// spec gives such an activity "all three times" from the stated metadata and
/// says every metric is computed from the stream, so the stated distance and
/// ascent are not repeated here.
public struct ActivityMetrics: Hashable, Codable, Sendable {
    public var time: TimeMetrics
    /// Metres: the last value the cumulative distance channel has.
    /// Unavailable with `.noDistance`. The spec lists distance among the
    /// metrics that survive unknown pause positions but does not define it;
    /// this is the literal reading of a cumulative channel.
    public var distance: Metric<Double>
    /// Metres climbed.
    ///
    /// Summed by peak and valley, over every second that has altitude. A
    /// climb runs from a low point to the next high point and ends once the
    /// altitude has fallen back by the threshold; a turn smaller than the
    /// threshold neither ends it nor counts. The threshold comes from
    /// `AnalysisRules.elevationThreshold(sport:isVirtual:)`, and a turn of
    /// exactly the threshold counts. Unavailable with `.noAltitude`.
    ///
    /// The stream carries one altitude channel, so preferring barometric
    /// altitude over GPS is the stream builder's job.
    public var ascent: Metric<Double>
    /// Metres descended, as a positive number, under the same rule as `ascent`.
    public var descent: Metric<Double>
    public var power: PowerMetrics
    public var heartRate: HeartRateMetrics
    /// The load the activity gets: from power when intensity is available,
    /// otherwise from heart rate when that is available, otherwise
    /// unavailable with the reason load from heart rate is unavailable. It is
    /// never estimated from partial data.
    public var load: Metric<ActivityLoad>
    /// Whether to prompt the user to set a threshold power: true exactly when
    /// weighted power is available and no threshold power was in effect on
    /// the activity date. The spec says a ride with no threshold power set
    /// prompts; this reads that as a ride whose intensity is missing for no
    /// other reason.
    public var promptsForThresholdPower: Bool
    /// Seven zones by share of the threshold power in effect on the activity
    /// date, for cycling, unless absolute custom boundaries are set.
    /// Missing thresholds use starter zones. Unavailable with
    /// `.notDefinedForSport`, `.noPower`, or `.zeroDenominator`.
    public var timeInPowerZones: Metric<TimeInZones>
    /// Five zones using custom boundaries, the personal threshold, or starter
    /// zones. Unavailable with `.noHeartRate` or `.zeroDenominator`.
    public var timeInHeartRateZones: Metric<TimeInZones>
    /// Five gradient bands. Unavailable with `.noGradient`.
    public var timeInGradientBands: Metric<TimeInZones>
    /// Watts per beat per minute: weighted power divided by average heart
    /// rate. Unavailable with `.notDefinedForSport` off a bike, weighted
    /// power's reason, average heart rate's reason, or `.zeroDenominator`.
    public var cyclingEfficiency: Metric<Double>
    /// Metres per second per beat per minute: average speed divided by
    /// average heart rate, both over the seconds that have both. Always
    /// speed, never pace. For walking, running and hiking; otherwise
    /// `.notDefinedForSport`. Unavailable with `.noSpeed` when the speed
    /// channel is empty, `.noHeartRate` when no second has both, or
    /// `.zeroDenominator`.
    ///
    /// The spec's table for unknown pause positions does not list it. Its
    /// definition does not use pause positions, so it stays available.
    public var onFootEfficiency: Metric<Double>
    /// One entry per kilometre, in order, for walking, running and hiking;
    /// otherwise `.notDefinedForSport`. Unavailable with
    /// `.pausePositionsUnknown` or `.noDistance`.
    public var splits: Metric<[Split]>
    /// One entry per distance in `AnalysisRules.bestDistances`, in that order.
    public var bestDistances: [BestDistance]

    public init(
        time: TimeMetrics,
        distance: Metric<Double>,
        ascent: Metric<Double>,
        descent: Metric<Double>,
        power: PowerMetrics,
        heartRate: HeartRateMetrics,
        load: Metric<ActivityLoad>,
        promptsForThresholdPower: Bool,
        timeInPowerZones: Metric<TimeInZones>,
        timeInHeartRateZones: Metric<TimeInZones>,
        timeInGradientBands: Metric<TimeInZones>,
        cyclingEfficiency: Metric<Double>,
        onFootEfficiency: Metric<Double>,
        splits: Metric<[Split]>,
        bestDistances: [BestDistance]
    ) {
        self.time = time
        self.distance = distance
        self.ascent = ascent
        self.descent = descent
        self.power = power
        self.heartRate = heartRate
        self.load = load
        self.promptsForThresholdPower = promptsForThresholdPower
        self.timeInPowerZones = timeInPowerZones
        self.timeInHeartRateZones = timeInHeartRateZones
        self.timeInGradientBands = timeInGradientBands
        self.cyclingEfficiency = cyclingEfficiency
        self.onFootEfficiency = onFootEfficiency
        self.splits = splits
        self.bestDistances = bestDistances
    }
}

/// The three times, in seconds.
public struct TimeMetrics: Hashable, Codable, Sendable {
    /// With a stream, the length of the stream. With no stream, the stated
    /// end minus the stated start, or `.notStated` when either is absent. A
    /// stated end before the stated start is also `.notStated`: the spec does
    /// not cover it, and a negative time is not a time.
    public var elapsed: Metric<TimeInterval>
    /// With known pause positions, elapsed time minus the paused spans. With
    /// unknown pause positions or no stream, the stated timer time, or
    /// `.notStated` when none is stated.
    public var timer: Metric<TimeInterval>
    /// True when `timer` is the stated figure of a stream whose pause
    /// positions are unknown. It is then a summary figure only, and no other
    /// metric is built on it.
    public var timerIsSummaryOnly: Bool
    /// Outdoors with known pause positions: timer time minus the timer
    /// seconds whose speed is below the sport's floor. A second exactly at
    /// the floor is moving, and so is a second with missing speed. Indoors,
    /// or with no speed at all, it equals timer time. With no stream it
    /// equals the stated timer time.
    ///
    /// Unavailable with `.pausePositionsUnknown` whenever a stream's pause
    /// positions are unknown, indoors included: the spec's table lists moving
    /// time as unavailable without exception. The spec gives a floor on foot
    /// and on a bike only, so for any other sport moving time equals timer
    /// time.
    public var moving: Metric<TimeInterval>

    public init(
        elapsed: Metric<TimeInterval>,
        timer: Metric<TimeInterval>,
        timerIsSummaryOnly: Bool,
        moving: Metric<TimeInterval>
    ) {
        self.elapsed = elapsed
        self.timer = timer
        self.timerIsSummaryOnly = timerIsSummaryOnly
        self.moving = moving
    }
}

/// The power metrics. They are for cycling only: for any other sport every
/// one is unavailable with `.notDefinedForSport` and the flag is false.
public struct PowerMetrics: Hashable, Codable, Sendable {
    /// The share of timer seconds with measured or interpolated power, from
    /// 0 to 1. A ride with no power at all has a coverage of 0, which is a
    /// true zero. Unavailable with `.pausePositionsUnknown`, or
    /// `.zeroDenominator` when timer time is zero.
    public var coverage: Metric<Double>
    /// Watts: the sum of power divided by the number of seconds that have
    /// power, zeros included. Unavailable with `.noPower`.
    public var average: Metric<Double>
    /// Whether coverage is shown beside average power: true when both are
    /// available and coverage is under
    /// `AnalysisRules.averagePowerCoverageNoteBelow`.
    public var averageShowsCoverage: Bool
    /// Watts. Over timer time, with paused spans removed and the series
    /// joined: the mean of each valid 30-second window, raised to the fourth
    /// power, averaged over the valid windows, then the fourth root. A window
    /// starts at every timer second that leaves room for a whole window. Its
    /// mean leaves missing seconds out of both the sum and the count.
    ///
    /// Unavailable with `.pausePositionsUnknown`, `.noPower`,
    /// `.tooLittlePower` when fewer than
    /// `AnalysisRules.weightedMinimumPowerSeconds` timer seconds have power,
    /// or `.tooFewValidWindows` when under
    /// `AnalysisRules.weightedMinimumValidWindowShare` of the possible
    /// windows are valid, checked in that order.
    public var weighted: Metric<Double>
    /// Weighted power divided by the threshold power in effect on the
    /// activity date. Unavailable with weighted power's reason,
    /// `.noThresholdPower`, or `.zeroDenominator` for a threshold of zero.
    public var intensity: Metric<Double>
    /// Timer hours times intensity squared times 100. Unavailable with
    /// intensity's reason.
    public var load: Metric<Double>
    /// Weighted power divided by average power. Unavailable with weighted
    /// power's reason, or `.zeroDenominator` when average power is zero.
    public var variability: Metric<Double>
    /// Unavailable with `.noPower`.
    public var work: Metric<Work>

    public init(
        coverage: Metric<Double>,
        average: Metric<Double>,
        averageShowsCoverage: Bool,
        weighted: Metric<Double>,
        intensity: Metric<Double>,
        load: Metric<Double>,
        variability: Metric<Double>,
        work: Metric<Work>
    ) {
        self.coverage = coverage
        self.average = average
        self.averageShowsCoverage = averageShowsCoverage
        self.weighted = weighted
        self.intensity = intensity
        self.load = load
        self.variability = variability
        self.work = work
    }
}

/// The energy the power meter recorded.
public struct Work: Hashable, Codable, Sendable {
    /// The sum of power over the seconds that have it, in kilojoules.
    public var kilojoules: Double
    /// Whether to label it "recorded work": true when pause positions are
    /// unknown or coverage is under `AnalysisRules.recordedWorkCoverageBelow`.
    /// When timer time is zero, coverage is unavailable rather than under
    /// that share, so by the literal reading the label is off.
    public var isRecordedOnly: Bool

    public init(kilojoules: Double, isRecordedOnly: Bool) {
        self.kilojoules = kilojoules
        self.isRecordedOnly = isRecordedOnly
    }
}

/// One point of the power curve.
public struct PowerCurvePoint: Hashable, Codable, Sendable {
    /// Seconds.
    public var duration: Int
    /// Watts: the best mean over the valid windows of this duration.
    public var power: Metric<Double>

    public init(duration: Int, power: Metric<Double>) {
        self.duration = duration
        self.power = power
    }
}

/// The heart-rate metrics, for every sport.
public struct HeartRateMetrics: Hashable, Codable, Sendable {
    /// The share of timer seconds with measured or interpolated heart rate,
    /// from 0 to 1. Unavailable with `.pausePositionsUnknown`, or
    /// `.zeroDenominator` when timer time is zero.
    public var coverage: Metric<Double>
    /// Beats per minute, over the seconds that have heart rate. Unavailable
    /// with `.noHeartRate`.
    public var average: Metric<Double>
    /// Each timer second with heart rate scores (heart rate / threshold heart
    /// rate) squared. Load is the sum, divided by 3,600, times 100. A timer
    /// second with no heart rate scores nothing and is not estimated.
    ///
    /// Unavailable with coverage's reason, `.noHeartRate`,
    /// `.lowHeartRateCoverage` when coverage is under
    /// `AnalysisRules.heartRateLoadMinimumCoverage`, `.noThresholdHeartRate`,
    /// or `.zeroDenominator` for a threshold of zero, checked in that order.
    public var load: Metric<Double>

    public init(coverage: Metric<Double>, average: Metric<Double>, load: Metric<Double>) {
        self.coverage = coverage
        self.average = average
        self.load = load
    }
}

/// Where an activity's load came from.
public enum LoadSource: String, Hashable, Codable, Sendable {
    case power
    case heartRate
}

/// The load an activity gets, and which rule supplied it.
public struct ActivityLoad: Hashable, Codable, Sendable {
    public var value: Double
    public var source: LoadSource

    public init(value: Double, source: LoadSource) {
        self.value = value
        self.source = source
    }
}

/// One kilometre of an activity on foot.
///
/// The spec says only "pace, heart rate and ascent per km", so the rest is
/// the simplest whole-second reading. Every second of the stream belongs to
/// the split its cumulative distance falls in: split n holds the seconds
/// whose distance is at least n km and under n + 1 km, so a second exactly on
/// a kilometre mark opens the next split. A second with missing distance
/// takes the last distance before it, and one before any distance belongs to
/// split 0. The last split is usually a part kilometre.
public struct Split: Hashable, Codable, Sendable {
    /// Counted from 0 for the first kilometre.
    public var index: Int
    /// Metres. A whole split is `AnalysisRules.splitDistance`; the last is
    /// the activity's distance minus the split's starting mark.
    public var distance: Double
    /// Timer seconds in the split. Paused seconds are not counted.
    public var duration: TimeInterval
    /// Seconds per kilometre: the duration divided by the distance in
    /// kilometres. Unavailable with `.zeroDenominator` when the distance is
    /// zero. A split covered wholly while paused has a duration of zero and
    /// so, by the literal reading, a pace of zero.
    public var pace: Metric<Double>
    /// Beats per minute over the split's timer seconds that have heart rate.
    /// Unavailable with `.noHeartRate` when none does.
    public var averageHeartRate: Metric<Double>
    /// Metres. Each climb the activity's ascent counts is credited to the
    /// split holding the second at which it is counted, so the splits add up
    /// to the activity's ascent. Unavailable with `.noAltitude` when the
    /// stream has no altitude.
    public var ascent: Metric<Double>

    public init(
        index: Int,
        distance: Double,
        duration: TimeInterval,
        pace: Metric<Double>,
        averageHeartRate: Metric<Double>,
        ascent: Metric<Double>
    ) {
        self.index = index
        self.distance = distance
        self.duration = duration
        self.pace = pace
        self.averageHeartRate = averageHeartRate
        self.ascent = ascent
    }
}

/// The fastest time over one distance within an activity.
public struct BestDistance: Hashable, Codable, Sendable {
    /// Metres.
    public var distance: Double
    /// Timer seconds: the fewest between two seconds of the stream whose
    /// cumulative distances differ by at least `distance`. From second i to a
    /// later second j the time is the number of timer seconds in i..<j, so a
    /// pause inside the stretch adds nothing, and the result is a whole
    /// number of seconds. A second with no distance is not an end point.
    ///
    /// For walking and running; otherwise `.notDefinedForSport`. Unavailable
    /// with `.pausePositionsUnknown`, `.noDistance`, or `.distanceNotCovered`.
    public var time: Metric<TimeInterval>

    public init(distance: Double, time: Metric<TimeInterval>) {
        self.distance = distance
        self.time = time
    }
}
