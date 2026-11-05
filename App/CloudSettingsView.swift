import SwiftUI

struct CloudSettingsView: View {
    let cloud: CloudConnection
    var body: some View {
        Form {
            Section {
                Toggle("Keep a private iCloud copy", isOn: Binding(get: { cloud.enabled }, set: { cloud.setEnabled($0) }))
                    .disabled(cloud.running)
            } footer: {
                Text("Garmin and imported originals, your profile and your decisions are copied to your private iCloud. Your library works offline.")
            }
            Section("Copy status") {
                Label(cloud.status, systemImage: cloud.detail == nil ? "icloud" : "exclamationmark.icloud")
                if cloud.running { ProgressView("Copying and recovering…") }
                if let detail = cloud.detail { Text(detail).foregroundStyle(.secondary) }
                if let date = cloud.lastConfirmed {
                    LabeledContent("Last confirmed copy") { Text(date, format: .dateTime.month().day().hour().minute()) }
                }
                if cloud.pending > 0 { Text("\(cloud.pending) records waiting to copy or remove").monospacedDigit() }
                Button("Sync and recover now") { Task { await cloud.sync() } }
                    .disabled(!cloud.enabled || cloud.running)
            }
            Section("Recovery") {
                Text("On a new device, enable this copy with the same Apple account. SweatKit downloads originals and decisions, then rebuilds activities and analysis.")
                Text("Apple Health workouts, samples, routes and summaries stay on this device. Connect Apple Health again to recover available workouts. Deleted Health-only workouts cannot be restored.")
                Text("Hidden and permanently deleted activities stay hidden or deleted. Your Garmin key stays in this device’s Keychain.")
            }.font(.body)
        }
        .navigationTitle("iCloud")
        .navigationBarTitleDisplayMode(.inline)
    }
}
