@testable import DevelopmentContent
import Foundation
import GameCore
import XCTest

final class DevelopmentContentTests: XCTestCase {
    private func resources() throws -> [String: Data] {
        let root = try BundledContent.resourceDirectory()
        let files = ["catalog.json", "marker.svg", "Levels/block.json", "Levels/tile.json", "Levels/unscrew.json", "Levels/dig.json"]
        return try Dictionary(uniqueKeysWithValues: files.map { ($0, try Data(contentsOf: root.appendingPathComponent($0))) })
    }
    private func load(_ files: [String: Data]) throws -> DevelopmentCatalog {
        try BundledContent.load { path in
            guard let data = files[path] else { throw ContentValidationError(message: "missing resource") }
            return data
        }
    }
    private func mutate(_ file: String, in files: inout [String: Data], _ change: (inout [String: Any]) -> Void) throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(files[file])) as? [String: Any])
        change(&object)
        files[file] = try JSONSerialization.data(withJSONObject: object)
    }
    private func rejects(_ files: [String: Data], containing expected: String) {
        XCTAssertThrowsError(try load(files)) { XCTAssertTrue($0.localizedDescription.contains(expected), $0.localizedDescription) }
    }

    func testResourceLookupSupportsFlatAndContentsBundlesWithoutContentFallback() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("content-bundle-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let files = try resources()
        func bundle(_ name: String, contents: Bool, malformed: Bool = false) throws -> (Bundle, URL) {
            let url = temporary.appendingPathComponent("\(name).bundle")
            let base = contents ? url.appendingPathComponent("Contents") : url
            let root = contents ? base.appendingPathComponent("Resources/Resources") : base.appendingPathComponent("Resources")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let info: [String: Any] = ["CFBundleIdentifier": "local.fixture.\(name)", "CFBundlePackageType": "BNDL", "CFBundleVersion": "1"]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: base.appendingPathComponent("Info.plist"))
            for (path, data) in files {
                let file = root.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: file)
            }
            if malformed {
                // A valid alternate catalog must not hide corrupt selected content.
                try files["catalog.json"]!.write(to: base.appendingPathComponent("Resources/catalog.json"))
                try Data("{\"schemaVersion\":99}".utf8).write(to: root.appendingPathComponent("catalog.json"))
            }
            return (try XCTUnwrap(Bundle(url: url)), root)
        }
        for (name, contents) in [("flat", false), ("contents", true)] {
            let (fixture, expected) = try bundle(name, contents: contents)
            let selected = try BundledContent.resourceDirectory(in: fixture)
            XCTAssertEqual(selected.standardizedFileURL.path, expected.standardizedFileURL.path)
            let catalog = try BundledContent.load { try Data(contentsOf: selected.appendingPathComponent($0)) }
            XCTAssertEqual(catalog.levels.count, 4)
        }
        let (fixture, _) = try bundle("malformed", contents: true, malformed: true)
        let selected = try BundledContent.resourceDirectory(in: fixture)
        XCTAssertThrowsError(try BundledContent.load { try Data(contentsOf: selected.appendingPathComponent($0)) }) {
            XCTAssertTrue($0.localizedDescription.contains("unsupported schema version 99"))
        }
        let empty = temporary.appendingPathComponent("empty.bundle")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        XCTAssertThrowsError(try BundledContent.resourceDirectory(in: XCTUnwrap(Bundle(url: empty)))) {
            XCTAssertTrue($0.localizedDescription.contains("catalog.json is missing"))
        }
    }

    func testInstalledSamplesHaveEveryPlannedTypeAndIdenticalSharedDecoder() throws {
        let bundled = try BundledContent.load()
        let decoded = try load(resources())
        XCTAssertEqual(bundled.envelope, decoded.envelope)
        XCTAssertEqual(bundled.levels, decoded.levels)
        XCTAssertEqual(Set(bundled.levels.map(\.gameType)), Set(GameType.allCases))
    }
    func testMissingAssetsLevelsDuplicateIDsAndUnsafePathsReject() throws {
        var files = try resources(); files.removeValue(forKey: "marker.svg"); rejects(files, containing: "marker.svg")
        files = try resources(); files.removeValue(forKey: "Levels/tile.json"); rejects(files, containing: "Levels/tile.json")
        files = try resources()
        try mutate("catalog.json", in: &files) { object in
            var levels = object["levels"] as! [[String: Any]]; levels.append(levels[0]); object["levels"] = levels
        }
        rejects(files, containing: "duplicate level ID")
        files = try resources()
        try mutate("catalog.json", in: &files) { object in object["assets"] = ["../outside.svg"] }
        rejects(files, containing: "invalid asset path")
    }
    func testUnsupportedVersionsAndIdentityMismatchRejectBeforePayload() throws {
        var files = try resources()
        files["Levels/block.json"] = Data("{\"schemaVersion\":99,\"future\":true}".utf8)
        rejects(files, containing: "unsupported schema version 99")
        files = try resources(); try mutate("Levels/block.json", in: &files) { $0["contentVersion"] = 2 }
        rejects(files, containing: "content version does not match")
        files = try resources(); try mutate("Levels/block.json", in: &files) { $0["gameType"] = "dig" }
        rejects(files, containing: "game type does not match")
        files = try resources(); try mutate("catalog.json", in: &files) { $0["titleID"] = "other-title" }
        rejects(files, containing: "expected development-practice")
    }
    func testTitleRulesAndReferencesRejectForEveryType() throws {
        let changes: [(String, ([String: Any]) -> [String: Any], String)] = [
            ("block", { var p = $0; p["occupiedCells"] = [0,0]; return p }, "unique"),
            ("tile", { var p = $0; p["tokens"] = ["a","b","c","d"]; return p }, "exactly two"),
            ("unscrew", { var p = $0; p["screws"] = [["id":"a", "panelIDs":["absent"]]]; return p }, "existing panels"),
            ("dig", { var p = $0; p["spawnCell"] = 99; return p }, "dig spawn")]
        for (type, change, message) in changes {
            var files = try resources()
            try mutate("Levels/\(type).json", in: &files) { $0["payload"] = change($0["payload"] as! [String: Any]) }
            rejects(files, containing: message)
        }
        var files = try resources()
        try mutate("Levels/block.json", in: &files) { object in
            var p = object["payload"] as! [String: Any]; p["nextLevelIDs"] = ["missing-level"]; object["payload"] = p
        }
        rejects(files, containing: "next-level reference")
        files = try resources()
        try mutate("Levels/block.json", in: &files) { $0["localizationKeys"] = ["absent.key"] }
        rejects(files, containing: "unknown localization key")
    }
    func testPureRulesReplayAllTypesAndRejectMismatchedFixture() throws {
        for level in try BundledContent.load().levels {
            let inputs: [String: [Int]] = ["block-sample-01": [1,0,4], "tile-sample-01": [0,3,1,2], "unscrew-sample-01": [0,1], "dig-sample-01": [8,4]]
            let seeds: [String: UInt64] = ["block-sample-01":100, "tile-sample-01":101, "unscrew-sample-01":102, "dig-sample-01":103]
            XCTAssertEqual(level.seed, seeds[level.id])
            let indices = try XCTUnwrap(inputs[level.id])
            let fixture = InputFixture(levelID: level.id, contentVersion: 1, seed: level.seed,
                inputs: indices.enumerated().map { TimedInput(tick: UInt64($0.offset + 1) * 10, action: FixtureAction(index: $0.element)) })
            XCTAssertEqual(FixtureRules.solutionFixture(level: level), fixture)
            let storedFixture = try JSONDecoder().decode(InputFixture<FixtureAction>.self, from: JSONEncoder().encode(fixture))
            let expected = try FixtureRules.replay(level: level, fixture: storedFixture)
            XCTAssertTrue(expected.completed, level.id)
            XCTAssertEqual(expected.removedIndices, indices.sorted())
            XCTAssertEqual(expected.finalTick, UInt64(indices.count) * 10)
            for _ in 0..<20 { XCTAssertEqual(try FixtureRules.replay(level: level, fixture: storedFixture), expected) }
            XCTAssertThrowsError(try FixtureRules.replay(level: level, fixture: InputFixture(
                levelID: level.id, contentVersion: level.contentVersion, seed: level.seed + 1, inputs: fixture.inputs)))
        }
    }
    func testUpdatedOrderAndRemovedLevelsKeepHistoricalProgress() throws {
        let catalog = try BundledContent.load().envelope
        var progress = SaveProgress()
        _ = progress.recordCompletion(levelID: "block-sample-01", score: 4, unlocks: ["tile-sample-01"])
        _ = progress.recordCompletion(levelID: "retired-level", score: 9)
        let before = progress
        let updated = CatalogEnvelope(titleID: catalog.titleID, contentVersion: 2,
            levels: Array(catalog.levels.reversed()), assets: catalog.assets)
        let index = ContentProgressIndex(progress: progress, catalog: updated)
        XCTAssertEqual(index.completedAvailableLevels, ["block-sample-01"])
        XCTAssertEqual(index.historicalCompletedLevels, ["retired-level"])
        XCTAssertEqual(progress, before)
    }
}
