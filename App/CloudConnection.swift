import Foundation
import Observation
import SweatKitCloud
import SweatKitLibrary

@MainActor @Observable
final class CloudConnection {
    private let library: ActivityLibrary
    private let root: URL
    private var transport: PrivateCloudCopy?
    private(set) var enabled: Bool
    private(set) var running = false
    private(set) var status = "Not enabled · originals are on this device"
    private(set) var detail: String?
    private(set) var lastConfirmed: Date?
    private(set) var pending = 0
    private var task: Task<Void, Never>?
    private var needsSync = false
    var didRecover: (@MainActor () async -> Void)?
    private static let preference = "private-cloud-copy-enabled"

    init(library: ActivityLibrary, root: URL) {
        self.library = library; self.root = root
        enabled = UserDefaults.standard.bool(forKey: Self.preference)
        if enabled { status = "Waiting to check iCloud" }
    }
    func setEnabled(_ value: Bool) {
        enabled = value
        UserDefaults.standard.set(value, forKey: Self.preference)
        if value { task = Task { await sync() } }
        else { status = "Paused · existing iCloud copy is kept" }
    }
    func schedule() {
        guard enabled else { return }
        if running { needsSync = true; return }
        task?.cancel()
        task = Task {
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            await sync()
        }
    }
    func sync() async {
        guard enabled, !running else { return }
        running = true; detail = nil; status = "Checking iCloud…"
        defer {
            running = false
            if needsSync { needsSync = false; schedule() }
        }
        do {
            #if targetEnvironment(simulator)
            throw NSError(domain: "SweatKitCloud", code: 1, userInfo: [NSLocalizedDescriptionKey: "iCloud copying needs a signed device build with the SweatKit CloudKit container. Your local library is available in the simulator."])
            #endif
            let copy: PrivateCloudCopy
            if let transport { copy = transport }
            else { copy = try PrivateCloudCopy(root: root); transport = copy }
            let exports = try await library.cloudExport()
            // Stage deletion intent first, including while offline.
            let ordered = exports.sorted(by: { $0.permanentlyDeleted && !$1.permanentlyDeleted })
            for start in stride(from: 0, to: ordered.count, by: 32) {
                try Task.checkCancellation()
                let batch = Array(ordered[start..<min(start + 32, ordered.count)])
                var originals: [String: Data] = [:]
                for item in batch where await copy.needsOriginal(item) {
                    try Task.checkCancellation()
                    originals[item.name] = try await library.cloudOriginal(item)
                }
                try await copy.stage(batch, originals: originals)
            }
            var transportError: Error?
            do { try await copy.sync() } catch { transportError = error }
            // A quota/send failure must not hold back a durably fetched delete
            // or a recoverable download. Replay the inbox even when sending failed.
            status = "Rebuilding recovered activities…"
            try await library.cloudRestore(await copy.records()) { item in try await copy.asset(item) }
            await didRecover?()
            if let transportError { throw transportError }
            let result = await copy.status()
            pending = result.pending; lastConfirmed = result.lastConfirmed
            status = result.total == 0 ? "No originals to copy" : "\(result.copied) of \(result.total) originals copied"
            detail = result.message
        } catch {
            status = "iCloud needs attention"
            detail = PrivateCloudCopy.message(error)
            if let transport {
                let result = await transport.status()
                pending = result.pending; lastConfirmed = result.lastConfirmed
            }
        }
    }
}
