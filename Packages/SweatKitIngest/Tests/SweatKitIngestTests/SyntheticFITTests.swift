import FITSwiftSDK
import Foundation
import Testing

/// Checks `SyntheticFIT` with the SDK alone, so the mapping tests can trust
/// what their files hold. Nothing here touches the decoder under test.
@Suite struct SyntheticFITTests {
    private func read(_ messages: [Mesg]) throws -> FitMessages {
        let data = try SyntheticFIT.file(messages)
        #expect(try Decoder(stream: FITSwiftSDK.InputStream(data: data)).checkIntegrity())
        let decoder = Decoder(stream: FITSwiftSDK.InputStream(data: data))
        let listener = FitListener()
        decoder.addMesgListener(listener)
        try decoder.read()
        return listener.fitMessages
    }

    @Test func dateMatchesTheSDKsOwnConversion() {
        #expect(SyntheticFIT.time(0).date == SyntheticFIT.date(0))
        #expect(SyntheticFIT.time(90).date == SyntheticFIT.date(90))
    }

    @Test func sessionValuesSurviveFixedPointStorage() throws {
        let session = try SyntheticFIT.session(elapsed: 3723.5, timer: 3600.25, distance: 40123.5, ascent: 512)
        let read = try #require(try read([session]).sessionMesgs.first)
        #expect(read.getStartTime() == SyntheticFIT.time(0))
        #expect(read.getTotalElapsedTime() == 3723.5)
        #expect(read.getTotalTimerTime() == 3600.25)
        #expect(read.getTotalDistance() == 40123.5)
        #expect(read.getTotalAscent() == 512)
    }

    @Test func recordValuesSurviveFixedPointStorage() throws {
        let record = try SyntheticFIT.record(0) {
            try $0.setPositionLat(596_523_236)
            try $0.setPositionLong(-5_965_232)
            try $0.setDistance(1234.5)
            try $0.setHeartRate(142)
            try $0.setPower(0)
            try $0.setCadence(88)
            try $0.setTemperature(-3)
        }
        let read = try #require(try read([record]).recordMesgs.first)
        #expect(read.getPositionLat() == 596_523_236)
        #expect(read.getPositionLong() == -5_965_232)
        #expect(read.getDistance() == 1234.5)
        #expect(read.getHeartRate() == 142)
        #expect(read.getPower() == 0)
        #expect(read.getCadence() == 88)
        #expect(read.getTemperature() == -3)
        #expect(read.getEnhancedSpeed() == nil)
        #expect(read.getEnhancedAltitude() == nil)
    }

    /// The premise of the enhanced-field tests: the file can hold a plain and
    /// an enhanced value that disagree, and the SDK reports both.
    @Test func plainAndEnhancedFieldsAreStoredSeparately() throws {
        let record = try SyntheticFIT.record(0) {
            try $0.setSpeed(5)
            try $0.setEnhancedSpeed(20)
            try $0.setAltitude(100)
            try $0.setEnhancedAltitude(250)
        }
        let read = try #require(try read([record]).recordMesgs.first)
        #expect(read.getSpeed() == 5)
        #expect(read.getEnhancedSpeed() == 20)
        #expect(read.getAltitude() == 100)
        #expect(read.getEnhancedAltitude() == 250)
    }

    @Test func lapAndEventAndLocalTimestampAreWritten() throws {
        let activity = ActivityMesg()
        try activity.setTimestamp(SyntheticFIT.time(600))
        try activity.setLocalTimestamp(SyntheticFIT.base + 600 + 7200)
        let messages = try read([
            try SyntheticFIT.event(.timer, .stopDisableAll, at: 45),
            try SyntheticFIT.lap(start: 601, elapsed: 600.5),
            activity,
        ])
        #expect(messages.eventMesgs.first?.getEvent() == .timer)
        #expect(messages.eventMesgs.first?.getEventType() == .stopDisableAll)
        #expect(messages.eventMesgs.first?.getTimestamp() == SyntheticFIT.time(45))
        #expect(messages.lapMesgs.first?.getStartTime() == SyntheticFIT.time(601))
        #expect(messages.lapMesgs.first?.getTotalElapsedTime() == 600.5)
        #expect(messages.activityMesgs.first?.getLocalTimestamp() == SyntheticFIT.base + 600 + 7200)
        #expect(messages.sessionMesgs.isEmpty)
    }
}
