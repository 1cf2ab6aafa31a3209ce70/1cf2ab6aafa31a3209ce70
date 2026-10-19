import XCTest

/// Native input through the shared shell: play the first board with the
/// accessible block controls and with a touch on the SpriteKit board, then
/// confirm the saved progress after relaunch.
final class BlockTitleUITests: XCTestCase {
    @MainActor
    func testClearFirstBoardThenRelaunchContinuesWithTheSecond() {
        continueAfterFailure = false
        let app = launch()
        tap(app, "shell.start")
        waitFor(app.staticTexts["shell.play"])
        // Column 0 by touch on the board; the other two groups by button.
        let board = app.otherElements["block.board"]
        waitFor(board)
        reveal(app, board)
        // intro-01 is 3x3, centered with a 12-point margin. Index 3 is the
        // middle row's first column: one cell left of the board's center.
        let frame = board.frame
        let cell = min((frame.width - 24) / 3, (frame.height - 24) / 3)
        board.coordinate(withNormalizedOffset: CGVector(dx: (frame.width / 2 - cell) / frame.width, dy: 0.5))
            .press(forDuration: 0.15)
        let remaining = app.staticTexts["block.remaining"]
        reveal(app, remaining)
        XCTAssertTrue(remaining.wait(for: \.label, toEqual: "Blocks left: 4", timeout: 5),
                      "A touch on the board clears its group")
        tap(app, "block.cell.4")
        tap(app, "block.cell.5")
        waitFor(app.staticTexts["shell.result.success"])
        let status = app.staticTexts["save.status"]
        reveal(app, status)
        XCTAssertTrue(status.wait(for: \.label, toEqual: "Local data saved", timeout: 10))
        attachScreen("block-cleared")

        app.terminate()
        app.launch()
        let progress = app.staticTexts["save.progress"]
        waitFor(progress)
        XCTAssertEqual(progress.label, "Completed levels: 1")
        tap(app, "shell.start")
        waitFor(app.staticTexts["shell.play"])
        XCTAssertTrue(app.buttons["block.cell.15"].waitForExistence(timeout: 10), "The second board is 4x4")
    }

    @MainActor
    func testWrongFirstChoiceOnTheSecondBoardEndsWithoutProgress() {
        continueAfterFailure = false
        let app = launch()
        tap(app, "shell.start")
        for index in [3, 4, 5] { tap(app, "block.cell.\(index)") }
        waitFor(app.staticTexts["shell.result.success"])
        tap(app, "shell.result.retry")
        waitFor(app.staticTexts["shell.play"])
        tap(app, "block.cell.9")
        tap(app, "block.cell.8")
        waitFor(app.staticTexts["shell.result.failure"])
        let progress = app.staticTexts["save.progress"]
        reveal(app, progress)
        XCTAssertEqual(progress.label, "Completed levels: 1")
        tap(app, "shell.result.menu")
        waitFor(app.staticTexts["shell.menu"])
    }

    @MainActor
    private func launch() -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        // A fresh namespace isolates each test; relaunches keep the same one.
        let identity = UUID()
        app.launchArguments = ["--ui-test-fixture", identity.uuidString]
        app.launch()
        waitFor(app.staticTexts["shell.menu"])
        let status = app.staticTexts["save.status"]
        waitFor(status)
        XCTAssertTrue(status.wait(for: \.label, toEqual: "Local data saved", timeout: 10))
        return app
    }

    @MainActor
    private func waitFor(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 15), "Missing \(element)", file: file, line: line)
    }

    @MainActor
    private func tap(_ app: XCUIApplication, _ id: String) {
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "Missing control \(id)")
        reveal(app, button)
        XCTAssertTrue(button.isHittable, "Unreachable control \(id)")
        button.press(forDuration: 0.15)
    }

    /// Scroll the shell until the whole element is inside the window.
    @MainActor
    private func reveal(_ app: XCUIApplication, _ element: XCUIElement) {
        let scroll = app.scrollViews["shell.scroll"]
        for _ in 0..<10 {
            let window = app.windows.firstMatch.frame
            if element.exists && element.isHittable && window.contains(element.frame) { return }
            if element.exists && element.frame.minY < window.minY { scroll.swipeDown() } else { scroll.swipeUp() }
        }
    }

    @MainActor
    private func attachScreen(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
