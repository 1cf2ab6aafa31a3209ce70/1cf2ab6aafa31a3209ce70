#if DEBUG && os(iOS)
import Foundation
import GameCore
import GamePlatform
import XCTest

@MainActor
final class ShellActionJournalTests: XCTestCase {
    private func ownedRoot(_ identity: UUID) -> URL {
        FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("UIAutomationFixtures", isDirectory: true)
            .appendingPathComponent(identity.uuidString, isDirectory: true)
    }
    private func records(_ root: URL) throws -> [[String: Any]] {
        let data = try Data(contentsOf: root.appendingPathComponent("diagnostics/action-state.jsonl"))
        return try data.split(separator: 10).map {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0)) as? [String: Any])
        }
    }

    func testControllerEventsRecordPauseResumeRefusalAndLifecycleWithoutPrivateValues() async throws {
        let identity = UUID(), root = ownedRoot(identity)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent().deletingLastPathComponent()) }
        let journal = try ShellActionJournal(fixtureRoot: root, fixtureID: identity)
        let controller = ShellController(title: TitleRegistration(id: "private-title-sentinel", displayName: "Private title sentinel"),
                                         feedback: nil, preparation: {}, preparationFailureMessage: "Unused fixture failure",
                                         prepareSession: {}, setPlaying: { _ in }, setReducedMotion: { _ in })
        journal.observe(controller)
        controller.finishSplash(); controller.start()
        let deadline = Date().addingTimeInterval(3)
        while case .loading = controller.flow.state, Date() < deadline { await Task.yield() }
        XCTAssertTrue(controller.flow.inputIsActive)
        journal.recordButton("shell.pause", controller: controller)
        controller.pause()
        controller.setApplicationActive(false)
        journal.recordButton("shell.resume", controller: controller)
        controller.resume() // Refused while applicationInactive remains set.
        XCTAssertFalse(controller.flow.inputIsActive)
        controller.setApplicationActive(true)
        controller.resume()
        XCTAssertTrue(controller.flow.inputIsActive)
        controller.handleAudioEvent(.interruptionBegan)
        controller.handleAudioEvent(.interruptionEnded(shouldResume: false))
        controller.resume()
        journal.record(kind: "private free text sentinel", flow: controller.flow,
                       persistenceReady: true, recoveryRequired: false, resumeMessagePresent: false)
        await journal.flush()
        let events = try records(root)
        XCTAssertEqual(events.first?["kind"] as? String, "journal.header")
        XCTAssertEqual(events.map { $0["sequence"] as? Int }, Array(1...events.count).map(Optional.some))
        let kinds = events.compactMap { $0["kind"] as? String }
        for expected in ["button.pause", "pause.entered", "pause.returned", "button.resume", "resume.entered",
                         "resume.returned", "pause.accepted", "resume.accepted", "resume.refused", "application.inactive.returned", "application.active.returned",
                         "audio.interruptionBegan.returned", "audio.interruptionEnded.returned", "flow.published"] {
            XCTAssertTrue(kinds.contains(expected), expected)
        }
        XCTAssertEqual(events.first { $0["kind"] as? String == "pause.entered" }?["state"] as? String, "playing")
        XCTAssertEqual(events.first { $0["kind"] as? String == "pause.returned" }?["state"] as? String, "paused")
        let resumes = events.filter { $0["kind"] as? String == "resume.returned" }
        XCTAssertEqual(resumes.first?["state"] as? String, "paused")
        XCTAssertEqual(resumes.last?["state"] as? String, "playing")
        XCTAssertTrue((resumes.first?["pauseReasons"] as? [String])?.contains("applicationInactive") == true)
        XCTAssertEqual(events.last?["kind"] as? String, "event.unknown")
        let text = try String(contentsOf: root.appendingPathComponent("diagnostics/action-state.jsonl"), encoding: .utf8)
        XCTAssertFalse(text.contains("private"))
        for event in events {
            XCTAssertEqual(event["fixtureUUID"] as? String, identity.uuidString)
            XCTAssertEqual(event["schema"] as? Int, 1)
            XCTAssertNil(event["settings"]); XCTAssertNil(event["titleID"]); XCTAssertNil(event["error"])
        }
    }

    func testCaptureIsBoundedAndOrderedAndRejectsInvalidRootsAndSymlinks() async throws {
        let identity = UUID(), root = ownedRoot(identity)
        let owner = root.deletingLastPathComponent().deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: owner) }
        XCTAssertThrowsError(try ShellActionJournal(fixtureRoot: owner, fixtureID: identity))
        XCTAssertThrowsError(try ShellActionJournal(fixtureRoot: root, fixtureID: UUID()))
        XCTAssertFalse(FileManager.default.fileExists(atPath: owner.path))
        let journal = try ShellActionJournal(fixtureRoot: root, fixtureID: identity)
        let flow = ShellFlow(title: TitleRegistration(id: "sentinel", displayName: "Sentinel"))
        // No writer barrier inside this loop: the capture/enqueue side must cap.
        for _ in 0..<2000 {
            journal.record(kind: "flow.published", flow: flow, persistenceReady: true,
                           recoveryRequired: false, resumeMessagePresent: false)
        }
        await journal.flush()
        let events = try records(root)
        XCTAssertLessThanOrEqual(events.count, 512)
        XCTAssertEqual(events.last?["kind"] as? String, "journal.truncated")
        XCTAssertEqual(events.filter { $0["kind"] as? String == "journal.truncated" }.count, 1)
        XCTAssertEqual(events.map { $0["sequence"] as? Int }, Array(1...events.count).map(Optional.some))
        let file = root.appendingPathComponent("diagnostics/action-state.jsonl")
        let bytes = try Data(contentsOf: file)
        XCTAssertLessThanOrEqual(bytes.count, 128 * 1024)
        XCTAssertTrue(try file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        let raw = try FileManager.default.attributesOfItem(atPath: file.path)[.protectionKey]
        let protection = (raw as? FileProtectionType)?.rawValue ?? (raw as? String)
        #if targetEnvironment(simulator)
        XCTAssertTrue(raw == nil || protection == FileProtectionType.completeUntilFirstUserAuthentication.rawValue)
        #else
        XCTAssertEqual(protection, FileProtectionType.completeUntilFirstUserAuthentication.rawValue)
        #endif
        let linkID = UUID(), link = root.deletingLastPathComponent().appendingPathComponent(linkID.uuidString)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
        XCTAssertThrowsError(try ShellActionJournal(fixtureRoot: link, fixtureID: linkID))
        let secondID = UUID(), second = root.deletingLastPathComponent().appendingPathComponent(secondID.uuidString)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: second.appendingPathComponent("diagnostics"), withDestinationURL: root)
        XCTAssertThrowsError(try ShellActionJournal(fixtureRoot: second, fixtureID: secondID))
        XCTAssertEqual(try Data(contentsOf: file), bytes, "Rejected roots must not append or overwrite the original journal")
    }
}
#endif
