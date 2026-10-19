import __CONTENT__
import Combine
import GameCore
import GamePlatform
import SwiftUI

/// __DISPLAY_NAME__ registered through module contract version 1. This
/// skeleton's session completes a level after its `steps` selections; replace
/// the rules, renderer and controls with the title's own.
@MainActor
final class __TARGET__Module: GameModule {
    let title = TitleRegistration(id: "__TITLE_ID__", displayName: "__DISPLAY_NAME__")
    let session: __TARGET__Session

    init(session: __TARGET__Session? = nil) {
        self.session = session ?? __TARGET__Session()
    }

    var presentation: ShellPresentation {
        ShellPresentation(
            openingMessage: "Opening __DISPLAY_NAME__", menuHeading: "__DISPLAY_NAME__",
            menuMessage: "A skeleton title. Replace this text with the title's own.",
            startLabel: "Play", loadingMessage: "Loading the level",
            pauseMessage: "Paused. Resume when you’re ready.",
            audioPauseMessage: "Paused for an audio interruption. Resume when you’re ready.",
            restartLabel: "Restart level", successHeading: "Level complete",
            successMessage: "The level was recorded on this device.", failureHeading: "Level ended",
            failureMessage: "No completion was recorded.", retryLabel: "Play again",
            languageName: "English", languageMessage: "__DISPLAY_NAME__ currently supports English.")
    }

    func makeGameplay() -> some View { __TARGET__GameplayView(session: session) }

    func makeControls(_ context: ModulePlayContext) -> some View {
        __TARGET__ControlsView(session: session, context: context)
    }

    func setReducedMotion(_ enabled: Bool) { session.reducedMotion = enabled }
}

/// Title-owned session: preparation decodes the next level from saved
/// progress, and beginning creates fresh rule state for that request.
@MainActor
final class __TARGET__Session: ObservableObject, ModuleSession {
    @Published var playing = false
    @Published var settings = ShellSettings()
    @Published var reducedMotion = false
    @Published private(set) var level: __CONTENT__Level?
    @Published private(set) var stepsTaken = 0
    var outcomeHandler: ((ShellOutcome, LoadRequest) -> Void)?
    private(set) var request: LoadRequest?
    private var progress = SaveProgress()
    private var preparationEpoch = UUID()
    private var staged: (request: LoadRequest, level: __CONTENT__Level)?
    private var finished = false
    private let loader: () async throws -> __CONTENT__Catalog

    init(loader: @escaping () async throws -> __CONTENT__Catalog = { try BundledContent.load() }) {
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

struct __TARGET__GameplayView: View {
    @ObservedObject var session: __TARGET__Session

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

struct __TARGET__ControlsView: View {
    @ObservedObject var session: __TARGET__Session
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
