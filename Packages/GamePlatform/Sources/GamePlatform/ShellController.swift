#if os(iOS)
import Combine
import GameCore

/// Reusable coordination for one mobile shell session. A title supplies
/// preparation and renderer callbacks; the controller owns flow, cancellation,
/// lifecycle and feedback without depending on a renderer or game rule.
@MainActor
public final class ShellController: ObservableObject {
    public typealias Preparation = @MainActor () async throws -> Void

    @Published public private(set) var flow: ShellFlow
    @Published public private(set) var resumeMessage: String?

    private let feedback: ShellFeedbackController?
    private let preparation: Preparation
    private let preparationFailureMessage: String
    private let prepareSession: @MainActor () -> Void
    private let setPlaying: @MainActor (Bool) -> Void
    private let applyReducedMotion: @MainActor (Bool) -> Void
    private var loadTask: Task<Void, Never>?

    public init(title: TitleRegistration, feedback: ShellFeedbackController?,
                preparation: @escaping Preparation, preparationFailureMessage: String,
                prepareSession: @escaping @MainActor () -> Void,
                setPlaying: @escaping @MainActor (Bool) -> Void,
                setReducedMotion: @escaping @MainActor (Bool) -> Void) {
        self.feedback = feedback
        self.preparation = preparation
        self.preparationFailureMessage = preparationFailureMessage
        self.prepareSession = prepareSession
        self.setPlaying = setPlaying
        self.applyReducedMotion = setReducedMotion
        flow = ShellFlow(title: title)
        feedback?.startObserving { [weak self] event in
            self?.handleAudioEvent(event)
        }
        synchronizeSession()
    }

    deinit { loadTask?.cancel() }

    public func finishSplash() {
        _ = flow.finishSplash()
        synchronizeSession()
    }

    public func start() {
        guard let request = flow.start() else { return }
        beginLoading(request)
    }

    public func pause() {
        guard flow.pause() else { return }
        synchronizeSession()
    }

    public func resume() {
        resumeMessage = nil
        if case .paused(_, let reasons) = flow.state, reasons.contains(.audioInterruption) {
            guard feedback?.recoverInterruption() ?? true else {
                resumeMessage = "Audio is still interrupted. Try Resume again when it is available."
                synchronizeSession()
                return
            }
            flow.endAudioInterruption(shouldResume: true)
        }
        if flow.resume() {
            synchronizeSession()
            feedback?.playCue(.selection)
        }
    }

    public func restart() {
        guard let request = flow.restart() else { return }
        beginLoading(request)
    }

    public func returnToMenu() {
        guard flow.returnToMenu() else { return }
        loadTask?.cancel()
        loadTask = nil
        resumeMessage = nil
        synchronizeSession()
    }

    public func finish(_ outcome: ShellOutcome) {
        guard let request = flow.currentRequest, flow.finish(request, outcome: outcome) else { return }
        synchronizeSession()
        feedback?.playCue(outcome == .success ? .success : .failure)
    }

    public func setApplicationActive(_ active: Bool) {
        feedback?.setForeground(active)
        flow.setApplicationActive(active)
        synchronizeSession()
    }

    public func handleAudioEvent(_ event: ShellAudioEvent) {
        switch event {
        case .interruptionBegan:
            flow.beginAudioInterruption()
        case .interruptionEnded(let shouldResume):
            resumeMessage = nil
            flow.endAudioInterruption(shouldResume: shouldResume)
        case .routeDisconnected, .mediaServicesReset:
            _ = flow.pause()
        }
        synchronizeSession()
    }

    @discardableResult
    public func updateSettings(sound: Bool? = nil, music: Bool? = nil,
                               haptics: Bool? = nil, language: String? = nil) -> Bool {
        let old = flow.settings
        guard flow.updateSettings(ShellSettings(
            soundEnabled: sound ?? old.soundEnabled,
            musicEnabled: music ?? old.musicEnabled,
            hapticsEnabled: haptics ?? old.hapticsEnabled,
            language: language ?? old.language
        )) else { return false }
        synchronizeSession()
        return true
    }

    public func setReducedMotion(_ enabled: Bool) { applyReducedMotion(enabled) }

    private func beginLoading(_ request: LoadRequest) {
        loadTask?.cancel()
        resumeMessage = nil
        synchronizeSession()
        let prepare = preparation
        loadTask = Task { [weak self] in
            do {
                try await prepare()
                guard !Task.isCancelled, let self, self.flow.currentRequest == request else { return }
                self.prepareSession()
                _ = self.flow.completeLoading(request)
                self.synchronizeSession()
            } catch {
                // Only cancellation owned by this shell or a superseded request
                // is silent. Title-originated cancellation still needs recovery.
                guard !Task.isCancelled, let self, self.flow.currentRequest == request else { return }
                _ = self.flow.failLoading(request, message: self.preparationFailureMessage)
                self.synchronizeSession()
            }
        }
    }

    private func synchronizeSession() {
        setPlaying(flow.inputIsActive)
        feedback?.updatePreferences(sound: flow.settings.soundEnabled,
                                    music: flow.settings.musicEnabled,
                                    haptics: flow.settings.hapticsEnabled)
        feedback?.setPlaying(flow.inputIsActive)
    }
}
#endif
