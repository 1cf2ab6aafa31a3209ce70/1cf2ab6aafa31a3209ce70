import GameCore
import SwiftUI

/// Version 1 of the title registration contract, provisional until Spike 11
/// confirms that a terrain title fits it. A title target registers exactly one
/// module at compile time; there is no runtime discovery or type erasure.
///
/// The module owns its rules, level decoding, renderer, hit testing and
/// accessible play controls. The shared shell owns menus, lifecycle pauses,
/// preferences, feedback and local saves, and never sees a renderer type.
@MainActor
public protocol GameModule: AnyObject {
    associatedtype Session: ModuleSession
    associatedtype Gameplay: View
    associatedtype Controls: View

    /// Source registration version, independent of content and save schema
    /// versions. The host refuses to prepare a version it does not support.
    var contractVersion: Int { get }
    /// Stable title identity. Its ID names the save namespace and matches the
    /// title's bundled catalog.
    var title: TitleRegistration { get }
    /// Title-authored copy for the shared menus and result pages.
    var presentation: ShellPresentation { get }
    /// Shown when preparation fails; the shell then offers retry and the menu.
    var loadFailureMessage: String { get }
    /// The retained session. It decodes and validates the selected level in
    /// `prepare(for:)` and creates fresh rule state in `begin(for:)`.
    var session: Session { get }
    /// The renderer view. The module retains its scene across view updates.
    func makeGameplay() -> Gameplay
    /// Accessible play controls, shown only while a session is active.
    func makeControls(_ context: ModulePlayContext) -> Controls
    func setReducedMotion(_ enabled: Bool)
}

extension GameModule {
    public var contractVersion: Int { 1 }
    public var loadFailureMessage: String { "This level could not be loaded. Try again, or return to the menu." }
}

/// What the shell lends to play controls. Controls end a session through their
/// module session, so every outcome carries the request it belongs to.
public struct ModulePlayContext {
    public let reducesMotion: Bool
    public let pause: @MainActor () -> Void

    public init(reducesMotion: Bool, pause: @escaping @MainActor () -> Void) {
        self.reducesMotion = reducesMotion
        self.pause = pause
    }
}

/// One title-owned play session, reused across requests. The shell calls
/// `prepare(for:)` while loading and `begin(for:)` only when that request is
/// still current. It drops outcomes for any request but the current one.
@MainActor
public protocol ModuleSession: AnyObject {
    /// True only while the shell accepts gameplay input.
    var playing: Bool { get set }
    /// Delivered at registration and again whenever a preference changes.
    var settings: ShellSettings { get set }
    /// Set by the host at registration, before any request is prepared.
    var outcomeHandler: ((ShellOutcome, LoadRequest) -> Void)? { get set }
    /// Decode and validate the level for this request. A thrown error shows the
    /// module's load-failure message. Check cancellation before replacing any
    /// staged state, so a superseded load cannot erase a newer one.
    func prepare(for request: LoadRequest) async throws
    /// Create fresh rule state for the prepared request.
    func begin(for request: LoadRequest)
    /// End the active session as a failure, for example from an End control.
    func fail()
    /// Record a success in title-scoped progress, by stable level ID.
    func recordSuccess(in progress: inout SaveProgress)
    /// Saved progress, delivered at registration, after loading and after each
    /// change, so the session can choose a level. Optional.
    func progressDidChange(_ progress: SaveProgress)
    /// One line the result page shows under the outcome message, such as a
    /// score, read when the page draws. Optional; nil shows nothing.
    var resultSummary: String? { get }
}

extension ModuleSession {
    public func progressDidChange(_ progress: SaveProgress) {}
    public var resultSummary: String? { nil }
}
