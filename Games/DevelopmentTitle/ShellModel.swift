import DevelopmentContent
import GameCore
import GamePlatform
import SwiftUI

/// The title owns its stable renderer and original preparation. Shared
/// coordination and UI consume the controller without depending on this type.
@MainActor
final class ShellModel: ObservableObject {
    let scene: DevelopmentScene
    let controller: ShellController
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
        let scene = DevelopmentScene(size: CGSize(width: 320, height: 240))
        self.scene = scene
        controller = ShellController(
            title: TitleRegistration(id: "development-practice", displayName: "Practice studio"),
            feedback: feedback,
            preparation: preparation,
            preparationFailureMessage: "Practice could not be prepared. Please try again.",
            prepareSession: scene.prepareSession,
            setPlaying: scene.setPlaying,
            setReducedMotion: scene.setReducedMotion,
            store: store,
            initialPersistenceError: storageError,
            recordSuccess: { progress in
                // Synthetic practice progress verifies persistence, not game rules.
                _ = progress.recordCompletion(levelID: "practice", score: 1, unlocks: ["practice-complete"])
            }
        )
    }
}
