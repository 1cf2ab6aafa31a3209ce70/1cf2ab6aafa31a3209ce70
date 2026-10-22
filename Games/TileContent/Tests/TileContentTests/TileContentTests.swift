@testable import TileContent
import Foundation
import GameCore
import XCTest

final class TileContentTests: XCTestCase {
    private func resources() throws -> [String: Data] {
        let root = try BundledContent.resourceDirectory()
        let files = ["catalog.json"] + (try BundledContent.load().envelope.levels.map(\.file))
        return try Dictionary(uniqueKeysWithValues: files.map { ($0, try Data(contentsOf: root.appendingPathComponent($0))) })
    }
    private func load(_ files: [String: Data]) throws -> TileCatalog {
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
    private func level(_ id: String) throws -> TileLevel {
        try XCTUnwrap(BundledContent.load().level(id: id))
    }
    private func kinds(_ game: TileGame) -> [Int] { game.tray.map { game.board.tiles[$0].kind } }

    func testBundledCatalogHasThreeChaptersOfTenLevelsForThisTitleOnly() throws {
        let catalog = try BundledContent.load()
        XCTAssertEqual(catalog.envelope.titleID, "tile-match")
        XCTAssertEqual(catalog.levels.count, 30)
        XCTAssertEqual(catalog.levels.prefix(2).map(\.id), ["intro-01", "intro-02"], "The hand-written boards open the title")
        for chapter in TileChapter.all {
            let levels = catalog.levels.filter { $0.payload.chapter == chapter.number }
            XCTAssertEqual(levels.count, 10, "chapter \(chapter.number)")
            for level in levels {
                let tiles = level.payload.tiles
                XCTAssertTrue(chapter.tiles.contains(tiles.count), level.id)
                XCTAssertTrue(chapter.layers.contains(tiles.map(\.layer).max()! + 1), level.id)
                XCTAssertTrue(chapter.kinds.contains(Set(tiles.map(\.kind)).count), level.id)
            }
        }
        XCTAssertTrue(catalog.levels.dropFirst(2).allSatisfy { Set($0.payload.tiles.map(\.kind)).count >= 4 },
                      "Every level after the first two can fill the tray")
        XCTAssertEqual(catalog.levels.map(\.payload.nextLevelIDs), catalog.levels.dropFirst().map { [$0.id] } + [[]],
                       "Each level unlocks the next")
        var files = try resources()
        try mutate("catalog.json", in: &files) { $0["titleID"] = "block-match" }
        rejects(files, containing: "expected tile-match title")
    }

    func testACoveredTileIsFreedOnlyOnceEveryTileOnItIsGone() throws {
        // intro-02: one top tile (8) rests on the middle four of a 4 × 2 layer.
        var board = TileBoard(tiles: try level("intro-02").payload.tiles)
        XCTAssertEqual(board.free, [0, 3, 4, 7, 8])
        XCTAssertEqual(board.coveredBy[1], [8])
        XCTAssertEqual(board.uncovers(8), [1, 2, 5, 6])
        XCTAssertEqual(board.uncovers(0), [], "A bottom tile frees nothing")
        XCTAssertEqual(board.uncovers(1), [], "A covered tile frees nothing")
        XCTAssertFalse(board.take(1), "A covered tile cannot be taken")
        XCTAssertTrue(board.take(8))
        XCTAssertEqual(board.free, Array(0...7))
        XCTAssertFalse(board.take(8), "A taken tile cannot be taken again")
        XCTAssertEqual(board.remaining, 8)
        XCTAssertEqual(board.width, 8)
        XCTAssertEqual(board.height, 4)
    }

    func testTheTrayKeepsKindsTogetherAndATripleScoresTheRoomItLeaves() throws {
        var game = TileGame(level: try level("intro-02"))
        XCTAssertTrue(game.select(8))
        XCTAssertTrue(game.select(0))
        XCTAssertTrue(game.select(1), "The top tile's removal freed tile 1")
        XCTAssertEqual(game.tray, [8, 1, 0], "A tile joins its kind in the tray")
        XCTAssertEqual(kinds(game), [1, 1, 2])
        XCTAssertEqual(game.score, 0)
        XCTAssertTrue(game.select(6))
        XCTAssertEqual(game.tray, [0], "Three alike clear")
        XCTAssertEqual(game.score, 6, "The triple leaves six of seven slots empty")
        XCTAssertEqual(game.outcome, .playing)
    }

    /// The third level teaches the full tray (ADR-011 rule 5): seven tiles of
    /// four kinds with no three alike stop play until Undo.
    func testCarelessPlayFillsTheTrayOnTheThirdLevelAndUndoRecovers() throws {
        let level = try level("intro-03")
        var game = TileGame(level: level)
        for index in [8, 9, 11, 0, 7, 4] { XCTAssertTrue(game.select(index), "tile \(index)") }
        XCTAssertEqual(game.outcome, .playing)
        XCTAssertTrue(game.select(10))
        XCTAssertEqual(game.outcome, .trayFull)
        XCTAssertEqual(kinds(game), [3, 3, 2, 2, 4, 4, 1])
        XCTAssertFalse(game.select(1), "A full tray takes no tile")
        XCTAssertTrue(game.canUndo, "A full tray can undo")
        XCTAssertTrue(game.undo())
        XCTAssertEqual(game.outcome, .playing)
        XCTAssertEqual(game.board.remaining, 6)
        for index in [1, 10, 5, 3, 2, 6] { XCTAssertTrue(game.select(index), "tile \(index)") }
        XCTAssertEqual(game.outcome, .cleared)
        XCTAssertEqual(game.score, 3 + 4 + 6 + 7)
    }

    func testEveryLevelsRecordedSequenceReplaysToTheSameClearedOutcome() throws {
        for level in try BundledContent.load().levels {
            let fixture = TileReplay.solutionFixture(level: level)
            let first = try TileReplay.replay(level: level, fixture: fixture)
            XCTAssertEqual(first.outcome, .cleared, level.id)
            XCTAssertEqual(try TileReplay.replay(level: level, fixture: fixture), first, "Replays are deterministic")
            XCTAssertEqual(first.selections, level.payload.tiles.count)
            let triples = level.payload.tiles.count / 3
            XCTAssertTrue((3 * triples...7 * triples).contains(first.score), "\(level.id): each triple scores 3 to 7")
        }
        XCTAssertEqual(TileReplay.solutionFixture(level: try level("intro-01")).inputs.map(\.action), (0...5).map { .select($0) })
    }

    func testUndoRestoresTheBoardTrayAndScoreAndReplays() throws {
        let level = try level("intro-02")
        var game = TileGame(level: level)
        let start = game
        XCTAssertFalse(game.canUndo)
        XCTAssertFalse(game.undo(), "Nothing to undo on a fresh board")
        for index in [8, 0, 1] { XCTAssertTrue(game.select(index)) }
        let beforeTriple = game
        XCTAssertTrue(game.select(6))
        XCTAssertTrue(game.undo())
        XCTAssertEqual(game, beforeTriple, "Undo brings back a cleared triple and its score")
        for _ in 0..<3 { XCTAssertTrue(game.undo()) }
        XCTAssertEqual(game, start)
        XCTAssertFalse(game.undo())
        for move in level.payload.solution { XCTAssertTrue(game.select(move)) }
        XCTAssertEqual(game.outcome, .cleared)
        XCTAssertFalse(game.canUndo, "A cleared board is final")
        XCTAssertFalse(game.undo())

        let fixture = InputFixture(levelID: level.id, contentVersion: level.contentVersion, seed: level.seed,
                                   inputs: [TimedInput(tick: 10, action: TileAction.select(8)), TimedInput(tick: 20, action: .select(0)),
                                            TimedInput(tick: 30, action: .undo), TimedInput(tick: 40, action: .undo)]
                                       + level.payload.solution.enumerated().map {
                                           TimedInput(tick: UInt64(50 + $0.offset * 10), action: .select($0.element))
                                       })
        let replayed = try TileReplay.replay(level: level, fixture: fixture)
        XCTAssertEqual(replayed.outcome, .cleared)
        XCTAssertEqual(replayed, try TileReplay.replay(level: level, fixture: TileReplay.solutionFixture(level: level)),
                       "Undone moves leave no trace in the outcome or score")
    }

    func testIllegalOrLateSelectionsChangeNothing() throws {
        var game = TileGame(level: try level("intro-02"))
        let start = game
        for index in [-1, 1, 2, 5, 6, 9, 100] { XCTAssertFalse(game.select(index), "tile \(index)") }
        XCTAssertEqual(game, start)
        for index in try level("intro-02").payload.solution { XCTAssertTrue(game.select(index)) }
        XCTAssertEqual(game.outcome, .cleared)
        XCTAssertFalse(game.select(0), "A finished game accepts no selection")
        XCTAssertEqual(game.selections, 9)
        let mismatched = InputFixture(levelID: "intro-01", contentVersion: 1, seed: 302, inputs: [TimedInput(tick: 1, action: TileAction.select(0))])
        XCTAssertThrowsError(try TileReplay.replay(level: try level("intro-02"), fixture: mismatched))
    }

    func testValidationRejectsMisplacedUnclearableAndMisreferencedLevels() throws {
        let base = try resources()
        var files = base
        func tiles(_ file: String, _ change: @escaping (inout [[Int]]) -> Void) throws {
            files = base
            try payload(file, in: &files) { payload in
                var tiles = payload["tiles"] as! [[Int]]
                change(&tiles)
                payload["tiles"] = tiles
            }
        }
        try tiles("Levels/intro-02.json") { $0[8] = [1, 2, 1, 1] }
        rejects(files, containing: "odd half cells on odd layers")
        try tiles("Levels/intro-02.json") { $0[8] = [1, 13, 1, 1] }
        rejects(files, containing: "within 14 half cells")
        try tiles("Levels/intro-02.json") { $0[1] = [0, 1, 0, 1] }
        rejects(files, containing: "odd half cells")
        try tiles("Levels/intro-01.json") { $0[1] = [0, 0, 0, 2] }
        rejects(files, containing: "tile 1 overlaps another tile on its layer")
        try tiles("Levels/intro-02.json") { $0[8] = [1, 9, 1, 1] }
        rejects(files, containing: "must rest on a tile in the layer below")
        try tiles("Levels/intro-02.json") { $0.swapAt(0, 8) }
        rejects(files, containing: "bottom layer first")
        try tiles("Levels/intro-01.json") { $0[5] = [0, 4, 2, 1] }
        rejects(files, containing: "multiple of three")
        try tiles("Levels/intro-01.json") { $0 = $0.map { [$0[0], $0[1], $0[2], $0[3] == 2 ? 5 : $0[3]] } }
        rejects(files, containing: "kinds 1...k")
        files = base
        try payload("Levels/intro-01.json", in: &files) { $0["solution"] = [0, 1, 2, 3] }
        rejects(files, containing: "leaves tiles")
        files = base
        try payload("Levels/intro-02.json", in: &files) { $0["solution"] = [1] }
        rejects(files, containing: "cannot take tile 1")
        files = base
        try payload("Levels/intro-01.json", in: &files) { $0["chapter"] = 3 }
        rejects(files, containing: "chapter 3 boards must have 39...54 tiles")
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
        try mutate("Levels/intro-03.json", in: &files) { $0["seed"] = 302 }
        rejects(files, containing: "share a seed")
        files = base
        try mutate("Levels/intro-02.json", in: &files) { $0["gameType"] = "block" }
        rejects(files, containing: "game type does not match")
        files = base
        try mutate("catalog.json", in: &files) { catalog in
            var levels = catalog["levels"] as! [[String: Any]]
            levels[1]["gameType"] = "dig"
            catalog["levels"] = levels
        }
        rejects(files, containing: "only tile levels")
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
