import XCTest
final class RouteScreens: XCTestCase {
    @MainActor func testLight() { flow(dark: false) }
    @MainActor func testDark() { flow(dark: true) }
    @MainActor func testLargeText() {
        let app = XCUIApplication(); app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"]
        app.launch(); XCTAssertTrue(app.buttons["route-row"].firstMatch.waitForExistence(timeout: 120))
        capture("routes-large")
        app.buttons["route-row"].firstMatch.tap()
        XCTAssertTrue(app.buttons["By time"].waitForExistence(timeout: 20))
        capture("route-large")
        for _ in 0..<3 { if app.buttons["route-effort"].firstMatch.isHittable { break }; app.swipeUp() }
        app.buttons["route-effort"].firstMatch.tap()
        XCTAssertTrue(app.sliders["Shared comparison clock"].waitForExistence(timeout: 15))
        capture("comparison-large")
    }
    @MainActor func testReview() {
        let app = XCUIApplication(); app.launchArguments = ["review"]; app.launch()
        XCTAssertTrue(app.staticTexts["Needs a decision"].waitForExistence(timeout: 60))
        capture("routes-review")
        app.buttons["Keep separate"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["No routes yet"].waitForExistence(timeout: 30))
        capture("routes-review-separated")
    }
    @MainActor func testError() {
        let app = XCUIApplication(); app.launchArguments = ["error"]; app.launch()
        XCTAssertTrue(app.staticTexts["Routes couldn’t refresh"].waitForExistence(timeout: 120)); capture("routes-error")
        XCTAssertTrue(app.buttons["Try again"].exists)
    }
    @MainActor func testEmpty() {
        let app = XCUIApplication(); app.launchArguments = ["empty"]; app.launch()
        XCTAssertTrue(app.staticTexts["No routes yet"].waitForExistence(timeout: 120)); capture("routes-empty")
    }
    @MainActor private func flow(dark: Bool) {
        let app = XCUIApplication(); app.launchArguments = dark ? ["dark"] : []; app.launch()
        XCTAssertTrue(app.staticTexts["2 efforts · best"].waitForExistence(timeout: 1) || app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH '2 efforts · best'")).firstMatch.waitForExistence(timeout: 120))
        capture(dark ? "routes-dark" : "routes-light")
        app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH '2 efforts · best'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["By time"].waitForExistence(timeout: 20)); capture(dark ? "route-dark" : "route-light")
        app.swipeUp()
        app.buttons["Edit effort"].firstMatch.waitForExistence(timeout: 10)
        let row = app.buttons["route-effort"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap()
        XCTAssertTrue(app.staticTexts["Effort comparison"].waitForExistence(timeout: 15)); capture(dark ? "comparison-dark" : "comparison-light")
        let slider = app.sliders["Shared comparison clock"]
        XCTAssertTrue(slider.exists); let old = slider.value as? String; slider.adjust(toNormalizedSliderPosition: 0.55); XCTAssertNotEqual(old, slider.value as? String)
        capture(dark ? "scrub-dark" : "scrub-light")
        app.buttons["Play"].tap(); XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5)); app.buttons["Pause"].tap()
        app.swipeUp(); capture(dark ? "charts-dark" : "charts-light")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["By time"].waitForExistence(timeout: 10))
    }
    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
