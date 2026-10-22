import GameCore
import XCTest
@testable import DigCore

final class RulesTests: XCTestCase {
    let workload = DigWorkload.default

    /// Frame-delta sequences in seconds. The jittered one is fixed by its seed and includes
    /// a hitch longer than `maxFrameDelta`.
    static let cadences: [String: [Double]] = {
        var random = DeterministicRNG(seed: 0xF00D)
        var jitter = (0..<997).map { _ in 0.004 + Double(random.next(upperBound: 46_000)) / 1_000_000 }
        jitter[100] = 0.4
        return ["8.3 ms": [0.0083], "16.7 ms": [0.0167], "33.3 ms": [0.0333], "jittered": jitter]
    }()

    /// Digest sampling interval in ticks; hashing every frame of a debug build is slow.
    static let sampleEvery: UInt64 = 10

    func testDigestsMatchAcrossFrameCadences() {
        assertCadenceIndependence(HeightfieldField.self)
        assertCadenceIndependence(VoxelField.self)
        assertCadenceIndependence(SideViewMask.self)
    }

    func testRestartRestoresInitialDigest() {
        assertRestart(HeightfieldField.self)
        assertRestart(VoxelField.self)
        assertRestart(SideViewMask.self)
    }

    func testEachCollectibleCollectedExactlyOnce() {
        assertCollection(HeightfieldField.self)
        assertCollection(VoxelField.self)
        assertCollection(SideViewMask.self)
    }

    func testDigestIsStableAcrossIndependentRuns() {
        XCTAssertEqual(replay(VoxelField.self).digest, replay(VoxelField.self).digest)
        XCTAssertNotEqual(replay(VoxelField.self).digest, VoxelRules(workload: workload).digest)
    }

    func testPauseDiscardsFrameTimeAndFrameDeltasAreClamped() {
        var rules = HeightfieldRules(workload: workload)
        rules.isPaused = true
        XCTAssertEqual(rules.advance(frameDelta: 1).ticksRun, 0)
        rules.isPaused = false
        XCTAssertEqual(rules.advance(frameDelta: 5).ticksRun, 15, "5 s clamps to 0.25 s, 15 ticks at 60 Hz")
        XCTAssertEqual(rules.advance(frameDelta: .nan).ticksRun, 0)
        XCTAssertEqual(rules.advance(frameDelta: -1).ticksRun, 0)
        // 1/60 s in two halves runs exactly one tick in total.
        let first = rules.advance(frameDelta: 1.0 / 120).ticksRun
        let second = rules.advance(frameDelta: 1.0 / 120).ticksRun
        XCTAssertEqual(first + second, 1)
    }

    func testScheduleRefusesPastFutureAndNonFiniteCommands() {
        var rules = HeightfieldRules(workload: workload)
        _ = rules.step()
        XCTAssertFalse(rules.schedule(.dig(x: 0, z: 0), at: 0))
        XCTAssertFalse(rules.schedule(.dig(x: 0, z: 0), at: rules.roundTicks))
        XCTAssertFalse(rules.schedule(.dig(x: .nan, z: 0)))
        XCTAssertFalse(rules.load(trace: [TimedInput(tick: 5, action: .digAtCursor), TimedInput(tick: 4, action: .digAtCursor)]))
        XCTAssertEqual(rules.pendingCommandCount, 0)
        XCTAssertTrue(rules.schedule(.dig(x: 9, z: -9)))
        let report = rules.step()
        XCTAssertEqual(report.revision, 1)
        XCTAssertLessThan(rules.field.surfaceHeight(x: 0.5, z: -0.5), 0, "out-of-arena dig clamps to the corner")
    }

    func testCursorMovesByBrushRadiusAndClamps() {
        var rules = SideViewRules(workload: workload)
        rules.schedule(.moveCursor(dx: 2, dz: -1))
        rules.schedule(.digAtCursor)
        _ = rules.step()
        XCTAssertEqual(rules.cursor.x, 2 * workload.brushRadius, accuracy: 1e-6)
        XCTAssertEqual(rules.cursor.y, -workload.brushRadius, accuracy: 1e-6)
        XCTAssertLessThan(rules.field.surfaceHeight(x: rules.cursor.x, z: 0), 0)
        rules.schedule(.moveCursor(dx: 1000, dz: 1000))
        _ = rules.step()
        XCTAssertEqual(rules.cursor, SIMD2(0.5, 0.5))
    }

    func testRoundEndsAtFixedTick() {
        var rules = HeightfieldRules(workload: workload)
        var ticks = 0
        while !rules.isFinished { ticks += rules.advance(frameDelta: 0.25).ticksRun }
        XCTAssertEqual(UInt64(ticks), workload.roundTicks)
        XCTAssertEqual(rules.advance(frameDelta: 0.1).ticksRun, 0)
        XCTAssertTrue(rules.step().finished)
    }

    // MARK: Helpers

    func replay<Field: ExcavationField>(_ type: Field.Type) -> DigRules<Field> {
        var rules = DigRules<Field>(workload: workload)
        XCTAssertTrue(rules.load(trace: workload.makeTrace()))
        while !rules.isFinished { _ = rules.step() }
        return rules
    }

    /// Drives the trace by frame deltas, recording the digest at every frame boundary.
    func drive<Field: ExcavationField>(_ type: Field.Type, deltas: [Double]) -> (digests: [UInt64: UInt64], final: DigRules<Field>) {
        var rules = DigRules<Field>(workload: workload)
        rules.load(trace: workload.makeTrace())
        var digests: [UInt64: UInt64] = [:]
        var frame = 0
        while !rules.isFinished {
            let ran = rules.advance(frameDelta: deltas[frame % deltas.count]).ticksRun
            if ran > 0, rules.tick % Self.sampleEvery == 0 { digests[rules.tick] = rules.digest }
            frame += 1
        }
        return (digests, rules)
    }

    func assertCadenceIndependence<Field: ExcavationField>(_ type: Field.Type, file: StaticString = #filePath, line: UInt = #line) {
        let reference = replay(type)
        var stepped: [UInt64: UInt64] = [:]
        var rules = DigRules<Field>(workload: workload)
        rules.load(trace: workload.makeTrace())
        while !rules.isFinished {
            _ = rules.step()
            if rules.tick % Self.sampleEvery == 0 { stepped[rules.tick] = rules.digest }
        }
        for (name, deltas) in Self.cadences.sorted(by: { $0.key < $1.key }) {
            let run = drive(type, deltas: deltas)
            XCTAssertEqual(run.final.digest, reference.digest, "\(Field.self) \(name) final digest", file: file, line: line)
            XCTAssertEqual(run.final.tick, workload.roundTicks, file: file, line: line)
            XCTAssertEqual(run.final.collectibles, reference.collectibles, "\(Field.self) \(name) collection ticks", file: file, line: line)
            XCTAssertGreaterThan(run.digests.count, 20, "\(name) compared too few frame boundaries", file: file, line: line)
            for (tick, digest) in run.digests {
                XCTAssertEqual(digest, stepped[tick], "\(Field.self) \(name) digest at tick \(tick)", file: file, line: line)
            }
        }
    }

    func assertRestart<Field: ExcavationField>(_ type: Field.Type, file: StaticString = #filePath, line: UInt = #line) {
        var rules = DigRules<Field>(workload: workload)
        let initial = rules.digest
        rules.load(trace: workload.makeTrace())
        for _ in 0..<3 {
            for _ in 0..<400 { _ = rules.advance(frameDelta: 1.0 / 60) }
            XCTAssertNotEqual(rules.digest, initial, file: file, line: line)
            let report = rules.restart()
            XCTAssertTrue(report.restarted, file: file, line: line)
            XCTAssertEqual(report.dirty, rules.field.allChunks, file: file, line: line)
            XCTAssertEqual(rules.digest, initial, "\(Field.self) restart digest", file: file, line: line)
            XCTAssertEqual(rules.score, 0, file: file, line: line)
            XCTAssertEqual(rules.pendingCommandCount, 0, file: file, line: line)
            XCTAssertTrue(rules.collectibles.allSatisfy { !$0.isCollected }, file: file, line: line)
            rules.load(trace: workload.makeTrace())
        }
        // A replay after restart matches a fresh replay.
        while !rules.isFinished { _ = rules.step() }
        XCTAssertEqual(rules.digest, replay(type).digest, file: file, line: line)
    }

    func assertCollection<Field: ExcavationField>(_ type: Field.Type, file: StaticString = #filePath, line: UInt = #line) {
        var rules = DigRules<Field>(workload: workload)
        rules.load(trace: workload.makeTrace())
        // Keep digging over every collectible after the trace to try to collect twice.
        for item in rules.collectibles {
            for offset in 0..<5 { rules.schedule(.dig(x: item.position.x, z: item.position.z), at: workload.roundTicks - 10 + UInt64(offset)) }
        }
        var events: [Int] = []
        while !rules.isFinished { events += rules.step().collected }
        XCTAssertEqual(events.count, Set(events).count, "\(Field.self) collected an item twice", file: file, line: line)
        XCTAssertEqual(rules.score, events.count, file: file, line: line)
        XCTAssertEqual(Set(events), Set(rules.collectibles.filter(\.isCollected).map(\.id)), file: file, line: line)
        XCTAssertEqual(events.count, workload.collectibleCount, "\(Field.self) default trace should expose every collectible",
                       file: file, line: line)
        for item in rules.collectibles {
            XCTAssertTrue(rules.field.isOpen(item.position), file: file, line: line)
        }
    }
}
