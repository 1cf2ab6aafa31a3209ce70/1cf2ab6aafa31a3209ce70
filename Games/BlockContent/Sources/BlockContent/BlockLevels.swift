import Foundation
import GameCore

public struct BlockMatchPayload: Codable, Equatable, Sendable {
    public let chapter: Int
    public let columns: Int
    public let rows: Int
    /// Row-major from the top row; 0 is empty, 1...4 a block kind.
    public let cells: [Int]
    /// One clearing sequence: the board index selected by each move, in order.
    public let solution: [Int]
    public let nextLevelIDs: [String]

    public init(chapter: Int, columns: Int, rows: Int, cells: [Int], solution: [Int], nextLevelIDs: [String]) {
        self.chapter = chapter
        self.columns = columns
        self.rows = rows
        self.cells = cells
        self.solution = solution
        self.nextLevelIDs = nextLevelIDs
    }
}

/// A chapter's board sizes and block kinds (ADR-010): each chapter adds a kind.
public struct BlockChapter: Equatable, Sendable {
    public let number: Int
    /// Allowed columns and rows.
    public let sizes: ClosedRange<Int>
    /// The chapter's boards use exactly kinds 1...kinds.
    public let kinds: Int

    public static let all = [BlockChapter(number: 1, sizes: 3...5, kinds: 2),
                             BlockChapter(number: 2, sizes: 5...7, kinds: 3),
                             BlockChapter(number: 3, sizes: 6...8, kinds: 4)]
}

public typealias BlockLevel = LevelEnvelope<BlockMatchPayload>

/// The block title's validated catalog. The app and the authoring validator
/// both decode through `decode`, so a level that fails here never ships.
public struct BlockCatalog: Sendable {
    public static let titleID = "block-match"
    public let envelope: CatalogEnvelope
    public let levels: [BlockLevel]

    public func level(id: String) -> BlockLevel? { levels.first { $0.id == id } }

    /// The first level in catalog order that `progress` has not completed.
    /// Once every level is complete, the level after `last`, the last level
    /// leading back to the first; without `last`, the first level.
    public func nextLevel(after progress: SaveProgress, following last: String? = nil) -> BlockLevel {
        if let open = levels.first(where: { !progress.completedLevels.contains($0.id) }) { return open }
        guard let last, let index = levels.firstIndex(where: { $0.id == last }) else { return levels[0] }
        return levels[(index + 1) % levels.count]
    }

    public static func decode(catalogData: Data, availableAssets: Set<String>,
                              levelData: (String) throws -> Data) throws -> BlockCatalog {
        let catalog: CatalogEnvelope
        do { catalog = try CatalogEnvelope.decode(catalogData) }
        catch { throw ContentValidationError(message: "catalog.json: malformed catalog: \(error.localizedDescription)") }
        try catalog.validate(availableAssets: availableAssets)
        guard catalog.titleID == titleID else {
            throw ContentValidationError(message: "catalog.json: expected \(titleID) title")
        }
        var levels: [BlockLevel] = []
        for reference in catalog.levels {
            do {
                guard reference.gameType == .block else {
                    throw ContentValidationError(message: "only block levels belong to this title")
                }
                let level = try BlockLevel.decode(try levelData(reference.file))
                try level.validate(reference: reference, catalog: catalog)
                try validate(level.payload)
                levels.append(level)
            } catch {
                throw ContentValidationError(message: "\(reference.file) [\(reference.id)]: \(error.localizedDescription)")
            }
        }
        try validateOrder(levels)
        return BlockCatalog(envelope: catalog, levels: levels)
    }

    /// Chapters in order, each level unlocking the next, and no board or seed twice.
    private static func validateOrder(_ levels: [BlockLevel]) throws {
        guard !levels.isEmpty else { throw ContentValidationError(message: "catalog.json: no levels") }
        for (index, level) in levels.enumerated() {
            let next = index + 1 < levels.count ? [levels[index + 1].id] : []
            guard level.payload.nextLevelIDs == next else {
                throw ContentValidationError(message: "\(level.id): must unlock exactly the next level in catalog order")
            }
            if index > 0, level.payload.chapter < levels[index - 1].payload.chapter {
                throw ContentValidationError(message: "\(level.id): chapters must not go backwards in catalog order")
            }
        }
        guard Set(levels.map(\.seed)).count == levels.count else {
            throw ContentValidationError(message: "catalog.json: two levels share a seed")
        }
        let boards = levels.map { [$0.payload.columns, $0.payload.rows] + $0.payload.cells }
        guard Set(boards).count == levels.count else {
            throw ContentValidationError(message: "catalog.json: two levels share a board")
        }
    }

    private static func validate(_ payload: BlockMatchPayload) throws {
        guard let chapter = BlockChapter.all.first(where: { $0.number == payload.chapter }) else {
            throw ContentValidationError(message: "chapter must be 1...\(BlockChapter.all.count)")
        }
        let sizes = chapter.sizes
        guard sizes.contains(payload.columns), sizes.contains(payload.rows),
              payload.cells.count == payload.columns * payload.rows else {
            throw ContentValidationError(message: "chapter \(chapter.number) boards must be \(sizes.lowerBound)...\(sizes.upperBound) "
                                         + "columns by \(sizes.lowerBound)...\(sizes.upperBound) rows with one cell each")
        }
        guard Set(payload.cells.filter { $0 != 0 }) == Set(1...chapter.kinds),
              payload.cells.allSatisfy({ $0 == 0 || BlockBoard.colors.contains($0) }) else {
            throw ContentValidationError(message: "chapter \(chapter.number) cells must be 0 or a kind 1...\(chapter.kinds), using every kind")
        }
        for column in 0..<payload.columns {
            let stack = (0..<payload.rows).map { payload.cells[$0 * payload.columns + column] }
            let top = stack.firstIndex(where: { $0 != 0 }) ?? payload.rows
            guard stack[top...].allSatisfy({ $0 != 0 }) else {
                throw ContentValidationError(message: "blocks must rest on the floor or another block")
            }
        }
        var board = BlockBoard(columns: payload.columns, rows: payload.rows, cells: payload.cells)
        for move in payload.solution {
            guard board.clear(at: move) > 0 else {
                throw ContentValidationError(message: "clearing sequence selects no group at \(move)")
            }
        }
        guard board.isEmpty else {
            throw ContentValidationError(message: "clearing sequence leaves blocks on the board")
        }
    }
}
