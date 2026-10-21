import XCTest

/// The reference title against docs/accessibility-checklist.md: system
/// accessibility audits of every shell page at default and accessibility text
/// sizes, the block-button input path and play under reduced motion.
final class BlockAccessibilityUITests: XCTestCase {
    /// An audit finding accepted with a tracked action: the page, the audit
    /// type, the element's identifier or label ("-" when the audit cannot
    /// resolve the element) and the entry in Games/BlockTitle/ACCESSIBILITY.md.
    struct Excuse {
        let page: String
        let type: XCUIAccessibilityAuditType
        let elements: [String]
        let tracked: String
    }

    /// Findings with a tracked action instead of a fix. Every entry here has
    /// the same entry in Games/BlockTitle/ACCESSIBILITY.md. All are in the
    /// shared settings sheet (`SharedShellSettingsView` in GamePlatform).
    static let excuses: [Excuse] = [
        Excuse(page: "settings", type: .contrast, elements: ["settings.done", "-"],
               tracked: "S-2 Done on the sheet's bar and an unresolved element below 4.5:1 in the settings sheet"),
        Excuse(page: "settings", type: .dynamicType,
               elements: ["settings.done", "Export local data", "Reset progress", "Delete local data",
                          "Export creates a JSON copy using Files. A provider you choose may transfer that copy. "
                          + "The developer receives nothing. Exported copies remain under your control after reset or deletion."],
               tracked: "S-3 settings rows reported as not scaling"),
        Excuse(page: "settings", type: .dynamicType, elements: ["-"],
               tracked: "S-3 unresolved settings element reported as not scaling (iPad)"),
        Excuse(page: "settings", type: .textClipped,
               elements: ["Export local data", "Reset progress", "Delete local data", "-",
                          "Export creates a JSON copy using Files. A provider you choose may transfer that copy. "
                          + "The developer receives nothing. Exported copies remain under your control after reset or deletion."],
               tracked: "S-3 settings rows reported as clipped at larger sizes"),
        Excuse(page: "settings", type: .elementDetection, elements: ["-"],
               tracked: "S-4 text the audit cannot match to an element in the iPad settings sheet"),
    ]

    /// Depth from the top of the window that the status bar and its scroll
    /// edge effect cover on the shell pages.
    static let statusBand: CGFloat = 120

    /// Every audit issue with its page, scroll pass and element frame.
    private var auditLog: [String] = []

    /// The audited pages come in two flows, so each test stays well inside the
    /// runner's 180-second allowance on a hosted iPad at the largest size.
    enum Flow: String {
        /// Menu, settings, play and pause.
        case shell
        /// Success, a stuck board and failure.
        case results
    }

    @MainActor
    func testAuditsPassOnShellPagesAtDefaultTextSize() throws {
        try auditPages(.shell, arguments: [], suffix: "default")
    }

    @MainActor
    func testAuditsPassOnShellPagesAtAccessibilityTextSize() throws {
        try auditPages(.shell, arguments: ["--shell-large-text", "--shell-reduced-motion"], suffix: "large-text")
    }

    @MainActor
    func testAuditsPassOnResultPagesAtDefaultTextSize() throws {
        try auditPages(.results, arguments: [], suffix: "default")
    }

    @MainActor
    func testAuditsPassOnResultPagesAtAccessibilityTextSize() throws {
        try auditPages(.results, arguments: ["--shell-large-text", "--shell-reduced-motion"], suffix: "large-text")
    }

    /// The gate's seeded-violation self-test: a DEBUG-only unlabeled 20-point
    /// button on the menu must come out of the same audit, filters and
    /// excuses as a failing finding.
    @MainActor
    func testAuditGateFailsOnASeededViolation() throws {
        continueAfterFailure = false
        let app = launchBlockTitle(arguments: ["--ui-test-seed-accessibility-violation"])
        waitFor(app.buttons["seeded.violation"])
        let findings = try audit(app, "menu-seeded", .all, through: app.buttons["shell.settings"])
        let seeded = findings.filter { $0.hasPrefix("FAIL") && $0.contains("seeded.violation") }
        XCTAssertFalse(seeded.isEmpty, "The audit gate did not report the seeded control: \(findings)")
    }

    /// The block buttons are the alternate input path: every block is a
    /// labelled control that names its position and shape, in reading order,
    /// and a whole board clears through them without touching the board.
    @MainActor
    func testBlockButtonsDescribeEveryBlockAndClearTheBoardWithoutTheBoard() {
        continueAfterFailure = false
        let app = launchBlockTitle()
        tap(app, "shell.start")
        let heading = app.staticTexts["shell.play"]
        waitFor(heading)
        let board = app.otherElements["block.board"]
        waitFor(board)
        XCTAssertEqual(board.label, "Block board")
        XCTAssertEqual(board.value as? String, "6 blocks left")
        // intro-01: coral circles in columns 1 and 3, teal squares in column 2.
        let expected = [3: "Row 2, column 1, Coral circle", 4: "Row 2, column 2, Teal square",
                        5: "Row 2, column 3, Coral circle", 6: "Row 3, column 1, Coral circle",
                        7: "Row 3, column 2, Teal square", 8: "Row 3, column 3, Coral circle"]
        for (index, label) in expected {
            let button = app.buttons["block.cell.\(index)"]
            waitFor(button)
            XCTAssertEqual(button.label, label)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44, "Block button \(index) is a full-size target")
        }
        // VoiceOver reads the play page top to bottom: heading, place, teaching,
        // counts, blocks, actions; Undo joins above the blocks after a move.
        let order = [heading, app.staticTexts["block.level"], app.staticTexts["block.teaching"],
                     app.staticTexts["block.remaining"], app.buttons["block.cell.3"],
                     app.buttons["block.cell.8"], app.buttons["shell.pause"], app.buttons["shell.fail"]]
        XCTAssertEqual(app.staticTexts["block.level"].label, "Board 1 of 30")
        for (earlier, later) in zip(order, order.dropFirst()) {
            XCTAssertLessThan(earlier.frame.minY, later.frame.minY, "\(earlier) reads before \(later)")
        }
        tap(app, "block.cell.3")
        let remaining = app.staticTexts["block.remaining"]
        reveal(app, remaining)
        XCTAssertTrue(remaining.wait(for: \.label, toEqual: "Blocks left: 4", timeout: queryAllowance))
        XCTAssertEqual(board.value as? String, "4 blocks left", "The board announces what is left")
        XCTAssertFalse(app.buttons["block.cell.6"].exists, "Cleared blocks lose their controls")
        let undo = app.buttons["block.undo"]
        waitFor(undo)
        XCTAssertLessThan(remaining.frame.minY, undo.frame.minY, "Undo reads after the counts")
        XCTAssertLessThan(undo.frame.minY, app.buttons["block.cell.4"].frame.minY, "Undo reads before the blocks")
        tap(app, "block.cell.4")
        tap(app, "block.cell.5")
        waitFor(app.staticTexts["shell.result.success"])
    }

    /// Reduced motion leaves every control and the whole flow in place. The
    /// board has no animation to remove; BlockModuleTests checks that the
    /// trait reaches the session and that the scene runs no actions.
    @MainActor
    func testReducedMotionKeepsPlayPauseAndResultsReachable() {
        continueAfterFailure = false
        let app = launchBlockTitle(arguments: ["--shell-reduced-motion"])
        tap(app, "shell.start")
        waitFor(app.staticTexts["shell.play"])
        tap(app, "block.cell.3")
        tap(app, "shell.pause")
        waitFor(app.staticTexts["shell.paused"])
        tap(app, "shell.resume")
        waitFor(app.staticTexts["shell.play"])
        tap(app, "block.cell.4")
        tap(app, "block.cell.5")
        waitFor(app.staticTexts["shell.result.success"])
    }

    /// Each page of one flow audited down to its last control. Findings are
    /// collected for the whole flow, then every one without an excuse fails
    /// the test.
    @MainActor
    private func auditPages(_ flow: Flow, arguments: [String], suffix: String) throws {
        continueAfterFailure = false
        // The DEBUG text-size override pins Dynamic Type, so the audit's own
        // size change cannot scale text there; the default-size run checks
        // `.dynamicType`, and this run checks clipping at the large size.
        let types: XCUIAccessibilityAuditType = arguments.contains("--shell-large-text")
            ? XCUIAccessibilityAuditType.all.subtracting(.dynamicType) : .all
        var findings: [String] = []
        let app = launchBlockTitle(arguments: arguments)
        switch flow {
        case .shell:
            findings += try audit(app, "menu-\(suffix)", types, through: app.buttons["shell.settings"])

            tap(app, "shell.settings")
            let form = app.collectionViews["settings.form"]
            waitFor(form)
            findings += try audit(app, "settings-\(suffix)", types, through: app.buttons["save.delete"], scrolling: form)
            app.buttons["settings.done"].tap()
            waitFor(app.staticTexts["shell.menu"])

            tap(app, "shell.start")
            waitFor(app.staticTexts["shell.play"])
            findings += try audit(app, "play-\(suffix)", types, through: app.buttons["shell.fail"])

            tap(app, "shell.pause")
            waitFor(app.staticTexts["shell.paused"])
            findings += try audit(app, "pause-\(suffix)", types, through: app.buttons["shell.menu.back"])
        case .results:
            tap(app, "shell.start")
            waitFor(app.staticTexts["shell.play"])
            for index in [3, 4, 5] { tap(app, "block.cell.\(index)") }
            waitFor(app.staticTexts["shell.result.success"])
            findings += try audit(app, "success-\(suffix)", types, through: app.buttons["shell.result.menu"])

            tap(app, "shell.result.retry")
            waitFor(app.staticTexts["shell.play"])
            tap(app, "block.cell.9")
            tap(app, "block.cell.8")
            waitFor(app.staticTexts["block.stuck"])
            findings += try audit(app, "stuck-\(suffix)", types, through: app.buttons["shell.fail"])

            tap(app, "shell.fail")
            waitFor(app.staticTexts["shell.result.failure"])
            findings += try audit(app, "failure-\(suffix)", types, through: app.buttons["shell.result.menu"])
        }

        let report = XCTAttachment(string: findings.isEmpty ? "No findings" : findings.joined(separator: "\n"))
        report.name = "audit-findings-\(flow.rawValue)-\(suffix).txt"
        report.lifetime = .keepAlways
        add(report)
        let log = XCTAttachment(string: auditLog.joined(separator: "\n"))
        log.name = "audit-log-\(flow.rawValue)-\(suffix).txt"
        log.lifetime = .keepAlways
        add(log)
        for entry in auditLog { print("AUDIT \(entry)") }
        continueAfterFailure = true
        for finding in findings where finding.hasPrefix("FAIL") { XCTFail(finding) }
    }

    /// Run the system audit from the top of the page and after each scroll
    /// until `last` is inside the window, and describe each distinct finding.
    @MainActor
    private func audit(_ app: XCUIApplication, _ screen: String, _ types: XCUIAccessibilityAuditType,
                       through last: XCUIElement, scrolling: XCUIElement? = nil,
                       file: StaticString = #filePath, line: UInt = #line) throws -> [String] {
        let scroll = scrolling ?? app.scrollViews["shell.scroll"]
        if scrolling == nil {
            // Start from the title header so nothing above the fold is skipped.
            let top = app.staticTexts["Blocky Marty"].firstMatch
            for _ in 0..<6 where !(top.exists && top.isHittable && app.windows.firstMatch.frame.contains(top.frame)) {
                if scrolling == nil { dragShell(app, scroll, towardEnd: false) } else { scroll.swipeDown() }
            }
        }
        var findings: [String] = []
        var reached = false
        for pass in 0..<16 {
            let window = app.windows.firstMatch.frame
            let pageFrame = scroll.exists ? scroll.frame : window
            // Decide before auditing: the audit varies the text size while it
            // runs, and the page reports stale geometry until the next scroll.
            let lastPass = isFullyVisible(last, in: app)
            // A sheet's navigation bar sits lower on iPad; the shell pages
            // have only the status bar.
            let navigation = app.navigationBars.firstMatch
            let barBand = navigation.exists ? navigation.frame.maxY : window.minY + Self.statusBand
            func run(_ attempt: Int) throws -> [String] {
                var found: [String] = []
                try app.performAccessibilityAudit(for: types) { issue in
                    let element = issue.element.map { $0.identifier.isEmpty ? $0.label : $0.identifier } ?? "-"
                    let type = Self.name(issue.auditType)
                    let frame = issue.element?.frame ?? .null
                    self.auditLog.append("\(screen) pass \(pass).\(attempt) \(type) \(element) frame \(frame) "
                                         + "window \(window): \(issue.detailedDescription)")
                    let finding: String
                    let inBar = navigation.exists && navigation.frame.contains(frame)
                    if !frame.isNull && (!window.contains(frame)
                                         || (!inBar && frame.intersects(pageFrame) && !pageFrame.contains(frame))) {
                        // Partly outside the window, or cut off by the edge of
                        // the page's scroll view (an iPad sheet ends above the
                        // window's bottom): the audit samples whatever is drawn
                        // there. Another pass sees the element in full.
                        return true
                    } else if pass > 0 && issue.auditType == .contrast && frame.minY < barBand {
                        // Scrolled content now sits under the translucent status
                        // or navigation bar; pass 0 audited this band unscrolled.
                        return true
                    } else if let excuse = Self.excuses.first(where: {
                        screen.hasPrefix($0.page + "-") && $0.type == issue.auditType && $0.elements.contains(element)
                    }) {
                        finding = "excused \(screen) \(type) \(element): \(excuse.tracked)"
                    } else {
                        finding = "FAIL \(screen) \(type) \(element): \(issue.compactDescription)"
                    }
                    if !found.contains(finding) { found.append(finding) }
                    return true
                }
                return found
            }
            var found = try run(0)
            // A page still settling after a scroll, a press highlight or a
            // size change can fail once; a real defect fails again a second
            // later at the same position.
            if found.contains(where: { $0.hasPrefix("FAIL") }) {
                Thread.sleep(forTimeInterval: 1)
                let again = try run(1)
                found = found.filter { !$0.hasPrefix("FAIL") || again.contains($0) }
                // The screen at a repeated failure, for reports that only
                // occur now and then (the app name's contrast at AX3).
                if found.contains(where: { $0.hasPrefix("FAIL") }) { attachScreen("audit-fail-\(screen)-pass\(pass)") }
            }
            for finding in found where !findings.contains(finding) { findings.append(finding) }
            if lastPass {
                reached = true
                break
            }
            if scrolling == nil { dragShell(app, scroll, towardEnd: true) } else { scroll.swipeUp() }
        }
        XCTAssertTrue(reached, "\(screen): audit never reached \(last): exists \(last.exists), hittable "
                      + "\(last.exists && last.isHittable), frame \(last.frame), window \(app.windows.firstMatch.frame)",
                      file: file, line: line)
        attachScreen("audit-\(screen)")
        return findings
    }

    @MainActor
    private func isFullyVisible(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        element.exists && element.isHittable && app.windows.firstMatch.frame.contains(element.frame)
    }

    private static func name(_ type: XCUIAccessibilityAuditType) -> String {
        let names: [(XCUIAccessibilityAuditType, String)] = [
            (.contrast, "contrast"), (.elementDetection, "elementDetection"), (.hitRegion, "hitRegion"),
            (.sufficientElementDescription, "sufficientElementDescription"), (.dynamicType, "dynamicType"),
            (.textClipped, "textClipped"), (.trait, "trait")]
        return names.first { $0.0 == type }?.1 ?? "audit(\(type.rawValue))"
    }
}
