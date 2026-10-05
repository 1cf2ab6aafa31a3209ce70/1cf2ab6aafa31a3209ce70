import Foundation
import GameCore
import SwiftUI

/// Source registration version, separate from content/save envelope versions.
/// Each module owns its concrete views; no universal renderer/entity API.
@MainActor
protocol GameModule: ObservableObject {
    associatedtype Session: ModuleSession
    associatedtype Gameplay: View
    associatedtype Controls: View
    var session: Session { get }
    var displayName: String { get }
    var contractVersion: Int { get }
    func makeGameplay() -> Gameplay
    func makeControls() -> Controls
    func setReducedMotion(_ enabled: Bool)
}
extension GameModule {
    var contractVersion: Int { 1 }

}

/// Session behavior is shared; deterministic state and simulation remain title-owned.
@MainActor
protocol ModuleSession: AnyObject {
    var playing: Bool { get set }
    var settings: ShellSettings { get set }
    var outcomeHandler: ((ShellOutcome, LoadRequest) -> Void)? { get set }
    func prepare(for request: LoadRequest) async throws
    func begin(for request: LoadRequest)
    func fail()
    func recordSuccess(in progress: inout SaveProgress)
}
