import SweatKitModel
import SwiftUI

/// The glass panel that floats at the top of the detail screen and shows the
/// values at the cursor.
///
/// Cycling shows distance, elapsed time, speed, 3-second power, heart rate,
/// cadence, elevation and gradient. Walking, running and hiking show pace in
/// place of speed and have no power. A value the caller leaves nil shows as a
/// dash, never as zero.
///
/// Every numeral has fixed-width digits in a fixed-width slot. The slots
/// reflow to fewer columns at large text sizes, and scroll when they are
/// taller than the space the panel is given.
public struct StatsPanel: View {
    private let stats: CursorStats
    private let sport: Sport
    private let units: UnitSystem

    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .title3) private var minimumHeight: CGFloat = 44

    public init(stats: CursorStats, sport: Sport, units: UnitSystem = .metric) {
        self.stats = stats
        self.sport = sport
        self.units = units
    }

    public var body: some View {
        let slots = StatSlots.cursor(stats, sport: sport, units: units, locale: locale)
        ViewThatFits(in: .vertical) {
            grid(slots)
            ScrollView { grid(slots) }
        }
        // Squeezed for space, the panel still shows about one row.
        .frame(minHeight: minimumHeight)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .modifier(FloatingPanel())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Stats at the cursor")
    }

    private func grid(_ slots: [StatSlot]) -> some View {
        StatGridLayout(maximumColumns: 4) {
            ForEach(slots) { StatSlotView(slot: $0, style: .panel) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
