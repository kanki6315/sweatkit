import Foundation
import SweatKitAnalysis
import SweatKitFlyover
import SweatKitIngest
import SweatKitModel
import SweatKitTestSupport
import SweatKitTimeline
import Testing
@testable import SweatKitDetail

/// A profile with a threshold power and a max heart rate, so every zoned
/// overlay is available.
let fixtureProfile = AthleteProfile(
    thresholdPowerHistory: [.init(effectiveFrom: Date(timeIntervalSince1970: 0), watts: 250)],
    maxHeartRate: 190
)

func fixtureInput(_ fixture: Fixtures.FIT) throws -> DetailInput {
    let activity = try FITActivityDecoder.decode(try fixture.data())
    let stream = try #require(StreamNormaliser.analysisStream(from: activity))
    return DetailInput(
        stream: stream,
        sport: activity.sport,
        isIndoor: activity.isIndoor,
        isVirtual: activity.isVirtual,
        lapStarts: DetailInput.lapStarts(of: activity.laps, streamStart: stream.start),
        profile: fixtureProfile,
        activityDate: stream.start
    )
}

@Suite("Real recordings")
struct FixtureTests {
    @Test(arguments: Fixtures.FIT.allCases)
    func everyViewInputHasTheShapeItsViewRequires(_ fixture: Fixtures.FIT) throws {
        let input = try fixtureInput(fixture)
        let detail = DetailPreparation.prepare(input)
        let count = input.stream.count

        // Bands: one per second, every band inside its count.
        for overlay in RouteOverlay.allCases {
            guard let bands = detail.bands[overlay]?.value else { continue }
            #expect(bands.bands.count == count)
            #expect(bands.bands.allSatisfy { $0.map { (0..<bands.bandCount).contains($0) } ?? true })
        }

        // The timeline: every array one per second, and its initialiser
        // accepts them again.
        let timeline = try #require(detail.timeline)
        #expect(timeline.count == count)
        #expect(timeline.distance?.count ?? count == count)
        let rebuilt = try TimelineData(
            elevation: timeline.elevation,
            distance: timeline.distance,
            stops: timeline.stops,
            lapBoundaries: timeline.lapBoundaries
        )
        #expect(rebuilt.count == count)
        #expect(!timeline.lapBoundaries.isEmpty)
        for overlay in detail.timelineOverlays.values {
            #expect(overlay.values.count == count)
            #expect(overlay.bands.map { $0.count == count } ?? true)
        }

        // The route, where there is one.
        for overlay in RouteOverlay.allCases {
            guard let route = detail.route(for: overlay).value else { continue }
            #expect(route.vertices.count == route.bands.count)
            #expect(route.sampleIndices.count == route.vertices.count)
            #expect(zip(route.sampleIndices, route.sampleIndices.dropFirst()).allSatisfy { $0 < $1 })
            #expect(route.sampleIndices.allSatisfy { (0..<count).contains($0) })
            let again = try FlyoverRoute(vertices: route.vertices, bands: route.bands, sampleIndices: route.sampleIndices)
            #expect(again == route)
        }

        // Stats at the cursor and over the whole activity.
        _ = detail.cursorStats(at: count / 2)
        let whole = detail.rangeStats(0...(count - 1))
        #expect(whole.time == TimeInterval(count))
        let metrics = ActivityAnalysis.metrics(for: ActivityInput(
            sport: input.sport, isIndoor: input.isIndoor, isVirtual: input.isVirtual,
            recording: .stream(input.stream), profile: input.profile, activityDate: input.activityDate
        ))
        // The range's ascent is the analysis package's own rule.
        #expect(whole.ascent == metrics.ascent.value)
        #expect(whole.averageHeartRate == metrics.heartRate.average.value)
        #expect(whole.averagePower == metrics.power.average.value)
    }

    @Test func theOutdoorRide() throws {
        let detail = DetailPreparation.prepare(try fixtureInput(.outdoorRide))
        #expect(detail.defaultOverlay == .power)
        let route = try #require(detail.route(for: .power).value)
        #expect(route.vertices.count >= 2)
        #expect(detail.timelineOverlays[.power] != nil)
        #expect(detail.timelineOverlays[.speed] != nil)
    }

    @Test func theZwiftRideHasNoRoute() throws {
        let detail = DetailPreparation.prepare(try fixtureInput(.zwiftRide))
        #expect(detail.line.reason == .virtualActivity)
        for overlay in RouteOverlay.allCases {
            #expect(detail.route(for: overlay).value == nil)
        }
        #expect(detail.timeline != nil)
        #expect(detail.defaultOverlay == .power)
    }

    @Test(arguments: [Fixtures.FIT.walk, .walkPitlane])
    func theWalks(_ fixture: Fixtures.FIT) throws {
        let detail = DetailPreparation.prepare(try fixtureInput(fixture))
        #expect(detail.defaultOverlay == .paceOrSpeed)
        #expect(detail.route(for: .paceOrSpeed).value != nil)
        #expect(detail.timelineOverlays[.pace] != nil)
        #expect(detail.timelineOverlays[.power] == nil)
    }

    @Test func thePitlaneWalkHasStopsToCollapse() throws {
        // About 2.5 hours paused: those spans at least are stops.
        let input = try fixtureInput(.walkPitlane)
        let timeline = try #require(DetailPreparation.prepare(input).timeline)
        #expect(!timeline.stops.isEmpty)
        if case .known(let paused) = input.stream.pauses {
            let stopped = Set(timeline.stops.flatMap { Array($0) })
            #expect(paused.allSatisfy { $0.allSatisfy(stopped.contains) })
        }
    }

    /// The spec's target is cached data on screen within 1 second on the
    /// phone. This times the whole preparation of the 36,142-second walk,
    /// decoding excluded, and prints it.
    @Test func preparingALongActivityIsQuick() throws {
        let input = try fixtureInput(.walkPitlane)
        #expect(input.stream.count == 36_142)
        let clock = ContinuousClock()
        var detail: PreparedDetail?
        let preparation = clock.measure { detail = DetailPreparation.prepare(input) }
        let prepared = try #require(detail)
        let range = clock.measure { _ = prepared.rangeStats(1000...30_000) }
        let cursor = clock.measure {
            for second in stride(from: 0, to: 36_142, by: 100) { _ = prepared.cursorStats(at: second) }
        }
        print("SweatKitDetail timing: prepare \(preparation), one range \(range), 362 cursor reads \(cursor)")
        // Generous, so a debug build on a loaded machine passes. The report
        // gives the release figure.
        #expect(preparation < .seconds(5))
    }
}
