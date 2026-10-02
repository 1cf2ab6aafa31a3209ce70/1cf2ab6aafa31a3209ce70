import XCTest

final class DevelopmentTitleUITests: XCTestCase {
    @MainActor
    func testLaunchRotationAndForegrounding() {
        continueAfterFailure = false
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        let ready = app.staticTexts["foundation.ready"]
        XCTAssertTrue(ready.waitForExistence(timeout: 15))
        XCTAssertEqual(ready.label, "Foundation ready")
        waitForLayout(app, ready: ready, landscape: false)
        attachScreen("portrait")

        XCUIDevice.shared.orientation = .landscapeLeft
        waitForLayout(app, ready: ready, landscape: true)
        attachScreen("landscape")

        XCUIDevice.shared.orientation = .portrait
        waitForLayout(app, ready: ready, landscape: false)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(ready.waitForExistence(timeout: 10))
        waitForLayout(app, ready: ready, landscape: false)
    }

    @MainActor
    private func waitForLayout(_ app: XCUIApplication, ready: XCUIElement, landscape: Bool) {
        let contained = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let window = app.windows.firstMatch.frame
            guard window.width > 0, window.height > 0, ready.exists else { return false }
            let oriented = landscape ? window.width > window.height : window.height > window.width
            return oriented && ready.frame.width > 0 && ready.frame.height > 0
                && window.contains(ready.frame)
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [contained], timeout: 10), .completed)
    }

    @MainActor
    private func attachScreen(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
