#if canImport(Darwin)
import Foundation

/// Opens a title app's local save store. Every title uses this instead of its
/// own storage code, so the namespace rules and failure copy stay shared.
public struct TitleStorage {
    public let store: LocalSaveStore?
    /// Shown by the shell when the store could not be opened; data is untouched.
    public let errorMessage: String?
    #if DEBUG
    /// Set when UI automation selected an owned fixture namespace.
    public let fixture: (identity: UUID, root: URL)?
    #endif

    /// In DEBUG builds `--ui-test-fixture <UUID>` selects an owned namespace
    /// below the default root; a malformed flag fails closed rather than
    /// falling back to the player's data.
    public static func open(titleID: String,
                            arguments: [String] = ProcessInfo.processInfo.arguments) -> TitleStorage {
        do {
            let defaultRoot = try LocalSaveStore.applicationSupportRoot()
            #if DEBUG
            let root = try UITestFixture.storageRoot(defaultRoot: defaultRoot, arguments: arguments)
            let fixture = root == defaultRoot ? nil : UUID(uuidString: root.lastPathComponent).map { ($0, root) }
            return TitleStorage(store: try LocalSaveStore(titleID: titleID, root: root), errorMessage: nil, fixture: fixture)
            #else
            return TitleStorage(store: try LocalSaveStore(titleID: titleID, root: defaultRoot), errorMessage: nil)
            #endif
        } catch {
            let message = "Local data could not be opened: \(error.localizedDescription). Close and reopen the app to retry. Existing data has been preserved."
            #if DEBUG
            return TitleStorage(store: nil, errorMessage: message, fixture: nil)
            #else
            return TitleStorage(store: nil, errorMessage: message)
            #endif
        }
    }
}

#if DEBUG
/// UI automation uses an owned namespace with the same save actor and schema.
/// The argument accepts an identity, never a caller-provided filesystem path.
public enum UITestFixture {
    public enum InvalidArguments: Error { case invalidFixtureIdentity }

    public static func storageRoot(defaultRoot: URL, arguments: [String]) throws -> URL {
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
#endif
