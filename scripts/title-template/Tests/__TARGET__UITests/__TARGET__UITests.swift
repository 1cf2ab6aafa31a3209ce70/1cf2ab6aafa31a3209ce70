import XCTest

final class __TARGET__UITests: XCTestCase {
    /// One accessibility query on a loaded hosted runner can stall for
    /// seconds; waits bound only failures.
    private let queryAllowance: TimeInterval = 30

    @MainActor
    func testCompleteTheFirstLevel() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", UUID().uuidString]
        app.launch()
        XCTAssertTrue(app.staticTexts["shell.menu"].waitForExistence(timeout: queryAllowance))
        tap(app, "shell.start")
        XCTAssertTrue(app.staticTexts["shell.play"].waitForExistence(timeout: queryAllowance))
        tap(app, "skeleton.step")
        tap(app, "skeleton.step")
        XCTAssertTrue(app.staticTexts["shell.result.success"].waitForExistence(timeout: queryAllowance))
    }

    @MainActor
    private func tap(_ app: XCUIApplication, _ id: String) {
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: queryAllowance), "Missing control \(id)")
        let scroll = app.scrollViews["shell.scroll"]
        for _ in 0..<6 where !button.isHittable { scroll.swipeUp() }
        button.press(forDuration: 0.15)
    }
}
