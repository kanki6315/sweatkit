import SwiftUI

/// Interface accent only. Effort colours remain owned by SweatKitPalette.
enum AppTheme: String, CaseIterable, Identifiable {
    case cyan, lime, cobalt
    static let profileDidChange = Notification.Name("SweatKit.profileDidChange")
    static let preferenceKey = "appearance.accent"
    var id: String { rawValue }
    var name: String {
        switch self { case .cyan: "Electric Cyan"; case .lime: "Neon Lime"; case .cobalt: "Cobalt" }
    }
    var color: Color {
        Color(uiColor: UIColor { traits in
            let dark = traits.userInterfaceStyle == .dark
            let hex: UInt32 = switch self {
            case .cyan: dark ? 0x19D5EF : 0x006D85
            case .lime: dark ? 0xC5ED45 : 0x486500
            case .cobalt: dark ? 0x8DAEFF : 0x2455BD
            }
            return UIColor(red: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    static let preferenceKey = "appearance.colorScheme"
    var id: String { rawValue }
    var name: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct SettingsSummaryRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let title: String
    let symbol: String
    var detail: String? = nil
    var body: some View {
        HStack(spacing: 12) {
            if !typeSize.isAccessibilitySize {
                Image(systemName: symbol)
                    .font(.body.weight(.semibold))
                    .frame(width: 32, height: 36)
                    .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 9))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).foregroundStyle(Color.primary)
                if let detail { Text(detail).font(.footnote).foregroundStyle(Color.secondary).fixedSize(horizontal: false, vertical: true) }
            }
        }.padding(.vertical, 5)
    }
}
