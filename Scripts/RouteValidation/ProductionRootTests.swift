import XCTest

/// Optional smoke test: install the production simulator app before adding this file to the harness test target.
final class ProductionRouteRoot: XCTestCase {
    @MainActor func testRoutesTabAndSettings() {
        let app = XCUIApplication(bundleIdentifier: "com.arjunakankipati.sweatkit")
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Routes"].waitForExistence(timeout: 30))
        app.tabBars.buttons["Routes"].tap()
        XCTAssertTrue(app.staticTexts["No routes yet"].waitForExistence(timeout: 30))
        let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        capture.name = "production-routes-empty"; capture.lifetime = .keepAlways; add(capture)
        app.buttons["Settings"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
    }
}
