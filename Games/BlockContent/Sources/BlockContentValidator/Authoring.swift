import BlockContent
import Foundation
import GameCore

// Authoring-only level tools (ADR-010). They live in the validator executable,
// so the app never links them: the solver for hand-written boards, the
// reverse-construction generator, and the playout measure that sets a
// generated level's difficulty band.

enum BlockSolver {
    /// The first clearing sequence in move order, or nil when none exists or
    /// the search exceeds `stateLimit` distinct boards.
    static func solution(for board: BlockBoard, stateLimit: Int = 100_000) -> [Int]? {
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
}

/// Integer draws from the shared SplitMix64 generator, so a seed fixes every
/// board on every toolchain.
struct AuthoringRandom {
    private var generator: DeterministicRNG
    init(seed: UInt64) { generator = DeterministicRNG(seed: seed) }
    mutating func pick(_ range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(generator.next(upperBound: UInt64(range.count)))
    }
}

enum BlockGenerator {
    struct Board: Equatable {
        let board: BlockBoard
        let solution: [Int]
    }

    /// Reverse construction from `seed`. Starting from an empty grid, each
    /// step inserts a group of one kind into the columns, pushing the blocks
    /// above it up; no block touching the group shares its kind, so the
    /// forward move clears exactly that group and the blocks above fall back.
    /// Clearing the groups in the reverse order of insertion empties the
    /// board, so every result carries its clearing sequence. Returns nil when
    /// the board stays below `minimumBlocks` or misses one of the kinds.
    static func generate(columns: Int, rows: Int, kinds: Int, minimumBlocks: Int, seed: UInt64) -> Board? {
        var random = AuthoringRandom(seed: seed)
        // Columns bottom first; `pending` marks the group being inserted.
        var stacks = Array(repeating: [Int](), count: columns)
        let pending = -1
        let largest = max(3, min(6, columns * rows / 6))
        var moves: [Int] = [], failures = 0
        while stacks.reduce(0, { $0 + $1.count }) < columns * rows && failures < 400 {
            failures += 1
            let size = random.pick(2...largest)
            let width = random.pick(1...min(size, columns))
            let first = random.pick(0...(columns - width))
            var runs = Array(repeating: 1, count: width)
            for _ in 0..<(size - width) { runs[random.pick(0...(width - 1))] += 1 }
            // Each column's run starts at or below its top block, and
            // neighboring runs share a row so the group stays connected.
            var starts: [Int] = []
            for (offset, run) in runs.enumerated() {
                let height = stacks[first + offset].count
                guard height + run <= rows else { break }
                var low = 0, high = height
                if let previous = starts.last {
                    low = max(low, previous - run + 1)
                    high = min(high, previous + runs[offset - 1] - 1)
                }
                guard low <= high else { break }
                starts.append(random.pick(low...high))
            }
            guard starts.count == width else { continue }
            var next = stacks
            for (offset, run) in runs.enumerated() {
                next[first + offset].insert(contentsOf: Array(repeating: pending, count: run), at: starts[offset])
            }
            let cells = (first..<(first + width)).flatMap { column in
                next[column].indices.filter { next[column][$0] == pending }.map { (column, $0) }
            }
            var touching = Set<Int>()
            for (column, height) in cells {
                for (c, h) in [(column, height - 1), (column, height + 1), (column - 1, height), (column + 1, height)]
                where (0..<columns).contains(c) && next[c].indices.contains(h) && next[c][h] != pending {
                    touching.insert(next[c][h])
                }
            }
            let choices = (1...kinds).filter { !touching.contains($0) }
            guard !choices.isEmpty else { continue }
            let kind = choices[random.pick(0...(choices.count - 1))]
            for (column, height) in cells { next[column][height] = kind }
            stacks = next
            moves.append(cells.map { (rows - 1 - $0.1) * columns + $0.0 }.min()!)
            failures = 0
        }
        let cells = (0..<rows).flatMap { row in
            (0..<columns).map { column in
                let height = rows - 1 - row
                return height < stacks[column].count ? stacks[column][height] : 0
            }
        }
        guard cells.filter({ $0 != 0 }).count >= minimumBlocks,
              Set(cells.filter { $0 != 0 }) == Set(1...kinds) else { return nil }
        let board = BlockBoard(columns: columns, rows: rows, cells: cells)
        let solution = Array(moves.reversed())
        var check = board
        for move in solution { precondition(check.clear(at: move) > 0, "Generated move selects no group") }
        precondition(check.isEmpty, "Generated clearing sequence leaves blocks")
        return Board(board: board, solution: solution)
    }
}

enum BlockDifficulty {
    struct Measure {
        /// Share of plays that cleared the board.
        let clearRate: Double
        /// Highest score among the plays that cleared it, 0 when none did.
        let bestScore: Int
    }

    /// Plays the board `playouts` times, each move chosen uniformly among the
    /// legal ones. A board most such plays clear is forgiving; one few clear
    /// punishes an unplanned move.
    static func measure(_ board: BlockBoard, playouts: Int, seed: UInt64) -> Measure {
        var random = AuthoringRandom(seed: seed)
        var cleared = 0, best = 0
        for _ in 0..<playouts {
            var play = board, score = 0, moves = board.moves
            while !moves.isEmpty {
                let count = play.clear(at: moves[random.pick(0...(moves.count - 1))])
                score += count * (count - 1)
                moves = play.moves
            }
            if play.isEmpty {
                cleared += 1
                best = max(best, score)
            }
        }
        return Measure(clearRate: Double(cleared) / Double(playouts), bestScore: best)
    }
}

/// The authoring plan: every level's chapter, size and seed, and either a
/// hand-written board or the difficulty band a generated board must meet.
struct LevelPlan: Codable {
    let contentVersion: Int
    /// Random plays per measured board.
    let playouts: Int
    let levels: [Entry]

    struct Entry: Codable {
        let id: String
        let chapter: Int
        let columns: Int
        let rows: Int
        /// A hand-written board, row-major from the top row. Without one, the
        /// level is generated: seeds from `seed` upward are tried in order.
        let cells: [Int]?
        let seed: UInt64
        let minimumBlocks: Int?
        /// The share of random plays that must clear a generated board, low...high.
        let clearRate: [Double]?
    }
}

struct PlannedLevel {
    let entry: LevelPlan.Entry
    let seed: UInt64
    let board: BlockBoard
    let solution: [Int]
    let measure: BlockDifficulty.Measure
}

enum LevelPlanner {
    static let seedsPerLevel: UInt64 = 1_000

    static func build(_ plan: LevelPlan) throws -> [PlannedLevel] {
        var built: [PlannedLevel] = []
        for entry in plan.levels {
            guard let chapter = BlockChapter.all.first(where: { $0.number == entry.chapter }) else {
                throw AuthoringError("\(entry.id): unknown chapter \(entry.chapter)")
            }
            if let cells = entry.cells {
                let board = BlockBoard(columns: entry.columns, rows: entry.rows, cells: cells)
                guard let solution = BlockSolver.solution(for: board) else {
                    throw AuthoringError("\(entry.id): hand-written board has no clearing sequence within the solver's limit")
                }
                built.append(PlannedLevel(entry: entry, seed: entry.seed, board: board, solution: solution,
                                          measure: BlockDifficulty.measure(board, playouts: plan.playouts, seed: entry.seed)))
                continue
            }
            guard let band = entry.clearRate, band.count == 2, let minimum = entry.minimumBlocks else {
                throw AuthoringError("\(entry.id): a generated level needs minimumBlocks and a clearRate band")
            }
            var found: PlannedLevel?
            for seed in entry.seed..<(entry.seed + seedsPerLevel) {
                guard let generated = BlockGenerator.generate(columns: entry.columns, rows: entry.rows, kinds: chapter.kinds,
                                                              minimumBlocks: minimum, seed: seed),
                      !built.contains(where: { $0.board == generated.board }) else { continue }
                let measure = BlockDifficulty.measure(generated.board, playouts: plan.playouts, seed: seed)
                if (band[0]...band[1]).contains(measure.clearRate) {
                    found = PlannedLevel(entry: entry, seed: seed, board: generated.board,
                                         solution: generated.solution, measure: measure)
                    break
                }
            }
            guard let found else {
                throw AuthoringError("\(entry.id): no seed in \(entry.seed)..<\(entry.seed + seedsPerLevel) meets the plan")
            }
            built.append(found)
        }
        return built
    }

    /// Level files in the bundled layout: one board row per line.
    static func levelJSON(_ level: PlannedLevel, contentVersion: Int, next: String?) -> String {
        let columns = level.board.columns
        let rows = (0..<level.board.rows).map { row in
            level.board.cells[(row * columns)..<((row + 1) * columns)].map(String.init).joined(separator: ", ")
        }
        return """
        {
          "schemaVersion": 1,
          "id": "\(level.entry.id)",
          "gameType": "block",
          "contentVersion": \(contentVersion),
          "seed": \(level.seed),
          "payload": {
            "chapter": \(level.entry.chapter),
            "columns": \(columns),
            "rows": \(level.board.rows),
            "cells": [\(rows.joined(separator: ",\n              "))],
            "solution": [\(level.solution.map(String.init).joined(separator: ", "))],
            "nextLevelIDs": [\(next.map { "\"\($0)\"" } ?? "")]
          }
        }

        """
    }

    static func catalogJSON(_ levels: [PlannedLevel], contentVersion: Int) -> String {
        let references = levels.map {
            "    {\"id\": \"\($0.entry.id)\", \"file\": \"Levels/\($0.entry.id).json\", \"gameType\": \"block\"}"
        }
        return """
        {
          "schemaVersion": 1,
          "titleID": "\(BlockCatalog.titleID)",
          "contentVersion": \(contentVersion),
          "levels": [
        \(references.joined(separator: ",\n"))
          ],
          "assets": [],
          "localizationKeys": []
        }

        """
    }
}

struct AuthoringError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
