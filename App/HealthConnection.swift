import Foundation
import HealthKit
import CoreLocation
import Observation
import Synchronization
import SweatKitLibrary
import SweatKitModel

/// Read-only HealthKit synchronization. Anchors and pending snapshot IDs are
/// committed together, so a failed snapshot is retried after the next launch.
@MainActor @Observable
final class HealthConnection {
    private(set) var running = false
    private(set) var lastSyncSucceeded = false
    private(set) var enabled = false
    private(set) var status = "Connect Apple Health to read your workouts."
    private let health = HKHealthStore()
    private let library: ActivityLibrary
    private let stateURL: URL
    private var backgroundWork: WorkoutBackgroundWork?
    private var syncTask: Task<Void, Never>?

    private typealias State = HealthSyncState
    private struct Page: Sendable {
        var samples: [HKSample]
        var deleted: [HKDeletedObject]
        var anchor: HKQueryAnchor?
    }
    private static let quantities: [HKQuantityTypeIdentifier] = [
        .heartRate, .cyclingPower, .cyclingCadence, .cyclingSpeed, .runningPower, .runningSpeed,
        .distanceWalkingRunning, .distanceCycling, .stepCount,
        .runningStrideLength, .runningGroundContactTime, .runningVerticalOscillation
    ]
    static var observedTypes: [HKSampleType] {
        [HKObjectType.workoutType(), HKSeriesType.workoutRoute()] + quantities.compactMap(HKObjectType.quantityType(forIdentifier:))
    }

    init(library: ActivityLibrary, root: URL) {
        self.library = library
        stateURL = root.appendingPathComponent("health-sync.json")
        enabled = UserDefaults.standard.bool(forKey: "healthReadRequested")
        if enabled { status = "Apple Health is ready to refresh. Read access is controlled in Health settings." }
    }

    func connect() async {
        guard HKHealthStore.isHealthDataAvailable() else { status = "Apple Health isn't available on this device."; return }
        guard !running else { return }
        running = true
        do {
            try await health.requestAuthorization(toShare: [], read: Set(Self.observedTypes))
            var state = try await readState()
            // A schema upgrade needs a backfill. Repeated permission reviews
            // still refresh snapshots (new access may reveal data), but do not
            // replay every unrelated daily measurement.
            if UserDefaults.standard.integer(forKey: "healthReadSchema") < 3 {
                state.anchors = [:]
            }
            // Previously hidden workouts must be rediscovered after access changes.
            state.anchors[HKObjectType.workoutType().identifier] = nil
            state.pending.formUnion(state.workouts.keys)
            try await save(state)
            UserDefaults.standard.set(3, forKey: "healthReadSchema")
            enabled = true
            UserDefaults.standard.set(true, forKey: "healthReadRequested")
            running = false
            HealthBackgroundDelivery.shared.start()
            await sync()
        } catch {
            running = false
            status = "Couldn't request Health access. Open Health → your profile → Apps → SweatKit to review permissions, then retry."
        }
    }

    func pause() {
        syncTask?.cancel()
        HealthBackgroundDelivery.shared.pause()
    }

    func sync(continued: Bool = true, changesCaptured: (@MainActor () -> Void)? = nil) async {
        // A notification may arrive after its type was read by an existing
        // pass. Wait, then fetch again; never acknowledge it using that pass.
        while running {
            guard syncTask != nil else { changesCaptured?(); return }
            // Do not cancel another caller's operation when this observer expires.
            // A cancellable wait also lets an expiring background worker exit promptly.
            do { try await Task.sleep(for: .milliseconds(250)) }
            catch { changesCaptured?(); return }
        }
        guard enabled, !Task.isCancelled, HKHealthStore.isHealthDataAvailable() else { changesCaptured?(); return }
        guard UserDefaults.standard.integer(forKey: "healthReadSchema") >= 3 else {
            status = "Health distance, steps and running form need read access. Tap Review Health access to update permissions and refresh existing workouts."
            changesCaptured?()
            return
        }
        running = true
        lastSyncSucceeded = false
        syncTask = Task { [self] in
            let background = WorkoutBackgroundWork(title: "Processing Health workouts", continued: continued) { [weak self] in
                self?.syncTask?.cancel()
            }
            backgroundWork = background
            defer { backgroundWork = nil }
            await synchronize(changesCaptured: changesCaptured)
            background.finish(success: !Task.isCancelled && lastSyncSucceeded)
        }
        let active = syncTask
        if continued {
            await active?.value
        } else {
            await withTaskCancellationHandler {
                await active?.value
            } onCancel: {
                active?.cancel()
            }
        }
        syncTask = nil
        running = false
    }

    private func synchronize(changesCaptured: (@MainActor () -> Void)? = nil) async {
        // On error/cancellation unchanged anchors and saved pending IDs are
        // retried on foreground activation. Completion does not claim success.
        var acknowledged = false
        defer { if !acknowledged { changesCaptured?() } }
        status = "Reading Apple Health workouts and changes…"
        do {
            var state = try await readState()
            state.refreshSnapshots(forAdapterVersion: 1)
            try await save(state)
            var workoutIndex = HealthWorkoutIndex(state.workouts)
            for type in Self.observedTypes {
                var count: Int
                repeat {
                    try Task.checkCancellation()
                    if pauseForHeat() { return }
                    let anchor = try state.anchors[type.identifier].map {
                        try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0)
                    } ?? nil
                    let page = try await changes(type, after: anchor)
                    count = page.samples.count + page.deleted.count
                    if type == HKObjectType.workoutType() {
                        for sample in page.samples {
                            state.workouts[sample.uuid] = DateInterval(start: sample.startDate, end: sample.endDate)
                            state.pending.insert(sample.uuid)
                        }
                        for deleted in page.deleted {
                            try await library.markHealthWorkoutRemoved(deleted.uuid)
                            state.workouts.removeValue(forKey: deleted.uuid)
                            state.pending.remove(deleted.uuid)
                        }
                    } else {
                        for sample in page.samples {
                            let affected = workoutIndex.overlapping(start: sample.startDate, end: sample.endDate)
                            state.pending.formUnion(affected)
                        }
                        // Deleted objects contain no dates or workout links.
                        // Keep the conservative fallback rather than miss edits.
                        if !page.deleted.isEmpty { state.pending.formUnion(state.workouts.keys) }
                    }
                    if let anchor = page.anchor {
                        state.anchors[type.identifier] = try NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
                    }
                    try await save(state)
                } while count >= 500
                if type == HKObjectType.workoutType() {
                    workoutIndex = HealthWorkoutIndex(state.workouts)
                }
            }
            // Every anchor and its pending snapshot IDs are durable now.
            // Release HealthKit's delivery promptly, before costly derivation.
            changesCaptured?()
            acknowledged = true
            let deleted = try await library.deletedIdentities()
            let skipped = state.pending.filter { deleted.contains(SourceIdentity(source: .healthKit, externalID: $0.uuidString)) }
            state.pending.subtract(skipped)
            for id in skipped { state.workouts.removeValue(forKey: id) }
            try await save(state)
            let pending = state.pending.sorted { $0.uuidString < $1.uuidString }
            var completed = 0
            var failures = 0
            // Bound memory and hold the library writer only while importing.
            // Persist completion after each reconciled batch, never before it.
            for offset in stride(from: 0, to: pending.count, by: 8) {
                try Task.checkCancellation()
                if pauseForHeat() { return }
                let batch = pending[offset..<min(offset + 8, pending.count)]
                var snapshots: [HealthSnapshot] = []
                for id in batch {
                    try Task.checkCancellation()
                    if pauseForHeat() { return }
                    do {
                        guard let workout = try await samples(HKObjectType.workoutType(), predicate: HKQuery.predicateForObject(with: id)).first as? HKWorkout else {
                            failures += 1
                            continue
                        }
                        snapshots.append(try await snapshot(workout))
                    } catch is CancellationError { throw CancellationError() }
                    catch { failures += 1 }
                }
                let imported = try await library.importHealthSnapshots(snapshots)
                failures += snapshots.count - imported.count
                state.pending.subtract(imported)
                try await save(state)
                completed += imported.count
                backgroundWork?.update(completed: completed, total: pending.count)
                status = "Apple Health: processed \(completed) of \(pending.count) workouts."
            }
            if failures > 0 {
                status = "Apple Health processed \(completed) workouts; \(failures) need another attempt. Review read access in Health → profile → Apps → SweatKit, then refresh. Your stored recordings are kept."
            } else if state.workouts.isEmpty {
                status = "No workouts are visible. There may be no workouts, or read access may be off. Review access in Health → profile → Apps → SweatKit, then refresh."
            } else {
                status = "Apple Health is up to date. \(completed) workouts refreshed."
            }
            lastSyncSucceeded = failures == 0
        } catch is CancellationError {
            status = "Health refresh paused. Refresh again to resume saved work."
        } catch {
            status = "Couldn't finish Health refresh. Unlock your device, check available storage and Health read access, then retry. Saved progress is kept."
        }
    }

    private func pauseForHeat() -> Bool {
        let thermal = ProcessInfo.processInfo.thermalState
        guard thermal == .serious || thermal == .critical else { return false }
        status = "Health refresh paused while your phone cools down. Refresh again to resume saved work."
        return true
    }

    private func snapshot(_ workout: HKWorkout) async throws -> HealthSnapshot {
        let sport: Sport
        switch workout.workoutActivityType {
        case .cycling: sport = .cycling
        case .walking: sport = .walking
        case .running: sport = .running
        case .hiking: sport = .hiking
        default: sport = .other
        }
        let predicate = HKQuery.predicateForObjects(from: workout)
        let quantityPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            predicate, HKQuery.predicateForObjects(from: workout.sourceRevision.source)
        ])
        var native: [NativeSample] = []
        for identifier in Self.quantities {
            try Task.checkCancellation()
            // Skip quantities this adapter would discard for this sport anyway.
            let relevant: Bool
            switch identifier {
            case .distanceWalkingRunning, .stepCount: relevant = sport.family == .onFoot
            case .distanceCycling, .cyclingPower, .cyclingSpeed: relevant = sport == .cycling
            case .runningPower, .runningSpeed: relevant = sport != .cycling
            case .runningStrideLength, .runningGroundContactTime, .runningVerticalOscillation: relevant = sport == .running
            default: relevant = true
            }
            guard relevant, let type = HKObjectType.quantityType(forIdentifier: identifier) else { continue }
            let unit: HKUnit
            switch identifier {
            case .distanceWalkingRunning, .distanceCycling, .runningStrideLength, .runningVerticalOscillation: unit = .meter()
            case .runningGroundContactTime: unit = .second()
            case .stepCount: unit = .count()
            case .heartRate, .cyclingCadence: unit = .count().unitDivided(by: .minute())
            case .cyclingPower, .runningPower: unit = .watt()
            default: unit = .meter().unitDivided(by: .second())
            }
            let readings = try await quantities(type, predicate: quantityPredicate, unit: unit)
            if (identifier == .distanceWalkingRunning && sport.family == .onFoot)
                || (identifier == .distanceCycling && sport == .cycling) {
                native += HealthQuantityConversion.distance(readings)
                continue
            }
            if identifier == .stepCount && sport.family == .onFoot {
                native += HealthQuantityConversion.cadence(readings)
                continue
            }
            for reading in readings {
                var point = NativeSample(timestamp: reading.start)
                switch identifier {
                case .heartRate: point.heartRate = reading.value
                case .cyclingCadence: point.cadence = reading.value
                case .cyclingPower where sport == .cycling, .runningPower where sport != .cycling:
                    point.power = reading.value
                case .cyclingSpeed where sport == .cycling, .runningSpeed where sport != .cycling:
                    point.speed = reading.value
                case .runningStrideLength where sport == .running:
                    if reading.value.isFinite && reading.value >= 0 { point.runningStrideLength = reading.value }
                case .runningGroundContactTime where sport == .running:
                    if reading.value.isFinite && reading.value >= 0 { point.runningGroundContactTime = reading.value }
                case .runningVerticalOscillation where sport == .running:
                    if reading.value.isFinite && reading.value >= 0 { point.runningVerticalOscillation = reading.value }
                default: continue
                }
                native.append(point)
            }
        }
        let routes = try await samples(HKSeriesType.workoutRoute(), predicate: predicate)
        for case let route as HKWorkoutRoute in routes {
            for location in try await locations(route) where location.horizontalAccuracy >= 0 {
                native.append(NativeSample(timestamp: location.timestamp,
                    position: Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
                    altitude: location.verticalAccuracy >= 0 ? location.altitude : nil,
                    speed: location.speed >= 0 ? location.speed : nil))
            }
        }
        // Query and route batch ordering is not guaranteed. A stable order
        // prevents unchanged workouts from producing spurious revisions.
        native = await Self.sortedSamples(native)
        let events = (workout.workoutEvents ?? []).compactMap { event -> TimerEvent? in
            switch event.type {
            case .pause, .motionPaused: TimerEvent(kind: .stop, timestamp: event.dateInterval.start)
            case .resume, .motionResumed: TimerEvent(kind: .start, timestamp: event.dateInterval.start)
            default: nil
            }
        }.sorted { $0.timestamp < $1.timestamp }
        let timezone = (workout.metadata?[HKMetadataKeyTimeZone] as? String).flatMap(TimeZone.init(identifier:))
        let workoutSpan = DateInterval(start: workout.startDate, end: workout.endDate)
        let laps = HealthWorkoutIntervals.laps(
            (workout.workoutEvents ?? []).filter { $0.type == .lap }.map(\.dateInterval),
            within: workoutSpan)
        let segments = HealthWorkoutIntervals.segments(
            (workout.workoutEvents ?? []).filter { $0.type == .segment }.map(\.dateInterval),
            within: workoutSpan)
        let activity = RecordedActivity(sport: sport,
            isIndoor: (workout.metadata?[HKMetadataKeyIndoorWorkout] as? Bool) ?? false,
            stated: StatedSummary(start: workout.startDate, end: workout.endDate, timerTime: workout.duration,
                distance: workout.totalDistance?.doubleValue(for: .meter()),
                utcOffset: timezone?.secondsFromGMT(for: workout.startDate)),
            timerEvents: events, laps: laps, segments: segments.isEmpty ? nil : segments,
            stream: NativeStream(samples: native))
        var links: Set<SourceIdentity> = []
        // Only an explicitly namespaced identifier is treated as a link.
        // A bare external UUID or numeric ID is not assumed to be Garmin's.
        if let external = workout.metadata?[HKMetadataKeyExternalUUID] as? String,
           external.hasPrefix("garmin:"), let id = Int64(external.dropFirst(7)), id > 0 {
            links.insert(SourceIdentity(source: .garmin, externalID: String(id)))
        }
        return HealthSnapshot(workoutID: workout.uuid, activity: activity, linkedIdentities: links,
            sourceName: workout.sourceRevision.source.name,
            sourceBundleIdentifier: workout.sourceRevision.source.bundleIdentifier,
            sourceSportName: workout.workoutActivityType == .golf ? "Golf" : nil)
    }

    @concurrent
    private static func sortedSamples(_ samples: [NativeSample]) async -> [NativeSample] {
        samples.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
            return sampleOrder(lhs) < sampleOrder(rhs)
        }
    }

    nonisolated private static func sampleOrder(_ sample: NativeSample) -> String {
        // Stable tie breaker only; values remain native and are never merged.
        [sample.position?.latitude, sample.position?.longitude, sample.altitude,
         sample.distance, sample.speed, sample.heartRate, sample.power, sample.cadence,
         sample.runningStrideLength, sample.runningGroundContactTime, sample.runningVerticalOscillation]
            .map { $0.map { String($0.bitPattern, radix: 16) } ?? "" }.joined(separator: ":")
    }

    private func changes(_ type: HKSampleType, after anchor: HKQueryAnchor?) async throws -> Page {
        try await HealthQueryOperation<Page>(health: health).run { finish in
            HKAnchoredObjectQuery(type: type, predicate: nil, anchor: anchor, limit: 500) { _, samples, deleted, anchor, error in
                if let error { finish(.failure(error)) }
                else { finish(.success(Page(samples: samples ?? [], deleted: deleted ?? [], anchor: anchor))) }
            }
        }
    }

    private func samples(_ type: HKSampleType, predicate: NSPredicate) async throws -> [HKSample] {
        try await HealthQueryOperation<[HKSample]>(health: health).run { finish in
            HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, error in
                if let error { finish(.failure(error)) }
                else { finish(.success(samples ?? [])) }
            }
        }
    }

    /// Read individual entries, including condensed Apple Watch quantities.
    /// Reading only HKQuantitySample.quantity loses their original timestamps.
    private func quantities(_ type: HKQuantityType, predicate: NSPredicate, unit: HKUnit) async throws -> [HealthQuantityInterval] {
        let accumulated = Mutex<[HealthQuantityInterval]>([])
        return try await HealthQueryOperation<[HealthQuantityInterval]>(health: health).run { finish in
            HKQuantitySeriesSampleQuery(quantityType: type, predicate: predicate) { _, quantity, interval, _, done, error in
                if let error { finish(.failure(error)); return }
                let result = accumulated.withLock { values -> [HealthQuantityInterval]? in
                    if let quantity, let interval {
                        values.append(HealthQuantityInterval(start: interval.start, end: interval.end,
                                                             value: quantity.doubleValue(for: unit)))
                    }
                    return done ? values : nil
                }
                if let result { finish(.success(result)) }
            }
        }
    }

    private func locations(_ route: HKWorkoutRoute) async throws -> [CLLocation] {
        let accumulated = Mutex<(points: [CLLocation], finished: Bool)>(([], false))
        return try await HealthQueryOperation<[CLLocation]>(health: health).run { finish in
            HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                let result = accumulated.withLock { state -> Result<[CLLocation], any Error>? in
                    guard !state.finished else { return nil }
                    if let error { state.finished = true; return .failure(error) }
                    state.points += locations ?? []
                    if done { state.finished = true; return .success(state.points) }
                    return nil
                }
                if let result { finish(result) }
            }
        }
    }

    private func readState() async throws -> State { try await Self.loadState(from: stateURL) }
    private func save(_ state: State) async throws { try await Self.saveState(state, to: stateURL) }

    @concurrent private static func loadState(from url: URL) async throws -> State { try State.load(from: url) }
    @concurrent private static func saveState(_ state: State, to url: URL) async throws { try state.save(to: url) }
}

/// Owns one query and resumes its waiter exactly once. HealthKit does not
/// promise a completion callback after stop(_:), so cancellation resumes it.
/// Main-actor serialization covers cancellation before setup and late callbacks.
@MainActor
private final class HealthQueryOperation<Value: Sendable> {
    private let health: HKHealthStore
    private var query: HKQuery?
    private var continuation: CheckedContinuation<Value, any Error>?
    private var cancelled = false

    init(health: HKHealthStore) { self.health = health }

    func run(_ makeQuery: (@escaping @Sendable (Result<Value, any Error>) -> Void) -> HKQuery) async throws -> Value {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                guard !cancelled else { continuation.resume(throwing: CancellationError()); return }
                self.continuation = continuation
                let query = makeQuery { result in
                    Task { @MainActor in self.finish(result) }
                }
                self.query = query
                health.execute(query)
            }
        } onCancel: {
            Task { @MainActor in self.cancel() }
        }
    }

    private func cancel() {
        cancelled = true
        if let query { health.stop(query) }
        finish(.failure(CancellationError()))
    }

    private func finish(_ result: Result<Value, any Error>) {
        guard let continuation else { return }
        self.continuation = nil
        query = nil
        continuation.resume(with: cancelled ? .failure(CancellationError()) : result)
    }
}
