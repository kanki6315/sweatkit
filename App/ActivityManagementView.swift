import SwiftUI
import SweatKitIdentity
import SweatKitLibrary
import SweatKitModel
import SweatKitStore

struct ActivityManagementView: View {
    let activity: ActivityRecord
    let library: ActivityLibrary
    var deleteActivity: (@MainActor (SourceIdentity) async throws -> Void)? = nil
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
                    if let deleteActivity { try await deleteActivity(id) }
                    else { try await library.permanentlyDelete(id) }
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
    @State private var units = UnitSystem.metric
    @State private var pairs: [IdentityPair] = []
    @State private var rows: [SourceIdentity: ActivityRecord] = [:]
    @State private var hidden: [ActivityRecord] = []
    @State private var error: String?
    @State private var busy = false

    @State private var selectedPairs: Set<IdentityPair> = []
    @State private var editMode = EditMode.inactive
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var selecting: Bool { editMode.isEditing }

    var body: some View {
        List(selection: selecting ? $selectedPairs : nil) {
            if let error { Section { Text(error); Button("Try again") { Task { await load() } } } }
            Section {
                if pairs.isEmpty { Text("No recordings need review.").foregroundStyle(.secondary) }
                ForEach(pairs, id: \.self) { pair in
                    comparison(pair)
                        .tag(pair)
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            if !selecting {
                                Button("Merge", systemImage: "arrow.triangle.merge") { decide([pair], .sameActivity) }
                                    .tint(.accentColor)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if !selecting {
                                Button("Keep separate", systemImage: "arrow.triangle.branch") { decide([pair], .keepSeparate) }
                                    .tint(.gray)
                            }
                        }
                        .accessibilityAction(named: "Merge") { decide([pair], .sameActivity) }
                        .accessibilityAction(named: "Keep separate") { decide([pair], .keepSeparate) }
                }
            } header: { Text("Possible duplicates") } footer: {
                Text("Swipe right to merge, or left to keep separate. Tap Select to review several pairs at once.")
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
                    .selectionDisabled(true)
                }
            }
        }
        .environment(\.editMode, $editMode)
        .safeAreaInset(edge: .bottom) {
            if selecting {
                VStack(spacing: 8) {
                    if busy {
                        ProgressView("Applying decisions…")
                    } else {
                        Text("\(selectedPairs.count) selected").font(.subheadline).foregroundStyle(.secondary)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack { batchActions }
                        VStack { batchActions }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(.bar)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !pairs.isEmpty || selecting {
                    Button(selecting ? "Done" : "Select") {
                        selectedPairs.removeAll()
                        editMode = selecting ? .inactive : .active
                    }
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                if selecting && !pairs.isEmpty {
                    Button(selectedPairs.count == pairs.count ? "Deselect all" : "Select all") {
                        selectedPairs = selectedPairs.count == pairs.count ? [] : Set(pairs)
                    }
                }
            }
        }
        .disabled(busy)
        .navigationTitle("Library review")
        .task { await load() }
    }

    @ViewBuilder private var batchActions: some View {
        Button("Merge selected", systemImage: "arrow.triangle.merge") {
            decide(pairs.filter { selectedPairs.contains($0) }, .sameActivity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(selectedPairs.isEmpty)
        Button("Keep separate", systemImage: "arrow.triangle.branch") {
            decide(pairs.filter { selectedPairs.contains($0) }, .keepSeparate)
        }
        .buttonStyle(.bordered)
        .disabled(selectedPairs.isEmpty)
    }

    private func comparison(_ pair: IdentityPair) -> some View {
        // Accessibility sizes retain complete text instead of squeezing two columns.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
        return layout {
            recording(pair.lower)
            recording(pair.upper)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private func recording(_ source: SourceIdentity) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(sourceName(source)).font(.caption).foregroundStyle(.secondary)
            Text(rows[source]?.title ?? "Recording").font(.subheadline.weight(.semibold))
            if let row = rows[source] {
                Text(row.start, format: .dateTime.month(.abbreviated).day().year())
                    .font(.caption)
                Text(row.start, format: .dateTime.hour().minute()).font(.caption)
                Text("\(Duration.seconds(row.elapsedTime).formatted(.time(pattern: .hourMinuteSecond))) elapsed")
                    .font(.caption).monospacedDigit()
                Text(distance(row.distance)).font(.caption).monospacedDigit()
                Text(row.sport.rawValue.capitalized)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
    private func distance(_ metres: Double?) -> String {
        guard let metres else { return "No distance" }
        return String(format: "%.1f %@", metres / (units == .metric ? 1000 : 1609.344), units == .metric ? "km" : "mi")
    }
    private func sourceName(_ source: SourceIdentity) -> String {
        switch source.source {
        case .garmin: "Garmin"
        case .healthKit: "Apple Health"
        case .file: "FIT file"
        }
    }
    private func decide(_ decisions: [IdentityPair], _ kind: LinkKind) {
        guard !busy, !decisions.isEmpty else { return }
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                for pair in decisions {
                    try await library.link(pair, kind: kind)
                    selectedPairs.remove(pair)
                    pairs.removeAll { $0 == pair }
                }
                await load()
            } catch {
                let failure = error.localizedDescription
                // Refresh even after partial success; never retry completed pairs.
                await load()
                self.error = failure
            }
        }
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
            units = try await library.profile().units
            pairs = try await library.possibleDuplicates()
            selectedPairs.formIntersection(Set(pairs))
            if pairs.isEmpty { editMode = .inactive }
            rows.removeAll()
            hidden = try await library.hiddenActivities()
            for pair in pairs {
                rows[pair.lower] = try await library.activityContaining(pair.lower)
                rows[pair.upper] = try await library.activityContaining(pair.upper)
            }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}
