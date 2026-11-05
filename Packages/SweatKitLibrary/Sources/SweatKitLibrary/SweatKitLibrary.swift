/// The pipeline that takes an imported file to a stored activity, and keeps
/// what was derived from it up to date.
///
/// - `ActivityLibrary` is the actor screens and sync talk to. It imports
///   files, reads the feed, reads and saves the athlete profile, and
///   recomputes derived results that have gone stale.
/// - `PipelineVersions` names the version of everything a result was built
///   by, and forms the input revision and the combined algorithm version a
///   result's provenance records.
/// - `FeedRules` generates the title and the headline of a feed row.
///
/// This package sits above the leaf packages on purpose: it joins
/// `SweatKitIngest`, `SweatKitAnalysis` and `SweatKitStore`, which never
/// depend on each other. The spec's "Data model and storage", "Activity
/// feed" and "Analysis metrics" sections are the contract.
///
/// Identity matching, merge/split, title, primary and visibility decisions
/// are persisted separately from the resolved feed.
/// Not here yet: reading a zip or a folder, geocoding a locality for the
/// title, HealthKit snapshots, and permanent deletion.
public enum SweatKitLibrary {}
