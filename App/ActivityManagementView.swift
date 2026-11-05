import SwiftUI
import SweatKitIdentity
import SweatKitLibrary
import SweatKitModel
import SweatKitStore

struct ActivityManagementView: View {
    let activity: ActivityRecord
    let library: ActivityLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsDeletion = false
    @State private var offers: [AlternativeOffer] = []
    @State private var title = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Form {
            Section("Title") {
                TextField("Activity title", text: $title)
                Button("Save title") { perform { try await library.decide(.title(title.trimmingCharacters(in: .whitespacesAndNewlines)), for: id) } }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Section {
                ForEach(activity.members, id: \.self) { source in
                    Button {
                        perform { try await library.decide(.primary(source), for: id) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(source.source == .garmin ? "Garmin" : source.source == .healthKit ? "Apple Health" : "Imported FIT file")
                                if let offer = offers.first(where: { $0.identity == source }) {
                                    Text("Adds " + offer.channels.map { $0 == .heartRate ? "heart rate" : $0.rawValue }.sorted().joined(separator: ", "))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Text(source.externalID).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer()
                            if source == activity.primary { Image(systemName: "checkmark").accessibilityLabel("Primary source") }
                        }
                    }.tint(.primary)
                }
            } header: { Text("Source of activity data") } footer: {
                Text("The selected recording supplies all streams and statistics. Other recordings are preserved as alternatives.")
            }
            if activity.members.count > 1 {
                Section {
                    Button("Separate recordings") { perform { try await library.split(id) } }
                } footer: { Text("Each recording becomes an activity. Your title and visibility choices are kept on each part.") }
            }
            Section {
                Button("Hide activity") { perform { try await library.decide(.hidden(true), for: id) } }
            } footer: { Text("Hidden activities stay on your device and can be restored in Settings. Sync won't bring them back into the feed.") }
            Section {
                Button("Permanently delete activity", role: .destructive) { confirmsDeletion = true }
            } footer: { Text("Erases this activity's recordings and computed data from SweatKit. It does not delete anything from Garmin or Apple Health.") }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }
        .confirmationDialog("Permanently delete this activity?", isPresented: $confirmsDeletion, titleVisibility: .visible) {
            Button("Delete permanently", role: .destructive) {
                perform {
                    // Older builds kept unindexed thumbnails outside the library.
                    // Drop that rebuildable cache before confirming erasure.
                    let legacy = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("SweatKitThumbnails")
                    if FileManager.default.fileExists(atPath: legacy.path) { try FileManager.default.removeItem(at: legacy) }
                    try await library.permanentlyDelete(id)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("All \(activity.members.count) recordings in this activity will be erased from SweatKit. This cannot be undone, and sync will not import them again. Copies used by another activity are kept.")
        }
        .disabled(busy)
        .navigationTitle("Activity info")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { title = activity.title }
        .task {
            do { offers = try await library.alternativeSources(for: id) }
            catch { self.error = error.localizedDescription }
        }
    }

    private var id: SourceIdentity { activity.id ?? activity.primary }
    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        busy = true
        Task {
            defer { busy = false }
            do { try await operation(); dismiss() }
            catch { self.error = error.localizedDescription }
        }
    }
}

struct LibraryReviewView: View {
    let library: ActivityLibrary
    @State private var pairs: [IdentityPair] = []
    @State private var rows: [SourceIdentity: ActivityRecord] = [:]
    @State private var hidden: [ActivityRecord] = []
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        List {
            if let error { Section { Text(error); Button("Try again") { Task { await load() } } } }
            Section {
                if pairs.isEmpty { Text("No recordings need review.").foregroundStyle(.secondary) }
                ForEach(pairs, id: \.self) { pair in
                    VStack(alignment: .leading, spacing: 12) {
                        recording(pair.lower)
                        recording(pair.upper)
                        HStack {
                            Button("Merge") { decide(pair, .sameActivity) }.buttonStyle(.bordered)
                            Button("Keep separate") { decide(pair, .keepSeparate) }.buttonStyle(.bordered)
                        }
                    }.padding(.vertical, 8)
                }
            } header: { Text("Possible duplicates") } footer: {
                Text("Overlapping recordings that don't meet the automatic matching rules stay separate until you decide.")
            }
            Section("Hidden activities") {
                if hidden.isEmpty { Text("No hidden activities.").foregroundStyle(.secondary) }
                ForEach(hidden, id: \.id) { row in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(row.title).font(.headline)
                        Text(row.start, format: .dateTime.month().day().year()).foregroundStyle(.secondary)
                        Button("Restore activity") {
                            run { try await library.decide(.hidden(false), for: row.id ?? row.primary) }
                        }
                    }
                }
            }
        }
        .disabled(busy)
        .navigationTitle("Library review")
        .task { await load() }
    }

    @ViewBuilder private func recording(_ source: SourceIdentity) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(rows[source]?.title ?? "Recording").font(.headline)
            if let row = rows[source] {
                Text(row.start, format: .dateTime.month().day().hour().minute()).font(.subheadline)
                Text("\(Int(row.elapsedTime / 60)) min · \(source.source.rawValue)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func decide(_ pair: IdentityPair, _ kind: LinkKind) {
        run { try await library.link(pair, kind: kind) }
    }
    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        busy = true
        Task {
            defer { busy = false }
            do { try await operation(); await load() }
            catch { self.error = error.localizedDescription }
        }
    }
    private func load() async {
        do {
            pairs = try await library.possibleDuplicates()
            hidden = try await library.hiddenActivities()
            for pair in pairs {
                rows[pair.lower] = try await library.activityContaining(pair.lower)
                rows[pair.upper] = try await library.activityContaining(pair.upper)
            }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}
