import Foundation
import GameCore

/// This title's level payload. Replace it with the title's own schema and
/// validate every field in `validate(_:catalog:)`.
public struct __CONTENT__Payload: Codable, Equatable, Sendable {
    /// Selections needed to complete the level.
    public let steps: Int
    public let nextLevelIDs: [String]
}

public typealias __CONTENT__Level = LevelEnvelope<__CONTENT__Payload>

/// The validated catalog. The app and the authoring validator both decode
/// through `decode`, so a level that fails here never ships.
public struct __CONTENT__Catalog: Sendable {
    public static let titleID = "__TITLE_ID__"
    public let envelope: CatalogEnvelope
    public let levels: [__CONTENT__Level]

    /// The first level in catalog order that `progress` has not completed, or
    /// the last level once every level is complete.
    public func nextLevel(after progress: SaveProgress) -> __CONTENT__Level {
        levels.first { !progress.completedLevels.contains($0.id) } ?? levels[levels.count - 1]
    }

    public static func decode(catalogData: Data, availableAssets: Set<String>,
                              levelData: (String) throws -> Data) throws -> __CONTENT__Catalog {
        let catalog: CatalogEnvelope
        do { catalog = try CatalogEnvelope.decode(catalogData) }
        catch { throw ContentValidationError(message: "catalog.json: malformed catalog: \(error.localizedDescription)") }
        try catalog.validate(availableAssets: availableAssets)
        guard catalog.titleID == titleID else {
            throw ContentValidationError(message: "catalog.json: expected \(titleID) title")
        }
        var levels: [__CONTENT__Level] = []
        for reference in catalog.levels {
            do {
                guard reference.gameType == .__GAME_TYPE__ else {
                    throw ContentValidationError(message: "only __GAME_TYPE__ levels belong to this title")
                }
                let level = try __CONTENT__Level.decode(try levelData(reference.file))
                try level.validate(reference: reference, catalog: catalog)
                try validate(level.payload, catalog: catalog)
                levels.append(level)
            } catch {
                throw ContentValidationError(message: "\(reference.file) [\(reference.id)]: \(error.localizedDescription)")
            }
        }
        return __CONTENT__Catalog(envelope: catalog, levels: levels)
    }

    private static func validate(_ payload: __CONTENT__Payload, catalog: CatalogEnvelope) throws {
        guard (1...10).contains(payload.steps) else {
            throw ContentValidationError(message: "steps must be 1...10")
        }
        guard Set(payload.nextLevelIDs).count == payload.nextLevelIDs.count,
              Set(payload.nextLevelIDs).isSubset(of: Set(catalog.levels.map(\.id))) else {
            throw ContentValidationError(message: "unknown or repeated next-level reference")
        }
    }
}
