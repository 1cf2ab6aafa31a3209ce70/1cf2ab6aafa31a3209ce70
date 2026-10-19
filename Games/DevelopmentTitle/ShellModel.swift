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
        let storage = TitleStorage.open(titleID: "development-practice")
        self.init(feedback: ShellFeedbackController(), store: storage.store, storageError: storage.errorMessage, preparation: {
            await Task.yield()
            try Task.checkCancellation()
            _ = try BundledContent.load()
        })
        #if DEBUG
        if let fixture = storage.fixture {
            do { diagnostics = try ShellActionJournal(fixtureRoot: fixture.root, fixtureID: fixture.identity) }
            catch { print("GAMECORE_JOURNAL_UNAVAILABLE") }
        }
        diagnostics?.observe(controller)
        #endif
    }

    init(feedback: ShellFeedbackController?, store: LocalSaveStore? = nil, storageError: String? = nil, preparation: @escaping ShellController.Preparation) {
        host = ModuleHost(module: PracticeModule(preparation: preparation), feedback: feedback,
                          store: store, storageError: storageError)
    }
}
