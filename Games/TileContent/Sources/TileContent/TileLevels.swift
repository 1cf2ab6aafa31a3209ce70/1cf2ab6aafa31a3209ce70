import Foundation
import GameCore

public struct TileMatchPayload: Codable, Equatable, Sendable {
    public let chapter: Int
    /// Every tile, bottom layer first; board indices refer to this order.
    public let tiles: [TileBoard.Tile]
    /// One clearing sequence: the board index taken by each move, in order.
    public let solution: [Int]
    public let nextLevelIDs: [String]

    public init(chapter: Int, tiles: [TileBoard.Tile], solution: [Int], nextLevelIDs: [String]) {
        self.chapter = chapter
        self.tiles = tiles
        self.solution = solution
        self.nextLevelIDs = nextLevelIDs
    }
}

/// A chapter's layers, kinds and tile counts (ADR-011): each chapter stacks
/// higher and adds kinds.
public struct TileChapter: Equatable, Sendable {
    public let number: Int
    public let layers: ClosedRange<Int>
    /// The chapter's boards use exactly kinds 1...k for a k in this range.
    public let kinds: ClosedRange<Int>
    public let tiles: ClosedRange<Int>

    public static let all = [TileChapter(number: 1, layers: 1...2, kinds: 2...4, tiles: 6...24),
                             TileChapter(number: 2, layers: 2...3, kinds: 4...5, tiles: 24...39),
                             TileChapter(number: 3, layers: 3...4, kinds: 5...6, tiles: 39...54)]
}

public typealias TileLevel = LevelEnvelope<TileMatchPayload>

/// Few Tiles' validated catalog. The app and the authoring validator both
/// decode through `decode`, so a level that fails here never ships.
public struct TileCatalog: Sendable {
    public static let titleID = "tile-match"
    /// The board's largest width and height in half cells: seven tiles across.
    public static let extent = 14
    public static let levelsPerChapter = 10
    public let envelope: CatalogEnvelope
    public let levels: [TileLevel]

    public func level(id: String) -> TileLevel? { levels.first { $0.id == id } }

    /// The first level in catalog order that `progress` has not completed.
    /// Once every level is complete, the level after `last`, the last level
    /// leading back to the first; without `last`, the first level.
    public func nextLevel(after progress: SaveProgress, following last: String? = nil) -> TileLevel {
        if let open = levels.first(where: { !progress.completedLevels.contains($0.id) }) { return open }
        guard let last, let index = levels.firstIndex(where: { $0.id == last }) else { return levels[0] }
        return levels[(index + 1) % levels.count]
    }

    public static func decode(catalogData: Data, availableAssets: Set<String>,
                              levelData: (String) throws -> Data) throws -> TileCatalog {
        let catalog: CatalogEnvelope
        do { catalog = try CatalogEnvelope.decode(catalogData) }
        catch { throw ContentValidationError(message: "catalog.json: malformed catalog: \(error.localizedDescription)") }
        try catalog.validate(availableAssets: availableAssets)
        guard catalog.titleID == titleID else {
            throw ContentValidationError(message: "catalog.json: expected \(titleID) title")
        }
        var levels: [TileLevel] = []
        for reference in catalog.levels {
            do {
                guard reference.gameType == .tile else {
                    throw ContentValidationError(message: "only tile levels belong to this title")
                }
                let level = try TileLevel.decode(try levelData(reference.file))
                try level.validate(reference: reference, catalog: catalog)
                try validate(level.payload)
                levels.append(level)
            } catch {
                throw ContentValidationError(message: "\(reference.file) [\(reference.id)]: \(error.localizedDescription)")
            }
        }
        try validateOrder(levels)
        return TileCatalog(envelope: catalog, levels: levels)
    }

    /// Chapters of ten in order, each level unlocking the next, no board or
    /// seed twice, and (ADR-011 rule 8) only the first two levels with too few
    /// kinds to fill the tray.
    private static func validateOrder(_ levels: [TileLevel]) throws {
        guard !levels.isEmpty else { throw ContentValidationError(message: "catalog.json: no levels") }
        for chapter in TileChapter.all where levels.filter({ $0.payload.chapter == chapter.number }).count != levelsPerChapter {
            throw ContentValidationError(message: "catalog.json: chapter \(chapter.number) must have \(levelsPerChapter) levels")
        }
        for level in levels.dropFirst(2) where Set(level.payload.tiles.map(\.kind)).count < 4 {
            throw ContentValidationError(message: "\(level.id): every level after the first two needs at least four kinds, so the tray can fill")
        }
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
        guard Set(levels.map(\.payload.tiles)).count == levels.count else {
            throw ContentValidationError(message: "catalog.json: two levels share a board")
        }
    }

    private static func validate(_ payload: TileMatchPayload) throws {
        guard let chapter = TileChapter.all.first(where: { $0.number == payload.chapter }) else {
            throw ContentValidationError(message: "chapter must be 1...\(TileChapter.all.count)")
        }
        let tiles = payload.tiles
        guard chapter.tiles.contains(tiles.count) else {
            throw ContentValidationError(message: "chapter \(chapter.number) boards must have \(chapter.tiles.lowerBound)...\(chapter.tiles.upperBound) tiles")
        }
        let layers = (tiles.map(\.layer).max() ?? -1) + 1
        guard chapter.layers.contains(layers) else {
            throw ContentValidationError(message: "chapter \(chapter.number) boards must have \(chapter.layers.lowerBound)...\(chapter.layers.upperBound) layers")
        }
        // The range check comes first, so an absurd kind fails before 1...k is built.
        let kinds = Set(tiles.map(\.kind))
        guard kinds.isSubset(of: Set(TileBoard.kinds)), let most = kinds.max(), kinds == Set(1...most),
              chapter.kinds.contains(kinds.count) else {
            throw ContentValidationError(message: "chapter \(chapter.number) tiles must use kinds 1...k for k in "
                                         + "\(chapter.kinds.lowerBound)...\(chapter.kinds.upperBound)")
        }
        guard kinds.allSatisfy({ kind in tiles.filter { $0.kind == kind }.count % 3 == 0 }) else {
            throw ContentValidationError(message: "every kind must have a multiple of three tiles")
        }
        for (index, tile) in tiles.enumerated() {
            guard tile.layer >= 0, tile.x >= 0, tile.y >= 0, tile.x + 2 <= extent, tile.y + 2 <= extent,
                  tile.x % 2 == tile.layer % 2, tile.y % 2 == tile.layer % 2 else {
                throw ContentValidationError(message: "tile \(index) must lie within \(extent) half cells, "
                                             + "on even half cells on even layers and odd half cells on odd layers")
            }
            if index > 0, tile.layer < tiles[index - 1].layer {
                throw ContentValidationError(message: "tiles must be listed bottom layer first")
            }
            if tiles[..<index].contains(where: { $0.layer == tile.layer && $0.overlaps(tile) }) {
                throw ContentValidationError(message: "tile \(index) overlaps another tile on its layer")
            }
            if tile.layer > 0, !tiles.contains(where: { $0.layer == tile.layer - 1 && $0.overlaps(tile) }) {
                throw ContentValidationError(message: "tile \(index) must rest on a tile in the layer below")
            }
        }
        var game = TileGame(board: TileBoard(tiles: tiles))
        for move in payload.solution {
            guard game.select(move) else {
                throw ContentValidationError(message: "clearing sequence cannot take tile \(move)")
            }
        }
        guard game.outcome == .cleared else {
            throw ContentValidationError(message: "clearing sequence leaves tiles on the board or in the tray")
        }
    }
}
