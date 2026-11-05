import FITSwiftSDK
import Foundation
import SweatKitTestSupport
import Testing

/// Confirms the Garmin SDK reads every shared fixture, and pins what each one
/// holds so later tests can rely on it. `Fixtures/README.md` lists the same facts.
@Suite struct FixtureDecodeTests {
    struct Expected: Sendable {
        var fixture: Fixtures.FIT
        var sport: FITSwiftSDK.Sport
        var subSport: SubSport
        var records: Int
        var recordsWithPosition: Int
        var recordsWithPower: Int
        var events: Int
        var laps: Int
    }

    static let expected = [
        Expected(fixture: .outdoorRide, sport: .cycling, subSport: .road, records: 5347, recordsWithPosition: 5347, recordsWithPower: 5337, events: 326, laps: 8),
        Expected(fixture: .zwiftRide, sport: .cycling, subSport: .virtualActivity, records: 2409, recordsWithPosition: 2409, recordsWithPower: 2409, events: 2, laps: 1),
        Expected(fixture: .walk, sport: .walking, subSport: .generic, records: 2492, recordsWithPosition: 2492, recordsWithPower: 0, events: 4, laps: 4),
        Expected(fixture: .walkPitlane, sport: .walking, subSport: .generic, records: 27039, recordsWithPosition: 26908, recordsWithPower: 0, events: 16, laps: 18),
    ]

    @Test(arguments: expected)
    func fixtureDecodes(_ expected: Expected) throws {
        let data = try expected.fixture.data()
        #expect(try Decoder(stream: FITSwiftSDK.InputStream(data: data)).checkIntegrity())

        let decoder = Decoder(stream: FITSwiftSDK.InputStream(data: data))
        let listener = FitListener()
        decoder.addMesgListener(listener)
        try decoder.read()
        let messages = listener.fitMessages

        let session = try #require(messages.sessionMesgs.first)
        #expect(messages.sessionMesgs.count == 1)
        #expect(session.getSport() == expected.sport)
        #expect(session.getSubSport() == expected.subSport)

        let records = messages.recordMesgs
        #expect(records.count == expected.records)
        #expect(records.allSatisfy { $0.getTimestamp() != nil })
        #expect(records.count { $0.getPositionLat() != nil } == expected.recordsWithPosition)
        #expect(records.count { $0.getPower() != nil } == expected.recordsWithPower)
        #expect(records.count { $0.getHeartRate() != nil } == expected.records)
        #expect(messages.eventMesgs.count == expected.events)
        #expect(messages.lapMesgs.count == expected.laps)
    }

    @Test func everyFixtureIsPinned() {
        #expect(Set(Self.expected.map(\.fixture)) == Set(Fixtures.FIT.allCases))
    }
}
