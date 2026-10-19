import XCTest

final class __TARGET__UITests: XCTestCase {
    @MainActor
    func testCompleteTheFirstLevel() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", UUID().uuidString]
        app.launch()
        XCTAssertTrue(app.staticTexts["shell.menu"].waitForExistence(timeout: 15))
        tap(app, "shell.start")
        XCTAssertTrue(app.staticTexts["shell.play"].waitForExistence(timeout: 15))
        tap(app, "skeleton.step")
        tap(app, "skeleton.step")
        XCTAssertTrue(app.staticTexts["shell.result.success"].waitForExistence(timeout: 15))
    }

    @MainActor
    private func tap(_ app: XCUIApplication, _ id: String) {
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "Missing control \(id)")
        let scroll = app.scrollViews["shell.scroll"]
        for _ in 0..<6 where !button.isHittable { scroll.swipeUp() }
        button.press(forDuration: 0.15)
    }
}
