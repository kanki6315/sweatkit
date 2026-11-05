import SwiftUI

/// The surface of the floating layer: Liquid Glass over the map.
///
/// With Reduce Transparency on it is the system's opaque background instead.
/// With Increase Contrast on it gains a border. Nothing inside a panel is
/// glass, so glass is never stacked on glass.
struct FloatingPanel: ViewModifier {
    static let cornerRadius: CGFloat = 26

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    /// A neutral tint that pulls the glass towards the colour scheme's own
    /// background. Untinted glass turns mid-grey in Dark Mode over bright
    /// ground, such as snow, which leaves the labels too faint to read.
    static func tint(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.black.opacity(0.45) : Color.white.opacity(0.45)
    }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        Group {
            if reduceTransparency {
                content.background(.background, in: shape)
            } else {
                content.glassEffect(.regular.tint(Self.tint(for: colorScheme)), in: shape)
            }
        }
        .overlay {
            if contrast == .increased {
                shape.strokeBorder(.primary.opacity(0.7), lineWidth: 1)
            } else if reduceTransparency {
                shape.strokeBorder(.primary.opacity(0.15), lineWidth: 1)
            }
        }
    }
}
