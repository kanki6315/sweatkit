import SweatKitModel

/// De-duplication, "same activity" and "keep separate" links, decisions and
/// tombstones, and the rules that form activities from them. Pure Swift. The
/// spec's "De-duplication" to "Deletion" sections are the contract.
///
/// Where to start:
/// - `MatchOutcome.between(_:_:tolerances:)` and `MatchScan.scan` apply the
///   automatic match rule.
/// - `LinkRecord.inEffect(for:among:)` picks the link in effect for a pair.
/// - `ActivityFormation.form(records:links:)` forms activities from links.
/// - `DecisionRecord` and `PrimaryChoice` resolve title, hidden state and
///   primary choice.
/// - `Split.inheritedCopies` writes the copies a split needs.
/// - `Tombstone.standing(of:tombstones:decisions:)` says whether an identity
///   is held hidden or deleted.
/// - `ResolvedLibrary.resolve` runs all of it over one set of records.
///
/// Nothing here reads a clock, a device ID or storage. Times and device IDs
/// are always passed in, and every result depends only on which records are
/// given, never on their order.
public enum SweatKitIdentity {}
