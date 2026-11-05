import Foundation
import SweatKitIdentity
import SweatKitLibrary
import SweatKitModel
import SweatKitStore
import SweatKitTestSupport
import Testing

@Suite struct IdentityIntegrationTests {
    let temporary = TemporaryLibrary()
    let first = SourceIdentity(source: .garmin, externalID: "101")
    let second = SourceIdentity(source: .garmin, externalID: "102")

    @Test func overlappingImportsMergeAndSplitWithoutLosingOriginals() async throws {
        let library = try temporary.open()
        let bytes = try Fixtures.FIT.outdoorRide.data()
        try await library.importFile(bytes, as: first)
        let result = try await library.importFile(bytes, as: second)
        #expect(Set(result.activity.members) == [first, second])
        #expect(try await library.feed(limit: 10).activities.count == 1)
        try await library.decide(.title("Sunday ride"), for: first)
        try await library.split(first)
        let rows = try await library.feed(limit: 10).activities
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.title == "Sunday ride" && $0.members.count == 1 })
        #expect(try await library.store.original(ContentHash(of: bytes)) == bytes)
        // A third matching record cannot bridge a user separation.
        try await library.importFile(bytes, as: .init(source: .garmin, externalID: "103"))
        let after = try await library.feed(limit: 10).activities
        #expect(after.count == 2)
        #expect(after.allSatisfy { !($0.members.contains(first) && $0.members.contains(second)) })
    }

    @Test func decisionsAndGroupsSurviveRestart() async throws {
        do {
            let library = try temporary.open()
            let bytes = try Fixtures.FIT.outdoorRide.data()
            try await library.importFile(bytes, as: first)
            try await library.importFile(bytes, as: second)
            try await library.decide(.primary(second), for: first)
            try await library.decide(.title("Chosen title"), for: first)
            try await library.decide(.hidden(true), for: first, at: Date(timeIntervalSince1970: 100))
        }
        let reopened = try temporary.open()
        #expect(try await reopened.feed(limit: 10).activities.isEmpty)
        try await reopened.decide(.hidden(false), for: first, at: Date(timeIntervalSince1970: 101))
        let row = try #require(try await reopened.feed(limit: 10).activities.first)
        #expect(row.title == "Chosen title")
        #expect(row.primary == second)
        #expect(Set(row.members) == [first, second])
        #expect(try await reopened.analysisStream(for: first).count > 0)
    }

    @Test func userSeparationWinsOverLaterAutomaticMatching() async throws {
        let library = try temporary.open()
        let bytes = try Fixtures.FIT.outdoorRide.data()
        try await library.importFile(bytes, as: first)
        try await library.link(IdentityPair(first, second), kind: .keepSeparate)
        try await library.importFile(bytes, as: second)
        #expect(try await library.feed(limit: 10).activities.count == 2)
        try await library.link(IdentityPair(first, second), kind: .sameActivity)
        #expect(try await library.feed(limit: 10).activities.count == 1)
    }
    @Test func offlineSplitAndConcurrentRenameHideConverge() async throws {
        let other = TemporaryLibrary()
        defer { withExtendedLifetime(other) {} }
        let left = try temporary.open()
        let right = try other.open()
        let bytes = try Fixtures.FIT.outdoorRide.data()
        for library in [left, right] {
            try await library.importFile(bytes, as: first)
            try await library.importFile(bytes, as: second)
        }
        try await left.decide(.title("Original title"), for: first, at: Date(timeIntervalSince1970: 1))
        try await right.applyIdentityChanges(left.identityChanges())
        try await left.split(first, at: Date(timeIntervalSince1970: 2))
        try await right.decide(.title("Later title"), for: first, at: Date(timeIntervalSince1970: 3))
        try await right.decide(.hidden(true), for: first, at: Date(timeIntervalSince1970: 4))
        let leftChanges = try await left.identityChanges()
        let rightChanges = try await right.identityChanges()
        try await left.applyIdentityChanges(rightChanges)
        try await right.applyIdentityChanges(IdentityChanges(links: leftChanges.links.reversed(),
            decisions: leftChanges.decisions.reversed(), tombstones: leftChanges.tombstones.reversed()))
        let leftRows = try await left.hiddenActivities()
        let rightRows = try await right.hiddenActivities()
        #expect(Set(leftRows) == Set(rightRows))
        #expect(leftRows.count == 2)
        #expect(leftRows.allSatisfy { $0.title == "Later title" && $0.isHidden && $0.members.count == 1 })
        #expect(try await left.feed(limit: 10).activities.isEmpty)
        #expect(try await right.feed(limit: 10).activities.isEmpty)
    }

}
