import GameCore

/// Player intent. Plane coordinates are arena x/z; the side view uses x and ignores z.
public enum DigCommand: Codable, Sendable, Equatable {
    /// Dig at the rule-field surface under this plane point (clamped to the arena).
    case dig(x: Float, z: Float)
    /// Non-precision path: move the cursor by whole brush radii, clamped to the arena.
    case moveCursor(dx: Int, dz: Int)
    /// Dig at the cursor, exactly like `dig` at the cursor's plane point.
    case digAtCursor
}

public struct Collectible: Sendable, Equatable {
    public let id: Int
    public let position: SIMD3<Float>
    /// Tick during which the rule field first became open at `position`; nil until then.
    public internal(set) var collectedTick: UInt64?
    public var isCollected: Bool { collectedTick != nil }

    public init(id: Int, position: SIMD3<Float>, collectedTick: UInt64? = nil) {
        self.id = id; self.position = position; self.collectedTick = collectedTick
    }
}

/// What changed during one `advance`, `step` or `restart` call. Feed it to `GeometrySync`.
public struct DigFrameReport: Sendable, Equatable {
    public var ticksRun = 0
    /// Union of chunks changed by the ticks run (every chunk after a restart).
    public var dirty = DirtyRegion()
    /// Field revision after the call.
    public var revision: UInt64 = 0
    /// Collectible IDs collected during the call, in collection order.
    public var collected: [Int] = []
    public var restarted = false
    public var finished = false
    public init() {}
}

/// Deterministic dig rules on a fixed step. Rules own the field, collectibles, score,
/// cursor and collection model. Render frame deltas only decide how many fixed ticks run;
/// commands execute on their stamped tick, so outcomes do not depend on frame cadence or
/// on when (or whether) geometry is rebuilt.
///
/// Collection: a collectible is collected, once, on the first tick whose dig leaves the
/// rule field open at its centre. Score is the number of collectibles collected.
public struct DigRules<Field: ExcavationField>: Sendable {
    public let workload: DigWorkload
    public private(set) var field: Field
    public private(set) var collectibles: [Collectible]
    public private(set) var score = 0
    /// Completed ticks. A command stamped `t` runs during the step from `t` to `t + 1`.
    public private(set) var tick: UInt64 = 0
    /// Increments whenever a dig changes the field; restart returns it to 0.
    public private(set) var revision: UInt64 = 0
    /// Plane point (x, z) used by `digAtCursor`.
    public private(set) var cursor = SIMD2<Float>(0, 0)
    /// While paused, `advance` discards frame time and runs no ticks.
    public var isPaused = false

    private var queue: [TimedInput<DigCommand>] = []
    private var queueHead = 0
    /// Frame time not yet consumed, in nanoseconds multiplied by `tickRate`; one tick is 1e9 units.
    private var accumulator: Int64 = 0
    private let initialField: Field
    private let initialCollectibles: [Collectible]

    public init(workload: DigWorkload = .default) {
        self.workload = workload
        initialField = Field(workload: workload)
        initialCollectibles = workload.makeCollectibles()
        field = initialField
        collectibles = initialCollectibles
    }

    public var roundTicks: UInt64 { workload.roundTicks }
    public var isFinished: Bool { tick >= roundTicks }
    public var pendingCommandCount: Int { queue.count - queueHead }

    /// Queues a command for `tick` (default: the next tick to run). Refuses past ticks,
    /// ticks at or after the round end, and non-finite coordinates.
    @discardableResult
    public mutating func schedule(_ command: DigCommand, at tick: UInt64? = nil) -> Bool {
        let target = tick ?? self.tick
        guard target >= self.tick, target < roundTicks, command.isFinite else { return false }
        if queueHead > 0, queueHead == queue.count { queue.removeAll(keepingCapacity: true); queueHead = 0 }
        var index = queue.count
        while index > queueHead, queue[index - 1].tick > target { index -= 1 }
        queue.insert(TimedInput(tick: target, action: command), at: index)
        return true
    }

    /// Queues a whole trace; returns false (and queues nothing) if any input is refused or out of order.
    @discardableResult
    public mutating func load(trace: [TimedInput<DigCommand>]) -> Bool {
        var previous = tick
        for input in trace {
            guard input.tick >= previous, input.tick < roundTicks, input.action.isFinite else { return false }
            previous = input.tick
        }
        for input in trace { schedule(input.action, at: input.tick) }
        return true
    }

    /// Accumulates a render frame delta (seconds, clamped to `0...maxFrameDelta`) and runs
    /// every whole fixed tick it completes. Time is accumulated as integer nanoseconds, so
    /// tick boundaries do not drift; a tick may fire up to 1 µs early so that deltas which
    /// sum to one frame period are not lost to nanosecond rounding.
    public mutating func advance(frameDelta seconds: Double) -> DigFrameReport {
        var report = DigFrameReport()
        report.revision = revision
        report.finished = isFinished
        guard !isPaused, !isFinished else { return report }
        let clamped = seconds.isFinite ? min(max(seconds, 0), workload.maxFrameDelta) : 0
        let rate = Int64(max(1, workload.tickRate))
        accumulator += Int64((clamped * 1e9).rounded()) * rate
        let threshold = 1_000_000_000 - 1_000 * rate
        while accumulator >= threshold, !isFinished {
            accumulator -= 1_000_000_000
            runTick(into: &report)
        }
        if isFinished { accumulator = 0 }
        report.revision = revision
        report.finished = isFinished
        return report
    }

    /// Runs exactly one tick regardless of accumulated time (headless replay and tests).
    public mutating func step() -> DigFrameReport {
        var report = DigFrameReport()
        if !isFinished { runTick(into: &report) }
        report.revision = revision
        report.finished = isFinished
        return report
    }

    /// Restores the initial rule state and clears queued commands and accumulated time.
    /// The report marks every chunk dirty and sets `restarted`.
    @discardableResult
    public mutating func restart() -> DigFrameReport {
        field = initialField
        collectibles = initialCollectibles
        score = 0
        tick = 0
        revision = 0
        cursor = SIMD2(0, 0)
        queue.removeAll()
        queueHead = 0
        accumulator = 0
        isPaused = false
        var report = DigFrameReport()
        report.dirty = field.allChunks
        report.restarted = true
        return report
    }

    /// Where a dig at this plane point would centre its sphere: the surface lowered by
    /// `digDepth`, with the sphere's bottom at that point. Resolved on the rule field.
    public func digCenter(x: Float, z: Float) -> SIMD3<Float> {
        let point = clampToArena(SIMD2(x, z))
        let surface = field.surfaceHeight(x: point.x, z: point.y)
        return SIMD3(point.x, surface - workload.digDepth + workload.brushRadius, point.y)
    }

    /// Stable digest of tick, revision, score, cursor, collectibles and field contents.
    /// Excludes pause state, queued commands and accumulated frame time.
    public var digest: UInt64 {
        var hasher = DigestHasher()
        hasher.combine(tick)
        hasher.combine(revision)
        hasher.combine(score)
        hasher.combine(cursor.x)
        hasher.combine(cursor.y)
        for item in collectibles {
            hasher.combine(item.id)
            hasher.combine(item.collectedTick ?? UInt64.max)
        }
        field.combine(into: &hasher)
        return hasher.value
    }

    private mutating func runTick(into report: inout DigFrameReport) {
        while queueHead < queue.count, queue[queueHead].tick == tick {
            apply(queue[queueHead].action, into: &report)
            queueHead += 1
        }
        tick += 1
        report.ticksRun += 1
    }

    private mutating func apply(_ command: DigCommand, into report: inout DigFrameReport) {
        switch command {
        case let .dig(x, z):
            dig(at: SIMD2(x, z), into: &report)
        case let .moveCursor(dx, dz):
            let step = workload.brushRadius
            let moved = cursor + SIMD2(Float(max(-1000, min(1000, dx))) * step, Float(max(-1000, min(1000, dz))) * step)
            cursor = clampToArena(moved)
        case .digAtCursor:
            dig(at: cursor, into: &report)
        }
    }

    private mutating func dig(at point: SIMD2<Float>, into report: inout DigFrameReport) {
        let changed = field.carve(center: digCenter(x: point.x, z: point.y), radius: workload.brushRadius)
        guard !changed.isEmpty else { return }
        revision += 1
        report.dirty.formUnion(changed)
        for index in collectibles.indices where !collectibles[index].isCollected {
            if field.isOpen(collectibles[index].position) {
                collectibles[index].collectedTick = tick
                score += 1
                report.collected.append(collectibles[index].id)
            }
        }
    }

    private func clampToArena(_ point: SIMD2<Float>) -> SIMD2<Float> {
        let half = workload.arenaSize / 2
        return SIMD2(min(max(point.x, -half), half), min(max(point.y, -half), half))
    }
}

extension DigCommand {
    var isFinite: Bool {
        if case let .dig(x, z) = self { return x.isFinite && z.isFinite }
        return true
    }
}

public typealias HeightfieldRules = DigRules<HeightfieldField>
public typealias VoxelRules = DigRules<VoxelField>
public typealias SideViewRules = DigRules<SideViewMask>
