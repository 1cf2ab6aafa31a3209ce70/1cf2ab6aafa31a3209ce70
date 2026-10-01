import XCTest
@testable import GamePlatform

@MainActor
final class ShellFeedbackControllerTests: XCTestCase {
    func testMediaRequiresForegroundAndExplicitPlay() {
        let (feedback, output, _) = makeFeedback()
        feedback.playCue(.selection)
        XCTAssertTrue(output.sounds.isEmpty)
        feedback.setForeground(true)
        XCTAssertTrue(output.musicRequests.isEmpty)
        feedback.setPlaying(true)
        feedback.setPlaying(true)
        XCTAssertEqual(output.musicRequests, [true])
        feedback.setForeground(false)
        XCTAssertEqual(output.stopCount, 1)
        feedback.setForeground(true)
        XCTAssertEqual(output.musicRequests, [true], "Returning cannot autonomously resume music")
        feedback.setPlaying(true)
        XCTAssertEqual(output.musicRequests, [true, true])
    }

    func testIndependentSettingsImmediatelyMuteExistingOutput() {
        let (feedback, output, _) = makeFeedback()
        feedback.setForeground(true)
        feedback.setPlaying(true)
        feedback.updatePreferences(sound: false, music: true, haptics: true)
        feedback.playCue(.selection)
        XCTAssertEqual(output.stopSoundCount, 1)
        XCTAssertTrue(output.sounds.isEmpty)
        XCTAssertEqual(output.haptics, [.selection])
        XCTAssertEqual(output.musicRequests, [true])
        feedback.updatePreferences(sound: true, music: false, haptics: false)
        feedback.playCue(.success)
        XCTAssertEqual(output.sounds, [.success])
        XCTAssertEqual(output.haptics, [.selection])
        XCTAssertEqual(output.musicRequests, [true, false])
        feedback.updatePreferences(sound: true, music: true, haptics: false)
        XCTAssertEqual(output.musicRequests, [true, false, true])
    }

    func testPlayRequestedWhileInactiveCannotQueuePlaybackForForeground() {
        let (feedback, output, _) = makeFeedback()
        feedback.setPlaying(true)
        feedback.setForeground(true)
        XCTAssertTrue(output.musicRequests.isEmpty)
        feedback.setPlaying(true)
        XCTAssertEqual(output.musicRequests, [true])
        feedback.setForeground(false)
        feedback.setPlaying(true)
        feedback.setForeground(true)
        XCTAssertEqual(output.musicRequests, [true])
        feedback.setPlaying(true)
        XCTAssertEqual(output.musicRequests, [true, true])
    }

    func testUnsupportedHapticsAreOptionalAndDoNotSuppressSound() {
        let (feedback, output, _) = makeFeedback()
        output.supportsHaptics = false
        feedback.setForeground(true)
        feedback.playCue(.failure)
        XCTAssertEqual(output.sounds, [.failure])
        XCTAssertTrue(output.haptics.isEmpty)
    }

    func testPausedResultMayHaveFeedbackButNoMusic() {
        let (feedback, output, _) = makeFeedback()
        feedback.setForeground(true)
        feedback.setPlaying(true)
        feedback.setPlaying(false)
        feedback.playCue(.success)
        XCTAssertEqual(output.stopCount, 1)
        XCTAssertEqual(output.sounds, [.success])
        XCTAssertEqual(output.musicRequests, [true])
    }

    func testInterruptionStopsBeforeCallbackAndNeverAutomaticallyResumes() {
        for shouldResume in [false, true] {
            let (feedback, output, observer) = makeFeedback()
            var received: [ShellAudioEvent] = []
            feedback.startObserving { event in
                if event == .interruptionBegan { XCTAssertEqual(output.stopCount, 1) }
                received.append(event)
            }
            feedback.setForeground(true)
            feedback.setPlaying(true)
            observer.emit(.interruptionBegan)
            feedback.playCue(.selection)
            feedback.setPlaying(true) // A blocked play cannot queue an automatic resume.
            XCTAssertTrue(output.sounds.isEmpty)
            XCTAssertTrue(output.haptics.isEmpty)
            observer.emit(.interruptionEnded(shouldResume: shouldResume))
            feedback.setForeground(true)
            XCTAssertEqual(output.musicRequests, [true])
            XCTAssertEqual(received, [.interruptionBegan, .interruptionEnded(shouldResume: shouldResume)])
            feedback.setPlaying(true)
            XCTAssertEqual(output.musicRequests, [true, true])
        }
    }

    func testForegroundCannotClearMissingInterruptionEnd() {
        let (feedback, output, observer) = makeFeedback()
        feedback.startObserving { _ in }
        feedback.setForeground(true)
        observer.emit(.interruptionBegan)
        feedback.setForeground(false)
        feedback.setForeground(true)
        feedback.setPlaying(true)
        feedback.playCue(.selection)
        XCTAssertTrue(output.musicRequests.isEmpty)
        XCTAssertTrue(output.sounds.isEmpty)
        XCTAssertEqual(output.recoveryCount, 0)
    }

    func testExplicitRecoveryRefusesUnavailableFocusThenPermitsUserResume() {
        let (feedback, output, observer) = makeFeedback()
        var events: [ShellAudioEvent] = []
        feedback.startObserving { events.append($0) }
        feedback.setForeground(true)
        observer.emit(.interruptionBegan)
        output.recoveryAllowed = false
        XCTAssertFalse(feedback.recoverInterruption())
        feedback.setPlaying(true)
        XCTAssertTrue(output.musicRequests.isEmpty)
        XCTAssertEqual(events, [.interruptionBegan])
        output.recoveryAllowed = true
        XCTAssertTrue(feedback.recoverInterruption())
        XCTAssertEqual(output.recoveryCount, 2)
        XCTAssertEqual(events, [.interruptionBegan, .interruptionEnded(shouldResume: true)])
        XCTAssertTrue(output.musicRequests.isEmpty)
        feedback.setPlaying(true)
        XCTAssertEqual(output.musicRequests, [true])
        XCTAssertTrue(feedback.recoverInterruption())
        XCTAssertEqual(output.recoveryCount, 2, "Already recovered does not reacquire focus")
    }

    func testRecoveryCannotAcquireFocusWhileInactive() {
        let (feedback, output, observer) = makeFeedback()
        feedback.startObserving { _ in }
        observer.emit(.interruptionBegan)
        XCTAssertFalse(feedback.recoverInterruption())
        XCTAssertEqual(output.recoveryCount, 0)
    }

    func testDisconnectAndResetPauseWithoutPermanentInterruptionBlocker() {
        for event in [ShellAudioEvent.routeDisconnected, .mediaServicesReset] {
            let (feedback, output, observer) = makeFeedback()
            var received: [ShellAudioEvent] = []
            feedback.startObserving { received.append($0) }
            feedback.setForeground(true)
            feedback.setPlaying(true)
            observer.emit(event)
            XCTAssertEqual(output.stopCount, 1)
            XCTAssertEqual(output.resetCount, event == .mediaServicesReset ? 1 : 0)
            XCTAssertEqual(received, [event])
            XCTAssertEqual(output.musicRequests, [true])
            feedback.setPlaying(true)
            XCTAssertEqual(output.musicRequests, [true, true])
            XCTAssertEqual(output.recoveryCount, 0)
        }
    }

    func testRepeatedObservationUpdatesSinkWithoutDuplicateSubscription() {
        let (feedback, output, observer) = makeFeedback()
        var oldEvents: [ShellAudioEvent] = []
        var newEvents: [ShellAudioEvent] = []
        feedback.startObserving { oldEvents.append($0) }
        feedback.startObserving { newEvents.append($0) }
        XCTAssertEqual(observer.startCount, 1)
        observer.emit(.routeDisconnected)
        XCTAssertTrue(oldEvents.isEmpty)
        XCTAssertEqual(newEvents, [.routeDisconnected])
        feedback.setForeground(true)
        feedback.setPlaying(true)
        feedback.stopObserving()
        observer.emit(.interruptionBegan)
        XCTAssertEqual(newEvents, [.routeDisconnected])
        XCTAssertEqual(output.stopCount, 2)
        feedback.startObserving { newEvents.append($0) }
        XCTAssertEqual(observer.startCount, 2)
        observer.emit(.mediaServicesReset)
        XCTAssertEqual(newEvents.last, .mediaServicesReset)
    }

    private func makeFeedback() -> (ShellFeedbackController, RecordingOutput, RecordingObserver) {
        let output = RecordingOutput()
        let observer = RecordingObserver()
        return (ShellFeedbackController(output: output, observer: observer), output, observer)
    }
}

@MainActor
private final class RecordingOutput: ShellFeedbackOutput {
    var supportsHaptics = true
    var recoveryAllowed = true
    var sounds: [ShellFeedbackCue] = []
    var haptics: [ShellFeedbackCue] = []
    var musicRequests: [Bool] = []
    var stopSoundCount = 0
    var stopCount = 0
    var resetCount = 0
    var recoveryCount = 0
    func playSound(_ cue: ShellFeedbackCue) { sounds.append(cue) }
    func playHaptic(_ cue: ShellFeedbackCue) { haptics.append(cue) }
    func setMusicPlaying(_ playing: Bool) { musicRequests.append(playing) }
    func stopSounds() { stopSoundCount += 1 }
    func stopAll() { stopCount += 1 }
    func resetAudio() { stopCount += 1; resetCount += 1 }
    func recoverAudioSession() -> Bool { recoveryCount += 1; return recoveryAllowed }
}

@MainActor
private final class RecordingObserver: ShellAudioObserving {
    var startCount = 0
    var handler: ((ShellAudioEvent) -> Void)?
    func start(_ handler: @escaping (ShellAudioEvent) -> Void) {
        startCount += 1
        self.handler = handler
    }
    func stop() { handler = nil }
    func emit(_ event: ShellAudioEvent) { handler?(event) }
}
