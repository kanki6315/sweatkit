import Foundation
import SweatKitAnalysis
import SweatKitIngest
import SweatKitModel

/// The version of everything that stands between an original and a stored
/// result: the decoder, the stream rules, and each algorithm.
///
/// A derived result records two values formed here. Its input revision
/// changes when the original, the decoder or the stream rules change. Its
/// algorithm version changes when any one algorithm's version changes. The
/// store compares both with what the running build says is current, which is
/// how a new build finds the results an older build left behind.
///
/// `current` is what the app uses. The parts are variables so that a test can
/// stand in for a later build by changing one.
public struct PipelineVersions: Hashable, Sendable {
    /// The version of the FIT decoder. Stored decoded activities carry it,
    /// and one from another version is decoded again from its original.
    public var decoder: Int
    /// The version of the stream rules. Stored analysis streams carry it,
    /// and one from another version is built again from the decoded activity.
    public var streamRules: Int
    /// The version of each algorithm a stored result depends on, by name.
    public var algorithms: [String: Int]

    public init(decoder: Int, streamRules: Int, algorithms: [String: Int]) {
        self.decoder = decoder
        self.streamRules = streamRules
        self.algorithms = algorithms
    }

    /// The versions of this build.
    public static let current = PipelineVersions(
        decoder: decoderVersion,
        streamRules: StreamRules.version,
        algorithms: currentAlgorithms
    )

    /// The version of `FITActivityDecoder`'s mapping from a FIT file to a
    /// `RecordedActivity`. Raise it whenever that mapping changes.
    ///
    /// Ingest exposes no decoder version, so it is defined here for now. It
    /// belongs in Ingest, beside `StreamRules.version`, where the change that
    /// should raise it is made.
    public static let decoderVersion = 1

    /// The version of the rules that turn metrics into a feed row: the title
    /// and the headline in `FeedRules`. Raising it rebuilds every row. The
    /// headline's switch to weighted power in M5 is such a change.
    public static let feedRowVersion = 2

    /// The version of the form a metrics result is stored in.
    public static let metricsPayloadVersion = 1

    /// The names the algorithm versions are combined under. Each name is
    /// part of the combined version, so renaming one stales every result.
    public enum AlgorithmName {
        public static let time = "analysis.time"
        public static let distance = "analysis.distance"
        public static let elevation = "analysis.elevation"
        public static let zones = "analysis.zones"
        public static let power = "analysis.power"
        public static let weightedPower = "analysis.weightedPower"
        public static let powerCurve = "analysis.powerCurve"
        public static let heartRate = "analysis.heartRate"
        public static let load = "analysis.load"
        public static let efficiency = "analysis.efficiency"
        public static let splits = "analysis.splits"
        public static let bestDistances = "analysis.bestDistances"
        public static let feedRow = "library.feedRow"
        public static let metricsPayload = "library.metricsPayload"
    }

    /// Every one of Analysis's per-algorithm versions, and this package's
    /// own two.
    ///
    /// The power curve is not part of the stored metrics, so its version
    /// stales them without need. It is included all the same: the rule is
    /// that any one of Analysis's versions changes the combined version, and
    /// a rule with no exceptions cannot be forgotten when the metrics grow.
    public static let currentAlgorithms: [String: Int] = [
        AlgorithmName.time: AlgorithmVersion.time,
        AlgorithmName.distance: AlgorithmVersion.distance,
        AlgorithmName.elevation: AlgorithmVersion.elevation,
        AlgorithmName.zones: AlgorithmVersion.zones,
        AlgorithmName.power: AlgorithmVersion.power,
        AlgorithmName.weightedPower: AlgorithmVersion.weightedPower,
        AlgorithmName.powerCurve: AlgorithmVersion.powerCurve,
        AlgorithmName.heartRate: AlgorithmVersion.heartRate,
        AlgorithmName.load: AlgorithmVersion.load,
        AlgorithmName.efficiency: AlgorithmVersion.efficiency,
        AlgorithmName.splits: AlgorithmVersion.splits,
        AlgorithmName.bestDistances: AlgorithmVersion.bestDistances,
        AlgorithmName.feedRow: feedRowVersion,
        AlgorithmName.metricsPayload: metricsPayloadVersion,
    ]

    /// The version of the canonical forms hashed below. Changing a form
    /// changes every input revision and every combined version.
    private static let canonicalFormVersion = 1

    /// The number of hexadecimal digits of the hash kept as the combined
    /// algorithm version: 60 bits, which fits a non-negative `Int`.
    private static let combinedVersionDigits = 15

    private static let hexadecimal = 16

    /// The input revision of a result computed from `original`: a hash of
    /// the original's content hash, the decoder version and the stream-rules
    /// version. It changes when any of the three does.
    public func inputRevision(original: ContentHash) -> ContentHash {
        let lines = [
            "sweatkit-library/input/\(Self.canonicalFormVersion)",
            "original=\(original.hex)",
            "decoder=\(decoder)",
            "streamRules=\(streamRules)",
        ]
        return ContentHash(of: Data(lines.joined(separator: "\n").utf8))
    }

    /// One number for all of `algorithms`: the leading 60 bits of a hash of
    /// every name and version, in name order. It changes when any one
    /// version changes and when an algorithm is added or removed.
    ///
    /// It is a hash and not a sum, so that raising one version while another
    /// build lowers a different one can never land on the same number. It is
    /// never negative.
    public var combinedAlgorithmVersion: Int {
        var lines = ["sweatkit-library/algorithms/\(Self.canonicalFormVersion)"]
        for (name, version) in algorithms.sorted(by: { $0.key < $1.key }) {
            lines.append("\(name)=\(version)")
        }
        let hash = ContentHash(of: Data(lines.joined(separator: "\n").utf8))
        // Fifteen hexadecimal digits always parse and always fit.
        return Int(hash.hex.prefix(Self.combinedVersionDigits), radix: Self.hexadecimal) ?? .zero
    }
}
