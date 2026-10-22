import TileContent
import Combine
import GameCore
import GamePlatform
import SwiftUI

/// Few Tiles registered through module contract version 1. This
/// skeleton's session completes a level after its `steps` selections; replace
/// the rules, renderer and controls with the title's own.
@MainActor
final class TileTitleModule: GameModule {
    let title = TitleRegistration(id: "tile-match", displayName: "Few Tiles")
    let session: TileTitleSession

    init(session: TileTitleSession? = nil) {
        self.session = session ?? TileTitleSession()
    }

    var presentation: ShellPresentation {
        ShellPresentation(
            openingMessage: "Opening Few Tiles", menuHeading: "Few Tiles",
            menuMessage: "A skeleton title. Replace this text with the title's own.",
            startLabel: "Play", loadingMessage: "Loading the level",
            pauseMessage: "Paused. Resume when you’re ready.",
            audioPauseMessage: "Paused for an audio interruption. Resume when you’re ready.",
            restartLabel: "Restart level", successHeading: "Level complete",
            successMessage: "The level was recorded on this device.", failureHeading: "Level ended",
            failureMessage: "No completion was recorded.", retryLabel: "Play again",
            languageName: "English", languageMessage: "Few Tiles currently supports English.")
    }

    func makeGameplay() -> some View { TileTitleGameplayView(session: session) }

    func makeControls(_ context: ModulePlayContext) -> some View {
        TileTitleControlsView(session: session, context: context)
    }

    func setReducedMotion(_ enabled: Bool) { session.reducedMotion = enabled }
}

/// Title-owned session: preparation decodes the next level from saved
/// progress, and beginning creates fresh rule state for that request.
@MainActor
final class TileTitleSession: ObservableObject, ModuleSession {
    @Published var playing = false
    @Published var settings = ShellSettings()
    @Published var reducedMotion = false
    @Published private(set) var level: TileContentLevel?
    @Published private(set) var stepsTaken = 0
    var outcomeHandler: ((ShellOutcome, LoadRequest) -> Void)?
    private(set) var request: LoadRequest?
    private var progress = SaveProgress()
    private var preparationEpoch = UUID()
    private var staged: (request: LoadRequest, level: TileContentLevel)?
    private var finished = false
    private let loader: () async throws -> TileContentCatalog

    init(loader: @escaping () async throws -> TileContentCatalog = { try BundledContent.load() }) {
        self.loader = loader
    }

    func progressDidChange(_ progress: SaveProgress) { self.progress = progress }

    func prepare(for request: LoadRequest) async throws {
        // A cancelled load must not erase a newer one's staged level.
        try Task.checkCancellation()
        let epoch = UUID()
        preparationEpoch = epoch
        staged = nil
        let catalog = try await loader()
        try Task.checkCancellation()
        guard preparationEpoch == epoch, request.titleID == catalog.envelope.titleID else {
            throw ContentValidationError(message: "Superseded preparation or another title's catalog")
        }
        staged = (request, catalog.nextLevel(after: progress))
    }

    func begin(for request: LoadRequest) {
        guard let staged, staged.request == request else { return }
        self.staged = nil
        self.request = request
        level = staged.level
        stepsTaken = 0
        finished = false
    }

    /// Touch and accessible controls both act through here.
    func step() {
        guard playing, !finished, let level, let request else { return }
        stepsTaken += 1
        if stepsTaken >= level.payload.steps { finish(.success, request) }
    }

    func fail() {
        guard playing, !finished, let request else { return }
        finish(.failure, request)
    }

    func recordSuccess(in progress: inout SaveProgress) {
        guard let level, stepsTaken >= level.payload.steps else { return }
        _ = progress.recordCompletion(levelID: level.id, unlocks: level.payload.nextLevelIDs)
    }

    private func finish(_ outcome: ShellOutcome, _ request: LoadRequest) {
        finished = true
        outcomeHandler?(outcome, request)
    }
}

struct TileTitleGameplayView: View {
    @ObservedObject var session: TileTitleSession

    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.accentColor.opacity(session.playing ? 0.35 : 0.15))
            .frame(height: 180)
            .overlay(Text(session.level?.id ?? "").font(.title2.monospaced()))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Level \(session.level?.id ?? "")")
            .accessibilityIdentifier("skeleton.surface")
    }
}

struct TileTitleControlsView: View {
    @ObservedObject var session: TileTitleSession
    let context: ModulePlayContext

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ShellHeading("Level in progress", id: "shell.play")
            Text("Steps: \(session.stepsTaken) of \(session.level?.payload.steps ?? 0)")
                .accessibilityIdentifier("skeleton.steps")
            ShellActionButton("Take a step", id: "skeleton.step", prominent: true, action: session.step)
            ShellActionButton("Pause", id: "shell.pause", action: context.pause)
            ShellActionButton("End level", id: "shell.fail", action: session.fail)
        }
    }
}
