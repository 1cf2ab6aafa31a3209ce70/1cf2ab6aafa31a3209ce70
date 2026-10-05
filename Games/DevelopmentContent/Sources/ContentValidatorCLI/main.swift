import DevelopmentContent
import Foundation

func validate() throws {
    let args = Array(CommandLine.arguments.dropFirst())
    guard args.count <= 1 else {
        throw NSError(domain: "ContentValidator", code: 3, userInfo: [NSLocalizedDescriptionKey: "usage: content-validator [content-directory]; omitted directory validates bundled original samples"])
    }
    let root = try (args.isEmpty ? BundledContent.resourceDirectory() : URL(fileURLWithPath: args[0], isDirectory: true)).standardizedFileURL.resolvingSymlinksInPath()
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
    for level in catalog.levels { print("  \(level.id): \(level.gameType.rawValue), seed \(level.seed)") }
}

do { try validate() }
catch {
    FileHandle.standardError.write(Data("Content validation failed: \(error.localizedDescription)\n".utf8))
    exit(1)
}
