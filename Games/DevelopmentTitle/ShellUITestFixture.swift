#if DEBUG
import Foundation

/// UI automation uses an owned namespace with the same save actor and schema.
/// The argument accepts an identity, never a caller-provided filesystem path.
enum ShellUITestFixture {
    enum InvalidArguments: Error { case invalidFixtureIdentity }

    static func storageRoot(defaultRoot: URL, arguments: [String]) throws -> URL {
        let flags = arguments.indices.filter { arguments[$0] == "--ui-test-fixture" }
        guard !flags.isEmpty else { return defaultRoot }
        guard flags.count == 1, let index = flags.first,
              arguments.indices.contains(index + 1),
              let identity = UUID(uuidString: arguments[index + 1]) else {
            throw InvalidArguments.invalidFixtureIdentity
        }
        return defaultRoot.appendingPathComponent("UIAutomationFixtures", isDirectory: true)
            .appendingPathComponent(identity.uuidString, isDirectory: true)
    }
}
#endif
