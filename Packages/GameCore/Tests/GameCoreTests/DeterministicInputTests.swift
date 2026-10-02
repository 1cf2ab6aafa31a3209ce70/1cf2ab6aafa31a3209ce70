import XCTest
@testable import GameCore

final class DeterministicInputTests: XCTestCase {
    private enum Action: String, Codable { case collect, wait }
    private struct Payload: Codable { let target: Int }
    private let level = LevelEnvelope(id: "replay-one", gameType: .block, contentVersion: 1,
                                      seed: 0, payload: Payload(target: 100))

    func testSplitMix64KnownVectorAndStableBoundedDistribution() {
        var random = DeterministicRNG(seed: 0)
        // Fixed vector from the public-domain reference's UInt64 arithmetic.
        let expected: [UInt64] = [0xe220a8397b1dcdaf, 0x6e789e6aa1b965f4, 0x06c45d188009454f,
                                  0xf88bb8a8724c81ec, 0x1b39896a51a8749b, 0x53cb9f0c747ea2ea]
        XCTAssertEqual(expected.map { _ in random.next() }, expected)
        var bounded = DeterministicRNG(seed: 0)
        XCTAssertEqual((0..<6).map { _ in bounded.next(upperBound: 100) }, [35, 0, 79, 44, 47, 90])
        XCTAssertEqual(bounded.next(upperBound: 1), 0)
        // This bound rejects several intervening reference outputs. The fixed
        // sequence was independently checked by a C reference/rejection harness.
        var rejection = DeterministicRNG(seed: 0)
        let largeBound: UInt64 = 0x8000000000000001
        let rejectionExpected: [UInt64] = [0x6220a8397b1dcdae, 0x788bb8a8724c81eb,
                                          0x4584133ac916ab3b, 0x73b8488c368cb0a5,
                                          0x42d326e0055bdef5, 0x0621a03fe0bbdb7a]
        XCTAssertEqual(rejectionExpected.map { _ in rejection.next(upperBound: largeBound) }, rejectionExpected)
    }

    func testClockOverflowIsExplicitAndPauseDoesNotAdvanceRules() throws {
        var clock = GameTickClock()
        try clock.advance(by: 7)
        XCTAssertEqual(clock.tick, 7)
        try clock.advance(by: 0)
        XCTAssertEqual(clock.tick, 7)
        var end = GameTickClock(tick: .max)
        XCTAssertThrowsError(try end.advance())
        XCTAssertEqual(end.tick, .max)
    }

    func testInputFixtureChecksVersionMetadataAndTickOrder() throws {
        let valid = InputFixture(levelID: level.id, contentVersion: 1, seed: 0,
                                 inputs: [TimedInput(tick: 1, action: Action.collect), TimedInput(tick: 1, action: .wait)])
        try valid.validate(level: level)
        let decoded = try JSONDecoder().decode(InputFixture<Action>.self, from: JSONEncoder().encode(valid))
        XCTAssertEqual(decoded, valid)
        for invalid in [InputFixture(schemaVersion: 2, levelID: level.id, contentVersion: 1, seed: 0, inputs: valid.inputs),
                        InputFixture(levelID: "other", contentVersion: 1, seed: 0, inputs: valid.inputs),
                        InputFixture(levelID: level.id, contentVersion: 2, seed: 0, inputs: valid.inputs),
                        InputFixture(levelID: level.id, contentVersion: 1, seed: 9, inputs: valid.inputs),
                        InputFixture(levelID: level.id, contentVersion: 1, seed: 0, inputs: [TimedInput(tick: 2, action: Action.wait), TimedInput(tick: 1, action: .collect)])] {
            XCTAssertThrowsError(try invalid.validate(level: level))
        }
    }

    func testTinyFixtureRulesRepeatKnownOutcomeRegardlessOfRenderFrameCount() throws {
        let fixture = InputFixture(levelID: level.id, contentVersion: 1, seed: 0,
                                   inputs: [TimedInput(tick: 1, action: Action.collect),
                                            TimedInput(tick: 3, action: .wait), TimedInput(tick: 3, action: .collect)])
        func replay(renderFramesPerTick: Int) throws -> (score: UInt64, tick: UInt64) {
            try fixture.validate(level: level)
            var random = DeterministicRNG(seed: fixture.seed)
            var clock = GameTickClock()
            var score: UInt64 = 0
            for input in fixture.inputs {
                try clock.advance(by: input.tick - clock.tick)
                // Presentation can redraw many times without supplying rule time.
                for _ in 0..<renderFramesPerTick { XCTAssertEqual(clock.tick, input.tick) }
                if input.action == .collect { score += random.next(upperBound: 100) }
            }
            return (score, clock.tick)
        }
        let first = try replay(renderFramesPerTick: 1)
        let repeated = try replay(renderFramesPerTick: 4)
        XCTAssertEqual(first.score, 35)
        XCTAssertEqual(first.tick, 3)
        XCTAssertEqual(first.score, repeated.score)
        XCTAssertEqual(first.tick, repeated.tick)
    }
}
