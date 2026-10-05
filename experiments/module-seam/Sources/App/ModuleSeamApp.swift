import Foundation
import GamePlatform
import SwiftUI

@main
struct ModuleSeamApp: App {
    var body: some Scene {
        WindowGroup {
            #if GRID_MODULE
            ModuleShell(host: makeHost(GridModule()))
            #else
            ModuleShell(host: makeHost(TerrainModule()))
            #endif
        }
    }
    @MainActor
    private func makeHost<M: GameModule>(_ module: M) -> ModuleHost<M> {
        do {
            var root = try LocalSaveStore.applicationSupportRoot()
            #if DEBUG
            root = try ModuleFixture.root(defaultRoot: root, arguments: ProcessInfo.processInfo.arguments)
            #endif
            let store = try LocalSaveStore(titleID: "development-practice", root: root)
            return ModuleHost(module: module, store: store, feedback: ShellFeedbackController())
        } catch {
            return ModuleHost(module: module, storageError: "Local data unavailable: \(error.localizedDescription)", feedback: ShellFeedbackController())
        }
    }
}
