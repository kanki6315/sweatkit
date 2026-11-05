import SwiftUI

/// One colour of a data ramp, as an sRGB value.
public struct RampColor: Hashable, Sendable {
    /// The colour as `0xRRGGBB`.
    public let hex: UInt32

    public init(hex: UInt32) {
        self.hex = hex
    }

    /// Red, green and blue, each from 0 to 1.
    public var components: (red: Double, green: Double, blue: Double) {
        (
            Double((hex >> 16) & 0xFF) / 255,
            Double((hex >> 8) & 0xFF) / 255,
            Double(hex & 0xFF) / 255
        )
    }

    public var color: Color {
        let rgb = components
        return Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}
