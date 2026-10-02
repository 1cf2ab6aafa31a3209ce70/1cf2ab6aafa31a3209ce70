import GameCore
import GamePlatform
import SpriteKit
import SwiftUI

/// Only this title's renderer, practice actions and presentation copy live here.
struct ShellView: View {
    @ObservedObject var model: ShellModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var forceReducedMotion = false

    var body: some View {
        SharedShellView(controller: model.controller, presentation: Self.presentation,
                        forceReducedMotion: forceReducedMotion) {
            SpriteView(scene: model.scene, isPaused: !model.controller.flow.inputIsActive)
                .frame(height: dynamicTypeSize.isAccessibilitySize ? 180 : 240)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .accessibilityHidden(true)
        } gameplayControls: { reducesMotion in
            VStack(alignment: .leading, spacing: 20) {
                ShellHeading("Practice in progress", id: "shell.play")
                Text(reducesMotion ? "The marker stays still with Reduce Motion. Complete the practice, or end it to try again."
                     : "The marker breathes while practice is running. Complete the practice, or end it to try again.")
                ShellActionButton("Pause", id: "shell.pause", action: model.controller.pause)
                ShellActionButton("Complete practice", id: "shell.complete", prominent: true) {
                    model.controller.finish(.success)
                }
                ShellActionButton("End practice", id: "shell.fail") { model.controller.finish(.failure) }
            }
        }
    }

    private static let presentation = ShellPresentation(
        openingMessage: "Opening practice",
        menuHeading: "Ready to practice",
        menuMessage: "A small offline scene for practicing play, pause and starting again.",
        startLabel: "Start practice",
        loadingMessage: "Preparing practice",
        pauseMessage: "Practice is paused. Resume when you’re ready.",
        audioPauseMessage: "Practice paused for an audio interruption. Resume when you’re ready.",
        restartLabel: "Restart practice",
        successHeading: "Practice complete",
        successMessage: "You completed this practice. Start another whenever you’re ready.",
        failureHeading: "Practice ended",
        failureMessage: "You ended this practice. Retry whenever you’re ready.",
        retryLabel: "Practice again",
        languageName: "English",
        languageMessage: "This practice currently supports English."
    )
}
