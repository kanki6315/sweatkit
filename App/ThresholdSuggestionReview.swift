import SwiftUI
import SweatKitModel

/// Owns the editable draft so first presentation never reads a stale parent
/// snapshot while its TextField binding already displays a newer value.
struct ThresholdSuggestionReview: View {
    let profile: AthleteProfile
    @Binding var saving: Bool
    @Binding var error: String?
    let apply: (Double, Date) async -> Void
    @State private var watts: Double
    @State private var effectiveFrom = Date()
    @Environment(\.dismiss) private var dismiss

    init(profile: AthleteProfile, estimate: Double, saving: Binding<Bool>, error: Binding<String?>,
         apply: @escaping (Double, Date) async -> Void) {
        self.profile = profile
        self._watts = State(initialValue: estimate.rounded())
        self._saving = saving
        self._error = error
        self.apply = apply
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Current threshold", value: profile.thresholdPower(on: effectiveFrom).map { "\(Int($0)) W" } ?? "Not set")
                    LabeledContent("Suggested threshold") {
                        TextField("Watts", value: $watts, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            .accessibilityLabel("Suggested threshold in watts")
                    }
                    DatePicker("Effective from", selection: $effectiveFrom, in: ...Date(), displayedComponents: .date)
                    if profile.thresholdPowerHistory.contains(where: { Calendar.current.isDate($0.effectiveFrom, inSameDayAs: effectiveFrom) }) {
                        Text("This replaces the threshold already set for this date.").font(.footnote).foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("The estimate is 95% of your best valid 20-minute power in the last 90 days. Review it against your own knowledge before applying. Activities from the effective date will be recalculated; earlier history is preserved.")
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Section {
                    Button(saving ? "Applying and recalculating…" : "Apply threshold") {
                        Task { await apply(watts, effectiveFrom) }
                    }.disabled(saving || !watts.isFinite || watts <= 0)
                }
            }
            .disabled(saving)
            .navigationTitle("Review threshold")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) } }
        }.interactiveDismissDisabled(saving)
    }
}
