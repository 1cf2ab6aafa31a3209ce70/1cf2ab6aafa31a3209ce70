import BlockContent
import GameCore
import GamePlatform
import SwiftUI
import XCTest
@testable import BlockTitle

/// Blocky Marty through the real module host, shared controller and save
/// store: level selection from progress, rule outcomes, undo, gating and relaunch.
@MainActor
final class BlockModuleTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("block-module-\(UUID())")
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func host() throws -> ModuleHost<BlockModule> {
        ModuleHost(module: BlockModule(), feedback: nil, store: try LocalSaveStore(titleID: "block-match", root: root))
    }
    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(5)
        while !condition() && Date() < deadline { await Task.yield() }
        XCTAssertTrue(condition(), "Condition not reached", file: file, line: line)
    }
    private func launchAndPlay(_ host: ModuleHost<BlockModule>) async {
        host.controller.finishSplash()
        await waitUntil { host.controller.persistenceReady }
        host.controller.start()
        await waitUntil { host.controller.flow.inputIsActive }
    }

    private func seed(_ progress: SaveProgress) async throws {
        let store = try LocalSaveStore(titleID: "block-match", root: root)
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
        XCTAssertNotNil(BlockTeaching.line(for: "intro-01"))
        _ = first.module.makeGameplay(); _ = first.module.makeControls(ModulePlayContext(reducesMotion: false, pause: {}))
        first.module.scene.synchronize()
        XCTAssertEqual(first.module.scene.children.count, 6, "One node per block")
        XCTAssertNil(session.resultSummary)
        for index in [3, 4, 5] { session.select(index) }
        XCTAssertEqual(first.controller.flow.state, .result(try XCTUnwrap(first.controller.flow.currentRequest), .success))
        XCTAssertEqual(session.resultSummary, "Score: 6.")
        await first.controller.flushPersistence()
        XCTAssertEqual(first.controller.progress.completedLevels, ["intro-01"])
        XCTAssertEqual(first.controller.progress.unlockedLevels, ["intro-02"])
        XCTAssertEqual(first.controller.progress.bestScores["intro-01"], 6)

        let relaunched = try host()
        await launchAndPlay(relaunched)
        XCTAssertEqual(relaunched.module.session.game?.levelID, "intro-02", "Saved progress chooses the next board")
    }

    func testStuckBoardStaysInPlayForUndoAndEndingItRecordsNothing() async throws {
        try await seed(SaveProgress(completedLevels: ["intro-01"]))
        let host = try host()
        await launchAndPlay(host)
        let session = host.module.session
        XCTAssertEqual(session.game?.levelID, "intro-02")
        session.select(9)
        session.select(8)
        XCTAssertEqual(session.game?.outcome, .stuck)
        XCTAssertTrue(host.controller.flow.inputIsActive, "A stuck board stays on the play page")
        session.undo()
        XCTAssertEqual(session.game?.outcome, .playing)
        XCTAssertEqual(session.game?.selections, 1, "Undo takes back the move that stranded the block")
        session.select(8)
        XCTAssertEqual(session.game?.outcome, .stuck)
        session.fail()
        guard case .result(_, .failure) = host.controller.flow.state else { return XCTFail("End board did not fail") }
        XCTAssertNil(session.resultSummary, "An ended board shows no score")
        await host.controller.flushPersistence()
        XCTAssertEqual(host.controller.progress.completedLevels, ["intro-01"])
        XCTAssertNil(host.controller.progress.bestScores["intro-02"])
        host.controller.restart()
        await waitUntil { host.controller.flow.inputIsActive }
        XCTAssertEqual(session.game?.levelID, "intro-02", "Try again replays the ended board")
        XCTAssertEqual(session.game?.selections, 0, "Try again begins a fresh board")
    }

    func testNextBoardFollowsAClearAndABestIsKeptPerLevel() async throws {
        let catalog = try BundledContent.load()
        try await seed(SaveProgress(completedLevels: catalog.levels.map(\.id), bestScores: ["intro-01": 4]))
        let host = try host()
        await launchAndPlay(host)
        let session = host.module.session
        XCTAssertEqual(session.game?.levelID, "intro-01", "With every level complete, Play starts at the first")
        XCTAssertNil(BlockTeaching.line(for: "intro-04"))
        for index in [3, 4, 5] { session.select(index) }
        XCTAssertEqual(session.resultSummary, "Score: 6, a new best.")
        await host.controller.flushPersistence()
        XCTAssertEqual(host.controller.progress.bestScores["intro-01"], 6)
        host.controller.restart()
        await waitUntil { host.controller.flow.inputIsActive }
        XCTAssertEqual(session.game?.levelID, "intro-02", "Next board follows the cleared one")
        XCTAssertEqual(session.levelNumber, 2)
        host.controller.pause()
        host.controller.restart()
        await waitUntil { host.controller.flow.inputIsActive }
        XCTAssertEqual(session.game?.levelID, "intro-02", "Restart board replays the board in play")
        for move in try XCTUnwrap(catalog.level(id: "intro-02")).payload.solution { session.select(move) }
        XCTAssertEqual(session.resultSummary, "Score: 20.")
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
        session.select(3)
        XCTAssertEqual(session.game?.selections, 0, "Paused input is ignored")
        host.controller.resume()
        host.controller.setApplicationActive(false)
        session.select(3)
        XCTAssertEqual(session.game?.selections, 0, "Background input is ignored")
        host.controller.setApplicationActive(true)
        host.controller.resume()
        session.select(3)
        XCTAssertEqual(session.game?.selections, 1)
        session.fail()
        session.fail()
        guard case .result(_, .failure) = host.controller.flow.state else { return XCTFail("End board did not fail") }
        session.select(4)
        XCTAssertEqual(session.game?.selections, 1, "A finished board accepts no selection")
    }

    func testContentErrorIsARecoverableLoadFailure() async throws {
        var failures = 1
        let session = BlockSession(loader: {
            if failures > 0 {
                failures -= 1
                throw ContentValidationError(message: "fixture content error")
            }
            return try BundledContent.load()
        })
        let host = ModuleHost(module: BlockModule(session: session), feedback: nil)
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
        session.select(3)
        scene.synchronize()
        XCTAssertEqual(scene.children.count, 4, "Cleared blocks disappear in one redraw")
        XCTAssertEqual(actionCount(), 0)
        host.controller.setReducedMotion(false)
        XCTAssertFalse(session.reducedMotion)
    }

    /// Every block color has its own name and shape, so the board, the
    /// buttons and VoiceOver never depend on color perception alone.
    func testEveryBlockColorHasADistinctShapeAndName() {
        let colors = 1...4
        XCTAssertEqual(Set(colors.map(BlockStyle.name)).count, colors.count)
        XCTAssertEqual(Set(colors.map(BlockStyle.symbol)).count, colors.count)
        for color in colors {
            XCTAssertFalse(BlockStyle.symbol(color).isEmpty)
            XCTAssertNotNil(UIImage(systemName: BlockStyle.symbol(color)), "SF Symbol for color \(color) exists")
            XCTAssertNotNil(UIImage(systemName: BlockStyle.outline(color)), "Outline for color \(color) exists")
        }
    }
}
