import Foundation
import XCTest
@testable import GamePlatform

@MainActor
final class NotificationAudioObserverTests: XCTestCase {
    func testNotificationSubscriptionHasOneSinkAcrossStartStopAndRestart() {
        let center = NotificationCenter()
        let name = Notification.Name("test.audio.interruption")
        let observer = NotificationAudioObserver(center: center, names: [name]) { notification in
            notification.userInfo?["began"] as? Bool == true ? .interruptionBegan : nil
        }
        var original: [ShellAudioEvent] = []
        var replacement: [ShellAudioEvent] = []
        observer.start { original.append($0) }
        observer.start { replacement.append($0) }
        center.post(name: name, object: nil, userInfo: ["began": true])
        XCTAssertTrue(original.isEmpty)
        XCTAssertEqual(replacement, [.interruptionBegan])
        center.post(name: name, object: nil, userInfo: ["began": false])
        XCTAssertEqual(replacement.count, 1, "Malformed or unrelated payloads are ignored")
        observer.stop()
        observer.stop()
        center.post(name: name, object: nil, userInfo: ["began": true])
        XCTAssertEqual(replacement.count, 1)
        observer.start { replacement.append($0) }
        center.post(name: name, object: nil, userInfo: ["began": true])
        XCTAssertEqual(replacement, [.interruptionBegan, .interruptionBegan])
    }

    func testObserverDeallocationRemovesItsSubscription() {
        let center = NotificationCenter()
        let name = Notification.Name("test.audio.route")
        var events: [ShellAudioEvent] = []
        var observer: NotificationAudioObserver? = NotificationAudioObserver(center: center, names: [name]) { _ in
            .routeDisconnected
        }
        let released = WeakObserverReference(observer)
        observer?.start { events.append($0) }
        center.post(name: name, object: nil)
        XCTAssertEqual(events, [.routeDisconnected])
        observer = nil
        XCTAssertNil(released.value)
        center.post(name: name, object: nil)
        XCTAssertEqual(events, [.routeDisconnected])
    }
}

private final class WeakObserverReference {
    weak var value: NotificationAudioObserver?
    init(_ value: NotificationAudioObserver?) { self.value = value }
}
