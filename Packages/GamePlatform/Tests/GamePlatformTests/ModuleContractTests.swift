import Foundation
import GameCore
import SwiftUI
import XCTest
@testable import GamePlatform

/// Contract version 1 driven through the shared controller with a fake module:
/// launch, level load, pause, result, save and relaunch, plus refused loads.
@MainActor
final class ModuleContractTests: XCTestCase {
    struct FakeLoadError: Error {}

    final class FakeSession: ModuleSession {
        var playing = false
        var settings = ShellSettings() { didSet { settingsDeliveries += 1 } }
        var settingsDeliveries = 0
        var outcomeHandler: ((ShellOutcome, LoadRequest) -> Void)?
        var failNextPreparation = false
        private(set) var deliveredProgress: [SaveProgress] = []
        private(set) var prepared: [LoadRequest] = []
        private(set) var begun: [LoadRequest] = []
        private(set) var level: String?

        func prepare(for request: LoadRequest) async throws {
            await Task.yield()
            try Task.checkCancellation()
            if failNextPreparation { failNextPreparation = false; throw FakeLoadError() }
            prepared.append(request)
        }
        func begin(for request: LoadRequest) {
            begun.append(request)
            level = "fake-level-01"
        }
        func succeed() { if let request = begun.last { outcomeHandler?(.success, request) } }
        func fail() { if let request = begun.last { outcomeHandler?(.failure, request) } }
        func recordSuccess(in progress: inout SaveProgress) {
            guard let level else { return }
            _ = progress.recordCompletion(levelID: level, score: 3, unlocks: ["fake-level-02"])
        }
        func progressDidChange(_ progress: SaveProgress) { deliveredProgress.append(progress) }
    }

    final class FakeModule: GameModule {
        let title = TitleRegistration(id: "fake-title", displayName: "Fake title")
        let session = FakeSession()
        var contractVersion = 1
        private(set) var reducedMotion = false
        var presentation: ShellPresentation {
            ShellPresentation(openingMessage: "Opening", menuHeading: "Menu", menuMessage: "Fake module",
                              startLabel: "Start", loadingMessage: "Loading", pauseMessage: "Paused",
                              audioPauseMessage: "Audio paused", restartLabel: "Restart",
                              successHeading: "Done", successMessage: "Recorded", failureHeading: "Ended",
                              failureMessage: "Not recorded", retryLabel: "Retry", languageName: "English",
                              languageMessage: "English only")
        }
        var loadFailureMessage: String { "Fake level could not load" }
        func makeGameplay() -> some View { EmptyView() }
        func makeControls(_ context: ModulePlayContext) -> some View { EmptyView() }
        func setReducedMotion(_ enabled: Bool) { reducedMotion = enabled }
    }

    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("module-contract-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func host(_ module: FakeModule? = nil, titleID: String = "fake-title") throws -> ModuleHost<FakeModule> {
        ModuleHost(module: module ?? FakeModule(), feedback: nil, store: try LocalSaveStore(titleID: titleID, root: root))
    }
    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(3)
        while !condition() && Date() < deadline { await Task.yield() }
        XCTAssertTrue(condition(), "Condition not reached", file: file, line: line)
    }
    private func launch(_ host: ModuleHost<FakeModule>) async {
        host.controller.finishSplash()
        await waitUntil { host.controller.persistenceReady }
    }
    private func play(_ host: ModuleHost<FakeModule>) async {
        host.controller.start()
        await waitUntil { host.controller.flow.inputIsActive }
    }

    func testLaunchLoadPauseResultSaveAndRelaunch() async throws {
        let first = try host()
        let session = first.module.session
        await launch(first)
        XCTAssertEqual(first.controller.flow.state, .menu)
        await play(first)
        let request = try XCTUnwrap(first.controller.flow.currentRequest)
        XCTAssertEqual(session.prepared, [request])
        XCTAssertEqual(session.begun, [request])
        XCTAssertEqual(request.titleID, "fake-title")
        XCTAssertTrue(session.playing)

        first.controller.pause()
        XCTAssertFalse(session.playing)
        first.controller.setApplicationActive(false)
        first.controller.setApplicationActive(true)
        XCTAssertFalse(session.playing, "Returning to the foreground never resumes input")
        first.controller.resume()
        XCTAssertTrue(session.playing)
        first.controller.setReducedMotion(true)
        XCTAssertTrue(first.module.reducedMotion)
        XCTAssertTrue(first.controller.updateSettings(music: false))

        session.succeed()
        XCTAssertEqual(first.controller.flow.state, .result(request, .success))
        XCTAssertFalse(session.playing)
        await first.controller.flushPersistence()
        XCTAssertEqual(first.controller.progress.completedLevels, ["fake-level-01"])

        let relaunched = try host()
        await launch(relaunched)
        XCTAssertEqual(relaunched.controller.progress.completedLevels, ["fake-level-01"])
        XCTAssertEqual(relaunched.controller.progress.bestScores, ["fake-level-01": 3])
        XCTAssertEqual(relaunched.controller.progress.unlockedLevels, ["fake-level-02"])
        XCTAssertFalse(relaunched.controller.flow.settings.musicEnabled)
        XCTAssertFalse(relaunched.module.session.settings.musicEnabled, "Restored settings reach the session")
    }

    /// ADR-010's two additive members keep version 1 behavior when a title
    /// leaves them out: no result line, and one retry label for both outcomes.
    func testResultSummaryAndSuccessLabelDefaultToVersionOneBehavior() {
        let module = FakeModule()
        XCTAssertNil(module.session.resultSummary)
        XCTAssertEqual(module.presentation.successRetryLabel, "Retry")
        let labelled = ShellPresentation(openingMessage: "Opening", menuHeading: "Menu", menuMessage: "Fake module",
                                         startLabel: "Start", loadingMessage: "Loading", pauseMessage: "Paused",
                                         audioPauseMessage: "Audio paused", restartLabel: "Restart",
                                         successHeading: "Done", successMessage: "Recorded", failureHeading: "Ended",
                                         failureMessage: "Not recorded", retryLabel: "Retry", successRetryLabel: "Next",
                                         languageName: "English", languageMessage: "English only")
        XCTAssertEqual(labelled.successRetryLabel, "Next")
        XCTAssertEqual(labelled.retryLabel, "Retry", "The failure page keeps the retry label")
    }

    func testModuleLoadFailureIsRecoverable() async throws {
        let host = try host()
        let session = host.module.session
        await launch(host)
        session.failNextPreparation = true
        host.controller.start()
        await waitUntil {
            if case .loadFailed = host.controller.flow.state { return true }
            return false
        }
        guard case .loadFailed(_, let message) = host.controller.flow.state else { return }
        XCTAssertEqual(message, "Fake level could not load")
        XCTAssertTrue(session.begun.isEmpty)
        XCTAssertFalse(session.playing)
        host.controller.restart()
        await waitUntil { host.controller.flow.inputIsActive }
        XCTAssertEqual(session.begun.count, 1)
        session.fail()
        XCTAssertEqual(host.controller.flow.state, .result(session.begun[0], .failure))
        await host.controller.flushPersistence()
        XCTAssertTrue(host.controller.progress.completedLevels.isEmpty, "A failure records no progress")
        host.controller.returnToMenu()
        XCTAssertEqual(host.controller.flow.state, .menu)
    }

    func testUnsupportedContractVersionFailsBeforePreparation() async throws {
        let module = FakeModule()
        module.contractVersion = 2
        let host = try host(module)
        await launch(host)
        host.controller.start()
        await waitUntil {
            if case .loadFailed = host.controller.flow.state { return true }
            return false
        }
        XCTAssertTrue(module.session.prepared.isEmpty)
        XCTAssertTrue(module.session.begun.isEmpty)
    }

    func testLateAndDuplicateOutcomesCannotReachAnotherSession() async throws {
        let host = try host()
        let session = host.module.session
        await launch(host)
        await play(host)
        let earlier = try XCTUnwrap(host.controller.flow.currentRequest)
        host.controller.restart()
        await waitUntil { host.controller.flow.inputIsActive && host.controller.flow.currentRequest != earlier }
        session.outcomeHandler?(.success, earlier)
        XCTAssertTrue(host.controller.flow.inputIsActive, "An earlier request's outcome is ignored")
        session.succeed()
        session.succeed()
        await host.controller.flushPersistence()
        XCTAssertEqual(host.controller.progress.completedLevels, ["fake-level-01"])
        XCTAssertEqual(session.begun.count, 2)
    }

    func testSettingsDeliveredOnceThenOnlyOnChange() async throws {
        let host = try host()
        let session = host.module.session
        XCTAssertEqual(session.settingsDeliveries, 1)
        await launch(host)
        XCTAssertEqual(session.settingsDeliveries, 1, "Loading equal stored settings does not redeliver")
        XCTAssertTrue(host.controller.updateSettings(haptics: false))
        XCTAssertEqual(session.settingsDeliveries, 2)
        XCTAssertFalse(session.settings.hapticsEnabled)
        XCTAssertFalse(host.controller.updateSettings(language: "xx"), "Unsupported languages are refused")
        XCTAssertEqual(session.settingsDeliveries, 2)
    }

    func testSavedProgressReachesTheSessionAtLaunchAndOnChange() async throws {
        let first = try host()
        XCTAssertEqual(first.module.session.deliveredProgress, [SaveProgress()])
        await launch(first)
        await play(first)
        first.module.session.succeed()
        await first.controller.flushPersistence()
        XCTAssertEqual(first.module.session.deliveredProgress.last?.completedLevels, ["fake-level-01"])
        XCTAssertEqual(first.module.session.deliveredProgress.count, 2, "Equal progress is not redelivered")

        let relaunched = try host()
        await launch(relaunched)
        XCTAssertEqual(relaunched.module.session.deliveredProgress.map(\.completedLevels), [[], ["fake-level-01"]],
                       "A session can choose its level from restored progress before the first load")
    }

    func testAnotherTitlesSaveNamespaceIsRefusedBeforePlay() async throws {
        let host = try host(titleID: "other-title")
        host.controller.finishSplash()
        XCTAssertNotNil(host.controller.persistenceMessage)
        host.controller.start()
        XCTAssertEqual(host.controller.flow.state, .menu)
        XCTAssertTrue(host.module.session.prepared.isEmpty)
    }

    func testReturningToMenuDuringLoadingNeverBeginsTheSession() async throws {
        let host = try host()
        let session = host.module.session
        await launch(host)
        host.controller.start()
        host.controller.returnToMenu()
        for _ in 0..<50 { await Task.yield() }
        XCTAssertTrue(session.begun.isEmpty)
        XCTAssertFalse(session.playing)
        XCTAssertEqual(host.controller.flow.state, .menu)
    }
}
