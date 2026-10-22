import Foundation
import GameCore

/// Few Tiles' board (ADR-011): tiles in overlapping layers. A tile covers a
/// square two half cells wide; it is covered while a tile on a higher layer
/// overlaps that square, and free otherwise. Only free tiles can be taken.
public struct TileBoard: Equatable, Sendable {
    public static let kinds = 1...6

    /// One tile: its layer from 0 at the bottom, the top-left corner of its
    /// square in half cells, and its kind. Encoded as `[layer, x, y, kind]`.
    public struct Tile: Codable, Equatable, Hashable, Sendable {
        public let layer: Int
        public let x: Int
        public let y: Int
        public let kind: Int

        public init(layer: Int, x: Int, y: Int, kind: Int) {
            self.layer = layer
            self.x = x
            self.y = y
            self.kind = kind
        }

        public init(from decoder: Decoder) throws {
            var values = try decoder.unkeyedContainer()
            layer = try values.decode(Int.self)
            x = try values.decode(Int.self)
            y = try values.decode(Int.self)
            kind = try values.decode(Int.self)
            guard values.isAtEnd else {
                throw DecodingError.dataCorruptedError(in: values, debugDescription: "A tile is [layer, x, y, kind]")
            }
        }

        public func encode(to encoder: Encoder) throws {
            var values = encoder.unkeyedContainer()
            try values.encode(contentsOf: [layer, x, y, kind])
        }

        /// True when the two tiles' squares share any area.
        public func overlaps(_ other: Tile) -> Bool { abs(x - other.x) < 2 && abs(y - other.y) < 2 }
    }

    public let tiles: [Tile]
    /// Whether each tile is still on the board.
    public private(set) var present: [Bool]
    /// For each tile, the tiles on higher layers that overlap it.
    public let coveredBy: [[Int]]

    public init(tiles: [Tile]) {
        self.tiles = tiles
        present = Array(repeating: true, count: tiles.count)
        coveredBy = tiles.map { tile in
            tiles.indices.filter { tiles[$0].layer > tile.layer && tiles[$0].overlaps(tile) }
        }
    }

    public var isEmpty: Bool { !present.contains(true) }
    public var remaining: Int { present.filter { $0 }.count }
    /// Width and height in half cells.
    public var width: Int { (tiles.map(\.x).max() ?? 0) + 2 }
    public var height: Int { (tiles.map(\.y).max() ?? 0) + 2 }

    public func isFree(_ index: Int) -> Bool {
        tiles.indices.contains(index) && present[index] && coveredBy[index].allSatisfy { !present[$0] }
    }

    /// Free tiles, ascending.
    public var free: [Int] { tiles.indices.filter(isFree) }

    /// The covered tiles that taking `index` would free, ascending.
    public func uncovers(_ index: Int) -> [Int] {
        guard isFree(index) else { return [] }
        return tiles.indices.filter { other in
            present[other] && coveredBy[other].contains(index)
                && coveredBy[other].allSatisfy { $0 == index || !present[$0] }
        }
    }

    /// Takes a free tile off the board. Returns false for any other index.
    @discardableResult
    public mutating func take(_ index: Int) -> Bool {
        guard isFree(index) else { return false }
        present[index] = false
        return true
    }
}

public enum TileOutcome: Equatable, Sendable {
    case playing, cleared, trayFull
}

/// Developer replay action: take the tile at a board index, or undo.
public enum TileAction: Codable, Equatable, Sendable {
    case select(Int)
    case undo
}

/// One play of a level (ADR-011). A taken tile joins its kind in the tray;
/// three alike clear. A full tray stays in play so Undo can take moves back.
/// Only selections and undos advance it, so a level, its seed and an input
/// fixture fix the outcome.
public struct TileGame: Equatable, Sendable {
    public static let traySlots = 7
    public let levelID: String
    public private(set) var board: TileBoard
    /// Board indices of the tiles in the tray, in display order.
    public private(set) var tray: [Int] = []
    public private(set) var score = 0
    /// The state before each move still in play, oldest first.
    private var history: [Step] = []

    private struct Step: Equatable, Sendable {
        let board: TileBoard
        let tray: [Int]
        let score: Int
    }

    public init(level: TileLevel) {
        self.init(levelID: level.id, board: TileBoard(tiles: level.payload.tiles))
    }

    /// A play of a bare board, for validation and authoring.
    public init(levelID: String = "", board: TileBoard) {
        self.levelID = levelID
        self.board = board
    }

    public var outcome: TileOutcome {
        if board.isEmpty && tray.isEmpty { return .cleared }
        return tray.count >= Self.traySlots ? .trayFull : .playing
    }

    /// Moves made and not undone.
    public var selections: Int { history.count }
    /// A cleared board is final; any other board with a move behind it can undo.
    public var canUndo: Bool { outcome != .cleared && !history.isEmpty }

    /// Takes one free tile into the tray. A covered or absent tile, a full
    /// tray or a finished game changes nothing.
    @discardableResult
    public mutating func select(_ index: Int) -> Bool {
        guard outcome == .playing else { return false }
        let before = Step(board: board, tray: tray, score: score)
        guard board.take(index) else { return false }
        history.append(before)
        let kind = board.tiles[index].kind
        let insertion = (tray.lastIndex { board.tiles[$0].kind == kind }).map { $0 + 1 } ?? tray.endIndex
        tray.insert(index, at: insertion)
        if tray.filter({ board.tiles[$0].kind == kind }).count == 3 {
            tray.removeAll { board.tiles[$0].kind == kind }
            // A triple scores the tray room it leaves (ADR-011 rule 7).
            score += Self.traySlots - tray.count
        }
        return true
    }

    /// Restores the board, tray and score before the last move. Undo is free.
    @discardableResult
    public mutating func undo() -> Bool {
        guard canUndo, let last = history.popLast() else { return false }
        board = last.board
        tray = last.tray
        score = last.score
        return true
    }

    @discardableResult
    public mutating func apply(_ action: TileAction) -> Bool {
        switch action {
        case .select(let index): return select(index)
        case .undo: return undo()
        }
    }
}

public enum TileReplay {
    /// Replays a developer fixture against its level; ticks only order inputs.
    public static func replay(level: TileLevel, fixture: InputFixture<TileAction>) throws -> TileGame {
        try fixture.validate(level: level)
        var clock = GameTickClock(), game = TileGame(level: level)
        for input in fixture.inputs {
            try clock.advance(by: input.tick - clock.tick)
            game.apply(input.action)
        }
        return game
    }

    /// A fixture that plays the level's recorded clearing sequence.
    public static func solutionFixture(level: TileLevel) -> InputFixture<TileAction> {
        InputFixture(levelID: level.id, contentVersion: level.contentVersion, seed: level.seed,
                     inputs: level.payload.solution.enumerated().map {
            TimedInput(tick: UInt64($0.offset + 1) * 10, action: .select($0.element))
        })
    }
}
