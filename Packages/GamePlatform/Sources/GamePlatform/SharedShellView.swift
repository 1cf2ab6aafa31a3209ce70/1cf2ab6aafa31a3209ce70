#if os(iOS)
import GameCore
import SwiftUI

/// Title-authored presentation copy for the shared flow. It contains no game rules.
public struct ShellPresentation: Sendable {
    public let openingMessage: String
    public let menuHeading: String
    public let menuMessage: String
    public let startLabel: String
    public let loadingMessage: String
    public let pauseMessage: String
    public let audioPauseMessage: String
    public let restartLabel: String
    public let successHeading: String
    public let successMessage: String
    public let failureHeading: String
    public let failureMessage: String
    public let retryLabel: String
    public let languageName: String
    public let languageMessage: String

    public init(openingMessage: String, menuHeading: String, menuMessage: String,
                startLabel: String, loadingMessage: String, pauseMessage: String,
                audioPauseMessage: String, restartLabel: String, successHeading: String,
                successMessage: String, failureHeading: String, failureMessage: String,
                retryLabel: String, languageName: String, languageMessage: String) {
        self.openingMessage = openingMessage
        self.menuHeading = menuHeading
        self.menuMessage = menuMessage
        self.startLabel = startLabel
        self.loadingMessage = loadingMessage
        self.pauseMessage = pauseMessage
        self.audioPauseMessage = audioPauseMessage
        self.restartLabel = restartLabel
        self.successHeading = successHeading
        self.successMessage = successMessage
        self.failureHeading = failureHeading
        self.failureMessage = failureMessage
        self.retryLabel = retryLabel
        self.languageName = languageName
        self.languageMessage = languageMessage
    }
}

/// Common mobile UI and lifecycle integration. A title supplies its renderer
/// and active play controls as ordinary SwiftUI content, without a module protocol.
@MainActor
public struct SharedShellView<GameplayHost: View, GameplayControls: View>: View {
    @ObservedObject private var controller: ShellController
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingSettings = false
    private let presentation: ShellPresentation
    private let forceReducedMotion: Bool
    private let gameplayHost: () -> GameplayHost
    private let gameplayControls: (Bool) -> GameplayControls

    public init(controller: ShellController, presentation: ShellPresentation,
                forceReducedMotion: Bool = false,
                @ViewBuilder gameplayHost: @escaping () -> GameplayHost,
                @ViewBuilder gameplayControls: @escaping (Bool) -> GameplayControls) {
        self.controller = controller
        self.presentation = presentation
        self.forceReducedMotion = forceReducedMotion
        self.gameplayHost = gameplayHost
        self.gameplayControls = gameplayControls
    }

    private var reducesMotion: Bool { reduceMotion || forceReducedMotion }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(controller.flow.title.displayName)
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                if showsGameplayHost {
                    gameplayHost()
                }
                content
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("shell.scroll")
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $showingSettings) {
            SharedShellSettingsView(controller: controller, presentation: presentation)
        }
        .onAppear {
            controller.finishSplash()
            controller.setReducedMotion(reducesMotion)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            controller.setApplicationActive(phase == .active)
        }
        .onChange(of: reducesMotion) { _, enabled in
            controller.setReducedMotion(enabled)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch controller.flow.state {
        case .splash:
            ProgressView(presentation.openingMessage)
                .accessibilityIdentifier("shell.splash")
        case .menu:
            VStack(alignment: .leading, spacing: 20) {
                ShellHeading(presentation.menuHeading, id: "shell.menu")
                Text(presentation.menuMessage)
                ShellActionButton(presentation.startLabel, id: "shell.start", prominent: true, action: controller.start)
                ShellActionButton("Settings", id: "shell.settings") { showingSettings = true }
            }
        case .loading:
            ProgressView(presentation.loadingMessage)
                .accessibilityIdentifier("shell.loading")
            ShellActionButton("Back to menu", id: "shell.menu.back", action: controller.returnToMenu)
        case .playing:
            gameplayControls(reducesMotion)
        case .paused(_, let reasons):
            ShellHeading("Paused", id: "shell.paused")
            Text(reasons.contains(.audioInterruption) ? presentation.audioPauseMessage : presentation.pauseMessage)
            if let message = controller.resumeMessage {
                Text(message).foregroundStyle(.secondary)
            }
            ShellActionButton("Resume", id: "shell.resume", prominent: true, action: controller.resume)
                .disabled(reasons.contains(.applicationInactive))
            ShellActionButton(presentation.restartLabel, id: "shell.restart", action: controller.restart)
            ShellActionButton("Settings", id: "shell.settings") { showingSettings = true }
            ShellActionButton("Back to menu", id: "shell.menu.back", action: controller.returnToMenu)
        case .result(_, let outcome):
            ShellHeading(outcome == .success ? presentation.successHeading : presentation.failureHeading,
                         id: outcome == .success ? "shell.result.success" : "shell.result.failure")
            Text(outcome == .success ? presentation.successMessage : presentation.failureMessage)
            ShellActionButton(presentation.retryLabel, id: "shell.result.retry", prominent: true, action: controller.restart)
            ShellActionButton("Back to menu", id: "shell.result.menu", action: controller.returnToMenu)
        case .loadFailed(_, let message):
            ShellHeading("Unable to start", id: "shell.load-error")
            Text(message)
            ShellActionButton("Try again", id: "shell.load.retry", prominent: true, action: controller.restart)
            ShellActionButton("Back to menu", id: "shell.menu.back", action: controller.returnToMenu)
        }
    }

    private var showsGameplayHost: Bool {
        switch controller.flow.state {
        case .playing, .paused: return true
        default: return false
        }
    }
}

/// Common, accessible action styling for both shell pages and title controls.
public struct ShellActionButton: View {
    private let title: String
    private let identifier: String
    private let prominent: Bool
    private let action: () -> Void

    public init(_ title: String, id: String, prominent: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.identifier = id
        self.prominent = prominent
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .tint(prominent ? .teal : .accentColor)
        .accessibilityIdentifier(identifier)
    }
}

public struct ShellHeading: View {
    private let title: String
    private let identifier: String

    public init(_ title: String, id: String) {
        self.title = title
        self.identifier = id
    }

    public var body: some View {
        Text(title).font(.title2.bold()).accessibilityAddTraits(.isHeader).accessibilityIdentifier(identifier)
    }
}

@MainActor
private struct SharedShellSettingsView: View {
    @ObservedObject var controller: ShellController
    let presentation: ShellPresentation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Feedback") {
                    Toggle("Sound effects", isOn: Binding(get: { controller.flow.settings.soundEnabled },
                        set: { controller.updateSettings(sound: $0) }))
                        .accessibilityIdentifier("settings.sound")
                    Toggle("Music", isOn: Binding(get: { controller.flow.settings.musicEnabled },
                        set: { controller.updateSettings(music: $0) }))
                        .accessibilityIdentifier("settings.music")
                    Toggle("Haptics", isOn: Binding(get: { controller.flow.settings.hapticsEnabled },
                        set: { controller.updateSettings(haptics: $0) }))
                        .accessibilityIdentifier("settings.haptics")
                }
                Section("Language") {
                    LabeledContent("Language", value: presentation.languageName)
                    Text(presentation.languageMessage).foregroundStyle(.secondary)
                }
                Section {
                    Text("Settings apply to this session and reset when the app closes.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("settings.done")
                }
            }
        }
    }
}
#endif
