@testable import TileContent
import Foundation
import GameCore
import XCTest

final class TileContentTests: XCTestCase {
    private func resources() throws -> [String: Data] {
        let root = try BundledContent.resourceDirectory()
        let files = ["catalog.json", "Levels/level-01.json"]
        return try Dictionary(uniqueKeysWithValues: files.map { ($0, try Data(contentsOf: root.appendingPathComponent($0))) })
    }
    private func load(_ files: [String: Data]) throws -> TileContentCatalog {
        try BundledContent.load { path in
            guard let data = files[path] else { throw ContentValidationError(message: "missing resource") }
            return data
        }
    }

    func testBundledCatalogDecodesForThisTitleOnly() throws {
        let catalog = try BundledContent.load()
        XCTAssertEqual(catalog.envelope.titleID, "tile-match")
        XCTAssertEqual(catalog.levels.map(\.id), ["level-01"])
        var files = try resources()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(files["catalog.json"])) as? [String: Any])
        object["titleID"] = "another-title"
        files["catalog.json"] = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try load(files))
    }

    func testValidationRejectsOutOfRangeSteps() throws {
        var files = try resources()
        var level = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(files["Levels/level-01.json"])) as? [String: Any])
        var payload = try XCTUnwrap(level["payload"] as? [String: Any])
        payload["steps"] = 0
        level["payload"] = payload
        files["Levels/level-01.json"] = try JSONSerialization.data(withJSONObject: level)
        XCTAssertThrowsError(try load(files)) { XCTAssertTrue($0.localizedDescription.contains("steps"), $0.localizedDescription) }
    }

    func testNextLevelFollowsSavedProgress() throws {
        let catalog = try BundledContent.load()
        XCTAssertEqual(catalog.nextLevel(after: SaveProgress()).id, "level-01")
        XCTAssertEqual(catalog.nextLevel(after: SaveProgress(completedLevels: ["level-01"])).id, "level-01")
    }
}
