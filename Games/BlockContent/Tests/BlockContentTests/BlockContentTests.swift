@testable import BlockContent
import Foundation
import GameCore
import XCTest

final class BlockContentTests: XCTestCase {
    private func resources() throws -> [String: Data] {
        let root = try BundledContent.resourceDirectory()
        let files = ["catalog.json"] + (try BundledContent.load().envelope.levels.map(\.file))
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

    func testBundledCatalogHasThreeChaptersOfTenLevelsForThisTitleOnly() throws {
        let catalog = try BundledContent.load()
        XCTAssertEqual(catalog.envelope.titleID, "block-match")
        XCTAssertEqual(catalog.levels.count, 30)
        XCTAssertEqual(catalog.levels.prefix(2).map(\.id), ["intro-01", "intro-02"], "The hand-written boards open the title")
        for chapter in BlockChapter.all {
            let levels = catalog.levels.filter { $0.payload.chapter == chapter.number }
            XCTAssertEqual(levels.count, 10, "chapter \(chapter.number)")
            for level in levels {
                XCTAssertTrue(chapter.sizes.contains(level.payload.columns) && chapter.sizes.contains(level.payload.rows), level.id)
                XCTAssertEqual(Set(level.payload.cells.filter { $0 != 0 }), Set(1...chapter.kinds), level.id)
            }
        }
        XCTAssertEqual(catalog.levels.map(\.payload.nextLevelIDs), catalog.levels.dropFirst().map { [$0.id] } + [[]],
                       "Each level unlocks the next")
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

    func testEveryLevelsRecordedSequenceReplaysToTheSameClearedOutcome() throws {
        for level in try BundledContent.load().levels {
            let fixture = BlockReplay.solutionFixture(level: level)
            let first = try BlockReplay.replay(level: level, fixture: fixture)
            XCTAssertEqual(first.outcome, .cleared, level.id)
            XCTAssertEqual(try BlockReplay.replay(level: level, fixture: fixture), first, "Replays are deterministic")
            XCTAssertGreaterThan(first.score, 0)
        }
        XCTAssertEqual(BlockReplay.solutionFixture(level: try level("intro-01")).inputs.map(\.action), [.select(3), .select(4), .select(5)])
    }

    /// The scoring review's case (ADR-010): forming the group of five first
    /// outscores every clearing line but strands a block, so only a cleared
    /// board's score counts.
    func testWrongFirstChoiceOnTheSecondLevelGetsStuckWithAHigherScoreThanAClear() throws {
        let level = try level("intro-02")
        let fixture = InputFixture(levelID: level.id, contentVersion: level.contentVersion, seed: level.seed,
                                   inputs: [TimedInput(tick: 10, action: BlockAction.select(9)),
                                            TimedInput(tick: 20, action: .select(8))])
        let game = try BlockReplay.replay(level: level, fixture: fixture)
        XCTAssertEqual(game.outcome, .stuck)
        XCTAssertEqual(game.board.cells.filter { $0 != 0 }, [2], "One block remains with no partner")
        XCTAssertEqual(game.selections, 2)
        XCTAssertEqual(game.score, 3 * 2 + 5 * 4)
        let cleared = try BlockReplay.replay(level: level, fixture: BlockReplay.solutionFixture(level: level))
        XCTAssertLessThan(cleared.score, game.score)
    }

    func testUndoRestoresTheBoardAndScoreAndReplays() throws {
        let level = try level("intro-02")
        var game = BlockGame(level: level)
        let start = game
        XCTAssertFalse(game.canUndo)
        XCTAssertFalse(game.undo(), "Nothing to undo on a fresh board")
        XCTAssertTrue(game.select(9))
        let afterFirst = game
        XCTAssertTrue(game.select(8))
        XCTAssertEqual(game.outcome, .stuck)
        XCTAssertTrue(game.canUndo, "A stuck board can undo")
        XCTAssertTrue(game.undo())
        XCTAssertEqual(game, afterFirst, "Undo restores the board and score before the last move")
        XCTAssertTrue(game.undo())
        XCTAssertEqual(game, start)
        XCTAssertFalse(game.undo())
        for move in level.payload.solution { XCTAssertTrue(game.select(move)) }
        XCTAssertEqual(game.outcome, .cleared)
        XCTAssertFalse(game.canUndo, "A cleared board is final")
        XCTAssertFalse(game.undo())

        let fixture = InputFixture(levelID: level.id, contentVersion: level.contentVersion, seed: level.seed,
                                   inputs: [TimedInput(tick: 10, action: BlockAction.select(9)), TimedInput(tick: 20, action: .select(8)),
                                            TimedInput(tick: 30, action: .undo), TimedInput(tick: 40, action: .undo)]
                                       + level.payload.solution.enumerated().map {
                                           TimedInput(tick: UInt64(50 + $0.offset * 10), action: .select($0.element))
                                       })
        let replayed = try BlockReplay.replay(level: level, fixture: fixture)
        XCTAssertEqual(replayed.outcome, .cleared)
        XCTAssertEqual(replayed, try BlockReplay.replay(level: level, fixture: BlockReplay.solutionFixture(level: level)),
                       "Undone moves leave no trace in the outcome or score")
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
        let mismatched = InputFixture(levelID: "intro-02", contentVersion: 2, seed: 201, inputs: [TimedInput(tick: 1, action: BlockAction.select(3))])
        XCTAssertThrowsError(try BlockReplay.replay(level: try level("intro-01"), fixture: mismatched))
    }

    func testValidationRejectsFloatingUnclearableAndMisreferencedLevels() throws {
        let base = try resources()
        var files = base
        try payload("Levels/intro-01.json", in: &files) { $0["cells"] = [1, 0, 0, 0, 2, 1, 1, 2, 1] }
        rejects(files, containing: "rest on the floor")
        files = base
        try payload("Levels/intro-01.json", in: &files) { $0["cells"] = [0, 0, 0, 1, 2, 1, 2, 1, 2] }
        rejects(files, containing: "selects no group at 3")
        files = base
        try payload("Levels/intro-01.json", in: &files) { $0["solution"] = [3, 4] }
        rejects(files, containing: "leaves blocks")
        files = base
        try payload("Levels/intro-01.json", in: &files) { $0["cells"] = [0, 0, 0, 1, 5, 1, 1, 5, 1] }
        rejects(files, containing: "kind 1...2")
        files = base
        try payload("Levels/intro-01.json", in: &files) { $0["columns"] = 9; $0["rows"] = 1 }
        rejects(files, containing: "3...5 columns")
        files = base
        try payload("Levels/intro-01.json", in: &files) { $0["chapter"] = 4 }
        rejects(files, containing: "chapter must be 1...3")
        files = base
        try payload("Levels/intro-01.json", in: &files) { $0["nextLevelIDs"] = ["absent-level"] }
        rejects(files, containing: "unlock exactly the next level")
        files = base
        try mutate("catalog.json", in: &files) { catalog in
            var levels = catalog["levels"] as! [[String: Any]]
            levels.swapAt(9, 10)
            catalog["levels"] = levels
        }
        rejects(files, containing: "unlock exactly the next level")
        files = base
        try mutate("Levels/intro-03.json", in: &files) { $0["seed"] = 202 }
        rejects(files, containing: "share a seed")
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

    func testNextLevelFollowsSavedProgressThenCyclesOnceAllAreComplete() throws {
        let catalog = try BundledContent.load()
        XCTAssertEqual(catalog.nextLevel(after: SaveProgress()).id, "intro-01")
        XCTAssertEqual(catalog.nextLevel(after: SaveProgress(completedLevels: ["intro-01"])).id, "intro-02")
        XCTAssertEqual(catalog.nextLevel(after: SaveProgress(completedLevels: ["intro-02"]), following: "intro-02").id, "intro-01",
                       "Catalog order, not completion order, chooses the next level")
        let all = SaveProgress(completedLevels: catalog.levels.map(\.id) + ["removed-level"])
        XCTAssertEqual(catalog.nextLevel(after: all).id, "intro-01", "With every level complete, Play starts over")
        XCTAssertEqual(catalog.nextLevel(after: all, following: "middle-04").id, "middle-05")
        XCTAssertEqual(catalog.nextLevel(after: all, following: "final-10").id, "intro-01", "The last level leads back to the first")
        XCTAssertEqual(catalog.nextLevel(after: all, following: "removed-level").id, "intro-01")
    }
}
