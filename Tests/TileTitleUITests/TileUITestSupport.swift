import XCTest

/// Shared steps for the Few Tiles UI tests. One accessibility query on a
/// loaded hosted runner can stall for seconds (N08); waits bound only failures.
let queryAllowance: TimeInterval = 30

extension XCTestCase {
    /// Launch in a fresh save namespace and wait for the saved menu. Extra
    /// arguments are the DEBUG presentation overrides, such as
    /// `--shell-large-text` and `--shell-reduced-motion`.
    @MainActor
    func launchTileTitle(arguments: [String] = []) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        // A fresh namespace isolates each test; relaunches keep the same one.
        app.launchArguments = ["--ui-test-fixture", UUID().uuidString] + arguments
        app.launch()
        waitFor(app.staticTexts["shell.menu"])
        let status = app.staticTexts["save.status"]
        waitFor(status)
        XCTAssertTrue(status.wait(for: \.label, toEqual: "Local data saved", timeout: queryAllowance))
        return app
    }

    @MainActor
    func waitFor(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: queryAllowance), "Missing \(element)", file: file, line: line)
    }

    @MainActor
    func tap(_ app: XCUIApplication, _ id: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: queryAllowance), "Missing control \(id)", file: file, line: line)
        reveal(app, button)
        XCTAssertTrue(button.isHittable, "Unreachable control \(id)", file: file, line: line)
        button.press(forDuration: 0.15)
    }

    /// Scroll the shell until the whole element is inside the window.
    @MainActor
    func reveal(_ app: XCUIApplication, _ element: XCUIElement) {
        let scroll = app.scrollViews["shell.scroll"]
        for _ in 0..<10 {
            let window = app.windows.firstMatch.frame
            if element.exists && element.isHittable && window.contains(element.frame) { return }
            dragShell(app, scroll, towardEnd: !(element.exists && element.frame.minY < window.minY))
        }
    }

    /// Swipe the shell one step. A swipe that starts on the SpriteKit board
    /// does not scroll, and at the largest text sizes the board can cover the
    /// middle of the screen; then the swipe starts on the save status text.
    @MainActor
    func dragShell(_ app: XCUIApplication, _ scroll: XCUIElement, towardEnd: Bool) {
        let board = app.otherElements["tile.board"]
        let status = app.staticTexts["save.status"]
        let center = CGPoint(x: scroll.frame.midX, y: scroll.frame.midY)
        let onBoard = board.exists && board.frame.contains(center)
        let target = onBoard && status.exists && status.isHittable ? status : scroll
        if towardEnd { target.swipeUp() } else { target.swipeDown() }
    }

    @MainActor
    func attachScreen(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
