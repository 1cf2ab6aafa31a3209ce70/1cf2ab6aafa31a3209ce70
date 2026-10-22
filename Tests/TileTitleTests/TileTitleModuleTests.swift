import GameCore
import GamePlatform
import XCTest
@testable import TileTitle

/// The skeleton through the real module host, shared controller and save store.
@MainActor
final class TileTitleModuleTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("tile-match-\(UUID())")
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(5)
        while !condition() && Date() < deadline { await Task.yield() }
        XCTAssertTrue(condition(), "Condition not reached", file: file, line: line)
    }

    func testLevelLoadsCompletesSavesAndRelaunchRestoresProgress() async throws {
        let host = ModuleHost(module: TileTitleModule(), feedback: nil,
                              store: try LocalSaveStore(titleID: "tile-match", root: root))
        host.controller.finishSplash()
        await waitUntil { host.controller.persistenceReady }
        host.controller.start()
        await waitUntil { host.controller.flow.inputIsActive }
        let session = host.module.session
        XCTAssertEqual(session.level?.id, "level-01")
        host.controller.pause()
        session.step()
        XCTAssertEqual(session.stepsTaken, 0, "Paused input is ignored")
        host.controller.resume()
        session.step()
        session.step()
        guard case .result(_, .success) = host.controller.flow.state else { return XCTFail("Level did not complete") }
        await host.controller.flushPersistence()

        let relaunched = ModuleHost(module: TileTitleModule(), feedback: nil,
                                    store: try LocalSaveStore(titleID: "tile-match", root: root))
        relaunched.controller.finishSplash()
        await waitUntil { relaunched.controller.persistenceReady }
        XCTAssertEqual(relaunched.controller.progress.completedLevels, ["level-01"])
    }
}
