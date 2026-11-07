import SwiftUI
import SweatKitModel
import SweatKitAnalysis
import SweatKitLibrary
import SweatKitStore
import SweatKitSync
import UniformTypeIdentifiers

struct SettingsView: View {
    let model: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppTheme.preferenceKey) private var accent = AppTheme.cyan.rawValue
    @AppStorage(AppAppearance.preferenceKey) private var appearance = AppAppearance.system.rawValue
    @State private var showsImporter = false
    @State private var profile = AthleteProfile()
    @State private var garminKey = ""
    @State private var keyCreated = Date()
    @State private var keyPeriod = GarminKeyLifetime.Period.days90
    @State private var loaded = false
    @State private var saving = false
    @State private var error: String?
    @State private var status: String?
    @State private var thresholdEstimate: Double?
    @State private var estimateError: String?
    @State private var showsThresholdReview = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Sources") {
                    NavigationLink { Form { garminSettings }.navigationTitle("Garmin Connect") } label: {
                        SettingsSummaryRow(title: "Garmin Connect", symbol: "watch.analog", detail: model.garmin?.status ?? "Opening library…")
                    }
                    NavigationLink { Form { healthSettings }.navigationTitle("Apple Health") } label: {
                        SettingsSummaryRow(title: "Apple Health", symbol: "heart.fill", detail: model.health?.status ?? "Opening library…")
                    }
                    Button { showsImporter = true } label: {
                        SettingsSummaryRow(title: "Import FIT files", symbol: "doc")
                    }.disabled(model.library == nil || model.isImporting)
                }
                Section("Athlete profile") {
                    if let estimate = thresholdEstimate, estimate.rounded() > (profile.thresholdPower(on: .now) ?? 0) {
                        thresholdSuggestion(estimate)
                            .listRowBackground(Color.accentColor.opacity(0.12))
                    }
                    if let estimateError { Text(estimateError).font(.footnote).foregroundStyle(.secondary) }
                    NavigationLink { Form { thresholdHistory; zoneSettings(power: true); profileSave }.navigationTitle("Threshold power") } label: {
                        profileRow("Threshold power", symbol: "bolt.fill", value: profile.thresholdPower(on: .now).map { "\(Int($0)) W" } ?? "Not set")
                    }
                    NavigationLink { Form { athleteSettings; zoneSettings(power: false); profileSave }.navigationTitle("Heart rate and weight") } label: {
                        profileRow("Threshold heart rate", symbol: "heart.fill", value: profile.thresholdHeartRate.map { "\(Int($0)) bpm" } ?? "Not set", detail: profile.statedThresholdHeartRate == nil && profile.maxHeartRate != nil ? "Estimated" : nil)
                    }
                    NavigationLink { Form { athleteSettings; zoneSettings(power: false); profileSave }.navigationTitle("Heart rate and weight") } label: {
                        profileRow("Weight", symbol: "person", value: profile.weight.map { String(format: "%.1f kg", $0) } ?? "Not set")
                    }

                }
                if let library = model.library {
                    Section("Sync and storage") {
                        NavigationLink { Form { deepScanSettings }.navigationTitle("Deep scan") } label: {
                            SettingsSummaryRow(title: "Deep scan", symbol: "arrow.trianglehead.2.clockwise.rotate.90")
                        }
                        if let cloud = model.cloud {
                            NavigationLink { CloudSettingsView(cloud: cloud) } label: {
                                SettingsSummaryRow(title: "iCloud", symbol: "icloud", detail: cloud.status)
                            }
                        }
                        NavigationLink("Review duplicates and hidden activities") { LibraryReviewView(library: library) }
                    }
                }
                Section("Display") {
                    Picker("Units", selection: $profile.units) {
                        Text("Metric").tag(UnitSystem.metric)
                        Text("Imperial").tag(UnitSystem.imperial)
                    }
                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        LabeledContent("Appearance", value: (AppAppearance(rawValue: appearance) ?? .system).name)
                    }
                    Text("Save profile to apply unit changes.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                profileSave
            }
            .disabled(saving)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task {
                do {
                    await model.open()
                    if let library = model.library {
                        profile = try await library.profile(); loaded = true
                        await loadThresholdEstimate()
                    }
                    else { error = model.error }
                } catch { self.error = error.localizedDescription }
            }
        }
        .sheet(isPresented: $showsThresholdReview) {
            ThresholdSuggestionReview(profile: profile, estimate: thresholdEstimate ?? 0, saving: $saving, error: $error) { watts, date in
                await applyThresholdSuggestion(watts, effectiveFrom: date)
            }
        }
        .tint((AppTheme(rawValue: accent) ?? .cyan).color)
        .preferredColorScheme((AppAppearance(rawValue: appearance) ?? .system).colorScheme)
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): model.importFiles(urls); dismiss()
            case .failure(let failure): error = failure.localizedDescription
            }
        }
        .onDisappear { Task { await model.reload() } }
        .interactiveDismissDisabled(saving)
    }

    @ViewBuilder private var profileSave: some View {
        if let error { Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) } }
        if let status { Section { Text(status) } }
        Section {
            Button(saving ? "Saving and recalculating…" : "Save profile") { Task { await save() } }
                .disabled(!loaded || saving)
        }
    }

    @ViewBuilder private var healthSettings: some View {
        if let health = model.health {
            Section("Apple Health") {
                Text(health.status)
                if let backgroundStatus = HealthBackgroundDelivery.shared.status {
                    Text(backgroundStatus).font(.footnote).foregroundStyle(.secondary)
                }
                Button(health.enabled ? "Review Health access" : "Connect Apple Health") {
                    Task { await health.connect(); await model.reload() }
                }.disabled(health.running)
                if health.enabled {
                    Button("Refresh Health workouts") { Task { await health.sync(); await model.reload() } }
                        .disabled(health.running)
                    if health.running { Button("Pause Health refresh") { health.pause() } }
                }
                Text("Read-only access. Your workouts and samples stay on this device.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var garminSettings: some View {
        Section("Garmin") {
            if let garmin = model.garmin {
                Text(garmin.status)
                if let notice = garmin.expiryNotice() { Text(notice).foregroundStyle(.secondary) }
                SecureField("Personal API key", text: $garminKey)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                DatePicker("Key created", selection: $keyCreated, in: ...Date(), displayedComponents: .date)
                Picker("Key expiry period", selection: $keyPeriod) {
                    ForEach(GarminKeyLifetime.Period.allCases, id: \.self) { period in
                        Text(period == .year ? "1 year" : "\(period.rawValue) days").tag(period)
                    }
                }
                Text("Match the date and period in Garmin. Expiry reminders are estimates.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button(garmin.connected ? "Replace Garmin key" : "Connect Garmin") {
                    Task {
                        if await garmin.connect(key: garminKey, lifetime: GarminKeyLifetime(created: keyCreated, period: keyPeriod)) {
                            garminKey = ""
                            await garmin.sync()
                            await model.reload()
                        }
                    }
                }.disabled(garmin.running || garminKey.isEmpty)
                if garmin.connected {
                    Button("Sync activities") { Task { await garmin.sync(); await model.reload() } }
                        .disabled(!garmin.canSync)
                    Button("Reconcile all history and files") {
                        Task { await garmin.sync(.fullReconciliation(.all)); await model.reload() }
                    }.disabled(!garmin.canSync)
                    Text("Downloads all originals again to check for changes.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if garmin.running { Button("Pause sync") { garmin.pause() } }
                }
            }
        }
    }

    @ViewBuilder private var athleteSettings: some View {
        Section {
            optionalNumber("Maximum heart rate (bpm)", value: $profile.maxHeartRate)
            optionalNumber("Threshold heart rate (bpm)", value: $profile.statedThresholdHeartRate)
            optionalNumber("Weight (kg)", value: $profile.weight)
        } header: { Text("Athlete profile") } footer: {
            Text("Without a threshold, heart-rate zones use 90% of your maximum.")
        }
    }

    private var thresholdHistory: some View {
        Section {
            ForEach(profile.thresholdPowerHistory.indices, id: \.self) { index in
                VStack(alignment: .leading) {
                    DatePicker("Effective from", selection: $profile.thresholdPowerHistory[index].effectiveFrom,
                               displayedComponents: .date)
                    TextField("Threshold power (watts)", value: $profile.thresholdPowerHistory[index].watts, format: .number)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel("Threshold power in watts")
                }
            }
            .onDelete { profile.thresholdPowerHistory.remove(atOffsets: $0) }
            Button("Add threshold power") {
                profile.thresholdPowerHistory.append(.init(effectiveFrom: .now, watts: 0))
            }
        } header: { Text("Threshold power history") } footer: {
            Text("Changes recalculate activities from the effective date.")
        }
    }

    private func profileRow(_ title: String, symbol: String, value: String, detail: String? = nil) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                SettingsSummaryRow(title: title, symbol: symbol, detail: detail)
                Spacer(minLength: 12)
                Text(value).foregroundStyle(.secondary).monospacedDigit().fixedSize()
            }
            VStack(alignment: .leading, spacing: 4) {
                SettingsSummaryRow(title: title, symbol: symbol, detail: detail)
                Text(value).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }

    private func thresholdSuggestion(_ estimate: Double) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Suggested threshold: **\(Int(estimate.rounded())) W**.")
                .fixedSize(horizontal: false, vertical: true)
            Button("Review") {
                showsThresholdReview = true
            }.buttonStyle(.borderedProminent)
        }.padding(.vertical, 8)
    }

    private func loadThresholdEstimate() async {
        guard let library = model.library else { return }
        do {
            let history = try await library.trendsHistory()
            thresholdEstimate = await Task.detached(priority: .utility) {
                TrendsAggregation.estimate(history.matching(FeedFilter(sports: [.cycling])), on: Date())
            }.value
            estimateError = nil
        } catch { estimateError = "Threshold estimate could not load. Your saved profile is unchanged." }
    }

    private func applyThresholdSuggestion(_ watts: Double, effectiveFrom date: Date) async {
        guard watts.isFinite, watts > 0 else { return }
        let previous = profile
        let day = Calendar.current.startOfDay(for: date)
        profile.thresholdPowerHistory.removeAll { Calendar.current.isDate($0.effectiveFrom, inSameDayAs: day) }
        profile.thresholdPowerHistory.append(.init(effectiveFrom: day, watts: watts))
        if await save() { showsThresholdReview = false }
        else { profile = previous }
    }

    @ViewBuilder private var deepScanSettings: some View {
        if let garmin = model.garmin {
            Section {
                Text(garmin.status)
                Button("Reconcile all history and files") {
                    Task { await garmin.sync(.fullReconciliation(.all)); await model.reload() }
                }.disabled(!garmin.canSync)
                if garmin.running { Button("Pause sync") { garmin.pause() } }
            } footer: {
                Text("Downloads all originals again to check for changes.")
            }
        } else {
            Section { Text("Open the library and connect Garmin to scan your history.") }
        }
    }

    private func zoneSettings(power: Bool) -> some View {
        let key: WritableKeyPath<AthleteProfile, [Double]?> = power ? \.powerZoneBounds : \.heartRateZoneBounds
        let resolved = power ? ResolvedZones.power(profile: profile, on: .now) : ResolvedZones.heartRate(profile: profile)
        let bounds = profile[keyPath: key] ?? resolved.absoluteBounds
        let unit = power ? "W" : "bpm"
        return Section {
            Toggle("Custom boundaries", isOn: Binding(
                get: { profile[keyPath: key] != nil },
                set: { profile[keyPath: key] = $0 ? bounds : nil }
            ))
            ForEach(bounds.indices, id: \.self) { index in
                LabeledContent("Zone \(index + 2) starts at (\(unit))") {
                    if profile[keyPath: key] != nil {
                        TextField("Lower boundary", value: Binding(
                            get: { profile[keyPath: key]?[index] ?? bounds[index] },
                            set: { profile[keyPath: key]?[index] = $0 }
                        ), format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .accessibilityLabel("Zone \(index + 2) lower boundary in \(unit)")
                    } else {
                        Text(bounds[index], format: .number.precision(.fractionLength(0...1)))
                    }
                }
            }
            if profile[keyPath: key] != nil {
                Button("Reset to automatic zones") { profile[keyPath: key] = nil }
            }
        } header: {
            Text(power ? "Power zones" : "Heart-rate zones")
        } footer: {
            Text(profile[keyPath: key] != nil
                 ? "Custom boundaries override thresholds for all activities."
                 : resolved.isStarter
                 ? "Using a default \(power ? "200 W" : "170 bpm") threshold, excluded from training load."
                 : "Automatic zones use your threshold. Values shown are for today.")
        }
    }

    private func optionalNumber(_ title: String, value: Binding<Double?>) -> some View {
        LabeledContent(title) {
            TextField("Not set", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 65)
                .accessibilityLabel(title)
        }
    }

    @discardableResult
    private func save() async -> Bool {
        for (bounds, count) in [(profile.powerZoneBounds, 6), (profile.heartRateZoneBounds, 4)] {
            if let bounds, !AthleteProfile.validZoneBounds(bounds, count: count) {
                error = "Zone boundaries must be positive and increase from one zone to the next."
                return false
            }
        }
        let values = [profile.maxHeartRate, profile.statedThresholdHeartRate, profile.weight].compactMap { $0 }
            + profile.thresholdPowerHistory.map(\.watts)
        guard values.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            error = "Enter positive values, or leave optional values blank."; return false
        }
        let dates = profile.thresholdPowerHistory.map { Calendar.current.startOfDay(for: $0.effectiveFrom) }
        guard Set(dates).count == dates.count else {
            error = "Use one threshold power entry per effective date."; return false
        }
        guard let library = model.library else { return false }
        saving = true
        error = nil
        defer { saving = false }
        do {
            for index in profile.thresholdPowerHistory.indices {
                profile.thresholdPowerHistory[index].effectiveFrom = dates[index]
            }
            try await library.saveProfile(profile)
            do {
                let report = try await library.recompute()
                status = report.failures.isEmpty ? "Profile saved. Activities are up to date."
                    : "Profile saved. \(report.failures.count) activities could not be recalculated. Save again to retry."
            } catch {
                status = "Profile saved. Recalculation could not finish. Save again to retry."
            }
            await model.reload()
            NotificationCenter.default.post(name: AppTheme.profileDidChange, object: nil)
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
}
