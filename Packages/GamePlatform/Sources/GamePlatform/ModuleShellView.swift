#if os(iOS)
import SwiftUI

/// The shared shell around one registered module: menus, settings, saves and
/// results come from the shell; the renderer and play controls from the module.
@MainActor
public struct ModuleShellView<Module: GameModule>: View {
    @ObservedObject private var host: ModuleHost<Module>
    private let forceReducedMotion: Bool

    public init(host: ModuleHost<Module>, forceReducedMotion: Bool = false) {
        self.host = host
        self.forceReducedMotion = forceReducedMotion
    }

    public var body: some View {
        SharedShellView(controller: host.controller, presentation: host.module.presentation,
                        forceReducedMotion: forceReducedMotion) {
            host.module.makeGameplay()
        } gameplayControls: { reducesMotion in
            host.module.makeControls(ModulePlayContext(reducesMotion: reducesMotion,
                                                       pause: host.controller.pause))
        }
    }
}
#endif
