import Foundation
import Testing
import SweatKitModel
@testable import SweatKitLibrary

struct GolfHealthRecordingTests {
    // Deliberately synthetic boundary cases, not a supplied user's round.
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private func snapshot(_ samples: [NativeSample] = [], distance: Double? = nil,
                          sportName: String? = "Golf") -> HealthSnapshot {
        HealthSnapshot(workoutID: UUID(), activity: RecordedActivity(sport: .other,
            stated: StatedSummary(start: start, end: start.addingTimeInterval(3600),
                                  timerTime: 3500, distance: distance),
            stream: NativeStream(samples: samples)), sourceName: "Test recorder",
            sourceBundleIdentifier: "test.golf", sourceSportName: sportName)
    }

    @Test func emptyRecordingDoesNotInventChannelsOrDistance() throws {
        let detail = try #require(GolfHealthRecording(snapshot()))
        #expect(detail.channels.isEmpty)
        #expect(detail.positions.isEmpty)
        #expect(detail.stated.distance == nil)
        #expect(detail.stated.timerTime == 3500)
        #expect(GolfHealthRecording(snapshot(sportName: nil)) == nil)
    }

    @Test func preservesSparseNativeReadingsWithoutFillingGapsOrUsingTotal() throws {
        let samples = [NativeSample(timestamp: start.addingTimeInterval(900), heartRate: 120),
                       NativeSample(timestamp: start, heartRate: 80),
                       NativeSample(timestamp: start.addingTimeInterval(450))]
        let detail = try #require(GolfHealthRecording(snapshot(samples, distance: 3000)))
        #expect(detail.channels.count == 1)
        let heart = try #require(detail.channels.first)
        #expect(heart.readings.map(\.value) == [80, 120])
        #expect(heart.readings.map(\.timestamp) == [start, start.addingTimeInterval(900)])
        #expect(detail.stated.distance == 3000)
        #expect(detail.positions.isEmpty)
    }

    @Test func invalidSamplesAreMissingAndRecordedZeroSurvives() throws {
        let detail = try #require(GolfHealthRecording(snapshot([
            NativeSample(timestamp: start, position: Coordinate(latitude: 0, longitude: 0),
                         altitude: -10, speed: 0, heartRate: .nan, power: 0),
            NativeSample(timestamp: start.addingTimeInterval(1), position: Coordinate(latitude: 91, longitude: 0),
                         altitude: .infinity, speed: -1, heartRate: -10)
        ])))
        #expect(detail.positions.count == 1)
        #expect(detail.channels.map(\.name) == ["Altitude", "Speed", "Power"])
        #expect(detail.channels.map { $0.readings.map(\.value) } == [[-10], [0], [0]])
    }

    @Test func readsSelectedOriginalAndLatestRevisionAfterReopen() async throws {
        let temporary = TemporaryLibrary()
        let library = try temporary.open()
        var first = snapshot([NativeSample(timestamp: start, heartRate: 90)])
        let other = snapshot([NativeSample(timestamp: start, heartRate: 150)])
        try await library.importHealthSnapshot(first)
        try await library.importHealthSnapshot(other)
        let original = try #require(try await library.golfHealthRecording(for: first.identity))
        #expect(original.channels.first?.readings.map(\.value) == [90])
        first.activity.stream.samples = []
        try await library.importHealthSnapshot(first)
        let reopened = try temporary.open()
        let refreshed = try #require(try await reopened.golfHealthRecording(for: first.identity))
        #expect(refreshed.channels.isEmpty)
        #expect(refreshed.stated.distance == nil)
        let unchanged = try #require(try await reopened.golfHealthRecording(for: other.identity))
        #expect(unchanged.channels.first?.readings.map(\.value) == [150])
    }
}
