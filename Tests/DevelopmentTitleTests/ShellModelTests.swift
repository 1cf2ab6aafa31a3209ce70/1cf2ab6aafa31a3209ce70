import GameCore
import GamePlatform
import SwiftUI
import UIKit
import XCTest
@testable import DevelopmentTitle

final class ShellModelTests: XCTestCase {
    @MainActor
    func testStableSceneAcrossPauseRotationRestartAndResults() async {
        let model = immediateModel()
        let scene = model.scene
        model.controller.finishSplash()
        model.controller.start()
        await waitUntil { model.controller.flow.inputIsActive }
        XCTAssertTrue(model.scene === scene)
        XCTAssertTrue(scene.acceptsGameInput)
        XCTAssertEqual(scene.preparationCount, 1)
        model.controller.pause()
        assertInputStopped(model)
        scene.size = CGSize(width: 600, height: 240)
        model.controller.resume()
        XCTAssertTrue(model.scene === scene)
        XCTAssertTrue(scene.acceptsGameInput)
        model.controller.finish(.success)
        assertInputStopped(model)
        model.controller.restart()
        await waitUntil { model.controller.flow.inputIsActive }
        XCTAssertTrue(model.scene === scene)
        XCTAssertEqual(scene.preparationCount, 2)
        model.controller.finish(.failure)
        assertInputStopped(model)
    }

    @MainActor
    func testInactiveAndAudioEventsRequireExplicitResume() async {
        let model = immediateModel()
        model.controller.finishSplash()
        model.controller.start()
        await waitUntil { model.controller.flow.inputIsActive }
        model.controller.setApplicationActive(false)
        assertInputStopped(model)
        model.controller.handleAudioEvent(.interruptionBegan)
        model.controller.handleAudioEvent(.interruptionEnded(shouldResume: true))
        model.controller.resume()
        assertInputStopped(model)
        model.controller.setApplicationActive(true)
        assertInputStopped(model)
        model.controller.resume()
        XCTAssertTrue(model.scene.acceptsGameInput)
        model.controller.handleAudioEvent(.interruptionBegan)
        assertInputStopped(model)
        model.controller.handleAudioEvent(.interruptionEnded(shouldResume: false))
        assertInputStopped(model)
        model.controller.resume()
        XCTAssertTrue(model.scene.acceptsGameInput)
        model.controller.handleAudioEvent(.routeDisconnected)
        assertInputStopped(model)
        model.controller.resume()
        model.controller.handleAudioEvent(.mediaServicesReset)
        assertInputStopped(model)
    }

    @MainActor
    func testExplicitResumeRecoversMissingAudioEndInSyntheticHarness() async {
        let model = immediateModel()
        model.controller.finishSplash()
        model.controller.start()
        await waitUntil { model.controller.flow.inputIsActive }
        model.controller.handleAudioEvent(.interruptionBegan)
        model.controller.setApplicationActive(false)
        model.controller.setApplicationActive(true)
        assertInputStopped(model)
        model.controller.resume()
        XCTAssertTrue(model.scene.acceptsGameInput)
    }

    @MainActor
    func testCancelledLoadingCannotPrepareSceneOrReactivateInput() async {
        let gate = PreparationGate()
        let model = ShellModel(feedback: nil, preparation: { try await gate.prepare() })
        model.controller.finishSplash()
        model.controller.start()
        await waitUntil { gate.pending.count == 1 }
        assertInputStopped(model)
        model.controller.returnToMenu()
        gate.succeed(0)
        await waitUntil { gate.completedCount == 1 }
        XCTAssertEqual(model.controller.flow.state, .menu)
        XCTAssertEqual(model.scene.preparationCount, 0)
        assertInputStopped(model)
    }

    @MainActor
    func testRestartIgnoresStaleLoadAndBackgroundCompletionStaysPaused() async {
        let gate = PreparationGate()
        let model = ShellModel(feedback: nil, preparation: { try await gate.prepare() })
        model.controller.finishSplash()
        model.controller.start()
        await waitUntil { gate.pending.count == 1 }
        let oldRequest = model.controller.flow.currentRequest
        model.controller.restart()
        await waitUntil { gate.pending.count == 2 }
        XCTAssertNotEqual(model.controller.flow.currentRequest, oldRequest)
        gate.succeed(0)
        await waitUntil { gate.completedCount == 1 }
        XCTAssertEqual(model.scene.preparationCount, 0)
        assertInputStopped(model)
        model.controller.setApplicationActive(false)
        gate.succeed(1)
        await waitUntil { model.scene.preparationCount == 1 }
        assertInputStopped(model)
        model.controller.setApplicationActive(true)
        assertInputStopped(model)
        model.controller.resume()
        XCTAssertTrue(model.scene.acceptsGameInput)
    }

    @MainActor
    func testLoadingErrorCanRetryAndSettingsRemainInMemory() async {
        let gate = PreparationGate()
        let model = ShellModel(feedback: nil, preparation: { try await gate.prepare() })
        model.controller.finishSplash()
        model.controller.updateSettings(sound: false, music: false, haptics: false)
        model.controller.start()
        await waitUntil { gate.pending.count == 1 }
        gate.fail(0)
        await waitUntil {
            if case .loadFailed = model.controller.flow.state { return true }
            return false
        }
        assertInputStopped(model)
        model.controller.restart()
        await waitUntil { gate.pending.count == 2 }
        gate.succeed(1)
        await waitUntil { model.controller.flow.inputIsActive }
        XCTAssertFalse(model.controller.flow.settings.soundEnabled)
        XCTAssertFalse(model.controller.flow.settings.musicEnabled)
        XCTAssertFalse(model.controller.flow.settings.hapticsEnabled)
        XCTAssertEqual(model.controller.flow.settings.language, "en")
        XCTAssertTrue(immediateModel().controller.flow.settings.soundEnabled)
    }

    @MainActor
    func testTitleCancellationErrorShowsRecoveryWhenShellDidNotCancel() async {
        let model = ShellModel(feedback: nil, preparation: { throw CancellationError() })
        model.controller.finishSplash()
        model.controller.start()
        await waitUntil {
            if case .loadFailed = model.controller.flow.state { return true }
            return false
        }
        assertInputStopped(model)
        model.controller.returnToMenu()
        XCTAssertEqual(model.controller.flow.state, .menu)
    }

    @MainActor
    func testReducedMotionStopsTitleAnimationAndRetainsInput() async {
        let model = immediateModel()
        model.controller.finishSplash()
        model.controller.start()
        await waitUntil { model.controller.flow.inputIsActive }
        model.controller.setReducedMotion(true)
        XCTAssertTrue(model.scene.reducedMotion)
        XCTAssertTrue(model.scene.acceptsGameInput)
        XCTAssertFalse(model.scene.children.contains { $0.hasActions() })
        model.controller.setReducedMotion(false)
        XCTAssertTrue(model.scene.children.contains { $0.hasActions() })
        model.controller.pause()
        XCTAssertFalse(model.scene.children.contains { $0.hasActions() })
        assertInputStopped(model)
    }

    @MainActor
    func testSharedShellHostsIndependentRegistrationAndRendererHooks() async throws {
        let hooks = OtherTitleHooks()
        let title = TitleRegistration(id: "other-title-fixture", displayName: "Other title")
        let controller = ShellController(
            title: title,
            feedback: nil,
            preparation: { await Task.yield() },
            preparationFailureMessage: "Other title could not start",
            prepareSession: { hooks.preparations += 1 },
            setPlaying: { hooks.playing = $0 },
            setReducedMotion: { hooks.reducedMotion = $0 }
        )
        controller.finishSplash()
        controller.setApplicationActive(true)
        controller.start()
        await waitUntil { controller.flow.inputIsActive }
        XCTAssertEqual(controller.flow.currentRequest?.titleID, title.id)
        XCTAssertEqual(hooks.preparations, 1)
        XCTAssertTrue(hooks.playing)

        // This second fixture consumes the same public UI/controller with an
        // ordinary SwiftUI host. It copies no shell, scene or title model code.
        let sharedView = SharedShellView(controller: controller, presentation: otherPresentation,
                                         forceReducedMotion: true) {
            Color.orange.frame(height: 100).accessibilityHidden(true)
                .onAppear { hooks.hostAppearances += 1 }
        } gameplayControls: { reducedMotion in
            Text("Other title action")
                .onAppear {
                    hooks.controlAppearances += 1
                    hooks.controlsUseReducedMotion = reducedMotion
                }
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        let host = UIHostingController(rootView: sharedView)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKeyAndVisible()
        }
        await waitUntil { hooks.hostAppearances > 0 && hooks.reducedMotion }
        XCTAssertTrue(host.view.window === window)

        // The hosted lifecycle may have paused before becoming active; the
        // fixture uses the same explicit-resume policy as a real title.
        controller.setApplicationActive(true)
        controller.resume()
        await waitUntil { hooks.controlAppearances > 0 }
        XCTAssertTrue(hooks.controlsUseReducedMotion)
        XCTAssertTrue(hooks.playing)
        controller.pause()
        XCTAssertFalse(hooks.playing)
        controller.resume()
        XCTAssertTrue(hooks.playing)
        controller.restart()
        await waitUntil { hooks.preparations == 2 && controller.flow.inputIsActive }
        controller.finish(.failure)
        guard case .result(let request, .failure) = controller.flow.state else {
            return XCTFail("Independent title did not reach its own result")
        }
        XCTAssertEqual(request.titleID, title.id)
        XCTAssertFalse(hooks.playing)

        let practice = immediateModel()
        XCTAssertTrue(controller.updateSettings(sound: false))
        XCTAssertFalse(controller.flow.settings.soundEnabled)
        XCTAssertTrue(practice.controller.flow.settings.soundEnabled)
        XCTAssertEqual(practice.controller.flow.state, .splash)
        XCTAssertFalse(practice.scene.acceptsGameInput)
    }

    private var otherPresentation: ShellPresentation {
        ShellPresentation(openingMessage: "Opening other title", menuHeading: "Other title ready",
                          menuMessage: "A second independent registration", startLabel: "Start other title",
                          loadingMessage: "Loading other title", pauseMessage: "Other title paused",
                          audioPauseMessage: "Other title audio paused", restartLabel: "Restart other title",
                          successHeading: "Other title complete", successMessage: "Other title succeeded",
                          failureHeading: "Other title ended", failureMessage: "Other title failed",
                          retryLabel: "Retry other title", languageName: "English",
                          languageMessage: "This fixture supports English")
    }

    @MainActor
    private func immediateModel() -> ShellModel {
        ShellModel(feedback: nil, preparation: { await Task.yield() })
    }

    @MainActor
    private func assertInputStopped(_ model: ShellModel, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(model.controller.flow.inputIsActive, file: file, line: line)
        XCTAssertFalse(model.scene.acceptsGameInput, file: file, line: line)
        XCTAssertFalse(model.scene.isUserInteractionEnabled, file: file, line: line)
        XCTAssertTrue(model.scene.isPaused, file: file, line: line)
    }

    @MainActor
    private func waitUntil(_ predicate: @MainActor () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Asynchronous title preparation did not reach the expected state", file: file, line: line)
    }
}

@MainActor
private final class OtherTitleHooks {
    var preparations = 0
    var playing = false
    var reducedMotion = false
    var hostAppearances = 0
    var controlAppearances = 0
    var controlsUseReducedMotion = false
}

@MainActor
private final class PreparationGate {
    enum Failure: Error { case unavailable }
    private(set) var pending: [CheckedContinuation<Void, Error>?] = []
    private(set) var completedCount = 0

    func prepare() async throws {
        defer { completedCount += 1 }
        try await withCheckedThrowingContinuation { pending.append($0) }
    }

    func succeed(_ index: Int) {
        pending[index]?.resume()
        pending[index] = nil
    }

    func fail(_ index: Int) {
        pending[index]?.resume(throwing: Failure.unavailable)
        pending[index] = nil
    }
}
