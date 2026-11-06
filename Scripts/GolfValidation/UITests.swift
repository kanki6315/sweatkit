import XCTest
final class GolfScreens: XCTestCase {
    @MainActor func testGolfSummaryAndLocations() {
        continueAfterFailure = false
        for mode in ["light", "dark", "large", "empty"] {
            let app = XCUIApplication()
            app.launchArguments = mode == "large" ? ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] : [mode]
            app.launch()
            let open = app.buttons["Open synthetic golf recording"]
            XCTAssertTrue(open.waitForExistence(timeout: 60)); open.tap()
            XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Synthetic test recorder")).firstMatch.waitForExistence(timeout: 30))
            capture("golf-summary-" + mode)
            if mode == "empty" {
                XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Unavailable")).firstMatch.exists)
                XCTAssertTrue(app.staticTexts["No route locations in this Health recording."].exists)
                app.swipeUp()
                XCTAssertTrue(app.staticTexts["No measurement samples in this Health recording."].exists)
                capture("golf-empty")
            } else {
                let route = app.buttons["View recorded locations"]
                for _ in 0..<6 { if route.isHittable { break }; app.swipeUp() }
                XCTAssertTrue(route.isHittable); route.tap()
                XCTAssertTrue(app.navigationBars["Recorded locations"].waitForExistence(timeout: 10))
                capture("golf-locations-" + mode)
                app.navigationBars.buttons.element(boundBy: 0).tap()
                app.swipeUp()
                capture("golf-samples-" + mode)
            }
            app.terminate()
        }
    }
    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
