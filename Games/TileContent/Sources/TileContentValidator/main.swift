import TileContent
import Foundation

let usage = """
usage: TileContentValidator [content-directory]
       TileContentValidator generate <level-plan.json> <content-directory>
An omitted directory validates the bundled levels. generate writes the plan's
level files and catalog into the directory, then validates it.
"""

@discardableResult
func validate(_ root: URL) throws -> TileCatalog {
    let catalog = try BundledContent.load { relative in
        let file = root.appendingPathComponent(relative).standardizedFileURL.resolvingSymlinksInPath()
        guard file.path.hasPrefix(root.path + "/") else {
            throw NSError(domain: "ContentValidator", code: 1, userInfo: [NSLocalizedDescriptionKey: "resource escapes the selected content directory"])
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, size.intValue <= 4 * 1024 * 1024 else {
            throw NSError(domain: "ContentValidator", code: 2, userInfo: [NSLocalizedDescriptionKey: "resource must be a regular file of at most 4 MiB"])
        }
        return try Data(contentsOf: file)
    }
    do {
        let notice = try Data(contentsOf: root.appendingPathComponent("SplitMix64-NOTICE.txt"))
        guard !notice.isEmpty, notice.count <= 16_384 else {
            throw NSError(domain: "ContentValidator", code: 8, userInfo: [NSLocalizedDescriptionKey: "notice must contain 1...16384 bytes"])
        }
    } catch {
        throw NSError(domain: "ContentValidator", code: 9, userInfo: [NSLocalizedDescriptionKey: "SplitMix64-NOTICE.txt: \(error.localizedDescription)"])
    }
    // The package copies this directory exactly. Reject undeclared files rather
    // than accidentally shipping authoring traces or an unchecked extra level.
    let allowed = Set(["catalog.json", "SplitMix64-NOTICE.txt"] + catalog.envelope.assets + catalog.envelope.levels.map(\.file))
    guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: []) else {
        throw NSError(domain: "ContentValidator", code: 4, userInfo: [NSLocalizedDescriptionKey: "cannot enumerate selected content directory"])
    }
    for case let url as URL in enumerator {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        let canonical = url.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().appendingPathComponent(url.lastPathComponent)
        guard canonical.path.hasPrefix(root.path + "/") else {
            throw NSError(domain: "ContentValidator", code: 7, userInfo: [NSLocalizedDescriptionKey: "resource escapes selected content directory"])
        }
        let path = String(canonical.path.dropFirst(root.path.count + 1))
        guard values.isSymbolicLink != true else {
            throw NSError(domain: "ContentValidator", code: 5, userInfo: [NSLocalizedDescriptionKey: "symbolic links are not bundled resources: \(path)"])
        }
        if values.isDirectory != true && !allowed.contains(path) {
            throw NSError(domain: "ContentValidator", code: 6, userInfo: [NSLocalizedDescriptionKey: "undeclared bundled resource: \(path)"])
        }
    }
    print("Valid content: \(catalog.envelope.titleID), version \(catalog.envelope.contentVersion), \(catalog.levels.count) levels")
    for level in catalog.levels {
        let board = TileBoard(tiles: level.payload.tiles)
        let layers = (level.payload.tiles.map(\.layer).max() ?? 0) + 1
        print("  \(level.id): chapter \(level.payload.chapter), \(board.tiles.count) tiles, layers: \(layers), seed \(level.seed)")
    }
    return catalog
}

/// Writes the plan's levels and catalog, then validates the directory. Files
/// outside the plan are left alone, so a stale level fails validation.
func generate(plan planURL: URL, into root: URL) throws {
    let plan = try JSONDecoder().decode(LevelPlan.self, from: Data(contentsOf: planURL))
    let levels = try LevelPlanner.build(plan)
    try FileManager.default.createDirectory(at: root.appendingPathComponent("Levels"), withIntermediateDirectories: true)
    for (index, level) in levels.enumerated() {
        let next = index + 1 < levels.count ? levels[index + 1].entry.id : nil
        try Data(LevelPlanner.levelJSON(level, contentVersion: plan.contentVersion, next: next).utf8)
            .write(to: root.appendingPathComponent("Levels/\(level.entry.id).json"))
    }
    try Data(LevelPlanner.catalogJSON(levels, contentVersion: plan.contentVersion).utf8)
        .write(to: root.appendingPathComponent("catalog.json"))
    print("Generated \(levels.count) levels from \(planURL.lastPathComponent)")
    for level in levels {
        var replay = TileGame(board: TileBoard(tiles: level.tiles))
        for move in level.solution { replay.select(move) }
        let layers = (level.tiles.map(\.layer).max() ?? 0) + 1
        let kinds = Set(level.tiles.map(\.kind)).count
        let rate = String(format: "%.3f", level.measure.clearRate)
        print("  \(level.entry.id): \(level.tiles.count) tiles, layers: \(layers), kinds: \(kinds), seed \(level.seed), "
              + "random clear rate \(rate), recorded line \(replay.score), best random clear \(level.measure.bestScore)")
    }
    try validate(root)
}

func directory(_ path: String) -> URL {
    URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
}

func run() throws {
    let args = Array(CommandLine.arguments.dropFirst())
    switch args.first {
    case "generate":
        guard args.count == 3 else {
            throw NSError(domain: "ContentValidator", code: 3, userInfo: [NSLocalizedDescriptionKey: usage])
        }
        try generate(plan: URL(fileURLWithPath: args[1]), into: directory(args[2]))
    default:
        guard args.count <= 1 else {
            throw NSError(domain: "ContentValidator", code: 3, userInfo: [NSLocalizedDescriptionKey: usage])
        }
        try validate(args.isEmpty ? BundledContent.resourceDirectory().standardizedFileURL.resolvingSymlinksInPath() : directory(args[0]))
    }
}

do { try run() }
catch {
    FileHandle.standardError.write(Data("Content validation failed: \(error.localizedDescription)\n".utf8))
    exit(1)
}
