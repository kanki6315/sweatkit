import Foundation
import SweatKitModel
import SweatKitStore
import SweatKitAnalysis
import SweatKitRouteMatching
import SweatKitTrackCleanup

public struct RouteEffort: Sendable, Identifiable {
    public let activity: ActivityRecord
    public let alignment: Alignment
    public let metrics: ActivityMetrics?
    public var id: SourceIdentity { activity.id! }
    public var movingTime: Double? { alignment.sectionTimes(clock: .moving).value?.duration }
    public var elapsedTime: Double? { alignment.sectionTimes(clock: .elapsed).value?.duration }
}
public struct LibraryRoute: Sendable, Identifiable {
    public let id: SourceIdentity
    public var name: String
    public var referenceID: SourceIdentity
    public var reference: RouteReference
    public var efforts: [RouteEffort]
    public var ranked: [RouteEffort] {
        efforts.filter { $0.movingTime != nil }.sorted {
            if $0.movingTime == $1.movingTime { return $0.id < $1.id }
            return $0.movingTime! < $1.movingTime!
        }
    }
    public var best: Double? { ranked.first?.movingTime }
    public var median: Double? {
        let times = ranked.compactMap(\.movingTime)
        guard !times.isEmpty else { return nil }
        return (times[(times.count - 1) / 2] + times[times.count / 2]) / 2
    }
    public func rank(of id: SourceIdentity) -> Int? {
        guard let time = efforts.first(where: { $0.activity.members.contains(id) })?.movingTime else { return nil }
        return 1 + ranked.filter { $0.movingTime! < time }.count
    }
}
public struct RouteReview: Sendable, Identifiable {
    public let routeID: SourceIdentity
    public let routeName: String
    public let activity: ActivityRecord
    public let measures: AlignmentMeasures
    public var id: String { "\(routeID)-\(activity.id!)" }
    public var explanation: String {
        "Matches \(routeName), but needs review: a stretch runs \(Int(abs(measures.worstSideOffset))) m to the side; \(Int(measures.proximity * 100))% within 30 m; \(Int(measures.coverage * 100))% coverage. Check for parallel roads, detours or another matching route."
    }
}
public struct RouteCatalog: Sendable {
    public var routes: [LibraryRoute]
    public var reviews: [RouteReview]
    public init(routes: [LibraryRoute], reviews: [RouteReview]) { self.routes = routes; self.reviews = reviews }
    public func membership(of activity: SourceIdentity) -> LibraryRoute? {
        routes.first { $0.efforts.contains { $0.activity.members.contains(activity) } }
    }
}

struct RouteInput: Sendable {
    let row: ActivityRecord
    let track: CleanedTrack
    let metrics: ActivityMetrics?
}
struct RouteSeed: Codable {
    var id: SourceIdentity
    var members: [SourceIdentity]
}

extension ActivityLibrary {
    private var routeDecisionURL: URL { store.root.appending(path: "route-decisions-v1.json") }
    private var routeSeedURL: URL { store.root.appending(path: "LocalMetadata/route-groups-v1.json") }

    static let routeCloudNamespace = "sweatkit.route-decisions.v1"

    static func routeDecision(from envelope: CloudDecisionEnvelope) throws -> RouteDecision? {
        guard envelope.namespace == routeCloudNamespace, envelope.version == 1 else { return nil }
        let decision = try JSONDecoder().decode(RouteDecision.self, from: envelope.payload)
        guard decision.id == envelope.id, decision.date == envelope.time else { throw CocoaError(.coderReadCorrupt) }
        return decision
    }

    public func routeDecisions() throws -> RouteDecisionExport {
        let local = FileManager.default.fileExists(atPath: routeDecisionURL.path)
            ? try JSONDecoder().decode(RouteDecisionExport.self, from: Data(contentsOf: routeDecisionURL)) : .init(decisions: [])
        guard local.version == 1 else { throw CocoaError(.coderReadCorrupt) }
        var records: [UUID: RouteDecision] = [:]
        let remote = try cloudDecisions(namespace: Self.routeCloudNamespace).compactMap { try Self.routeDecision(from: $0) }
        for decision in local.decisions + remote {
            if let old = records[decision.id], old != decision { throw CocoaError(.coderReadCorrupt) }
            records[decision.id] = decision
        }
        return .init(decisions: records.values.sorted { ($0.date, $0.id.uuidString) < ($1.date, $1.id.uuidString) })
    }
    /// Cloud stores this payload under `sweatkit.route-decisions.v1` without interpreting it.
    public func exportRouteDecisionPayload() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(routeDecisions())
    }
    /// Additive union; unknown versions or conflicting UUID reuse fail without replacing local intent.
    public func applyRouteDecisionPayload(_ payload: Data) throws {
        try applyRouteDecisions(JSONDecoder().decode(RouteDecisionExport.self, from: payload))
    }
    public func applyRouteDecisions(_ incoming: RouteDecisionExport) throws {
        guard incoming.version == 1 else { throw CocoaError(.coderReadCorrupt) }
        let existing = try routeDecisions().decisions
        // UUID conflicts are rejected instead of silently replacing already recorded intent.
        var records = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for decision in incoming.decisions {
            if let old = records[decision.id], old != decision { throw CocoaError(.coderReadCorrupt) }
            records[decision.id] = decision
        }
        let sorted = records.values.sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date }
        try JSONEncoder().encode(RouteDecisionExport(decisions: sorted)).write(to: routeDecisionURL, options: .atomic)
    }
    public func decideRoute(_ route: SourceIdentity, value: RouteDecision.Value) async throws {
        var additional: [RouteDecision] = []
        let current = try await routes()
        let anchors = current.routes.first(where: { $0.id == route })?.efforts.map(\.id)
        if case .merge(let source) = value {
            let catalog = current
            guard let target = catalog.routes.first(where: { $0.id == route }),
                  let other = catalog.routes.first(where: { $0.id == source }), source != route else {
                throw RouteEditError.unavailable
            }
            for effort in other.efforts {
                let stream = try await analysisStream(for: effort.id)
                let track = await Self.routeTrack(stream, row: effort.activity)
                guard let match = RouteMatcher.match(track, against: [target.reference]).first,
                      match.outcome != .reject else { throw RouteEditError.incompatible }
                additional.append(RouteDecision(route: route, value: .membership(activity: effort.id, included: true)))
            }
        }
        if case .reference(let activity) = value {
            let catalog = current
            guard catalog.routes.first(where: { $0.id == route })?.efforts.contains(where: { $0.id == activity }) == true else {
                throw RouteEditError.unavailable
            }
        }
        try applyRouteDecisions(.init(decisions: additional + [.init(route: route, value: value, anchors: anchors)]))
    }

    /// Complete library query, independent of feed pagination. Geometry is rebuilt from current
    /// primary revisions, never exported. Hidden/deleted activities cannot participate.
    public func routes() async throws -> RouteCatalog {
        try Task.checkCancellation()
        let sourceSnapshot = try await store.sourceRecords()
        var rows: [ActivityRecord] = []
        var cursor: FeedCursor?
        repeat {
            let page = try await feed(limit: 256, after: cursor)
            rows += page.activities.filter { !$0.isHidden && $0.sport.hasFullSupport && (!$0.isIndoor || $0.isVirtual) }
            cursor = page.next
        } while cursor != nil
        var inputs: [RouteInput] = []
        for row in rows.sorted(by: { $0.start == $1.start ? $0.id! < $1.id! : $0.start < $1.start }) {
            try Task.checkCancellation()
            let stream = try await analysisStream(for: row.id!)
            let track = await Self.routeTrack(stream, row: row)
            guard RouteReference(track: track) != nil else { continue }
            inputs.append(RouteInput(row: row, track: track, metrics: try await metrics(for: row.id!)))
        }
        let decisions = try routeDecisions().decisions
        let seeds = FileManager.default.fileExists(atPath: routeSeedURL.path)
            ? try JSONDecoder().decode([RouteSeed].self, from: Data(contentsOf: routeSeedURL)) : []
        let result = await Self.assembleRoutes(inputs, seeds: seeds, decisions: decisions)
        try Task.checkCancellation()
        guard try await store.sourceRecords() == sourceSnapshot else { return try await routes() }
        for input in inputs {
            guard try await activity(input.row.id!) == input.row else { return try await routes() }
        }
        guard try routeDecisions().decisions == decisions else { return try await routes() }
        // Membership hints preserve route IDs when the first effort is hidden. They carry no geometry.
        // Retain dormant groups too, so restoring an effort restores its route's name and decisions.
        var saved = Dictionary(uniqueKeysWithValues: seeds.map { ($0.id, $0) })
        for route in result.routes { saved[route.id] = RouteSeed(id: route.id, members: route.efforts.map(\.id)) }
        try JSONEncoder().encode(saved.values.sorted { $0.id < $1.id }).write(to: routeSeedURL, options: .atomic)
        return result
    }

    nonisolated static func routeTrack(_ stream: AnalysisStream, row: ActivityRecord) async -> CleanedTrack {
        let clean = TrackCleanup.clean(stream, sport: row.sport)
        var moving = [Double](repeating: 0, count: stream.count + 1)
        var paused = Set<Int>()
        if case .known(let spans) = stream.pauses { for span in spans { paused.formUnion(span) } }
        let floor = row.sport.family == .cycling ? AnalysisRules.movingSpeedFloorCycling : AnalysisRules.movingSpeedFloorOnFoot
        for second in 0..<stream.count {
            let stopped = !row.isIndoor && (stream.speed[second].map { $0 < floor } ?? false)
            moving[second + 1] = moving[second] + (paused.contains(second) || stopped ? 0 : 1)
        }
        return CleanedTrack(points: clean.points.flatMap { position -> [TrackPoint] in
            let first = TrackPoint(coordinate: position.coordinate, elapsedTime: Double(position.sampleIndex), movingTime: moving[position.sampleIndex])
            let last = position.coveredSamples.upperBound
            guard last > position.sampleIndex else { return [first] }
            return [first, TrackPoint(coordinate: position.coordinate, elapsedTime: Double(last), movingTime: moving[last])]
        }, sportFamily: row.sport.family, pausePositionsAreReliable: clean.pausePositionsAreReliable)
    }

    nonisolated static func assembleRoutes(_ inputs: [RouteInput], seeds: [RouteSeed], decisions: [RouteDecision]) async -> RouteCatalog {
        // A paged feed may overlap while an import changes ordering. Never count an effort twice.
        var uniqueInputs: [SourceIdentity: RouteInput] = [:]
        for input in inputs { uniqueInputs[input.row.id!] = input }
        let orderedInputs: [RouteInput] = uniqueInputs.values.sorted {
            $0.row.start == $1.row.start ? $0.row.id! < $1.row.id! : $0.row.start < $1.row.start
        }
        var groups: [LibraryRoute] = []
        var reviews: [RouteReview] = []
        var byID: [SourceIdentity: RouteInput] = [:]
        for input in orderedInputs { for member in input.row.members { byID[member] = input } }
        func excluded(_ activity: SourceIdentity, _ route: SourceIdentity) -> Bool {
            let aliases = Set(byID[activity]?.row.members ?? [activity])
            return decisions.last { decision in
                guard decision.route == route else { return false }
                if case .membership(let id, _) = decision.value { return aliases.contains(id) }; return false
            }.map { if case .membership(_, let included) = $0.value { return !included }; return false } ?? false
        }
        func makeGroup(_ input: RouteInput, id: SourceIdentity) -> LibraryRoute {
            var referenceInput = input
            for d in decisions where d.route == id {
                if case .reference(let choice) = d.value, let found = byID[choice], !excluded(choice, id),
                   RouteMatcher.match(found.track, against: [RouteReference(track: input.track)!]).first.map({ $0.outcome != .reject }) == true {
                    referenceInput = found
                }
            }
            let reference = RouteReference(track: referenceInput.track)!
            let name = decisions.compactMap { d -> String? in
                if d.route == id, case .name(let name) = d.value { return name }; return nil
            }.last ?? referenceInput.row.title
            return LibraryRoute(id: id, name: name, referenceID: referenceInput.row.id!, reference: reference, efforts: [])
        }
        var anchoredSeeds = Dictionary(uniqueKeysWithValues: seeds.map { ($0.id, $0) })
        for decision in decisions {
            var hints = decision.anchors ?? []
            if case .reference(let id) = decision.value { hints.append(id) }
            if case .membership(let id, true) = decision.value { hints.append(id) }
            guard !hints.isEmpty else { continue }
            let previous = anchoredSeeds[decision.route]?.members ?? []
            anchoredSeeds[decision.route] = RouteSeed(id: decision.route, members: Array(Set(previous + hints)).sorted())
        }
        for seed in anchoredSeeds.values.sorted(by: { $0.id < $1.id }) {
            if let input = ([seed.id] + seed.members).compactMap({ byID[$0] }).first(where: { !excluded($0.row.id!, seed.id) }) {
                groups.append(makeGroup(input, id: seed.id))
            }
        }
        for input in orderedInputs {
            let id = input.row.id!
            let matches = RouteMatcher.match(input.track, against: groups.map(\.reference))
            let allowed = matches.filter { !excluded(id, groups[$0.routeIndex].id) && $0.outcome != .reject }
            let manual = decisions.last { d in
                if case .membership(let activity, let included) = d.value { return input.row.members.contains(activity) && included }; return false
            }
            let own = groups.firstIndex { $0.referenceID == id && !excluded(id, $0.id) }
            let joins = allowed.filter { $0.measures.outcome() == .join }
            let selected: Int?
            if let manual, let match = allowed.first(where: { groups[$0.routeIndex].id == manual.route }) { selected = match.routeIndex }
            else if let own { selected = own }
            else if joins.count == 1 { selected = joins[0].routeIndex }
            else { selected = nil }
            if let selected {
                let alignment = RouteAlignment.align(input.track, to: groups[selected].reference.line)
                groups[selected].efforts.append(RouteEffort(activity: input.row, alignment: alignment, metrics: input.metrics))
            } else if !allowed.isEmpty {
                reviews += allowed.map { RouteReview(routeID: groups[$0.routeIndex].id, routeName: groups[$0.routeIndex].name, activity: input.row, measures: $0.measures) }
            } else if !groups.contains(where: { $0.id == id }) {
                var group = makeGroup(input, id: id)
                let alignment = RouteAlignment.align(input.track, to: group.reference.line)
                group.efforts = [RouteEffort(activity: input.row, alignment: alignment, metrics: input.metrics)]
                groups.append(group)
            }
        }
        // Manual merge is still constrained to full efforts in the same sport and direction.
        for d in decisions {
            guard case .merge(let source) = d.value,
                  let targetIndex = groups.firstIndex(where: { $0.id == d.route }),
                  let sourceIndex = groups.firstIndex(where: { $0.id == source }), targetIndex != sourceIndex else { continue }
            let target = groups[targetIndex]
            let sourceEfforts = groups[sourceIndex].efforts
            var moved: [RouteEffort] = []
            for effort in sourceEfforts {
                guard let input = byID[effort.id], !excluded(effort.id, target.id),
                      let match = RouteMatcher.match(input.track, against: [target.reference]).first,
                      match.outcome != .reject else { continue }
                moved.append(RouteEffort(activity: effort.activity, alignment: match.alignment, metrics: effort.metrics))
            }
            if moved.count == sourceEfforts.count {
                groups[targetIndex].efforts += moved
                groups[sourceIndex].efforts = []
            }
        }
        return RouteCatalog(routes: groups.filter { $0.efforts.count >= 2 }.sorted {
            ($0.efforts.map(\.activity.start).max() ?? .distantPast) > ($1.efforts.map(\.activity.start).max() ?? .distantPast)
        }, reviews: reviews)
    }
}

public enum RouteEditError: LocalizedError {
    case unavailable, incompatible
    public var errorDescription: String? {
        switch self {
        case .unavailable: "This route or effort is no longer available. Refresh Routes and try again."
        case .incompatible: "These routes cannot merge: every effort must cover the full course in the same direction and sport family."
        }
    }
}
