import Foundation
import SweatKitAnalysis
import SweatKitModel
import SweatKitStore

/// How an activity's metrics become its row in the feed: the generated title
/// and the headline. The spec's "Activity feed" section is the contract, and
/// each place it is silent is marked "Reading:" below.
///
/// Strings are English literals. There is no string catalogue yet.
public enum FeedRules {
    // MARK: Headline

    /// The headline kind of a ride that has power: its average power in
    /// watts. Retained for decoding older feed rows.
    public static let averagePowerHeadline = "averagePower"

    /// M5 headline. Unavailable weighted power is never replaced with average power.
    public static let weightedPowerHeadline = "weightedPower"

    /// The headline kind of a walk, a run or a hike: its average pace in
    /// seconds per kilometre.
    public static let averagePaceHeadline = "averagePace"

    public static let metresPerKilometre = 1000.0

    /// The headline of an activity, or nil when its sport has none.
    ///
    /// - Cycling with power: weighted power. Reading: the spec gives the
    ///   headline to "rides with a power meter", so a ride with no power has
    ///   no headline at all, not an unavailable one.
    /// - Walking, running and hiking: average pace, which can be
    ///   unavailable. Reading: the spec says "walks and runs"; a hike is on
    ///   foot and coloured by pace like them, so it takes the same headline.
    /// - Any other sport: none.
    public static func headline(sport: Sport, metrics: ActivityMetrics) -> ActivityRecord.Headline? {
        switch sport.family {
        case .cycling:
            guard case .available = metrics.power.average else { return nil }
            return ActivityRecord.Headline(kind: weightedPowerHeadline, value: metrics.power.weighted)
        case .onFoot:
            return ActivityRecord.Headline(kind: averagePaceHeadline, value: averagePace(metrics))
        case .other:
            return nil
        }
    }

    /// Seconds per kilometre: moving time divided by distance in kilometres.
    ///
    /// Reading: the spec names average pace without defining it. The feed
    /// card shows moving time and distance beside the headline, so the pace
    /// is the one those two figures give. It is unavailable with moving
    /// time's reason, then distance's reason, then `.zeroDenominator` for a
    /// distance of zero. It is never worked out from timer or elapsed time
    /// in place of a moving time that is unavailable.
    public static func averagePace(_ metrics: ActivityMetrics) -> Metric<Double> {
        guard let moving = metrics.time.moving.value else {
            return .unavailable(metrics.time.moving.reason ?? .notStated)
        }
        guard let distance = metrics.distance.value else {
            return .unavailable(metrics.distance.reason ?? .noDistance)
        }
        guard distance > 0 else { return .unavailable(.zeroDenominator) }
        return .available(moving / (distance / metresPerKilometre))
    }

    // MARK: Title

    /// The part of the day an activity started in, by its local clock.
    ///
    /// Reading: the spec says titles come from the time of day and gives
    /// "Morning ride" as its one example. The four parts and their hours
    /// are this package's choice.
    public enum TimeOfDay: String, Hashable, Sendable, CaseIterable {
        case morning
        case afternoon
        case evening
        case night

        /// The part of the day that holds `hour`, from 0 to 23.
        public init(hour: Int) {
            switch hour {
            case FeedRules.morningStartHour..<FeedRules.afternoonStartHour: self = .morning
            case FeedRules.afternoonStartHour..<FeedRules.eveningStartHour: self = .afternoon
            case FeedRules.eveningStartHour..<FeedRules.nightStartHour: self = .evening
            default: self = .night
            }
        }
    }

    /// The first hour of the morning. Night runs up to it.
    public static let morningStartHour = 5
    /// The first hour of the afternoon.
    public static let afternoonStartHour = 12
    /// The first hour of the evening.
    public static let eveningStartHour = 17
    /// The first hour of the night, which runs past midnight.
    public static let nightStartHour = 21

    private static let secondsPerHour = 3600
    private static let secondsPerDay = 86_400

    /// The hour of the local clock at `start`, from 0 to 23, for a zone
    /// `utcOffset` seconds east of UTC.
    public static func localHour(of start: Date, utcOffset: Int) -> Int {
        let local = Int(start.timeIntervalSince1970.rounded(.down)) + utcOffset
        let secondOfDay = ((local % secondsPerDay) + secondsPerDay) % secondsPerDay
        return secondOfDay / secondsPerHour
    }

    /// The generated title of an activity, such as "Morning ride".
    ///
    /// - The time of day comes from the start on the activity's own clock.
    ///   Reading: when the UTC offset is unknown the time of day is left
    ///   out, and the title is the sport alone, such as "Virtual ride". The
    ///   device's own time zone is not used in its place, so the same file
    ///   gets the same title on every device.
    /// - The sport is "ride", "walk", "run" or "hike", and "activity" for
    ///   any other. A virtual activity is a "virtual ride", and an indoor
    ///   one that is not virtual an "indoor ride".
    /// - The spec adds the locality: "Morning ride, Richmond Park". The app resolves
    ///   and caches the locality separately, so offline imports remain usable.
    public static func title(
        sport: Sport,
        isIndoor: Bool = false,
        isVirtual: Bool = false,
        start: Date,
        utcOffset: Int?,
        locality: String? = nil
    ) -> String {
        var words: [String] = []
        if let utcOffset {
            words.append(TimeOfDay(hour: localHour(of: start, utcOffset: utcOffset)).rawValue)
        }
        if isVirtual {
            words.append("virtual")
        } else if isIndoor {
            words.append("indoor")
        }
        words.append(noun(for: sport))
        let phrase = words.joined(separator: " ")
        let title = phrase.prefix(1).uppercased() + phrase.dropFirst()
        guard let locality, !locality.isEmpty else { return title }
        return "\(title), \(locality)"
    }

    private static func noun(for sport: Sport) -> String {
        switch sport {
        case .cycling: "ride"
        case .walking: "walk"
        case .running: "run"
        case .hiking: "hike"
        case .other: "activity"
        }
    }

    /// The title `title(...)` gives a stored row from its own fields, with
    /// an optional cached locality.
    static func generatedTitle(for row: ActivityRecord, locality: String? = nil) -> String {
        title(sport: row.sport, isIndoor: row.isIndoor, isVirtual: row.isVirtual, start: row.start, utcOffset: row.utcOffset, locality: locality)
    }
}

/// What a feed row takes from the decoded activity and not from its metrics.
struct ActivityFacts: Hashable, Sendable {
    var sport: Sport
    var isIndoor: Bool
    var isVirtual: Bool
    /// Seconds east of UTC at the start, when known.
    var utcOffset: Int?

    /// The facts of a decoded activity. An offset the original does not
    /// state falls back to `fallbackUTCOffset`.
    init(_ recorded: RecordedActivity, fallbackUTCOffset: Int?) {
        self.sport = recorded.sport
        self.isIndoor = recorded.isIndoor
        self.isVirtual = recorded.isVirtual
        self.utcOffset = recorded.stated.utcOffset ?? fallbackUTCOffset
    }

    /// The facts a stored row already holds, for a recompute that reads only
    /// the stored stream.
    init(_ row: ActivityRecord) {
        self.sport = row.sport
        self.isIndoor = row.isIndoor
        self.isVirtual = row.isVirtual
        self.utcOffset = row.utcOffset
    }
}

extension FeedRules {
    /// The feed row of an activity.
    ///
    /// `start` and `elapsed` are the stream's own start and length. Every
    /// other figure comes from the metrics. One the metrics report as
    /// unavailable is left nil, never zero, and never filled from what the
    /// file states about itself.
    ///
    /// `existing` is the row being replaced, if any. Its hidden state is
    /// kept. Its title is kept when it is not the title this package would
    /// have generated for it, because then someone wrote it; a generated
    /// title is generated again, so it follows a corrected sport or start.
    static func row(
        members: [SourceIdentity],
        primary: SourceIdentity,
        facts: ActivityFacts,
        start: Date,
        elapsed: TimeInterval,
        metrics: ActivityMetrics,
        existing: ActivityRecord?
    ) -> ActivityRecord {
        // Identity reconciliation applies cached locality and explicit title
        // decisions after the source facts have been derived.
        var title = FeedRules.title(
            sport: facts.sport,
            isIndoor: facts.isIndoor,
            isVirtual: facts.isVirtual,
            start: start,
            utcOffset: facts.utcOffset,
            locality: nil
        )
        if let existing, existing.title != generatedTitle(for: existing) {
            title = existing.title
        }
        return ActivityRecord(
            members: members,
            primary: primary,
            sport: facts.sport,
            start: start,
            utcOffset: facts.utcOffset,
            elapsedTime: elapsed,
            timerTime: metrics.time.timer.value,
            movingTime: metrics.time.moving.value,
            distance: metrics.distance.value,
            ascent: metrics.ascent.value,
            isIndoor: facts.isIndoor,
            isVirtual: facts.isVirtual,
            title: title,
            headline: headline(sport: facts.sport, metrics: metrics),
            isHidden: existing?.isHidden ?? false
        )
    }
}
