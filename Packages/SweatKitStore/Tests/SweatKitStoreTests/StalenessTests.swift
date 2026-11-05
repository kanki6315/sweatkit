import Foundation
import SweatKitModel
import SweatKitStore
import Testing

/// Three activities, on days 50, 150 and 250, each with a stream-derived
/// summary that reads no profile, and zones that read the threshold power in
/// effect on its day.
struct StalenessLibrary {
    static let summaryKind = "summary"
    static let zonesKind = "zones"
    static let heartRateKind = "heartRateZones"
    static let summaryVersion = 4
    static let zonesVersion = 2
    static let heartRateVersion = 1
    static let activityDays: [Double] = [50, 150, 250]

    /// Threshold power 240 W from day 100, then 260 W from day 200. Day 50
    /// has none.
    static let profile = AthleteProfile(
        thresholdPowerHistory: [
            .init(effectiveFrom: day(100), watts: 240),
            .init(effectiveFrom: day(200), watts: 260),
        ],
        maxHeartRate: 190,
        weight: 70
    )

    let library = TemporaryLibrary()
    let store: LibraryStore
    let owners: [ResultOwner]

    init() async throws {
        store = try library.open()
        try await store.saveProfile(Self.profile)
        var owners: [ResultOwner] = []
        for (index, offset) in Self.activityDays.enumerated() {
            let id = garmin(index + 1)
            let revision = try await storeGarminRecord(index + 1, in: store)
            try await store.saveActivity(ActivityRecord(members: [id], primary: id, sport: .cycling, start: day(offset), elapsedTime: 3_600, title: "Ride \(index)"))
            let owner = ResultOwner.activity(id)
            owners.append(owner)
            try await store.saveDerivedResult(DerivedResult(
                owner: owner,
                kind: Self.summaryKind,
                provenance: Provenance(inputRevision: revision, algorithmVersion: Self.summaryVersion),
                payload: Data("summary \(index)".utf8),
                computedAt: referenceDate
            ))
            let powerReading = ProfileReading(date: day(offset), inputs: .thresholdPower)
            try await store.saveDerivedResult(DerivedResult(
                owner: owner,
                kind: Self.zonesKind,
                provenance: Provenance(
                    inputRevision: revision,
                    profileFingerprint: Self.profile.fingerprint(on: powerReading.date, reading: powerReading.inputs),
                    algorithmVersion: Self.zonesVersion
                ),
                profileReading: powerReading,
                payload: Data("zones \(index)".utf8),
                computedAt: referenceDate
            ))
            let heartReading = ProfileReading(date: day(offset), inputs: [.thresholdHeartRate, .maxHeartRate])
            try await store.saveDerivedResult(DerivedResult(
                owner: owner,
                kind: Self.heartRateKind,
                provenance: Provenance(
                    inputRevision: revision,
                    profileFingerprint: Self.profile.fingerprint(on: heartReading.date, reading: heartReading.inputs),
                    algorithmVersion: Self.heartRateVersion
                ),
                profileReading: heartReading,
                payload: Data("hr \(index)".utf8),
                computedAt: referenceDate
            ))
        }
        self.owners = owners
    }

    func stale(
        _ kind: String,
        version: Int? = nil,
        profile: AthleteProfile = StalenessLibrary.profile
    ) async throws -> [StaleResult] {
        let current = [
            Self.summaryKind: Self.summaryVersion,
            Self.zonesKind: Self.zonesVersion,
            Self.heartRateKind: Self.heartRateVersion,
        ]
        return try await store.staleResults(
            kind: kind,
            algorithmVersion: version ?? current[kind] ?? 0,
            profile: profile,
            inputRevisions: try await store.activityInputRevisions()
        )
    }

    var allKinds: [String] { [Self.summaryKind, Self.zonesKind, Self.heartRateKind] }
}

@Suite struct StalenessTests {
    @Test func freshResultsAreNotStale() async throws {
        let library = try await StalenessLibrary()
        for kind in library.allKinds {
            #expect(try await library.stale(kind).isEmpty)
        }
    }

    @Test func anAlgorithmVersionChangeStalesEverythingThatAlgorithmProduced() async throws {
        let library = try await StalenessLibrary()

        let stale = try await library.stale(StalenessLibrary.zonesKind, version: StalenessLibrary.zonesVersion + 1)

        #expect(stale == library.owners.map { StaleResult(owner: $0, kind: StalenessLibrary.zonesKind, reasons: [.algorithm]) })
        #expect(try await library.stale(StalenessLibrary.summaryKind).isEmpty)
        #expect(try await library.stale(StalenessLibrary.heartRateKind).isEmpty)
    }

    @Test func aNewRevisionStalesThatActivityOnly() async throws {
        let library = try await StalenessLibrary()
        let oldRevision = try #require(try await library.store.sourceRecord(garmin(2))?.currentRevision)
        try await library.store.saveAnalysisStream(makeShortStream(), for: oldRevision)

        let newRevision = try await storeGarminRecord(2, in: library.store, bytes: "garmin original 2, edited at Garmin")

        for kind in library.allKinds {
            #expect(try await library.stale(kind) == [StaleResult(owner: library.owners[1], kind: kind, reasons: [.input])])
        }
        // The new revision has no stream yet; the old revision's stream is kept.
        #expect(await library.store.analysisStream(for: newRevision, rulesVersion: rulesVersion) == .needsRebuild(.missing))
        #expect(await library.store.analysisStream(for: oldRevision, rulesVersion: rulesVersion).value != nil)
    }

    @Test func aCorrectedPastThresholdStalesOnlyResultsInItsDates() async throws {
        let library = try await StalenessLibrary()
        // The 240 W threshold, in effect from day 100 to day 200, was really 250 W.
        var corrected = StalenessLibrary.profile
        corrected.thresholdPowerHistory[0].watts = 250
        try await library.store.saveProfile(corrected)

        let zones = try await library.stale(StalenessLibrary.zonesKind, profile: corrected)

        #expect(zones == [StaleResult(owner: library.owners[1], kind: StalenessLibrary.zonesKind, reasons: [.profile])])
        // Results that never read threshold power are untouched.
        #expect(try await library.stale(StalenessLibrary.summaryKind, profile: corrected).isEmpty)
        #expect(try await library.stale(StalenessLibrary.heartRateKind, profile: corrected).isEmpty)
    }

    @Test func aThresholdSetForAnEarlierDateStalesTheActivityThatHadNone() async throws {
        let library = try await StalenessLibrary()
        var corrected = StalenessLibrary.profile
        corrected.thresholdPowerHistory.append(.init(effectiveFrom: day(0), watts: 220))

        let zones = try await library.stale(StalenessLibrary.zonesKind, profile: corrected)

        #expect(zones == [StaleResult(owner: library.owners[0], kind: StalenessLibrary.zonesKind, reasons: [.profile])])
    }

    @Test func aProfileChangeThatNoResultReadStalesNothing() async throws {
        let library = try await StalenessLibrary()
        var changed = StalenessLibrary.profile
        changed.weight = 68
        changed.units = .imperial
        // A new threshold from a date after every stored activity.
        changed.thresholdPowerHistory.append(.init(effectiveFrom: day(300), watts: 270))

        for kind in library.allKinds {
            #expect(try await library.stale(kind, profile: changed).isEmpty)
        }
    }

    @Test func aMaxHeartRateChangeStalesOnlyHeartRateResults() async throws {
        let library = try await StalenessLibrary()
        var changed = StalenessLibrary.profile
        changed.maxHeartRate = 186

        #expect(try await library.stale(StalenessLibrary.heartRateKind, profile: changed).count == library.owners.count)
        #expect(try await library.stale(StalenessLibrary.zonesKind, profile: changed).isEmpty)
    }

    @Test func aResultWhoseInputIsGoneIsStale() async throws {
        let library = try await StalenessLibrary()

        let stale = try await library.store.staleResults(
            kind: StalenessLibrary.summaryKind,
            algorithmVersion: StalenessLibrary.summaryVersion + 1,
            profile: StalenessLibrary.profile,
            inputRevisions: [:]
        )

        #expect(stale.count == library.owners.count)
        #expect(stale.allSatisfy { $0.reasons == [.algorithm, .input] })
    }

    @Test func savingAgainReplacesTheResult() async throws {
        let library = try await StalenessLibrary()
        let owner = library.owners[0]
        let revision = try #require(try await library.store.activityInputRevisions()[owner])
        let replacement = DerivedResult(
            owner: owner,
            kind: StalenessLibrary.summaryKind,
            provenance: Provenance(inputRevision: revision, algorithmVersion: StalenessLibrary.summaryVersion + 1),
            payload: Data("new summary".utf8),
            computedAt: day(1)
        )

        try await library.store.saveDerivedResult(replacement)

        #expect(try await library.store.derivedResult(owner: owner, kind: StalenessLibrary.summaryKind) == replacement)
        #expect(try await library.store.derivedResults(owner: owner).map(\.kind) == [StalenessLibrary.heartRateKind, StalenessLibrary.summaryKind, StalenessLibrary.zonesKind])
        let stale = try await library.stale(StalenessLibrary.summaryKind, version: StalenessLibrary.summaryVersion + 1)
        #expect(stale.map(\.owner) == [library.owners[1], library.owners[2]])
    }

    @Test func aProfileReadingNeedsAFingerprint() async throws {
        let library = TemporaryLibrary()
        let store = try library.open()
        let revision = try await storeGarminRecord(1, in: store)
        let missingFingerprint = DerivedResult(
            owner: .activity(garmin(1)),
            kind: "zones",
            provenance: Provenance(inputRevision: revision, algorithmVersion: 1),
            profileReading: ProfileReading(date: referenceDate),
            payload: Data(),
            computedAt: referenceDate
        )
        await #expect(throws: StoreError.inconsistentProvenance) {
            try await store.saveDerivedResult(missingFingerprint)
        }
    }
}
