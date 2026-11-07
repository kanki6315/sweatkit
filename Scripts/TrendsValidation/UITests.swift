import XCTest

final class TrendsInteractionTests: XCTestCase {
    @MainActor func testLight() { journey(dark: false) }
    @MainActor func testDark() { journey(dark: true) }
    @MainActor func testLargeText() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["Filter trends"].waitForExistence(timeout: 120))
        let chart = app.descendants(matching: .any)["power-chart"].firstMatch
        reveal(chart, in: app)
        center(chart, in: app)
        capture("power-large-chart", true)
        // The chart's AX frame includes its enlarged axis labels. Use a point
        // inside the rendered plot on the leased iPhone 17, verified in capture.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.6)).tap()
        reveal(app.buttons["clear-power-selection"], in: app)
        XCTAssertTrue(app.buttons["clear-power-selection"].exists)
        reveal(app.buttons["power-source-Last 6 weeks"], in: app)
        capture("power-large-readout", true)
        reveal(app.buttons["view-power-activities"], in: app)
        app.buttons["view-power-activities"].tap()
        capture("power-large-list", true)
        app.terminate()
    }
    @MainActor private func journey(dark: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = dark ? ["dark"] : []
        app.launch()
        XCTAssertTrue(app.buttons["Filter trends"].waitForExistence(timeout: 120))
        app.buttons["Filter trends"].tap()
        app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Date range,'")).firstMatch.tap()
        app.buttons["All time"].firstMatch.tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Volume"].waitForExistence(timeout: 120))
        let volumeChart = app.descendants(matching: .any)["volume-chart"].firstMatch
        XCTAssertTrue(volumeChart.exists)
        volumeChart.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["view-period-activities"].exists)
        // Clear and step from the latest bucket to the unchanged October fixture.
        app.buttons["Clear period selection"].tap()
        let previous = app.buttons["Previous"]
        reveal(previous, in: app)
        previous.tap()
        previous.tap()
        XCTAssertTrue(app.buttons["view-period-activities"].waitForExistence(timeout: 5))
        capture("volume-selected", dark)
        app.buttons["view-period-activities"].tap()
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 5))
        capture("period-detail", dark)
        app.navigationBars.buttons.firstMatch.tap()
        let readout = app.staticTexts["power-duration-readout"]
        reveal(readout, in: app)
        let chart = app.descendants(matching: .any)["power-chart"].firstMatch
        XCTAssertTrue(chart.exists)
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.45)).tap()
        let clear = app.buttons["clear-power-selection"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        // This assertion happens after finger-up and a separate run-loop turn.
        XCTAssertTrue(app.buttons["view-power-activities"].exists)
        let start = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.45))
        start.press(forDuration: 0.5, thenDragTo: chart.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.45)))
        XCTAssertTrue(clear.exists)
        capture("power-selected", dark)
        let source = app.buttons["power-source-Last 6 weeks"]
        reveal(source, in: app)
        source.tap()
        XCTAssertTrue(app.buttons["Analysis"].waitForExistence(timeout: 30))
        app.buttons["Back"].tap()
        XCTAssertTrue(clear.exists)
        reveal(app.buttons["view-power-activities"], in: app)
        app.buttons["view-power-activities"].tap()
        capture("power-activities", dark)
        app.navigationBars.buttons.firstMatch.tap()
        reveal(clear, in: app)
        clear.tap()
        XCTAssertFalse(app.buttons["view-power-activities"].exists)
        capture("power-cleared", dark)
        app.terminate()
    }
    @MainActor private func center(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<4 {
            let delta = element.frame.midY - app.frame.height * 0.4
            if abs(delta) < 30 { return }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.7))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: max(-350, min(350, -delta)))))
        }
    }
    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }
    @MainActor private func capture(_ name: String, _ dark: Bool) {
        // Navigation zoom transitions can outlive the runner's idle signal.
        Thread.sleep(forTimeInterval: 1)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name + (dark ? "-dark" : "-light")
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
