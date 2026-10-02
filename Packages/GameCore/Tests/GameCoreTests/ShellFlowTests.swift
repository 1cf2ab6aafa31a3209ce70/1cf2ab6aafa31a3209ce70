import XCTest
@testable import GameCore

final class ShellFlowTests: XCTestCase {
    private let title = TitleRegistration(id: "sample", displayName: "Sample", supportedLanguages: ["en", "fr"])

    private func loadingFlow() -> (ShellFlow, LoadRequest) {
        var flow = ShellFlow(title: title)
        XCTAssertTrue(flow.finishSplash())
        let request = flow.start()!
        return (flow, request)
    }

    private func playingFlow() -> (ShellFlow, LoadRequest) {
        var (flow, request) = loadingFlow()
        XCTAssertTrue(flow.completeLoading(request))
        return (flow, request)
    }

    private func assertPaused(_ flow: ShellFlow, request: LoadRequest,
                              reasons: Set<PauseReason>, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(flow.state, .paused(request, reasons), file: file, line: line)
        XCTAssertFalse(flow.inputIsActive, file: file, line: line)
    }

    func testSplashAndMenuRejectPlaybackActionsWithoutChangingState() {
        var flow = ShellFlow(title: title)
        let foreign = LoadRequest(titleID: title.id)
        for expected in [ShellState.splash, .menu] {
            XCTAssertEqual(flow.state, expected)
            XCTAssertNil(flow.restart())
            XCTAssertFalse(flow.returnToMenu())
            XCTAssertFalse(flow.pause())
            XCTAssertFalse(flow.resume())
            XCTAssertFalse(flow.completeLoading(foreign))
            XCTAssertFalse(flow.failLoading(foreign, message: "Unexpected"))
            XCTAssertFalse(flow.finish(foreign, outcome: .success))
            XCTAssertEqual(flow.state, expected)
            XCTAssertFalse(flow.inputIsActive)
            XCTAssertNil(flow.currentRequest)
            if expected == .splash {
                XCTAssertNil(flow.start())
                XCTAssertTrue(flow.finishSplash())
            }
        }
        XCTAssertFalse(flow.finishSplash())
    }

    func testStartAndLoadingCompletionReachPlay() {
        var (flow, request) = loadingFlow()
        XCTAssertEqual(request.titleID, title.id)
        XCTAssertEqual(flow.state, .loading(request))
        XCTAssertEqual(flow.currentRequest, request)
        XCTAssertFalse(flow.inputIsActive)
        XCTAssertNil(flow.start())
        XCTAssertFalse(flow.finish(request, outcome: .success))
        XCTAssertTrue(flow.completeLoading(request))
        XCTAssertEqual(flow.state, .playing(request))
        XCTAssertTrue(flow.inputIsActive)
        XCTAssertFalse(flow.completeLoading(request))
        XCTAssertFalse(flow.failLoading(request, message: "Late failure"))
        XCTAssertFalse(flow.resume())
        XCTAssertEqual(flow.state, .playing(request))
    }

    func testLoadFailureCanRetryWithFreshIdentity() {
        var (flow, request) = loadingFlow()
        XCTAssertTrue(flow.failLoading(request, message: "The sample could not load"))
        XCTAssertEqual(flow.state, .loadFailed(request, "The sample could not load"))
        XCTAssertFalse(flow.inputIsActive)
        XCTAssertFalse(flow.pause())
        XCTAssertFalse(flow.resume())
        XCTAssertNil(flow.start())
        XCTAssertFalse(flow.completeLoading(request))
        XCTAssertFalse(flow.failLoading(request, message: "Duplicate failure"))
        let retry = flow.restart()!
        XCTAssertNotEqual(retry.id, request.id)
        XCTAssertFalse(flow.completeLoading(request))
        XCTAssertFalse(flow.failLoading(request, message: "Stale retry error"))
        XCTAssertTrue(flow.completeLoading(retry))
        XCTAssertEqual(flow.state, .playing(retry))
    }

    func testRestartDuringLoadingRejectsStaleSuccessAndFailure() {
        var (flow, old) = loadingFlow()
        let replacement = flow.restart()!
        XCTAssertNotEqual(old, replacement)
        XCTAssertFalse(flow.completeLoading(old))
        XCTAssertFalse(flow.failLoading(old, message: "Canceled"))
        XCTAssertEqual(flow.state, .loading(replacement))
        XCTAssertTrue(flow.completeLoading(replacement))
    }

    func testReturningToMenuCancelsLoadingAndFailedLoadCallbacks() {
        for failFirst in [false, true] {
            var (flow, old) = loadingFlow()
            if failFirst { XCTAssertTrue(flow.failLoading(old, message: "Error")) }
            XCTAssertTrue(flow.returnToMenu())
            XCTAssertNil(flow.currentRequest)
            XCTAssertFalse(flow.completeLoading(old))
            XCTAssertFalse(flow.failLoading(old, message: "Late error"))
            XCTAssertEqual(flow.state, .menu)
            let current = flow.start()!
            XCTAssertFalse(flow.completeLoading(old))
            XCTAssertTrue(flow.completeLoading(current))
        }
    }

    func testPauseAndExplicitResumeGateInput() {
        var (flow, request) = playingFlow()
        XCTAssertTrue(flow.pause())
        assertPaused(flow, request: request, reasons: [.user])
        XCTAssertFalse(flow.pause())
        XCTAssertFalse(flow.finish(request, outcome: .failure))
        XCTAssertTrue(flow.resume())
        XCTAssertEqual(flow.state, .playing(request))
        XCTAssertTrue(flow.inputIsActive)
    }

    func testPausingDuringLoadingLatchesForRouteLossOrMediaReset() {
        var (flow, request) = loadingFlow()
        XCTAssertTrue(flow.pause())
        XCTAssertFalse(flow.pause())
        XCTAssertFalse(flow.resume())
        XCTAssertEqual(flow.state, .loading(request))
        XCTAssertTrue(flow.completeLoading(request))
        assertPaused(flow, request: request, reasons: [.user])
        XCTAssertTrue(flow.resume())
        XCTAssertTrue(flow.inputIsActive)
    }

    func testBackgroundAndForegroundRequireExplicitResume() {
        var (flow, request) = playingFlow()
        flow.setApplicationActive(false)
        flow.setApplicationActive(false)
        assertPaused(flow, request: request, reasons: [.user, .applicationInactive])
        XCTAssertFalse(flow.resume())
        flow.setApplicationActive(true)
        flow.setApplicationActive(true)
        assertPaused(flow, request: request, reasons: [.user])
        XCTAssertTrue(flow.resume())
        XCTAssertTrue(flow.inputIsActive)
    }

    func testAudioResumePermissionDoesNotAutomaticallyResumePlay() {
        for permission in [false, true] {
            var (flow, request) = playingFlow()
            flow.beginAudioInterruption()
            flow.beginAudioInterruption()
            assertPaused(flow, request: request, reasons: [.user, .audioInterruption])
            XCTAssertFalse(flow.resume())
            flow.endAudioInterruption(shouldResume: permission)
            flow.endAudioInterruption(shouldResume: permission)
            assertPaused(flow, request: request, reasons: [.user])
            XCTAssertTrue(flow.resume())
            XCTAssertTrue(flow.inputIsActive)
        }
    }

    func testOverlappingAudioAndLifecyclePausesRemainIndependent() {
        var (flow, request) = playingFlow()
        flow.beginAudioInterruption()
        flow.setApplicationActive(false)
        assertPaused(flow, request: request, reasons: [.user, .audioInterruption, .applicationInactive])
        flow.setApplicationActive(true)
        assertPaused(flow, request: request, reasons: [.user, .audioInterruption])
        XCTAssertFalse(flow.resume())
        flow.endAudioInterruption(shouldResume: true)
        assertPaused(flow, request: request, reasons: [.user])
        XCTAssertTrue(flow.resume())
    }

    func testRecoveringAudioWhileInactiveCannotResumeUntilForeground() {
        var (flow, request) = playingFlow()
        flow.setApplicationActive(false)
        flow.beginAudioInterruption()
        // The explicit platform recovery path supplies this ended event only
        // after successful session activation. Foreground alone cannot do so.
        flow.endAudioInterruption(shouldResume: true)
        assertPaused(flow, request: request, reasons: [.user, .applicationInactive])
        XCTAssertFalse(flow.resume())
        flow.setApplicationActive(true)
        assertPaused(flow, request: request, reasons: [.user])
        XCTAssertTrue(flow.resume())
    }

    func testLoadCompletingDuringBackgroundNeverActivatesInput() {
        var (flow, request) = loadingFlow()
        flow.setApplicationActive(false)
        XCTAssertTrue(flow.completeLoading(request))
        assertPaused(flow, request: request, reasons: [.user, .applicationInactive])
        XCTAssertFalse(flow.resume())
        flow.setApplicationActive(true)
        assertPaused(flow, request: request, reasons: [.user])
    }

    func testInterruptionEndingBeforeLoadCompletionStillRequiresResume() {
        var (flow, request) = loadingFlow()
        flow.setApplicationActive(false)
        flow.beginAudioInterruption()
        flow.setApplicationActive(true)
        flow.endAudioInterruption(shouldResume: true)
        XCTAssertEqual(flow.state, .loading(request))
        XCTAssertTrue(flow.completeLoading(request))
        assertPaused(flow, request: request, reasons: [.user])
        XCTAssertTrue(flow.resume())
    }

    func testStartingOrRestartingWhileBlockedPreservesPauseLatch() {
        var flow = ShellFlow(title: title)
        flow.setApplicationActive(false)
        flow.beginAudioInterruption()
        XCTAssertTrue(flow.finishSplash())
        let first = flow.start()!
        let current = flow.restart()!
        XCTAssertFalse(flow.completeLoading(first))
        flow.setApplicationActive(true)
        flow.endAudioInterruption(shouldResume: true)
        XCTAssertTrue(flow.completeLoading(current))
        assertPaused(flow, request: current, reasons: [.user])
        XCTAssertTrue(flow.resume())
    }

    func testRestartFromPlayingOrPausedReplacesSessionAndKeepsSystemBlockers() {
        for (userPaused, inactive) in [(false, false), (true, false), (true, true)] {
            var (flow, old) = playingFlow()
            if userPaused { XCTAssertTrue(flow.pause()) }
            if inactive { flow.setApplicationActive(false) }
            let current = flow.restart()!
            XCTAssertNotEqual(current, old)
            XCTAssertFalse(flow.completeLoading(old))
            XCTAssertFalse(flow.finish(old, outcome: .success))
            XCTAssertTrue(flow.completeLoading(current))
            if inactive {
                assertPaused(flow, request: current, reasons: [.user, .applicationInactive])
                XCTAssertFalse(flow.resume())
                flow.setApplicationActive(true)
                assertPaused(flow, request: current, reasons: [.user])
                XCTAssertTrue(flow.resume())
            }
            XCTAssertEqual(flow.state, .playing(current))
            XCTAssertTrue(flow.inputIsActive)
        }
    }

    func testInactiveLaunchDoesNotPauseALaterUserStartedGame() {
        var flow = ShellFlow(title: title)
        flow.setApplicationActive(false)
        flow.beginAudioInterruption()
        flow.setApplicationActive(true)
        flow.endAudioInterruption(shouldResume: false)
        XCTAssertTrue(flow.finishSplash())
        let request = flow.start()!
        XCTAssertTrue(flow.completeLoading(request))
        XCTAssertTrue(flow.inputIsActive)
    }

    func testResultRejectsDuplicateOrStaleCompletionAndCanRestart() {
        for outcome in [ShellOutcome.success, .failure] {
            var (flow, request) = playingFlow()
            XCTAssertTrue(flow.finish(request, outcome: outcome))
            XCTAssertEqual(flow.state, .result(request, outcome))
            XCTAssertFalse(flow.inputIsActive)
            XCTAssertFalse(flow.finish(request, outcome: outcome))
            XCTAssertFalse(flow.pause())
            XCTAssertFalse(flow.resume())
            XCTAssertFalse(flow.completeLoading(request))
            let replacement = flow.restart()!
            XCTAssertTrue(flow.completeLoading(replacement))
            XCTAssertFalse(flow.finish(request, outcome: .success))
            XCTAssertEqual(flow.state, .playing(replacement))
            XCTAssertTrue(flow.finish(replacement, outcome: outcome))
            XCTAssertTrue(flow.returnToMenu())
            XCTAssertEqual(flow.state, .menu)
        }
    }

    func testReturningToMenuClearsUserPauseButPreservesSystemBlockers() {
        var (flow, old) = playingFlow()
        flow.beginAudioInterruption()
        XCTAssertTrue(flow.returnToMenu())
        let request = flow.start()!
        XCTAssertFalse(flow.finish(old, outcome: .success))
        XCTAssertTrue(flow.completeLoading(request))
        assertPaused(flow, request: request, reasons: [.user, .audioInterruption])
        flow.endAudioInterruption(shouldResume: true)
        XCTAssertTrue(flow.resume())
        XCTAssertTrue(flow.pause())
        XCTAssertTrue(flow.returnToMenu())
        let fresh = flow.start()!
        XCTAssertTrue(flow.completeLoading(fresh))
        XCTAssertTrue(flow.inputIsActive)
    }

    func testWrongTitleWithSameUUIDCannotCompleteLoadOrPlay() {
        var (flow, request) = loadingFlow()
        let otherTitle = LoadRequest(id: request.id, titleID: "other")
        XCTAssertFalse(flow.completeLoading(otherTitle))
        XCTAssertFalse(flow.failLoading(otherTitle, message: "Wrong title"))
        XCTAssertTrue(flow.completeLoading(request))
        XCTAssertFalse(flow.finish(otherTitle, outcome: .success))
        XCTAssertEqual(flow.state, .playing(request))
    }

    func testSettingsRemainInMemoryAndRejectUnsupportedLanguage() {
        var flow = ShellFlow(title: title)
        let changed = ShellSettings(soundEnabled: false, musicEnabled: false,
                                    hapticsEnabled: false, language: "fr")
        XCTAssertTrue(flow.updateSettings(changed))
        XCTAssertEqual(flow.settings, changed)
        XCTAssertFalse(flow.updateSettings(ShellSettings(language: "de")))
        XCTAssertEqual(flow.settings, changed)
        XCTAssertTrue(flow.finishSplash())
        let request = flow.start()!
        XCTAssertTrue(flow.completeLoading(request))
        XCTAssertTrue(flow.restart() != nil)
        XCTAssertEqual(flow.settings, changed)
        XCTAssertEqual(ShellFlow(title: title).settings, ShellSettings(language: "en"))
    }

    func testDefaultLanguageUsesTitleRegistration() {
        let frenchTitle = TitleRegistration(id: "fr-title", displayName: "Titre", supportedLanguages: ["fr"])
        XCTAssertEqual(ShellFlow(title: frenchTitle).settings.language, "fr")
    }
}
