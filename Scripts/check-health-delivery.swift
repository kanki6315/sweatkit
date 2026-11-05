// Host check using the production callback wrapper, no simulator/Health data.
// swiftc -parse-as-library App/HealthDeliveryCompletion.swift Scripts/check-health-delivery.swift -o /tmp/check-health-delivery
// /tmp/check-health-delivery
import Foundation
import Dispatch

@main struct CheckHealthDelivery {
    static func main() {
        for _ in 0..<100 {
            let count = Count()
            let completion = HealthDeliveryCompletion { count.increment() }
            DispatchQueue.concurrentPerform(iterations: 100) { _ in completion.complete() }
            precondition(count.value == 1, "Delivery must complete exactly once")
        }
        let slot = Slot()
        slot.completion = HealthDeliveryCompletion { slot.completion?.complete() }
        slot.completion?.complete() // Must not deadlock when the callback reenters.
        print("Health delivery completion: 100 concurrent races and reentrant completion passed.")
    }
}
private final class Count: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = 0
    var value: Int { lock.withLock { stored } }
    func increment() { lock.withLock { stored += 1 } }
}
private final class Slot { var completion: HealthDeliveryCompletion? }
