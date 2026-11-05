import FITSwiftSDK
import Foundation
import SweatKitIngest
import SweatKitModel
import Testing

/// How a FIT file's messages map onto `RecordedActivity`, one rule at a time,
/// on files written by `SyntheticFIT`. The real fixtures are in
/// `FixtureActivityTests`.
@Suite struct FITDecodeMappingTests {
    private func decode(_ messages: [Mesg]) throws -> RecordedActivity {
        try FITActivityDecoder.decode(try SyntheticFIT.file(messages))
    }

    // MARK: Sport and flags

    @Test(arguments: zip(
        [FITSwiftSDK.Sport.cycling, .walking, .running, .hiking, .swimming, .generic],
        [SweatKitModel.Sport.cycling, .walking, .running, .hiking, .other, .other]
    ))
    func sportMapsToTheModelSport(_ fit: FITSwiftSDK.Sport, _ expected: SweatKitModel.Sport) throws {
        let activity = try decode([try SyntheticFIT.session(sport: fit)])
        #expect(activity.sport == expected)
    }

    @Test func sessionWithNoSportIsOther() throws {
        let activity = try decode([try SyntheticFIT.session(sport: nil, subSport: nil)])
        #expect(activity.sport == .other)
        #expect(!activity.isIndoor)
        #expect(!activity.isVirtual)
    }

    /// Reading: a virtual ride is ridden indoors, so the virtual-activity
    /// sub-sport sets the indoor flag as well as the virtual one.
    @Test func virtualActivitySubSportSetsVirtualAndIndoor() throws {
        let activity = try decode([try SyntheticFIT.session(subSport: .virtualActivity)])
        #expect(activity.isVirtual)
        #expect(activity.isIndoor)
    }

    /// Reading: the spec does not say what marks a file as indoor. The
    /// sub-sports the FIT profile names as indoor are taken.
    @Test(arguments: [SubSport.indoorCycling, .spin, .treadmill, .indoorWalking, .indoorRunning])
    func indoorSubSportSetsIndoorButNotVirtual(_ subSport: SubSport) throws {
        let activity = try decode([try SyntheticFIT.session(subSport: subSport)])
        #expect(activity.isIndoor)
        #expect(!activity.isVirtual)
    }

    @Test(arguments: [SubSport.generic, .road, .mountain, .gravelCycling, .trail])
    func outdoorSubSportSetsNeitherFlag(_ subSport: SubSport) throws {
        let activity = try decode([try SyntheticFIT.session(subSport: subSport)])
        #expect(!activity.isIndoor)
        #expect(!activity.isVirtual)
    }

    // MARK: Stated summary

    @Test func statedSummaryComesFromTheSessionMessage() throws {
        let session = try SyntheticFIT.session(elapsed: 3723.5, timer: 3600.25, distance: 40123.5, ascent: 512)
        let stated = try decode([session]).stated
        #expect(stated.start == SyntheticFIT.date(0))
        // The end is the start plus total elapsed time.
        #expect(stated.end == SyntheticFIT.date(3723.5))
        #expect(stated.timerTime == 3600.25)
        #expect(stated.distance == 40123.5)
        #expect(stated.ascent == 512)
    }

    @Test func fieldsTheSessionDoesNotHoldStayNil() throws {
        let session = try SyntheticFIT.session(elapsed: nil, timer: nil)
        let stated = try decode([session]).stated
        #expect(stated.start == SyntheticFIT.date(0))
        // No total elapsed time, so no stated end.
        #expect(stated.end == nil)
        #expect(stated.timerTime == nil)
        #expect(stated.distance == nil)
        #expect(stated.ascent == nil)
        // No activity message, so no offset.
        #expect(stated.utcOffset == nil)
    }

    @Test func sessionWithNoStartTimeStatesNeitherStartNorEnd() throws {
        let stated = try decode([try SyntheticFIT.session(hasStartTime: false)]).stated
        #expect(stated.start == nil)
        #expect(stated.end == nil)
        #expect(stated.timerTime == 600)
    }

    /// Reading: the session message has no time zone, so the offset is read
    /// from the activity message: local timestamp minus timestamp.
    @Test(arguments: [7200, -14400])
    func utcOffsetIsLocalTimestampMinusTimestamp(_ offset: Int) throws {
        let activity = ActivityMesg()
        try activity.setTimestamp(SyntheticFIT.time(600))
        // The local timestamp is the same instant on the local clock.
        try activity.setLocalTimestamp(UInt32(Int(SyntheticFIT.base) + 600 + offset))
        let stated = try decode([try SyntheticFIT.session(), activity]).stated
        #expect(stated.utcOffset == offset)
    }

    /// Zwift writes a local timestamp of 0, which is not a date: the FIT
    /// profile's smallest absolute date-time is 0x10000000.
    @Test func localTimestampThatIsNotADateGivesNoOffset() throws {
        let activity = ActivityMesg()
        try activity.setTimestamp(SyntheticFIT.time(600))
        try activity.setLocalTimestamp(0)
        let stated = try decode([try SyntheticFIT.session(), activity]).stated
        #expect(stated.utcOffset == nil)
    }

    // MARK: Timer events

    @Test func timerEventsAreTheTimerStartsAndStopsInFileOrder() throws {
        let activity = try decode([
            try SyntheticFIT.event(.timer, .start, at: 0),
            try SyntheticFIT.event(.rearGearChange, .marker, at: 30),
            try SyntheticFIT.event(.timer, .stopAll, at: 60),
            // A stop, but of the session event, not the timer.
            try SyntheticFIT.event(.session, .stop, at: 70),
            try SyntheticFIT.event(.timer, .start, at: 90),
            // A timer event that is neither a start nor a stop.
            try SyntheticFIT.event(.timer, .marker, at: 100),
            try SyntheticFIT.event(.timer, .stop, at: 120),
            try SyntheticFIT.session(),
        ])
        #expect(activity.timerEvents == [
            TimerEvent(kind: .start, timestamp: SyntheticFIT.date(0)),
            TimerEvent(kind: .stop, timestamp: SyntheticFIT.date(60)),
            TimerEvent(kind: .start, timestamp: SyntheticFIT.date(90)),
            TimerEvent(kind: .stop, timestamp: SyntheticFIT.date(120)),
        ])
    }

    @Test(arguments: [EventType.stop, .stopAll, .stopDisable, .stopDisableAll])
    func everyKindOfTimerStopIsAStop(_ type: EventType) throws {
        let activity = try decode([try SyntheticFIT.event(.timer, type, at: 45), try SyntheticFIT.session()])
        #expect(activity.timerEvents == [TimerEvent(kind: .stop, timestamp: SyntheticFIT.date(45))])
    }

    @Test func fileWithNoTimerEventsHasNone() throws {
        let activity = try decode([try SyntheticFIT.record(0), try SyntheticFIT.session()])
        #expect(activity.timerEvents.isEmpty)
    }

    // MARK: Laps

    @Test func lapsRunFromStartTimeForTheirElapsedTime() throws {
        let activity = try decode([
            try SyntheticFIT.lap(start: 0, elapsed: 600.5),
            try SyntheticFIT.lap(start: 601, elapsed: 300),
            try SyntheticFIT.session(),
        ])
        #expect(activity.laps == [
            // 0 + 600.5 = 600.5.
            RecordedLap(start: SyntheticFIT.date(0), end: SyntheticFIT.date(600.5)),
            // 601 + 300 = 901.
            RecordedLap(start: SyntheticFIT.date(601), end: SyntheticFIT.date(901)),
        ])
    }

    // MARK: Records

    @Test func everyRecordBecomesASampleInFileOrder() throws {
        let activity = try decode([
            try SyntheticFIT.record(0) { try $0.setHeartRate(100) },
            try SyntheticFIT.record(1) { try $0.setHeartRate(101) },
            try SyntheticFIT.record(5) { try $0.setHeartRate(105) },
            try SyntheticFIT.session(),
        ])
        #expect(activity.stream.samples.map(\.timestamp) == [0, 1, 5].map { SyntheticFIT.date($0) })
        #expect(activity.stream.samples.map(\.heartRate) == [100, 101, 105])
    }

    @Test func positionIsConvertedFromSemicirclesToDegrees() throws {
        let activity = try decode([
            // 2^30 semicircles x 180 / 2^31 = 90 degrees.
            // -2^29 semicircles x 180 / 2^31 = -45 degrees.
            try SyntheticFIT.record(0) {
                try $0.setPositionLat(1_073_741_824)
                try $0.setPositionLong(-536_870_912)
            },
            // 50 degrees is 50 x 2^31 / 180 = 596,523,235.6 semicircles, and
            // -0.5 degrees is -5,965,232.4. Stored as whole semicircles they
            // are within 0.0000001 degrees of that.
            try SyntheticFIT.record(1) {
                try $0.setPositionLat(596_523_236)
                try $0.setPositionLong(-5_965_232)
            },
            try SyntheticFIT.session(),
        ])
        let samples = activity.stream.samples
        #expect(samples.count == 2)
        #expect(samples.first?.position == Coordinate(latitude: 90, longitude: -45))
        #expect(isClose(samples.last?.position?.latitude, 50, tolerance: 1e-6))
        #expect(isClose(samples.last?.position?.longitude, -0.5, tolerance: 1e-6))
    }

    @Test func positionNeedsBothLatitudeAndLongitude() throws {
        let activity = try decode([
            try SyntheticFIT.record(0) { try $0.setPositionLat(1_073_741_824) },
            try SyntheticFIT.record(1) { try $0.setPositionLong(1_073_741_824) },
            try SyntheticFIT.session(),
        ])
        #expect(activity.stream.samples.map(\.position) == [nil, nil])
    }

    @Test func plainSpeedAndAltitudeAreReadWhenThereIsNoEnhancedField() throws {
        let activity = try decode([
            try SyntheticFIT.record(0) {
                try $0.setSpeed(7.5)
                try $0.setAltitude(100)
            },
            try SyntheticFIT.session(),
        ])
        #expect(activity.stream.samples.first?.speed == 7.5)
        #expect(isClose(activity.stream.samples.first?.altitude, 100, tolerance: 1e-6))
    }

    @Test func enhancedSpeedAndAltitudeAreReadWhenTheyAreTheOnlyFields() throws {
        // What Garmin devices write: no plain speed or altitude at all.
        let activity = try decode([
            try SyntheticFIT.record(0) {
                try $0.setEnhancedSpeed(12.5)
                try $0.setEnhancedAltitude(1234)
            },
            try SyntheticFIT.session(),
        ])
        #expect(activity.stream.samples.first?.speed == 12.5)
        #expect(isClose(activity.stream.samples.first?.altitude, 1234, tolerance: 1e-6))
    }

    @Test func enhancedSpeedAndAltitudeArePreferredOverThePlainFields() throws {
        // Both fields present and disagreeing, so the value says which was read.
        let activity = try decode([
            try SyntheticFIT.record(0) {
                try $0.setSpeed(5)
                try $0.setEnhancedSpeed(20)
                try $0.setAltitude(100)
                try $0.setEnhancedAltitude(250)
            },
            try SyntheticFIT.session(),
        ])
        #expect(activity.stream.samples.first?.speed == 20)
        #expect(isClose(activity.stream.samples.first?.altitude, 250, tolerance: 1e-6))
    }

    @Test func sensorChannelsAreReadAsRecorded() throws {
        let activity = try decode([
            try SyntheticFIT.record(0) {
                try $0.setDistance(1234.5)
                try $0.setHeartRate(142)
                try $0.setPower(250)
                try $0.setCadence(88)
                try $0.setTemperature(-3)
            },
            try SyntheticFIT.session(),
        ])
        let sample = try #require(activity.stream.samples.first)
        #expect(sample.timestamp == SyntheticFIT.date(0))
        #expect(sample.distance == 1234.5)
        #expect(sample.heartRate == 142)
        #expect(sample.power == 250)
        #expect(sample.cadence == 88)
        #expect(sample.temperature == -3)
    }

    /// "Cadence: steps per minute on foot." A FIT file counts the strides of
    /// one foot, so on foot the recorded figure is doubled.
    @Test(arguments: [FITSwiftSDK.Sport.walking, .running, .hiking])
    func onFootCadenceIsStepsPerMinute(_ sport: FITSwiftSDK.Sport) throws {
        let activity = try decode([
            // 54 strides of one foot a minute: 54 x 2 = 108 steps a minute.
            try SyntheticFIT.record(0) { try $0.setCadence(54) },
            // With half a stride more: (54 + 0.5) x 2 = 109.
            try SyntheticFIT.record(1) {
                try $0.setCadence(54)
                try $0.setFractionalCadence(0.5)
            },
            // Standing still: 0 x 2 = 0, a recorded zero.
            try SyntheticFIT.record(2) { try $0.setCadence(0) },
            // No cadence field: nil, not zero.
            try SyntheticFIT.record(3) { try $0.setHeartRate(100) },
            try SyntheticFIT.session(sport: sport),
        ])
        #expect(activity.stream.samples.map(\.cadence) == [108, 109, 0, nil])
    }

    @Test func cyclingCadenceIsRevolutionsPerMinute() throws {
        let activity = try decode([
            // Not doubled on a bike: 88.
            try SyntheticFIT.record(0) { try $0.setCadence(88) },
            // The fractional part is added: 88 + 0.5 = 88.5.
            try SyntheticFIT.record(1) {
                try $0.setCadence(88)
                try $0.setFractionalCadence(0.5)
            },
            try SyntheticFIT.session(sport: .cycling),
        ])
        #expect(activity.stream.samples.map(\.cadence) == [88, 88.5])
    }

    @Test func cadenceOfAnotherSportIsLeftAsRecorded() throws {
        // Only walking, running and hiking count steps. Rowing maps to
        // `.other`, and its 30 strokes a minute stay 30.
        let activity = try decode([
            try SyntheticFIT.record(0) { try $0.setCadence(30) },
            try SyntheticFIT.session(sport: .rowing),
        ])
        #expect(activity.stream.samples.first?.cadence == 30)
    }

    /// Missing is never zero, from the first step: a field the record does
    /// not hold is nil, and a recorded zero is 0.
    @Test func recordedZeroIsZeroAndAnAbsentFieldIsNil() throws {
        let activity = try decode([
            try SyntheticFIT.record(0) {
                try $0.setPower(0)
                try $0.setCadence(0)
                try $0.setSpeed(0)
                try $0.setDistance(0)
            },
            try SyntheticFIT.record(1),
            try SyntheticFIT.session(),
        ])
        let samples = activity.stream.samples
        #expect(samples.count == 2)
        let coasting = try #require(samples.first)
        #expect(coasting.power == 0)
        #expect(coasting.cadence == 0)
        #expect(coasting.speed == 0)
        #expect(coasting.distance == 0)
        // The second record holds a timestamp and nothing else.
        #expect(samples.last == NativeSample(timestamp: SyntheticFIT.date(1)))
    }

    // MARK: Not an activity

    @Test func soundFileWithNoSessionIsNotAnActivity() throws {
        let data = try SyntheticFIT.file([try SyntheticFIT.record(0) { try $0.setHeartRate(100) }])
        #expect(throws: FITDecodeError.noActivity) { try FITActivityDecoder.decode(data) }
    }
}
