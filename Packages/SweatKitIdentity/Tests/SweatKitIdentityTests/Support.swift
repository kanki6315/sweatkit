import Foundation
import SweatKitIdentity
import SweatKitModel

// The identities every test uses. In `SourceIdentity`'s order, which compares
// the source name and then the external ID as strings:
// file:f1 < garmin:1 < garmin:2 < healthKit:W1 < healthKit:W2.

let fi1 = SourceIdentity(source: .file, externalID: "f1")
let ga1 = SourceIdentity(source: .garmin, externalID: "1")
let ga2 = SourceIdentity(source: .garmin, externalID: "2")
let hk1 = SourceIdentity(source: .healthKit, externalID: "W1")
let hk2 = SourceIdentity(source: .healthKit, externalID: "W2")

/// A time `seconds` after the reference date.
func at(_ seconds: Double) -> Date {
    Date(timeIntervalSinceReferenceDate: seconds)
}

/// A user-made link with a hand-picked name.
func userLink(
    _ name: String,
    _ first: SourceIdentity,
    _ second: SourceIdentity,
    _ kind: LinkKind,
    time: Double = 0,
    device: String = "phone"
) -> LinkRecord {
    LinkRecord(
        name: RecordName(name),
        pair: IdentityPair(first, second),
        kind: kind,
        maker: .user,
        time: at(time),
        device: DeviceID(device)
    )
}

/// An automatic link. Its name is spelled out here by hand in the documented
/// form `link|<kind>|<lower>|<upper>`, so `lower` and `upper` must be given in
/// ascending order. It does not go through `LinkRecord.automatic`.
func autoLink(
    _ lower: SourceIdentity,
    _ upper: SourceIdentity,
    _ kind: LinkKind = .sameActivity,
    time: Double = 0,
    device: String = "phone"
) -> LinkRecord {
    LinkRecord(
        name: RecordName("link|\(kind.rawValue)|\(lower)|\(upper)"),
        pair: IdentityPair(lower, upper),
        kind: kind,
        maker: .automatic,
        time: at(time),
        device: DeviceID(device)
    )
}

/// A decision record.
func decision(
    _ name: String,
    _ value: DecisionValue,
    time: Double,
    device: String = "phone",
    on members: Set<SourceIdentity>,
    origin: DecisionOrigin = .direct
) -> DecisionRecord {
    DecisionRecord(
        name: RecordName(name),
        value: value,
        time: at(time),
        device: DeviceID(device),
        members: members,
        origin: origin
    )
}

/// An expected activity, with its ID stated by hand.
func group(id: SourceIdentity, _ members: SourceIdentity...) -> ActivityGroup {
    ActivityGroup(id: id, members: Set(members))
}

/// Every ordering of `items`. Use for up to five or six items.
func permutations<T>(_ items: [T]) -> [[T]] {
    guard items.count > 1 else { return [items] }
    var result: [[T]] = []
    for index in items.indices {
        var rest = items
        let head = rest.remove(at: index)
        for tail in permutations(rest) {
            result.append([head] + tail)
        }
    }
    return result
}

/// SplitMix64, so shuffles are the same on every run.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
