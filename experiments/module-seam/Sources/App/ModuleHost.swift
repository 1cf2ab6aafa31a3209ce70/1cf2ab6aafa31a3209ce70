import Combine
import Foundation
import GameCore
import GamePlatform
import SwiftUI

/// Named compatibility bridge for the shell's existing no-argument closures.
@MainActor
private final class ControllerReference { weak var value: ShellController? }

@MainActor
final class ModuleHost<Module: GameModule>: ObservableObject {
    let module: Module
    let controller: ShellController
    private var settingsSubscription: AnyCancellable?
    init(module: Module, store: LocalSaveStore? = nil, storageError: String? = nil,
         feedback: ShellFeedbackController? = nil) {
        self.module = module
        let bridge = ControllerReference()
        let session = module.session
        let controller = ShellController(
            title: TitleRegistration(id: "development-practice", displayName: module.displayName),
            feedback: feedback,
            preparation: {
                guard module.contractVersion == 1 else { throw ContentValidationError(message: "Unsupported module registration") }
                guard let request = bridge.value?.flow.currentRequest else { throw CancellationError() }
                try await session.prepare(for: request)
            }, preparationFailureMessage: "Module could not load. Check its bundled content and registration version.",
            prepareSession: { if let request = bridge.value?.flow.currentRequest { session.begin(for: request) } },
            setPlaying: { session.playing = $0 }, setReducedMotion: module.setReducedMotion,
            store: store, initialPersistenceError: storageError,
            recordSuccess: session.recordSuccess)
        self.controller = controller
        bridge.value = controller
        session.outcomeHandler = { [weak controller] outcome, request in controller?.finish(outcome, for: request) }
        settingsSubscription = controller.$flow.map(\.settings).removeDuplicates().sink { session.settings = $0 }
    }
}

struct ModuleShell<Module: GameModule>: View {
    @StateObject var host: ModuleHost<Module>
    var body: some View {
        SharedShellView(controller: host.controller, presentation: Self.presentation) {
            host.module.makeGameplay()
        } gameplayControls: { _ in
            VStack(alignment: .leading, spacing: 12) {
                ShellHeading("Module running", id: "shell.play")
                host.module.makeControls()
                ShellActionButton("Pause", id: "shell.pause", action: host.controller.pause)
                ShellActionButton("End session", id: "shell.fail", action: host.module.session.fail)
            }
        }
    }
    private static var presentation: ShellPresentation {
        ShellPresentation(openingMessage: "Opening module", menuHeading: "Module seam experiment",
            menuMessage: "Original bundled sample; renderer and controls belong to this module.",
            startLabel: "Start sample", loadingMessage: "Loading sample", pauseMessage: "Resume to accept input.",
            audioPauseMessage: "Audio interrupted. Resume when ready.", restartLabel: "Restart sample",
            successHeading: "Sample complete", successMessage: "The selected level was recorded locally.",
            failureHeading: "Session ended", failureMessage: "No completion was recorded.", retryLabel: "Try again",
            languageName: "English", languageMessage: "Experiment supports English.")
    }
}
