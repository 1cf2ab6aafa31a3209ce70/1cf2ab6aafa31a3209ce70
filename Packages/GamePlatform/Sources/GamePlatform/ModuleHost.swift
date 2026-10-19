import Combine
import Foundation
import GameCore

/// Registers one module with a shell controller. The host adapts the
/// controller's closures to the module session and keeps no game state.
@MainActor
public final class ModuleHost<Module: GameModule>: ObservableObject {
    /// Registration versions this host prepares. Any other version fails
    /// loading with the module's message; it is never treated as version 1.
    public static var supportedContractVersions: ClosedRange<Int> { 1...1 }

    public let module: Module
    public let controller: ShellController
    private var settingsSubscription: AnyCancellable?

    /// A store must belong to `module.title.id`; the controller refuses another
    /// title's namespace before reading it.
    public init(module: Module, feedback: ShellFeedbackController?,
                store: LocalSaveStore? = nil, storageError: String? = nil) {
        self.module = module
        let bridge = ControllerReference()
        let session = module.session
        let supported = Self.supportedContractVersions.contains(module.contractVersion)
        let controller = ShellController(
            title: module.title,
            feedback: feedback,
            preparation: {
                guard supported else {
                    throw ContentValidationError(message: "Unsupported module contract version")
                }
                // The controller exists before any load; a missing request means
                // the load was superseded and must stay silent.
                guard let request = bridge.value?.flow.currentRequest else { throw CancellationError() }
                try await session.prepare(for: request)
            },
            preparationFailureMessage: module.loadFailureMessage,
            prepareSession: {
                if let request = bridge.value?.flow.currentRequest { session.begin(for: request) }
            },
            setPlaying: { session.playing = $0 },
            setReducedMotion: { module.setReducedMotion($0) },
            store: store,
            initialPersistenceError: storageError,
            recordSuccess: { session.recordSuccess(in: &$0) })
        self.controller = controller
        bridge.value = controller
        session.outcomeHandler = { [weak controller] outcome, request in
            controller?.finish(outcome, for: request)
        }
        // The published initial value delivers settings once; equal values are not resent.
        settingsSubscription = controller.$flow.map(\.settings).removeDuplicates()
            .sink { session.settings = $0 }
    }
}

/// Lets preparation read the controller's current request without retaining it.
@MainActor
private final class ControllerReference {
    weak var value: ShellController?
}
