import Foundation
import SweatKitAnalysis
import SweatKitIngest
import SweatKitModel
import SweatKitStore

/// The heavy steps between an original and what is stored for it: decoding,
/// building the stream, and computing the metrics. Each runs on the
/// concurrent executor, off the library's actor and off the main actor, and
/// touches no storage.
enum Pipeline {
    /// A decoded original and the analysis stream built from it.
    struct Decoded: Sendable {
        var recorded: RecordedActivity
        var stream: AnalysisStream
        var sourceSportName: String? = nil
    }

    /// The activity a result is computed for.
    struct Target: Sendable {
        var members: [SourceIdentity]
        var primary: SourceIdentity
        /// The primary's current revision: the original the stream came from.
        var revision: ContentHash
        /// The stored row being replaced, if any.
        var existing: ActivityRecord?
    }

    /// The feed row and the stored metrics of one activity.
    struct Derived: Sendable {
        var row: ActivityRecord
        var result: DerivedResult
    }

    /// The bytes of one file of a batch.
    @concurrent
    static func read(_ contents: ImportFile.Contents) async throws -> Data {
        switch contents {
        case .bytes(let bytes):
            return bytes
        case .url(let url):
            do {
                return try Data(contentsOf: url)
            } catch {
                throw LibraryError.unreadableFile(error.localizedDescription)
            }
        }
    }

    /// Decodes a FIT file and builds its analysis stream. Throws Ingest's
    /// `FITDecodeError` for a file that is not a sound FIT activity, and
    /// `LibraryError.noTimeSpan` for one with nothing to put a grid on.
    @concurrent
    static func decode(_ bytes: Data, versions: PipelineVersions, allowsSnapshot: Bool = false) async throws -> Decoded {
        let snapshot = allowsSnapshot ? try HealthSnapshot.decode(bytes) : nil
        let recorded = try snapshot?.activity ?? FITActivityDecoder.decode(bytes)
        return Decoded(recorded: recorded, stream: try stream(of: recorded, versions: versions), sourceSportName: snapshot?.sourceSportName)
    }

    /// Builds the analysis stream of an activity that is already decoded.
    @concurrent
    static func normalise(_ recorded: RecordedActivity, versions: PipelineVersions) async throws -> AnalysisStream {
        try stream(of: recorded, versions: versions)
    }

    private static func stream(of recorded: RecordedActivity, versions: PipelineVersions) throws -> AnalysisStream {
        guard var stream = StreamNormaliser.analysisStream(from: recorded) else {
            throw LibraryError.noTimeSpan
        }
        // The same number in the app. A test that stands in for a later
        // build's rules changes `versions`, and the stream must then carry
        // that version to be read back as current.
        stream.rulesVersion = versions.streamRules
        return stream
    }

    /// Computes the metrics of one activity, and from them its feed row and
    /// the result to store, with the provenance the store checks.
    @concurrent
    static func derive(
        facts: ActivityFacts,
        stream: AnalysisStream,
        profile: AthleteProfile,
        versions: PipelineVersions,
        target: Target,
        at date: Date,
        summaryOnly: StatedSummary? = nil,
        sourceDistance: Double? = nil
    ) async throws -> Derived {
        // Thresholds are looked up for the activity's start.
        let activityDate = stream.start
        let input = ActivityInput(
            sport: facts.sport,
            isIndoor: facts.isIndoor,
            isVirtual: facts.isVirtual,
            recording: summaryOnly.map(ActivityInput.Recording.summaryOnly) ?? .stream(stream),
            profile: profile,
            activityDate: activityDate
        )
        let metrics = ActivityAnalysis.metrics(for: input)

        var row = FeedRules.row(
            members: target.members,
            primary: target.primary,
            facts: facts,
            start: stream.start,
            elapsed: TimeInterval(stream.count) * StreamRules.gridInterval,
            metrics: metrics,
            existing: target.existing
        )

        // The source's total distance remains available for a summary-only
        // workout, without inventing a per-second distance series.
        if let summaryOnly {
            row.distance = summaryOnly.distance
            row.elapsedTime = metrics.time.elapsed.value ?? row.elapsedTime
        }
        if row.distance == nil { row.distance = sourceDistance }

        let reading = ProfileReading(date: activityDate, inputs: profileInputs(for: facts.sport))
        let provenance = Provenance(
            inputRevision: versions.inputRevision(original: target.revision),
            profileFingerprint: profile.fingerprint(on: reading.date, reading: reading.inputs),
            algorithmVersion: versions.combinedAlgorithmVersion
        )
        // The row's ID is the lowest member, which is what the store names
        // the activity by.
        let id = target.members.min() ?? target.primary
        let result = DerivedResult(
            owner: .activity(id),
            kind: ActivityLibrary.metricsKind,
            provenance: provenance,
            profileReading: reading,
            payload: try encode(metrics),
            computedAt: date
        )
        return Derived(row: row, result: result)
    }

    /// The profile values the metrics of a sport read.
    ///
    /// Every sport reads the threshold heart rate, for time in heart-rate
    /// zones and load from heart rate. Only cycling reads threshold power,
    /// for intensity, load from power and time in power zones: off a bike
    /// those are not defined, so a corrected threshold power leaves a walk's
    /// metrics valid. Max heart rate is read only through the threshold
    /// heart rate it stands in for, which the threshold's fingerprint
    /// already covers.
    ///
    /// This restates what Analysis reads. It belongs in Analysis, which is
    /// the only place that can keep it true.
    static func profileInputs(for sport: Sport) -> AthleteProfile.Inputs {
        sport == .cycling ? [.thresholdPower, .thresholdHeartRate] : [.thresholdHeartRate]
    }

    // MARK: The stored form of the metrics

    /// A binary property list, which holds every `Double` exactly.
    /// `PipelineVersions.metricsPayloadVersion` is the version of this form.
    static func encode(_ metrics: ActivityMetrics) throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(metrics)
    }

    /// The metrics a stored result holds, or nil when it was written in a
    /// form this build does not read.
    static func decodeMetrics(_ payload: Data) -> ActivityMetrics? {
        try? PropertyListDecoder().decode(ActivityMetrics.self, from: payload)
    }
}
