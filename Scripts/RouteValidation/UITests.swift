import XCTest
final class RouteScreens: XCTestCase {
    @MainActor func testDevelopingLight() { inspectDeveloping(arguments: []) }
    @MainActor func testDevelopingDark() { inspectDeveloping(arguments: ["dark"]) }
    @MainActor func testDevelopingLargeText() {
        inspectDeveloping(arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"])
    }
    @MainActor private func inspectDeveloping(arguments: [String]) {
        let app = XCUIApplication()
        app.launchArguments = ["developing"] + arguments
        app.launch()
        let group = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Building history'")).firstMatch
        XCTAssertTrue(group.waitForExistence(timeout: 120))
        group.tap()
        app.buttons["developing-route-row"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["3 confirmed outings"].waitForExistence(timeout: 10))
        capture("history-\(arguments.first ?? "light")")
        let outing = app.buttons["route-history-outing"].firstMatch
        for _ in 0..<6 {
            if outing.isHittable { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.85))
                .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.25)))
        }
        outing.tap()
        XCTAssertTrue(app.navigationBars["Inspect outing"].waitForExistence(timeout: 15))
        capture("overlay-\(arguments.first ?? "light")")
        for _ in 0..<5 {
            if app.staticTexts["The pair passes the alignment checks."].isHittable { break }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.85))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.25))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        XCTAssertTrue(app.staticTexts["The pair passes the alignment checks."].waitForExistence(timeout: 15))
        capture("evidence-\(arguments.first ?? "light")")
    }
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
        let optional = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Optional review'")).firstMatch
        XCTAssertTrue(optional.waitForExistence(timeout: 60))
        capture("routes-review-collapsed")
        optional.tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'possible route'")).firstMatch.tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'nearby parallel line'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Keep separate"].waitForExistence(timeout: 20))
        capture("routes-review-map")
        app.buttons["Keep separate"].tap()
        XCTAssertTrue(app.staticTexts["Review complete"].waitForExistence(timeout: 30))
        app.buttons["Back to Routes"].tap()
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Optional review'")).firstMatch.exists)
        XCTAssertTrue(app.buttons["route-row"].firstMatch.waitForExistence(timeout: 30))
        capture("routes-review-separated")
    }
    @MainActor func testError() {
        let app = XCUIApplication(); app.launchArguments = ["error"]; app.launch()
        XCTAssertTrue(app.staticTexts["Routes couldn’t refresh"].waitForExistence(timeout: 120)); capture("routes-error")
        XCTAssertTrue(app.buttons["Try again"].exists)
    }
    @MainActor func testEmpty() {
        let app = XCUIApplication(); app.launchArguments = ["empty"]; app.launch()
        XCTAssertTrue(app.staticTexts["No frequent routes yet"].waitForExistence(timeout: 120)); capture("routes-empty")
    }
    @MainActor private func flow(dark: Bool) {
        let app = XCUIApplication(); app.launchArguments = dark ? ["dark"] : []; app.launch()
        XCTAssertTrue(app.staticTexts["5 efforts · best"].waitForExistence(timeout: 1) || app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH '5 efforts · best'")).firstMatch.waitForExistence(timeout: 120))
        capture(dark ? "routes-dark" : "routes-light")
        app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH '5 efforts · best'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["By time"].waitForExistence(timeout: 20)); capture(dark ? "route-dark" : "route-light")
        app.swipeUp()
        app.buttons["Edit effort"].firstMatch.waitForExistence(timeout: 10)
        let row = app.buttons["route-effort"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap()
        XCTAssertTrue(app.sliders["Shared comparison clock"].waitForExistence(timeout: 15)); capture(dark ? "comparison-dark" : "comparison-light")
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
