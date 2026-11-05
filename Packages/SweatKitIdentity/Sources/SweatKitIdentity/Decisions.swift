import Foundation
import SweatKitModel

/// The fields a user decision can set on an activity.
public enum DecisionField: String, Codable, Sendable, CaseIterable {
    case title
    case hidden
    /// Which member supplies the streams.
    case primary
}

/// The value of a decision. The case says which field it sets.
public enum DecisionValue: Hashable, Codable, Sendable {
    case title(String)
    /// True is "hide". False is a restore.
    case hidden(Bool)
    /// The member chosen as the primary record.
    case primary(SourceIdentity)

    /// The field this value sets.
    public var field: DecisionField {
        fatalError("unimplemented")
    }
}

/// Whether a decision record is the decision itself or a copy written by a
/// split.
public enum DecisionOrigin: String, Codable, Sendable, CaseIterable {
    case direct
    case inheritedCopy
}

/// One user decision about an activity.
///
/// A decision belongs to the activity, not to whichever record supplies its
/// streams, so it lists the member identities it applies to: all of the
/// activity's members at the time it was made. Decision records are only
/// ever added, never edited. A merge writes none.
public struct DecisionRecord: Hashable, Codable, Sendable {
    public let name: RecordName
    public let value: DecisionValue
    /// When the decision was made. An inherited copy keeps the time of the
    /// decision it copies.
    public let time: Date
    /// The device that wrote this record.
    public let device: DeviceID
    /// The member identities the decision applies to.
    public let members: Set<SourceIdentity>
    public let origin: DecisionOrigin

    public init(
        name: RecordName,
        value: DecisionValue,
        time: Date,
        device: DeviceID,
        members: Set<SourceIdentity>,
        origin: DecisionOrigin = .direct
    ) {
        self.name = name
        self.value = value
        self.time = time
        self.device = device
        self.members = members
        self.origin = origin
    }

    /// The field this decision sets.
    public var field: DecisionField {
        fatalError("unimplemented")
    }

    /// The winner among `decisions`, or nil when there are none.
    ///
    /// The winner is the decision with the later time. On equal times a
    /// direct decision beats an inherited copy, then the higher device ID
    /// wins, then the higher record name.
    ///
    /// Fields and values are not looked at, so the caller passes decisions
    /// on one field. The result does not depend on their order.
    public static func winner(among decisions: some Sequence<DecisionRecord>) -> DecisionRecord? {
        fatalError("unimplemented")
    }

    /// The winning decision on `field` among those that apply to `member`,
    /// or nil when none does. A decision applies to a member when its
    /// `members` holds it.
    public static func winner(
        of field: DecisionField,
        for member: SourceIdentity,
        among decisions: some Sequence<DecisionRecord>
    ) -> DecisionRecord? {
        fatalError("unimplemented")
    }

    /// The decision that gives an activity of `members` its value for
    /// `field`, or nil when no decision on that field applies to any member.
    ///
    /// For a title or a primary choice it is the winner among the members'
    /// winning decisions.
    ///
    /// For hidden state the spec names no single decision, so this takes the
    /// reading that matches how the state is worked out: when any member's
    /// winning decision is "hide", it is the winner among those "hide"
    /// decisions; otherwise it is the winner among the members' winning
    /// decisions. This is what a split copies to each part.
    public static func inEffect(
        _ field: DecisionField,
        members: Set<SourceIdentity>,
        among decisions: some Sequence<DecisionRecord>
    ) -> DecisionRecord? {
        fatalError("unimplemented")
    }

    /// The title of an activity of `members`, or nil when no title decision
    /// applies to any of them.
    ///
    /// Each member's winning title decision is taken, and the activity uses
    /// the winner among those. A merged activity therefore has the most
    /// recent title of its parts.
    public static func title(
        of members: Set<SourceIdentity>,
        among decisions: some Sequence<DecisionRecord>
    ) -> String? {
        fatalError("unimplemented")
    }

    /// Whether an activity of `members` is hidden by its decisions.
    ///
    /// Each member's winning hidden-state decision is taken, and the
    /// activity is hidden if any of them is "hide". A later restore on one
    /// member does not unhide an activity that another member's winning
    /// decision hides. With no hidden-state decision it is not hidden.
    ///
    /// Tombstones are not read here. See `Tombstone.standing`.
    public static func isHidden(
        _ members: Set<SourceIdentity>,
        among decisions: some Sequence<DecisionRecord>
    ) -> Bool {
        fatalError("unimplemented")
    }
}
