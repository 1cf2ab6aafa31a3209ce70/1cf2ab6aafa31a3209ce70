import GameCore
import GamePlatform
import SwiftUI

/// The title owns its stable renderer and original preparation. Shared
/// coordination and UI consume the controller without depending on this type.
@MainActor
final class ShellModel: ObservableObject {
    let scene: DevelopmentScene
    let controller: ShellController

    convenience init() {
        self.init(feedback: ShellFeedbackController(), preparation: {
            // The practice has no external assets to load.
            await Task.yield()
            try Task.checkCancellation()
        })
    }

    init(feedback: ShellFeedbackController?, preparation: @escaping ShellController.Preparation) {
        let scene = DevelopmentScene(size: CGSize(width: 320, height: 240))
        self.scene = scene
        controller = ShellController(
            title: TitleRegistration(id: "development-practice", displayName: "Practice studio"),
            feedback: feedback,
            preparation: preparation,
            preparationFailureMessage: "Practice could not be prepared. Please try again.",
            prepareSession: scene.prepareSession,
            setPlaying: scene.setPlaying,
            setReducedMotion: scene.setReducedMotion
        )
    }
}
