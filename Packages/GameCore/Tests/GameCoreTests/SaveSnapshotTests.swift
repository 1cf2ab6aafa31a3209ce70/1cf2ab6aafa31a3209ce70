import XCTest
@testable import GameCore

final class SaveSnapshotTests: XCTestCase {
    func testRepeatedCompletionPreservesMaximaAndUniqueUnlocks() {
        var progress = SaveProgress()
        XCTAssertTrue(progress.recordCompletion(levelID: "level-1", score: 10, unlocks: ["level-2", "level-2"]))
        XCTAssertFalse(progress.recordCompletion(levelID: "level-1", score: 5, unlocks: ["level-2"]))
        XCTAssertTrue(progress.recordCompletion(levelID: "level-1", score: 20))
        XCTAssertEqual(progress.completedLevels, ["level-1"])
        XCTAssertEqual(progress.unlockedLevels, ["level-2"])
        XCTAssertEqual(progress.bestScores, ["level-1": 20])
    }

    func testV2SettingsRetainSpikeWireKeys() throws {
        let settings = ShellSettings(soundEnabled: false)
        let data = try JSONEncoder().encode(settings)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["effectsEnabled"] as? Bool, false)
        XCTAssertNil(object["soundEnabled"])
        XCTAssertEqual(try JSONDecoder().decode(ShellSettings.self, from: data), settings)
    }
}
