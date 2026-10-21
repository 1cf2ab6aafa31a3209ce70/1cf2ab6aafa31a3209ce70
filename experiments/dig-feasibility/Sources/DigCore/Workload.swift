import GameCore

/// The fixed arena and dig workload shared by rules, renderers and the benchmark.
/// Defaults are provisional until the research member supplies agreed budgets.
public struct DigWorkload: Sendable, Equatable {
    /// Arena width and depth in scene units.
    public var arenaSize: Float = 1
    /// Fixed simulation steps per second.
    public var tickRate: Int = 60
    /// Heightfield vertices per side, and quads per side of one geometry tile.
    public var heightfieldResolution: Int = 64
    public var heightfieldTileQuads: Int = 16
    /// Voxel counts. x and z must be equal (cubic cells) and every count a multiple of `chunkSize`.
    public var voxelX: Int = 64
    public var voxelY: Int = 32
    public var voxelZ: Int = 64
    public var chunkSize: Int = 16
    /// Side-view mask cells (square cells, `arenaSize / maskColumns` wide) and cells per tile side.
    public var maskColumns: Int = 128
    public var maskRows: Int = 96
    public var maskTileSize: Int = 16
    /// Brush radius as a fraction of the arena.
    public var brushRadiusFraction: Float = 0.06
    /// How far one dig lowers the surface under the brush centre, as a fraction of the arena.
    public var digDepthFraction: Float = 0.02
    /// Excavation never goes below this depth (fraction of the arena).
    public var maxDepthFraction: Float = 0.45
    public var digsPerSecond: Int = 10
    /// Round length; the rules stop at `durationSeconds * tickRate` ticks.
    public var durationSeconds: Int = 30
    public var collectibleCount: Int = 8
    /// Collectibles are buried between these depths (fractions of the arena, positive down).
    public var collectibleDepthRange: ClosedRange<Float> = 0.06...0.30
    /// Explicit collectible positions (IDs in array order). When set, it replaces the
    /// seeded placement and `collectibleCount`; the Spike 11 fixture uses it.
    public var collectibleLayout: [SIMD3<Float>]? = nil
    /// Seeds collectible placement and the generated trace.
    public var seed: UInt64 = 0x5D16_0011
    /// Longer frame deltas are clamped, bounding catch-up work after a hitch.
    public var maxFrameDelta: Double = 0.25

    public init() {}
    public static let `default` = DigWorkload()

    public var brushRadius: Float { brushRadiusFraction * arenaSize }
    public var digDepth: Float { digDepthFraction * arenaSize }
    public var maxDepth: Float { maxDepthFraction * arenaSize }
    public var roundTicks: UInt64 { UInt64(max(0, durationSeconds) * max(1, tickRate)) }

    /// Seeded collectible positions, reproducible from `seed`.
    public func makeCollectibles() -> [Collectible] {
        if let collectibleLayout {
            return collectibleLayout.enumerated().map { Collectible(id: $0.offset, position: $0.element) }
        }
        var random = DeterministicRNG(seed: seed)
        let span = arenaSize * 0.8
        return (0..<max(0, collectibleCount)).map { id in
            let x = (random.unit() - 0.5) * span
            let z = (random.unit() - 0.5) * span
            let depth = collectibleDepthRange.lowerBound
                + random.unit() * (collectibleDepthRange.upperBound - collectibleDepthRange.lowerBound)
            return Collectible(id: id, position: SIMD3(x, -depth * arenaSize, z))
        }
    }

    /// The default input trace: `digsPerSecond` digs for `durationSeconds`. The trace walks
    /// to each collectible in turn and then digs around it with seeded jitter of up to half
    /// a brush radius. Equal-tick inputs keep array order, as in `InputFixture`.
    public func makeTrace() -> [TimedInput<DigCommand>] {
        let total = max(0, digsPerSecond * durationSeconds)
        guard total > 0 else { return [] }
        let targets = makeCollectibles().map { SIMD2($0.position.x, $0.position.z) }
        var random = DeterministicRNG(seed: seed ^ 0x7472_6163_6500_0000)
        var previous = SIMD2<Float>(0, 0)
        var trace: [TimedInput<DigCommand>] = []
        trace.reserveCapacity(total)
        let segments = max(1, targets.count)
        for segment in 0..<segments {
            let start = segment * total / segments
            let end = (segment + 1) * total / segments
            let target = targets.isEmpty ? SIMD2<Float>(0, 0) : targets[segment]
            let travel = (end - start) / 3
            for index in start..<end {
                let local = index - start
                var point: SIMD2<Float>
                if local < travel {
                    let fraction = Float(local + 1) / Float(travel + 1)
                    point = previous + (target - previous) * fraction
                } else {
                    let jitter = brushRadius * 0.5
                    point = target + SIMD2((random.unit() * 2 - 1) * jitter, (random.unit() * 2 - 1) * jitter)
                }
                let tick = UInt64(index * max(1, tickRate) / max(1, digsPerSecond))
                trace.append(TimedInput(tick: tick, action: .dig(x: point.x, z: point.y)))
            }
            previous = target
        }
        return trace
    }
}

extension DeterministicRNG {
    /// Uniform value in [0, 1) from the top 24 bits; fixed arithmetic, no library distribution.
    mutating func unit() -> Float { Float(next() >> 40) / Float(1 << 24) }
}
