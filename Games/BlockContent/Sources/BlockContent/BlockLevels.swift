import Foundation
import GameCore

public struct BlockMatchPayload: Codable, Equatable, Sendable {
    public let columns: Int
    public let rows: Int
    /// Row-major from the top row; 0 is empty, 1...4 a block color.
    public let cells: [Int]
    public let nextLevelIDs: [String]
}

public typealias BlockLevel = LevelEnvelope<BlockMatchPayload>

/// The block title's validated catalog. The app and the authoring validator
/// both decode through `decode`, so a level that fails here never ships.
public struct BlockCatalog: Sendable {
    public static let titleID = "block-match"
    public let envelope: CatalogEnvelope
    public let levels: [BlockLevel]

    public func level(id: String) -> BlockLevel? { levels.first { $0.id == id } }

    /// The first level in catalog order that `progress` has not completed, or
    /// the last level once every level is complete.
    public func nextLevel(after progress: SaveProgress) -> BlockLevel {
        levels.first { !progress.completedLevels.contains($0.id) } ?? levels[levels.count - 1]
    }

    public static func decode(catalogData: Data, availableAssets: Set<String>,
                              levelData: (String) throws -> Data) throws -> BlockCatalog {
        let catalog: CatalogEnvelope
        do { catalog = try CatalogEnvelope.decode(catalogData) }
        catch { throw ContentValidationError(message: "catalog.json: malformed catalog: \(error.localizedDescription)") }
        try catalog.validate(availableAssets: availableAssets)
        guard catalog.titleID == titleID else {
            throw ContentValidationError(message: "catalog.json: expected \(titleID) title")
        }
        var levels: [BlockLevel] = []
        for reference in catalog.levels {
            do {
                guard reference.gameType == .block else {
                    throw ContentValidationError(message: "only block levels belong to this title")
                }
                let level = try BlockLevel.decode(try levelData(reference.file))
                try level.validate(reference: reference, catalog: catalog)
                try validate(level.payload, catalog: catalog)
                levels.append(level)
            } catch {
                throw ContentValidationError(message: "\(reference.file) [\(reference.id)]: \(error.localizedDescription)")
            }
        }
        return BlockCatalog(envelope: catalog, levels: levels)
    }

    private static func validate(_ payload: BlockMatchPayload, catalog: CatalogEnvelope) throws {
        guard (2...8).contains(payload.columns), (2...8).contains(payload.rows),
              payload.cells.count == payload.columns * payload.rows else {
            throw ContentValidationError(message: "board must be 2...8 columns by 2...8 rows with one cell each")
        }
        guard payload.cells.allSatisfy({ $0 == 0 || BlockBoard.colors.contains($0) }),
              payload.cells.filter({ $0 != 0 }).count >= 2 else {
            throw ContentValidationError(message: "cells must be 0 or a color 1...4, with at least two blocks")
        }
        for column in 0..<payload.columns {
            let stack = (0..<payload.rows).map { payload.cells[$0 * payload.columns + column] }
            let top = stack.firstIndex(where: { $0 != 0 }) ?? payload.rows
            guard stack[top...].allSatisfy({ $0 != 0 }) else {
                throw ContentValidationError(message: "blocks must rest on the floor or another block")
            }
        }
        let board = BlockBoard(columns: payload.columns, rows: payload.rows, cells: payload.cells)
        guard BlockReplay.solution(for: board) != nil else {
            throw ContentValidationError(message: "board cannot be cleared")
        }
        guard Set(payload.nextLevelIDs).count == payload.nextLevelIDs.count,
              Set(payload.nextLevelIDs).isSubset(of: Set(catalog.levels.map(\.id))) else {
            throw ContentValidationError(message: "unknown or repeated next-level reference")
        }
    }
}
