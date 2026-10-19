@testable import BlockContent
import Foundation
import GameCore
import XCTest

final class BlockContentTests: XCTestCase {
    private func resources() throws -> [String: Data] {
        let root = try BundledContent.resourceDirectory()
        let files = ["catalog.json", "Levels/intro-01.json", "Levels/intro-02.json"]
        return try Dictionary(uniqueKeysWithValues: files.map { ($0, try Data(contentsOf: root.appendingPathComponent($0))) })
    }
    private func load(_ files: [String: Data]) throws -> BlockCatalog {
        try BundledContent.load { path in
            guard let data = files[path] else { throw ContentValidationError(message: "missing resource") }
            return data
        }
    }
    private func mutate(_ file: String, in files: inout [String: Data], _ change: (inout [String: Any]) -> Void) throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(files[file])) as? [String: Any])
        change(&object)
        files[file] = try JSONSerialization.data(withJSONObject: object)
    }
    private func payload(_ file: String, in files: inout [String: Data], _ change: (inout [String: Any]) -> Void) throws {
        try mutate(file, in: &files) { level in
            var payload = level["payload"] as! [String: Any]
            change(&payload)
            level["payload"] = payload
        }
    }
    private func rejects(_ files: [String: Data], containing expected: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try load(files), file: file, line: line) {
            XCTAssertTrue($0.localizedDescription.contains(expected), $0.localizedDescription, file: file, line: line)
        }
    }
    private func level(_ id: String) throws -> BlockLevel {
        try XCTUnwrap(BundledContent.load().level(id: id))
    }

    func testBundledCatalogDecodesTwoOriginalLevelsForThisTitleOnly() throws {
        let catalog = try BundledContent.load()
        XCTAssertEqual(catalog.envelope.titleID, "block-match")
        XCTAssertEqual(catalog.levels.map(\.id), ["intro-01", "intro-02"])
        XCTAssertEqual(catalog.levels.map(\.payload.nextLevelIDs), [["intro-02"], []])
        var files = try resources()
        try mutate("catalog.json", in: &files) { $0["titleID"] = "development-practice" }
        rejects(files, containing: "expected block-match title")
    }

    func testClearingAGroupLetsBlocksAboveFall() throws {
        var board = BlockBoard(columns: 4, rows: 4, cells: try level("intro-02").payload.cells)
        XCTAssertEqual(board.moves, [8, 9])
        XCTAssertEqual(board.group(at: 9), [9, 13, 14])
        XCTAssertEqual(board.group(at: 4), [4], "A lone block is not a move")
        XCTAssertEqual(board.clear(at: 4), 0)
        XCTAssertEqual(board.clear(at: 9), 3)
        XCTAssertEqual(board.cells, [0, 0, 0, 0,
                                     2, 0, 0, 0,
                                     1, 0, 0, 0,
                                     1, 1, 1, 1], "Each column settles onto the floor")
    }

    func testSolutionFixturesReplayToTheSameClearedOutcome() throws {
        for id in ["intro-01", "intro-02"] {
            let level = try level(id)
            let fixture = try XCTUnwrap(BlockReplay.solutionFixture(level: level))
            let first = try BlockReplay.replay(level: level, fixture: fixture)
            XCTAssertEqual(first.outcome, .cleared, id)
            XCTAssertEqual(try BlockReplay.replay(level: level, fixture: fixture), first, "Replays are deterministic")
            XCTAssertGreaterThan(first.score, 0)
        }
        let intro = try level("intro-01")
        XCTAssertEqual(BlockReplay.solutionFixture(level: intro)?.inputs.map(\.action.index), [3, 4, 5])
    }

    func testWrongFirstChoiceOnTheSecondLevelGetsStuck() throws {
        let level = try level("intro-02")
        let fixture = InputFixture(levelID: level.id, contentVersion: level.contentVersion, seed: level.seed,
                                   inputs: [TimedInput(tick: 10, action: BlockAction(index: 9)),
                                            TimedInput(tick: 20, action: BlockAction(index: 8))])
        let game = try BlockReplay.replay(level: level, fixture: fixture)
        XCTAssertEqual(game.outcome, .stuck)
        XCTAssertEqual(game.board.cells.filter { $0 != 0 }, [2], "One block remains with no partner")
        XCTAssertEqual(game.selections, 2)
        XCTAssertEqual(game.score, 3 * 2 + 5 * 4)
    }

    func testIllegalOrLateSelectionsChangeNothing() throws {
        var game = BlockGame(level: try level("intro-01"))
        let start = game
        for index in [-1, 0, 2, 9, 100] { XCTAssertFalse(game.select(index)) }
        XCTAssertEqual(game, start)
        for index in [3, 4, 5] { XCTAssertTrue(game.select(index)) }
        XCTAssertEqual(game.outcome, .cleared)
        XCTAssertFalse(game.select(6), "A finished game accepts no selection")
        XCTAssertEqual(game.selections, 3)
        let mismatched = InputFixture(levelID: "intro-02", contentVersion: 1, seed: 201, inputs: [TimedInput(tick: 1, action: BlockAction(index: 3))])
        XCTAssertThrowsError(try BlockReplay.replay(level: try level("intro-01"), fixture: mismatched))
    }

    func testValidationRejectsFloatingUnclearableAndMisreferencedLevels() throws {
        let base = try resources()
        var files = base
        try payload("Levels/intro-01.json", in: &files) { $0["cells"] = [1, 0, 0, 0, 2, 1, 1, 2, 1] }
        rejects(files, containing: "rest on the floor")
        files = base
        try payload("Levels/intro-01.json", in: &files) { $0["cells"] = [0, 0, 0, 1, 2, 1, 2, 1, 2] }
        rejects(files, containing: "cannot be cleared")
        files = base
        try payload("Levels/intro-01.json", in: &files) { $0["cells"] = [0, 0, 0, 1, 5, 1, 1, 5, 1] }
        rejects(files, containing: "color 1...4")
        files = base
        try payload("Levels/intro-01.json", in: &files) { $0["columns"] = 9; $0["rows"] = 1 }
        rejects(files, containing: "2...8 columns")
        files = base
        try payload("Levels/intro-01.json", in: &files) { $0["nextLevelIDs"] = ["absent-level"] }
        rejects(files, containing: "next-level reference")
        files = base
        try mutate("Levels/intro-02.json", in: &files) { $0["gameType"] = "tile" }
        rejects(files, containing: "game type does not match")
        files = base
        try mutate("catalog.json", in: &files) { catalog in
            var levels = catalog["levels"] as! [[String: Any]]
            levels[1]["gameType"] = "dig"
            catalog["levels"] = levels
        }
        rejects(files, containing: "only block levels")
    }

    func testNextLevelFollowsSavedProgress() throws {
        let catalog = try BundledContent.load()
        XCTAssertEqual(catalog.nextLevel(after: SaveProgress()).id, "intro-01")
        XCTAssertEqual(catalog.nextLevel(after: SaveProgress(completedLevels: ["intro-01"])).id, "intro-02")
        XCTAssertEqual(catalog.nextLevel(after: SaveProgress(completedLevels: ["intro-02"])).id, "intro-01",
                       "Catalog order, not completion order, chooses the next level")
        XCTAssertEqual(catalog.nextLevel(after: SaveProgress(completedLevels: ["intro-01", "intro-02", "removed-level"])).id,
                       "intro-02", "Replays the last level once all are complete")
    }
}
