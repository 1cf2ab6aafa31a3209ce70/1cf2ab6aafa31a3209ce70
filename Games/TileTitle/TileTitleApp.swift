import GamePlatform
import SwiftUI

@main
struct TileTitleApp: App {
    @StateObject private var host = TileTitleApp.makeHost()

    var body: some Scene {
        WindowGroup {
            ModuleShellView(host: host)
        }
    }

    /// The whole composition root: shared storage, shared feedback, this module.
    @MainActor
    private static func makeHost() -> ModuleHost<TileTitleModule> {
        let module = TileTitleModule()
        let storage = TitleStorage.open(titleID: module.title.id)
        return ModuleHost(module: module, feedback: ShellFeedbackController(),
                          store: storage.store, storageError: storage.errorMessage)
    }
}
