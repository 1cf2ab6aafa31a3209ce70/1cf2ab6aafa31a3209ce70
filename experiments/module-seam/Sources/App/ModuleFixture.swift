#if DEBUG
import Foundation
import GameCore

/// Test-only namespaces fail closed when an explicit identity is malformed.
enum ModuleFixture {
    static func root(defaultRoot: URL, arguments: [String]) throws -> URL {
        let positions = arguments.indices.filter { arguments[$0] == "--module-fixture" }
        guard !positions.isEmpty else { return defaultRoot }
        guard positions.count == 1, let index = positions.first,
              arguments.indices.contains(index + 1),
              let fixture = UUID(uuidString: arguments[index + 1]) else {
            throw ContentValidationError(message: "Invalid module fixture identity")
        }
        return defaultRoot.appendingPathComponent("module-fixtures").appendingPathComponent(fixture.uuidString)
    }
}
#endif
