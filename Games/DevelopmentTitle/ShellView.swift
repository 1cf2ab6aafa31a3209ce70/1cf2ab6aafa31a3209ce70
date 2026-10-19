import GamePlatform
import SwiftUI

/// The title's root view: the shared module shell, plus DEBUG fixture diagnostics.
struct ShellView: View {
    @ObservedObject var model: ShellModel
    var forceReducedMotion = false

    @ViewBuilder
    var body: some View {
        #if DEBUG
        ModuleShellView(host: model.host, forceReducedMotion: forceReducedMotion)
            .environment(\.shellDiagnosticAction, { [weak model] id in
                guard let model else { return }
                model.diagnostics?.recordButton(id, controller: model.controller)
            })
        #else
        ModuleShellView(host: model.host, forceReducedMotion: forceReducedMotion)
        #endif
    }
}
