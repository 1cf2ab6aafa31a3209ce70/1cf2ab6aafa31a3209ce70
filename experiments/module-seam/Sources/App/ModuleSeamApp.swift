import Foundation
import GamePlatform
import SwiftUI

#if GRID_MODULE
typealias SeamModule = GridModule
#else
typealias SeamModule = TerrainModule
#endif

@main
struct ModuleSeamApp: App {
    @StateObject private var host = Self.makeHost(SeamModule())

    var body: some Scene {
        WindowGroup {
            ModuleShellView(host: host)
        }
    }

    @MainActor
    private static func makeHost(_ module: SeamModule) -> ModuleHost<SeamModule> {
        do {
            var root = try LocalSaveStore.applicationSupportRoot()
            #if DEBUG
            root = try ModuleFixture.root(defaultRoot: root, arguments: ProcessInfo.processInfo.arguments)
            #endif
            let store = try LocalSaveStore(titleID: module.title.id, root: root)
            return ModuleHost(module: module, feedback: ShellFeedbackController(), store: store)
        } catch {
            return ModuleHost(module: module, feedback: ShellFeedbackController(),
                              storageError: "Local data unavailable: \(error.localizedDescription)")
        }
    }
}
