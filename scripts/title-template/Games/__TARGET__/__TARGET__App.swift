import GamePlatform
import SwiftUI

@main
struct __TARGET__App: App {
    @StateObject private var host = __TARGET__App.makeHost()

    var body: some Scene {
        WindowGroup {
            ModuleShellView(host: host)
        }
    }

    /// The whole composition root: shared storage, shared feedback, this module.
    @MainActor
    private static func makeHost() -> ModuleHost<__TARGET__Module> {
        let module = __TARGET__Module()
        let storage = TitleStorage.open(titleID: module.title.id)
        return ModuleHost(module: module, feedback: ShellFeedbackController(),
                          store: storage.store, storageError: storage.errorMessage)
    }
}
