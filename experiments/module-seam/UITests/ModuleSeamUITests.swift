import XCTest

final class ModuleSeamUITests: XCTestCase {
    func testNativeRendererInputCompletesAndPersistsSample() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--module-fixture", UUID().uuidString]
        app.launch()
        let start = app.buttons["shell.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.press(forDuration: 0.15)
        #if GRID_MODULE
        let surface = app.otherElements["grid.surface"]
        XCTAssertTrue(surface.waitForExistence(timeout: 10))
        // Top middle block is index 1 in the validated 3x2 sample.
        surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.28)).press(forDuration: 0.15)
        let removed = app.staticTexts["grid.removed"]
        reveal(removed, app: app)
        XCTAssertTrue(removed.waitForExistence(timeout: 5))
        XCTAssertEqual(removed.label, "Removed blocks: 1")
        for index in [0, 4] {
            let cell = app.buttons["grid.cell.\(index)"]
            reveal(cell, app: app); cell.press(forDuration: 0.15)
        }
        #else
        let cell = app.buttons["terrain.cell.8"]
        reveal(cell, app: app); XCTAssertTrue(cell.waitForExistence(timeout: 10)); cell.press(forDuration: 0.15)
        let surface = app.otherElements["terrain.surface"]
        reveal(surface, app: app)
        XCTAssertTrue(surface.waitForExistence(timeout: 10))
        // The virtual camera looks at the center column (index 4).
        surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.15)
        #endif
        let result = app.staticTexts["shell.result.success"]
        reveal(result, app: app)
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        let status = app.staticTexts["save.status"]
        reveal(status, app: app)
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(status.wait(for: \.label, toEqual: "Local data saved", timeout: 5))
        app.terminate(); app.launch()
        let progress = app.staticTexts["save.progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        XCTAssertEqual(progress.label, "Completed levels: 1")
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<5 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        for _ in 0..<5 {
            if element.exists && element.isHittable { return }
            app.swipeDown()
        }
    }
}
