import XCTest
final class IntegratedScreens: XCTestCase {
    @MainActor func testBottomSearch() {
        for mode in ["dark", "light", "large"] {
            let app = XCUIApplication()
            app.launchArguments = mode == "dark" ? ["dark"] : mode == "large" ? ["dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"] : []
            app.launch()
            XCTAssertTrue(app.buttons["indoor-activity-row"].firstMatch.waitForExistence(timeout: 120))
            let search = app.tabBars.buttons["Search"]
            XCTAssertTrue(search.exists)
            XCTAssertGreaterThan(search.frame.midY, app.frame.height * 0.8)
            XCTAssertFalse(app.navigationBars.buttons["Search"].exists)
            XCTAssertFalse(app.searchFields.firstMatch.exists)
            capture("bottom-search-" + mode)
            search.tap()
            let field = app.searchFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 10))
            field.tap(); field.typeText("NoSuchActivity123")
            XCTAssertTrue(app.staticTexts["No matching activities"].waitForExistence(timeout: 20))
            capture("search-active-" + mode)
            app.buttons["Clear filters"].tap()
            XCTAssertTrue(app.buttons["indoor-activity-row"].firstMatch.waitForExistence(timeout: 20))
            if app.buttons["Close"].exists { app.buttons["Close"].tap() }
            app.tabBars.buttons["Activities"].tap()
            XCTAssertTrue(app.buttons["indoor-activity-row"].firstMatch.waitForExistence(timeout: 20))
            XCTAssertFalse(app.searchFields.firstMatch.exists)
            XCTAssertTrue(app.buttons["Settings"].isHittable)
            app.terminate()
        }
    }

    @MainActor func testLight() { flow(dark: false) }
    @MainActor func testDark() { flow(dark: true) }
    @MainActor func testHistoricalCurveLabels() {
        for dark in [false, true] {
            let app = XCUIApplication()
            let suffix = dark ? "dark" : "light"
            app.launchArguments = dark ? ["dark"] : []
            app.launch()
            XCTAssertTrue(app.tabBars.buttons["Activities"].waitForExistence(timeout: 120))
            let indoor = app.buttons["indoor-activity-row"].firstMatch
            XCTAssertTrue(indoor.waitForExistence(timeout: 30)); indoor.tap()
            XCTAssertTrue(app.buttons["Analysis"].waitForExistence(timeout: 60)); app.buttons["Analysis"].tap()
            let history = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Historical power window'")).firstMatch
            for _ in 0..<8 { if history.isHittable { break }; app.swipeUp() }
            XCTAssertTrue(history.exists)
            let sources = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Historical sources:'")).firstMatch
            XCTAssertTrue(sources.waitForExistence(timeout: 30))
            alignNearTop(history, in: app); capture("historical-curve-" + suffix)
            history.tap(); app.buttons["All time"].firstMatch.tap()
            XCTAssertTrue(sources.waitForExistence(timeout: 30))
            capture("historical-all-time-" + suffix)
            app.terminate()
        }
    }
    @MainActor func testRouteLinkAndLargeText() {
        let app = XCUIApplication()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Activities"].waitForExistence(timeout: 120))
        capture("feed-large")
        let ride = app.buttons.matching(NSPredicate(format: "identifier == 'outdoor-activity-row' AND label CONTAINS 'Morning ride'")).firstMatch
        for _ in 0..<8 { if ride.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(ride.exists); ride.tap()
        let compare = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Compare'")).firstMatch
        XCTAssertTrue(compare.waitForExistence(timeout: 120)); capture("detail-route-large")
        compare.tap()
        XCTAssertTrue(app.sliders["Shared comparison clock"].waitForExistence(timeout: 20))
        capture("detail-to-comparison-large")
    }
    @MainActor private func alignNearTop(_ element: XCUIElement, in app: XCUIApplication) {
        let target: CGFloat = 190
        for _ in 0..<3 {
            let delta = element.frame.minY - target
            if abs(delta) < 30 { return }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
            let distance = max(-250, min(400, delta))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -distance)),
                        withVelocity: .slow, thenHoldForDuration: 0.3)
        }
    }
    @MainActor private func capture(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    @MainActor private func flow(dark: Bool) {
        let app = XCUIApplication(); app.launchArguments = dark ? ["dark"] : []; app.launch()
        let suffix = dark ? "dark" : "light"
        XCTAssertTrue(app.tabBars.buttons["Activities"].waitForExistence(timeout: 120))
        // Wait for asynchronous thumbnail preparation before recording visual evidence.
        _ = app.images.firstMatch.waitForExistence(timeout: 5)
        Thread.sleep(forTimeInterval: 2)
        capture("01-feed-" + suffix)
        app.tabBars.buttons["Routes"].tap()
        let route = app.buttons["route-row"].firstMatch
        XCTAssertTrue(route.waitForExistence(timeout: 120)); capture("05-routes-" + suffix)
        route.tap(); XCTAssertTrue(app.buttons["By time"].waitForExistence(timeout: 20)); capture("06-route-" + suffix)
        for _ in 0..<3 { if app.buttons["route-effort"].firstMatch.isHittable { break }; app.swipeUp() }
        app.buttons["route-effort"].firstMatch.tap()
        XCTAssertTrue(app.sliders["Shared comparison clock"].waitForExistence(timeout: 20)); capture("07-comparison-" + suffix)
        let slider = app.sliders["Shared comparison clock"]; let before = slider.value as? String
        slider.adjust(toNormalizedSliderPosition: 0.55); XCTAssertNotEqual(before, slider.value as? String)
        app.navigationBars.buttons.firstMatch.tap(); app.navigationBars.buttons.firstMatch.tap()
        app.tabBars.buttons["Trends"].tap(); app.buttons["Filter trends"].tap()
        app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Date range,'")).firstMatch.tap(); app.buttons["All time"].firstMatch.tap(); app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Volume"].waitForExistence(timeout: 120)); capture("08-trends-" + suffix)
        app.tabBars.buttons["Activities"].tap()
        // The derived fixture is the newest activity and preserves real route geometry.
        let first = app.buttons["outdoor-activity-row"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 20)); first.tap()
        XCTAssertTrue(app.buttons["Analysis"].waitForExistence(timeout: 60)); capture("02-detail-" + suffix)
        app.buttons["Analysis"].tap(); XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10)); capture("03-analysis-" + suffix)
        let splits = app.staticTexts["Kilometre splits"].firstMatch
        for _ in 0..<6 { if splits.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(splits.exists)
        alignNearTop(splits, in: app)
        capture("analysis-content-" + suffix)
        capture("splits-table-" + suffix)
        app.buttons["Done"].tap(); app.buttons["Back"].tap()
        XCTAssertTrue(app.tabBars.buttons["Activities"].waitForExistence(timeout: 10))
        let indoor = app.buttons["indoor-activity-row"].firstMatch
        for _ in 0..<5 { if indoor.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(indoor.exists); indoor.tap()
        XCTAssertTrue(app.buttons["Analysis"].waitForExistence(timeout: 60)); capture("04-indoor-" + suffix)
        app.buttons["Analysis"].tap()
        let history = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Historical power window'")).firstMatch
        for _ in 0..<8 { if history.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(history.exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Historical sources:'")).firstMatch.waitForExistence(timeout: 30))
        alignNearTop(history, in: app)
        capture("historical-curve-" + suffix)
        history.tap(); app.buttons["All time"].firstMatch.tap()
        capture("historical-all-time-" + suffix)
        app.buttons["Done"].tap(); app.buttons["Back"].tap()
        app.buttons["Settings"].tap(); XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10)); capture("09-settings-" + suffix)
        let review = app.buttons["Review"].firstMatch
        for _ in 0..<3 { if review.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(review.waitForExistence(timeout: 30))
        if review.exists {
            review.tap(); XCTAssertTrue(app.navigationBars["Review threshold"].waitForExistence(timeout: 10))
            capture("threshold-review-" + suffix)
            XCTAssertTrue(app.buttons["Apply threshold"].isEnabled)
            app.buttons["Apply threshold"].tap()
            XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 30))
            XCTAssertTrue(app.navigationBars["Review threshold"].waitForNonExistence(timeout: 30))
            XCTAssertFalse(app.buttons["Review"].exists)
            capture("threshold-applied-" + suffix)
            app.buttons["Done"].tap(); app.buttons["Settings"].tap()
            XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["155 W"].waitForExistence(timeout: 30))
            XCTAssertFalse(app.buttons["Review"].exists)
        }
        app.swipeUp(); app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'iCloud'")).firstMatch.tap()
        capture("cloud-" + suffix)
    }
}
