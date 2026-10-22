import GamePlatform
import SwiftUI

@main
struct TileTitleApp: App {
    @StateObject private var host = TileTitleApp.makeHost()

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            ModuleShellView(host: host, forceReducedMotion: ProcessInfo.processInfo.arguments.contains("--shell-reduced-motion"))
                .modifier(ShellTestTextSize())
                .modifier(SeededAccessibilityViolation())
            #else
            ModuleShellView(host: host)
            #endif
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

#if DEBUG
/// `--ui-test-seed-accessibility-violation` adds one small control with no
/// label, so a UI test can prove the accessibility audit gate fails on it.
private struct SeededAccessibilityViolation: ViewModifier {
    func body(content: Content) -> some View {
        if ProcessInfo.processInfo.arguments.contains("--ui-test-seed-accessibility-violation") {
            content.overlay {
                Button {} label: { Rectangle().fill(Color(white: 0.9)).frame(width: 20, height: 20) }
                    .accessibilityIdentifier("seeded.violation")
            }
        } else {
            content
        }
    }
}

/// The practice title's DEBUG text-size override. It changes presentation
/// traits only; the production flow and controls stay unchanged.
private struct ShellTestTextSize: ViewModifier {
    func body(content: Content) -> some View {
        if ProcessInfo.processInfo.arguments.contains("--shell-large-text") {
            content.dynamicTypeSize(.accessibility3)
        } else {
            content
        }
    }
}
#endif
