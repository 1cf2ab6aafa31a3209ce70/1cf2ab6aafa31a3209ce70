import XCTest
@testable import GameCore

final class BundledContentTests: XCTestCase {
    private struct Payload: Codable, Equatable { let cells: [Int] }
    private let reference = LevelReference(id: "stable-one", file: "levels/one.json", gameType: .block)
    private func catalog(levels: [LevelReference]? = nil, assets: [String] = []) -> CatalogEnvelope {
        CatalogEnvelope(titleID: "practice", contentVersion: 2, levels: levels ?? [reference],
                        assets: assets, localizationKeys: ["level.title"])
    }
    private func level(id: String = "stable-one", version: Int = 2, type: GameType = .block,
                       keys: [String] = ["level.title"]) -> LevelEnvelope<Payload> {
        LevelEnvelope(id: id, gameType: type, contentVersion: version, seed: 42,
                      payload: Payload(cells: [0, 1]), localizationKeys: keys)
    }

    func testGenericEnvelopeRoundTripAndDeclaredReferences() throws {
        let catalog = catalog(assets: ["art/board.svg"])
        try catalog.validate(availableAssets: ["art/board.svg"])
        let encoded = try JSONEncoder().encode(level())
        let decoded = try LevelEnvelope<Payload>.decode(encoded)
        XCTAssertEqual(decoded, level())
        try decoded.validate(reference: reference, catalog: catalog)
        let maximumSeed = LevelEnvelope(id: reference.id, gameType: .block, contentVersion: 2,
                                         seed: UInt64.max, payload: Payload(cells: []))
        XCTAssertEqual(try LevelEnvelope<Payload>.decode(JSONEncoder().encode(maximumSeed)).seed, UInt64.max)
    }

    func testOptionalLocalizationAndAssetDeclarationsCanBeAbsent() throws {
        let levelJSON = Data(#"{"schemaVersion":1,"id":"stable-one","gameType":"block","contentVersion":2,"seed":42,"payload":{"cells":[0]}}"#.utf8)
        let decoded = try LevelEnvelope<Payload>.decode(levelJSON)
        XCTAssertEqual(decoded.localizationKeys, [])
        let catalogJSON = Data(#"{"schemaVersion":1,"titleID":"practice","contentVersion":2,"levels":[{"id":"stable-one","file":"levels/one.json","gameType":"block"}]}"#.utf8)
        let catalog = try CatalogEnvelope.decode(catalogJSON)
        XCTAssertEqual(catalog.assets, [])
        try catalog.validate(availableAssets: [])
        try decoded.validate(reference: reference, catalog: catalog)
    }

    func testDuplicateIDsFilesAssetsAndLocalizationKeysAreRejected() throws {
        let duplicateIDs = catalog(levels: [reference, LevelReference(id: reference.id, file: "other.json", gameType: .tile)])
        XCTAssertThrowsError(try duplicateIDs.validate(availableAssets: []))
        let duplicateFiles = catalog(levels: [reference, LevelReference(id: "another", file: reference.file, gameType: .tile)])
        XCTAssertThrowsError(try duplicateFiles.validate(availableAssets: []))
        XCTAssertThrowsError(try catalog(assets: ["one.svg", "one.svg"]).validate(availableAssets: ["one.svg"]))
        let duplicateKeys = CatalogEnvelope(titleID: "practice", contentVersion: 2, levels: [reference],
                                            localizationKeys: ["same", "same"])
        XCTAssertThrowsError(try duplicateKeys.validate(availableAssets: []))
    }

    func testMissingAssetInvalidPathsAndIdentifierAreRejected() throws {
        XCTAssertThrowsError(try catalog(assets: ["missing.svg"]).validate(availableAssets: [])) { error in
            XCTAssertTrue(error.localizedDescription.contains("missing asset 'missing.svg'"))
        }
        for path in ["../outside.json", "/absolute.json", "a//b.json", "a/./b.json", "a/../b.json",
                     "https://host/x", "a\\b.json", "", "a/", "a/%2e%2e/b"] {
            let invalid = catalog(levels: [LevelReference(id: "valid", file: path, gameType: .block)])
            XCTAssertThrowsError(try invalid.validate(availableAssets: []), path)
            XCTAssertFalse(isRelativeContentPath(path), path)
        }
        for id in ["", "..", "white space", String(repeating: "x", count: 121)] {
            // A dot-only ID is an identity ambiguity even though it isn't a path.
            let invalid = catalog(levels: [LevelReference(id: id, file: "valid.json", gameType: .block)])
            XCTAssertThrowsError(try invalid.validate(availableAssets: []), id)
        }
    }

    func testUnsupportedSchemasMalformedPayloadAndBoundedJSONFailBeforeUse() throws {
        let unknown = Data(#"{"schemaVersion":99,"futureHeader":true}"#.utf8)
        XCTAssertThrowsError(try CatalogEnvelope.decode(unknown)) { error in
            XCTAssertTrue(error.localizedDescription.contains("unsupported schema version 99"))
        }
        XCTAssertThrowsError(try LevelEnvelope<Payload>.decode(unknown))
        let malformed = Data(#"{"schemaVersion":1,"id":"stable-one","gameType":"block","contentVersion":2,"seed":42,"payload":{"cells":"invalid"}}"#.utf8)
        XCTAssertThrowsError(try LevelEnvelope<Payload>.decode(malformed))
        XCTAssertThrowsError(try CatalogEnvelope.decode(Data(repeating: 32, count: 1_048_577)))
    }

    func testLevelIdentityVersionGameTypeAndLocalizationMustMatchCatalog() throws {
        let catalog = catalog()
        for invalid in [level(id: "changed"), level(version: 1), level(type: .dig),
                        level(keys: ["missing.key"]), level(keys: ["level.title", "level.title"])] {
            XCTAssertThrowsError(try invalid.validate(reference: reference, catalog: catalog))
        }
        let unrelated = LevelReference(id: reference.id, file: "unlisted.json", gameType: .block)
        XCTAssertThrowsError(try level().validate(reference: unrelated, catalog: catalog))
    }

    func testContentUpdatePreservesUnchangedAndHistoricalProgressWithoutPositionalMapping() throws {
        let saved = SaveProgress(completedLevels: ["stable-one", "retired"],
                                 bestScores: ["stable-one": 8, "retired": 9], unlockedLevels: ["stable-one"])
        let before = saved
        let added = LevelReference(id: "new-before-one", file: "new.json", gameType: .tile)
        let updated = CatalogEnvelope(titleID: "practice", contentVersion: 3, levels: [added, reference])
        let index = ContentProgressIndex(progress: saved, catalog: updated)
        XCTAssertEqual(index.completedAvailableLevels, ["stable-one"])
        XCTAssertEqual(index.historicalCompletedLevels, ["retired"])
        XCTAssertEqual(saved, before)
        XCTAssertFalse(index.completedAvailableLevels.contains("new-before-one"))
    }
}
