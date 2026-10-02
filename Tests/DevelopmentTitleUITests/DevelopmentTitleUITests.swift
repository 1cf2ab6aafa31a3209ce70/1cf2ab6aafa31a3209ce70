import XCTest

final class DevelopmentTitleUITests: XCTestCase {
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
    func testSettingsAndProgressPersistOnRelaunch() {
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
        tap(app, "shell.resume")
        tap(app, "shell.complete")
        waitForHeading(app, "shell.result.success")
        waitForSaved(app)
        app.terminate()
        app.launch()
        waitForHeading(app, "shell.menu")
        XCTAssertTrue(app.staticTexts["save.progress"].waitForExistence(timeout: 10))
        tap(app, "shell.settings")
        for id in ["settings.sound", "settings.music", "settings.haptics"] {
            waitForSwitchValue(app.switches[id], "0")
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
    func testResetDeleteAndDestructiveCancellation() {
        continueAfterFailure = false
        let app = launch()
        tap(app, "shell.start")
        waitForHeading(app, "shell.play")
        tap(app, "shell.complete")
        waitForHeading(app, "shell.result.success")
        waitForSaved(app)
        tap(app, "shell.result.menu")
        tap(app, "shell.settings")
        let sound = app.switches["settings.sound"]
        let trailingTrack = max(0.5, 1 - 25 / max(sound.frame.width, 1))
        sound.coordinate(withNormalizedOffset: CGVector(dx: trailingTrack, dy: 0.5)).tap()
        reveal(app, sound, scrollUpWhenMissing: true)
        waitForSwitchValue(sound, "0")
        tap(app, "save.reset")
        app.alerts.buttons["Cancel"].tap()
        tap(app, "settings.done")
        XCTAssertTrue(app.staticTexts["save.progress"].exists)
        tap(app, "shell.settings")
        tap(app, "save.reset")
        app.alerts.buttons["Reset progress"].tap()
        reveal(app, sound, scrollUpWhenMissing: true)
        waitForSwitchValue(sound, "0")
        tap(app, "settings.done")
        waitForSaved(app)
        XCTAssertFalse(app.staticTexts["save.progress"].exists)
        tap(app, "shell.settings")
        tap(app, "save.delete")
        app.alerts.buttons["Cancel"].tap()
        reveal(app, sound, scrollUpWhenMissing: true)
        waitForSwitchValue(sound, "0")
        tap(app, "save.delete")
        app.alerts.buttons["Delete local data"].tap()
        reveal(app, sound, scrollUpWhenMissing: true)
        waitForSwitchValue(sound, "1")
        tap(app, "settings.done")
        waitForSaved(app)
    }

    @MainActor
    func testPlayerExportPresentsFilesAndCancellationKeepsProgress() {
        continueAfterFailure = false
        let app = launch()
        tap(app, "shell.start")
        waitForHeading(app, "shell.play")
        tap(app, "shell.complete")
        waitForHeading(app, "shell.result.success")
        waitForSaved(app)
        tap(app, "shell.result.menu")
        tap(app, "shell.settings")
        tap(app, "save.export")
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), "Files exporter was not presented")
        cancel.tap()
        tap(app, "settings.done")
        XCTAssertTrue(app.staticTexts["save.progress"].exists)
    }

    @MainActor
    private func waitForSaved(_ app: XCUIApplication) {
        let saved = app.staticTexts["save.status"]
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Local data saved"), object: saved)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 10), .completed)
    }

    @MainActor
    private func launch(arguments: [String] = []) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        waitForHeading(app, "shell.menu")
        waitForSaved(app)
        tap(app, "shell.settings")
        tap(app, "save.delete")
        app.alerts.buttons["Delete local data"].tap()
        tap(app, "settings.done")
        waitForSaved(app)
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
        // Form rows are virtualized; discover them by scrolling before waiting.
        if id.hasPrefix("save.") { reveal(app, button) }
        XCTAssertTrue(button.waitForExistence(timeout: 10), "Missing control \(id)")
        reveal(app, button)
        XCTAssertTrue(button.isHittable, "Unreachable control \(id)")
        button.tap()
    }

    @MainActor
    private func reveal(_ app: XCUIApplication, _ element: XCUIElement, scrollUpWhenMissing: Bool = false) {
        // A partly clipped element may be hittable. Bring the whole element
        // onscreen before tapping or checking safe layout after rotation.
        for _ in 0..<12 {
            let window = app.windows.firstMatch.frame
            let frame = element.exists ? element.frame : .zero
            // Static headings need visible geometry, not a tappable hit point.
            // Button actionability is asserted separately by tap().
            if element.exists && frame.width > 0 && frame.height > 0 && window.contains(frame) { return }
            let shellScroll = app.scrollViews["shell.scroll"]
            let formCollection = app.collectionViews["settings.form"]
            let formScroll = app.scrollViews["settings.form"]
            let scroll = formCollection.exists ? formCollection : (formScroll.exists ? formScroll : shellScroll)
            XCTAssertTrue(scroll.exists)
            let upwards = element.exists ? frame.midY > window.midY : !scrollUpWhenMissing
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
