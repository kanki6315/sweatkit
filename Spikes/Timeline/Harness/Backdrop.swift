import SwiftUI

/// Throwaway: what sits behind the glass. The drawn ones stand in for
/// satellite imagery of bright and dark ground, so text and glass can be
/// checked against both without waiting for map tiles.
enum Backdrop: String, CaseIterable, Identifiable {
    case map, snow, forest, mixed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .map: "Map"
        case .snow: "Bright ground"
        case .forest: "Dark ground"
        case .mixed: "Mixed ground"
        }
    }
}

/// Blotches of a few ground colours, placed the same way every time.
struct DrawnBackdrop: View {
    let backdrop: Backdrop

    private var palette: [Color] {
        switch backdrop {
        case .snow:
            [Color(hex: 0xFFFFFF), Color(hex: 0xF2F5F8), Color(hex: 0xE3EAF0), Color(hex: 0xF7EFD9), Color(hex: 0xEADFC0)]
        case .forest:
            [Color(hex: 0x0F1F12), Color(hex: 0x16301A), Color(hex: 0x1F3B22), Color(hex: 0x2A2A1C), Color(hex: 0x0A140C)]
        case .map, .mixed:
            [Color(hex: 0xF4F1E6), Color(hex: 0x1F3B22), Color(hex: 0xC9B58A), Color(hex: 0x5E7F4A), Color(hex: 0x30363C),
             Color(hex: 0xFFFFFF), Color(hex: 0x8A6F4D)]
        }
    }

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(palette[0]))
            var generator = Lehmer(seed: 20_261_105)
            var blurred = context
            blurred.addFilter(.blur(radius: 6))
            for _ in 0..<420 {
                let width = 30 + generator.unit() * 150
                let height = 20 + generator.unit() * 110
                let rect = CGRect(
                    x: generator.unit() * size.width - width / 2,
                    y: generator.unit() * size.height - height / 2,
                    width: width, height: height
                )
                let color = palette[Int(generator.unit() * Double(palette.count)) % palette.count]
                blurred.fill(
                    Path(roundedRect: rect, cornerRadius: min(width, height) / 3),
                    with: .color(color.opacity(0.55 + generator.unit() * 0.45))
                )
            }
            // Thin pale lines, like roads and paths.
            for _ in 0..<14 {
                var road = Path()
                road.move(to: CGPoint(x: generator.unit() * size.width, y: generator.unit() * size.height))
                for _ in 0..<4 {
                    road.addLine(to: CGPoint(x: generator.unit() * size.width, y: generator.unit() * size.height))
                }
                context.stroke(road, with: .color(.white.opacity(0.5)), lineWidth: 1.5)
            }
        }
    }
}

/// A small fixed-seed generator, so the backdrop never changes.
private struct Lehmer {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func unit() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(1 << 53)
    }
}
