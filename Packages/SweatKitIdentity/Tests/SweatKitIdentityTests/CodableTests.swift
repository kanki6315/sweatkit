import Foundation
import SweatKitIdentity
import SweatKitModel
import Testing

/// Every record type is stored, so each must come back from its encoded
/// form as the same value.
@Suite("Encoding and decoding records")
struct CodableTests {
    private func roundTrip<Value: Codable>(_ value: Value) throws -> Value {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(Value.self, from: data)
    }

    @Test func namesAndDeviceIDsRoundTrip() throws {
        #expect(try roundTrip([RecordName("link|sameActivity|garmin:1|healthKit:W1")]) == [RecordName("link|sameActivity|garmin:1|healthKit:W1")])
        #expect(try roundTrip([DeviceID("phone")]) == [DeviceID("phone")])
    }

    @Test func aPairRoundTrips() throws {
        let pair = IdentityPair(hk1, ga1)
        #expect(try roundTrip(pair) == pair)
    }

    @Test func aPairStoredTheWrongWayRoundDecodesInOrder() throws {
        // The stored form names healthKit:W1 as the lower identity and
        // garmin:1 as the upper. garmin:1 < healthKit:W1, so the decoded
        // pair must put them right, or it would not equal the same pair
        // built in code.
        let json = """
        {
          "lower": { "source": "healthKit", "externalID": "W1" },
          "upper": { "source": "garmin", "externalID": "1" }
        }
        """
        let decoded = try JSONDecoder().decode(IdentityPair.self, from: Data(json.utf8))
        #expect(decoded.lower == ga1)
        #expect(decoded.upper == hk1)
        #expect(decoded == IdentityPair(ga1, hk1))
    }

    @Test func linksRoundTrip() throws {
        let links = [
            userLink("u1", ga1, hk1, .keepSeparate, time: 12.5, device: "pad"),
            autoLink(ga1, hk1, .sameActivity, time: 40, device: "phone"),
        ]
        #expect(try roundTrip(links) == links)
    }

    @Test func decisionsRoundTripWithEveryKindOfValue() throws {
        let decisions = [
            decision("t", .title("Morning loop"), time: 1, on: [ga1, hk1]),
            decision("h", .hidden(true), time: 2, device: "pad", on: [ga1]),
            decision("r", .hidden(false), time: 3, on: [ga1]),
            decision("p", .primary(hk1), time: 4, on: [ga1, hk1]),
            decision("t|copy|garmin:1", .title("Morning loop"), time: 1, on: [ga1], origin: .inheritedCopy),
        ]
        #expect(try roundTrip(decisions) == decisions)
    }

    @Test func tombstonesRoundTrip() throws {
        let tombstones = [
            Tombstone(identity: ga1, kind: .hidden, time: at(10)),
            Tombstone(identity: hk1, kind: .deleted, time: at(20)),
        ]
        #expect(try roundTrip(tombstones) == tombstones)
    }

    @Test func matchCandidatesAndScansRoundTrip() throws {
        let candidate = MatchCandidate(
            identity: hk1,
            sport: .hiking,
            start: at(30),
            elapsed: 3590,
            distance: nil,
            isIndoor: true,
            linkedIdentities: [ga1]
        )
        #expect(try roundTrip(candidate) == candidate)

        let scan = MatchScan(
            links: [autoLink(ga1, hk1, time: 400)],
            possibleDuplicates: [IdentityPair(fi1, ga1)]
        )
        #expect(try roundTrip(scan) == scan)
        #expect(try roundTrip(MatchTolerances.standard) == MatchTolerances.standard)
        #expect(try roundTrip([MatchOutcome.sameActivity(.sourceIdentifier), .possibleDuplicate, .unrelated])
            == [.sameActivity(.sourceIdentifier), .possibleDuplicate, .unrelated])
    }

    @Test func aResolvedLibraryRoundTrips() throws {
        let library = ResolvedLibrary(
            activities: [
                ResolvedActivity(id: ga1, members: [ga1, hk1], title: "Morning loop", isHidden: true, primary: hk1),
                ResolvedActivity(id: ga2, members: [ga2], title: nil, isHidden: false, primary: ga2),
            ],
            possibleDuplicates: [autoLink(ga2, hk1, time: 400)]
        )
        #expect(try roundTrip(library) == library)

        let formation = ActivityFormation(
            activities: [group(id: ga1, ga1, hk1)],
            skippedLinks: [autoLink(ga2, hk1)]
        )
        #expect(try roundTrip(formation) == formation)
        let offer = AlternativeOffer(identity: hk1, channels: [.heartRate, .cadence])
        #expect(try roundTrip(offer) == offer)
    }
}
