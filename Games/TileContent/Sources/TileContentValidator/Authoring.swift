import Foundation
import GameCore
import TileContent

// Authoring-only level tools (ADR-011). They live in the validator executable,
// so the app never links them: the solver for hand-written boards, the
// reverse-construction generator, and the playout measure that sets a
// generated level's difficulty band.

enum TileSolver {
    private struct State: Hashable {
        let present: [Bool]
        let tray: [Int]
    }

    /// The first clearing sequence in board-index order, or nil when none
    /// exists or the search exceeds `stateLimit` distinct positions.
    static func solution(for board: TileBoard, stateLimit: Int = 200_000) -> [Int]? {
        var dead = Set<State>()
        func search(_ game: TileGame) -> [Int]? {
            if game.outcome == .cleared { return [] }
            guard game.outcome == .playing else { return nil }
            let state = State(present: game.board.present, tray: game.tray.map { game.board.tiles[$0].kind }.sorted())
            guard !dead.contains(state), dead.count < stateLimit else { return nil }
            for move in game.board.free {
                var next = game
                next.select(move)
                if let rest = search(next) { return [move] + rest }
            }
            dead.insert(state)
            return nil
        }
        return search(TileGame(board: board))
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
    mutating func element<T>(_ items: [T]) -> T { items[pick(0...(items.count - 1))] }
}

enum TileGenerator {
    struct Board: Equatable {
        let tiles: [TileBoard.Tile]
        let solution: [Int]
    }

    private struct Spot: Hashable {
        let layer: Int, x: Int, y: Int
        func overlaps(_ other: Spot) -> Bool { abs(x - other.x) < 2 && abs(y - other.y) < 2 }
    }

    /// Reverse construction from `seed`. Lays out a centered pyramid, layer l
    /// holding (columns − l) × (rows − l) tiles from (l, l) half cells, and
    /// thins it to `count` tiles by removing left-right mirror pairs while
    /// every tile above still rests on one below. Then it draws an order in
    /// which each tile is free when its turn comes, and gives kinds along that
    /// order so that at most `waiting` kinds have tiles in the tray at once.
    /// Taking the tiles in that order therefore never holds more than
    /// 2 × `waiting` tiles and clears the board, so every result carries its
    /// clearing sequence. Returns nil when thinning cannot reach `count`.
    static func generate(columns: Int, rows: Int, layers: Int, count: Int, kinds: Int, waiting: Int, seed: UInt64) -> Board? {
        precondition(count % 3 == 0 && count / 3 >= kinds && (1...3).contains(waiting), "Unbuildable plan entry")
        var random = AuthoringRandom(seed: seed)
        var spots = (0..<layers).flatMap { layer in
            (0..<max(0, rows - layer)).flatMap { row in
                (0..<max(0, columns - layer)).map { column in Spot(layer: layer, x: layer + 2 * column, y: layer + 2 * row) }
            }
        }
        func supported(_ set: [Spot]) -> Bool {
            set.allSatisfy { spot in spot.layer == 0 || set.contains { $0.layer == spot.layer - 1 && $0.overlaps(spot) } }
        }
        var attempts = 0
        while spots.count > count && attempts < 400 {
            attempts += 1
            let spot = random.element(spots)
            let mirror = Spot(layer: spot.layer, x: 2 * columns - 2 - spot.x, y: spot.y)
            let removal: Set<Spot> = spots.count - count >= 2 ? [spot, mirror] : [spot]
            // An odd remainder only removes a tile on the center line.
            guard removal.count == 2 || spot == mirror else { continue }
            let thinned = spots.filter { !removal.contains($0) }
            guard spots.count - thinned.count == removal.count, thinned.count >= count, supported(thinned) else { continue }
            spots = thinned
            attempts = 0
        }
        guard spots.count == count else { return nil }

        var shape = TileBoard(tiles: spots.map { TileBoard.Tile(layer: $0.layer, x: $0.x, y: $0.y, kind: 1) })
        var order: [Int] = []
        while !shape.isEmpty {
            let index = random.element(shape.free)
            shape.take(index)
            order.append(index)
        }

        // Each kind gets at least one triple; the rest go to random kinds.
        var quota = Array(repeating: 1, count: kinds + 1)
        quota[0] = 0
        for _ in 0..<(count / 3 - kinds) { quota[random.pick(1...kinds)] += 1 }
        var waitingCounts: [Int: Int] = [:], assigned = Array(repeating: 0, count: count)
        for index in order {
            let startable = (1...kinds).filter { quota[$0] > 0 && waitingCounts[$0] == nil }
            let mustStart = waitingCounts.isEmpty
            let mayStart = !startable.isEmpty && waitingCounts.count < waiting
            let kind: Int
            if mustStart || (mayStart && random.pick(0...1) == 0) {
                kind = random.element(startable)
                quota[kind] -= 1
                waitingCounts[kind] = 1
            } else {
                kind = random.element(waitingCounts.keys.sorted())
                waitingCounts[kind]! += 1
                if waitingCounts[kind] == 3 { waitingCounts[kind] = nil }
            }
            assigned[index] = kind
        }

        // Files list tiles bottom layer first, then by row and column.
        let sorted = spots.indices.sorted { (spots[$0].layer, spots[$0].y, spots[$0].x) < (spots[$1].layer, spots[$1].y, spots[$1].x) }
        var position = Array(repeating: 0, count: count)
        for (newIndex, oldIndex) in sorted.enumerated() { position[oldIndex] = newIndex }
        let tiles = sorted.map { TileBoard.Tile(layer: spots[$0].layer, x: spots[$0].x, y: spots[$0].y, kind: assigned[$0]) }
        let solution = order.map { position[$0] }
        var check = TileGame(board: TileBoard(tiles: tiles))
        for move in solution { precondition(check.select(move), "Generated move takes no tile") }
        precondition(check.outcome == .cleared, "Generated clearing sequence leaves tiles")
        return Board(tiles: tiles, solution: solution)
    }
}

enum TileDifficulty {
    struct Measure {
        /// Share of plays that cleared the board.
        let clearRate: Double
        /// Highest score among the plays that cleared it, 0 when none did.
        let bestScore: Int
    }

    /// Plays the board `playouts` times, each move chosen uniformly among the
    /// free tiles. A board most such plays clear is forgiving; one few clear
    /// punishes an unplanned move.
    static func measure(_ board: TileBoard, playouts: Int, seed: UInt64) -> Measure {
        var random = AuthoringRandom(seed: seed)
        var cleared = 0, best = 0
        for _ in 0..<playouts {
            var play = TileGame(board: board)
            while play.outcome == .playing { play.select(random.element(play.board.free)) }
            if play.outcome == .cleared {
                cleared += 1
                best = max(best, play.score)
            }
        }
        return Measure(clearRate: Double(cleared) / Double(playouts), bestScore: best)
    }
}

/// The authoring plan: every level's chapter and seed, and either a
/// hand-written board or the shape and difficulty band a generated board
/// must meet.
struct LevelPlan: Codable {
    let contentVersion: Int
    /// Random plays per measured board.
    let playouts: Int
    let levels: [Entry]

    struct Entry: Codable {
        let id: String
        let chapter: Int
        /// A hand-written board, bottom layer first. Without one, the level is
        /// generated: seeds from `seed` upward are tried in order.
        let tiles: [TileBoard.Tile]?
        let seed: UInt64
        /// The pyramid's bottom layer in tiles, its layers, and the tile count after thinning.
        let columns: Int?
        let rows: Int?
        let layers: Int?
        let count: Int?
        let kinds: Int?
        /// How many kinds the recorded clearing sequence may hold in the tray at once.
        let waiting: Int?
        /// The share of random plays that must clear a generated board, low...high.
        let clearRate: [Double]?
    }
}

struct PlannedLevel {
    let entry: LevelPlan.Entry
    let seed: UInt64
    let tiles: [TileBoard.Tile]
    let solution: [Int]
    let measure: TileDifficulty.Measure
}

enum LevelPlanner {
    static let seedsPerLevel: UInt64 = 1_000

    static func build(_ plan: LevelPlan) throws -> [PlannedLevel] {
        var built: [PlannedLevel] = []
        for entry in plan.levels {
            if let tiles = entry.tiles {
                guard let solution = TileSolver.solution(for: TileBoard(tiles: tiles)) else {
                    throw AuthoringError("\(entry.id): hand-written board has no clearing sequence within the solver's limit")
                }
                built.append(PlannedLevel(entry: entry, seed: entry.seed, tiles: tiles, solution: solution,
                                          measure: TileDifficulty.measure(TileBoard(tiles: tiles), playouts: plan.playouts, seed: entry.seed)))
                continue
            }
            guard let columns = entry.columns, let rows = entry.rows, let layers = entry.layers, let count = entry.count,
                  let kinds = entry.kinds, let waiting = entry.waiting, let band = entry.clearRate, band.count == 2 else {
                throw AuthoringError("\(entry.id): a generated level needs columns, rows, layers, count, kinds, waiting and a clearRate band")
            }
            var found: PlannedLevel?
            for seed in entry.seed..<(entry.seed + seedsPerLevel) {
                guard let generated = TileGenerator.generate(columns: columns, rows: rows, layers: layers, count: count,
                                                             kinds: kinds, waiting: waiting, seed: seed),
                      !built.contains(where: { $0.tiles == generated.tiles }) else { continue }
                let measure = TileDifficulty.measure(TileBoard(tiles: generated.tiles), playouts: plan.playouts, seed: seed)
                if (band[0]...band[1]).contains(measure.clearRate) {
                    found = PlannedLevel(entry: entry, seed: seed, tiles: generated.tiles,
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

    /// Level files in the bundled layout: one tile per line.
    static func levelJSON(_ level: PlannedLevel, contentVersion: Int, next: String?) -> String {
        let tiles = level.tiles.map { "[\($0.layer), \($0.x), \($0.y), \($0.kind)]" }
        return """
        {
          "schemaVersion": 1,
          "id": "\(level.entry.id)",
          "gameType": "tile",
          "contentVersion": \(contentVersion),
          "seed": \(level.seed),
          "payload": {
            "chapter": \(level.entry.chapter),
            "tiles": [\(tiles.joined(separator: ",\n              "))],
            "solution": [\(level.solution.map(String.init).joined(separator: ", "))],
            "nextLevelIDs": [\(next.map { "\"\($0)\"" } ?? "")]
          }
        }

        """
    }

    static func catalogJSON(_ levels: [PlannedLevel], contentVersion: Int) -> String {
        let references = levels.map {
            "    {\"id\": \"\($0.entry.id)\", \"file\": \"Levels/\($0.entry.id).json\", \"gameType\": \"tile\"}"
        }
        return """
        {
          "schemaVersion": 1,
          "titleID": "\(TileCatalog.titleID)",
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
