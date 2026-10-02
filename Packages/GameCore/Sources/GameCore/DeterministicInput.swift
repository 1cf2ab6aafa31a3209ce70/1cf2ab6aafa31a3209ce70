import Foundation

/// Fixed SplitMix64 integer operations, independent of Swift's randomized hash
/// and system random generator. Algorithm reference: prng.di.unimi.it/splitmix64.c
/// (Sebastiano Vigna's public-domain reference). This is not cryptographic RNG.
public struct DeterministicRNG: RandomNumberGenerator, Equatable, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var value = state
        value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
        value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
        return value ^ (value >> 31)
    }
    /// Rejection sampling avoids modulo bias. Explicit bound supplies a stable
    /// algorithm rather than Swift library distribution internals.
    public mutating func next(upperBound: UInt64) -> UInt64 {
        precondition(upperBound > 0, "Random bound must be positive")
        let threshold = (0 &- upperBound) % upperBound
        while true {
            let value = next()
            if value >= threshold { return value % upperBound }
        }
    }
}

/// Rules advance by integer ticks supplied by the title. Render frame timestamps
/// never enter this clock; paused titles simply do not advance it.
public struct GameTickClock: Equatable, Sendable {
    public private(set) var tick: UInt64
    public init(tick: UInt64 = 0) { self.tick = tick }
    public mutating func advance(by amount: UInt64 = 1) throws {
        let addition = tick.addingReportingOverflow(amount)
        guard !addition.overflow else { throw ContentValidationError(message: "clock: tick overflow") }
        tick = addition.partialValue
    }
}

public struct TimedInput<Action: Codable>: Codable {
    public let tick: UInt64
    public let action: Action
    public init(tick: UInt64, action: Action) { self.tick = tick; self.action = action }
}
extension TimedInput: Equatable where Action: Equatable {}
extension TimedInput: Sendable where Action: Sendable {}

/// Developer fixture only. Production save envelopes have no input trace field.
/// Equal-tick inputs execute in array order, which is part of fixture identity.
public struct InputFixture<Action: Codable>: Codable {
    public let schemaVersion: Int
    public let levelID: String
    public let contentVersion: Int
    public let seed: UInt64
    public let inputs: [TimedInput<Action>]
    public init(schemaVersion: Int = 1, levelID: String, contentVersion: Int, seed: UInt64,
                inputs: [TimedInput<Action>]) {
        self.schemaVersion = schemaVersion; self.levelID = levelID
        self.contentVersion = contentVersion; self.seed = seed; self.inputs = inputs
    }
    public func validate<Payload>(level: LevelEnvelope<Payload>) throws {
        guard schemaVersion == 1, levelID == level.id, contentVersion == level.contentVersion, seed == level.seed else {
            throw ContentValidationError(message: "input fixture: version, level ID, content version or seed mismatch")
        }
        guard inputs.count <= 100_000 else { throw ContentValidationError(message: "input fixture: too many inputs") }
        var previous: UInt64 = 0
        for input in inputs {
            guard input.tick >= previous else { throw ContentValidationError(message: "input fixture: ticks are out of order") }
            previous = input.tick
        }
    }
}
extension InputFixture: Equatable where Action: Equatable {}
extension InputFixture: Sendable where Action: Sendable {}
