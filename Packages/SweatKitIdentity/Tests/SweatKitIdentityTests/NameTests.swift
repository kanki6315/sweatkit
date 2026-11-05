import SweatKitIdentity
import SweatKitModel
import Testing

@Suite("Record names, device IDs and pairs")
struct NameTests {
    @Test func aHigherRecordNameIsTheGreaterString() {
        // "b" comes after "a".
        #expect(RecordName("a") < RecordName("b"))
        #expect(!(RecordName("b") < RecordName("a")))
        #expect(!(RecordName("a") < RecordName("a")))
    }

    @Test func recordNamesAreOrderedAsStringsNotNumbers() {
        // The names first differ at "1" against "9", and "1" < "9", so
        // "link-10" is the lower name although 10 > 9.
        #expect(RecordName("link-10") < RecordName("link-9"))
    }

    @Test func aHigherDeviceIDIsTheGreaterString() {
        // "pad" and "phone" first differ at "a" against "h", and "a" < "h".
        #expect(DeviceID("pad") < DeviceID("phone"))
        #expect(!(DeviceID("phone") < DeviceID("pad")))
        #expect(!(DeviceID("pad") < DeviceID("pad")))
    }

    @Test func deviceIDsAreOrderedAsStringsNotNumbers() {
        // "device-10" against "device-9": "1" < "9".
        #expect(DeviceID("device-10") < DeviceID("device-9"))
    }

    @Test func aPairHasNoOrder() {
        #expect(IdentityPair(ga1, hk1) == IdentityPair(hk1, ga1))
        #expect(IdentityPair(ga1, hk1).hashValue == IdentityPair(hk1, ga1).hashValue)
    }

    @Test func aPairPutsTheLowerIdentityFirst() {
        // garmin:1 < healthKit:W1 because "garmin" < "healthKit".
        let pair = IdentityPair(hk1, ga1)
        #expect(pair.lower == ga1)
        #expect(pair.upper == hk1)
    }

    @Test func aPairOrdersGarminIDsAsStrings() {
        // "10" < "9" as strings, so garmin:10 is the lower identity.
        let ten = SourceIdentity(source: .garmin, externalID: "10")
        let nine = SourceIdentity(source: .garmin, externalID: "9")
        let pair = IdentityPair(nine, ten)
        #expect(pair.lower == ten)
        #expect(pair.upper == nine)
    }

    @Test func aPairContainsItsTwoIdentitiesOnly() {
        let pair = IdentityPair(ga1, hk1)
        #expect(pair.contains(ga1))
        #expect(pair.contains(hk1))
        #expect(!pair.contains(ga2))
    }

    @Test func differentPairsAreNotEqual() {
        #expect(IdentityPair(ga1, hk1) != IdentityPair(ga2, hk1))
        #expect(IdentityPair(ga1, hk1) != IdentityPair(ga1, hk2))
    }

    @Test func pairsAreOrderedByLowerThenUpper() {
        // Lower identities differ: garmin:1 < garmin:2.
        #expect(IdentityPair(ga1, hk2) < IdentityPair(ga2, hk1))
        // Lower identities equal, upper differ: garmin:2 < healthKit:W1.
        #expect(IdentityPair(ga1, ga2) < IdentityPair(ga1, hk1))
        #expect(!(IdentityPair(ga1, hk1) < IdentityPair(ga1, ga2)))
        #expect(!(IdentityPair(ga1, hk1) < IdentityPair(hk1, ga1)))
    }
}
