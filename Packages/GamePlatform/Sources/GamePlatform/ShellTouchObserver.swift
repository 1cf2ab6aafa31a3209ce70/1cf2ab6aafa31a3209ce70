#if DEBUG && os(iOS)
import ObjectiveC
import UIKit

/// Fixture-only touch-phase observation for missed-action diagnostics. It
/// reports a touch's arrival phases before the window dispatches the event and
/// never alters, delays, consumes or participates in touch handling.
@MainActor
enum ShellTouchObserver {
    private static var installed = false
    private static var handler: ((UITouch.Phase) -> Void)?

    /// Only a validated UI-test journal installs this; ordinary launches never do.
    static func install(_ handler: @escaping (UITouch.Phase) -> Void) {
        self.handler = handler
        guard !installed,
              let original = class_getInstanceMethod(UIWindow.self, #selector(UIWindow.sendEvent(_:))),
              let observed = class_getInstanceMethod(UIWindow.self, #selector(UIWindow.gamecoreFixtureSendEvent(_:)))
        else { return }
        method_exchangeImplementations(original, observed)
        installed = true
    }

    fileprivate static func observe(_ event: UIEvent) {
        guard event.type == .touches, let handler, let touches = event.allTouches else { return }
        for touch in touches where touch.phase == .began || touch.phase == .ended || touch.phase == .cancelled {
            handler(touch.phase)
        }
    }
}

extension UIWindow {
    /// After the exchange this selector names the original implementation.
    @objc fileprivate func gamecoreFixtureSendEvent(_ event: UIEvent) {
        ShellTouchObserver.observe(event)
        gamecoreFixtureSendEvent(event)
    }
}
#endif
