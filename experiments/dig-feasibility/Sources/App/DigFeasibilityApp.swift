import Foundation
import GamePlatform
import SwiftUI

/// One title target registering one module through contract version 1. Debug builds
/// choose the candidate renderer by launch argument; Release always runs the heightfield.
@main
struct DigFeasibilityApp: App {
    @StateObject private var host = Self.makeHost(DigModule(options: DigOptions.launch))

    var body: some Scene {
        WindowGroup {
            ModuleShellView(host: host)
        }
    }

    @MainActor
    private static func makeHost(_ module: DigModule) -> ModuleHost<DigModule> {
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
