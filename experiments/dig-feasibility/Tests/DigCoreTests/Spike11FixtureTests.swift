import DigCore
import XCTest

/// The pure fixture check each candidate must pass before any timing run.
final class Spike11FixtureTests: XCTestCase {
    func testTraceShape() {
        XCTAssertEqual(Spike11Fixture.traceS.count, 600)
        XCTAssertEqual(Spike11Fixture.traceB.count, 300)
        XCTAssertEqual(Spike11Fixture.items.count, 36)
        let field = HeightfieldField(workload: Spike11Fixture.workload)
        XCTAssertEqual(field.chunkCount, 16)
        XCTAssertEqual(field.geometry(chunk: 0).vertexCount, 169)
        XCTAssertEqual(VoxelField(workload: Spike11Fixture.workload).chunkCount, 9)
    }

    func testHeightfieldScoresAndControls() {
        assertExpectedScores(HeightfieldRules.self)
    }

    /// Measured deviation, kept explicit: the voxel sphere carve undercuts sideways below
    /// the visible trench and opens two control items (x = 40; z = 8 and 40), so the voxel
    /// candidate scores 26 after S and 30 after B and fails the fixture's correctness row.
    func testVoxelUndercutOpensTwoControls() {
        var rules = VoxelRules(workload: Spike11Fixture.workload)
        Spike11Fixture.replay(Spike11Fixture.traceS, into: &rules, perTick: 1)
        XCTAssertEqual(Set(rules.collectibles.filter(\.isCollected).map(\.id)),
                       Spike11Fixture.expectedCollectedAfterS.union([32, 35]))
        Spike11Fixture.replay(Spike11Fixture.traceB, into: &rules, perTick: 1)
        XCTAssertEqual(rules.score, 30)
        XCTAssertEqual(Set(rules.collectibles.filter(\.isCollected).map(\.id)),
                       Spike11Fixture.expectedCollectedAfterB.union([32, 35]))
        // The control columns' surfaces are untouched: the opening is an undercut.
        for id in [32, 35] {
            let item = rules.collectibles[id].position
            XCTAssertEqual(rules.field.surfaceHeight(x: item.x, z: item.z), 0, accuracy: 1e-6)
        }
    }

    /// Batching 1, 2 or 6 commands per tick gives the same field, score and collected set.
    func testBatchingCadence() {
        for type in [0, 1] {
            var digests: Set<UInt64> = []
            for perTick in [1, 2, 6] {
                if type == 0 {
                    var rules = HeightfieldRules(workload: Spike11Fixture.workload)
                    Spike11Fixture.replay(Spike11Fixture.traceS + Spike11Fixture.traceB, into: &rules, perTick: perTick)
                    digests.insert(Spike11Fixture.outcomeDigest(rules))
                } else {
                    var rules = VoxelRules(workload: Spike11Fixture.workload)
                    Spike11Fixture.replay(Spike11Fixture.traceS + Spike11Fixture.traceB, into: &rules, perTick: perTick)
                    digests.insert(Spike11Fixture.outcomeDigest(rules))
                }
            }
            XCTAssertEqual(digests.count, 1, "field \(type)")
        }
    }

    /// The heightfield dirty set per command stays within 2 x 2 chunks.
    func testHeightfieldDirtySetBound() {
        var rules = HeightfieldRules(workload: Spike11Fixture.workload)
        var largest = 0
        for command in Spike11Fixture.traceS + Spike11Fixture.traceB {
            rules.schedule(command)
            largest = max(largest, rules.step().dirty.chunks.count)
        }
        XCTAssertLessThanOrEqual(largest, 4)
    }

    private func assertExpectedScores<Field: ExcavationField>(_ type: DigRules<Field>.Type,
                                                              file: StaticString = #filePath, line: UInt = #line) {
        var rules = DigRules<Field>(workload: Spike11Fixture.workload)
        Spike11Fixture.replay(Spike11Fixture.traceS, into: &rules, perTick: 1)
        let afterS = Set(rules.collectibles.filter(\.isCollected).map(\.id))
        XCTAssertEqual(rules.score, Spike11Fixture.expectedAfterS, "after S: \(afterS.sorted())", file: file, line: line)
        XCTAssertEqual(afterS, Spike11Fixture.expectedCollectedAfterS, file: file, line: line)
        Spike11Fixture.replay(Spike11Fixture.traceB, into: &rules, perTick: 1)
        let afterB = Set(rules.collectibles.filter(\.isCollected).map(\.id))
        XCTAssertEqual(rules.score, Spike11Fixture.expectedAfterB, "after B: \(afterB.sorted())", file: file, line: line)
        XCTAssertEqual(afterB, Spike11Fixture.expectedCollectedAfterB, file: file, line: line)
        XCTAssertTrue(afterB.isDisjoint(with: Spike11Fixture.controlIDs), file: file, line: line)
    }
}
