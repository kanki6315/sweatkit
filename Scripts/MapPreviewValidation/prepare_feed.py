#!/usr/bin/env python3
"""Show production feed thumbnails using the existing synthetic route fixtures."""
from pathlib import Path
import subprocess
import sys
repo = Path(__file__).resolve().parents[2]
out = Path(sys.argv[1]).resolve()
subprocess.run([sys.executable, str(repo / 'Scripts/RouteValidation/prepare.py'), str(out)], check=True)
harness = out / 'Harness.swift'
s = harness.read_text().replace('@State private var ready = false', '@State private var ready = false\n    @State private var filters = ActivityFeedFilters()')
s = s.replace('RoutesView(libraryModel: model).navigationTitle("Routes")', 'ActivityFeedView(model: model, filters: filters, showSettings: {})')
harness.write_text(s)
(out / 'UITests.swift').write_text('''import XCTest
final class MapFeedTests: XCTestCase {
    @MainActor func testFeedAndReturnFromFlyover() throws {
        let app = XCUIApplication()
        app.launch()
        let row = app.buttons.matching(identifier: "outdoor-activity-row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 60))
        // Allow the cold preview download before recording visual evidence.
        let settle = expectation(description: "Cold map preview")
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { settle.fulfill() }
        wait(for: [settle], timeout: 10)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "activity-feed-cached-map"
        image.lifetime = .keepAlways
        add(image)
        row.tap()
        XCTAssertTrue(app.buttons["Back"].firstMatch.waitForExistence(timeout: 30))
        app.buttons["Back"].firstMatch.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 15))
    }
}
''')
