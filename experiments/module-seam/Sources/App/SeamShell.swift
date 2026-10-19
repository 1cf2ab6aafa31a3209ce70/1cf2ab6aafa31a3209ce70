import GameCore
import GamePlatform
import SwiftUI

/// Both studies register through the production contract with this shared
/// experiment copy; each study adds only its own controls between these.
extension ShellPresentation {
    static let seam = ShellPresentation(
        openingMessage: "Opening module", menuHeading: "Module seam experiment",
        menuMessage: "Original bundled sample; renderer and controls belong to this module.",
        startLabel: "Start sample", loadingMessage: "Loading sample", pauseMessage: "Resume to accept input.",
        audioPauseMessage: "Audio interrupted. Resume when ready.", restartLabel: "Restart sample",
        successHeading: "Sample complete", successMessage: "The selected level was recorded locally.",
        failureHeading: "Session ended", failureMessage: "No completion was recorded.", retryLabel: "Try again",
        languageName: "English", languageMessage: "Experiment supports English.")
}

/// The play controls both studies share: a heading, the study's own controls,
/// Pause from the shell and End through the session.
@MainActor
struct SeamPlayControls<StudyControls: View>: View {
    let context: ModulePlayContext
    let end: () -> Void
    @ViewBuilder let study: () -> StudyControls

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ShellHeading("Module running", id: "shell.play")
            study()
            ShellActionButton("Pause", id: "shell.pause", action: context.pause)
            ShellActionButton("End session", id: "shell.fail", action: end)
        }
    }
}
