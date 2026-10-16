import Foundation

public struct ContentValidationError: Error, LocalizedError, Equatable, Sendable {
    public let message: String
    public init(message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public enum GameType: String, Codable, CaseIterable, Sendable {
    case block, tile, unscrew, dig
}

public struct LevelReference: Codable, Equatable, Sendable {
    public let id: String
    public let file: String
    public let gameType: GameType
    public init(id: String, file: String, gameType: GameType) {
        self.id = id; self.file = file; self.gameType = gameType
    }
}

/// A title owns payload decoders/rules and assets; this manifest only establishes
/// stable identity, version boundaries, and explicitly declared references.
public struct CatalogEnvelope: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let titleID: String
    public let contentVersion: Int
    public let levels: [LevelReference]
    public let assets: [String]
    public let localizationKeys: [String]

    public init(schemaVersion: Int = 1, titleID: String, contentVersion: Int,
                levels: [LevelReference], assets: [String] = [], localizationKeys: [String] = []) {
        self.schemaVersion = schemaVersion; self.titleID = titleID
        self.contentVersion = contentVersion; self.levels = levels
        self.assets = assets; self.localizationKeys = localizationKeys
    }
    enum CodingKeys: String, CodingKey { case schemaVersion, titleID, contentVersion, levels, assets, localizationKeys }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        titleID = try values.decode(String.self, forKey: .titleID)
        contentVersion = try values.decode(Int.self, forKey: .contentVersion)
        levels = try values.decode([LevelReference].self, forKey: .levels)
        assets = try values.decodeIfPresent([String].self, forKey: .assets) ?? []
        localizationKeys = try values.decodeIfPresent([String].self, forKey: .localizationKeys) ?? []
    }

    public static func decode(_ data: Data) throws -> CatalogEnvelope {
        try decodeContent(data, as: Self.self)
    }

    public func validate(availableAssets: Set<String>) throws {
        try requireContent(schemaVersion == 1, "catalog: unsupported schema version \(schemaVersion)")
        try requireContent(contentVersion > 0, "catalog: contentVersion must be positive")
        try requireContent(isCanonicalTitleID(titleID), "catalog: invalid titleID '\(titleID)'")
        try requireContent(!levels.isEmpty && levels.count <= 10_000, "catalog: expected 1...10000 levels")
        var ids = Set<String>(), files = Set<String>()
        for reference in levels {
            try requireContent(isContentIdentifier(reference.id), "catalog: invalid level ID '\(reference.id)'")
            try requireContent(ids.insert(reference.id).inserted, "catalog: duplicate level ID '\(reference.id)'")
            try requireContent(isRelativeContentPath(reference.file), "catalog: invalid level file '\(reference.file)'")
            try requireContent(files.insert(reference.file).inserted, "catalog: duplicate level file '\(reference.file)'")
        }
        try validateUniqueContentIdentifiers(localizationKeys, context: "catalog localization keys")
        try requireContent(assets.count <= 10_000, "catalog: too many assets")
        var declared = Set<String>()
        for asset in assets {
            try requireContent(isRelativeContentPath(asset), "catalog: invalid asset path '\(asset)'")
            try requireContent(declared.insert(asset).inserted, "catalog: duplicate asset '\(asset)'")
            try requireContent(availableAssets.contains(asset), "catalog: missing asset '\(asset)'")
        }
    }
}

public struct LevelEnvelope<Payload: Codable>: Codable {
    public let schemaVersion: Int
    public let id: String
    public let gameType: GameType
    public let contentVersion: Int
    public let seed: UInt64
    public let payload: Payload
    public let localizationKeys: [String]

    public init(schemaVersion: Int = 1, id: String, gameType: GameType, contentVersion: Int,
                seed: UInt64, payload: Payload, localizationKeys: [String] = []) {
        self.schemaVersion = schemaVersion; self.id = id; self.gameType = gameType
        self.contentVersion = contentVersion; self.seed = seed; self.payload = payload
        self.localizationKeys = localizationKeys
    }
    enum CodingKeys: String, CodingKey { case schemaVersion, id, gameType, contentVersion, seed, payload, localizationKeys }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        id = try values.decode(String.self, forKey: .id)
        gameType = try values.decode(GameType.self, forKey: .gameType)
        contentVersion = try values.decode(Int.self, forKey: .contentVersion)
        seed = try values.decode(UInt64.self, forKey: .seed)
        payload = try values.decode(Payload.self, forKey: .payload)
        localizationKeys = try values.decodeIfPresent([String].self, forKey: .localizationKeys) ?? []
    }
    public static func decode(_ data: Data) throws -> LevelEnvelope<Payload> {
        try decodeContent(data, as: Self.self)
    }
    public func validate(reference: LevelReference, catalog: CatalogEnvelope) throws {
        try requireContent(schemaVersion == 1, "level '\(id)': unsupported schema version \(schemaVersion)")
        try requireContent(isContentIdentifier(id), "level: invalid ID '\(id)'")
        try requireContent(id == reference.id, "level '\(id)': does not match catalog ID '\(reference.id)'")
        try requireContent(gameType == reference.gameType, "level '\(id)': game type does not match catalog")
        try requireContent(contentVersion > 0 && contentVersion == catalog.contentVersion,
                           "level '\(id)': content version does not match catalog")
        try requireContent(catalog.levels.contains(reference), "level '\(id)': reference is absent from catalog")
        try validateUniqueContentIdentifiers(localizationKeys, context: "level '\(id)' localization keys")
        for key in localizationKeys {
            try requireContent(catalog.localizationKeys.contains(key), "level '\(id)': unknown localization key '\(key)'")
        }
    }
}
extension LevelEnvelope: Equatable where Payload: Equatable {}
extension LevelEnvelope: Sendable where Payload: Sendable {}

/// Paths are bundle-relative ASCII components; dot traversal, absolute paths,
/// URL schemes, backslashes and empty components never cross a loader boundary.
public func isRelativeContentPath(_ path: String) -> Bool {
    guard !path.isEmpty, path.utf8.count <= 240 else { return false }
    return path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { component in
        !component.isEmpty && component != "." && component != ".." &&
        component.utf8.allSatisfy {
            (97...122).contains($0) || (65...90).contains($0) || (48...57).contains($0) || [45, 46, 95].contains($0)
        }
    }
}
public func isContentIdentifier(_ id: String) -> Bool {
    !id.isEmpty && id != "." && id != ".." && id.utf8.count <= 120 && id.utf8.allSatisfy {
        (97...122).contains($0) || (65...90).contains($0) || (48...57).contains($0) || [45, 46, 95].contains($0)
    }
}
private func isCanonicalTitleID(_ id: String) -> Bool {
    !id.isEmpty && id.utf8.count <= 80 && id.utf8.allSatisfy {
        (97...122).contains($0) || (48...57).contains($0) || $0 == 45
    }
}
private func validateUniqueContentIdentifiers(_ ids: [String], context: String) throws {
    try requireContent(ids.count <= 10_000, "\(context): too many identifiers")
    var unique = Set<String>()
    for id in ids {
        try requireContent(isContentIdentifier(id), "\(context): invalid identifier '\(id)'")
        try requireContent(unique.insert(id).inserted, "\(context): duplicate identifier '\(id)'")
    }
}
private func requireContent(_ condition: Bool, _ message: String) throws {
    if !condition { throw ContentValidationError(message: message) }
}
private struct ContentHeader: Decodable { let schemaVersion: Int }
private func decodeContent<Value: Decodable>(_ data: Data, as type: Value.Type) throws -> Value {
    try requireContent(data.count <= 1_048_576, "content: JSON exceeds 1 MiB limit")
    do {
        let version = try JSONDecoder().decode(ContentHeader.self, from: data).schemaVersion
        try requireContent(version == 1, "content: unsupported schema version \(version)")
        return try JSONDecoder().decode(type, from: data)
    } catch let error as ContentValidationError { throw error }
      catch { throw ContentValidationError(message: "content: malformed JSON or payload (\(error))") }
}

/// Catalog order never determines saved identity. Removed IDs remain historical
/// records; titles must explicitly migrate renamed IDs instead of remapping them.
public struct ContentProgressIndex: Equatable, Sendable {
    public let completedAvailableLevels: [String]
    public let historicalCompletedLevels: [String]
    public init(progress: SaveProgress, catalog: CatalogEnvelope) {
        let available = Set(catalog.levels.map(\.id))
        completedAvailableLevels = progress.completedLevels.filter { available.contains($0) }.sorted()
        historicalCompletedLevels = progress.completedLevels.filter { !available.contains($0) }.sorted()
    }
}
