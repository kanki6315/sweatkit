#if canImport(UIKit)
import SwiftUI
import UIKit

/// An independent overview: never waits for MapKit tiles or its overlay renderer.
@MainActor
final class RouteFallbackView: UIView {
    private var route: FlyoverRoute?
    private var projected: [CGPoint] = []
    private var colors: [UIColor] = []
    private var position = RoutePosition(segment: 0, fraction: 0)
    private var options = FlyoverOptions()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemBackground
        isOpaque = true
        isAccessibilityElement = true
        accessibilityLabel = "Route overview"
        accessibilityIdentifier = "flyover-route-fallback"
        contentMode = .redraw
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: RouteFallbackView, _) in
            view.setNeedsDisplay()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func update(route: FlyoverRoute, colors: [Color], position: RoutePosition, options: FlyoverOptions) {
        if self.route != route {
            self.route = route
            // Unwrap longitude so a route crossing the date line stays compact.
            var previousX: Double?
            projected = route.vertices.map {
                let point = Geodesy.mercator($0)
                var x = point.x
                if let previousX { x += (previousX - x).rounded() }
                previousX = x
                return CGPoint(x: x, y: -point.y)
            }
        }
        self.colors = colors.map { UIColor($0) }
        self.position = position
        self.options = options
        setNeedsDisplay()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let route, projected.count >= 2, let context = UIGraphicsGetCurrentContext() else { return }
        let area = bounds.inset(by: safeAreaInsets).insetBy(dx: 32, dy: 32)
        guard area.width > 0, area.height > 0 else { return }
        let minX = projected.map(\.x).min()!, maxX = projected.map(\.x).max()!
        let minY = projected.map(\.y).min()!, maxY = projected.map(\.y).max()!
        let scale = min(area.width / max(maxX - minX, 1e-9), area.height / max(maxY - minY, 1e-9))
        let points = projected.map {
            CGPoint(x: area.midX + ($0.x - (minX + maxX) / 2) * scale,
                    y: area.midY + ($0.y - (minY + maxY) / 2) * scale)
        }
        func stroke(_ a: CGPoint, _ b: CGPoint, color: UIColor, alpha: CGFloat) {
            context.setAlpha(alpha)
            context.setLineCap(.round)
            context.move(to: a); context.addLine(to: b)
            context.setStrokeColor(UIColor.black.withAlphaComponent(0.55).cgColor)
            context.setLineWidth(options.lineWidth + 3)
            context.strokePath()
            context.move(to: a); context.addLine(to: b)
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(options.lineWidth)
            context.strokePath()
        }
        let a = points[position.segment], b = points[position.segment + 1]
        let marker = CGPoint(x: a.x + (b.x - a.x) * position.fraction,
                             y: a.y + (b.y - a.y) * position.fraction)
        for index in 0..<(points.count - 1) {
            let band = route.bands[index]
            let color = colors.indices.contains(band) ? colors[band] : .gray
            let alpha = options.dimsAhead && index >= position.segment ? options.dimmedOpacity : 1
            stroke(points[index], points[index + 1], color: color, alpha: alpha)
            if options.dimsAhead && index == position.segment {
                stroke(points[index], marker, color: color, alpha: 1)
            }
        }
        context.setAlpha(1)
        let dot = CGRect(x: marker.x - 9, y: marker.y - 9, width: 18, height: 18)
        context.setFillColor(UIColor.white.cgColor)
        context.fillEllipse(in: dot)
        context.setStrokeColor(UIColor.black.withAlphaComponent(0.6).cgColor)
        context.setLineWidth(3)
        context.strokeEllipse(in: dot)
    }
}
#endif
