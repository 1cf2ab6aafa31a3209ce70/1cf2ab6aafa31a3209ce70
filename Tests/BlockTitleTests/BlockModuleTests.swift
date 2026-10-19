import BlockContent
import GameCore
import GamePlatform
import SwiftUI
import XCTest
@testable import BlockTitle

/// The block slice through the real module host, shared controller and save
/// store: level selection from progress, rule outcomes, gating and relaunch.
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

    func testFirstBoardClearsSavesAndRelaunchContinuesWithTheNext() async throws {
        let first = try host()
        await launchAndPlay(first)
        let session = first.module.session
        XCTAssertEqual(session.game?.levelID, "intro-01")
        _ = first.module.makeGameplay(); _ = first.module.makeControls(ModulePlayContext(reducesMotion: false, pause: {}))
        first.module.scene.synchronize()
        XCTAssertEqual(first.module.scene.children.count, 6, "One node per block")
        for index in [3, 4, 5] { session.select(index) }
        XCTAssertEqual(first.controller.flow.state, .result(try XCTUnwrap(first.controller.flow.currentRequest), .success))
        await first.controller.flushPersistence()
        XCTAssertEqual(first.controller.progress.completedLevels, ["intro-01"])
        XCTAssertEqual(first.controller.progress.unlockedLevels, ["intro-02"])
        XCTAssertEqual(first.controller.progress.bestScores["intro-01"], 6)

        let relaunched = try host()
        await launchAndPlay(relaunched)
        XCTAssertEqual(relaunched.module.session.game?.levelID, "intro-02", "Saved progress chooses the next board")
    }

    func testStuckBoardIsAFailureThatRecordsNothing() async throws {
        let seed = try LocalSaveStore(titleID: "block-match", root: root)
        let loaded = try await seed.load()
        _ = try await seed.save(settings: ShellSettings(), progress: SaveProgress(completedLevels: ["intro-01"]),
                                generation: loaded.generation)
        let host = try host()
        await launchAndPlay(host)
        let session = host.module.session
        XCTAssertEqual(session.game?.levelID, "intro-02")
        session.select(9)
        session.select(8)
        XCTAssertEqual(session.game?.outcome, .stuck)
        guard case .result(_, .failure) = host.controller.flow.state else { return XCTFail("Stuck board did not fail") }
        await host.controller.flushPersistence()
        XCTAssertEqual(host.controller.progress.completedLevels, ["intro-01"])
        host.controller.restart()
        await waitUntil { host.controller.flow.inputIsActive }
        XCTAssertEqual(session.game?.selections, 0, "Restart begins a fresh board")
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
}
