import Foundation

public enum ShellFeedbackCue: Hashable, Sendable {
    case selection
    case success
    case failure
}

public enum ShellAudioEvent: Equatable, Sendable {
    case interruptionBegan
    case interruptionEnded(shouldResume: Bool)
    case routeDisconnected
    case mediaServicesReset
}

/// Owns the shell's optional media output. Gameplay and flow remain in GameCore.
/// System events stop output before reaching the shell; resuming input is always
/// an explicit user action, even when the system recommends resuming audio.
@MainActor
public final class ShellFeedbackController {
    private let output: ShellFeedbackOutput
    private let observer: ShellAudioObserving
    private var onEvent: ((ShellAudioEvent) -> Void)?
    private var observing = false
    private var foreground = false
    private var playing = false
    private var interrupted = false
    private var soundEnabled = true
    private var musicEnabled = true
    private var hapticsEnabled = true
    private var musicRequested = false

    public convenience init() {
        #if os(iOS)
        self.init(output: MobileFeedbackOutput(), observer: makeMobileAudioObserver())
        #else
        self.init(output: SilentFeedbackOutput(), observer: SilentAudioObserver())
        #endif
    }

    init(output: ShellFeedbackOutput, observer: ShellAudioObserving) {
        self.output = output
        self.observer = observer
    }

    public func updatePreferences(sound: Bool, music: Bool, haptics: Bool) {
        soundEnabled = sound
        musicEnabled = music
        hapticsEnabled = haptics
        if !sound { output.stopSounds() }
        reconcileMusic()
    }

    public func setForeground(_ foreground: Bool) {
        self.foreground = foreground
        if !foreground {
            playing = false
            stopOutput()
        }
        reconcileMusic()
    }

    public func setPlaying(_ playing: Bool) {
        self.playing = playing && foreground && !interrupted
        if !playing { stopOutput() }
        reconcileMusic()
    }

    /// Repeated appearance callbacks reuse one observation and replace its sink.
    public func startObserving(onEvent: @escaping (ShellAudioEvent) -> Void) {
        self.onEvent = onEvent
        guard !observing else { return }
        observing = true
        observer.start { [weak self] event in self?.handle(event) }
    }

    public func stopObserving() {
        observer.stop()
        observing = false
        onEvent = nil
        playing = false
        stopOutput()
    }

    public func playCue(_ cue: ShellFeedbackCue) {
        guard foreground, !interrupted else { return }
        if soundEnabled { output.playSound(cue) }
        if hapticsEnabled, output.supportsHaptics { output.playHaptic(cue) }
    }

    /// Used only when the user requests Resume after an interruption whose end
    /// notification was missed during suspension. Refused focus leaves the shell
    /// paused. Successful recovery permits a later explicit setPlaying(true).
    public func recoverInterruption() -> Bool {
        guard interrupted else { return true }
        guard foreground, output.recoverAudioSession() else { return false }
        interrupted = false
        onEvent?(.interruptionEnded(shouldResume: true))
        return true
    }

    private func handle(_ event: ShellAudioEvent) {
        switch event {
        case .interruptionBegan:
            interrupted = true
            playing = false
            stopOutput()
        case .interruptionEnded:
            interrupted = false
            // Never restore playing here, including shouldResume == true.
        case .routeDisconnected:
            playing = false
            stopOutput()
        case .mediaServicesReset:
            playing = false
            output.resetAudio()
            musicRequested = false
        }
        onEvent?(event)
    }

    private func reconcileMusic() {
        let requested = foreground && playing && !interrupted && musicEnabled
        guard requested != musicRequested else { return }
        musicRequested = requested
        output.setMusicPlaying(requested)
    }

    private func stopOutput() {
        output.stopAll()
        musicRequested = false
    }
}

/// A narrow test seam for media policy, not a public sound engine API.
@MainActor
protocol ShellFeedbackOutput: AnyObject {
    var supportsHaptics: Bool { get }
    func playSound(_ cue: ShellFeedbackCue)
    func playHaptic(_ cue: ShellFeedbackCue)
    func setMusicPlaying(_ playing: Bool)
    func stopSounds()
    func stopAll()
    func resetAudio()
    func recoverAudioSession() -> Bool
}

@MainActor
protocol ShellAudioObserving: AnyObject {
    func start(_ handler: @escaping (ShellAudioEvent) -> Void)
    func stop()
}

@MainActor
private final class SilentFeedbackOutput: ShellFeedbackOutput {
    let supportsHaptics = false
    func playSound(_ cue: ShellFeedbackCue) {}
    func playHaptic(_ cue: ShellFeedbackCue) {}
    func setMusicPlaying(_ playing: Bool) {}
    func stopSounds() {}
    func stopAll() {}
    func resetAudio() {}
    func recoverAudioSession() -> Bool { true }
}

@MainActor
private final class SilentAudioObserver: ShellAudioObserving {
    func start(_ handler: @escaping (ShellAudioEvent) -> Void) {}
    func stop() {}
}
