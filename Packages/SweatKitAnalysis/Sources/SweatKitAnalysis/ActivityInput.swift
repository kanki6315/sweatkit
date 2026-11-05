import Foundation
import SweatKitModel

/// Everything one activity's metrics are computed from.
public struct ActivityInput: Hashable, Sendable {
    /// What the activity recorded.
    public enum Recording: Hashable, Sendable {
        /// The analysis stream. Its `pauses` value says whether pause
        /// positions are known, and its `count` is elapsed time: the stream
        /// builder has already applied the stated start and end, the
        /// first-and-last-sample fallback and the treated-as-unpaused rule.
        case stream(AnalysisStream)
        /// An activity with no stream, which has only what its original states.
        case summaryOnly(StatedSummary)
    }

    public var sport: Sport
    public var isIndoor: Bool
    public var recording: Recording
    public var profile: AthleteProfile
    /// The date whose threshold power applies.
    public var activityDate: Date

    public init(
        sport: Sport,
        isIndoor: Bool = false,
        recording: Recording,
        profile: AthleteProfile = AthleteProfile(),
        activityDate: Date
    ) {
        self.sport = sport
        self.isIndoor = isIndoor
        self.recording = recording
        self.profile = profile
        self.activityDate = activityDate
    }
}
