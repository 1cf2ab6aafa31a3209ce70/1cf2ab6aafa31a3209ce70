import XCTest

final class DevelopmentTitleUITests: XCTestCase {
    override func tearDown() async throws {
        if (testRun?.failureCount ?? 0) > 0 {
            // Failure-only capture survives continueAfterFailure = false. Read
            // action state directly as well as retaining the complete hierarchy.
            await MainActor.run {
                let app = XCUIApplication()
                let scroll = app.scrollViews["shell.scroll"]
                let valueDescription = scroll.exists ? String(describing: scroll.value)
                    : "unavailable (shell.scroll absent)"
                let attachment = XCTAttachment(string:
                    "shell.scroll.value: \(valueDescription)\n\n\(app.debugDescription)")
                attachment.name = "failed-shell-action-state-and-hierarchy"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
        try await super.tearDown()
    }

    @MainActor
    func testNavigationSuccessFailureResumeAndRestart() {
        continueAfterFailure = false
        let app = launch()
        tap(app, "shell.start")
        waitForHeading(app, "shell.play")
        tap(app, "shell.pause")
        waitForHeading(app, "shell.paused")
        tap(app, "shell.resume")
        waitForHeading(app, "shell.play")
        tap(app, "shell.complete")
        waitForHeading(app, "shell.result.success")
        tap(app, "shell.result.retry")
        waitForHeading(app, "shell.play")
        tap(app, "shell.fail")
        waitForHeading(app, "shell.result.failure")
        tap(app, "shell.result.menu")
        waitForHeading(app, "shell.menu")
        tap(app, "shell.start")
        waitForHeading(app, "shell.play")
        tap(app, "shell.pause")
        waitForHeading(app, "shell.paused")
        tap(app, "shell.restart")
        waitForHeading(app, "shell.play")
        attachScreen("practice-playing")
    }

    @MainActor
    func testForegroundRequiresExplicitResumeAndRotationPreservesPlay() {
        continueAfterFailure = false
        let app = launch()
        tap(app, "shell.start")
        waitForHeading(app, "shell.play")
        XCUIDevice.shared.press(.home)
        app.activate()
        waitForHeading(app, "shell.paused")
        XCTAssertFalse(app.buttons["shell.complete"].exists)
        tap(app, "shell.resume")
        waitForHeading(app, "shell.play")
        XCUIDevice.shared.orientation = .landscapeLeft
        waitForOrientation(app, landscape: true)
        let ready = app.staticTexts["shell.play"]
        reveal(app, ready)
        waitForLayout(app, ready: ready, landscape: true)
        attachScreen("practice-landscape")
        XCUIDevice.shared.orientation = .portrait
        waitForOrientation(app, landscape: false)
        reveal(app, ready)
        waitForLayout(app, ready: ready, landscape: false)
        tap(app, "shell.complete")
        waitForHeading(app, "shell.result.success")
    }

    @MainActor
    func testSettingsPersistWithinSessionAndResetOnRelaunch() {
        continueAfterFailure = false
        let app = launch()
        tap(app, "shell.settings")
        for id in ["settings.sound", "settings.music", "settings.haptics"] {
            let toggle = app.switches[id]
            XCTAssertTrue(toggle.waitForExistence(timeout: 10))
            waitForSwitchValue(toggle, "1")
            reveal(app, toggle)
            // SwiftUI exposes the whole labeled row as the Switch frame. Its
            // center is text; the visible switch track is at the trailing edge.
            let trailingTrack = max(0.5, 1 - 25 / max(toggle.frame.width, 1))
            toggle.coordinate(withNormalizedOffset: CGVector(dx: trailingTrack, dy: 0.5)).tap()
            waitForSwitchValue(toggle, "0")
        }
        tap(app, "settings.done")
        tap(app, "shell.start")
        waitForHeading(app, "shell.play")
        tap(app, "shell.pause")
        tap(app, "shell.settings")
        for id in ["settings.sound", "settings.music", "settings.haptics"] {
            waitForSwitchValue(app.switches[id], "0")
        }
        tap(app, "settings.done")
        app.terminate()
        app.launch()
        waitForHeading(app, "shell.menu")
        tap(app, "shell.settings")
        for id in ["settings.sound", "settings.music", "settings.haptics"] {
            waitForSwitchValue(app.switches[id], "1")
        }
    }

    @MainActor
    func testLargeTextAndReducedMotionKeepControlsReachable() {
        continueAfterFailure = false
        // These DEBUG-only arguments override view traits, not system accessibility preferences.
        let app = launch(arguments: ["--shell-large-text", "--shell-reduced-motion"])
        tap(app, "shell.start")
        waitForHeading(app, "shell.play")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'stays still'")).firstMatch.exists)
        tap(app, "shell.pause")
        waitForHeading(app, "shell.paused")
        tap(app, "shell.resume")
        tap(app, "shell.complete")
        waitForHeading(app, "shell.result.success")
        attachScreen("large-text-result")
    }

    @MainActor
    private func launch(arguments: [String] = []) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        // DEBUG-only app-side action trace is exposed in the existing scroll
        // accessibility value for failed snapshots; no extra per-tap query.
        app.launchArguments = arguments + ["--shell-action-diagnostics"]
        app.launch()
        waitForHeading(app, "shell.menu")
        return app
    }

    @MainActor
    private func waitForHeading(_ app: XCUIApplication, _ id: String) {
        let heading = app.staticTexts[id]
        XCTAssertTrue(heading.waitForExistence(timeout: 15), "Missing heading \(id)")
    }

    @MainActor
    private func tap(_ app: XCUIApplication, _ id: String) {
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "Missing control \(id)")
        reveal(app, button)
        XCTAssertTrue(button.isHittable, "Unreachable control \(id)")
        button.tap()
    }

    @MainActor
    private func reveal(_ app: XCUIApplication, _ element: XCUIElement) {
        // A partly clipped element may be hittable. Bring the whole element
        // onscreen before tapping or checking safe layout after rotation.
        for _ in 0..<12 {
            guard element.exists else {
                XCTFail("Element disappeared while revealing it: \(element.identifier)")
                return
            }
            let window = app.windows.firstMatch.frame
            let frame = element.frame
            // Static headings need visible geometry, not a tappable hit point.
            // Button actionability is asserted separately by tap().
            if frame.width > 0 && frame.height > 0 && window.contains(frame) { return }
            let scroll = app.scrollViews["shell.scroll"]
            XCTAssertTrue(scroll.exists)
            let upwards = frame.midY > window.midY
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: upwards ? 0.7 : 0.3))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: upwards ? 0.3 : 0.7))
            // Stay inside the content rather than invoking a system edge gesture.
            start.press(forDuration: 0.05, thenDragTo: end)
        }
    }

    @MainActor
    private func waitForSwitchValue(_ toggle: XCUIElement, _ value: String) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 5), .completed)
        XCTAssertEqual(toggle.value as? String, value)
    }

    @MainActor
    private func waitForOrientation(_ app: XCUIApplication, landscape: Bool) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let window = app.windows.firstMatch.frame
            return window.width > 0 && window.height > 0
                && (landscape ? window.width > window.height : window.height > window.width)
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 10), .completed)
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
