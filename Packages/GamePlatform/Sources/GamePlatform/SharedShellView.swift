#if os(iOS)
import GameCore
import SwiftUI
import UniformTypeIdentifiers

#if DEBUG
private struct ShellDiagnosticActionKey: EnvironmentKey {
    static let defaultValue: ((String) -> Void)? = nil
}
extension EnvironmentValues {
    public var shellDiagnosticAction: ((String) -> Void)? {
        get { self[ShellDiagnosticActionKey.self] }
        set { self[ShellDiagnosticActionKey.self] = newValue }
    }
}
#endif

/// Common mobile UI and lifecycle integration. A title supplies its renderer
/// and active play controls as ordinary SwiftUI content, without a module protocol.
@MainActor
public struct SharedShellView<GameplayHost: View, GameplayControls: View>: View {
    @ObservedObject private var controller: ShellController
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingSettings = false
    private let presentation: ShellPresentation
    private let forceReducedMotion: Bool
    private let resultSummary: () -> String?
    private let gameplayHost: () -> GameplayHost
    private let gameplayControls: (Bool) -> GameplayControls

    public init(controller: ShellController, presentation: ShellPresentation,
                forceReducedMotion: Bool = false,
                resultSummary: @escaping () -> String? = { nil },
                @ViewBuilder gameplayHost: @escaping () -> GameplayHost,
                @ViewBuilder gameplayControls: @escaping (Bool) -> GameplayControls) {
        self.controller = controller
        self.presentation = presentation
        self.forceReducedMotion = forceReducedMotion
        self.resultSummary = resultSummary
        self.gameplayHost = gameplayHost
        self.gameplayControls = gameplayControls
    }

    private var reducesMotion: Bool { reduceMotion || forceReducedMotion }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Each page's ShellHeading is its one heading; the title's
                // name repeats above every page.
                Text(controller.flow.title.displayName)
                    .font(.largeTitle.bold())
                if showsGameplayHost {
                    gameplayHost()
                }
                if controller.hasPersistence {
                    Text(controller.isSaving ? "Saving local data…" : (controller.persistenceMessage == nil && controller.persistenceReady ? "Local data saved" : "Local data needs attention"))
                        .accessibilityIdentifier("save.status")
                    if let message = controller.persistenceMessage {
                        Text(message).accessibilityIdentifier("save.message")
                        if controller.recoveryRequired {
                            ShellActionButton("Use recovered save", id: "save.recover", action: controller.acknowledgeRecovery)
                        } else {
                            ShellActionButton("Retry local data", id: "save.retry", action: controller.retryPersistence)
                        }
                    }
                    if !controller.progress.completedLevels.isEmpty {
                        Text("Completed levels: \(controller.progress.completedLevels.count)").accessibilityIdentifier("save.progress")
                    }
                }
                content
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("shell.scroll")
        .background(Color(.systemGroupedBackground))
        .overlay(alignment: .top) {
            // The page scrolls behind the status bar; without a backdrop its
            // text runs into the clock, which the audit reports as text with
            // no accessibility element (S-8). A zero-height strip at the top
            // of the safe area extends its background up over the bar.
            Color.clear
                .frame(height: 0)
                .background(Color(.systemGroupedBackground).ignoresSafeArea(edges: .top))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .sheet(isPresented: $showingSettings) {
            // UIKit presents the sheet at the process's text size, so a size
            // set on the title's root view reaches it only through here.
            SharedShellSettingsView(controller: controller, presentation: presentation)
                .dynamicTypeSize(dynamicTypeSize)
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
        .onChange(of: page) { _, _ in
            // A page change removes the control that has keyboard focus. Left
            // alone, Full Keyboard Access keeps its highlight on the removed
            // control whenever nothing takes its place, so ask the focus system
            // to choose again once the new page is laid out. VoiceOver is told
            // the screen changed.
            UIAccessibility.post(notification: .screenChanged, argument: nil)
            DispatchQueue.main.async {
                guard let window = UIApplication.shared.connectedScenes
                    .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first,
                      let focus = UIFocusSystem.focusSystem(for: window) else { return }
                focus.requestFocusUpdate(to: window)
                focus.updateFocusIfNeeded()
            }
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
                    .disabled(!controller.persistenceReady || controller.recoveryRequired)
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
            if let summary = resultSummary() {
                Text(summary).accessibilityIdentifier("shell.result.summary")
            }
            ShellActionButton(outcome == .success ? presentation.successRetryLabel : presentation.retryLabel,
                              id: "shell.result.retry", prominent: true, action: controller.restart)
            ShellActionButton("Back to menu", id: "shell.result.menu", action: controller.returnToMenu)
        case .loadFailed(_, let message):
            ShellHeading("Unable to start", id: "shell.load-error")
            Text(message)
            ShellActionButton("Try again", id: "shell.load.retry", prominent: true, action: controller.restart)
            ShellActionButton("Back to menu", id: "shell.menu.back", action: controller.returnToMenu)
        }
    }

    /// The page the flow state shows; requests, pause reasons and outcomes do not change it.
    private var page: String {
        switch controller.flow.state {
        case .splash: return "splash"
        case .menu: return "menu"
        case .loading: return "loading"
        case .playing: return "playing"
        case .paused: return "paused"
        case .result: return "result"
        case .loadFailed: return "loadFailed"
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
    #if DEBUG
    @Environment(\.shellDiagnosticAction) private var diagnosticAction
    #endif

    public init(_ title: String, id: String, prominent: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.identifier = id
        self.prominent = prominent
        self.action = action
    }

    public var body: some View {
        Button {
            #if DEBUG
            diagnosticAction?(identifier)
            #endif
            action()
        } label: {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.primary)
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
    @State private var confirmation: LocalDataAction?
    @State private var exportDocument: SaveExportDocument?
    @State private var showingExporter = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Sound effects", isOn: Binding(get: { controller.flow.settings.soundEnabled },
                        set: { controller.updateSettings(sound: $0) }))
                        .accessibilityIdentifier("settings.sound")
                    Toggle("Music", isOn: Binding(get: { controller.flow.settings.musicEnabled },
                        set: { controller.updateSettings(music: $0) }))
                        .accessibilityIdentifier("settings.music")
                    Toggle("Haptics", isOn: Binding(get: { controller.flow.settings.hapticsEnabled },
                        set: { controller.updateSettings(haptics: $0) }))
                        .accessibilityIdentifier("settings.haptics")
                } header: {
                    SettingsHeader(title: "Feedback")
                }
                .disabled(!controller.persistenceReady || controller.recoveryRequired)
                Section {
                    LabeledContent("Language", value: presentation.languageName)
                    Text(presentation.languageMessage)
                } header: {
                    SettingsHeader(title: "Language")
                }
                Section {
                    Text(controller.hasPersistence ? "Settings and progress are saved on this device. Automatic backup and sync are disabled. Uninstalling the app or losing the device can erase them." : "Settings apply to this session and reset when the app closes.")
                }
                if controller.hasPersistence {
                    Section {
                        if let message = controller.persistenceMessage {
                            Text(message).accessibilityIdentifier("settings.save-message")
                        }
                        Text("Export creates a JSON copy using Files. A provider you choose may transfer that copy. The developer receives nothing. Exported copies remain under your control after reset or deletion.")
                        Button {
                            Task {
                                do {
                                    exportDocument = SaveExportDocument(data: try await controller.exportLocalData())
                                    showingExporter = true
                                } catch { controller.reportExportFailure(error) }
                            }
                        } label: {
                            LocalDataLabel(title: "Export local data", symbol: "square.and.arrow.up")
                        }.accessibilityIdentifier("save.export")
                            .disabled(!controller.persistenceReady || controller.recoveryRequired || controller.isSaving)
                        Button(role: .destructive) { confirmation = .reset } label: {
                            LocalDataLabel(title: "Reset progress", symbol: "arrow.counterclockwise")
                        }.accessibilityIdentifier("save.reset")
                        Button(role: .destructive) { confirmation = .delete } label: {
                            LocalDataLabel(title: "Delete local data", symbol: "trash")
                        }.accessibilityIdentifier("save.delete")
                    } header: {
                        SettingsHeader(title: "Local data")
                    }
                }
            }
            .accessibilityIdentifier("settings.form")
            .navigationTitle("Settings")
            .alert(confirmation == .delete ? "Delete local data?" : "Reset progress?", isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })) {
                Button("Cancel", role: .cancel) { confirmation = nil }
                Button(confirmation == .delete ? "Delete local data" : "Reset progress", role: .destructive) {
                    if confirmation == .delete { controller.deleteLocalData() } else { controller.resetProgress() }
                    confirmation = nil
                }
            } message: {
                Text(confirmation == .delete ? "Remove this title’s progress, preferences and recovery files from this device. Other titles and exported copies are unchanged." : "Remove this title’s progress and close the current session. Keep sound, music, haptics and language preferences. This cannot be undone.")
            }
            .fileExporter(isPresented: $showingExporter, document: exportDocument, contentType: .json, defaultFilename: "\(controller.flow.title.id)-save") { result in
                if case .failure(let error) = result { controller.reportExportFailure(error) }
                exportDocument = nil
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("settings.done")
                        .tint(doneTint)
                }
            }
        }
    }

    /// iOS 18 draws Done in the accent tint on the sheet's bar, which falls
    /// below 4.5:1; iOS 26 draws it in the primary color.
    private var doneTint: Color? {
        if #available(iOS 26, *) { return nil }
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(red: 0.39, green: 0.69, blue: 1, alpha: 1)
                : UIColor(red: 0, green: 0.35, blue: 0.8, alpha: 1)
        })
    }
}

/// Section header text in the primary color: the default secondary header
/// falls below 4.5:1 at body size.
private struct SettingsHeader: View {
    let title: String

    var body: some View {
        Text(title).foregroundStyle(Color.primary)
    }
}

/// A local-data action with primary-colored text: the accent and destructive
/// colors fall below 4.5:1 as text, so they color only the symbol.
private struct LocalDataLabel: View {
    let title: String
    let symbol: String

    var body: some View {
        Label {
            Text(title).foregroundStyle(Color.primary)
        } icon: {
            Image(systemName: symbol)
        }
    }
}

private enum LocalDataAction { case reset, delete }

private struct SaveExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
#endif
