#if os(iOS)
import Combine
import Foundation
import GameCore

/// Reusable coordination for one mobile shell session. A title supplies
/// preparation and renderer callbacks; the controller owns flow, cancellation,
/// lifecycle and feedback without depending on a renderer or game rule.
@MainActor
public final class ShellController: ObservableObject {
    public typealias Preparation = @MainActor () async throws -> Void

    @Published public private(set) var flow: ShellFlow
    @Published public private(set) var resumeMessage: String?

    @Published public private(set) var progress = SaveProgress()
    @Published public private(set) var persistenceReady = true
    @Published public private(set) var persistenceMessage: String?
    @Published public private(set) var recoveryRequired = false
    @Published public private(set) var isSaving = false
    public var hasPersistence: Bool { store != nil || initialPersistenceError != nil }
    #if DEBUG
    /// Optional fixture-only observation; never changes an action or its result.
    public var diagnosticEvent: ((String, ShellFlow) -> Void)?
    #endif
    private let initialPersistenceError: String?
    private let store: LocalSaveStore?
    private let recordSuccess: (@MainActor (inout SaveProgress) -> Void)?
    private var generation: UUID?
    private var persistenceEpoch = UUID()
    private var persistenceTask: Task<Void, Never>?
    private var dirty = false
    private var latestStorageOperation = UUID()

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
                setReducedMotion: @escaping @MainActor (Bool) -> Void,
                store: LocalSaveStore? = nil,
                initialPersistenceError: String? = nil,
                recordSuccess: (@MainActor (inout SaveProgress) -> Void)? = nil) {
        let configurationError = store.map { $0.titleID != title.id } == true
            ? "Local data belongs to another title. This title cannot read or change it."
            : initialPersistenceError
        self.store = configurationError == nil ? store : nil
        self.initialPersistenceError = configurationError
        persistenceMessage = configurationError
        self.recordSuccess = recordSuccess
        persistenceReady = store == nil && configurationError == nil
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
        if store != nil && generation == nil && persistenceTask == nil { retryPersistence() }
        _ = flow.finishSplash()
        synchronizeSession()
    }

    public func start() {
        #if DEBUG
        diagnosticEvent?("start.entered", flow)
        defer { diagnosticEvent?("start.returned", flow) }
        #endif
        guard persistenceReady, !recoveryRequired, let request = flow.start() else {
            #if DEBUG
            diagnosticEvent?("start.refused", flow)
            #endif
            return
        }
        #if DEBUG
        diagnosticEvent?("start.accepted", flow)
        #endif
        beginLoading(request)
    }

    public func pause() {
        #if DEBUG
        diagnosticEvent?("pause.entered", flow)
        defer { diagnosticEvent?("pause.returned", flow) }
        #endif
        guard flow.pause() else {
            #if DEBUG
            diagnosticEvent?("pause.refused", flow)
            #endif
            return
        }
        #if DEBUG
        diagnosticEvent?("pause.accepted", flow)
        #endif
        synchronizeSession()
    }

    public func resume() {
        #if DEBUG
        diagnosticEvent?("resume.entered", flow)
        defer { diagnosticEvent?("resume.returned", flow) }
        #endif
        resumeMessage = nil
        if case .paused(_, let reasons) = flow.state, reasons.contains(.audioInterruption) {
            guard feedback?.recoverInterruption() ?? true else {
                #if DEBUG
                diagnosticEvent?("resume.audioRecoveryRefused", flow)
                #endif
                resumeMessage = "Audio is still interrupted. Try Resume again when it is available."
                synchronizeSession()
                return
            }
            #if DEBUG
            diagnosticEvent?("resume.audioRecoveryAllowed", flow)
            #endif
            flow.endAudioInterruption(shouldResume: true)
        }
        if flow.resume() {
            #if DEBUG
            diagnosticEvent?("resume.accepted", flow)
            #endif
            synchronizeSession()
            feedback?.playCue(.selection)
        } else {
            #if DEBUG
            diagnosticEvent?("resume.refused", flow)
            #endif
        }
    }

    public func restart() {
        guard persistenceReady, !recoveryRequired, let request = flow.restart() else { return }
        beginLoading(request)
    }

    public func returnToMenu() {
        guard flow.returnToMenu() else { return }
        loadTask?.cancel()
        loadTask = nil
        resumeMessage = nil
        synchronizeSession()
    }

    /// Synchronous UI actions can finish the currently visible session.
    public func finish(_ outcome: ShellOutcome) {
        guard let request = flow.currentRequest else { return }
        finish(outcome, for: request)
    }

    /// Asynchronous title callbacks must retain their request token so a reset,
    /// deletion or restart cannot award progress to a newer session.
    public func finish(_ outcome: ShellOutcome, for request: LoadRequest) {
        guard flow.currentRequest == request, flow.finish(request, outcome: outcome) else { return }
        if outcome == .success {
            recordSuccess?(&progress)
            persistCurrentState()
        }
        synchronizeSession()
        feedback?.playCue(outcome == .success ? .success : .failure)
    }

    public func setApplicationActive(_ active: Bool) {
        #if DEBUG
        let event = active ? "application.active" : "application.inactive"
        diagnosticEvent?(event + ".entered", flow)
        defer { diagnosticEvent?(event + ".returned", flow) }
        #endif
        if !active { persistCurrentState() }
        feedback?.setForeground(active)
        flow.setApplicationActive(active)
        synchronizeSession()
    }

    public func handleAudioEvent(_ event: ShellAudioEvent) {
        #if DEBUG
        let kind: String
        switch event {
        case .interruptionBegan: kind = "audio.interruptionBegan"
        case .interruptionEnded: kind = "audio.interruptionEnded"
        case .routeDisconnected: kind = "audio.routeDisconnected"
        case .mediaServicesReset: kind = "audio.mediaServicesReset"
        }
        diagnosticEvent?(kind + ".entered", flow)
        defer { diagnosticEvent?(kind + ".returned", flow) }
        #endif
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
        guard persistenceReady, !recoveryRequired else { return false }
        let old = flow.settings
        guard flow.updateSettings(ShellSettings(
            soundEnabled: sound ?? old.soundEnabled,
            musicEnabled: music ?? old.musicEnabled,
            hapticsEnabled: haptics ?? old.hapticsEnabled,
            language: language ?? old.language
        )) else { return false }
        synchronizeSession()
        persistCurrentState()
        return true
    }

    public func setReducedMotion(_ enabled: Bool) { applyReducedMotion(enabled) }

    /// Waits for all meaningful updates queued before this call, including a retry.
    public func flushPersistence() async { await persistenceTask?.value }

    public func retryPersistence() {
        guard let store else { return }
        if generation != nil && dirty { persistCurrentState(); return }
        enqueueStorage { controller, epoch in
            let result = try await store.load()
            guard controller.persistenceEpoch == epoch else { return }
            try controller.accept(result)
        }
    }

    public func acknowledgeRecovery() {
        guard let store, let generation else { return }
        enqueueStorage { controller, epoch in
            let result = try await store.acknowledgeRecovery(generation: generation)
            guard controller.persistenceEpoch == epoch else { return }
            try controller.accept(result)
        }
    }

    public func resetProgress() { destructiveChange(deleteAll: false) }
    public func deleteLocalData() { destructiveChange(deleteAll: true) }

    public func exportLocalData() async throws -> Data {
        await flushPersistence()
        guard let store else { throw LocalSaveError.invalidSnapshot }
        return try await store.exportData()
    }

    public func reportExportFailure(_ error: Error) {
        persistenceMessage = "Export could not finish: \(error.localizedDescription)"
    }

    private func destructiveChange(deleteAll: Bool) {
        guard let store else { return }
        let resetSettings = persistenceReady && !recoveryRequired ? flow.settings : nil
        // Stop renderer/loading before the storage actor invalidates pending writes.
        returnToMenu()
        persistenceEpoch = UUID()
        generation = nil
        dirty = false
        recoveryRequired = false
        persistenceReady = false
        enqueueStorage { controller, epoch in
            let result = try await (deleteAll ? store.deleteLocalData() : store.resetProgress(settings: resetSettings))
            guard controller.persistenceEpoch == epoch else { return }
            try controller.accept(result)
        }
    }

    private func persistCurrentState() {
        guard let store, let generation, persistenceReady, !recoveryRequired else { return }
        dirty = true
        let settings = flow.settings
        let progress = progress
        enqueueStorage { controller, epoch in
            let result = try await store.save(settings: settings, progress: progress, generation: generation)
            // A queued newer snapshot remains authoritative in the controller.
            guard controller.persistenceEpoch == epoch else { return }
            controller.generation = result.generation
        }
    }

    private func accept(_ result: SaveLoadResult) throws {
        guard flow.title.supportedLanguages.contains(result.snapshot.settings.language) else {
            persistenceReady = false
            throw LocalSaveError.invalidSnapshot
        }
        generation = result.generation
        progress = result.snapshot.progress
        _ = flow.updateSettings(result.snapshot.settings)
        recoveryRequired = result.recovered
        persistenceReady = true
        persistenceMessage = result.recovered
            ? "A previous good save was recovered. Review it and choose Use recovered save before continuing."
            : nil
        dirty = false
        synchronizeSession()
    }

    private func enqueueStorage(_ operation: @escaping @MainActor (ShellController, UUID) async throws -> Void) {
        let previous = persistenceTask
        let epoch = persistenceEpoch
        let operationID = UUID()
        latestStorageOperation = operationID
        isSaving = true
        persistenceTask = Task { [weak self] in
            await previous?.value
            guard let self, self.persistenceEpoch == epoch else { return }
            do {
                try await operation(self, epoch)
                guard self.persistenceEpoch == epoch else { return }
                if !self.recoveryRequired { self.persistenceMessage = nil }
            } catch {
                guard self.persistenceEpoch == epoch else { return }
                self.persistenceMessage = "Local data is unavailable: \(error.localizedDescription). Retry, reset progress or delete local data. A failed deletion may have removed some files; unreadable or unsupported data is never replaced automatically."
            }
            // Yielding serial work is complete; later tasks may still be queued.
            if self.latestStorageOperation == operationID {
                self.isSaving = false
                if self.persistenceMessage == nil { self.dirty = false }
            }
        }
    }

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
