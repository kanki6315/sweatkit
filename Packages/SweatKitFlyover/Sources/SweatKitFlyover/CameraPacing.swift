import Foundation

/// Eases the camera along the route independently of the immediately responsive cursor.
struct CameraPacing {
    private(set) var distance: Double = 0

    mutating func reset(to distance: Double) { self.distance = distance }

    func hasSettled(on target: Double) -> Bool { abs(target - distance) < 0.5 }

    mutating func step(towards target: Double, seconds: Double) -> Double {
        guard target.isFinite, seconds.isFinite, seconds > 0 else { return distance }
        // Clamp long frame gaps so returning from a pause doesn't jump the camera.
        let fraction = 1 - exp(-min(seconds, 0.1) / 0.4)
        distance += (target - distance) * fraction
        if hasSettled(on: target) { distance = target }
        return distance
    }
}
