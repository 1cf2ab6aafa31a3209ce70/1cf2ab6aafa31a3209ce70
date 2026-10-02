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
        verifyLayout(app, ready: ready, snapshot: reveal(app, ready), landscape: true)
        attachScreen("practice-landscape")
        XCUIDevice.shared.orientation = .portrait
        waitForOrientation(app, landscape: false)
        verifyLayout(app, ready: ready, snapshot: reveal(app, ready), landscape: false)
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
        let picker = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10), "Native Files exporter was not presented")
        attachScreen("native-files-export")
        let sidebar = app.navigationBars.matching(NSPredicate(format: "identifier IN %@", [
            "com_apple_DocumentManager_Service.DOCSidebarView", "DOCSidebarView"
        ])).firstMatch
        let window = app.windows.firstMatch.frame
        let beforeHierarchy = app.debugDescription
        let before = XCTAttachment(string: "window=\(window); picker=\(picker.frame); sidebarExists=\(sidebar.exists)\n" + beforeHierarchy)
        before.name = "native-files-before-cancellation-hierarchy"
        before.lifetime = .keepAlways
        add(before)
        print("NATIVE_FILES before hierarchy:\n" + beforeHierarchy)
        print("NATIVE_FILES window=\(window) picker=\(picker.frame) sidebarExists=\(sidebar.exists)")
        // The presented SwiftUI overlay exposes an Other labeled Cancel at
        // exactly the native More button's frame. Only genuine button actions
        // can be cancellation candidates; the overlay label is misleading.
        let cancellations = app.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "Close"]))
        if let cancel = cancellations.allElementsBoundByIndex.first(where: {
            let frame = $0.frame
            let hittable = $0.isHittable
            print("NATIVE_FILES candidate type=\($0.elementType.rawValue) label=\($0.label) frame=\(frame) hittable=\(hittable) insideWindow=\(window.contains(frame))")
            return frame.width > 0 && frame.height > 0 && window.contains(frame) && hittable
        }) {
            // A hosted Files AX tap reported a {-1,-1} hit point after its
            // automatic scroll, leaving the exporter open. Use the validated
            // visible control's coordinate without that automatic scroll.
            let frame = cancel.frame
            print("NATIVE_FILES selected candidate frame=\(frame) point=(\(frame.midX),\(frame.midY))")
            cancel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        } else if sidebar.exists {
            // iPad's observed native sidebar displays a leading X. Validate
            // its visible bounds before tapping that close affordance.
            let frame = sidebar.frame
            XCTAssertTrue(frame.width > 0 && frame.height > 0 && window.contains(frame),
                          "Native Files close bar has no visible bounds")
            print("NATIVE_FILES selected sidebar frame=\(frame) point=(\(frame.minX + frame.width * 0.08),\(frame.minY + frame.height * 0.4))")
            sidebar.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.4)).tap()
        } else {
            // The phone exporter can start inside On My iPhone, where its
            // leading control is Back rather than Close. The accepted local
            // run dismisses that sheet by dragging its upper bar downward.
            let frame = picker.frame
            XCTAssertTrue(frame.width > 0 && frame.height > 0 && window.contains(frame),
                          "Native Files exporter bar has no visible bounds")
            print("NATIVE_FILES selected phone drag picker=\(frame) window=\(window)")
            let start = picker.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05))
            let end = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        attachScreen("native-files-after-cancellation")
        let afterHierarchy = app.debugDescription
        let after = XCTAttachment(string: afterHierarchy)
        after.name = "native-files-after-cancellation-hierarchy"
        after.lifetime = .keepAlways
        add(after)
        print("NATIVE_FILES after hierarchy:\n" + afterHierarchy)
        let done = app.buttons["settings.done"]
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            // A native menu can hide the named exporter bar while Files is
            // still open. Require the underlying Settings control reachable.
            return !picker.exists && !sidebar.exists && done.exists && done.isHittable
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 10), .completed,
                       "Files cancellation did not return to reachable Settings")
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
    @discardableResult
    private func reveal(_ app: XCUIApplication, _ element: XCUIElement, scrollUpWhenMissing: Bool = false) -> (window: CGRect, element: CGRect)? {
        // A partly clipped element may be hittable. Bring the whole element
        // onscreen before tapping or checking safe layout after rotation.
        for _ in 0..<12 {
            let window = app.windows.firstMatch.frame
            let shellScroll = app.scrollViews["shell.scroll"]
            let formCollection = app.collectionViews["settings.form"]
            let formScroll = app.scrollViews["settings.form"]
            let hasForm = formCollection.exists || formScroll.exists
            let scroll = formCollection.exists ? formCollection : (formScroll.exists ? formScroll : shellScroll)
            XCTAssertTrue(scroll.exists)
            // iPad Settings occupies a smaller modal sheet. An offscreen Form
            // row can still have a frame inside the app window, so use the
            // actual scrolling surface's visible bounds as the clipping region.
            let visible = hasForm ? scroll.frame.intersection(window) : window
            let exists = element.exists
            let frame = exists ? element.frame : .zero
            if exists && frame.width > 0 && frame.height > 0 && visible.contains(frame) {
                if element.elementType != .button && element.elementType != .switch { return (window, frame) }
                if element.isHittable { return (window, frame) }
            }
            let upwards = exists ? frame.midY > visible.midY : !scrollUpWhenMissing
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: upwards ? 0.7 : 0.3))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: upwards ? 0.3 : 0.7))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        return nil
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
    private func verifyLayout(_ app: XCUIApplication, ready: XCUIElement,
                              snapshot: (window: CGRect, element: CGRect)?, landscape: Bool) {
        // reveal already obtained a contained heading snapshot after rotation.
        // A second AX Window lookup stalled past the predicate deadline on CI;
        // verify the same observed geometry rather than querying it again.
        guard let snapshot else {
            attachScreen("layout-failure")
            let hierarchy = XCTAttachment(string: "window=\(app.windows.firstMatch.frame); "
                + "heading=\(ready.frame); scroll=\(app.scrollViews["shell.scroll"].frame)\n"
                + app.debugDescription)
            hierarchy.name = "layout-failure-hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            XCTFail("Heading could not be brought fully onscreen after rotation")
            return
        }
        let geometry = "window=\(snapshot.window); heading=\(snapshot.element); landscape=\(landscape)"
        let diagnostic = XCTAttachment(string: geometry)
        diagnostic.name = landscape ? "landscape-layout-geometry" : "portrait-layout-geometry"
        diagnostic.lifetime = .keepAlways
        add(diagnostic)
        XCTAssertGreaterThan(snapshot.window.width, 0, geometry)
        XCTAssertGreaterThan(snapshot.window.height, 0, geometry)
        XCTAssertGreaterThan(snapshot.element.width, 0, geometry)
        XCTAssertGreaterThan(snapshot.element.height, 0, geometry)
        XCTAssertTrue(landscape ? snapshot.window.width > snapshot.window.height
                               : snapshot.window.height > snapshot.window.width, geometry)
        XCTAssertTrue(snapshot.window.contains(snapshot.element), geometry)
    }

    @MainActor
    private func attachScreen(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
