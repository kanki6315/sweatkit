import Foundation
import Observation
import Security
import SweatKitGarmin
import SweatKitLibrary
import SweatKitSync

@MainActor @Observable
final class GarminConnection {
    private(set) var connected = false
    private(set) var running = false
    private(set) var status = "Connect Garmin in Settings to sync your activities."
    private var engine: GarminSync?
    private var task: Task<Void, Never>?
    private let library: ActivityLibrary
    private let bridge: PersistentGarminLibrary

    init(library: ActivityLibrary, root: URL) {
        self.library = library
        bridge = PersistentGarminLibrary(library: library, metadataURL: root.appendingPathComponent("garmin-sync.json"))
        do {
            if let key = try GarminKeychain.read() {
                engine = GarminSync(remote: GarminClientSource(client: GarminClient(apiKey: key)), library: bridge)
                connected = true
                status = "Garmin connected. Refresh to sync."
            }
        } catch { status = "The Garmin key couldn't be read. Unlock your device and try again." }
    }

    func connect(key: String) async {
        guard !running else { return }
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { status = "Enter your Garmin Personal API key."; return }
        running = true
        defer { running = false }
        let client = GarminClient(apiKey: key)
        do {
            try await client.validateKey()
            try GarminKeychain.save(key)
            engine = GarminSync(remote: GarminClientSource(client: client), library: bridge)
            connected = true
            status = "Garmin connected. Refresh to import your history."
        } catch let error as GarminError { status = Self.message(error) }
        catch { status = "The key couldn't be saved in Keychain. Unlock your device and try again." }
    }

    func sync(_ run: SyncRun = .routine) async {
        guard !running, let engine else { return }
        running = true
        status = "Syncing Garmin. You can keep browsing; completed work is saved."
        task = Task {
            let report = await engine.run(run)
            switch report.outcome {
            case .completed:
                status = "Garmin sync finished. \(report.added.count) added, \(report.revised.count) updated."
                if report.outstanding > 0 { status += " \(report.outstanding) activities need another attempt. Refresh to retry." }
                if !report.unsettledMonths.isEmpty { status += " Some history changed during sync and will be checked again." }
            case .rateLimited(let until):
                status = "Garmin asked us to wait until \(until.formatted(date: .abbreviated, time: .shortened)). Refresh after that to resume."
            case .keyRefused: status = "Garmin refused your key. Enter a new Personal API key in Settings; your activities are safe."
            case .tokenRefused: status = "Garmin refused a renewed session. Try syncing again, or reconnect in Settings."
            case .listingFailed(let error): status = Self.message(error) + " Refresh to resume."
            case .interrupted: status = "Sync paused. Refresh to resume from saved progress."
            case .libraryFailed: status = "Sync couldn't save or read the library. Check available device storage, then retry."
            case .alreadyRunning: status = "Garmin sync is already running."
            }
        }
        await task?.value
        task = nil
        running = false
    }

    func pause() { task?.cancel() }

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

private enum GarminKeychain {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.arjunakankipati.sweatkit.garmin",
         kSecAttrAccount as String: "personal-api-key"]
    }
    struct Failure: Error { let status: OSStatus }

    static func read() throws -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else { throw Failure(status: status) }
        return key
    }

    static func save(_ key: String) throws {
        let attributes: [String: Any] = [kSecValueData as String: Data(key.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw Failure(status: status) }
    }
}
