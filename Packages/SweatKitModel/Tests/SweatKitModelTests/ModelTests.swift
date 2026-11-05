import Foundation
import SweatKitModel
import SweatKitTestSupport
import Testing

@Suite struct SourceIdentityTests {
    @Test func ordersBySourceThenExternalID() {
        let garmin = SourceIdentity(source: .garmin, externalID: "2")
        let health = SourceIdentity(source: .healthKit, externalID: "1")
        let file = SourceIdentity(source: .file, externalID: "9")
        #expect([health, garmin, file].sorted() == [file, garmin, health])
        #expect(SourceIdentity(source: .garmin, externalID: "1") < garmin)
    }

    @Test func identicalFilesShareAnIdentity() {
        let bytes = Data("same bytes".utf8)
        #expect(SourceIdentity(fileContents: bytes) == SourceIdentity(fileContents: bytes))
        #expect(SourceIdentity(fileContents: bytes) != SourceIdentity(fileContents: Data("other".utf8)))
    }

    @Test func hashIsSHA256() {
        #expect(
            ContentHash(of: Data("abc".utf8)).hex
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }
}

@Suite struct SeriesTests {
    @Test func missingIsNotZero() {
        let series = Series([0, nil, 250])
        #expect(series[0] == 0)
        #expect(series[1] == nil)
        #expect(series[2] == 250)
        #expect(series.quality == [.measured, .missing, .measured])
    }

    @Test func valuesUnderMissingSecondsDoNotAffectEquality() {
        let a = Series(values: [1, 99], quality: [.measured, .missing])
        let b = Series(values: [1, -5], quality: [.measured, .missing])
        #expect(a == b)
    }
}

@Suite struct AnalysisStreamTests {
    @Test func startsWithEveryChannelMissing() {
        let stream = AnalysisStream(rulesVersion: 1, start: .now, count: 10)
        #expect(stream.isConsistent)
        #expect(Channel.allCases.allSatisfy { stream[$0].quality.allSatisfy { $0 == .missing } })
        #expect(stream.coordinate(at: 0) == nil)
    }

    @Test func channelSubscriptReadsAndWrites() {
        var stream = AnalysisStream(rulesVersion: 1, start: .now, count: 2)
        stream[.power] = Series([200, 210])
        #expect(stream.power[1] == 210)
        stream.latitude = Series([51.44, nil])
        stream.longitude = Series([-0.27, nil])
        #expect(stream.coordinate(at: 0) == Coordinate(latitude: 51.44, longitude: -0.27))
        #expect(stream.coordinate(at: 1) == nil)
    }

    @Test func survivesCoding() throws {
        var stream = AnalysisStream(rulesVersion: 1, start: Date(timeIntervalSince1970: 0), count: 3, pauses: .known(paused: [1..<2]))
        stream.heartRate = Series(values: [140, 141, 0], quality: [.measured, .interpolated, .missing])
        let decoded = try JSONDecoder().decode(AnalysisStream.self, from: JSONEncoder().encode(stream))
        #expect(decoded == stream)
    }
}

@Suite struct AthleteProfileTests {
    private func day(_ offset: Double) -> Date {
        Date(timeIntervalSince1970: offset * 86_400)
    }

    @Test func thresholdPowerIsDateEffective() {
        let profile = AthleteProfile(thresholdPowerHistory: [
            .init(effectiveFrom: day(200), watts: 260),
            .init(effectiveFrom: day(100), watts: 240),
        ])
        #expect(profile.thresholdPower(on: day(50)) == nil)
        #expect(profile.thresholdPower(on: day(100)) == 240)
        #expect(profile.thresholdPower(on: day(199)) == 240)
        #expect(profile.thresholdPower(on: day(300)) == 260)
    }

    @Test func thresholdHeartRateDefaultsTo90PercentOfMax() {
        var profile = AthleteProfile(maxHeartRate: 190)
        #expect(profile.thresholdHeartRate == 171)
        profile.statedThresholdHeartRate = 165
        #expect(profile.thresholdHeartRate == 165)
        #expect(AthleteProfile().thresholdHeartRate == nil)
    }
}

@Suite struct ProfileFingerprintTests {
    private func day(_ offset: Double) -> Date {
        Date(timeIntervalSince1970: offset * 86_400)
    }

    private var base: AthleteProfile {
        AthleteProfile(
            thresholdPowerHistory: [
                .init(effectiveFrom: day(100), watts: 240),
                .init(effectiveFrom: day(200), watts: 260),
            ],
            maxHeartRate: 190
        )
    }

    @Test func equalValuesGiveEqualFingerprints() {
        #expect(base.fingerprint(on: day(150)) == base.fingerprint(on: day(199)))
        #expect(base.fingerprint(on: day(150)) != base.fingerprint(on: day(250)))
    }

    @Test func correctingOneRangeLeavesOtherDatesAlone() {
        var corrected = base
        corrected.thresholdPowerHistory[0].watts = 250
        #expect(corrected.fingerprint(on: day(150)) != base.fingerprint(on: day(150)))
        #expect(corrected.fingerprint(on: day(250)) == base.fingerprint(on: day(250)))
        #expect(corrected.fingerprint(on: day(50)) == base.fingerprint(on: day(50)))
    }

    @Test func weightAndUnitsAreNotRead() {
        var changed = base
        changed.weight = 72
        changed.units = .imperial
        #expect(changed.fingerprint(on: day(150)) == base.fingerprint(on: day(150)))
    }

    @Test func onlyTheReadValuesCount() {
        var changed = base
        changed.maxHeartRate = 185
        #expect(changed.fingerprint(on: day(150), reading: .thresholdPower) == base.fingerprint(on: day(150), reading: .thresholdPower))
        #expect(changed.fingerprint(on: day(150), reading: .maxHeartRate) != base.fingerprint(on: day(150), reading: .maxHeartRate))
        // Threshold heart rate defaults to 90% of max, so it moves with max.
        #expect(changed.fingerprint(on: day(150), reading: .thresholdHeartRate) != base.fingerprint(on: day(150), reading: .thresholdHeartRate))
    }

    @Test func aMissingValueDiffersFromAnySetOne() {
        let empty = AthleteProfile()
        #expect(empty.fingerprint(on: day(50)) != base.fingerprint(on: day(150)))
        #expect(empty.fingerprint(on: day(50)) == AthleteProfile().fingerprint(on: day(300)))
    }

    @Test func provenanceRecordsTheFingerprint() {
        let provenance = Provenance(
            inputRevision: ContentHash(of: Data("input".utf8)),
            profileFingerprint: base.fingerprint(on: day(150)),
            algorithmVersion: 1
        )
        #expect(provenance.profileFingerprint == base.fingerprint(on: day(120)))
        #expect(Provenance(inputRevision: provenance.inputRevision, algorithmVersion: 1).profileFingerprint == nil)
    }
}

@Suite struct FixtureTests {
    @Test(arguments: Fixtures.FIT.allCases)
    func fitFixtureIsPresent(_ fixture: Fixtures.FIT) throws {
        let data = try fixture.data()
        // Bytes 8 to 11 of a FIT header spell ".FIT".
        #expect(String(decoding: data[8..<12], as: UTF8.self) == ".FIT")
    }
}
