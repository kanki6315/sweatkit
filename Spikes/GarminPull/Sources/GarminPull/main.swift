import Foundation
import GarminPullCore

// Throwaway M0 spike for the Garmin Personal API. See README.md for the commands
// and RESULTS.md for what they settle. The key is read from GARMIN_API_KEY and is
// never printed, logged or written anywhere.

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

struct Live {
    let client: PacedClient
    let endpoints = Endpoints()
    let token: String

    static func connect() async throws -> Live {
        guard let key = ProcessInfo.processInfo.environment["GARMIN_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            throw Failure(description: "GARMIN_API_KEY is not set. Export it in this terminal first; see README.md.")
        }
        try FileManager.default.createDirectory(at: outputDirectory.appending(path: "responses"), withIntermediateDirectories: true)
        let client = PacedClient(log: outputDirectory.appending(path: "requests.jsonl"))

        heading("Token")
        let (data, exchange) = try await client.send(Endpoints().token(apiKey: key))
        report(exchange)
        let token: TokenResponse
        do {
            token = try TokenResponse.parse(data)
        } catch {
            say("Token body is \(data.count) bytes and did not parse: \(error)")
            throw error
        }
        say("Body keys: \(token.keys.joined(separator: ", "))")
        say("token_type: \(token.tokenType ?? "not stated")  expires_in: \(token.expiresIn.map { "\(Int($0)) s (\(String(format: "%.1f", $0 / 3600)) h)" } ?? "not stated")  token length: \(token.accessToken.count)")
        return Live(client: client, token: token.accessToken)
    }

    func search(_ query: ActivitySearch, saveAs name: String) async throws -> [ActivityListEntry] {
        let (data, exchange) = try await client.send(endpoints.search(query, accessToken: token))
        report(exchange)
        save(data, name)
        return try ActivityListEntry.decodeList(data)
    }

    func detail(_ id: Int64) async throws -> ActivityDetail {
        let (data, exchange) = try await client.send(endpoints.activity(id: id, accessToken: token))
        report(exchange)
        save(data, "activity-\(id).json")
        return try ActivityDetail.decode(data)
    }

    /// Lists every page of one month, as the backfill would.
    func month(_ month: CalendarMonth) async throws -> [ActivityListEntry] {
        var all: [ActivityListEntry] = []
        var start = 0
        while true {
            let page = try await search(.month(month, start: start), saveAs: "month-\(month)-\(start).json")
            all += page
            if page.count < 99 { return all }
            say("Month \(month) filled a page of 99; fetching the next page.")
            start += 99
        }
    }

    func download(_ id: Int64) async throws -> Data {
        let (data, exchange) = try await client.send(endpoints.download(id: id, accessToken: token))
        report(exchange)
        return data
    }

    func save(_ data: Data, _ name: String) {
        try? data.write(to: outputDirectory.appending(path: "responses/\(name)"))
    }
}

func report(_ exchange: Exchange) {
    say("\(exchange.request) -> \(exchange.status)  \(exchange.bytes) bytes  \(exchange.milliseconds) ms")
    say("  rate headers: \(exchange.rateHeaders.isEmpty ? "none" : exchange.rateHeaders.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))")
    let shown = ["content-type", "content-disposition", "content-length", "cache-control", "server", "via", "x-cache", "date"]
    for name in shown { if let value = exchange.headers[name] { say("  \(name): \(value)") } }
}

func describe(_ entries: [ActivityListEntry], limit: Int = 5) {
    say("\(entries.count) activities")
    for entry in entries.prefix(limit) {
        say("  \(entry.activityId)  \(entry.startTimeLocal ?? "?")  \(entry.activityType?.typeKey ?? "?")  \(entry.manufacturer ?? "?")  \(entry.activityName ?? "")")
    }
    if entries.count > limit { say("  ...") }
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
func checkReference(_ live: Live, id: Int64, fixture: String) async throws {
    heading("Activity \(id) (\(fixture))")
    let detail = try await live.detail(id)
    let meta = detail.metadataDTO
    say("type \(detail.activityTypeDTO?.typeKey ?? "?")  start \(detail.summaryDTO?.startTimeLocal ?? "?")  manufacturer \(meta?.manufacturer ?? "?")")
    say("isOriginal \(meta?.isOriginal.map(String.init) ?? "?")  fileFormat \(meta?.fileFormat?.formatKey ?? "?")  trimmed \(meta?.trimmed.map(String.init) ?? "?")  lastUpdateDate \(meta?.lastUpdateDate ?? "?")  uploadedDate \(meta?.uploadedDate ?? "?")")

    if let date = detail.startDate {
        let month = CalendarMonth(containing: date)
        let entries = try await live.month(month)
        let listed = entries.contains { $0.activityId == id }
        say("Month \(month) lists \(entries.count) activities; \(id) is \(listed ? "LISTED" : "NOT LISTED").")
    } else {
        say("No start date in the summary, so the month listing was skipped.")
    }

    let payload = try await live.download(id)
    let fit = try inspect(payload, label: "download", keepAs: id)
    try compare(fit, toFixture: fixture)
}

func run(_ arguments: [String]) async throws {
    let command = arguments.first ?? "help"
    switch command {
    case "gates":
        let live = try await Live.connect()
        heading("Newest page")
        describe(try await live.search(.newest, saveAs: "newest.json"))
        heading("Earliest activity (ascending, limit 1)")
        let earliest = try await live.search(.earliest, saveAs: "earliest.json")
        describe(earliest)
        for reference in references {
            try await checkReference(live, id: reference.id, fixture: reference.fixture)
        }
        if let first = earliest.first {
            heading("Earliest activity's file")
            try inspect(try await live.download(first.activityId), label: "download", keepAs: first.activityId)
        }
        heading("Done")
        say("\(await live.client.exchanges.count) requests, none rate limited. Log: out/requests.jsonl")

    case "token":
        _ = try await Live.connect()

    case "newest":
        let live = try await Live.connect()
        describe(try await live.search(.newest, saveAs: "newest.json"), limit: 99)

    case "earliest":
        let live = try await Live.connect()
        describe(try await live.search(.earliest, saveAs: "earliest.json"))

    case "month":
        guard arguments.count == 2, let month = CalendarMonth(arguments[1]) else { throw Failure(description: "Usage: month YYYY-MM") }
        let live = try await Live.connect()
        heading("Month \(month): \(month.firstDay) to \(month.lastDay)")
        describe(try await live.month(month), limit: 99)

    case "months":
        // Walks whole months newest first, as the backfill would, and reports each
        // month's count. Capped so a mistake cannot hammer the API.
        guard arguments.count == 3, let from = CalendarMonth(arguments[1]), let to = CalendarMonth(arguments[2]) else {
            throw Failure(description: "Usage: months YYYY-MM YYYY-MM (oldest first, newest second; at most 36 months)")
        }
        var months: [CalendarMonth] = []
        var cursor = to
        while (cursor.year, cursor.month) >= (from.year, from.month) {
            months.append(cursor)
            cursor = cursor.month == 1 ? CalendarMonth(year: cursor.year - 1, month: 12) : CalendarMonth(year: cursor.year, month: cursor.month - 1)
        }
        guard months.count <= 36 else { throw Failure(description: "\(months.count) months is over the cap of 36.") }
        let live = try await Live.connect()
        var counts: [(CalendarMonth, Int)] = []
        for month in months {
            heading("Month \(month)")
            let entries = try await live.month(month)
            describe(entries, limit: 3)
            counts.append((month, entries.count))
        }
        heading("Summary")
        for (month, count) in counts { say("\(month)  \(count)\(count >= 99 ? "  (needed paging)" : "")") }

    case "activity":
        guard arguments.count == 2, let id = Int64(arguments[1]) else { throw Failure(description: "Usage: activity ID") }
        let live = try await Live.connect()
        let fixture = references.first { $0.id == id }?.fixture
        if let fixture {
            try await checkReference(live, id: id, fixture: fixture)
        } else {
            let detail = try await live.detail(id)
            say("type \(detail.activityTypeDTO?.typeKey ?? "?")  start \(detail.summaryDTO?.startTimeLocal ?? "?")  isOriginal \(detail.metadataDTO?.isOriginal.map(String.init) ?? "?")")
        }

    case "download":
        guard arguments.count >= 2, let id = Int64(arguments[1]) else { throw Failure(description: "Usage: download ID [--compare PATH]") }
        let live = try await Live.connect()
        heading("Download \(id)")
        let fit = try inspect(try await live.download(id), label: "download", keepAs: id)
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
    print("ERROR: \(error)")
    exit(1)
}
