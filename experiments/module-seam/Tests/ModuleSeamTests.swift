import DevelopmentContent
import GameCore
import GamePlatform
import SwiftUI
import XCTest
#if GRID_MODULE
@testable import GridSeam
#else
@testable import TerrainSeam
#endif

@MainActor
final class ModuleSeamTests: XCTestCase {
    final class FakeModule: ObservableObject, GameModule {
        let session = RuleSession(levelID: "block-sample-01")
        let displayName = "Fake"
        var contractVersion = 1
        func makeGameplay() -> some View { EmptyView() }
        func makeControls() -> some View { EmptyView() }
        func setReducedMotion(_ enabled: Bool) { session.reducedMotion = enabled }
    }
    final class IndependentSession: ModuleSession {
        var playing = false
        var settings = ShellSettings() { didSet { settingsCalls += 1 } }
        var settingsCalls = 0
        var outcomeHandler: ((ShellOutcome, LoadRequest) -> Void)?
        var request: LoadRequest?
        func prepare(for request: LoadRequest) async throws { self.request = request }
        func begin(for request: LoadRequest) { self.request = request }
        func fail() { if let request { outcomeHandler?(.failure, request) } }
        func recordSuccess(in progress: inout SaveProgress) { _ = progress.recordCompletion(levelID: "independent-original-level") }
    }
    final class IndependentModule: ObservableObject, GameModule {
        let session = IndependentSession()
        let displayName = "Independent simulation"
        func makeGameplay() -> some View { Text("Independent renderer") }
        func makeControls() -> some View { EmptyView() }
        func setReducedMotion(_ enabled: Bool) { }
    }
    func testIndependentSessionAndSettingsDelivery() async {
        let root = URL(fileURLWithPath: "/unused-original")
        XCTAssertEqual(try? ModuleFixture.root(defaultRoot: root, arguments: []), root)
        for args in [["--module-fixture"], ["--module-fixture", "../unsafe"], ["--module-fixture", UUID().uuidString, "--module-fixture", UUID().uuidString]] {
            XCTAssertThrowsError(try ModuleFixture.root(defaultRoot: root, arguments: args))
        }

        let host = ModuleHost(module: IndependentModule())
        XCTAssertEqual(host.module.session.settingsCalls, 1)
        host.controller.finishSplash(); host.controller.start(); await waitForLoad(host.controller)
        XCTAssertEqual(host.module.session.settingsCalls, 1)
        _ = host.controller.updateSettings(sound: false)
        XCTAssertEqual(host.module.session.settingsCalls, 2)
        let request = host.controller.flow.currentRequest!
        host.module.session.outcomeHandler?(.success, request)
        host.module.session.outcomeHandler?(.success, request)
        XCTAssertEqual(host.controller.progress.completedLevels, ["independent-original-level"])
    }
    private func waitForLoad(_ controller: ShellController) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while case .loading = controller.flow.state, ContinuousClock.now < deadline { await Task.yield() }
        if case .loading = controller.flow.state { XCTFail("Loading did not finish") }
    }
    func testBothSamplesUseValidatedIdentityAndGateInput() async throws {
        for id in ["block-sample-01", "dig-sample-01"] {
            let session = RuleSession(levelID: id)
            let request = LoadRequest(titleID: "development-practice")
            try await session.prepare(for: request); session.begin(for: request)
            var outcomes = 0
            session.outcomeHandler = { outcome, token in XCTAssertEqual(outcome, .success); XCTAssertEqual(token, request); outcomes += 1 }
            let level = try XCTUnwrap(session.level)
            let fixture = FixtureRules.solutionFixture(level: level)
            session.select(index: fixture.inputs[0].action.index)
            XCTAssertTrue(session.inputs.isEmpty)
            session.playing = true
            for input in fixture.inputs { session.select(index: input.action.index) }
            XCTAssertEqual(session.inputs, fixture.inputs)
            XCTAssertEqual(outcomes, 1)
            session.select(index: fixture.inputs[0].action.index)
            XCTAssertEqual(outcomes, 1)
            XCTAssertEqual(session.level?.id, id)
        }
    }
    func testSupersededPreparationCannotReplaceNewSession() async throws {
        let session = RuleSession(levelID: "block-sample-01")
        let catalog = try BundledContent.load()
        let old = LoadRequest(titleID: "development-practice"), current = LoadRequest(titleID: "development-practice")
        var continuation: CheckedContinuation<DevelopmentCatalog, Never>?
        let task = Task { try await session.prepare(for: old, loader: {
            await withCheckedContinuation { continuation = $0 }
        }) }
        while continuation == nil { await Task.yield() }
        try await session.prepare(for: current)
        var canceledLoaderEntered = false
        let canceledBeforeEntry = Task {
            try await session.prepare(for: old, loader: {
                canceledLoaderEntered = true
                return catalog
            })
        }
        canceledBeforeEntry.cancel()
        do {
            try await canceledBeforeEntry.value
            XCTFail("Canceled preparation accepted")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(canceledLoaderEntered)
        session.begin(for: current)
        XCTAssertEqual(session.request, current, "Canceled preparation must preserve the staged current load")
        continuation?.resume(returning: catalog)
        do { try await task.value; XCTFail("Superseded preparation accepted") } catch { }
        session.begin(for: old)
        XCTAssertEqual(session.request, current)
    }
    func testHostRejectsVersionAndLateOutcomes() async {
        let module = FakeModule()
        module.contractVersion = 2
        let host = ModuleHost(module: module)
        host.controller.finishSplash(); host.controller.start()
        await waitForLoad(host.controller)
        if case .loadFailed = host.controller.flow.state { } else { XCTFail("Unsupported registration accepted") }
        XCTAssertNil(module.session.level)
        module.contractVersion = 1
        host.controller.restart(); await waitForLoad(host.controller)
        let old = host.controller.flow.currentRequest!
        host.controller.restart(); await waitForLoad(host.controller)
        module.session.outcomeHandler?(.success, old)
        XCTAssertTrue(host.controller.progress.completedLevels.isEmpty)
        XCTAssertTrue(host.controller.flow.inputIsActive)
        host.controller.returnToMenu()
        module.session.outcomeHandler?(.success, module.session.request!)
        XCTAssertTrue(host.controller.progress.completedLevels.isEmpty)
    }
    func testPauseBackgroundSettingsAndFailure() async {
        let host = ModuleHost(module: FakeModule())
        let controller = host.controller, session = host.module.session
        controller.finishSplash(); controller.start(); await waitForLoad(controller)
        controller.pause(); session.select(index: 1); XCTAssertTrue(session.inputs.isEmpty)
        controller.resume(); controller.setApplicationActive(false)
        session.select(index: 1); XCTAssertTrue(session.inputs.isEmpty)
        controller.setApplicationActive(true); XCTAssertFalse(session.playing)
        controller.resume(); XCTAssertTrue(session.playing)
        _ = controller.updateSettings(sound: false, music: false, haptics: false)
        XCTAssertEqual(session.settings, controller.flow.settings)
        controller.setReducedMotion(true); XCTAssertTrue(session.reducedMotion)
        session.fail(); XCTAssertTrue(controller.progress.completedLevels.isEmpty)
        XCTAssertFalse(session.playing)
    }
    func testActualModulePersistsSelectedLevelAndRestoresSettings() async throws {
        #if GRID_MODULE
        let module = GridModule()
        #else
        let module = TerrainModule()
        #endif
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LocalSaveStore(titleID: "development-practice", root: root)
        let host = ModuleHost(module: module, store: store)
        host.controller.finishSplash(); await host.controller.flushPersistence()
        _ = host.controller.updateSettings(sound: false)
        host.controller.start(); await waitForLoad(host.controller)
        let level = try XCTUnwrap(module.session.level)
        _ = module.makeGameplay(); _ = module.makeControls()
        for input in FixtureRules.solutionFixture(level: level).inputs { module.session.select(index: input.action.index) }
        await host.controller.flushPersistence()
        let saved = try await store.load()
        XCTAssertEqual(saved.snapshot.progress.completedLevels, [level.id])
        XCTAssertFalse(saved.snapshot.settings.soundEnabled)
        let restored = ModuleHost(module: FakeModule(), store: store)
        restored.controller.finishSplash(); await restored.controller.flushPersistence()
        XCTAssertFalse(restored.module.session.settings.soundEnabled)
        // Delete invalidates a retained old outcome token before storage work.
        let old = module.session.request!
        host.controller.deleteLocalData(); await host.controller.flushPersistence()
        module.session.outcomeHandler?(.success, old)
        XCTAssertTrue(host.controller.progress.completedLevels.isEmpty)
    }
}
