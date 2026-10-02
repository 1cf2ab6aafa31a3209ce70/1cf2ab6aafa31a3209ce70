import Foundation
import GameCore

public enum BundledContent {
    /// Reads only resources installed by SwiftPM in the app bundle. No save/import path.
    public static func resourceDirectory() throws -> URL {
        guard let root = Bundle.module.resourceURL?.appendingPathComponent("Resources", isDirectory: true) else {
            throw ContentValidationError(message: "Bundled content resources are missing")
        }
        return root
    }
    public static func load() throws -> DevelopmentCatalog {
        let root = try resourceDirectory()
        return try load(readResource: { path in
            try Data(contentsOf: root.appendingPathComponent(path))
        })
    }

    /// Shared entry point for package tests and the local authoring CLI.
    public static func load(readResource: (String) throws -> Data) throws -> DevelopmentCatalog {
        func bounded(_ path: String) throws -> Data {
            do {
                let data = try readResource(path)
                guard !data.isEmpty, data.count <= 4 * 1024 * 1024 else {
                    throw ContentValidationError(message: "resource must contain 1...4194304 bytes")
                }
                return data
            } catch { throw ContentValidationError(message: "\(path): \(error.localizedDescription)") }
        }
        let data = try bounded("catalog.json")
        let catalog: CatalogEnvelope
        do { catalog = try CatalogEnvelope.decode(data) }
        catch { throw ContentValidationError(message: "catalog.json: \(error.localizedDescription)") }
        // Validate relative paths and identifiers before attempting any resource read.
        try catalog.validate(availableAssets: Set(catalog.assets))
        for asset in catalog.assets { _ = try bounded(asset) }
        return try DevelopmentCatalog.decode(catalogData: data, availableAssets: Set(catalog.assets), levelData: bounded)
    }
}
