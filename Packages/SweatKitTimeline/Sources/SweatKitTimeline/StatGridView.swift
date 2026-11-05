import SwiftUI

/// How large a grid of stats is set.
enum StatStyle {
    /// The stats panel: large numerals.
    case panel
    /// A range's stats inside the timeline: smaller, so they do not compete
    /// with the panel.
    case compact

    var valueFont: Font {
        switch self {
        case .panel: .title3.weight(.heavy)
        case .compact: .callout.weight(.bold)
        }
    }

    var labelFont: Font {
        switch self {
        case .panel: .caption
        case .compact: .caption2
        }
    }

    var unitFont: Font {
        switch self {
        case .panel: .caption.weight(.medium)
        case .compact: .caption2.weight(.medium)
        }
    }
}

/// One stat: its label above its numerals, with the unit beside them, smaller
/// and lighter.
///
/// The numerals use fixed-width digits and sit in a slot sized to the widest
/// value the stat can show, so nothing moves while the value changes.
struct StatSlotView: View {
    let slot: StatSlot
    let style: StatStyle

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let quiet: HierarchicalShapeStyle = contrast == .increased ? .primary : .secondary
        VStack(alignment: .leading, spacing: 0) {
            Text(slot.label)
                .font(style.labelFont)
                .foregroundStyle(quiet)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                // The numerals sit against their unit, so a value with
                // fewer digits leaves its space on the left.
                ZStack(alignment: .trailing) {
                    Text(slot.template).hidden()
                    Text(slot.stat.value)
                        .foregroundStyle(slot.stat.value == StatFormatter.missing ? quiet : .primary)
                }
                .font(style.valueFont)
                .monospacedDigit()
                if !slot.stat.unit.isEmpty {
                    Text(slot.stat.unit)
                        .font(style.unitFont)
                        .foregroundStyle(quiet)
                }
            }
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(slot.spokenLabel)
        .accessibilityValue(slot.stat.spoken)
    }
}

/// Lays stat slots out row by row in as many columns as fit, up to a
/// maximum. Each column is as wide as its widest slot and the columns are
/// spread across the width, at equal steps where they fit them. At large text sizes the slots are wider, so they
/// reflow to fewer columns instead of being cut short.
struct StatGridLayout: Layout {
    var maximumColumns: Int
    var spacing: CGFloat = 12
    var rowSpacing: CGFloat = 8

    private struct Arrangement {
        var sizes: [CGSize]
        var columnWidths: [CGFloat]
        var rowHeights: [CGFloat]

        var columns: Int { columnWidths.count }
        var naturalWidth: CGFloat { columnWidths.reduce(0, +) }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat?) -> Arrangement {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let widths = sizes.map { Double($0.width) }
        let columns = StatGrid.columns(
            available: width.map(Double.init) ?? .infinity,
            slotWidths: widths,
            spacing: spacing,
            maximum: maximumColumns
        )
        let columnWidths = StatGrid.columnWidths(slotWidths: widths, columns: columns).map { CGFloat($0) }
        var rowHeights: [CGFloat] = []
        for (index, size) in sizes.enumerated() {
            if index % columns == 0 { rowHeights.append(0) }
            rowHeights[rowHeights.count - 1] = max(rowHeights[rowHeights.count - 1], size.height)
        }
        return Arrangement(sizes: sizes, columnWidths: columnWidths, rowHeights: rowHeights)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let proposed = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        let arrangement = arrange(subviews, width: proposed)
        let natural = arrangement.naturalWidth + spacing * CGFloat(arrangement.columns - 1)
        let height = arrangement.rowHeights.reduce(0, +)
            + rowSpacing * CGFloat(max(0, arrangement.rowHeights.count - 1))
        return CGSize(width: proposed ?? natural, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrange(subviews, width: bounds.width)
        let columns = arrangement.columns
        let origins = StatGrid.columnOrigins(
            columnWidths: arrangement.columnWidths.map { Double($0) },
            available: Double(bounds.width),
            spacing: Double(spacing)
        )
        var y = bounds.minY
        for (index, subview) in subviews.enumerated() {
            let column = index % columns
            let row = index / columns
            if column == 0, row > 0 { y += arrangement.rowHeights[row - 1] + rowSpacing }
            let x = bounds.minX + CGFloat(origins[column])
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
        }
    }
}
