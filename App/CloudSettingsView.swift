import SwiftUI

struct CloudSettingsView: View {
    let cloud: CloudConnection
    var body: some View {
        Form {
            Section {
                Toggle("Keep a private iCloud copy", isOn: Binding(get: { cloud.enabled }, set: { cloud.setEnabled($0) }))
                    .disabled(cloud.running)
            } footer: {
                Text("Copies Garmin and imported files, your profile and library decisions. Excludes Apple Health data.")
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
                Text("Use the same Apple account on a new device. Reconnect Garmin and Apple Health.")
                Text("Permanently deleted activities cannot be restored.")
            }.font(.body)
        }
        .navigationTitle("iCloud")
        .navigationBarTitleDisplayMode(.inline)
    }
}
