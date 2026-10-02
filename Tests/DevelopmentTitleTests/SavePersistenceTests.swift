import Foundation
import GameCore
import GamePlatform
import XCTest
@testable import DevelopmentTitle

final class SavePersistenceTests: XCTestCase {
    @MainActor
    func testIncompatibleStoreInjectionFailsClosedWithoutChangingFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LocalSaveStore(titleID: "another-title", root: root)
        let original = try await store.load()
        _ = try await store.save(settings: ShellSettings(soundEnabled: false), progress: SaveProgress(completedLevels: ["practice"]), generation: original.generation)
        let file = store.directory.appendingPathComponent("save.json")
        let bytes = try Data(contentsOf: file)
        let model = ShellModel(feedback: nil, store: store, preparation: { await Task.yield() })
        model.controller.finishSplash()
        model.controller.retryPersistence()
        model.controller.start()
        model.controller.resetProgress()
        model.controller.deleteLocalData()
        await model.controller.flushPersistence()
        XCTAssertFalse(model.controller.persistenceReady)
        XCTAssertTrue(model.controller.hasPersistence)
        XCTAssertNotNil(model.controller.persistenceMessage)
        XCTAssertEqual(model.controller.flow.state, .menu)
        XCTAssertFalse(model.controller.updateSettings(sound: false))
        XCTAssertEqual(try Data(contentsOf: file), bytes)

        let languageStore = try LocalSaveStore(titleID: "development-practice", root: root,
                                               defaultSettings: ShellSettings(language: "fr"),
                                               supportedLanguages: ["en", "fr"])
        let languageInitial = try await languageStore.load()
        _ = try await languageStore.save(settings: languageInitial.snapshot.settings,
                                         progress: languageInitial.snapshot.progress,
                                         generation: languageInitial.generation)
        let languageFile = languageStore.directory.appendingPathComponent("save.json")
        let languageBytes = try Data(contentsOf: languageFile)
        let incompatibleLanguage = ShellModel(feedback: nil, store: languageStore, preparation: { await Task.yield() })
        incompatibleLanguage.controller.finishSplash()
        await incompatibleLanguage.controller.flushPersistence()
        XCTAssertFalse(incompatibleLanguage.controller.persistenceReady)
        XCTAssertFalse(incompatibleLanguage.controller.updateSettings(sound: false))
        incompatibleLanguage.controller.start()
        XCTAssertEqual(incompatibleLanguage.controller.flow.state, .menu)
        XCTAssertEqual(try Data(contentsOf: languageFile), languageBytes)
    }

    @MainActor
    func testSettingsProgressAndDuplicateResultsSurviveControllerRelaunch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LocalSaveStore(titleID: "development-practice", root: root)
        let model = ShellModel(feedback: nil, store: store, preparation: { await Task.yield() })
        model.controller.finishSplash()
        await model.controller.flushPersistence()
        XCTAssertTrue(model.controller.updateSettings(sound: false, music: false))
        model.controller.start()
        await waitUntil { model.controller.flow.inputIsActive }
        model.controller.finish(.success)
        model.controller.finish(.success)
        await model.controller.flushPersistence()
        let saved = try await store.load()
        XCTAssertEqual(saved.snapshot.progress.completedLevels, ["practice"])
        XCTAssertEqual(saved.snapshot.progress.bestScores["practice"], 1)
        XCTAssertEqual(saved.snapshot.progress.unlockedLevels, ["practice-complete"])
        let relaunched = ShellModel(feedback: nil, store: try LocalSaveStore(titleID: "development-practice", root: root), preparation: { await Task.yield() })
        relaunched.controller.finishSplash()
        await relaunched.controller.flushPersistence()
        XCTAssertFalse(relaunched.controller.flow.settings.soundEnabled)
        XCTAssertEqual(relaunched.controller.progress, saved.snapshot.progress)
        let export = try await relaunched.controller.exportLocalData()
        XCTAssertEqual(try JSONDecoder().decode(SaveSnapshot.self, from: export).progress, saved.snapshot.progress)
    }

    @MainActor
    func testResetAndDeleteInvalidatePendingResultAndKeepOtherTitle() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let other = try LocalSaveStore(titleID: "other-title", root: root)
        let otherState = try await other.load()
        _ = try await other.save(settings: ShellSettings(soundEnabled: false), progress: SaveProgress(completedLevels: ["practice"]), generation: otherState.generation)
        let store = try LocalSaveStore(titleID: "development-practice", root: root)
        let model = ShellModel(feedback: nil, store: store, preparation: { await Task.yield() })
        model.controller.finishSplash()
        await model.controller.flushPersistence()
        model.controller.updateSettings(sound: false)
        model.controller.start()
        await waitUntil { model.controller.flow.inputIsActive }
        let staleRequest = try XCTUnwrap(model.controller.flow.currentRequest)
        model.controller.finish(.success)
        model.controller.updateSettings(music: false)
        model.controller.resetProgress()
        await model.controller.flushPersistence()
        XCTAssertEqual(model.controller.flow.state, .menu)
        XCTAssertTrue(model.controller.progress.completedLevels.isEmpty)
        XCTAssertFalse(model.controller.flow.settings.soundEnabled)
        XCTAssertFalse(model.controller.flow.settings.musicEnabled)
        model.controller.deleteLocalData()
        await model.controller.flushPersistence()
        XCTAssertTrue(model.controller.flow.settings.soundEnabled)
        XCTAssertTrue(model.controller.progress.completedLevels.isEmpty)
        model.controller.start()
        await waitUntil { model.controller.flow.inputIsActive }
        model.controller.finish(.success, for: staleRequest)
        XCTAssertTrue(model.controller.flow.inputIsActive)
        XCTAssertTrue(model.controller.progress.completedLevels.isEmpty)
        let otherReloaded = try await other.load()
        XCTAssertEqual(otherReloaded.snapshot.progress.completedLevels, ["practice"])
    }

    @MainActor
    func testRecoveryRequiresAcknowledgementAndFutureDataBlocksPlay() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LocalSaveStore(titleID: "development-practice", root: root)
        let initial = try await store.load()
        let first = try await store.save(settings: ShellSettings(soundEnabled: false), progress: SaveProgress(completedLevels: ["practice"]), generation: initial.generation)
        _ = try await store.save(settings: first.snapshot.settings, progress: first.snapshot.progress, generation: first.generation)
        let current = store.directory.appendingPathComponent("save.json")
        try Data("damaged".utf8).write(to: current)
        let model = ShellModel(feedback: nil, store: store, preparation: { await Task.yield() })
        model.controller.finishSplash()
        await model.controller.flushPersistence()
        XCTAssertTrue(model.controller.recoveryRequired)
        model.controller.start()
        XCTAssertEqual(model.controller.flow.state, .menu)
        XCTAssertEqual(try Data(contentsOf: current), Data("damaged".utf8))
        model.controller.acknowledgeRecovery()
        await model.controller.flushPersistence()
        XCTAssertFalse(model.controller.recoveryRequired)
        XCTAssertFalse(model.controller.flow.settings.soundEnabled)
        let future = Data("{\"schemaVersion\":999,\"titleID\":\"development-practice\"}".utf8)
        try future.write(to: current)
        let futureModel = ShellModel(feedback: nil, store: try LocalSaveStore(titleID: "development-practice", root: root), preparation: { await Task.yield() })
        futureModel.controller.finishSplash()
        await futureModel.controller.flushPersistence()
        XCTAssertFalse(futureModel.controller.persistenceReady)
        futureModel.controller.start()
        XCTAssertEqual(futureModel.controller.flow.state, .menu)
        XCTAssertNotNil(futureModel.controller.persistenceMessage)
        XCTAssertEqual(try Data(contentsOf: current), future)
    }

    func testNativeProtectionAndBackupExclusionOnCommittedFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LocalSaveStore(titleID: "attributes-proof", root: root)
        let loaded = try await store.load()
        let first = try await store.save(settings: loaded.snapshot.settings, progress: loaded.snapshot.progress, generation: loaded.generation)
        _ = try await store.save(settings: first.snapshot.settings, progress: first.snapshot.progress, generation: first.generation)
        for url in [store.directory, store.directory.appendingPathComponent("save.json"), store.directory.appendingPathComponent("save.previous.json")] {
            XCTAssertEqual(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let rawProtection = (attributes[.protectionKey] as? FileProtectionType)?.rawValue
                ?? attributes[.protectionKey] as? String
            #if targetEnvironment(simulator)
            if let rawProtection {
                XCTAssertEqual(rawProtection, FileProtectionType.completeUntilFirstUserAuthentication.rawValue)
            } else {
                let limitation = XCTAttachment(string: "Simulator omits file protection metadata for \(url.lastPathComponent). Backup exclusion is verified; physical data protection is not certified by this run.")
                limitation.lifetime = .keepAlways
                add(limitation)
            }
            #else
            XCTAssertEqual(rawProtection, FileProtectionType.completeUntilFirstUserAuthentication.rawValue)
            #endif
        }
    }

    /// Root validation runs this twice around a simulator shutdown/boot. The
    /// dedicated marker distinguishes preparation from restoration; it never
    /// touches the title used by players or UI tests.
    func testSimulatorRestartPersistence() async throws {
        let root = try LocalSaveStore.applicationSupportRoot().appendingPathComponent("epic04-restart-proof", isDirectory: true)
        let marker = root.appendingPathComponent("prepared.marker")
        let store = try LocalSaveStore(titleID: "restart-proof", root: root)
        if FileManager.default.fileExists(atPath: marker.path) {
            let saved = try await store.load()
            XCTAssertFalse(saved.snapshot.settings.soundEnabled)
            XCTAssertEqual(saved.snapshot.progress.completedLevels, ["practice"])
            XCTAssertEqual(saved.snapshot.progress.bestScores["practice"], 7)
            try FileManager.default.removeItem(at: root)
        } else {
            let initial = try await store.load()
            _ = try await store.save(settings: ShellSettings(soundEnabled: false), progress: SaveProgress(completedLevels: ["practice"], bestScores: ["practice": 7]), generation: initial.generation)
            try Data("prepared".utf8).write(to: marker)
        }
    }

    @MainActor
    private func waitUntil(_ predicate: @MainActor () -> Bool) async {
        for _ in 0..<500 {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Expected shell state was not reached")
    }
}
