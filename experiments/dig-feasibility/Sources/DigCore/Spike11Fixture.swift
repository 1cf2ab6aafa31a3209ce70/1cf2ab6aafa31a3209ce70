import GameCore

/// The agreed Spike 11 workload: a 1.6 su arena on a 48 x 48 cell grid, a 0.12 su brush
/// that lowers the centre by 0.02 su, a 0.45 su depth clamp, 36 rule-owned collectibles
/// and the fixed S (sustained) and B (burst) command traces. Developer fixture only.
///
/// Grid coordinates are vertex units of 1.6 / 48 su measured from the arena's -x/-z edge,
/// so cell 12, 24 and 36 lie on heightfield tile (chunk) boundaries.
public enum Spike11Fixture {
    public static let cells = 48
    public static let arenaSize: Float = 1.6
    public static var cellSize: Float { arenaSize / Float(cells) }
    /// A collectible is collected when the rule field is open 0.099 su below the ground,
    /// i.e. the excavation there has reached 0.10 su (to within 0.001 su).
    public static let collectibleDepth: Float = 0.099
    public static let expectedAfterS = 24
    public static let expectedAfterB = 28
    public static let sRate = 10
    public static let bRate = 30
    /// Rows dug by S, in order (serpentine), in grid units.
    public static let sRows: [Float] = [4, 12, 20, 28, 36, 44]

    public enum Kind: String, Sendable { case trench, ridge, control }

    public struct Item: Sendable, Equatable {
        public let id: Int
        public let kind: Kind
        public let cellX: Float
        public let cellZ: Float
    }

    /// IDs 0-23 trench centrelines, 24-27 ridges under the burst column, 28-35 controls.
    public static let items: [Item] = {
        var result: [Item] = []
        for z in sRows { for x: Float in [10, 18, 30, 38] { result.append(Item(id: result.count, kind: .trench, cellX: x, cellZ: z)) } }
        for z: Float in [8, 16, 32, 40] { result.append(Item(id: result.count, kind: .ridge, cellX: 24, cellZ: z)) }
        for x: Float in [8, 40] { for z: Float in [8, 16, 32, 40] { result.append(Item(id: result.count, kind: .control, cellX: x, cellZ: z)) } }
        return result
    }()

    public static var controlIDs: Set<Int> { Set(items.filter { $0.kind == .control }.map(\.id)) }
    public static var expectedCollectedAfterS: Set<Int> { Set(items.filter { $0.kind == .trench }.map(\.id)) }
    public static var expectedCollectedAfterB: Set<Int> { Set(items.filter { $0.kind != .control }.map(\.id)) }

    /// Arena plane point (x, z) for grid coordinates.
    public static func point(cellX: Float, cellZ: Float) -> SIMD2<Float> {
        SIMD2(cellX * cellSize - arenaSize / 2, cellZ * cellSize - arenaSize / 2)
    }

    /// The fixture workload. The round is long enough that no run reaches its end.
    public static var workload: DigWorkload {
        var workload = DigWorkload()
        workload.arenaSize = arenaSize
        workload.heightfieldResolution = cells + 1
        workload.heightfieldTileQuads = 12
        workload.voxelX = cells
        workload.voxelZ = cells
        workload.voxelY = 16
        workload.chunkSize = 16
        workload.brushRadiusFraction = 0.12 / arenaSize
        workload.digDepthFraction = 0.02 / arenaSize
        workload.maxDepthFraction = 0.45 / arenaSize
        workload.durationSeconds = 3_600
        workload.digsPerSecond = sRate
        workload.collectibleLayout = items.map {
            let plane = point(cellX: $0.cellX, cellZ: $0.cellZ)
            return SIMD3(plane.x, -collectibleDepth, plane.y)
        }
        return workload
    }

    /// One row of 100 stamps from x = 4.0 to 43.6 in steps of 0.4 grid units.
    static func row(z: Float, reversed: Bool) -> [DigCommand] {
        let xs = (0..<100).map { 4 + Float($0) * 0.4 }
        return (reversed ? xs.reversed() : xs).map { x in
            let plane = point(cellX: x, cellZ: z)
            return .dig(x: plane.x, z: plane.y)
        }
    }

    /// S: 600 commands, six serpentine rows, issued at 10 commands per second.
    public static let traceS: [DigCommand] = sRows.enumerated().flatMap { row(z: $0.element, reversed: $0.offset % 2 == 1) }

    /// B: 300 commands, rows 20 and 28 again then a column at x = 24, issued at 30 per second.
    public static let traceB: [DigCommand] = row(z: 20, reversed: false) + row(z: 28, reversed: true)
        + (0..<100).map { index in
            let plane = point(cellX: 24, cellZ: 4 + Float(index) * 0.4)
            return DigCommand.dig(x: plane.x, z: plane.y)
        }

    /// Rule-state hash that ignores tick stamps: field contents, score and the collected
    /// set. Equal across command batching and frame cadence when the command order is equal.
    public static func outcomeDigest<Field: ExcavationField>(_ rules: DigRules<Field>) -> UInt64 {
        var hasher = DigestHasher()
        hasher.combine(rules.revision)
        hasher.combine(rules.score)
        for item in rules.collectibles where item.isCollected { hasher.combine(item.id) }
        rules.field.combine(into: &hasher)
        return hasher.value
    }

    /// Replays commands with `perTick` commands on each tick and returns the rules.
    public static func replay<Field: ExcavationField>(_ commands: [DigCommand], into rules: inout DigRules<Field>, perTick: Int) {
        var index = 0
        while index < commands.count {
            for command in commands[index..<min(commands.count, index + max(1, perTick))] {
                rules.schedule(command)
            }
            index += max(1, perTick)
            _ = rules.step()
        }
    }
}
