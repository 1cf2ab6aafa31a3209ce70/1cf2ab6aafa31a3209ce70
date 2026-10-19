import DevelopmentContent
import GameCore
import GamePlatform
import SwiftUI

/// Composition root for the development title: it opens local storage and
/// registers the practice module. Shared coordination and UI depend on neither.
@MainActor
final class ShellModel: ObservableObject {
    let host: ModuleHost<PracticeModule>
    var scene: DevelopmentScene { host.module.scene }
    var controller: ShellController { host.controller }
    #if DEBUG
    private(set) var diagnostics: ShellActionJournal?
    #endif

    convenience init() {
        let store: LocalSaveStore?
        let storageError: String?
        #if DEBUG
        var diagnostics: ShellActionJournal?
        #endif
        do {
            let defaultRoot = try LocalSaveStore.applicationSupportRoot()
            #if DEBUG
            let root = try ShellUITestFixture.storageRoot(defaultRoot: defaultRoot, arguments: ProcessInfo.processInfo.arguments)
            #else
            let root = defaultRoot
            #endif
            store = try LocalSaveStore(titleID: "development-practice", root: root)
            storageError = nil
            #if DEBUG
            if root != defaultRoot, let identity = UUID(uuidString: root.lastPathComponent) {
                do { diagnostics = try ShellActionJournal(fixtureRoot: root, fixtureID: identity) }
                catch { print("GAMECORE_JOURNAL_UNAVAILABLE") }
            }
            #endif
        } catch {
            store = nil
            storageError = "Local data could not be opened: \(error.localizedDescription). Close and reopen the app to retry. Existing data has been preserved."
        }
        self.init(feedback: ShellFeedbackController(), store: store, storageError: storageError, preparation: {
            await Task.yield()
            try Task.checkCancellation()
            _ = try BundledContent.load()
        })
        #if DEBUG
        self.diagnostics = diagnostics
        diagnostics?.observe(controller)
        #endif
    }

    init(feedback: ShellFeedbackController?, store: LocalSaveStore? = nil, storageError: String? = nil, preparation: @escaping ShellController.Preparation) {
        host = ModuleHost(module: PracticeModule(preparation: preparation), feedback: feedback,
                          store: store, storageError: storageError)
    }
}
