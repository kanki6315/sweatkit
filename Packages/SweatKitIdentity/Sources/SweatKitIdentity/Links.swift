import Foundation
import SweatKitModel

/// What a link says about its two source records.
public enum LinkKind: String, Codable, Sendable, CaseIterable {
    /// The two records are the same real-world activity.
    case sameActivity
    /// The two records must never share an activity.
    case keepSeparate
}

/// Who made a link.
public enum LinkMaker: String, Codable, Sendable, CaseIterable {
    case user
    /// The automatic match rule.
    case automatic
}

/// A "same activity" or "keep separate" link between two source records.
///
/// A link is a record of its own. Link records are only ever added, never
/// edited, so a change of mind is a new link on the same pair and
/// `inEffect(for:among:)` picks between them.
public struct LinkRecord: Hashable, Codable, Sendable {
    public let name: RecordName
    public let pair: IdentityPair
    public let kind: LinkKind
    public let maker: LinkMaker
    public let time: Date
    public let device: DeviceID

    /// A link with a name the caller chose. User-made links are individually
    /// named, so each user action is its own record.
    public init(
        name: RecordName,
        pair: IdentityPair,
        kind: LinkKind,
        maker: LinkMaker,
        time: Date,
        device: DeviceID
    ) {
        self.name = name
        self.pair = pair
        self.kind = kind
        self.maker = maker
        self.time = time
        self.device = device
    }

    /// The name of the automatic link of `kind` on `pair`.
    ///
    /// It is `link|<kind>|<lower>|<upper>`, where the kind is its raw value
    /// and the identities are in canonical form, for example
    /// `link|sameActivity|garmin:1|healthKit:W1`. It depends only on the pair
    /// and the kind, so two devices that make the same automatic merge write
    /// the same record.
    public static func automaticName(pair: IdentityPair, kind: LinkKind) -> RecordName {
        RecordName("link|\(kind.rawValue)|\(pair.lower)|\(pair.upper)")
    }

    /// An automatic link, named by `automaticName(pair:kind:)`.
    public static func automatic(
        pair: IdentityPair,
        kind: LinkKind = .sameActivity,
        time: Date,
        device: DeviceID
    ) -> LinkRecord {
        LinkRecord(
            name: automaticName(pair: pair, kind: kind),
            pair: pair,
            kind: kind,
            maker: .automatic,
            time: time,
            device: device
        )
    }

    /// The link in effect for `pair`, or nil when `links` holds none for it.
    /// Links on other pairs are ignored.
    ///
    /// When the pair has more than one link, the one in effect is chosen in
    /// this order:
    /// 1. A user-made link beats an automatic one.
    /// 2. The later time wins.
    /// 3. On equal times, "keep separate" beats "same activity".
    /// 4. Then the higher device ID wins, then the higher record name.
    ///
    /// The result does not depend on the order of `links`.
    public static func inEffect(
        for pair: IdentityPair,
        among links: some Sequence<LinkRecord>
    ) -> LinkRecord? {
        var winner: LinkRecord?
        for link in links where link.pair == pair {
            if let current = winner {
                if link.beats(current) {
                    winner = link
                }
            } else {
                winner = link
            }
        }
        return winner
    }

    /// The link in effect for every pair that has one.
    public static func inEffect(among links: some Sequence<LinkRecord>) -> [IdentityPair: LinkRecord] {
        var winners: [IdentityPair: LinkRecord] = [:]
        for link in links {
            if let current = winners[link.pair] {
                if link.beats(current) {
                    winners[link.pair] = link
                }
            } else {
                winners[link.pair] = link
            }
        }
        return winners
    }

    /// Whether this link is in effect over `other`, a link on the same pair.
    ///
    /// Two links that tie on every step hold the same pair, kind, maker,
    /// time, device and name, so they are the same record and neither beats
    /// the other.
    func beats(_ other: LinkRecord) -> Bool {
        if maker != other.maker {
            return maker == .user
        }
        if time != other.time {
            return time > other.time
        }
        if kind != other.kind {
            return kind == .keepSeparate
        }
        if device != other.device {
            return device > other.device
        }
        return name > other.name
    }
}
