import Foundation
import Testing
import SweatKitModel
import SweatKitLibrary

@Suite struct HealthWorkoutIntervalsTests {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    func span(_ start: Double, _ end: Double) -> DateInterval {
        DateInterval(start: self.start.addingTimeInterval(start), end: self.start.addingTimeInterval(end))
    }

    @Test func explicitLapsRetainGapsAndLegacyMarkersUsePreviousEnd() {
        let laps = HealthWorkoutIntervals.laps([span(50, 50), span(10, 20), span(30, 40), span(10, 20)], within: span(0, 60))
        #expect(laps == [RecordedLap(start: span(10, 20).start, end: span(10, 20).end),
                         RecordedLap(start: span(30, 40).start, end: span(30, 40).end),
                         RecordedLap(start: span(40, 50).start, end: span(40, 50).end)])
    }

    @Test func legacyLapsBeginAtWorkoutStartWithoutInventingTrailingLap() {
        let laps = HealthWorkoutIntervals.laps([span(20, 20), span(40, 40)], within: span(0, 60))
        #expect(laps.map { $0.end.timeIntervalSince($0.start) } == [20, 20])
        #expect(laps.first?.start == start)
        #expect(laps.last?.end == start.addingTimeInterval(40))
    }

    @Test func segmentsPreserveOverlapsWhileInvalidLapsAreExcluded() {
        let intervals = [span(-10, 5), span(10, 30), span(20, 40), span(50, 70)]
        #expect(HealthWorkoutIntervals.laps(intervals, within: span(0, 60)).count == 1)
        #expect(HealthWorkoutIntervals.segments(intervals, within: span(0, 60)).count == 2)
    }

    @Test func oldRecordingsAndCheckpointsDecodeAndUpgradeOnce() throws {
        let old = RecordedActivity(sport: .running)
        let encoded = try JSONEncoder().encode(old)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("segments"))
        #expect(try JSONDecoder().decode(RecordedActivity.self, from: encoded).segments == nil)
        var updated = old
        updated.segments = [RecordedLap(start: start, end: start.addingTimeInterval(10))]
        #expect(try JSONDecoder().decode(RecordedActivity.self, from: JSONEncoder().encode(updated)) == updated)

        var state = HealthSyncState()
        let id = UUID()
        state.workouts[id] = span(0, 60)
        state.anchors["workouts"] = Data([1, 2])
        state = try JSONDecoder().decode(HealthSyncState.self, from: JSONEncoder().encode(state))
        state.refreshSnapshots(forAdapterVersion: 1)
        #expect(state.pending == [id])
        #expect(state.anchors["workouts"] == Data([1, 2]))
        state.pending.remove(id)
        state.refreshSnapshots(forAdapterVersion: 1)
        #expect(state.pending.isEmpty)
    }
}
