import SwiftUI

/// One update from a pinch.
struct PinchValue: Sendable {
    /// How far the fingers have spread since the pinch began: 2 is twice as
    /// far apart.
    var scale: Double
    /// Where the middle of the fingers is, in points from the view's left
    /// edge.
    var x: Double
    /// How many fingers are down.
    var touches: Int
    var ended: Bool
}

extension View {
    /// Reports a pinch on this view, alongside its other gestures.
    ///
    /// On iOS the middle of the fingers is followed as it moves, so two
    /// fingers can pan as well as zoom. Elsewhere the pinch only zooms,
    /// around where it began.
    func onPinch(_ action: @escaping (PinchValue) -> Void) -> some View {
        #if canImport(UIKit)
        gesture(PinchRecognizer(action: action))
        #else
        simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    action(PinchValue(scale: value.magnification, x: value.startLocation.x, touches: 2, ended: false))
                }
                .onEnded { value in
                    action(PinchValue(scale: value.magnification, x: value.startLocation.x, touches: 2, ended: true))
                }
        )
        #endif
    }
}

#if canImport(UIKit)
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Wraps `TwoFingerRecognizer` for SwiftUI.
private struct PinchRecognizer: UIGestureRecognizerRepresentable {
    let action: (PinchValue) -> Void

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// The pinch runs alongside the drag that scrubs.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> TwoFingerRecognizer {
        let recognizer = TwoFingerRecognizer()
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: TwoFingerRecognizer, context: Context) {
        let ended: Bool
        switch recognizer.state {
        case .began, .changed: ended = false
        case .ended, .cancelled, .failed: ended = true
        default: return
        }
        action(PinchValue(
            scale: recognizer.scale,
            x: context.converter.localLocation.x,
            touches: recognizer.numberOfTouches,
            ended: ended
        ))
    }
}

/// Two fingers that spread, close or move together.
///
/// UIKit's pinch does not begin until the fingers change their distance, so
/// two fingers sliding side by side would never pan. This begins when the
/// distance between the fingers or the middle of them moves, and ends when
/// either finger lifts.
private final class TwoFingerRecognizer: UIGestureRecognizer {
    /// How far the fingers move, in points, before the gesture begins.
    static let slop: CGFloat = 8

    /// How far apart the fingers are, as a share of where they began.
    private(set) var scale: CGFloat = 1
    private var fingers: [UITouch] = []
    private var startDistance: CGFloat = 1
    private var startCentre = CGPoint.zero

    private var distance: CGFloat {
        guard fingers.count == 2 else { return 1 }
        let first = fingers[0].location(in: view), second = fingers[1].location(in: view)
        return max(hypot(first.x - second.x, first.y - second.y), 1)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches where fingers.count < 2 { fingers.append(touch) }
        if fingers.count == 2, state == .possible {
            startDistance = distance
            startCentre = location(in: view)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard fingers.count == 2 else { return }
        switch state {
        case .possible:
            let centre = location(in: view)
            let moved = hypot(centre.x - startCentre.x, centre.y - startCentre.y)
            if abs(distance - startDistance) > Self.slop || moved > Self.slop {
                // Measure from here, so the timeline does not jump by the slop.
                startDistance = distance
                scale = 1
                state = .began
            }
        case .began, .changed:
            scale = distance / startDistance
            state = .changed
        default:
            break
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        lift(touches, to: .ended)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        lift(touches, to: .cancelled)
    }

    private func lift(_ touches: Set<UITouch>, to finished: UIGestureRecognizer.State) {
        fingers.removeAll { touches.contains($0) }
        switch state {
        case .began, .changed: state = finished
        case .possible: if fingers.isEmpty { state = .failed }
        default: break
        }
    }

    override func reset() {
        fingers = []
        scale = 1
    }
}
#endif
