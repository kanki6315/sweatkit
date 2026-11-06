import XCTest

final class ScrollTests: XCTestCase {
    @MainActor func testLongFeedAndReturnFromDetail() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Activities"].waitForExistence(timeout: 180), app.debugDescription)
        for _ in 0..<14 { app.swipeUp(velocity: .fast) }
        let row = app.buttons.matching(identifier: "outdoor-activity-row").allElementsBoundByIndex.first { $0.isHittable && $0.frame.minY > app.frame.height * 0.35 && $0.frame.maxY < app.frame.height * 0.75 }
        XCTAssertNotNil(row)
        guard let row else { return }
        let label = row.label
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "long-feed-scrolled"
        attachment.lifetime = .keepAlways
        add(attachment)
        row.tap()
        XCTAssertTrue(app.buttons["Analysis"].waitForExistence(timeout: 30))
        app.buttons["Back"].firstMatch.tap()
        let returned = app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
        XCTAssertTrue(returned.waitForExistence(timeout: 15))
        XCTAssertTrue(returned.isHittable)
    }
}
