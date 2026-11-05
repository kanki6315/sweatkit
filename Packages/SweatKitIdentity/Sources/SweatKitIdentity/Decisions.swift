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
        switch self {
        case .title: .title
        case .hidden: .hidden
        case .primary: .primary
        }
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
        value.field
    }

    /// The winner among `decisions`, or nil when there are none.
    ///
    /// The winner is the decision with the later time. On equal times a
    /// direct decision beats an inherited copy, then the higher device ID
    /// wins, then the higher record name.
    ///
    /// Fields are not looked at, so the caller passes decisions on one
    /// field. The result does not depend on their order.
    ///
    /// The spec does not say what happens when two different records tie on
    /// time, origin, device and name. Names are meant to be unique, so that
    /// is a storage fault. So that the result still does not depend on
    /// order, such a tie goes to the higher value and then the higher
    /// member list, each compared in a canonical text form.
    public static func winner(among decisions: some Sequence<DecisionRecord>) -> DecisionRecord? {
        var winner: DecisionRecord?
        for decision in decisions {
            if let current = winner {
                if decision.beats(current) {
                    winner = decision
                }
            } else {
                winner = decision
            }
        }
        return winner
    }

    /// The winning decision on `field` among those that apply to `member`,
    /// or nil when none does. A decision applies to a member when its
    /// `members` holds it.
    public static func winner(
        of field: DecisionField,
        for member: SourceIdentity,
        among decisions: some Sequence<DecisionRecord>
    ) -> DecisionRecord? {
        winner(among: decisions.lazy.filter { $0.field == field && $0.members.contains(member) })
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
        DecisionIndex(decisions).inEffect(field, members: members)
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
        DecisionIndex(decisions).title(of: members)
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
        DecisionIndex(decisions).isHidden(members)
    }

    /// Whether this decision wins over `other`.
    func beats(_ other: DecisionRecord) -> Bool {
        if time != other.time {
            return time > other.time
        }
        if origin != other.origin {
            return origin == .direct
        }
        if device != other.device {
            return device > other.device
        }
        if name != other.name {
            return name > other.name
        }
        return (value.canonicalText, canonicalMembers) > (other.value.canonicalText, other.canonicalMembers)
    }

    /// The members in canonical form, in ascending order, joined by commas.
    private var canonicalMembers: String {
        members.sorted().map(\.description).joined(separator: ",")
    }
}

extension DecisionValue {
    /// A text form that is the same on every device. It only settles ties
    /// that the spec's order leaves open.
    fileprivate var canonicalText: String {
        switch self {
        case .title(let title): "title:\(title)"
        case .hidden(let hidden): "hidden:\(hidden)"
        case .primary(let identity): "primary:\(identity)"
        }
    }
}

/// Each member's winning decision on each field, worked out in one pass
/// over the decisions. Resolving a whole library reads it once per
/// activity instead of reading every decision again.
struct DecisionIndex {
    private struct Key: Hashable {
        let member: SourceIdentity
        let field: DecisionField
    }

    private var winners: [Key: DecisionRecord] = [:]
    /// The time of each identity's latest restore: the latest
    /// `.hidden(false)` decision that applies to it.
    private var latestRestores: [SourceIdentity: Date] = [:]

    init(_ decisions: some Sequence<DecisionRecord>) {
        for decision in decisions {
            let field = decision.field
            let isRestore = decision.value == .hidden(false)
            for member in decision.members {
                let key = Key(member: member, field: field)
                if let current = winners[key] {
                    if decision.beats(current) {
                        winners[key] = decision
                    }
                } else {
                    winners[key] = decision
                }
                if isRestore {
                    if let latest = latestRestores[member] {
                        latestRestores[member] = max(latest, decision.time)
                    } else {
                        latestRestores[member] = decision.time
                    }
                }
            }
        }
    }

    /// The winning decision on `field` among those that apply to `member`.
    func winner(of field: DecisionField, for member: SourceIdentity) -> DecisionRecord? {
        winners[Key(member: member, field: field)]
    }

    /// See `DecisionRecord.inEffect(_:members:among:)`.
    func inEffect(_ field: DecisionField, members: Set<SourceIdentity>) -> DecisionRecord? {
        let memberWinners = members.compactMap { winner(of: field, for: $0) }
        if field == .hidden {
            let hides = memberWinners.filter { $0.value == .hidden(true) }
            if !hides.isEmpty {
                return DecisionRecord.winner(among: hides)
            }
        }
        return DecisionRecord.winner(among: memberWinners)
    }

    /// See `DecisionRecord.title(of:among:)`.
    func title(of members: Set<SourceIdentity>) -> String? {
        guard case .title(let title)? = inEffect(.title, members: members)?.value else {
            return nil
        }
        return title
    }

    /// See `DecisionRecord.isHidden(_:among:)`.
    func isHidden(_ members: Set<SourceIdentity>) -> Bool {
        members.contains { winner(of: .hidden, for: $0)?.value == .hidden(true) }
    }

    /// The primary choice in effect for an activity of `members`, whether
    /// or not the chosen record is still a member.
    func primaryChoice(of members: Set<SourceIdentity>) -> SourceIdentity? {
        guard case .primary(let identity)? = inEffect(.primary, members: members)?.value else {
            return nil
        }
        return identity
    }

    /// When the latest restore that applies to `identity` was made, or nil
    /// when there is none.
    func latestRestore(of identity: SourceIdentity) -> Date? {
        latestRestores[identity]
    }
}
