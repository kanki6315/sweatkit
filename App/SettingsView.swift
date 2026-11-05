import SwiftUI
import SweatKitModel
import SweatKitAnalysis
import SweatKitSync

struct SettingsView: View {
    let model: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var profile = AthleteProfile()
    @State private var garminKey = ""
    @State private var keyCreated = Date()
    @State private var keyPeriod = GarminKeyLifetime.Period.days90
    @State private var loaded = false
    @State private var saving = false
    @State private var error: String?
    @State private var status: String?

    var body: some View {
        NavigationStack {
            Form {
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
                        Text("Use the creation date and period chosen in Garmin. The expiry reminder is an estimate; Garmin does not report the expiry date.")
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
                            Text("Full reconciliation checks all history and downloads every original again. Unchanged files do not create new revisions. You can pause and resume.")
                                .font(.footnote).foregroundStyle(.secondary)
                            if garmin.running { Button("Pause sync") { garmin.pause() } }
                        }
                        Text("Your key stays in this device’s Keychain. Garmin supplies the activity data.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let library = model.library {
                    Section("Library") {
                        NavigationLink("Review duplicates and hidden activities") { LibraryReviewView(library: library) }
                    }
                }
                Section("Units") {
                    Picker("Distance and speed", selection: $profile.units) {
                        Text("Metric").tag(UnitSystem.metric)
                        Text("Imperial").tag(UnitSystem.imperial)
                    }
                }
                Section {
                    optionalNumber("Maximum heart rate (bpm)", value: $profile.maxHeartRate)
                    optionalNumber("Threshold heart rate (bpm)", value: $profile.statedThresholdHeartRate)
                    optionalNumber("Weight (kg)", value: $profile.weight)
                } header: { Text("Athlete profile") } footer: {
                    Text("Leave unknown values blank. Without a threshold heart rate, zones use 90% of your maximum heart rate when set. Starter zones apply when neither is known.")
                }
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
                    Text("Each value applies from its date until the next entry. Corrections recalculate the affected activities. Swipe an entry to delete it.")
                }
                zoneSettings(power: true)
                zoneSettings(power: false)
                if let error { Section { Text(error).foregroundStyle(.red) } }
                if let status { Section { Text(status) } }
                Section {
                    Button(saving ? "Saving and recalculating…" : "Save profile") { Task { await save() } }
                        .disabled(!loaded || saving)
                }
            }
            .disabled(saving)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task {
                do {
                    await model.open()
                    if let library = model.library { profile = try await library.profile(); loaded = true }
                    else { error = model.error }
                } catch { self.error = error.localizedDescription }
            }
        }
        .interactiveDismissDisabled(saving)
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
                 ? "Boundaries must increase. Zone 1 is below the first boundary; the last zone has no upper limit. Custom boundaries apply to all activities and override thresholds for zone colours and totals."
                 : resolved.isStarter
                 ? "Starter zones use an assumed \(power ? "200 W" : "170 bpm") threshold. Set your personal threshold above or turn on custom boundaries. Starter values are not used for training load."
                 : "Automatic zones follow your personal threshold. Power zones follow the threshold in effect on each activity’s date. Values shown are for today.")
        }
    }

    private func optionalNumber(_ title: String, value: Binding<Double?>) -> some View {
        TextField(title, value: value, format: .number)
            .keyboardType(.decimalPad)
            .accessibilityLabel(title)
    }

    private func save() async {
        for (bounds, count) in [(profile.powerZoneBounds, 6), (profile.heartRateZoneBounds, 4)] {
            if let bounds, !AthleteProfile.validZoneBounds(bounds, count: count) {
                error = "Zone boundaries must be positive and increase from one zone to the next."
                return
            }
        }
        let values = [profile.maxHeartRate, profile.statedThresholdHeartRate, profile.weight].compactMap { $0 }
            + profile.thresholdPowerHistory.map(\.watts)
        guard values.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            error = "Enter positive values, or leave optional values blank."; return
        }
        let dates = profile.thresholdPowerHistory.map { Calendar.current.startOfDay(for: $0.effectiveFrom) }
        guard Set(dates).count == dates.count else {
            error = "Use one threshold power entry per effective date."; return
        }
        guard let library = model.library else { return }
        saving = true
        error = nil
        defer { saving = false }
        do {
            for index in profile.thresholdPowerHistory.indices {
                profile.thresholdPowerHistory[index].effectiveFrom = dates[index]
            }
            try await library.saveProfile(profile)
            let report = try await library.recompute()
            status = report.failures.isEmpty ? "Profile saved. Activities are up to date."
                : "Profile saved. \(report.failures.count) activities could not be recalculated. Save again to retry."
            await model.reload()
        } catch { self.error = error.localizedDescription }
    }
}
