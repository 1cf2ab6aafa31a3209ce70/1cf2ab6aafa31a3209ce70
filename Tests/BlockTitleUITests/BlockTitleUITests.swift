import XCTest

/// Native input through the shared shell: play the first board with the
/// accessible block controls and with a touch on the SpriteKit board, then
/// confirm the saved progress after relaunch.
final class BlockTitleUITests: XCTestCase {
    @MainActor
    func testClearFirstBoardThenRelaunchContinuesWithTheSecond() {
        continueAfterFailure = false
        let app = launchBlockTitle()
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
        XCTAssertTrue(remaining.wait(for: \.label, toEqual: "Blocks left: 4", timeout: queryAllowance),
                      "A touch on the board clears its group")
        tap(app, "block.cell.4")
        tap(app, "block.cell.5")
        waitFor(app.staticTexts["shell.result.success"])
        XCTAssertEqual(app.staticTexts["shell.result.summary"].label, "Score: 6.")
        XCTAssertEqual(app.buttons["shell.result.retry"].label, "Next board")
        let status = app.staticTexts["save.status"]
        reveal(app, status)
        XCTAssertTrue(status.wait(for: \.label, toEqual: "Local data saved", timeout: queryAllowance))
        attachScreen("block-cleared")

        app.terminate()
        app.launch()
        let progress = app.staticTexts["save.progress"]
        waitFor(progress)
        XCTAssertEqual(progress.label, "Completed levels: 1")
        tap(app, "shell.start")
        waitFor(app.staticTexts["shell.play"])
        XCTAssertTrue(app.buttons["block.cell.15"].waitForExistence(timeout: queryAllowance), "The second board is 4x4")
    }

    /// intro-02's wrong first choice strands a block: the board stays on the
    /// play page, Undo takes the move back, and ending the board records nothing.
    @MainActor
    func testStuckSecondBoardOffersUndoAndEndingItRecordsNothing() {
        continueAfterFailure = false
        let app = launchBlockTitle()
        tap(app, "shell.start")
        for index in [3, 4, 5] { tap(app, "block.cell.\(index)") }
        waitFor(app.staticTexts["shell.result.success"])
        tap(app, "shell.result.retry")
        waitFor(app.staticTexts["shell.play"])
        XCTAssertFalse(app.buttons["block.undo"].exists, "Nothing to undo on a fresh board")
        tap(app, "block.cell.9")
        tap(app, "block.cell.8")
        waitFor(app.staticTexts["block.stuck"])
        tap(app, "block.undo")
        XCTAssertTrue(app.buttons["block.cell.8"].waitForExistence(timeout: queryAllowance), "Undo restores the cleared group")
        XCTAssertFalse(app.staticTexts["block.stuck"].exists)
        tap(app, "block.cell.8")
        waitFor(app.staticTexts["block.stuck"])
        tap(app, "shell.fail")
        waitFor(app.staticTexts["shell.result.failure"])
        XCTAssertEqual(app.buttons["shell.result.retry"].label, "Try again")
        let progress = app.staticTexts["save.progress"]
        reveal(app, progress)
        XCTAssertEqual(progress.label, "Completed levels: 1")
        tap(app, "shell.result.menu")
        waitFor(app.staticTexts["shell.menu"])
    }
}
