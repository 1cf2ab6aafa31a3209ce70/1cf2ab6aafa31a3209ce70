import XCTest
import GameCore
@testable import GamePlatform

final class LocalSaveStoreTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("local-save-tests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func store(_ title: String = "practice") throws -> LocalSaveStore {
        try LocalSaveStore(titleID: title, root: root)
    }
    private func file(_ name: String, title: String = "practice") -> URL {
        root.appendingPathComponent(title).appendingPathComponent(name)
    }
    private func expect(_ expected: LocalSaveError, _ operation: () async throws -> Void,
                        file: StaticString = #filePath, line: UInt = #line) async {
        do { try await operation(); XCTFail("Expected \(expected)", file: file, line: line) }
        catch { XCTAssertEqual(error as? LocalSaveError, expected, file: file, line: line) }
    }
    private var settings: ShellSettings { ShellSettings(soundEnabled: false, hapticsEnabled: false) }
    private var progress: SaveProgress {
        SaveProgress(completedLevels: ["level-1"], bestScores: ["level-1": 12], unlockedLevels: ["level-2"])
    }
    private func seed(_ store: LocalSaveStore) async throws -> SaveLoadResult {
        let loaded = try await store.load()
        return try await store.save(settings: settings, progress: progress, generation: loaded.generation)
    }

    func testAbsentRoundTripAndFreshStoreRestore() async throws {
        let writer = try store()
        let absent = try await writer.load()
        XCTAssertEqual(absent.snapshot.progress, SaveProgress())
        XCTAssertFalse(absent.recovered)
        let committed = try await seed(writer)
        let restored = try await store().load()
        XCTAssertEqual(restored.snapshot, committed.snapshot)
        XCTAssertEqual(restored.snapshot.settings, settings)
        XCTAssertEqual(restored.snapshot.progress, progress)
    }

    func testAllInterruptedReplacementBoundariesRetainWholePriorOrNewState() async throws {
        for phase in LocalSaveStore.WritePhase.allCases {
            let title = "case-\(String(describing: phase).lowercased())"
            let writer = try store(title)
            let old = try await seed(writer)
            await writer.setInterruption(phase)
            do {
                _ = try await writer.save(settings: ShellSettings(), progress: SaveProgress(), generation: old.generation)
                XCTFail("Interruption should fail the caller")
            } catch { XCTAssertNotNil(error as? LocalSaveError) }
            let restarted = try await store(title).load()
            if phase == .currentPromoted {
                XCTAssertEqual(restarted.snapshot.revision, old.snapshot.revision + 1)
                XCTAssertEqual(restarted.snapshot.progress, SaveProgress())
            } else { XCTAssertEqual(restarted.snapshot, old.snapshot) }
        }
    }

    func testInterruptedFirstWriteNeverAcceptsPendingData() async throws {
        for phase in LocalSaveStore.WritePhase.allCases {
            let title = "first-\(String(describing: phase).lowercased())"
            let writer = try store(title)
            let loaded = try await writer.load()
            await writer.setInterruption(phase)
            do { _ = try await writer.save(settings: settings, progress: progress, generation: loaded.generation) }
            catch { XCTAssertNotNil(error as? LocalSaveError) }
            let restarted = try await store(title).load()
            XCTAssertEqual(restarted.snapshot.progress, phase == .currentPromoted ? progress : SaveProgress())
        }
    }

    func testCorruptCurrentNeedsAcknowledgementAndPreservesDamagedBytesUntilThen() async throws {
        let writer = try store()
        let first = try await seed(writer)
        _ = try await writer.save(settings: ShellSettings(), progress: SaveProgress(), generation: first.generation)
        let damaged = Data("{truncated".utf8)
        try damaged.write(to: file("save.json"))
        let recovery = try await writer.load()
        XCTAssertTrue(recovery.recovered)
        XCTAssertEqual(recovery.snapshot, first.snapshot)
        await expect(.recoveryRequired) {
            _ = try await writer.save(settings: settings, progress: progress, generation: recovery.generation)
        }
        XCTAssertEqual(try Data(contentsOf: file("save.json")), damaged)
        let export = try await writer.exportData()
        XCTAssertEqual(try JSONDecoder().decode(SaveSnapshot.self, from: export), first.snapshot)
        XCTAssertEqual(try Data(contentsOf: file("save.json")), damaged)
        let repaired = try await writer.acknowledgeRecovery(generation: recovery.generation)
        XCTAssertFalse(repaired.recovered)
        XCTAssertEqual(repaired.snapshot.progress, progress)
        let restarted = try await store().load()
        XCTAssertEqual(restarted.snapshot, repaired.snapshot)
    }

    func testMissingCurrentRecoversBackupAndBothCorruptNeverCreateDefaults() async throws {
        let writer = try store()
        let first = try await seed(writer)
        _ = try await writer.save(settings: settings, progress: progress, generation: first.generation)
        try FileManager.default.removeItem(at: file("save.json"))
        let loaded = try await writer.load()
        XCTAssertTrue(loaded.recovered)
        try Data("bad".utf8).write(to: file("save.json"))
        try Data("bad".utf8).write(to: file("save.previous.json"))
        await expect(.corrupt) { _ = try await writer.load() }
        await expect(.corrupt) { _ = try await writer.exportData() }
        XCTAssertEqual(try Data(contentsOf: file("save.json")), Data("bad".utf8))
    }

    func testFutureAndForeignCurrentAndBackupPreserved() async throws {
        for destination in ["save.json", "save.previous.json"] {
            for foreign in [false, true] {
                let title = "protected-\(destination == "save.json" ? "current" : "backup")-\(foreign ? "foreign" : "future")"
                let writer = try store(title)
                let initial = try await seed(writer)
                let value = SaveSnapshot(schemaVersion: foreign ? 2 : 99, titleID: foreign ? "other" : title)
                let bytes = try JSONEncoder().encode(value)
                try bytes.write(to: file(destination, title: title))
                let expected: LocalSaveError = foreign ? .titleMismatch : .futureVersion(99)
                await expect(expected) {
                    _ = try await writer.save(settings: settings, progress: progress, generation: initial.generation)
                }
                if destination == "save.json" {
                    await expect(expected) { _ = try await writer.load() }
                }
                XCTAssertEqual(try Data(contentsOf: file(destination, title: title)), bytes)
            }
        }
    }

    func testOversizedFuturePrimaryAndBackupCannotBeSilentlyReplaced() async throws {
        for destination in ["save.json", "save.previous.json"] {
            let title = destination == "save.json" ? "large-primary" : "large-backup"
            let writer = try store(title)
            let initial = try await seed(writer)
            _ = try await writer.save(settings: settings, progress: progress, generation: initial.generation)
            let huge = Data(("{\"schemaVersion\":99,\"titleID\":\"\(title)\",\"futurePayload\":\"" +
                             String(repeating: "x", count: 1_048_576) + "\"}").utf8)
            try huge.write(to: file(destination, title: title))
            if destination == "save.json" {
                await expect(.oversized) { _ = try await writer.load() }
            }
            await expect(.oversized) {
                _ = try await writer.save(settings: settings, progress: progress, generation: initial.generation,
                                           acknowledgeRecovery: true)
            }
            XCTAssertEqual(try Data(contentsOf: file(destination, title: title)), huge)
        }
    }

    func testFutureVersionWithChangedHeaderShapeRemainsProtected() async throws {
        for destination in ["save.json", "save.previous.json"] {
            let title = destination == "save.json" ? "header-primary" : "header-backup"
            let writer = try store(title)
            let initial = try await seed(writer)
            let future = Data(#"{"schemaVersion":99,"renamedTitleIdentifier":"future"}"#.utf8)
            try future.write(to: file(destination, title: title))
            await expect(.futureVersion(99)) {
                _ = try await writer.save(settings: settings, progress: progress, generation: initial.generation)
            }
            XCTAssertEqual(try Data(contentsOf: file(destination, title: title)), future)
        }
    }

    func testLegacyMigrationCommitsOnceAndRetainsValidatedBackup() async throws {
        let writer = try store()
        _ = try await writer.load()
        let old = Data(#"{"schemaVersion":1,"titleID":"practice","revision":7,"completedLevelNumbers":[2,1],"bestScore":230,"soundEnabled":false}"#.utf8)
        try old.write(to: file("save.json"))
        let migrated = try await writer.load()
        XCTAssertTrue(migrated.migrated)
        XCTAssertEqual(migrated.snapshot.revision, 8)
        XCTAssertEqual(migrated.snapshot.progress.completedLevels, ["level-1", "level-2"])
        XCTAssertEqual(migrated.snapshot.progress.bestScores, ["legacy-total": 230])
        XCTAssertFalse(migrated.snapshot.settings.soundEnabled)
        let current = try Data(contentsOf: file("save.json"))
        let again = try await store().load()
        XCTAssertFalse(again.migrated)
        XCTAssertEqual(again.snapshot, migrated.snapshot)
        XCTAssertEqual(try Data(contentsOf: file("save.json")), current)
        XCTAssertEqual(try JSONDecoder().decode(SaveSnapshot.self, from: Data(contentsOf: file("save.previous.json"))).schemaVersion, 2)
    }

    func testLegacyBackupMigrationWaitsForRecoveryConfirmation() async throws {
        let writer = try store()
        _ = try await writer.load()
        let old = Data(#"{"schemaVersion":1,"titleID":"practice","revision":7,"completedLevelNumbers":[1],"bestScore":23,"soundEnabled":false}"#.utf8)
        let damaged = Data("bad".utf8)
        try old.write(to: file("save.previous.json"))
        try damaged.write(to: file("save.json"))
        let recovered = try await writer.load()
        XCTAssertTrue(recovered.recovered)
        XCTAssertTrue(recovered.migrated)
        XCTAssertEqual(try Data(contentsOf: file("save.json")), damaged)
        XCTAssertEqual(try Data(contentsOf: file("save.previous.json")), old)
        _ = try await writer.acknowledgeRecovery(generation: recovered.generation)
        let fresh = try await store().load()
        XCTAssertFalse(fresh.recovered)
        XCTAssertFalse(fresh.migrated)
        XCTAssertEqual(fresh.snapshot.revision, 8)
        XCTAssertEqual(fresh.snapshot.progress.completedLevels, ["level-1"])
    }

    func testUnsupportedOldVersionAndInvalidDecodedPayloadNeverOverwrite() async throws {
        let writer = try store()
        let initial = try await writer.load()
        let unsupported = Data(#"{"schemaVersion":0,"titleID":"practice"}"#.utf8)
        try unsupported.write(to: file("save.json"))
        await expect(.unsupportedVersion(0)) { _ = try await writer.load() }
        await expect(.unsupportedVersion(0)) {
            _ = try await writer.save(settings: settings, progress: progress, generation: initial.generation)
        }
        XCTAssertEqual(try Data(contentsOf: file("save.json")), unsupported)
        let malformed = SaveSnapshot(titleID: "practice", progress: SaveProgress(completedLevels: ["same", "same"]))
        let bytes = try JSONEncoder().encode(malformed)
        try bytes.write(to: file("save.json"))
        await expect(.corrupt) { _ = try await writer.load() }
        XCTAssertEqual(try Data(contentsOf: file("save.json")), bytes)
    }

    func testResetPreservesPreferencesAndBackupCannotResurrectProgress() async throws {
        let writer = try store()
        let first = try await seed(writer)
        let reset = try await writer.resetProgress()
        XCTAssertEqual(reset.snapshot.settings, settings)
        XCTAssertEqual(reset.snapshot.progress, SaveProgress())
        await expect(.staleGeneration) {
            _ = try await writer.save(settings: settings, progress: progress, generation: first.generation)
        }
        try Data("bad".utf8).write(to: file("save.json"))
        let recovery = try await writer.load()
        XCTAssertEqual(recovery.snapshot.progress, SaveProgress())
        XCTAssertEqual(recovery.snapshot.settings, settings)
    }

    func testResetPreservesMostRecentPreferencesBeforeQueuedSave() async throws {
        let writer = try store()
        _ = try await seed(writer)
        let preferences = ShellSettings(soundEnabled: true, musicEnabled: false)
        let reset = try await writer.resetProgress(settings: preferences)
        XCTAssertEqual(reset.snapshot.settings, preferences)
        XCTAssertEqual(reset.snapshot.progress, SaveProgress())
        let fresh = try await store().load()
        XCTAssertEqual(fresh.snapshot.settings, preferences)
    }

    func testDeleteRemovesOwnedDataAndRejectsDelayedSave() async throws {
        let writer = try store()
        let initial = try await seed(writer)
        try Data("unfinished".utf8).write(to: file("backup.pending"))
        let deleted = try await writer.deleteLocalData()
        XCTAssertEqual(deleted.snapshot.settings, ShellSettings())
        for name in ["save.json", "save.previous.json", "save.pending", "backup.pending"] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: file(name).path))
        }
        await expect(.staleGeneration) {
            _ = try await writer.save(settings: settings, progress: progress, generation: initial.generation)
        }
        let restarted = try await store().load()
        XCTAssertEqual(restarted.snapshot, deleted.snapshot)
    }

    func testSameLevelIdentifiersAreIsolatedAndInvalidTitleIDsRejected() async throws {
        let first = try await seed(store("first"))
        let other = try store("second")
        let absent = try await other.load()
        XCTAssertEqual(absent.snapshot.progress, SaveProgress())
        _ = try await other.save(settings: ShellSettings(), progress: SaveProgress(completedLevels: ["level-1"]),
                                 generation: absent.generation)
        let restored = try await store("first").load()
        XCTAssertEqual(restored.snapshot, first.snapshot)
        for id in ["", "../first", "First", "first_title", String(repeating: "a", count: 81)] {
            XCTAssertThrowsError(try store(id)) { XCTAssertEqual($0 as? LocalSaveError, .invalidTitleID) }
        }
    }

    func testInvalidDuplicateNegativeAndOversizedSnapshotsAreRejected() async throws {
        let writer = try store()
        let initial = try await writer.load()
        for invalid in [SaveProgress(completedLevels: ["level-1", "level-1"]),
                        SaveProgress(bestScores: ["level-1": -1]), SaveProgress(unlockedLevels: [""])] {
            await expect(.invalidSnapshot) {
                _ = try await writer.save(settings: settings, progress: invalid, generation: initial.generation)
            }
        }
        try Data(repeating: 0, count: 1_048_577).write(to: file("save.json"))
        await expect(.oversized) { _ = try await writer.load() }
        XCTAssertEqual(try Data(contentsOf: file("save.json")).count, 1_048_577)
    }

    func testAttributesOrIOFailureDoesNotBecomeAbsenceOrOverwrite() async throws {
        let writer = try store()
        let first = try await seed(writer)
        let bytes = try Data(contentsOf: file("save.json"))
        await writer.setAttributeFailure(true)
        await expect(.io("Injected unavailable file attributes")) {
            _ = try await writer.save(settings: ShellSettings(), progress: SaveProgress(), generation: first.generation)
        }
        XCTAssertEqual(try Data(contentsOf: file("save.json")), bytes)
        await writer.setAttributeFailure(false)
        let restored = try await writer.load()
        XCTAssertEqual(restored.snapshot, first.snapshot)
    }

    #if os(iOS)
    func testPromotedFilesAndDirectoryRetainLocalOnlyProtectionAttributes() async throws {
        let writer = try store()
        let first = try await seed(writer)
        _ = try await writer.save(settings: settings, progress: progress, generation: first.generation)
        for url in [root!, writer.directory, file("save.json"), file("save.previous.json")] {
            XCTAssertEqual(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            let protectionValue = attrs[.protectionKey]
            let protectionName = (protectionValue as? FileProtectionType)?.rawValue ?? (protectionValue as? String)
            #if targetEnvironment(simulator)
            if protectionValue != nil {
                XCTAssertEqual(protectionName, FileProtectionType.completeUntilFirstUserAuthentication.rawValue)
            }
            #else
            XCTAssertEqual(protectionName, FileProtectionType.completeUntilFirstUserAuthentication.rawValue)
            #endif
        }
    }
    #endif
}
