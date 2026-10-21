import XCTest

/// Shared helpers. Each candidate has a timing class (the two halves of one measured run)
/// and a behaviour class (correctness scenarios). verify.py selects classes by name.
class DigUITestCase: XCTestCase {
    var candidate: String { "heightfield" }
    /// Heightfield rules (A and C) must meet the fixture's 24 / 28 score; the voxel field's
    /// undercut is a recorded deviation, so it is held to its own headless replay only.
    var fixtureHolds: Bool { candidate != "voxel" }
    var usesPhysics: Bool { candidate != "sprite" }
    var runLabel: String { ProcessInfo.processInfo.environment["DIG_RUN_LABEL"] ?? "local" }

    func launch(_ name: String, extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--module-fixture", UUID().uuidString, "--dig-candidate", candidate,
                               "--dig-run-label", "\(runLabel)-\(name)"] + extra
        app.launch()
        let start = app.buttons["shell.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 30))
        wait(for: start, "isEnabled == true", timeout: 15)
        start.press(forDuration: 0.1)
        XCTAssertTrue(app.otherElements["dig.surface"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["shell.play"].waitForExistence(timeout: 15))
        return app
    }

    func press(_ id: String, in app: XCUIApplication) {
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: 15), id)
        reveal(button, in: app)
        button.press(forDuration: 0.1)
    }

    func waitForState(_ app: XCUIApplication, _ state: String, timeout: TimeInterval) {
        let element = app.staticTexts["dig.run.state"]
        XCTAssertTrue(element.waitForExistence(timeout: 15))
        wait(for: element, "label == '\(state)'", timeout: timeout)
    }

    func wait(for element: XCUIElement, _ format: String, timeout: TimeInterval) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: format), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed,
                       "\(element) never satisfied \(format)")
    }

    /// The compact run summary, also attached and printed for verify.py.
    func summary(_ app: XCUIApplication, _ name: String) -> [String: Any] {
        let text = app.staticTexts["dig.run.summary"].value as? String ?? "{}"
        let attachment = XCTAttachment(string: text)
        attachment.name = "\(candidate)-\(name)-summary"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("DIG11-SUMMARY \(candidate) \(name) \(text)")
        let object = try? JSONSerialization.jsonObject(with: Data(text.utf8))
        return object as? [String: Any] ?? [:]
    }

    /// Parses "rev=… tick=… accepted=…".
    func status(_ app: XCUIApplication) -> [String: Int] {
        var result: [String: Int] = [:]
        for part in app.staticTexts["dig.status"].label.split(separator: " ") {
            let pair = part.split(separator: "=")
            if pair.count == 2, let value = Int(pair[1]) { result[String(pair[0])] = value }
        }
        return result
    }

    func score(_ app: XCUIApplication) -> Int {
        Int(app.staticTexts["dig.score"].label.split(separator: " ").dropFirst().first ?? "") ?? -1
    }

    func dragSurface(_ app: XCUIApplication) {
        let surface = app.otherElements["dig.surface"]
        reveal(surface, in: app)
        surface.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.55))
            .press(forDuration: 0.1, thenDragTo: surface.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.55)))
    }

    /// Scrolls the shell by dragging below the dig surface, so scrolling never digs.
    func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 {
            if element.exists && element.isHittable { return }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.88))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        }
        for _ in 0..<6 {
            if element.exists && element.isHittable { return }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
        }
    }

    // MARK: Timing (one measured run, split into two cases under the per-case allowance)

    /// Load, warm-up, I, S, B and settle, driven in-app after one tap.
    func runSustainedTrace() {
        let app = launch("timing")
        press("dig.run.timing", in: app)
        waitForState(app, "done", timeout: 160)
        let surface = app.otherElements["dig.surface"]
        reveal(surface, in: app)
        let shot = XCTAttachment(screenshot: surface.screenshot())
        shot.name = "\(candidate)-after-trace"
        shot.lifetime = .keepAlways
        add(shot)
        let result = summary(app, "timing")
        XCTAssertEqual(result["written"] as? Bool, true)
        XCTAssertEqual(result["refused"] as? Int, 0)
        XCTAssertEqual(result["matchesReplay"] as? Bool, true)
        if fixtureHolds {
            XCTAssertEqual(result["scoreAfterS"] as? Int, 24)
            XCTAssertEqual(result["scoreAfterB"] as? Int, 28)
            XCTAssertEqual(result["meetsFixture"] as? Bool, true)
        }
    }

    /// Five shell restarts, each followed by the first 100 commands of S, a settle and 2 s idle.
    func runRestartCycles() {
        let app = launch("prefix")
        var first: [String: Any] = [:]
        for cycle in 1...5 {
            press("shell.pause", in: app)
            press("shell.restart", in: app)
            XCTAssertTrue(app.staticTexts["shell.play"].waitForExistence(timeout: 20))
            press("dig.run.prefix", in: app)
            waitForState(app, "cycle \(cycle) done", timeout: 45)
            let result = summary(app, "cycle\(cycle)")
            XCTAssertEqual(result["restoredInitialState"] as? Bool, true, "cycle \(cycle)")
            XCTAssertEqual(result["matchesReplay"] as? Bool, true, "cycle \(cycle)")
            XCTAssertEqual(result["refused"] as? Int, 0, "cycle \(cycle)")
            XCTAssertEqual(result["reloadKind"] as? String, "restart", "cycle \(cycle)")
            if cycle == 1 {
                first = result
            } else {
                XCTAssertEqual(result["entities"] as? Int, first["entities"] as? Int, "cycle \(cycle)")
                XCTAssertEqual(result["subscriptions"] as? Int, first["subscriptions"] as? Int, "cycle \(cycle)")
                // A loose leak bound; verify.py applies the 8 MiB budget.
                let growth = (result["footprintMiB"] as? Double ?? 0) - (first["footprintMiB"] as? Double ?? 0)
                XCTAssertLessThan(growth, 64, "cycle \(cycle)")
            }
        }
        XCTAssertEqual(summary(app, "cycles")["written"] as? Bool, true)
    }

    // MARK: Behaviour

    /// The same 900 commands with geometry delayed: outcome equals the headless replay.
    func runFastTrace(_ name: String, extra: [String]) {
        let app = launch(name, extra: extra)
        press("dig.run.fast", in: app)
        waitForState(app, "done", timeout: 90)
        let result = summary(app, name)
        XCTAssertEqual(result["matchesReplay"] as? Bool, true)
        XCTAssertEqual(result["refused"] as? Int, 0)
        if fixtureHolds { XCTAssertEqual(result["meetsFixture"] as? Bool, true) }
    }

    /// Pause mid-trace: rule ticks, revision and accepted input stay frozen and physics
    /// does not move; resume completes with no command lost.
    func runPauseResume() {
        let app = launch("pause")
        press("dig.run.fast", in: app)
        let deadline = Date().addingTimeInterval(30)
        while (status(app)["rev"] ?? 0) < 40, Date() < deadline { usleep(200_000) }
        press("shell.pause", in: app)
        XCTAssertTrue(app.staticTexts["shell.paused"].waitForExistence(timeout: 10))
        let before = app.staticTexts["dig.status"].label
        sleep(2)
        XCTAssertEqual(app.staticTexts["dig.status"].label, before, "rules advanced while paused")
        press("shell.resume", in: app)
        waitForState(app, "done", timeout: 90)
        let result = summary(app, "pause")
        XCTAssertEqual(result["matchesReplay"] as? Bool, true)
        XCTAssertEqual(result["refused"] as? Int, 0)
        XCTAssertGreaterThanOrEqual(result["pauses"] as? Int ?? 0, 1)
        XCTAssertEqual(result["pausedTickAdvance"] as? Int, 0)
        if usesPhysics { XCTAssertLessThan(result["maxSphereDrift"] as? Double ?? 1, 0.001) }
    }

    /// A native drag digs through the session; while paused the same drag is refused.
    func runDragAndPausedDrag() {
        let app = launch("drag")
        dragSurface(app)
        let deadline = Date().addingTimeInterval(10)
        while (status(app)["rev"] ?? 0) == 0, Date() < deadline { usleep(200_000) }
        let dug = status(app)
        XCTAssertGreaterThan(dug["accepted"] ?? 0, 0)
        XCTAssertGreaterThan(dug["rev"] ?? 0, 0)
        press("shell.pause", in: app)
        XCTAssertTrue(app.staticTexts["shell.paused"].waitForExistence(timeout: 10))
        let paused = app.staticTexts["dig.status"].label
        dragSurface(app)
        sleep(1)
        XCTAssertEqual(app.staticTexts["dig.status"].label, paused, "a paused drag reached the rules")
        press("shell.resume", in: app)
        XCTAssertTrue(app.staticTexts["shell.play"].waitForExistence(timeout: 10))
    }

    /// Non-precision path: two cursor moves and repeated Dig uncover the ridge item at z = 16.
    func runAccessibleDig() {
        let app = launch("accessible")
        press("dig.cursor.north", in: app)
        press("dig.cursor.north", in: app)
        let cursor = app.staticTexts["dig.cursor"]
        wait(for: cursor, "label == 'Cursor x 0.00, z -0.24'", timeout: 5)
        var presses = 0
        while score(app) < 1, presses < 30 {
            press("dig.dig", in: app)
            presses += 1
            usleep(300_000)
        }
        XCTAssertEqual(score(app), 1, "after \(presses) Dig presses")
        XCTAssertEqual(app.buttons["dig.dig"].label, "Dig at cursor")
        XCTAssertEqual(app.buttons["dig.cursor.north"].label, "Move cursor north")
        XCTAssertEqual(status(app)["accepted"], presses + 2)
    }

    /// Scene reload rebuilds every entity from rule state without touching the rules.
    func runSceneReload() {
        let app = launch("reload")
        for _ in 0..<3 { press("dig.dig", in: app) }
        sleep(1)
        press("dig.reload", in: app)
        waitForState(app, "reloaded", timeout: 20)
        let result = summary(app, "reload")
        XCTAssertEqual(result["digestUnchanged"] as? Bool, true)
        XCTAssertEqual(result["reloadComplete"] as? Bool, true)
        XCTAssertEqual(result["reloadKind"] as? String, "scene")
        XCTAssertEqual(result["entitiesBefore"] as? Int, result["entitiesAfter"] as? Int)
        XCTAssertEqual(result["subscriptionsBefore"] as? Int, result["subscriptionsAfter"] as? Int)
    }
}

final class HeightfieldTimingTests: DigUITestCase {
    override var candidate: String { "heightfield" }
    func test1SustainedTrace() { runSustainedTrace() }
    func test2RestartCycles() { runRestartCycles() }
}

final class LowLevelTimingTests: DigUITestCase {
    override var candidate: String { "lowlevel" }
    func test1SustainedTrace() { runSustainedTrace() }
    func test2RestartCycles() { runRestartCycles() }
}

final class VoxelTimingTests: DigUITestCase {
    override var candidate: String { "voxel" }
    func test1SustainedTrace() { runSustainedTrace() }
    func test2RestartCycles() { runRestartCycles() }
}

final class SpriteTimingTests: DigUITestCase {
    override var candidate: String { "sprite" }
    func test1SustainedTrace() { runSustainedTrace() }
    func test2RestartCycles() { runRestartCycles() }
}

final class HeightfieldBehaviourTests: DigUITestCase {
    override var candidate: String { "heightfield" }
    func testAccessibleControlsDig() { runAccessibleDig() }
    func testDelayedGeometryKeepsOutcome() { runFastTrace("delayed", extra: ["--dig-mesh-delay-ms", "50", "--dig-collision-delay-ms", "200"]) }
    func testDragDigsAndPauseRefusesTouch() { runDragAndPausedDrag() }
    func testPauseResumeKeepsOutcome() { runPauseResume() }
    func testSceneReloadKeepsRules() { runSceneReload() }
}

/// A2 shares A's rules, input and collision; only the mesh update path differs.
final class LowLevelBehaviourTests: DigUITestCase {
    override var candidate: String { "lowlevel" }
    func testDelayedGeometryKeepsOutcome() { runFastTrace("delayed", extra: ["--dig-mesh-delay-ms", "50", "--dig-collision-delay-ms", "200"]) }
    func testSceneReloadKeepsRules() { runSceneReload() }
}

final class VoxelBehaviourTests: DigUITestCase {
    override var candidate: String { "voxel" }
    func testAccessibleControlsDig() { runAccessibleDig() }
    func testDelayedGeometryKeepsOutcome() { runFastTrace("delayed", extra: ["--dig-mesh-delay-ms", "50", "--dig-collision-delay-ms", "200"]) }
    func testDragDigsAndPauseRefusesTouch() { runDragAndPausedDrag() }
    func testPauseResumeKeepsOutcome() { runPauseResume() }
    func testSceneReloadKeepsRules() { runSceneReload() }
}

final class SpriteBehaviourTests: DigUITestCase {
    override var candidate: String { "sprite" }
    func testAccessibleControlsDig() { runAccessibleDig() }
    func testDelayedGeometryKeepsOutcome() { runFastTrace("delayed", extra: ["--dig-mesh-delay-ms", "50"]) }
    func testDragDigsAndPauseRefusesTouch() { runDragAndPausedDrag() }
    func testFrameRate30KeepsOutcome() { runFastTrace("fps30", extra: ["--dig-fps", "30"]) }
    func testFrameRate60KeepsOutcome() { runFastTrace("fps60", extra: ["--dig-fps", "60"]) }
    func testPauseResumeKeepsOutcome() { runPauseResume() }
    func testSceneReloadKeepsRules() { runSceneReload() }
}
