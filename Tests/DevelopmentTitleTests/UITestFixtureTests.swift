#if DEBUG
import Foundation
import GameCore
import GamePlatform
import XCTest
@testable import DevelopmentTitle

final class UITestFixtureTests: XCTestCase {
    func testAbsentFlagKeepsDefaultRootAndUUIDSelectsCanonicalOwnedRoot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertEqual(try ShellUITestFixture.storageRoot(defaultRoot: root, arguments: []), root)
        XCTAssertEqual(try ShellUITestFixture.storageRoot(defaultRoot: root,
                         arguments: ["--shell-large-text", "--shell-reduced-motion"]), root)

        let identity = try XCTUnwrap(UUID(uuidString: "01234567-89AB-4CDE-8123-456789ABCDEF"))
        let expected = root.appendingPathComponent("UIAutomationFixtures", isDirectory: true)
            .appendingPathComponent(identity.uuidString, isDirectory: true)
        for value in [identity.uuidString, identity.uuidString.lowercased()] {
            let selected = try ShellUITestFixture.storageRoot(defaultRoot: root,
                               arguments: ["--ui-test-fixture", value])
            XCTAssertEqual(selected, expected)
            XCTAssertEqual(selected.lastPathComponent, identity.uuidString)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path), "Parsing must not create directories")
    }

    func testInvalidFixtureArgumentsThrowWithoutCreatingDirectories() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = UUID().uuidString
        let invalid: [[String]] = [
            ["--ui-test-fixture"],
            ["--ui-test-fixture", ""],
            ["--ui-test-fixture", "--shell-large-text"],
            ["--ui-test-fixture", "not-a-uuid"],
            ["--ui-test-fixture", "../" + identity],
            ["--ui-test-fixture", root.appendingPathComponent(identity).path],
            ["--ui-test-fixture", identity + "/save.json"],
            ["--ui-test-fixture", identity, "--ui-test-fixture", identity],
            ["--ui-test-fixture", identity, "--ui-test-fixture", UUID().uuidString]
        ]
        for arguments in invalid {
            XCTAssertThrowsError(try ShellUITestFixture.storageRoot(defaultRoot: root, arguments: arguments)) {
                XCTAssertTrue($0 is ShellUITestFixture.InvalidArguments)
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.path),
                           "Rejected arguments must not create directories: \(arguments)")
        }
    }

    @MainActor
    func testFixtureRelaunchPersistsAndOtherIdentityCannotChangeDefaultSaveBytes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let defaultStore = try LocalSaveStore(titleID: "development-practice", root: root)
        let baseline = try await defaultStore.load()
        let first = try await defaultStore.save(settings: ShellSettings(),
            progress: SaveProgress(completedLevels: ["baseline-one"]), generation: baseline.generation)
        _ = try await defaultStore.save(settings: ShellSettings(),
            progress: SaveProgress(completedLevels: ["baseline-one", "baseline-two"]), generation: first.generation)
        let current = defaultStore.directory.appendingPathComponent("save.json")
        let backup = defaultStore.directory.appendingPathComponent("save.previous.json")
        let originalCurrent = try Data(contentsOf: current)
        let originalBackup = try Data(contentsOf: backup)

        for invalid in [["--ui-test-fixture"], ["--ui-test-fixture", root.path],
                        ["--ui-test-fixture", UUID().uuidString, "--ui-test-fixture", UUID().uuidString]] {
            XCTAssertThrowsError(try ShellUITestFixture.storageRoot(defaultRoot: root, arguments: invalid))
        }
        XCTAssertEqual(try Data(contentsOf: current), originalCurrent)
        XCTAssertEqual(try Data(contentsOf: backup), originalBackup)

        let arguments = ["--ui-test-fixture", UUID().uuidString]
        let fixtureRoot = try ShellUITestFixture.storageRoot(defaultRoot: root, arguments: arguments)
        let fixture = try LocalSaveStore(titleID: "development-practice", root: fixtureRoot)
        let initial = try await fixture.load()
        let settings = ShellSettings(soundEnabled: false, musicEnabled: false, hapticsEnabled: false)
        let progress = SaveProgress(completedLevels: ["fixture-level"], bestScores: ["fixture-level": 7],
                                    unlockedLevels: ["fixture-next"])
        _ = try await fixture.save(settings: settings, progress: progress, generation: initial.generation)

        let relaunchedRoot = try ShellUITestFixture.storageRoot(defaultRoot: root, arguments: arguments)
        XCTAssertEqual(relaunchedRoot, fixtureRoot)
        let relaunched = try LocalSaveStore(titleID: "development-practice", root: relaunchedRoot)
        let restored = try await relaunched.load()
        XCTAssertEqual(restored.snapshot.settings, settings)
        XCTAssertEqual(restored.snapshot.progress, progress)

        let otherRoot = try ShellUITestFixture.storageRoot(defaultRoot: root,
                            arguments: ["--ui-test-fixture", UUID().uuidString])
        XCTAssertNotEqual(otherRoot, fixtureRoot)
        let other = try LocalSaveStore(titleID: "development-practice", root: otherRoot)
        let otherState = try await other.load()
        XCTAssertEqual(otherState.snapshot.settings, ShellSettings())
        XCTAssertEqual(otherState.snapshot.progress, SaveProgress())
        _ = try await other.save(settings: ShellSettings(),
            progress: SaveProgress(completedLevels: ["other-fixture"]), generation: otherState.generation)
        _ = try await other.deleteLocalData()
        let unaffected = try await relaunched.load()
        XCTAssertEqual(unaffected.snapshot.settings, settings)
        XCTAssertEqual(unaffected.snapshot.progress, progress)
        XCTAssertEqual(try Data(contentsOf: current), originalCurrent)
        XCTAssertEqual(try Data(contentsOf: backup), originalBackup)
    }
}
#endif
