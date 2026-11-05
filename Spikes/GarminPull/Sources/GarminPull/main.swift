import Foundation
import GarminPullCore
import SweatKitGarmin

// Throwaway M0 probe for the Garmin Personal API, built on SweatKitGarmin. See
// README.md for the commands and RESULTS.md for what they settle. The key is read
// from GARMIN_API_KEY and is never printed, logged or written anywhere.

let packageDirectory = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let repositoryRoot = packageDirectory.deletingLastPathComponent().deletingLastPathComponent()
let outputDirectory = packageDirectory.appending(path: "out")

/// The two fixtures the gates compare against, by their Garmin activity IDs.
let references: [(id: Int64, fixture: String)] = [
    (24172582403, "Fixtures/fit/outdoor-ride.fit"),
    (24906063494, "Fixtures/fit/zwift-ride.fit"),
]

func say(_ text: String = "") { print(text) }
func heading(_ text: String) { say("\n== \(text)") }

struct Failure: Error, CustomStringConvertible { var description: String }

func explain(_ error: any Error) -> String {
    guard let error = error as? GarminError else { return "\(error)" }
    switch error {
    case .keyRejected(let status): return "Key refused (HTTP \(status)): wrong, expired or deleted. Create a new key."
    case .tokenExpired: return "A freshly issued token was refused by a data endpoint (HTTP 401 twice). The Bearer assumption may be wrong."
    case .rateLimited(let retryAfter): return "RATE LIMITED (429). Retry-After: \(retryAfter.map { "\(Int($0)) s" } ?? "not given"). The run stopped; nothing more was sent."
    case .network(let code): return "Network failure: URLError \(code.rawValue)."
    case .unexpectedResponse(let response): return "Unexpected response: HTTP \(response.status), \(response.reason)."
    case .invalidRequest: return "Invalid request arguments."
    }
}

func report(_ exchange: GarminExchange) {
    say("\(exchange.method) \(exchange.target) -> \(exchange.status)  \(exchange.bytes) bytes")
    let rate = rateHeaders(exchange.headers)
    say("  rate headers: \(rate.isEmpty ? "none" : rate.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))")
    for name in ["content-type", "content-disposition", "cache-control", "server", "via", "x-cache"] {
        if let value = exchange.headers[name] { say("  \(name): \(value)") }
    }
}

func connect() async throws -> GarminClient {
    guard let key = ProcessInfo.processInfo.environment["GARMIN_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
        throw Failure(description: "GARMIN_API_KEY is not set. Export it in this terminal first; see README.md.")
    }
    try FileManager.default.createDirectory(at: outputDirectory.appending(path: "responses"), withIntermediateDirectories: true)
    let recorder = ExchangeRecorder(url: outputDirectory.appending(path: "requests.jsonl"))
    let client = GarminClient(apiKey: key, transport: PacedTransport(saveJSONBodiesTo: outputDirectory.appending(path: "responses")), observer: { exchange in
        recorder.record(exchange)
        report(exchange)
    })

    heading("Token")
    try await client.validateKey()
    say("Body keys: \((await client.tokenResponseKeys ?? []).joined(separator: ", "))")
    if let expiry = await client.tokenExpiry {
        say("Treated as valid for \(String(format: "%.1f", expiry.timeIntervalSinceNow / 3600)) h (from expires_in, or the documented 24 h if absent)")
    }
    return client
}

func describe(_ entries: [ActivitySummary], limit: Int = 5) {
    say("\(entries.count) activities")
    for entry in entries.prefix(limit) {
        say("  \(entry.activityId)  \(entry.startTimeLocal ?? "?")  \(entry.activityType?.typeKey ?? "?")  \(entry.manufacturer ?? "?")  \(entry.activityName ?? "")")
    }
    if entries.count > limit { say("  ...") }
}

/// Lists every page of one month, as the backfill would.
func listMonth(_ client: GarminClient, _ month: CalendarMonth) async throws -> [ActivitySummary] {
    var query = month.query()
    var all: [ActivitySummary] = []
    while true {
        let page = try await client.activities(query)
        all += page
        if page.count < query.limit { return all }
        say("Month \(month) filled a page of \(query.limit); fetching the next page.")
        query = query.nextPage
    }
}

/// Reports what a downloaded or local payload holds and returns the FIT report.
@discardableResult
func inspect(_ payload: Data, label: String, keepAs id: Int64? = nil) throws -> FITChannelReport? {
    let kind = PayloadKind(sniffing: payload)
    say("\(label): \(kind.rawValue), \(payload.count) bytes, sha256 \(sha256Hex(payload))")
    if let id { try? payload.write(to: outputDirectory.appending(path: "\(id).\(kind == .other ? "bin" : kind.rawValue)")) }
    switch kind {
    case .fit:
        let fit = try FITChannelReport(fit: payload)
        say(fit.description)
        return fit
    case .zip:
        let entries = try unzipEntries(payload)
        say("zip holds \(entries.count) file(s): \(entries.map { "\($0.name) (\($0.data.count) bytes)" }.joined(separator: ", "))")
        var first: FITChannelReport?
        for entry in entries where PayloadKind(sniffing: entry.data) == .fit {
            say("-- \(entry.name)")
            let fit = try FITChannelReport(fit: entry.data)
            say(fit.description)
            first = first ?? fit
        }
        if first == nil { say("No FIT file inside the zip.") }
        return first
    case .other:
        say("Neither zip nor FIT. First bytes: \(payload.prefix(16).map { String(format: "%02x", $0) }.joined(separator: " "))")
        return nil
    }
}

func download(_ client: GarminClient, _ id: Int64) async throws -> FITChannelReport? {
    let file = try await client.originalFile(activityID: id)
    say("content type \(file.contentType ?? "none")  filename \(file.suggestedFilename ?? "none")")
    return try inspect(file.data, label: "download", keepAs: id)
}

func compare(_ downloaded: FITChannelReport?, toFixture path: String) throws {
    let reference = try FITChannelReport(fit: Data(contentsOf: repositoryRoot.appending(path: path)))
    say("-- reference \(path)")
    say(reference.description)
    guard let downloaded else { say("RESULT: no FIT file to compare."); return }
    let sameBytes = downloaded.sha256 == reference.sha256
    let differences = downloaded.differences(from: reference)
    say("RESULT: bytes \(sameBytes ? "IDENTICAL" : "DIFFER")  channels \(differences.isEmpty ? "MATCH" : "DIFFER")")
    for line in differences { say("  \(line)") }
}

/// Checks one reference activity: its summary, that it appears in its month's
/// listing, and that its file downloads with the fixture's channels.
func checkReference(_ client: GarminClient, id: Int64, fixture: String) async throws {
    heading("Activity \(id) (\(fixture))")
    let detail = try await client.activity(id: id)
    let meta = detail.metadataDTO
    say("type \(detail.activityTypeDTO?.typeKey ?? "?")  start \(detail.summaryDTO?.startTimeLocal ?? "?")  manufacturer \(meta?.manufacturer ?? "?")")
    say("isOriginal \(meta?.isOriginal.map(String.init) ?? "?")  fileFormat \(meta?.fileFormat?.formatKey ?? "?")  trimmed \(meta?.trimmed.map(String.init) ?? "?")  lastUpdateDate \(meta?.lastUpdateDate ?? "?")  uploadedDate \(meta?.uploadedDate ?? "?")")

    if let date = detail.startDate {
        let month = CalendarMonth(containing: date)
        let entries = try await listMonth(client, month)
        let listed = entries.contains { $0.activityId == id }
        let outside = entries.filter { entry in entry.startDate.map { CalendarMonth(containing: $0) != month } ?? true }
        say("Month \(month) lists \(entries.count) activities; \(id) is \(listed ? "LISTED" : "NOT LISTED"). Entries outside the month: \(outside.count).")
    } else {
        say("No start date in the summary, so the month listing was skipped.")
    }

    try compare(try await download(client, id), toFixture: fixture)
}

func run(_ arguments: [String]) async throws {
    let command = arguments.first ?? "help"
    switch command {
    case "gates":
        let client = try await connect()
        heading("Newest page")
        describe(try await client.activities(.newest))
        heading("Earliest activity (ascending, limit 1)")
        let earliest = try await client.activities(.earliest)
        describe(earliest)
        for reference in references {
            try await checkReference(client, id: reference.id, fixture: reference.fixture)
        }
        if let first = earliest.first {
            heading("Earliest activity's file")
            _ = try await download(client, first.activityId)
        }
        heading("Done")
        say("No request was rate limited. Every exchange is in out/requests.jsonl.")

    case "token":
        _ = try await connect()

    case "newest":
        describe(try await connect().activities(.newest), limit: 99)

    case "earliest":
        describe(try await connect().activities(.earliest))

    case "month":
        guard arguments.count == 2, let month = CalendarMonth(arguments[1]) else { throw Failure(description: "Usage: month YYYY-MM") }
        let client = try await connect()
        heading("Month \(month)")
        describe(try await listMonth(client, month), limit: 99)

    case "months":
        // Walks whole months newest first, as the backfill would, and reports each
        // month's count. Capped so a mistake cannot hammer the API.
        guard arguments.count == 3, let from = CalendarMonth(arguments[1]), let to = CalendarMonth(arguments[2]) else {
            throw Failure(description: "Usage: months YYYY-MM YYYY-MM (oldest first, newest second; at most 36 months)")
        }
        var months: [CalendarMonth] = []
        var cursor: CalendarMonth? = to
        while let month = cursor, (month.year, month.month) >= (from.year, from.month), months.count <= 36 {
            months.append(month)
            cursor = month.previous
        }
        guard months.count <= 36 else { throw Failure(description: "More than 36 months; narrow the range.") }
        let client = try await connect()
        var counts: [(CalendarMonth, Int)] = []
        for month in months {
            heading("Month \(month)")
            let entries = try await listMonth(client, month)
            describe(entries, limit: 3)
            counts.append((month, entries.count))
        }
        heading("Summary")
        for (month, count) in counts { say("\(month)  \(count)\(count >= ActivityQuery.defaultLimit ? "  (needed paging)" : "")") }

    case "activity":
        guard arguments.count == 2, let id = Int64(arguments[1]) else { throw Failure(description: "Usage: activity ID") }
        let client = try await connect()
        if let fixture = references.first(where: { $0.id == id })?.fixture {
            try await checkReference(client, id: id, fixture: fixture)
        } else {
            let detail = try await client.activity(id: id)
            say("type \(detail.activityTypeDTO?.typeKey ?? "?")  start \(detail.summaryDTO?.startTimeLocal ?? "?")  isOriginal \(detail.metadataDTO?.isOriginal.map(String.init) ?? "?")")
        }

    case "download":
        guard arguments.count >= 2, let id = Int64(arguments[1]) else { throw Failure(description: "Usage: download ID [--compare PATH]") }
        let client = try await connect()
        heading("Download \(id)")
        let fit = try await download(client, id)
        if arguments.count == 4, arguments[2] == "--compare" { try compare(fit, toFixture: arguments[3]) }

    case "inspect":
        // Offline: decodes a local FIT or zip, to check the decoding path without a key.
        guard arguments.count == 2 else { throw Failure(description: "Usage: inspect PATH") }
        try inspect(try Data(contentsOf: URL(filePath: arguments[1])), label: arguments[1])

    default:
        say("""
        garmin-pull <command>
          gates                    run every M0 Garmin check in one paced session (about 10 requests)
          token                    exchange GARMIN_API_KEY for an access token and report its shape
          newest                   list the newest page
          earliest                 find the earliest activity (ascending sort, limit 1)
          month YYYY-MM            list one calendar month by start date
          months FROM TO           list each month from TO back to FROM (at most 36)
          activity ID              summary, month listing and download for one activity
          download ID [--compare PATH]  download one activity's file and decode it
          inspect PATH             decode a local FIT or zip, no network
        """)
    }
}

do {
    try await run(Array(CommandLine.arguments.dropFirst()))
} catch {
    print("ERROR: \(explain(error))")
    exit(1)
}
