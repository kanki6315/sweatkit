import SweatKitModel

/// Turns an original into the stream everything else reads.
///
/// - `FITActivityDecoder` reads a FIT file into a `RecordedActivity`.
/// - `StreamNormaliser` builds the 1 Hz `AnalysisStream` from a
///   `RecordedActivity` under `StreamRules`.
///
/// The spec's "Stream rules" section and the "Time" table of "Analysis
/// metrics" are the contract.
public enum SweatKitIngest {}
