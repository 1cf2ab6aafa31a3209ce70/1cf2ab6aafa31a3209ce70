import Foundation
import GameCore

public struct BlockPayload: Codable, Equatable {
    public let columns: Int
    public let rows: Int
    public let occupiedCells: [Int]
    public let asset: String
    public let nextLevelIDs: [String]
}
public struct TilePayload: Codable, Equatable {
    public let columns: Int
    public let rows: Int
    public let tokens: [String]
    public let asset: String
    public let nextLevelIDs: [String]
}
public struct Panel: Codable, Equatable { public let id: String }
public struct Screw: Codable, Equatable { public let id: String; public let panelIDs: [String] }
public struct UnscrewPayload: Codable, Equatable {
    public let panels: [Panel]
    public let screws: [Screw]
    public let asset: String
    public let nextLevelIDs: [String]
}
public struct DigPayload: Codable, Equatable {
    public let columns: Int
    public let rows: Int
    public let spawnCell: Int
    public let targetCells: [Int]
    public let asset: String
    public let nextLevelIDs: [String]
}

/// Original authoring fixtures, not the later production games or their solvers.
public enum DevelopmentLevel: Equatable {
    case block(LevelEnvelope<BlockPayload>)
    case tile(LevelEnvelope<TilePayload>)
    case unscrew(LevelEnvelope<UnscrewPayload>)
    case dig(LevelEnvelope<DigPayload>)

    public var id: String { switch self {
    case .block(let l): return l.id
    case .tile(let l): return l.id
    case .unscrew(let l): return l.id
    case .dig(let l): return l.id
    } }
    public var gameType: GameType { switch self {
    case .block: return .block
    case .tile: return .tile
    case .unscrew: return .unscrew
    case .dig: return .dig
    } }
    public var contentVersion: Int { switch self {
    case .block(let l): return l.contentVersion
    case .tile(let l): return l.contentVersion
    case .unscrew(let l): return l.contentVersion
    case .dig(let l): return l.contentVersion
    } }
    public var seed: UInt64 { switch self {
    case .block(let l): return l.seed
    case .tile(let l): return l.seed
    case .unscrew(let l): return l.seed
    case .dig(let l): return l.seed
    } }
}

public struct DevelopmentCatalog {
    public let envelope: CatalogEnvelope
    public let levels: [DevelopmentLevel]

    /// Both the build tool and installed app call this same decoder/validator.
    public static func decode(catalogData: Data, availableAssets: Set<String>,
                              levelData: (String) throws -> Data) throws -> DevelopmentCatalog {
        let catalog: CatalogEnvelope
        do { catalog = try CatalogEnvelope.decode(catalogData) }
        catch { throw ContentValidationError(message: "catalog.json: malformed catalog: \(error.localizedDescription)") }
        try catalog.validate(availableAssets: availableAssets)
        guard catalog.titleID == "development-practice" else {
            throw ContentValidationError(message: "catalog.json: expected development-practice title")
        }
        var decoded: [DevelopmentLevel] = []
        for reference in catalog.levels {
            do {
                let data = try levelData(reference.file)
                switch reference.gameType {
                case .block:
                    let l = try LevelEnvelope<BlockPayload>.decode(data)
                    try l.validate(reference: reference, catalog: catalog)
                    let count = try grid(l.payload.columns, l.payload.rows)
                    try cells(l.payload.occupiedCells, count: count)
                    try references(asset: l.payload.asset, next: l.payload.nextLevelIDs, catalog: catalog)
                    decoded.append(.block(l))
                case .tile:
                    let l = try LevelEnvelope<TilePayload>.decode(data)
                    try l.validate(reference: reference, catalog: catalog)
                    let count = try grid(l.payload.columns, l.payload.rows)
                    guard l.payload.tokens.count == count, !l.payload.tokens.contains(where: { $0.isEmpty || $0.count > 64 }),
                          Dictionary(grouping: l.payload.tokens, by: { $0 }).values.allSatisfy({ $0.count == 2 }) else {
                        throw ContentValidationError(message: "tile tokens must fill the grid with exactly two of each token")
                    }
                    try references(asset: l.payload.asset, next: l.payload.nextLevelIDs, catalog: catalog)
                    decoded.append(.tile(l))
                case .unscrew:
                    let l = try LevelEnvelope<UnscrewPayload>.decode(data)
                    try l.validate(reference: reference, catalog: catalog)
                    let panels = l.payload.panels.map(\.id), screws = l.payload.screws.map(\.id)
                    try uniqueIDs(panels); try uniqueIDs(screws)
                    guard panels.count <= 256, screws.count <= 256,
                          l.payload.screws.allSatisfy({ !$0.panelIDs.isEmpty && Set($0.panelIDs).count == $0.panelIDs.count && Set($0.panelIDs).isSubset(of: Set(panels)) }),
                          Set(l.payload.screws.flatMap(\.panelIDs)) == Set(panels) else {
                        throw ContentValidationError(message: "screws must reference existing panels, and every panel must have a screw")
                    }
                    try references(asset: l.payload.asset, next: l.payload.nextLevelIDs, catalog: catalog)
                    decoded.append(.unscrew(l))
                case .dig:
                    let l = try LevelEnvelope<DigPayload>.decode(data)
                    try l.validate(reference: reference, catalog: catalog)
                    let count = try grid(l.payload.columns, l.payload.rows)
                    try cells(l.payload.targetCells, count: count)
                    guard (0..<count).contains(l.payload.spawnCell), !l.payload.targetCells.contains(l.payload.spawnCell) else {
                        throw ContentValidationError(message: "dig spawn must be inside the grid and outside targets")
                    }
                    try references(asset: l.payload.asset, next: l.payload.nextLevelIDs, catalog: catalog)
                    decoded.append(.dig(l))
                }
            } catch {
                throw ContentValidationError(message: "\(reference.file) [\(reference.id)]: \(error.localizedDescription)")
            }
        }
        return DevelopmentCatalog(envelope: catalog, levels: decoded)
    }

    private static func grid(_ columns: Int, _ rows: Int) throws -> Int {
        guard (1...32).contains(columns), (1...32).contains(rows) else {
            throw ContentValidationError(message: "grid dimensions must be between 1 and 32")
        }
        return columns * rows
    }
    private static func cells(_ values: [Int], count: Int) throws {
        guard !values.isEmpty, Set(values).count == values.count, values.allSatisfy({ (0..<count).contains($0) }) else {
            throw ContentValidationError(message: "cells must be nonempty, unique and inside the grid")
        }
    }
    private static func uniqueIDs(_ values: [String]) throws {
        guard !values.isEmpty, Set(values).count == values.count,
              values.allSatisfy({ !$0.isEmpty && $0.count <= 64 && $0.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-").contains($0) }) }) else {
            throw ContentValidationError(message: "panel/screw IDs must be unique, nonempty stable identifiers")
        }
    }
    private static func references(asset: String, next: [String], catalog: CatalogEnvelope) throws {
        guard catalog.assets.contains(asset), Set(next).count == next.count,
              Set(next).isSubset(of: Set(catalog.levels.map(\.id))) else {
            throw ContentValidationError(message: "unknown asset or next-level reference")
        }
    }
}
