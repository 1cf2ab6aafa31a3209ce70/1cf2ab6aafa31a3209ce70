import XCTest

/// Native input through the shared shell: play the first board with the
/// accessible tile controls and with a touch on the SpriteKit board, then
/// confirm the saved progress after relaunch.
final class TileTitleUITests: XCTestCase {
    @MainActor
    func testClearFirstBoardThenRelaunchContinuesWithTheSecond() {
        continueAfterFailure = false
        let app = launchTileTitle()
        tap(app, "shell.start")
        waitFor(app.staticTexts["shell.play"])
        // The first tile by touch on the board; the other five by button.
        let board = app.otherElements["tile.board"]
        waitFor(board)
        reveal(app, board)
        // intro-01 is three tiles by two, six half cells by four, centered
        // with a 12-point margin. Tile 0 is the top-left tile.
        let frame = board.frame
        let half = min((frame.width - 24) / 6, (frame.height - 24) / 4)
        let x = (frame.width - 6 * half) / 2 + half, y = (frame.height - 4 * half) / 2 + half
        board.coordinate(withNormalizedOffset: CGVector(dx: x / frame.width, dy: y / frame.height)).press(forDuration: 0.15)
        let remaining = app.staticTexts["tile.remaining"]
        reveal(app, remaining)
        XCTAssertTrue(remaining.wait(for: \.label, toEqual: "Tiles left: 5", timeout: queryAllowance),
                      "A touch on the board takes its tile")
        XCTAssertEqual(app.staticTexts["tile.tray.summary"].label, "Tray: Leaf; 6 slots free")
        for index in 1...5 { tap(app, "tile.cell.\(index)") }
        waitFor(app.staticTexts["shell.result.success"])
        XCTAssertEqual(app.staticTexts["shell.result.summary"].label, "Score: 12.")
        XCTAssertEqual(app.buttons["shell.result.retry"].label, "Next board")
        let status = app.staticTexts["save.status"]
        reveal(app, status)
        XCTAssertTrue(status.wait(for: \.label, toEqual: "Local data saved", timeout: queryAllowance))
        attachScreen("tile-cleared")

        app.terminate()
        app.launch()
        let progress = app.staticTexts["save.progress"]
        waitFor(progress)
        XCTAssertEqual(progress.label, "Completed levels: 1")
        tap(app, "shell.start")
        waitFor(app.staticTexts["shell.play"])
        XCTAssertTrue(app.buttons["tile.cell.8"].waitForExistence(timeout: queryAllowance), "The second board's top tile is free")
        XCTAssertFalse(app.buttons["tile.cell.1"].exists, "A covered tile is not a control")
    }

    /// intro-03's careless order fills the tray: the board stays on the play
    /// page, Undo takes the move back, and ending the board records nothing.
    @MainActor
    func testFullTrayOnTheThirdBoardOffersUndoAndEndingItRecordsNothing() {
        continueAfterFailure = false
        let app = launchTileTitle()
        tap(app, "shell.start")
        for index in 0...5 { tap(app, "tile.cell.\(index)") }
        waitFor(app.staticTexts["shell.result.success"])
        tap(app, "shell.result.retry")
        waitFor(app.staticTexts["shell.play"])
        for index in [0, 3, 4, 7, 8, 1, 2, 5, 6] { tap(app, "tile.cell.\(index)") }
        waitFor(app.staticTexts["shell.result.success"])
        tap(app, "shell.result.retry")
        waitFor(app.staticTexts["shell.play"])
        XCTAssertFalse(app.buttons["tile.undo"].exists, "Nothing to undo on a fresh board")
        for index in [8, 9, 11, 0, 7, 4, 10] { tap(app, "tile.cell.\(index)") }
        waitFor(app.staticTexts["tile.full"])
        XCTAssertFalse(app.buttons["tile.cell.1"].exists, "A full tray offers no tile")
        tap(app, "tile.undo")
        XCTAssertTrue(app.buttons["tile.cell.10"].waitForExistence(timeout: queryAllowance), "Undo puts the tile back")
        XCTAssertFalse(app.staticTexts["tile.full"].exists)
        tap(app, "tile.cell.10")
        waitFor(app.staticTexts["tile.full"])
        tap(app, "shell.fail")
        waitFor(app.staticTexts["shell.result.failure"])
        XCTAssertEqual(app.buttons["shell.result.retry"].label, "Try again")
        let progress = app.staticTexts["save.progress"]
        reveal(app, progress)
        XCTAssertEqual(progress.label, "Completed levels: 2")
        tap(app, "shell.result.menu")
        waitFor(app.staticTexts["shell.menu"])
    }
}
