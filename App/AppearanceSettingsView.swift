import SwiftUI

struct AppearanceSettingsView: View {
    @AppStorage(AppTheme.preferenceKey) private var accent = AppTheme.cyan.rawValue
    @AppStorage(AppAppearance.preferenceKey) private var appearance = AppAppearance.system.rawValue

    private var theme: AppTheme { AppTheme(rawValue: accent) ?? .cyan }

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.name).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Preview") {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text("Activities").font(.title2.bold())
                        Spacer()
                        Image(systemName: "line.3.horizontal.decrease")
                            .foregroundStyle(theme.color)
                    }
                    Label("Morning ride", systemImage: "figure.outdoor.cycle")
                        .font(.headline)
                    HStack {
                        Text("24.8 km · 1h 12m")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Spacer()
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack { previewControls }
                        VStack(alignment: .leading, spacing: 12) { previewControls }
                    }
                }
                .padding(.vertical, 12)
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Preview of activity controls in \(theme.name)")
            }

            Section("Accent") {
                ForEach(AppTheme.allCases) { option in
                    Button {
                        accent = option.rawValue
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(option.color)
                                .frame(width: 28, height: 28)
                                .accessibilityHidden(true)
                            Text(option.name).foregroundStyle(.primary)
                            Spacer()
                            if theme == option {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(option.color)
                                    .accessibilityHidden(true)
                            }
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(theme == option ? [.isSelected] : [])
                }
            }
        }
        .tint(theme.color)
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var previewControls: some View {
        Button("Play flyover", systemImage: "play.fill") {}
            .buttonStyle(.borderedProminent)
        Button("View activity") {}
            .buttonStyle(.borderless)
    }
}

#Preview {
    NavigationStack { AppearanceSettingsView() }
}
