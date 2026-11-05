import Foundation

/// HealthKit's callback is not annotated Sendable in the SDK. The wrapper
/// transfers it to the main actor, while the lock makes late/expiration paths
/// exactly-once. Callbacks run outside the lock to allow reentrant completion.
final class HealthDeliveryCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var callback: (() -> Void)?
    init(_ callback: @escaping () -> Void) { self.callback = callback }
    func complete() {
        let action = lock.withLock { let value = callback; callback = nil; return value }
        action?()
    }
}
