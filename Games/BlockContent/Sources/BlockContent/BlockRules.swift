import Foundation
import GameCore

/// Reference rules for the Epic 07 block slice, kept to what the module
/// contract needs: select a group of two or more orthogonally connected blocks
/// of one color to clear it, and the blocks above fall into the gap. A board is
/// won when empty and lost when blocks remain but no group of two does.
/// Epic 09A records the complete title's rules and extends these.
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

/// Developer replay action: select the block at a board index.
public struct BlockAction: Codable, Equatable, Sendable {
    public let index: Int
    public init(index: Int) { self.index = index }
}

/// One play of a level. Frame time and animation never advance it; only
/// selections do, so a level, its seed and an input fixture fix the outcome.
public struct BlockGame: Equatable, Sendable {
    public let levelID: String
    public private(set) var board: BlockBoard
    public private(set) var score = 0
    public private(set) var selections = 0

    public init(level: BlockLevel) {
        levelID = level.id
        board = BlockBoard(columns: level.payload.columns, rows: level.payload.rows, cells: level.payload.cells)
    }

    public var outcome: BlockOutcome {
        if board.isEmpty { return .cleared }
        return board.hasMove ? .playing : .stuck
    }

    /// Applies one selection. An illegal selection or a finished game changes nothing.
    @discardableResult
    public mutating func select(_ index: Int) -> Bool {
        guard outcome == .playing else { return false }
        let cleared = board.clear(at: index)
        guard cleared > 0 else { return false }
        selections += 1
        // Larger groups score more: n blocks earn n × (n − 1).
        score += cleared * (cleared - 1)
        return true
    }
}

public enum BlockReplay {
    /// Replays a developer fixture against its level; ticks only order inputs.
    public static func replay(level: BlockLevel, fixture: InputFixture<BlockAction>) throws -> BlockGame {
        try fixture.validate(level: level)
        var clock = GameTickClock(), game = BlockGame(level: level)
        for input in fixture.inputs {
            try clock.advance(by: input.tick - clock.tick)
            game.select(input.action.index)
        }
        return game
    }

    /// The first clearing sequence in move order, or nil when none exists or
    /// the search exceeds `stateLimit` distinct boards.
    public static func solution(for board: BlockBoard, stateLimit: Int = 100_000) -> [Int]? {
        var dead = Set<[Int]>()
        func search(_ board: BlockBoard) -> [Int]? {
            if board.isEmpty { return [] }
            guard !dead.contains(board.cells), dead.count < stateLimit else { return nil }
            for move in board.moves {
                var next = board
                next.clear(at: move)
                if let rest = search(next) { return [move] + rest }
            }
            dead.insert(board.cells)
            return nil
        }
        return search(board)
    }

    /// Test helper: a fixture that plays the level's first solution.
    public static func solutionFixture(level: BlockLevel) -> InputFixture<BlockAction>? {
        let board = BlockBoard(columns: level.payload.columns, rows: level.payload.rows, cells: level.payload.cells)
        guard let moves = solution(for: board) else { return nil }
        return InputFixture(levelID: level.id, contentVersion: level.contentVersion, seed: level.seed,
                            inputs: moves.enumerated().map {
            TimedInput(tick: UInt64($0.offset + 1) * 10, action: BlockAction(index: $0.element))
        })
    }
}
