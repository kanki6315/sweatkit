import FITSwiftSDK
import Foundation
import SweatKitIngest
import SweatKitModel
import SweatKitTestSupport
import Testing

/// Decoder cases the first round of tests left open. Each expected value
/// comes from `FITActivityDecoder.decode`'s doc comment or from
/// `FITDecodeError`'s, worked out before the implementation was run.
@Suite struct FITDecodeEdgeTests {
    private func decode(_ messages: [Mesg]) throws -> RecordedActivity {
        try FITActivityDecoder.decode(try SyntheticFIT.file(messages))
    }

    // MARK: Session

    /// "The first session message describes the activity."
    @Test func firstSessionDescribesTheActivity() throws {
        let activity = try decode([
            try SyntheticFIT.session(sport: .cycling, elapsed: 600, timer: 590),
            try SyntheticFIT.session(sport: .running, subSport: .treadmill, elapsed: 300, timer: 280),
        ])
        #expect(activity.sport == .cycling)
        #expect(!activity.isIndoor)
        // 0 + 600 = 600, from the first session.
        #expect(activity.stated.end == SyntheticFIT.date(600))
        #expect(activity.stated.timerTime == 590)
    }

    /// "Every other sport ... is `.other`", e-biking included: it is a FIT
    /// sport of its own, not a kind of cycling.
    @Test func eBikingIsOther() throws {
        #expect(try decode([try SyntheticFIT.session(sport: .eBiking)]).sport == .other)
    }

    /// The indoor sub-sports the first round did not try.
    @Test(arguments: [
        SubSport.indoorRowing, .indoorSkiing, .indoorClimbing, .indoorGrinding,
        .indoorWheelchairWalk, .indoorWheelchairRun, .indoorHandCycling,
    ])
    func everyIndoorSubSportSetsIndoor(_ subSport: SubSport) throws {
        let activity = try decode([try SyntheticFIT.session(subSport: subSport)])
        #expect(activity.isIndoor)
        #expect(!activity.isVirtual)
    }

    /// "It is nil ... when either value is below the smallest absolute
    /// date-time." An activity message with no local timestamp has no local
    /// time to take the offset from.
    @Test func activityMessageWithNoLocalTimestampGivesNoOffset() throws {
        let activity = ActivityMesg()
        try activity.setTimestamp(SyntheticFIT.time(600))
        #expect(try decode([try SyntheticFIT.session(), activity]).stated.utcOffset == nil)
    }

    // MARK: Messages that cannot be placed

    @Test func recordWithNoTimestampIsLeftOut() throws {
        let unplaced = RecordMesg()
        try unplaced.setHeartRate(101)
        let activity = try decode([
            try SyntheticFIT.record(0) { try $0.setHeartRate(100) },
            unplaced,
            try SyntheticFIT.record(2) { try $0.setHeartRate(102) },
            try SyntheticFIT.session(),
        ])
        #expect(activity.stream.samples.map(\.timestamp) == [0, 2].map { SyntheticFIT.date($0) })
        #expect(activity.stream.samples.map(\.heartRate) == [100, 102])
    }

    @Test func timerEventWithNoTimestampIsLeftOut() throws {
        let unplaced = EventMesg()
        try unplaced.setEvent(.timer)
        try unplaced.setEventType(.stopAll)
        let activity = try decode([
            try SyntheticFIT.event(.timer, .start, at: 0),
            unplaced,
            try SyntheticFIT.session(),
        ])
        #expect(activity.timerEvents == [TimerEvent(kind: .start, timestamp: SyntheticFIT.date(0))])
    }

    @Test func lapWithNoStartTimeOrNoElapsedTimeIsLeftOut() throws {
        let noStart = LapMesg()
        try noStart.setTotalElapsedTime(300)
        let activity = try decode([
            try SyntheticFIT.lap(start: 0, elapsed: 300),
            try SyntheticFIT.lap(start: 300, elapsed: nil),
            noStart,
            try SyntheticFIT.session(),
        ])
        // Only the first lap has both: 0 + 300 = 300.
        #expect(activity.laps == [RecordedLap(start: SyntheticFIT.date(0), end: SyntheticFIT.date(300))])
    }

    // MARK: The bytes handed over

    /// A slice of a larger `Data` keeps its parent's indices. The same bytes
    /// must decode the same wherever the slice starts.
    @Test func sliceWithShiftedIndicesDecodesLikeAFreshCopy() throws {
        let data = try Fixtures.FIT.walk.data()
        let padded = Data([0, 0, 0]) + data + Data([0, 0])
        let slice = padded[3..<(3 + data.count)]
        #expect(slice.startIndex == 3)
        #expect(try FITActivityDecoder.decode(slice) == FITActivityDecoder.decode(data))
    }

    /// "The file is shorter than its own header says." Raising the stated
    /// data size by one byte leaves the file one byte short of it.
    @Test func headerStatingMoreDataThanTheFileHoldsIsTruncated() throws {
        var data = try Fixtures.FIT.walk.data()
        data.replaceSubrange(4..<8, with: littleEndian(statedDataSize(data) + 1))
        #expect(throws: FITDecodeError.truncated) { try FITActivityDecoder.decode(data) }
    }

    /// Lowering the stated data size by one byte leaves the file long enough,
    /// so it is not truncated, but the header no longer matches its own
    /// checksum and the file's checksum is no longer where the header says.
    @Test func headerStatingLessDataThanTheFileHoldsIsCorrupt() throws {
        var data = try Fixtures.FIT.walk.data()
        data.replaceSubrange(4..<8, with: littleEndian(statedDataSize(data) - 1))
        #expect(throws: FITDecodeError.corrupt) { try FITActivityDecoder.decode(data) }
    }

    /// Reading: bytes after a sound file that are not another FIT file make
    /// the whole thing unreadable. The spec does not cover this.
    @Test func bytesAfterASoundFileAreCorrupt() throws {
        let data = try SyntheticFIT.file([try SyntheticFIT.session()])
        #expect(throws: Never.self) { try FITActivityDecoder.decode(data) }
        #expect(throws: FITDecodeError.corrupt) { try FITActivityDecoder.decode(data + Data([0])) }
        #expect(throws: FITDecodeError.corrupt) {
            try FITActivityDecoder.decode(data + Data("trailing text".utf8))
        }
    }

    /// Reading: a second FIT file chained after the first is read through,
    /// as the SDK does, and the first session still describes the activity.
    /// The spec does not cover this.
    @Test func chainedFilesAreReadThrough() throws {
        let first = try SyntheticFIT.file([
            try SyntheticFIT.record(0) { try $0.setHeartRate(100) },
            try SyntheticFIT.session(sport: .cycling, elapsed: 600, timer: 600),
        ])
        let second = try SyntheticFIT.file([
            try SyntheticFIT.record(700) { try $0.setHeartRate(107) },
            try SyntheticFIT.session(sport: .running, elapsed: 300, timer: 300),
        ])
        let activity = try FITActivityDecoder.decode(first + second)
        #expect(activity.sport == .cycling)
        #expect(activity.stated.end == SyntheticFIT.date(600))
        #expect(activity.stream.samples.map(\.heartRate) == [100, 107])
    }

    /// The data size the header states: bytes 4 to 7, little-endian.
    private func statedDataSize(_ data: Data) -> UInt32 {
        data[4..<8].reversed().reduce(0) { $0 << 8 | UInt32($1) }
    }

    private func littleEndian(_ value: UInt32) -> Data {
        Data((0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) })
    }
}
