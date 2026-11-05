import Foundation
import SweatKitIngest
import SweatKitModel
import SweatKitTestSupport
import Testing

/// The four real fixtures through the decoder and the normaliser.
///
/// Every expected value comes from `Fixtures/README.md`, or from the counts
/// `FixtureDecodeTests` pins with the SDK alone. None comes from running the
/// decoder.
@Suite struct FixtureActivityTests {
    /// One row of the README's table.
    struct Facts: Sendable, CustomTestStringConvertible {
        var fixture: Fixtures.FIT
        var sport: SweatKitModel.Sport
        var isVirtual: Bool
        var isIndoor: Bool
        /// The "Elapsed" column, seconds, rounded to 0.1 s.
        var elapsed: Double
        /// The "Timer" column, seconds, rounded to 0.1 s.
        var timer: Double
        /// The "Distance" column, kilometres, rounded to 0.01 km.
        var distanceKilometres: Double
        /// Elapsed time rounded up to whole seconds: the length of the grid.
        var gridSeconds: Int

        var testDescription: String { fixture.rawValue }

        /// The counts `FixtureDecodeTests` pins for the same file.
        var pinned: FixtureDecodeTests.Expected {
            get throws { try #require(FixtureDecodeTests.expected.first { $0.fixture == fixture }) }
        }
    }

    static let facts = [
        // "Outdoor road ride, Garmin bike computer". 5,755.7 s rounds up to 5,756.
        Facts(
            fixture: .outdoorRide, sport: .cycling, isVirtual: false, isIndoor: false,
            elapsed: 5755.7, timer: 5335.7, distanceKilometres: 37.53, gridSeconds: 5756
        ),
        // "Zwift ride, sub-sport virtual activity". 2,408.0 s is 2,408 whole seconds.
        // Reading: a virtual ride is indoor as well as virtual.
        Facts(
            fixture: .zwiftRide, sport: .cycling, isVirtual: true, isIndoor: true,
            elapsed: 2408.0, timer: 2409.0, distanceKilometres: 18.74, gridSeconds: 2408
        ),
        // "Outdoor walk in the open". 2,492.7 s rounds up to 2,493.
        Facts(
            fixture: .walk, sport: .walking, isVirtual: false, isIndoor: false,
            elapsed: 2492.7, timer: 2490.3, distanceKilometres: 3.27, gridSeconds: 2493
        ),
        // "Walk along a pit lane, beside buildings". 36,141.7 s rounds up to 36,142.
        Facts(
            fixture: .walkPitlane, sport: .walking, isVirtual: false, isIndoor: false,
            elapsed: 36141.7, timer: 27034.1, distanceKilometres: 17.91, gridSeconds: 36142
        ),
    ]

    /// Half of the README's last printed digit: 0.1 s for times.
    private static let timeRounding = 0.05
    /// Half of the README's last printed digit for distance: 0.01 km is 10 m.
    private static let distanceRounding = 5.0

    @Test func everyFixtureHasItsFacts() {
        #expect(Set(Self.facts.map(\.fixture)) == Set(Fixtures.FIT.allCases))
    }

    // MARK: Decoding

    @Test(arguments: facts)
    func fixtureDecodesToItsSportAndFlags(_ facts: Facts) throws {
        let activity = try FITActivityDecoder.decode(try facts.fixture.data())
        #expect(activity.sport == facts.sport)
        #expect(activity.isVirtual == facts.isVirtual)
        #expect(activity.isIndoor == facts.isIndoor)
    }

    @Test(arguments: facts)
    func fixtureDecodesToItsStatedSummary(_ facts: Facts) throws {
        let stated = try FITActivityDecoder.decode(try facts.fixture.data()).stated
        let start = try #require(stated.start)
        let end = try #require(stated.end)
        let timerTime = try #require(stated.timerTime)
        let distance = try #require(stated.distance)
        #expect(abs(end.timeIntervalSince(start) - facts.elapsed) <= Self.timeRounding)
        #expect(abs(timerTime - facts.timer) <= Self.timeRounding)
        #expect(abs(distance - facts.distanceKilometres * 1000) <= Self.distanceRounding)
    }

    @Test(arguments: facts)
    func fixtureDecodesEveryRecord(_ facts: Facts) throws {
        let activity = try FITActivityDecoder.decode(try facts.fixture.data())
        let samples = activity.stream.samples
        let pinned = try facts.pinned
        #expect(samples.count == pinned.records)
        // "Every record has a timestamp and heart rate."
        #expect(samples.count { $0.heartRate != nil } == pinned.records)
        #expect(samples.count { $0.position != nil } == pinned.recordsWithPosition)
        #expect(samples.count { $0.power != nil } == pinned.recordsWithPower)
        // The Garmin files hold speed and altitude in the enhanced fields only.
        #expect(samples.count { $0.speed != nil } == pinned.recordsWithSpeed)
        #expect(samples.count { $0.altitude != nil } == pinned.recordsWithAltitude)
        #expect(activity.laps.count == pinned.laps)
        // Records are in time order in every fixture, and stay so.
        #expect(samples.map(\.timestamp) == samples.map(\.timestamp).sorted())
    }

    @Test(arguments: facts)
    func fixturePositionsAreDegrees(_ facts: Facts) throws {
        let samples = try FITActivityDecoder.decode(try facts.fixture.data()).stream.samples
        // Left in semicircles, a latitude would be in the hundreds of millions.
        #expect(samples.compactMap(\.position).allSatisfy {
            abs($0.latitude) <= 90 && abs($0.longitude) <= 180
        })
    }

    // MARK: Normalising

    @Test(arguments: facts)
    func fixtureStreamSpansStatedElapsedTime(_ facts: Facts) throws {
        let activity = try FITActivityDecoder.decode(try facts.fixture.data())
        let stream = try #require(StreamNormaliser.analysisStream(from: activity))
        #expect(stream.rulesVersion == StreamRules.version)
        #expect(stream.start == activity.stated.start)
        #expect(stream.count == facts.gridSeconds)
        #expect(stream.isConsistent)
    }

    /// "Timer time, complete pause data: elapsed time minus the paused
    /// spans." So the paused spans must add up to the README's elapsed minus
    /// its timer time: 420.0 s on the outdoor ride, -1.0 s on Zwift (so no
    /// pause), 2.4 s on the walk and 9,107.6 s on the pit-lane walk.
    @Test(arguments: facts)
    func fixturePausesAreKnownAndAddUpToElapsedMinusTimerTime(_ facts: Facts) throws {
        let activity = try FITActivityDecoder.decode(try facts.fixture.data())
        let stream = try #require(StreamNormaliser.analysisStream(from: activity))
        guard case .known(let paused) = stream.pauses else {
            Issue.record("Pause data is \(stream.pauses), expected complete")
            return
        }
        // Sorted, non-overlapping, non-empty and on the grid, as `PauseData` promises.
        #expect(paused.allSatisfy { !$0.isEmpty && $0.lowerBound >= 0 && $0.upperBound <= stream.count })
        #expect(zip(paused, paused.dropFirst()).allSatisfy { $0.upperBound <= $1.lowerBound })

        let pausedSeconds = Double(paused.reduce(0) { $0 + $1.count })
        // Event timestamps are whole seconds and the device's timer runs in
        // milliseconds, and the grid rounds elapsed time up, so allow 2 s.
        #expect(abs(pausedSeconds - (facts.elapsed - facts.timer)) <= 2)
    }

    /// Every record has heart rate and a second of its own, so each lands on
    /// the grid as one measured second. The one exception allowed is a record
    /// stamped exactly on the stated end, which is off the grid.
    @Test(arguments: facts)
    func fixtureHeartRateKeepsEveryRecord(_ facts: Facts) throws {
        let activity = try FITActivityDecoder.decode(try facts.fixture.data())
        let stream = try #require(StreamNormaliser.analysisStream(from: activity))
        let records = try facts.pinned.records
        let measuredSeconds = stream.heartRate.quality.count { $0 == .measured }
        #expect((records - 1...records).contains(measuredSeconds))
    }

    @Test func zwiftStreamKeepsItsPowerAndMadeUpPositions() throws {
        let activity = try FITActivityDecoder.decode(try Fixtures.FIT.zwiftRide.data())
        let stream = try #require(StreamNormaliser.analysisStream(from: activity))
        // Power and position are on all 2,409 records, one a second, over a
        // 2,408 s grid, so no second is without either.
        #expect(stream.power.presentSeconds.count == 2408)
        #expect(stream.latitude.presentSeconds.count == 2408)
    }

    @Test func walksHaveNoPower() throws {
        for fixture in [Fixtures.FIT.walk, .walkPitlane] {
            let activity = try FITActivityDecoder.decode(try fixture.data())
            let stream = try #require(StreamNormaliser.analysisStream(from: activity))
            // Missing, never zero.
            #expect(stream.power.presentSeconds.isEmpty)
        }
    }
}
