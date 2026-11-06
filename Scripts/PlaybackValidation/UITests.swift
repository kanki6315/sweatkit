import XCTest

final class PlaybackAcceptance: XCTestCase {
    @MainActor func testOverviewReplayScrubAndActivityReset() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Ride fixture"].waitForExistence(timeout: 120))
        app.buttons["Ride fixture"].tap()
        let play = app.buttons["Play"]
        XCTAssertTrue(play.waitForExistence(timeout: 120))
        XCTAssertEqual(app.buttons["Playback speed"].value as? String, "1×")
        let started = Date()
        play.tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
        XCTAssertTrue(play.waitForExistence(timeout: 36))
        XCTAssertLessThan(Date().timeIntervalSince(started), 36)
        capture("overview-finished")
        play.tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
        app.buttons["Pause"].tap()
        app.buttons["Analysis"].tap()
        let slider = app.sliders["Analysis playback position"]
        XCTAssertTrue(slider.waitForExistence(timeout: 10))
        slider.adjust(toNormalizedSliderPosition: 0.5)
        XCTAssertTrue(app.buttons["Play"].exists)
        app.buttons["Done"].tap()
        app.buttons["Back"].tap()
        app.buttons["Walk fixture"].tap()
        XCTAssertTrue(play.waitForExistence(timeout: 120))
        let clock = app.otherElements["Activity elapsed time"]
        XCTAssertTrue(clock.waitForExistence(timeout: 10))
        XCTAssertTrue((clock.value as? String ?? "").hasPrefix("0:00 of"))
        capture("walk-reset")
        app.buttons["Back"].tap()
        app.buttons["Indoor fixture"].tap()
        XCTAssertTrue(play.waitForExistence(timeout: 120))
        play.tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
        XCTAssertTrue(play.waitForExistence(timeout: 36))
        capture("indoor-finished")
    }

    @MainActor func testManualCameraTakeoverAndResume() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Ride fixture"].waitForExistence(timeout: 120))
        app.buttons["Ride fixture"].tap()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 120))
        // Standard maps also support camera gestures and may be available
        // when satellite imagery is still loading in the simulator.
        app.buttons["Activity options"].tap()
        app.buttons["Satellite map"].tap()
        app.buttons["Playback speed"].tap()
        app.buttons["0.25×"].tap()
        app.buttons["Play"].tap()
        let fallback = app.otherElements["flyover-route-fallback"]
        if fallback.exists && !fallback.waitForNonExistence(timeout: 30) {
            capture("camera-map-unavailable")
            throw XCTSkip("MapKit imagery did not load; camera gesture acceptance requires a rendered map.")
        }
        app.buttons["Follow current position"].tap()
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 80, dy: 20)))
        let resume = app.buttons["Resume automatic camera following"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Pause"].exists)
        capture("manual-camera-playing")
        app.buttons["Analysis"].tap()
        let slider = app.sliders["Analysis playback position"]
        XCTAssertTrue(slider.waitForExistence(timeout: 10))
        slider.adjust(toNormalizedSliderPosition: 0.5)
        app.buttons["Done"].tap()
        XCTAssertTrue(resume.exists)
        XCTAssertTrue(app.buttons["Play"].exists)
        app.buttons["Play"].tap()
        resume.tap()
        XCTAssertTrue(app.buttons["Show whole route"].waitForExistence(timeout: 5))
        XCTAssertFalse(resume.exists)
        capture("camera-follow-resumed")
        let map = app.maps.firstMatch
        XCTAssertTrue(map.exists)
        map.pinch(withScale: 1.3, velocity: 1)
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        resume.tap()
        map.rotate(.pi / 6, withVelocity: 1)
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        capture("camera-rotated")
    }

    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
