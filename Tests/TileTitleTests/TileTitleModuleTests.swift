import GameCore
import GamePlatform
import SwiftUI
import TileContent
import XCTest
@testable import TileTitle

/// Few Tiles through the real module host, shared controller and save store:
/// level selection from progress, rule outcomes, the full tray, undo, gating
/// and relaunch.
@MainActor
final class TileTitleModuleTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("tile-match-\(UUID())")
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func host() throws -> ModuleHost<TileTitleModule> {
        ModuleHost(module: TileTitleModule(), feedback: nil, store: try LocalSaveStore(titleID: "tile-match", root: root))
    }
    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(5)
        while !condition() && Date() < deadline { await Task.yield() }
        XCTAssertTrue(condition(), "Condition not reached", file: file, line: line)
    }
    private func launchAndPlay(_ host: ModuleHost<TileTitleModule>) async {
        host.controller.finishSplash()
        await waitUntil { host.controller.persistenceReady }
        host.controller.start()
        await waitUntil { host.controller.flow.inputIsActive }
    }

    private func seed(_ progress: SaveProgress) async throws {
        let store = try LocalSaveStore(titleID: "tile-match", root: root)
        let loaded = try await store.load()
        _ = try await store.save(settings: ShellSettings(), progress: progress, generation: loaded.generation)
    }

    func testFirstBoardClearsSavesAndRelaunchContinuesWithTheNext() async throws {
        let first = try host()
        await launchAndPlay(first)
        let session = first.module.session
        XCTAssertEqual(session.game?.levelID, "intro-01")
        XCTAssertEqual(session.levelNumber, 1)
        XCTAssertEqual(session.levelCount, 30)
        XCTAssertNotNil(TileTeaching.line(for: "intro-01"))
        _ = first.module.makeGameplay(); _ = first.module.makeControls(ModulePlayContext(reducesMotion: false, pause: {}))
        first.module.scene.synchronize()
        XCTAssertEqual(first.module.scene.children.count, 6, "One node per tile")
        XCTAssertNil(session.resultSummary)
        for index in 0...5 { session.select(index) }
        XCTAssertEqual(first.controller.flow.state, .result(try XCTUnwrap(first.controller.flow.currentRequest), .success))
        XCTAssertEqual(session.resultSummary, "Score: 12.")
        await first.controller.flushPersistence()
        XCTAssertEqual(first.controller.progress.completedLevels, ["intro-01"])
        XCTAssertEqual(first.controller.progress.unlockedLevels, ["intro-02"])
        XCTAssertEqual(first.controller.progress.bestScores["intro-01"], 12)

        let relaunched = try host()
        await launchAndPlay(relaunched)
        XCTAssertEqual(relaunched.module.session.game?.levelID, "intro-02", "Saved progress chooses the next board")
    }

    func testFullTrayStaysInPlayForUndoAndEndingItRecordsNothing() async throws {
        try await seed(SaveProgress(completedLevels: ["intro-01", "intro-02"]))
        let host = try host()
        await launchAndPlay(host)
        let session = host.module.session
        XCTAssertEqual(session.game?.levelID, "intro-03")
        for index in [8, 9, 11, 0, 7, 4, 10] { session.select(index) }
        XCTAssertEqual(session.game?.outcome, .trayFull)
        XCTAssertTrue(host.controller.flow.inputIsActive, "A full tray stays on the play page")
        session.select(1)
        XCTAssertEqual(session.game?.selections, 7, "A full tray takes no tile")
        session.undo()
        XCTAssertEqual(session.game?.outcome, .playing)
        XCTAssertEqual(session.game?.selections, 6, "Undo takes back the tile that filled the tray")
        session.select(10)
        XCTAssertEqual(session.game?.outcome, .trayFull)
        session.fail()
        guard case .result(_, .failure) = host.controller.flow.state else { return XCTFail("End board did not fail") }
        XCTAssertNil(session.resultSummary, "An ended board shows no score")
        await host.controller.flushPersistence()
        XCTAssertEqual(host.controller.progress.completedLevels, ["intro-01", "intro-02"])
        XCTAssertNil(host.controller.progress.bestScores["intro-03"])
        host.controller.restart()
        await waitUntil { host.controller.flow.inputIsActive }
        XCTAssertEqual(session.game?.levelID, "intro-03", "Try again replays the ended board")
        XCTAssertEqual(session.game?.selections, 0, "Try again begins a fresh board")
    }

    func testNextBoardFollowsAClearAndABestIsKeptPerLevel() async throws {
        let catalog = try BundledContent.load()
        try await seed(SaveProgress(completedLevels: catalog.levels.map(\.id), bestScores: ["intro-01": 10]))
        let host = try host()
        await launchAndPlay(host)
        let session = host.module.session
        XCTAssertEqual(session.game?.levelID, "intro-01", "With every level complete, Play starts at the first")
        XCTAssertNil(TileTeaching.line(for: "intro-04"))
        for index in 0...5 { session.select(index) }
        XCTAssertEqual(session.resultSummary, "Score: 12, a new best.")
        await host.controller.flushPersistence()
        XCTAssertEqual(host.controller.progress.bestScores["intro-01"], 12)
        host.controller.restart()
        await waitUntil { host.controller.flow.inputIsActive }
        XCTAssertEqual(session.game?.levelID, "intro-02", "Next board follows the cleared one")
        XCTAssertEqual(session.levelNumber, 2)
        host.controller.pause()
        host.controller.restart()
        await waitUntil { host.controller.flow.inputIsActive }
        XCTAssertEqual(session.game?.levelID, "intro-02", "Restart board replays the board in play")
        for move in try XCTUnwrap(catalog.level(id: "intro-02")).payload.solution { session.select(move) }
        XCTAssertEqual(session.resultSummary, "Score: 15.")
        host.controller.restart()
        await waitUntil { host.controller.flow.inputIsActive }
        XCTAssertEqual(session.game?.levelID, "intro-03")
        let moves = try XCTUnwrap(catalog.level(id: "intro-03")).payload.solution
        for move in moves.dropLast() { session.select(move) }
        session.undo()
        for move in moves.suffix(2) { session.select(move) }
        guard case .result(_, .success) = host.controller.flow.state else { return XCTFail("intro-03 did not clear after an undo") }
    }

    func testSelectionsWaitForPlayAndEndBoardFailsOnce() async throws {
        let host = try host()
        await launchAndPlay(host)
        let session = host.module.session
        host.controller.pause()
        session.select(0)
        XCTAssertEqual(session.game?.selections, 0, "Paused input is ignored")
        host.controller.resume()
        host.controller.setApplicationActive(false)
        session.select(0)
        XCTAssertEqual(session.game?.selections, 0, "Background input is ignored")
        host.controller.setApplicationActive(true)
        host.controller.resume()
        session.select(0)
        XCTAssertEqual(session.game?.selections, 1)
        session.fail()
        session.fail()
        guard case .result(_, .failure) = host.controller.flow.state else { return XCTFail("End board did not fail") }
        session.select(1)
        XCTAssertEqual(session.game?.selections, 1, "A finished board accepts no selection")
    }

    func testContentErrorIsARecoverableLoadFailure() async throws {
        var failures = 1
        let session = TileTitleSession(loader: {
            if failures > 0 {
                failures -= 1
                throw ContentValidationError(message: "fixture content error")
            }
            return try BundledContent.load()
        })
        let host = ModuleHost(module: TileTitleModule(session: session), feedback: nil)
        host.controller.finishSplash()
        host.controller.start()
        await waitUntil {
            if case .loadFailed = host.controller.flow.state { return true }
            return false
        }
        guard case .loadFailed(_, let message) = host.controller.flow.state else { return }
        XCTAssertEqual(message, host.module.loadFailureMessage)
        XCTAssertNil(session.game)
        host.controller.restart()
        await waitUntil { host.controller.flow.inputIsActive }
        XCTAssertEqual(session.game?.levelID, "intro-01")
    }

    /// Reduced motion reaches the session through the shell, and the board
    /// redraws without SpriteKit actions in either mode, so there is no
    /// motion for the trait to remove. A title animation must fail this test
    /// until it honours `session.reducedMotion`.
    func testReducedMotionReachesTheSessionAndTheBoardRunsNoActions() async throws {
        let host = try host()
        await launchAndPlay(host)
        let session = host.module.session
        let scene = host.module.scene
        func actionCount() -> Int {
            var count = 0
            scene.enumerateChildNodes(withName: "//*") { node, _ in if node.hasActions() { count += 1 } }
            return count + (scene.hasActions() ? 1 : 0)
        }
        XCTAssertFalse(session.reducedMotion)
        scene.synchronize()
        XCTAssertEqual(actionCount(), 0)
        host.controller.setReducedMotion(true)
        XCTAssertTrue(session.reducedMotion, "The shell forwards the trait to the module")
        session.select(0)
        scene.synchronize()
        XCTAssertEqual(scene.children.count, 5, "A taken tile leaves the board in one redraw")
        XCTAssertEqual(actionCount(), 0)
        host.controller.setReducedMotion(false)
        XCTAssertFalse(session.reducedMotion)
    }

    /// Every kind has its own name and symbol, so the board, the tray, the
    /// buttons and VoiceOver never depend on color perception alone.
    func testEveryKindHasADistinctSymbolAndName() {
        let kinds = TileBoard.kinds
        XCTAssertEqual(Set(kinds.map(TileStyle.name)).count, kinds.count)
        XCTAssertEqual(Set(kinds.map(TileStyle.symbol)).count, kinds.count)
        for kind in kinds {
            XCTAssertNotNil(UIImage(systemName: TileStyle.symbol(kind)), "SF Symbol for kind \(kind) exists")
            XCTAssertNotNil(UIImage(systemName: TileStyle.outline(kind)), "Outline for kind \(kind) exists")
        }
    }

    /// The tray in words, as VoiceOver and the play page read it.
    func testTraySummaryGroupsKindsAndCountsFreeSlots() throws {
        var game = TileGame(level: try XCTUnwrap(BundledContent.load().level(id: "intro-02")))
        XCTAssertEqual(TileTeaching.tray(game), "empty, 7 slots free")
        for index in [8, 0, 1] { game.select(index) }
        XCTAssertEqual(TileTeaching.tray(game), "2 Leaf, Drop; 4 slots free")
        var full = TileGame(level: try XCTUnwrap(BundledContent.load().level(id: "intro-03")))
        for index in [8, 9, 11, 0, 7, 4, 10] { full.select(index) }
        XCTAssertEqual(TileTeaching.tray(full), "2 Sun, 2 Drop, 2 Moon, Leaf; no slots free")
    }
}
