import SwiftUI

@main
struct DevelopmentTitleApp: App {
    @StateObject private var model = ShellModel()

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            ShellView(model: model, forceReducedMotion: ProcessInfo.processInfo.arguments.contains("--shell-reduced-motion"))
                .modifier(ShellTestTextSize())
            #else
            ShellView(model: model)
            #endif
        }
    }
}

#if DEBUG
/// Overrides presentation traits only; the production flow and controls stay unchanged.
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
