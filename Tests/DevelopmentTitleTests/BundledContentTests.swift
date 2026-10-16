import DevelopmentContent
import Foundation
import GameCore
import GamePlatform
import XCTest
@testable import DevelopmentTitle

@MainActor
final class BundledContentTests: XCTestCase {
    func testInstalledOfflineBundleEnumeratesLoadsAndReplaysEveryPlannedType() throws {
        let catalog = try BundledContent.load()
        XCTAssertEqual(catalog.envelope.titleID, "development-practice")
        XCTAssertEqual(Set(catalog.levels.map(\.gameType)), Set(GameType.allCases))
        XCTAssertEqual(catalog.levels.count, 4)
        let notice = try Data(contentsOf: BundledContent.resourceDirectory().appendingPathComponent("SplitMix64-NOTICE.txt"))
        XCTAssertFalse(notice.isEmpty)
        // These fixed fixtures and expected outputs also run in the host package.
        let inputs: [String: [Int]] = ["block-sample-01": [1,0,4], "tile-sample-01": [0,3,1,2], "unscrew-sample-01": [0,1], "dig-sample-01": [8,4]]
        let seeds: [String: UInt64] = ["block-sample-01":100, "tile-sample-01":101, "unscrew-sample-01":102, "dig-sample-01":103]
        for level in catalog.levels {
            let indices = try XCTUnwrap(inputs[level.id])
            XCTAssertEqual(level.seed, seeds[level.id])
            let fixture = InputFixture(levelID: level.id, contentVersion: 1, seed: level.seed,
                inputs: indices.enumerated().map { TimedInput(tick: UInt64($0.offset + 1) * 10, action: FixtureAction(index: $0.element)) })
            XCTAssertEqual(FixtureRules.solutionFixture(level: level), fixture)
            for _ in 0..<20 {
                let outcome = try FixtureRules.replay(level: level, fixture: fixture)
                XCTAssertTrue(outcome.completed)
                XCTAssertEqual(outcome.removedIndices, indices.sorted())
                XCTAssertEqual(outcome.finalTick, UInt64(indices.count) * 10)
            }
        }
        var rng = DeterministicRNG(seed: 0)
        XCTAssertEqual((0..<6).map { _ in rng.next(upperBound: 100) }, [35,0,79,44,47,90])
    }

    func testUpdatedBundleKeepsPersistedStableIDsScoresUnlocksAndHistory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("content-update-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LocalSaveStore(titleID: "development-practice", root: root)
        let first = try await store.load()
        var progress = first.snapshot.progress
        _ = progress.recordCompletion(levelID: "block-sample-01", score: 7, unlocks: ["tile-sample-01"])
        _ = progress.recordCompletion(levelID: "retired-level", score: 3)
        _ = try await store.save(settings: first.snapshot.settings, progress: progress, generation: first.generation)
        let catalog = try BundledContent.load().envelope
        let updated = CatalogEnvelope(titleID: catalog.titleID, contentVersion: 2,
            levels: Array(catalog.levels.reversed().filter { $0.id != "tile-sample-01" }), assets: catalog.assets)
        let restored = try await LocalSaveStore(titleID: "development-practice", root: root).load()
        let index = ContentProgressIndex(progress: restored.snapshot.progress, catalog: updated)
        XCTAssertEqual(index.completedAvailableLevels, ["block-sample-01"])
        XCTAssertEqual(index.historicalCompletedLevels, ["retired-level"])
        XCTAssertEqual(restored.snapshot.progress, progress)
        XCTAssertEqual(restored.snapshot.progress.bestScores["block-sample-01"], 7)
        XCTAssertEqual(restored.snapshot.progress.unlockedLevels, ["tile-sample-01"])
    }
}
