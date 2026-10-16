import Foundation
import GameCore

/// Developer-only replay action: select a cell or a screw index in a tiny fixture.
public struct FixtureAction: Codable, Equatable {
    public let index: Int
    public init(index: Int) { self.index = index }
}
public struct FixtureOutcome: Equatable {
    public let removedIndices: [Int]
    public let completed: Bool
    public let finalTick: UInt64
}

/// Minimal title-owned rules prove input/seed reproducibility. No renderer, wall
/// clock, physics, production trace storage, or later game mechanics enter here.
public enum FixtureRules {
    public static func replay(level: DevelopmentLevel, fixture: InputFixture<FixtureAction>) throws -> FixtureOutcome {
        switch level {
        case .block(let l): try fixture.validate(level: l)
        case .tile(let l): try fixture.validate(level: l)
        case .unscrew(let l): try fixture.validate(level: l)
        case .dig(let l): try fixture.validate(level: l)
        }
        var clock = GameTickClock(), removed = Set<Int>(), pending: Int?
        let order = solutionIndices(level: level)
        for input in fixture.inputs {
            try clock.advance(by: input.tick - clock.tick)
            let index = input.action.index
            switch level {
            case .block, .dig:
                // A seed determines the original fixture's target order.
                if removed.count < order.count, index == order[removed.count] { removed.insert(index) }
            case .unscrew(let l):
                if l.payload.screws.indices.contains(index) { removed.insert(index) }
            case .tile(let l):
                guard l.payload.tokens.indices.contains(index), !removed.contains(index) else { continue }
                if let first = pending {
                    if first != index && l.payload.tokens[first] == l.payload.tokens[index] {
                        removed.insert(first); removed.insert(index)
                    }
                    pending = nil
                } else { pending = index }
            }
        }
        return FixtureOutcome(removedIndices: removed.sorted(), completed: removed.count == order.count, finalTick: clock.tick)
    }

    /// Test helpers create input fixtures; shipped samples contain no input traces.
    public static func solutionFixture(level: DevelopmentLevel) -> InputFixture<FixtureAction> {
        InputFixture(levelID: level.id, contentVersion: level.contentVersion, seed: level.seed,
                     inputs: solutionIndices(level: level).enumerated().map {
            TimedInput(tick: UInt64($0.offset + 1) * 10, action: FixtureAction(index: $0.element))
        })
    }
    private static func solutionIndices(level: DevelopmentLevel) -> [Int] {
        var values: [Int]
        switch level {
        case .block(let l): values = l.payload.occupiedCells
        case .dig(let l): values = l.payload.targetCells
        case .unscrew(let l): return Array(l.payload.screws.indices)
        case .tile(let l):
            return Dictionary(grouping: l.payload.tokens.indices, by: { l.payload.tokens[$0] })
                .keys.sorted().flatMap { token in l.payload.tokens.indices.filter { l.payload.tokens[$0] == token } }
        }
        var rng = DeterministicRNG(seed: level.seed)
        if values.count > 1 {
            for index in stride(from: values.count - 1, through: 1, by: -1) {
                values.swapAt(index, Int(rng.next(upperBound: UInt64(index + 1))))
            }
        }
        return values
    }
}
