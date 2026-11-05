import Testing
@testable import SweatKitFlyover

@Suite struct CameraPacingTests {
    @Test func easesAndSettlesInBothDirections() {
        var camera = CameraPacing()
        camera.reset(to: 100)
        let first = camera.step(towards: 1000, seconds: 1.0 / 30)
        #expect(first > 100 && first < 200)
        for _ in 0..<150 { _ = camera.step(towards: 1000, seconds: 1.0 / 30) }
        #expect(camera.distance == 1000)
        for _ in 0..<150 { _ = camera.step(towards: 0, seconds: 1.0 / 30) }
        #expect(camera.distance == 0)
    }

    @Test func ignoresInvalidInputAndBoundsPauseJump() {
        var camera = CameraPacing()
        #expect(camera.step(towards: .nan, seconds: 1) == 0)
        #expect(camera.step(towards: 1000, seconds: -1) == 0)
        #expect(camera.step(towards: 1000, seconds: 60) < 250)
    }
}
