import Foundation
import GameCore

/// Blocky Marty's rules (ADR-010): select a group of two or more orthogonally
/// connected blocks of one kind to clear it, and the blocks above fall
/// straight down; columns never shift sideways. A board is cleared when empty
/// and stuck when blocks remain but no group of two does. Undo takes back
/// moves, a stuck board's included.
public struct BlockBoard: Equatable, Sendable {
    public static let colors = 1...4
    public let columns: Int
    public let rows: Int
    /// Row-major from the top row; 0 is empty, otherwise a color.
    public private(set) var cells: [Int]

    public init(columns: Int, rows: Int, cells: [Int]) {
        precondition(columns > 0 && rows > 0 && cells.count == columns * rows, "Board cells must fill the grid")
        self.columns = columns
        self.rows = rows
        self.cells = cells
    }

    public var isEmpty: Bool { cells.allSatisfy { $0 == 0 } }
    public var hasMove: Bool { !moves.isEmpty }

    /// The lowest index of each clearable group, ascending.
    public var moves: [Int] {
        var seen = Set<Int>(), result: [Int] = []
        for index in cells.indices where cells[index] != 0 && !seen.contains(index) {
            let members = group(at: index)
            seen.formUnion(members)
            if members.count >= 2 { result.append(members[0]) }
        }
        return result
    }

    /// The blocks connected to `index` by color, ascending; empty for an empty cell.
    public func group(at index: Int) -> [Int] {
        guard cells.indices.contains(index), cells[index] != 0 else { return [] }
        let color = cells[index]
        var members: Set<Int> = [index], pending = [index]
        while let current = pending.popLast() {
            let row = current / columns, column = current % columns
            for (r, c) in [(row - 1, column), (row + 1, column), (row, column - 1), (row, column + 1)]
            where (0..<rows).contains(r) && (0..<columns).contains(c) {
                let neighbor = r * columns + c
                if cells[neighbor] == color && members.insert(neighbor).inserted { pending.append(neighbor) }
            }
        }
        return members.sorted()
    }

    /// Clears the group at `index` and lets the blocks above fall. Returns the
    /// number cleared, or 0 when the selection is not a legal move.
    @discardableResult
    public mutating func clear(at index: Int) -> Int {
        let members = group(at: index)
        guard members.count >= 2 else { return 0 }
        for member in members { cells[member] = 0 }
        for column in 0..<columns {
            let stack = (0..<rows).map { cells[$0 * columns + column] }.filter { $0 != 0 }
            let settled = Array(repeating: 0, count: rows - stack.count) + stack
            for row in 0..<rows { cells[row * columns + column] = settled[row] }
        }
        return members.count
    }
}

public enum BlockOutcome: Equatable, Sendable {
    case playing, cleared, stuck
}

/// Developer replay action: select the block at a board index, or undo.
public enum BlockAction: Codable, Equatable, Sendable {
    case select(Int)
    case undo
}

/// One play of a level. Frame time and animation never advance it; only
/// selections and undos do, so a level, its seed and an input fixture fix the
/// outcome.
public struct BlockGame: Equatable, Sendable {
    public let levelID: String
    public private(set) var board: BlockBoard
    public private(set) var score = 0
    /// The board and score before each move still on the board, oldest first.
    private var history: [Step] = []

    private struct Step: Equatable, Sendable {
        let board: BlockBoard
        let score: Int
    }

    public init(level: BlockLevel) {
        levelID = level.id
        board = BlockBoard(columns: level.payload.columns, rows: level.payload.rows, cells: level.payload.cells)
    }

    public var outcome: BlockOutcome {
        if board.isEmpty { return .cleared }
        return board.hasMove ? .playing : .stuck
    }

    /// Moves made and not undone.
    public var selections: Int { history.count }
    /// A cleared board is final; any other board with a move behind it can undo.
    public var canUndo: Bool { outcome != .cleared && !history.isEmpty }

    /// Applies one selection. An illegal selection or a finished game changes nothing.
    @discardableResult
    public mutating func select(_ index: Int) -> Bool {
        guard outcome == .playing else { return false }
        let before = Step(board: board, score: score)
        let cleared = board.clear(at: index)
        guard cleared > 0 else { return false }
        history.append(before)
        // Each block scores one point for every other block in its group.
        score += cleared * (cleared - 1)
        return true
    }

    /// Restores the board and score before the last move. Undo is free.
    @discardableResult
    public mutating func undo() -> Bool {
        guard canUndo, let last = history.popLast() else { return false }
        board = last.board
        score = last.score
        return true
    }

    @discardableResult
    public mutating func apply(_ action: BlockAction) -> Bool {
        switch action {
        case .select(let index): return select(index)
        case .undo: return undo()
        }
    }
}

public enum BlockReplay {
    /// Replays a developer fixture against its level; ticks only order inputs.
    public static func replay(level: BlockLevel, fixture: InputFixture<BlockAction>) throws -> BlockGame {
        try fixture.validate(level: level)
        var clock = GameTickClock(), game = BlockGame(level: level)
        for input in fixture.inputs {
            try clock.advance(by: input.tick - clock.tick)
            game.apply(input.action)
        }
        return game
    }

    /// A fixture that plays the level's recorded clearing sequence.
    public static func solutionFixture(level: BlockLevel) -> InputFixture<BlockAction> {
        InputFixture(levelID: level.id, contentVersion: level.contentVersion, seed: level.seed,
                     inputs: level.payload.solution.enumerated().map {
            TimedInput(tick: UInt64($0.offset + 1) * 10, action: .select($0.element))
        })
    }
}
