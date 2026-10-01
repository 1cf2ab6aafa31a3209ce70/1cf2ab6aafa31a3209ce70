import Foundation

/// Notification lifetime is tested on the package host. The iOS adapter supplies
/// Apple's notification names and decodes their platform-specific payloads.
@MainActor
final class NotificationAudioObserver: ShellAudioObserving {
    private let center: NotificationCenter
    private let names: [Notification.Name]
    private let decode: (Notification) -> ShellAudioEvent?
    private var tokens: [NSObjectProtocol] = []
    private var handler: ((ShellAudioEvent) -> Void)?

    init(center: NotificationCenter, names: [Notification.Name],
         decode: @escaping (Notification) -> ShellAudioEvent?) {
        self.center = center
        self.names = names
        self.decode = decode
    }

    func start(_ handler: @escaping (ShellAudioEvent) -> Void) {
        self.handler = handler
        guard tokens.isEmpty else { return }
        tokens = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                // OperationQueue.main delivers this synchronously when already
                // on the main thread, so input is paused before the callback ends.
                MainActor.assumeIsolated {
                    guard let self, let event = self.decode(notification) else { return }
                    self.handler?(event)
                }
            }
        }
    }

    func stop() {
        tokens.forEach(center.removeObserver)
        tokens.removeAll()
        handler = nil
    }

    deinit {
        tokens.forEach(center.removeObserver)
    }
}
