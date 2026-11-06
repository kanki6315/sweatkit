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
    @Test func repeatedPairsAreVisibleAsDevelopingUntilFiveOutings() async throws {
        let catalog = try await ActivityLibrary.assembleRoutes([input("a"), input("b"), input("c", reverse: true)], seeds: [], decisions: [])
        #expect(catalog.routes.isEmpty)
        #expect(catalog.developingRoutes?.count == 1)
        #expect(catalog.developingRoutes?.first?.efforts.count == 2)
        let frequent = try await ActivityLibrary.assembleRoutes([input("a"), input("b"), input("c"), input("d"), input("e")], seeds: [], decisions: [])
        #expect(frequent.routes.count == 1)
        #expect(frequent.developingRoutes?.isEmpty == true)
    }

    @Test func groupsRanksAndRejectsReverse() async throws {
        let a = input("a"), b = input("b"), c = input("c", reverse: true)
        let catalog = try await ActivityLibrary.assembleRoutes([a,a,b,c], seeds: [], decisions: [], minimumOutings: 2)
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
        let route = try #require(try await ActivityLibrary.assembleRoutes([faster, first], seeds: [], decisions: [], minimumOutings: 2).routes.first)
        #expect(route.occurrence(of: first.row.id!) == 1)
        #expect(route.occurrence(of: faster.row.id!) == 2)
        #expect(route.rank(of: first.row.id!) == 2)
        #expect(route.rank(of: faster.row.id!) == 1)
        #expect(abs(try #require(route.secondsBehindBest(of: first.row.id!)) - 19.5) < 0.01)
    }

    @Test func parallelRoadNeedsExplicitDecisionAndRemovalPersists() async throws {
        let a = input("a"), b = input("b", offset: 14)
        let review = try await ActivityLibrary.assembleRoutes([a,b], seeds: [], decisions: [], minimumOutings: 2)
        #expect(review.routes.isEmpty)
        #expect(review.reviews.isEmpty) // Too few confirmed outings to surface a review.
        let approve = RouteDecision(route: a.row.id!, value: .membership(activity: b.row.id!, included: true))
        let joined = try await ActivityLibrary.assembleRoutes([a,b], seeds: [], decisions: [approve], minimumOutings: 2)
        #expect(joined.routes.count == 1)
        let remove = RouteDecision(route: a.row.id!, value: .membership(activity: b.row.id!, included: false))
        let separate = try await ActivityLibrary.assembleRoutes([a,b], seeds: [.init(id: a.row.id!, members: [a.row.id!, b.row.id!])], decisions: [approve,remove], minimumOutings: 2)
        #expect(separate.routes.isEmpty)
        #expect(separate.reviews.isEmpty)
    }
    @Test func unknownPausesHaveNoMovingRankAndBothGhostsUseElapsed() async throws {
        let a = input("a"), b = input("b", reliable: false)
        let route = try #require(try await ActivityLibrary.assembleRoutes([a,b], seeds: [], decisions: [], minimumOutings: 2).routes.first)
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
        let route = try #require(try await ActivityLibrary.assembleRoutes([b,c], seeds: [seed], decisions: [rename,reference], minimumOutings: 2).routes.first)
        #expect(route.id == a.row.id!)
        #expect(route.name == "River loop")
        #expect(route.referenceID == c.row.id!)
        #expect(route.efforts.count == 2)
    }

    @Test func exportedEditScopeRestoresNamedGroupWithoutLocalSeedsOrOriginalReference() async throws {
        let a = input("a"), b = input("b"), c = input("c")
        let name = RouteDecision(route: a.row.id!, value: .name("Cloud-restored name"), anchors: [a.row.id!, b.row.id!, c.row.id!])
        let catalog = try await ActivityLibrary.assembleRoutes([b,c], seeds: [], decisions: [name], minimumOutings: 2)
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
        let catalog = try await ActivityLibrary.assembleRoutes([mergedInput,c], seeds: [seed], decisions: [name], minimumOutings: 2)
        let route = try #require(catalog.routes.first)
        #expect(route.id == b.row.id!)
        #expect(route.name == "Kept name")
        #expect(catalog.membership(of: b.row.id!)?.id == b.row.id!)
        let remove = RouteDecision(route: b.row.id!, value: .membership(activity: b.row.id!, included: false))
        #expect(try await ActivityLibrary.assembleRoutes([mergedInput,c], seeds: [seed], decisions: [name,remove], minimumOutings: 2).routes.isEmpty)
    }
    @Test func explicitMergeRebuildsEveryAlignmentWithoutOverridingExclusions() async throws {
        let a = input("a"), b = input("b"), c = input("c", offset: 14), d = input("d", offset: 14)
        let separate = [c,d].map { RouteDecision(route: a.row.id!, value: .membership(activity: $0.row.id!, included: false)) }
        let split = try await ActivityLibrary.assembleRoutes([a,b,c,d], seeds: [], decisions: separate, minimumOutings: 2)
        #expect(split.routes.count == 2)
        let merge = RouteDecision(route: a.row.id!, value: .merge(c.row.id!))
        // Per-effort exclusions remain stronger than merging their group.
        let refused = try await ActivityLibrary.assembleRoutes([a,b,c,d], seeds: [], decisions: separate + [merge], minimumOutings: 2)
        #expect(refused.routes.count == 2)
        let included = [c,d].map { RouteDecision(route: a.row.id!, value: .membership(activity: $0.row.id!, included: true)) }
        let merged = try await ActivityLibrary.assembleRoutes([a,b,c,d], seeds: [], decisions: separate + included + [merge], minimumOutings: 2)
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
    @Test func fiveConfirmedOutingsAndRegionalNames() async throws {
        var outings = ["a", "b", "c", "d", "e"].map { input($0) }
        for i in outings.indices { outings[i].locality = "Brookline" }
        outings[0].locality = nil // A newer outing can name an older reference.
        let four = try await ActivityLibrary.assembleRoutes(Array(outings.prefix(4)) + [input("z", offset: 14)], seeds: [], decisions: [])
        #expect(four.routes.isEmpty)
        #expect(four.reviews.isEmpty)
        let five = try await ActivityLibrary.assembleRoutes(outings + [input("z", offset: 14)], seeds: [], decisions: [])
        let route = try #require(five.routes.first)
        #expect(route.efforts.count == 5)
        #expect(route.region == "Brookline")
        #expect(route.name == "Brookline 2.0 km Point-to-Point")
        #expect(five.reviews.count == 1)
        #expect(five.reviews.first?.region == "Brookline")
        let renamed = try await ActivityLibrary.assembleRoutes(outings, seeds: [], decisions: [
            RouteDecision(route: outings[0].row.id!, value: .name("Rail Trail"))
        ])
        #expect(renamed.routes.first?.name == "Rail Trail")
        var elsewhere = ["f", "g", "h", "i", "j"].map { input($0, offset: 1000) }
        for i in elsewhere.indices { elsewhere[i].locality = "Cambridge" }
        let regions = try await ActivityLibrary.assembleRoutes(outings + elsewhere, seeds: [], decisions: [])
        #expect(Set(regions.routes.map(\.region)) == ["Brookline", "Cambridge"])
    }

    @Test func earlyNoisyRecordingDoesNotBlockFiveConsistentOutings() async throws {
        let noisy = input("a", offset: 14)
        let consistent = ["b", "c", "d", "e", "f"].map { input($0) }
        let catalog = try await ActivityLibrary.assembleRoutes([noisy] + consistent, seeds: [], decisions: [])
        #expect(catalog.routes.count == 1)
        #expect(catalog.routes.first?.efforts.count == 5)
        #expect(catalog.reviews.count == 1)
        #expect(catalog.reviews.first?.activity.id == noisy.row.id)
    }

    @Test func localDriftJoinsButSustainedParallelTrackNeedsReview() async throws {
        let base = input("a")
        var drift = input("b").track
        for i in 40...50 { drift.points[i].coordinate.latitude += 14 / 111_195 }
        let reference = try #require(RouteReference(track: base.track))
        #expect(RouteMatcher.match(drift, against: [reference]).first?.outcome == .join)
        #expect(RouteMatcher.match(input("c", offset: 14).track, against: [reference]).first?.outcome == .manualReview)
        #expect(RouteMatcher.match(input("d", reverse: true).track, against: [reference]).isEmpty)
    }

    @Test func cancelledMatchingStopsBeforeProducingACatalog() async throws {
        let inputs = [input("a"), input("b")]
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ActivityLibrary.assembleRoutes(inputs, seeds: [], decisions: [], minimumOutings: 2)
        }
        do {
            _ = try await task.value
            Issue.record("Cancelled route matching returned a catalog")
        } catch is CancellationError { }
    }

    actor CachedResults {
        var values: [RouteCatalog] = []
        func append(_ catalog: RouteCatalog) { values.append(catalog) }
    }

    @Test func cachePreviewDistinguishesMissFromValidEmptyAndInvalidatesUpgrade() async throws {
        let previews = CachedResults()
        let library = try temporary.open()
        _ = try await library.routes(includeOlderHistory: true) { await previews.append($0) }
        #expect(await previews.values.isEmpty)
        let reopened = try temporary.open()
        _ = try await reopened.routes(includeOlderHistory: true) { await previews.append($0) }
        #expect(await previews.values.count == 1)
        #expect(await previews.values.first?.routes.isEmpty == true)
        var versions = PipelineVersions.current
        versions.streamRules += 1
        let upgraded = try temporary.open(versions: versions)
        _ = try await upgraded.routes(includeOlderHistory: true) { await previews.append($0) }
        #expect(await previews.values.count == 1)
    }

    @Test func emptyCatalogPersistsAndAlgorithmUpgradeInvalidatesCache() async throws {
        let library = try temporary.open()
        #expect(try await library.routes(includeOlderHistory: true).routes.isEmpty)
        let original = try #require(await library.routeCatalogCache)
        let reopened = try temporary.open()
        #expect(try await reopened.routes(includeOlderHistory: true).routes.isEmpty)
        #expect(await reopened.routeCatalogCache?.key == original.key)
        var versions = PipelineVersions.current
        versions.streamRules += 1
        let upgraded = try temporary.open(versions: versions)
        #expect(try await upgraded.routes(includeOlderHistory: true).routes.isEmpty)
        #expect(await upgraded.routeCatalogCache?.key != original.key)
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
        for day in 2...4 {
            var outing = repeated
            let extra = Double(day) * 86400 * 7
            outing.stated.start = outing.stated.start?.addingTimeInterval(extra)
            outing.stated.end = outing.stated.end?.addingTimeInterval(extra)
            for i in outing.stream.samples.indices { outing.stream.samples[i].timestamp += extra }
            for i in outing.timerEvents.indices { outing.timerEvents[i].timestamp += extra }
            try await library.importHealthSnapshot(HealthSnapshot(workoutID: UUID(), activity: outing, sourceName: "Fixture", sourceBundleIdentifier: "test.routes"))
        }
        let route = try #require(try await library.routes(includeOlderHistory: true).routes.first)
        #expect(route.efforts.count == 5)
        let inspection = try await library.inspectRoute(activity: route.referenceID, against: route)
        #expect(!inspection.coordinates.isEmpty)
        #expect(inspection.shortlisted)
        #expect(inspection.measures?.failedMeasures().isEmpty == true)
        #expect(inspection.explicitMembership == nil)
        var extendedReference = route
        extendedReference.reference.signature.length *= 1.2
        let separate = try await library.inspectRoute(activity: route.referenceID, against: extendedReference)
        #expect(!separate.detection.distanceWithinTolerance)
        #expect(!separate.shortlisted)
        #expect(separate.measures == nil)
        #expect(route.efforts.allSatisfy { $0.elapsedTime != nil })
        let boundary = Calendar(identifier: .gregorian).date(byAdding: .year, value: 2, to: first.activity.start)!
        #expect(try await library.routes(now: boundary).routes.count == 1)
        #expect(try await library.routes(now: boundary.addingTimeInterval(1)).routes.isEmpty)
        #expect(try await library.routes(includeOlderHistory: true, now: boundary.addingTimeInterval(1)).routes.count == 1)
        #expect(try await library.routes(now: boundary.addingTimeInterval(60 * 86400)).routes.isEmpty)
        _ = try await library.routes(includeOlderHistory: true)
        let cacheURL = temporary.root.appending(path: "LocalMetadata/route-catalog-v1.json")
        let savedData = try Data(contentsOf: cacheURL)
        let saved = try JSONDecoder().decode(RouteCatalogCache.self, from: savedData)
        #expect(saved.catalog.routes.first?.efforts.count == 5)
        // A marker timestamp proves both warm visits and a fresh library reuse the file.
        let marker = Date(timeIntervalSince1970: 1_000_000)
        try FileManager.default.setAttributes([.modificationDate: marker], ofItemAtPath: cacheURL.path)
        #expect(try await library.routes(includeOlderHistory: true).routes.first?.best == route.best)
        let previewLibrary = try temporary.open()
        let previews = CachedResults()
        let previewTask = Task {
            try await previewLibrary.routes(includeOlderHistory: true) { catalog in
                await previews.append(catalog)
                // Stopping here proves the populated catalog is delivered before
                // the remaining metric refresh, not just alongside final completion.
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
        do {
            _ = try await previewTask.value
            Issue.record("Preview cancellation should stop the refresh")
        } catch is CancellationError { }
        #expect(await previews.values.first?.routes.first?.efforts.count == 5)
        #expect(await previews.values.first?.routes.first?.best == route.best)
        let cachedLibrary = try temporary.open()
        #expect(try await cachedLibrary.routes(includeOlderHistory: true).routes.first?.best == route.best)
        #expect(try FileManager.default.attributesOfItem(atPath: cacheURL.path)[.modificationDate] as? Date == marker)
        #expect(await cachedLibrary.routeCatalogCache?.key == saved.key)
        // Geocoding changes names and effort rows, but must reuse persisted geometry.
        let request = try #require(try await library.localityRequest(for: first.activity.id!))
        #expect(try await library.setLocality("Cambridge", for: request))
        let localized = try #require(try await library.routes(includeOlderHistory: true).routes.first)
        #expect(localized.region == "Cambridge")
        #expect(localized.name.hasPrefix("Cambridge "))
        #expect(localized.efforts.first(where: { $0.id == first.activity.id! })?.activity.title.contains("Cambridge") == true)
        #expect(await library.routeCatalogCache?.key == saved.key)
        #expect(try FileManager.default.attributesOfItem(atPath: cacheURL.path)[.modificationDate] as? Date == marker)
        let localizedReopen = try temporary.open()
        #expect(try await localizedReopen.routes(includeOlderHistory: true).routes.first?.name == localized.name)
        try await library.decideRoute(route.id, value: .name("Fixture course"), includeOlderHistory: true)
        #expect(try await library.routes(includeOlderHistory: true).routes.first?.name == "Fixture course")
        #expect(await library.routeCatalogCache?.key != saved.key)
        // Corrupt disposable data is repaired on the next open.
        try Data("broken cache".utf8).write(to: cacheURL)
        let repaired = try temporary.open()
        #expect(try await repaired.routes(includeOlderHistory: true).routes.first?.name == "Fixture course")
        #expect((try? JSONDecoder().decode(RouteCatalogCache.self, from: Data(contentsOf: cacheURL))) != nil)
        let reopened = try temporary.open()
        var noGPS = health
        for i in noGPS.activity.stream.samples.indices { noGPS.activity.stream.samples[i].position = nil }
        try await reopened.importHealthSnapshot(noGPS)
        let invalidatedPreviews = CachedResults()
        let revised = try await reopened.routes(includeOlderHistory: true) { await invalidatedPreviews.append($0) }
        #expect(revised.routes.isEmpty)
        #expect(await invalidatedPreviews.values.isEmpty)
        try await reopened.importHealthSnapshot(health)
        _ = try await reopened.recompute()
        #expect(try await reopened.routes(includeOlderHistory: true).routes.first?.name == "Fixture course")
        try await reopened.decide(.hidden(true), for: first.activity.id!)
        #expect(try await reopened.routes(includeOlderHistory: true).routes.isEmpty)
        try await reopened.decide(.hidden(false), for: first.activity.id!)
        #expect(try await reopened.routes(includeOlderHistory: true).routes.first?.name == "Fixture course")
        try await reopened.permanentlyDelete(health.identity)
        #expect(try await reopened.routes(includeOlderHistory: true).routes.isEmpty)
        let excluded = try temporary.root.appending(path: "LocalMetadata").resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(excluded.isExcludedFromBackup == true)
    }
}
