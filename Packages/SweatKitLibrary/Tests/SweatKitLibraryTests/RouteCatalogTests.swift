import Foundation
import Testing
@testable import SweatKitLibrary
import SweatKitModel
import SweatKitStore
import SweatKitIngest
import SweatKitRouteMatching
import SweatKitTestSupport

@Suite struct RouteCatalogTests {
    let temporary = TemporaryLibrary()

    func input(_ id: String, offset: Double = 0, reverse: Bool = false, reliable: Bool = true) -> RouteInput {
        let identity = SourceIdentity(source: .file, externalID: id)
        let row = ActivityRecord(members: [identity], primary: identity, sport: .cycling,
            start: Date(timeIntervalSince1970: Double(id.utf8.first ?? 0) * 86400), elapsedTime: 100, title: id)
        var coords = (0...100).map { Coordinate(latitude: (5 + offset) / 111_195, longitude: (10 + Double($0) * 20) / 111_195) }
        if reverse { coords.reverse() }
        return RouteInput(row: row, track: CleanedTrack(points: coords.enumerated().map {
            TrackPoint(coordinate: $0.element, time: Double($0.offset))
        }, sportFamily: .cycling, pausePositionsAreReliable: reliable), metrics: nil)
    }
    @Test func groupsRanksAndRejectsReverse() async throws {
        let a = input("a"), b = input("b"), c = input("c", reverse: true)
        let catalog = await ActivityLibrary.assembleRoutes([a,a,b,c], seeds: [], decisions: [])
        let route = try #require(catalog.routes.first)
        #expect(catalog.routes.count == 1)
        #expect(route.efforts.count == 2)
        #expect(route.rank(of: a.row.id!) == 1)
        #expect(route.rank(of: b.row.id!) == 1)
        #expect(route.occurrence(of: a.row.id!) == 1)
        #expect(route.occurrence(of: b.row.id!) == 2)
        #expect(route.secondsBehindBest(of: b.row.id!) == 0)
        #expect(catalog.membership(of: c.row.id!) == nil)
        #expect(try #require(route.best) < 100)
    }
    @Test func routeContextSeparatesChronologyFromSpeedAndKeepsTiesStable() async throws {
        let first = input("a")
        var fastTrack = input("b").track
        fastTrack.points = fastTrack.points.map {
            TrackPoint(coordinate: $0.coordinate, elapsedTime: $0.elapsedTime * 0.8, movingTime: $0.movingTime * 0.8)
        }
        var sameDate = input("b").row
        sameDate.start = first.row.start
        let faster = RouteInput(row: sameDate, track: fastTrack, metrics: nil)
        let route = try #require(await ActivityLibrary.assembleRoutes([faster, first], seeds: [], decisions: []).routes.first)
        #expect(route.occurrence(of: first.row.id!) == 1)
        #expect(route.occurrence(of: faster.row.id!) == 2)
        #expect(route.rank(of: first.row.id!) == 2)
        #expect(route.rank(of: faster.row.id!) == 1)
        #expect(abs(try #require(route.secondsBehindBest(of: first.row.id!)) - 19.5) < 0.01)
    }

    @Test func parallelRoadNeedsExplicitDecisionAndRemovalPersists() async throws {
        let a = input("a"), b = input("b", offset: 14)
        let review = await ActivityLibrary.assembleRoutes([a,b], seeds: [], decisions: [])
        #expect(review.routes.isEmpty)
        #expect(review.reviews.count == 1)
        let approve = RouteDecision(route: a.row.id!, value: .membership(activity: b.row.id!, included: true))
        let joined = await ActivityLibrary.assembleRoutes([a,b], seeds: [], decisions: [approve])
        #expect(joined.routes.count == 1)
        let remove = RouteDecision(route: a.row.id!, value: .membership(activity: b.row.id!, included: false))
        let separate = await ActivityLibrary.assembleRoutes([a,b], seeds: [.init(id: a.row.id!, members: [a.row.id!, b.row.id!])], decisions: [approve,remove])
        #expect(separate.routes.isEmpty)
        #expect(separate.reviews.isEmpty)
    }
    @Test func unknownPausesHaveNoMovingRankAndBothGhostsUseElapsed() async throws {
        let a = input("a"), b = input("b", reliable: false)
        let route = try #require(await ActivityLibrary.assembleRoutes([a,b], seeds: [], decisions: []).routes.first)
        #expect(route.ranked.count == 1)
        #expect(route.rank(of: b.row.id!) == nil)
        #expect(route.occurrence(of: b.row.id!) == 2)
        #expect(route.secondsBehindBest(of: b.row.id!) == nil)
        let comparison = try #require(RouteComparison.compare(route.efforts[0].alignment, against: route.efforts[1].alignment).value)
        #expect(comparison.clock == .elapsed)
        #expect(!comparison.movingTimeIsAvailable)
        #expect(comparison.ghost(at: 0).subjectRouteDistance == 25)
        #expect(comparison.ghost(at: 50).separation == 0)
    }
    @Test func sharedClockProducesNonzeroSeparationAndDistanceGridGap() async throws {
        let a = input("a")
        var faster = input("b").track
        faster.points = faster.points.map { TrackPoint(coordinate: $0.coordinate, elapsedTime: $0.elapsedTime * 0.8, movingTime: $0.movingTime * 0.8) }
        let line = try #require(ReferenceLine(track: a.track))
        let comparison = try #require(RouteComparison.compare(RouteAlignment.align(a.track, to: line), against: RouteAlignment.align(faster, to: line)).value)
        // 20 m/s vs 25 m/s: after 30 s the faster effort is 150 m ahead.
        #expect(abs(comparison.ghost(at: 30).separation - 150) < 0.1)
        #expect(abs(try #require(comparison.grid.last).gap - 19.5) < 0.01)
    }
    @Test func changedReferenceAndHiddenSeedKeepRouteIdentity() async throws {
        let a = input("a"), b = input("b"), c = input("c")
        let seed = RouteSeed(id: a.row.id!, members: [a.row.id!, b.row.id!, c.row.id!])
        let rename = RouteDecision(route: a.row.id!, value: .name("River loop"))
        let reference = RouteDecision(route: a.row.id!, value: .reference(c.row.id!))
        let route = try #require(await ActivityLibrary.assembleRoutes([b,c], seeds: [seed], decisions: [rename,reference]).routes.first)
        #expect(route.id == a.row.id!)
        #expect(route.name == "River loop")
        #expect(route.referenceID == c.row.id!)
        #expect(route.efforts.count == 2)
    }

    @Test func exportedEditScopeRestoresNamedGroupWithoutLocalSeedsOrOriginalReference() async throws {
        let a = input("a"), b = input("b"), c = input("c")
        let name = RouteDecision(route: a.row.id!, value: .name("Cloud-restored name"), anchors: [a.row.id!, b.row.id!, c.row.id!])
        let catalog = await ActivityLibrary.assembleRoutes([b,c], seeds: [], decisions: [name])
        let route = try #require(catalog.routes.first)
        #expect(route.id == a.row.id!)
        #expect(route.name == "Cloud-restored name")
    }
    @Test func identityMergePreservesRouteNameAndMembershipDecisions() async throws {
        let a = input("a"), b = input("b"), c = input("c")
        var merged = b.row
        merged.members = [a.row.id!, b.row.id!]
        let mergedInput = RouteInput(row: merged, track: b.track, metrics: nil)
        let seed = RouteSeed(id: b.row.id!, members: [b.row.id!, c.row.id!])
        let name = RouteDecision(route: b.row.id!, value: .name("Kept name"))
        let catalog = await ActivityLibrary.assembleRoutes([mergedInput,c], seeds: [seed], decisions: [name])
        let route = try #require(catalog.routes.first)
        #expect(route.id == b.row.id!)
        #expect(route.name == "Kept name")
        #expect(catalog.membership(of: b.row.id!)?.id == b.row.id!)
        let remove = RouteDecision(route: b.row.id!, value: .membership(activity: b.row.id!, included: false))
        #expect(await ActivityLibrary.assembleRoutes([mergedInput,c], seeds: [seed], decisions: [name,remove]).routes.isEmpty)
    }
    @Test func explicitMergeRebuildsEveryAlignmentWithoutOverridingExclusions() async throws {
        let a = input("a"), b = input("b"), c = input("c", offset: 14), d = input("d", offset: 14)
        let separate = [c,d].map { RouteDecision(route: a.row.id!, value: .membership(activity: $0.row.id!, included: false)) }
        let split = await ActivityLibrary.assembleRoutes([a,b,c,d], seeds: [], decisions: separate)
        #expect(split.routes.count == 2)
        let merge = RouteDecision(route: a.row.id!, value: .merge(c.row.id!))
        // Per-effort exclusions remain stronger than merging their group.
        let refused = await ActivityLibrary.assembleRoutes([a,b,c,d], seeds: [], decisions: separate + [merge])
        #expect(refused.routes.count == 2)
        let included = [c,d].map { RouteDecision(route: a.row.id!, value: .membership(activity: $0.row.id!, included: true)) }
        let merged = await ActivityLibrary.assembleRoutes([a,b,c,d], seeds: [], decisions: separate + included + [merge])
        #expect(merged.routes.count == 1)
        #expect(merged.routes.first?.efforts.count == 4)
    }

    @Test func decisionExportIsIdempotentAndContainsNoDerivedGeometry() async throws {
        let library = try temporary.open()
        let id = input("a").row.id!
        let event = RouteDecision(route: id, value: .name("Loop"))
        let payload = RouteDecisionExport(decisions: [event])
        try await library.applyRouteDecisions(payload)
        try await library.applyRouteDecisionPayload(library.exportRouteDecisionPayload())
        let reopened = try temporary.open()
        let exported = try await reopened.routeDecisions()
        #expect(exported.decisions == [event])
        let json = String(decoding: try JSONEncoder().encode(exported), as: UTF8.self)
        #expect(!json.contains("latitude")); #expect(!json.contains("alignment"))
        let conflict = RouteDecision(id: event.id, route: id, value: .name("Other"), date: event.date)
        await #expect(throws: (any Error).self) { try await reopened.applyRouteDecisions(.init(decisions: [conflict])) }
    }
    @Test func realFixtureReopensRecomputesAndHonorsHiddenDeletedActivities() async throws {
        let library = try temporary.open()
        let bytes = try Fixtures.FIT.outdoorRide.data()
        let first = try await library.importFile(bytes)
        var repeated = try FITActivityDecoder.decode(bytes)
        let shift = 86400.0 * 7
        repeated.stated.start = repeated.stated.start?.addingTimeInterval(shift)
        repeated.stated.end = repeated.stated.end?.addingTimeInterval(shift)
        for i in repeated.stream.samples.indices { repeated.stream.samples[i].timestamp += shift }
        for i in repeated.timerEvents.indices { repeated.timerEvents[i].timestamp += shift }
        let health = HealthSnapshot(workoutID: UUID(), activity: repeated, sourceName: "Fixture", sourceBundleIdentifier: "test.routes")
        try await library.importHealthSnapshot(health)
        let route = try #require(try await library.routes().routes.first)
        #expect(route.efforts.count == 2)
        #expect(route.efforts.allSatisfy { $0.elapsedTime != nil })
        try await library.decideRoute(route.id, value: .name("Fixture course"))
        let reopened = try temporary.open()
        var noGPS = health
        for i in noGPS.activity.stream.samples.indices { noGPS.activity.stream.samples[i].position = nil }
        try await reopened.importHealthSnapshot(noGPS)
        #expect(try await reopened.routes().routes.isEmpty)
        try await reopened.importHealthSnapshot(health)
        _ = try await reopened.recompute()
        #expect(try await reopened.routes().routes.first?.name == "Fixture course")
        try await reopened.decide(.hidden(true), for: first.activity.id!)
        #expect(try await reopened.routes().routes.isEmpty)
        try await reopened.decide(.hidden(false), for: first.activity.id!)
        #expect(try await reopened.routes().routes.first?.name == "Fixture course")
        try await reopened.permanentlyDelete(health.identity)
        #expect(try await reopened.routes().routes.isEmpty)
        let excluded = try temporary.root.appending(path: "LocalMetadata").resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(excluded.isExcludedFromBackup == true)
    }
}
