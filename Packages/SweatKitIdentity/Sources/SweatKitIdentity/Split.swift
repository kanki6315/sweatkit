import SweatKitModel

/// What a split writes besides its links.
///
/// The spec does not say which links a split writes, so this package writes
/// none. The caller adds user-made "keep separate" links that take effect
/// over the "same activity" links between the parts.
public enum Split {
    /// The inherited copies a split writes: one copy of every decision then
    /// in effect, once for each resulting part.
    ///
    /// A decision in effect is `DecisionRecord.inEffect(_:members:among:)`
    /// for the activity being split, so there is at most one per field.
    /// Each copy:
    /// - has the original's value,
    /// - keeps the original's time, so it is not a new decision: a rename or
    ///   hide made on another device, later than the original, still wins on
    ///   every part it applies to,
    /// - applies to that part's members,
    /// - is marked `.inheritedCopy`,
    /// - records `device`, the device making the split. The spec says a copy
    ///   keeps the original's time and says nothing of its device, so the
    ///   copy holds the device that wrote it, like every other record,
    /// - is named by `copyName(of:part:)`.
    ///
    /// The copies are ordered by name. A copy is written for every part,
    /// including parts the original already applies to. `parts` should
    /// divide `members` between them with no overlap.
    public static func inheritedCopies(
        splitting members: Set<SourceIdentity>,
        into parts: [Set<SourceIdentity>],
        decisions: some Sequence<DecisionRecord>,
        device: DeviceID
    ) -> [DecisionRecord] {
        fatalError("unimplemented")
    }

    /// The name of the copy of the decision named `original` for `part`.
    ///
    /// It is `<original>|copy|<members>`, where the members are the part's
    /// identities in canonical form, in ascending order, joined by commas,
    /// for example `t1|copy|garmin:1,healthKit:W1`. The spec does not name
    /// copies. Naming them from the original and the part means the same
    /// split made twice writes the same records, and two different parts
    /// never share a name.
    public static func copyName(of original: RecordName, part: Set<SourceIdentity>) -> RecordName {
        fatalError("unimplemented")
    }
}
