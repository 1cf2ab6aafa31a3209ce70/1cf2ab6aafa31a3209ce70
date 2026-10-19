import GameCore
import GamePlatform
import SpriteKit
import SwiftUI

/// The development practice registers through the module contract like any
/// title. Its session is synthetic: it exercises the shared flow, not game rules.
@MainActor
final class PracticeModule: GameModule {
    let title = TitleRegistration(id: "development-practice", displayName: "Practice studio")
    let loadFailureMessage = "Practice could not be prepared. Please try again."
    let scene: DevelopmentScene
    let session: PracticeSession

    init(preparation: @escaping ShellController.Preparation) {
        scene = DevelopmentScene(size: CGSize(width: 320, height: 240))
        session = PracticeSession(scene: scene, preparation: preparation)
    }

    var presentation: ShellPresentation { Self.presentation }

    func makeGameplay() -> some View {
        PracticeGameplay(scene: scene, playing: session.playing)
    }

    func makeControls(_ context: ModulePlayContext) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            ShellHeading("Practice in progress", id: "shell.play")
            Text(context.reducesMotion ? "The marker stays still with Reduce Motion. Complete the practice, or end it to try again."
                 : "The marker breathes while practice is running. Complete the practice, or end it to try again.")
            ShellActionButton("Pause", id: "shell.pause", action: context.pause)
            ShellActionButton("Complete practice", id: "shell.complete", prominent: true, action: session.complete)
            ShellActionButton("End practice", id: "shell.fail", action: session.fail)
        }
    }

    func setReducedMotion(_ enabled: Bool) { scene.setReducedMotion(enabled) }

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

/// Practice has one synthetic level. Preparation validates the bundled
/// catalog; success records fixed progress so saves are exercised end to end.
@MainActor
final class PracticeSession: ModuleSession {
    var playing = false { didSet { scene.setPlaying(playing) } }
    var settings = ShellSettings()
    var outcomeHandler: ((ShellOutcome, LoadRequest) -> Void)?
    private let scene: DevelopmentScene
    private let preparation: ShellController.Preparation
    private var request: LoadRequest?

    init(scene: DevelopmentScene, preparation: @escaping ShellController.Preparation) {
        self.scene = scene
        self.preparation = preparation
    }

    func prepare(for request: LoadRequest) async throws { try await preparation() }

    func begin(for request: LoadRequest) {
        self.request = request
        scene.prepareSession()
    }

    func complete() { finish(.success) }
    func fail() { finish(.failure) }

    func recordSuccess(in progress: inout SaveProgress) {
        // Synthetic practice progress verifies persistence, not game rules.
        _ = progress.recordCompletion(levelID: "practice", score: 1, unlocks: ["practice-complete"])
    }

    private func finish(_ outcome: ShellOutcome) {
        guard let request else { return }
        outcomeHandler?(outcome, request)
    }
}

private struct PracticeGameplay: View {
    let scene: DevelopmentScene
    let playing: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        SpriteView(scene: scene, isPaused: !playing)
            .frame(height: dynamicTypeSize.isAccessibilitySize ? 180 : 240)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .accessibilityHidden(true)
    }
}
