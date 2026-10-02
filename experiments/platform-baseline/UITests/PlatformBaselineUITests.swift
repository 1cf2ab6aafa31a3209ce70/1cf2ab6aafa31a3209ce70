import XCTest

final class PlatformBaselineUITests: XCTestCase {
    @MainActor
    func testBoardPanelTerrainAndLifecycle() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        #if os(macOS)
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        #endif
        app.launch()
        XCTAssertTrue(app.buttons["mode.blocks"].waitForExistence(timeout: 15))
        let surface = app.descendants(matching: .any)["probe.renderer"].firstMatch
        XCTAssertTrue(surface.waitForExistence(timeout: 5))
        activate(surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        waitForAction(app, containing: "blocks: cell")
        #if os(macOS)
        app.typeKey(.rightArrow, modifierFlags: [])
        let keyboard = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "\(textAttribute) CONTAINS 'Keyboard selected cell'"),
            object: app.staticTexts["metrics.action"])
        XCTAssertEqual(XCTWaiter.wait(for: [keyboard], timeout: 5), .completed)
        app.typeKey(.space, modifierFlags: [])
        waitForAction(app, containing: "blocks: cell")
        #endif
        attachSummary(app, phase: "blocks")
        activate(app.buttons["probe.pause"])
        XCTAssertEqual(app.buttons["probe.pause"].label, "Resume")
        activate(surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        XCTAssertFalse(text(app.staticTexts["metrics.action"]).contains(": cell"),
                       "Paused input must not activate a board cell; resize diagnostics may still arrive.")
        activate(app.buttons["probe.pause"])
        activate(app.buttons["mode.panel"])
        activate(surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        waitForAction(app, containing: "panel: cell")
        attachSummary(app, phase: "panel")
        activate(app.buttons["mode.terrain"])
        XCTAssertTrue(app.buttons["terrain.drill"].waitForExistence(timeout: 20))
        waitForTerrainRevision(app, revision: 1)
        activate(app.buttons["terrain.drill"])
        waitForTerrainRevision(app, revision: 2)
        let terrainResult = app.staticTexts["metrics.terrain"]
        XCTAssertTrue(terrainResult.waitForExistence(timeout: 10))
        let contact = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "\(textAttribute) CONTAINS 'Sphere contact' AND \(textAttribute) CONTAINS 'revision=2'"),
            object: app.staticTexts["terrain.collision"])
        XCTAssertEqual(XCTWaiter.wait(for: [contact], timeout: 15), .completed)
        let contactLabel = text(app.staticTexts["terrain.collision"])
        print("SPIKE00 CONTACT: \(contactLabel)")
        let settled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "\(textAttribute) CONTAINS 'Sphere settled' AND \(textAttribute) CONTAINS 'revision=2'"),
            object: app.staticTexts["terrain.settled"])
        let settledWait = XCTWaiter.wait(for: [settled], timeout: 15)
        print("SPIKE00 SETTLED CURRENT: \(text(app.staticTexts["terrain.settled"]))")
        XCTAssertEqual(settledWait, .completed)
        let settledLabel = text(app.staticTexts["terrain.settled"])
        let yValue = settledLabel.split(separator: " ").first { $0.hasPrefix("y=") }?.dropFirst(2)
        let settledY = try XCTUnwrap(yValue.flatMap { Double($0) })
        print("SPIKE00 SETTLED: \(settledLabel)")
        XCTAssertLessThan(settledY, 0.05, "Sphere must settle on the excavated patch below the flat-surface height of 0.06.")
        print("SPIKE00 MESH: \(text(app.staticTexts["terrainStatus"]))")
        attachSummary(app, phase: "terrain")
        let terrainSurface = app.descendants(matching: .any)["terrain.surface"].firstMatch
        XCTAssertTrue(terrainSurface.waitForExistence(timeout: 5))
        activate(terrainSurface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)))
        waitForTerrainRevision(app, revision: 3)
        print("SPIKE00 SURFACE: \(text(app.staticTexts["terrainStatus"]))")
        activate(app.buttons["terrain.reset"])
        waitForTerrainRevision(app, revision: 4)
        #if os(iOS)
        XCUIDevice.shared.orientation = .landscapeLeft
        waitForOrientation(app, landscape: true)
        waitForTerrainRevision(app, revision: 4)
        activate(app.buttons["terrain.drill"])
        waitForTerrainRevision(app, revision: 5)
        waitForLandscapeControls(app)
        attachScreenshot(app, name: "landscape")
        XCUIDevice.shared.orientation = .portrait
        waitForOrientation(app, landscape: false)
        waitForTerrainRevision(app, revision: 5)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["mode.blocks"].waitForExistence(timeout: 10))
        #endif
        activate(app.buttons["mode.blocks"])
        XCTAssertTrue(surface.waitForExistence(timeout: 10))
        attachSummary(app, phase: "resume")
    }

    private var textAttribute: String {
        #if os(macOS)
        return "value"
        #else
        return "label"
        #endif
    }

    @MainActor
    private func text(_ element: XCUIElement) -> String {
        #if os(macOS)
        return element.value as? String ?? element.label
        #else
        return element.label
        #endif
    }

    @MainActor
    private func activate(_ element: XCUIElement) {
        #if os(macOS)
        element.click()
        #else
        element.tap()
        #endif
    }

    @MainActor
    private func activate(_ coordinate: XCUICoordinate) {
        #if os(macOS)
        coordinate.click()
        #else
        coordinate.tap()
        #endif
    }

    @MainActor
    private func waitForOrientation(_ app: XCUIApplication, landscape: Bool) {
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { object, _ in
            guard let window = object as? XCUIElement else { return false }
            return landscape ? window.frame.width > window.frame.height : window.frame.height > window.frame.width
        }, object: app.windows.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 10), .completed)
    }

    @MainActor
    private func waitForLandscapeControls(_ app: XCUIApplication) {
        let elements = [app.buttons["probe.pause"], app.buttons["terrain.drill"],
                        app.buttons["terrain.reset"],
                        app.descendants(matching: .any)["terrain.surface"].firstMatch]
        let contained = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let window = app.windows.firstMatch.frame
            guard window.width > window.height else { return false }
            return elements.allSatisfy { element in
                guard element.exists else { return false }
                let frame = element.frame
                return frame.width > 0 && frame.height > 0
                    && window.insetBy(dx: -1, dy: -1).contains(frame)
            }
        }, object: app)
        let result = XCTWaiter.wait(for: [contained], timeout: 10)
        print("SPIKE00 LANDSCAPE WINDOW: \(app.windows.firstMatch.frame)")
        for element in elements { print("SPIKE00 LANDSCAPE CONTROL: \(element.identifier) \(element.frame)") }
        XCTAssertEqual(result, .completed, "Landscape render surface and controls must fit inside the window.")
    }

    @MainActor
    private func waitForTerrainRevision(_ app: XCUIApplication, revision: Int) {
        let updated = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "\(textAttribute) BEGINSWITH %@", "Revision \(revision) ·"),
            object: app.staticTexts["terrainStatus"])
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 15), .completed)
    }

    @MainActor
    private func waitForAction(_ app: XCUIApplication, containing value: String) {
        let action = app.staticTexts["metrics.action"]
        let match = NSPredicate(format: "\(textAttribute) CONTAINS %@ AND \(textAttribute) CONTAINS 'removed'", value)
        let expectation = XCTNSPredicateExpectation(predicate: match, object: action)
        let result = XCTWaiter.wait(for: [expectation], timeout: 5)
        print("SPIKE00 ACTION: label=\(action.label) value=\(String(describing: action.value))")
        XCTAssertEqual(result, .completed)
    }

    @MainActor
    private func attachSummary(_ app: XCUIApplication, phase: String) {
        let summary = app.staticTexts["metrics.summary"]
        let populated = NSPredicate(format: "\(textAttribute) MATCHES 'Window ([3-9][0-9]{2}|[1-9][0-9]{3}) intervals.*'")
        let ready = XCTNSPredicateExpectation(predicate: populated, object: summary)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
        print("SPIKE00 \(phase.uppercased()): \(text(summary))")
        let summaryAttachment = XCTAttachment(string: "\(phase): \(text(summary))\n\(text(app.staticTexts["metrics.action"]))")
        summaryAttachment.lifetime = .keepAlways
        add(summaryAttachment)
        attachScreenshot(app, name: phase)
    }

    @MainActor
    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        #if os(iOS)
        let screenshot = XCUIScreen.main.screenshot()
        if name == "landscape" {
            XCTAssertGreaterThan(screenshot.image.size.width, screenshot.image.size.height,
                                 "Capture must finish rotating before recording landscape evidence.")
        }
        #else
        let screenshot = app.screenshot()
        #endif
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
