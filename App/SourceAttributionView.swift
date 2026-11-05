import SwiftUI
import SweatKitModel

/// Source labels describe the records actually contributing to this surface.
struct SourceAttributionView: View {
    let sources: [SourceKind]
    var body: some View {
        Text(Self.names(sources))
            .font(.caption2).foregroundStyle(.secondary)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 4))
            .accessibilityLabel("Sources: " + Self.names(sources))
    }
    static func names(_ sources: [SourceKind]) -> String {
        Set(sources).sorted { $0.rawValue < $1.rawValue }.map {
            switch $0 { case .garmin: "Garmin"; case .healthKit: "Apple Health"; case .file: "FIT file" }
        }.joined(separator: " · ")
    }
}
