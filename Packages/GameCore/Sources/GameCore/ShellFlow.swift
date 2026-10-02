import Foundation

/// Metadata used by the shell. A title keeps its renderer and game rules outside
/// this contract; later module work can extend the seam when there is evidence.
public struct TitleRegistration: Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let supportedLanguages: [String]

    public init(id: String, displayName: String, supportedLanguages: [String] = ["en"]) {
        precondition(!id.isEmpty && !displayName.isEmpty, "Title metadata must not be empty")
        precondition(!supportedLanguages.isEmpty && supportedLanguages.allSatisfy { !$0.isEmpty },
                     "A title must support at least one language")
        precondition(Set(supportedLanguages).count == supportedLanguages.count,
                     "Supported languages must be unique")
        self.id = id
        self.displayName = displayName
        self.supportedLanguages = supportedLanguages
    }
}

/// Temporary local preferences. There is deliberately no persistence here.
public struct ShellSettings: Equatable, Sendable {
    public let soundEnabled: Bool
    public let musicEnabled: Bool
    public let hapticsEnabled: Bool
    public let language: String

    public init(soundEnabled: Bool = true, musicEnabled: Bool = true,
                hapticsEnabled: Bool = true, language: String = "en") {
        self.soundEnabled = soundEnabled
        self.musicEnabled = musicEnabled
        self.hapticsEnabled = hapticsEnabled
        self.language = language
    }
}

/// Identifies one load and its resulting play session. Replacing this token on
/// retry or restart makes late asynchronous callbacks harmless.
public struct LoadRequest: Equatable, Hashable, Sendable {
    public let id: UUID
    public let titleID: String

    public init(id: UUID = UUID(), titleID: String) {
        self.id = id
        self.titleID = titleID
    }
}

public enum ShellOutcome: Equatable, Sendable {
    case success
    case failure
}

public enum PauseReason: Hashable, Sendable {
    case user
    case applicationInactive
    case audioInterruption
}

public enum ShellState: Equatable, Sendable {
    case splash
    case menu
    case loading(LoadRequest)
    case playing(LoadRequest)
    case paused(LoadRequest, Set<PauseReason>)
    case result(LoadRequest, ShellOutcome)
    case loadFailed(LoadRequest, String)
}

/// A synchronous state machine with no renderer, platform subscription or task
/// ownership. The app owns loading/cancellation and supplies lifecycle events.
/// All rejected actions leave the flow unchanged.
public struct ShellFlow: Equatable, Sendable {
    public let title: TitleRegistration
    public private(set) var state: ShellState = .splash
    public private(set) var settings: ShellSettings

    private var systemPauseReasons: Set<PauseReason> = []
    private var userPauseRequested = false

    public init(title: TitleRegistration) {
        self.title = title
        self.settings = ShellSettings(language: title.supportedLanguages[0])
    }

    public var inputIsActive: Bool {
        if case .playing = state { return true }
        return false
    }

    public var currentRequest: LoadRequest? {
        switch state {
        case .loading(let request), .playing(let request), .paused(let request, _),
             .result(let request, _), .loadFailed(let request, _):
            return request
        case .splash, .menu:
            return nil
        }
    }

    @discardableResult
    public mutating func finishSplash() -> Bool {
        guard state == .splash else { return false }
        state = .menu
        return true
    }

    @discardableResult
    public mutating func start() -> LoadRequest? {
        guard state == .menu else { return nil }
        return beginLoading()
    }

    @discardableResult
    public mutating func completeLoading(_ request: LoadRequest) -> Bool {
        guard case .loading(let current) = state, current == request else { return false }
        state = .playing(request)
        refreshPlaybackState()
        return true
    }

    @discardableResult
    public mutating func failLoading(_ request: LoadRequest, message: String) -> Bool {
        guard case .loading(let current) = state, current == request else { return false }
        state = .loadFailed(request, message)
        return true
    }

    /// Pausing an unfinished load latches a pause for the eventual scene.
    @discardableResult
    public mutating func pause() -> Bool {
        guard hasActiveSession && !userPauseRequested else { return false }
        userPauseRequested = true
        refreshPlaybackState()
        return true
    }

    /// Explicit resumption is possible only after all system blockers clear.
    /// A refused request preserves the user pause instead of scheduling a later
    /// automatic resume when an interruption happens to end.
    @discardableResult
    public mutating func resume() -> Bool {
        guard case .paused = state, systemPauseReasons.isEmpty else { return false }
        userPauseRequested = false
        refreshPlaybackState()
        return true
    }

    public mutating func setApplicationActive(_ active: Bool) {
        if active {
            systemPauseReasons.remove(.applicationInactive)
        } else {
            systemPauseReasons.insert(.applicationInactive)
            if hasActiveSession { userPauseRequested = true }
        }
        refreshPlaybackState()
    }

    public mutating func beginAudioInterruption() {
        systemPauseReasons.insert(.audioInterruption)
        if hasActiveSession { userPauseRequested = true }
        refreshPlaybackState()
    }

    /// `shouldResume` is permission from the audio system, not a command to
    /// restart the game. Both outcomes retain the explicit user-resume latch.
    public mutating func endAudioInterruption(shouldResume: Bool) {
        systemPauseReasons.remove(.audioInterruption)
        refreshPlaybackState()
    }

    @discardableResult
    public mutating func finish(_ request: LoadRequest, outcome: ShellOutcome) -> Bool {
        guard case .playing(let current) = state, current == request else { return false }
        state = .result(request, outcome)
        return true
    }

    @discardableResult
    public mutating func restart() -> LoadRequest? {
        guard currentRequest != nil else { return nil }
        return beginLoading()
    }

    @discardableResult
    public mutating func returnToMenu() -> Bool {
        guard currentRequest != nil else { return false }
        state = .menu
        userPauseRequested = false
        return true
    }

    @discardableResult
    public mutating func updateSettings(_ settings: ShellSettings) -> Bool {
        guard title.supportedLanguages.contains(settings.language) else { return false }
        self.settings = settings
        return true
    }

    private var hasActiveSession: Bool {
        switch state {
        case .loading, .playing, .paused: return true
        case .splash, .menu, .result, .loadFailed: return false
        }
    }

    private mutating func beginLoading() -> LoadRequest {
        let request = LoadRequest(titleID: title.id)
        // A newly requested game clears an old user pause, but cannot bypass a
        // system blocker. Loading begun while blocked must resume explicitly.
        userPauseRequested = !systemPauseReasons.isEmpty
        state = .loading(request)
        return request
    }

    private mutating func refreshPlaybackState() {
        let request: LoadRequest
        switch state {
        case .playing(let current), .paused(let current, _): request = current
        case .splash, .menu, .loading, .result, .loadFailed: return
        }
        var reasons = systemPauseReasons
        if userPauseRequested { reasons.insert(.user) }
        state = reasons.isEmpty ? .playing(request) : .paused(request, reasons)
    }
}
