import Foundation
import Observation
import Security
import SweatKitGarmin
import SweatKitLibrary
import SweatKitSync
import SweatKitModel

@MainActor @Observable
final class GarminConnection {
    private(set) var connected = false
    private(set) var running = false
    private(set) var lastSyncSucceeded = false
    private(set) var lifetime: GarminKeyLifetime?
    private(set) var keyRefused = false
    var canSync: Bool { connected && !keyRefused && !running }
    private var credential: GarminCredential?
    private(set) var status = "Connect Garmin in Settings to sync your activities."
    private var engine: GarminSync?
    private var backgroundWork: WorkoutBackgroundWork?
    private var task: Task<Void, Never>?
    private let library: ActivityLibrary
    private let bridge: PersistentGarminLibrary

    init(library: ActivityLibrary, root: URL) {
        self.library = library
        bridge = PersistentGarminLibrary(library: library, metadataURL: root.appendingPathComponent("garmin-sync.json"))
        restoreCredential()
    }

    /// A protected Keychain may be unavailable at background launch. Retry on
    /// the next foreground refresh rather than requiring a new key or reinstall.
    private func restoreCredential() {
        do {
            if let saved = try GarminKeychain.read() {
                credential = saved
                lifetime = saved.lifetime
                keyRefused = saved.refused
                let key = saved.key
                engine = GarminSync(remote: GarminClientSource(client: GarminClient(apiKey: key)), library: bridge)
                connected = true
                status = saved.refused ? "Garmin refused your key. Replace it in Settings to resume sync." : "Garmin connected. Refresh to sync."
            }
        } catch { status = "The Garmin key couldn't be read. Unlock your device and try again." }
    }

    func connect(key: String, lifetime: GarminKeyLifetime) async -> Bool {
        guard !running else { return false }
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { status = "Enter your Garmin Personal API key."; return false }
        running = true
        defer { running = false }
        let client = GarminClient(apiKey: key)
        do {
            try await client.validateKey()
            let saved = GarminCredential(key: key, lifetime: lifetime, refused: false)
            try GarminKeychain.save(saved)
            credential = saved
            self.lifetime = lifetime
            keyRefused = false
            engine = GarminSync(remote: GarminClientSource(client: client), library: bridge)
            connected = true
            status = "Garmin connected. Sync to import your history."
            return true
        } catch let error as GarminError { status = Self.message(error) }
        catch { status = "The key couldn't be saved in Keychain. Unlock your device and try again." }
        return false
    }

    func sync(_ run: SyncRun = .routine, continued: Bool = true) async {
        if !connected && !running { restoreCredential() }
        guard canSync, let engine else { return }
        running = true
        status = "Syncing Garmin: 0 added, 0 updated. You can keep browsing; completed work is saved."
        lastSyncSucceeded = false
        task = Task { [self] in
            let background = WorkoutBackgroundWork(title: "Syncing Garmin workouts", continued: continued) { [weak self] in
                self?.task?.cancel()
            }
            backgroundWork = background
            defer { backgroundWork = nil }
            let report = await engine.run(run) { [weak self] progress in
                await self?.showProgress(progress)
            }
            lastSyncSucceeded = report.outcome == .completed && report.outstanding == 0
            background.finish(success: lastSyncSucceeded)
            switch report.outcome {
            case .completed:
                status = "Garmin sync finished. \(report.added.count) added, \(report.revised.count) updated."
                if report.outstanding > 0 { status += " \(report.outstanding) activities need another attempt. Refresh to retry." }
                if !report.unsettledMonths.isEmpty { status += " Some history changed during sync and will be checked again." }
            case .rateLimited(let until):
                status = "Garmin asked us to wait until \(until.formatted(date: .abbreviated, time: .shortened)). Refresh after that to resume."
            case .keyRefused:
                keyRefused = true
                credential?.refused = true
                status = "Garmin refused your key. Enter a new Personal API key in Settings; your activities are safe."
                if let credential {
                    do { try GarminKeychain.save(credential) }
                    catch { status += " The refusal couldn't be saved; unlock your device before closing the app." }
                }
            case .tokenRefused: status = "Garmin refused a renewed session. Try syncing again, or reconnect in Settings."
            case .listingFailed(let error): status = Self.message(error) + " Refresh to resume."
            case .interrupted: status = "Sync paused. Refresh to resume from saved progress."
            case .libraryFailed: status = "Sync couldn't save or read the library. Check available device storage, then retry."
            case .alreadyRunning: status = "Garmin sync is already running."
            }
        }
        let runningTask = task
        if continued {
            await runningTask?.value
        } else {
            await withTaskCancellationHandler {
                await runningTask?.value
            } onCancel: {
                runningTask?.cancel()
            }
        }
        task = nil
        running = false
    }

    private func showProgress(_ progress: SyncProgress) {
        backgroundWork?.update(completed: progress.added + progress.updated, total: progress.added + progress.updated + 1)
        status = "Syncing Garmin: \(progress.added) added, \(progress.updated) updated. You can keep browsing; completed work is saved."
    }

    func recoverDeletionCleanup() async {
        do { try await bridge.pruneDeletedSummaries() }
        catch { status = "Deleted recordings remain deleted, but cached Garmin summaries could not be cleared. Check storage and reopen SweatKit to retry." }
    }

    func permanentlyDelete(_ id: SourceIdentity) async throws {
        try await bridge.permanentlyDelete(id)
    }

    func pause() { task?.cancel() }

    func expiryNotice(at now: Date = Date()) -> String? {
        guard let lifetime else { return connected ? "Key expiry is unknown. Enter the creation date and expiry period when replacing this key." : nil }
        switch lifetime.warning(at: now) {
        case .none: return nil
        case .dueSoon: return "Your Garmin key is expected to expire on \(lifetime.estimatedExpiry.formatted(date: .abbreviated, time: .omitted)). Replace it in Settings."
        case .expired: return "Your entered Garmin key period has ended. Replace the key if Garmin refuses sync. Stored activities are kept."
        }
    }

    private static func message(_ error: GarminError) -> String {
        switch error {
        case .keyRejected: "Garmin refused this key. Check or replace your Personal API key."
        case .tokenExpired: "Garmin refused the session after renewal. Try connecting again."
        case .rateLimited: "Garmin is limiting requests. Wait before trying again."
        case .network: "Couldn't reach Garmin. Check your connection."
        case .unexpectedResponse: "Garmin returned an unexpected response. Try again later."
        case .invalidRequest: "The Garmin request couldn't be prepared."
        }
    }
}

private struct GarminCredential: Codable {
    var key: String
    var lifetime: GarminKeyLifetime?
    var refused: Bool
}

private enum GarminKeychain {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.arjunakankipati.sweatkit.garmin",
         kSecAttrAccount as String: "personal-api-key"]
    }
    struct Failure: Error { let status: OSStatus }

    static func read() throws -> GarminCredential? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else { throw Failure(status: status) }
        if let saved = try? JSONDecoder().decode(GarminCredential.self, from: data) { return saved }
        // The first app version stored the plain key. Preserve it, with unknown expiry.
        guard !key.hasPrefix("{") else { throw Failure(status: errSecDecode) }
        return GarminCredential(key: key, lifetime: nil, refused: false)
    }

    static func save(_ credential: GarminCredential) throws {
        let attributes: [String: Any] = [kSecValueData as String: try JSONEncoder().encode(credential),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw Failure(status: status) }
    }
}
