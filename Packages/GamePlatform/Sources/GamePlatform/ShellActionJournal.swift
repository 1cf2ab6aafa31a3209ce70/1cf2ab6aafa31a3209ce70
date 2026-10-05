#if DEBUG && os(iOS)
import Combine
import Darwin
import Foundation
import GameCore

/// Bounded, fixture-only diagnostics. Missing events never prove non-delivery:
/// an interrupted process or failed writer can leave an incomplete tail.
@MainActor
public final class ShellActionJournal {
    public enum JournalError: Error { case invalidFixtureRoot, symbolicLink, unavailableAttributes, invalidExistingJournal }
    private static let maximumBytes = 128 * 1024
    private static let maximumRecords = 512
    private static let markerReserve = 512
    private static let kinds: Set<String> = [
        "journal.header", "flow.published", "button.pause", "button.resume",
        "pause.entered", "pause.returned", "resume.entered", "resume.returned",
        "pause.accepted", "pause.refused", "resume.accepted", "resume.refused",
        "resume.audioRecoveryAllowed", "resume.audioRecoveryRefused",
        "application.active.entered", "application.active.returned",
        "application.inactive.entered", "application.inactive.returned",
        "audio.interruptionBegan.entered", "audio.interruptionBegan.returned",
        "audio.interruptionEnded.entered", "audio.interruptionEnded.returned",
        "audio.routeDisconnected.entered", "audio.routeDisconnected.returned",
        "audio.mediaServicesReset.entered", "audio.mediaServicesReset.returned"
    ]
    private let fixtureID: UUID
    private let launchID = UUID()
    private let writer: JournalWriter
    private let queue = DispatchQueue(label: "gamecore.fixture.action-journal", qos: .utility)
    private var subscription: AnyCancellable?
    private var sequence = 0
    private var capturedRecords: Int
    private var capturedBytes: Int
    private var truncated = false

    public init(fixtureRoot: URL, fixtureID: UUID) throws {
        let root = fixtureRoot.standardizedFileURL
        guard fixtureRoot.isFileURL, root.lastPathComponent == fixtureID.uuidString,
              root.deletingLastPathComponent().lastPathComponent == "UIAutomationFixtures",
              fixtureRoot.path == root.path else { throw JournalError.invalidFixtureRoot }
        let manager = FileManager.default
        var ancestor = root
        while ancestor.path != "/" {
            if manager.fileExists(atPath: ancestor.path) ||
                ((try? manager.attributesOfItem(atPath: ancestor.path)[.type]) as? FileAttributeType) == .typeSymbolicLink {
                if try manager.attributesOfItem(atPath: ancestor.path)[.type] as? FileAttributeType == .typeSymbolicLink {
                    throw JournalError.symbolicLink
                }
            }
            ancestor.deleteLastPathComponent()
        }
        let diagnostics = root.appendingPathComponent("diagnostics", isDirectory: true)
        let file = diagnostics.appendingPathComponent("action-state.jsonl")
        for path in [diagnostics, file] {
            if ((try? manager.attributesOfItem(atPath: path.path)[.type]) as? FileAttributeType) == .typeSymbolicLink {
                throw JournalError.symbolicLink
            }
        }
        try manager.createDirectory(at: diagnostics, withIntermediateDirectories: true)
        for directory in [root, diagnostics] { try Self.applyAttributes(directory) }
        if !manager.fileExists(atPath: file.path) {
            guard manager.createFile(atPath: file.path, contents: nil, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]) else {
                throw JournalError.invalidExistingJournal
            }
        }
        try Self.applyAttributes(file)
        let size = try manager.attributesOfItem(atPath: file.path)[.size] as? NSNumber
        guard let size, size.intValue <= Self.maximumBytes else { throw JournalError.invalidExistingJournal }
        let existing = try Data(contentsOf: file)
        let records = existing.filter { $0 == 10 }.count
        guard records <= Self.maximumRecords, existing.isEmpty || existing.last == 10 else {
            throw JournalError.invalidExistingJournal
        }
        self.fixtureID = fixtureID
        capturedBytes = existing.count
        capturedRecords = records
        writer = try JournalWriter(file: file)
        let header: [String: Any] = ["schema": 1, "fixtureUUID": fixtureID.uuidString,
            "launchUUID": launchID.uuidString, "sequence": 0, "kind": "journal.header",
            "wallTime": Date().timeIntervalSince1970, "tailMayBeIncomplete": true]
        enqueue(header)
    }

    public func record(kind: String, flow: ShellFlow, persistenceReady: Bool,
                       recoveryRequired: Bool, resumeMessagePresent: Bool) {
        var state: String
        var reasons: [String] = []
        switch flow.state {
        case .splash: state = "splash"
        case .menu: state = "menu"
        case .loading: state = "loading"
        case .playing: state = "playing"
        case .paused(_, let values):
            state = "paused"
            reasons = values.map { reason in
                switch reason { case .user: return "user"
                case .applicationInactive: return "applicationInactive"
                case .audioInterruption: return "audioInterruption" }
            }.sorted()
        case .result(_, let outcome): state = outcome == .success ? "result.success" : "result.failure"
        case .loadFailed: state = "loadFailed"
        }
        var event: [String: Any] = ["schema": 1, "fixtureUUID": fixtureID.uuidString,
            "launchUUID": launchID.uuidString, "kind": Self.kinds.contains(kind) ? kind : "event.unknown",
            "wallTime": Date().timeIntervalSince1970, "state": state,
            "inputActive": flow.inputIsActive, "pauseReasons": reasons,
            "persistenceReady": persistenceReady, "recoveryRequired": recoveryRequired,
            "resumeMessagePresent": resumeMessagePresent]
        if let request = flow.currentRequest { event["requestUUID"] = request.id.uuidString }
        enqueue(event)
    }

    public func observe(_ controller: ShellController) {
        controller.diagnosticEvent = { [weak self, weak controller] kind, flow in
            guard let self, let controller else { return }
            self.record(kind: kind, flow: flow, persistenceReady: controller.persistenceReady,
                        recoveryRequired: controller.recoveryRequired, resumeMessagePresent: controller.resumeMessage != nil)
        }
        subscription = controller.$flow.sink { [weak self, weak controller] flow in
            guard let self, let controller else { return }
            self.record(kind: "flow.published", flow: flow, persistenceReady: controller.persistenceReady,
                        recoveryRequired: controller.recoveryRequired, resumeMessagePresent: controller.resumeMessage != nil)
        }
    }

    public func recordButton(_ id: String, controller: ShellController) {
        guard id == "shell.pause" || id == "shell.resume" else { return }
        record(kind: id == "shell.pause" ? "button.pause" : "button.resume", flow: controller.flow,
               persistenceReady: controller.persistenceReady, recoveryRequired: controller.recoveryRequired,
               resumeMessagePresent: controller.resumeMessage != nil)
    }

    /// Queue barrier for tests only; no product lifecycle or action waits on it.
    public func flush() async {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume() }
        }
    }

    private func enqueue(_ fields: [String: Any]) {
        guard !truncated else { return }
        var event = fields
        sequence += 1
        event["sequence"] = sequence
        guard var data = try? JSONSerialization.data(withJSONObject: event, options: [.sortedKeys]) else {
            JournalWriter.report("encode-failed"); return
        }
        data.append(10)
        if capturedRecords >= Self.maximumRecords - 1 || capturedBytes + data.count > Self.maximumBytes - Self.markerReserve {
            truncated = true
            let marker: [String: Any] = ["schema": 1, "fixtureUUID": fixtureID.uuidString,
                "launchUUID": launchID.uuidString, "sequence": sequence, "kind": "journal.truncated"]
            guard var bytes = try? JSONSerialization.data(withJSONObject: marker, options: [.sortedKeys]) else { return }
            bytes.append(10)
            if capturedRecords < Self.maximumRecords, capturedBytes + bytes.count <= Self.maximumBytes {
                capturedRecords += 1; capturedBytes += bytes.count
                let writer = writer, payload = bytes
                queue.async { writer.append(payload) }
            }
            return
        }
        capturedRecords += 1; capturedBytes += data.count
        let writer = writer, payload = data
        queue.async { writer.append(payload) }
    }

    private static func applyAttributes(_ url: URL) throws {
        let manager = FileManager.default
        try manager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        var target = url
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try target.setResourceValues(values)
        let excluded = try target.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
        let protection = try manager.attributesOfItem(atPath: target.path)[.protectionKey]
        let name = (protection as? FileProtectionType)?.rawValue ?? (protection as? String)
        #if targetEnvironment(simulator)
        let matches = protection == nil || name == FileProtectionType.completeUntilFirstUserAuthentication.rawValue
        #else
        let matches = name == FileProtectionType.completeUntilFirstUserAuthentication.rawValue
        #endif
        guard excluded == true, matches else { throw JournalError.unavailableAttributes }
    }
}

/// Accessed only by the journal's serial utility queue after initialization.
/// Initialization hands off immutable ownership; no caller can invoke append.
/// Pending blocks retain the writer, so destruction cannot overlap a write.
private final class JournalWriter: @unchecked Sendable {
    private let handle: FileHandle
    private var failed = false
    init(file: URL) throws {
        let descriptor = Darwin.open(file.path, O_WRONLY | O_APPEND | O_NOFOLLOW)
        guard descriptor >= 0 else { throw ShellActionJournal.JournalError.invalidExistingJournal }
        handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }
    func append(_ data: Data) {
        guard !failed else { return }
        do { try handle.write(contentsOf: data) }
        catch { failed = true; Self.report("write-failed-tail-incomplete") }
    }
    deinit { try? handle.close() }
    static func report(_ tag: String) {
        // Fixed diagnostic tags only: no paths, error text, preferences or saves.
        try? FileHandle.standardError.write(contentsOf: Data(("ShellActionJournal: " + tag + "\n").utf8))
    }
}
#endif
