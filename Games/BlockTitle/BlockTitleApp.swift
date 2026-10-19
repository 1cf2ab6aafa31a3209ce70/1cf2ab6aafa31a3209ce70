import GamePlatform
import SwiftUI

@main
struct BlockTitleApp: App {
    @StateObject private var host = BlockTitleApp.makeHost()

    var body: some Scene {
        WindowGroup {
            ModuleShellView(host: host)
        }
    }

    /// The whole composition root: shared storage, shared feedback, this module.
    @MainActor
    private static func makeHost() -> ModuleHost<BlockModule> {
        let module = BlockModule()
        let storage = TitleStorage.open(titleID: module.title.id)
        return ModuleHost(module: module, feedback: ShellFeedbackController(),
                          store: storage.store, storageError: storage.errorMessage)
    }
}
