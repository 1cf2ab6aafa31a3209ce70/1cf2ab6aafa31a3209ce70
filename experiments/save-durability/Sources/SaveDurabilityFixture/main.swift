import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

struct Settings: Codable, Equatable {
    var musicEnabled: Bool
    var effectsEnabled: Bool
    var hapticsEnabled: Bool
    var language: String
}
struct Progress: Codable, Equatable {
    var completedLevels: [String]
    var bestScores: [String: Int]
    var unlockedLevels: [String]
}
struct Envelope: Codable, Equatable {
    var schemaVersion = 2
    var titleID: String
    var revision: Int
    var progress: Progress
    var settings: Settings
}
struct Legacy: Codable {
    var schemaVersion = 1
    var titleID: String
    var revision: Int
    var completedLevelNumbers: [Int]
    var bestScore: Int
    var soundEnabled: Bool
}
struct Header: Decodable { var schemaVersion: Int; var titleID: String }
enum Fault: Error, Equatable {
    case corrupt, titleMismatch, futureVersion(Int), unsupportedVersion(Int), invalidTitle
    case recoveryRequired, staleRevision, oversized, io(String), interrupted(Phase)
}
enum Phase: String, CaseIterable { case partialTemporary, flushedTemporary, replacedBackup, replacedCurrent }
enum Origin: String { case absent, current, backup }
struct Loaded { var value: Envelope?; var origin: Origin; var migrated: Bool }
let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
}()
let fm = FileManager.default
let maximumSaveBytes = 1_048_576 // Investigation bound; content-specific limits belong to Epic 04.

// A tiny concrete fixture, deliberately not a reusable persistence abstraction.
struct FixtureStore {
    let titleID: String
    let directory: URL
    var current: URL { directory.appendingPathComponent("save.json") }
    var backup: URL { directory.appendingPathComponent("save.previous.json") }
    var temporary: URL { directory.appendingPathComponent("save.pending") }
    var backupTemporary: URL { directory.appendingPathComponent("backup.pending") }

    init(root: URL, titleID: String) throws {
        guard !titleID.isEmpty, titleID.utf8.count <= 80,
              titleID.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 })
        else { throw Fault.invalidTitle }
        self.titleID = titleID
        directory = root.appendingPathComponent(titleID, isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func decode(_ data: Data) throws -> (Envelope, Bool) {
        let header: Header
        do { header = try JSONDecoder().decode(Header.self, from: data) }
        catch { throw Fault.corrupt }
        guard header.titleID == titleID else { throw Fault.titleMismatch }
        guard header.schemaVersion <= 2 else { throw Fault.futureVersion(header.schemaVersion) }
        switch header.schemaVersion {
        case 2:
            guard let value = try? JSONDecoder().decode(Envelope.self, from: data), valid(value)
            else { throw Fault.corrupt }
            return (value, false)
        case 1:
            guard let old = try? JSONDecoder().decode(Legacy.self, from: data), old.revision >= 0,
                  old.bestScore >= 0, old.completedLevelNumbers.allSatisfy({ $0 > 0 }),
                  Set(old.completedLevelNumbers).count == old.completedLevelNumbers.count
            else { throw Fault.corrupt }
            let completed = old.completedLevelNumbers.sorted().map { "level-\($0)" }
            return (Envelope(titleID: old.titleID, revision: old.revision,
                progress: Progress(completedLevels: completed, bestScores: ["legacy-total": old.bestScore],
                                   unlockedLevels: ["level-1"]),
                settings: Settings(musicEnabled: old.soundEnabled, effectsEnabled: old.soundEnabled,
                                   hapticsEnabled: true, language: "en")), true)
        default: throw Fault.unsupportedVersion(header.schemaVersion)
        }
    }

    func valid(_ value: Envelope) -> Bool {
        value.schemaVersion == 2 && value.titleID == titleID && value.revision >= 0 &&
        value.progress.bestScores.values.allSatisfy { $0 >= 0 } &&
        value.progress.bestScores.keys.allSatisfy { !$0.isEmpty } &&
        [value.progress.completedLevels, value.progress.unlockedLevels].allSatisfy {
            $0.allSatisfy { !$0.isEmpty } && Set($0).count == $0.count
        } && value.settings.language == "en"
    }

    func read(_ url: URL) throws -> (Envelope, Bool)? {
        // Only genuine absence is absence; permission/I/O failures propagate.
        do {
            let attributes = try fm.attributesOfItem(atPath: url.path)
            guard let size = attributes[.size] as? NSNumber, size.intValue <= maximumSaveBytes
            else { throw Fault.oversized }
            let data = try Data(contentsOf: url)
            guard data.count <= maximumSaveBytes else { throw Fault.oversized }
            return try decode(data)
        }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
    }

    func load() throws -> Loaded {
        do {
            if let (value, migrated) = try read(current) {
                return Loaded(value: value, origin: .current, migrated: migrated)
            }
        } catch Fault.corrupt {
            // Only malformed known-schema data may fall back. Wrong-title/future data is preserved.
        }
        if let (value, migrated) = try read(backup) {
            return Loaded(value: value, origin: .backup, migrated: migrated)
        }
        if fm.fileExists(atPath: current.path) { throw Fault.corrupt }
        return Loaded(value: nil, origin: .absent, migrated: false)
    }

    func write(_ value: Envelope, interrupt: Phase? = nil, acknowledgeRecovery: Bool = false) throws {
        guard valid(value) else { throw Fault.corrupt }
        let previous = try load() // Refuse overwrite of future/wrong-title/unrecoverable existing saves.
        guard previous.origin != .backup || acknowledgeRecovery else { throw Fault.recoveryRequired }
        guard previous.value.map({ value.revision > $0.revision }) ?? true else { throw Fault.staleRevision }
        // Even if current is valid, refuse silently overwriting a future or alien backup.
        do { _ = try read(backup) } catch Fault.corrupt { /* A valid current can replace corrupt backup. */ }
        let data = try encoder.encode(value)
        guard data.count <= maximumSaveBytes else { throw Fault.oversized }
        if interrupt == .partialTemporary {
            try syncWrite(Data(data.prefix(data.count / 2)), to: temporary)
            throw Fault.interrupted(.partialTemporary)
        }
        try syncWrite(data, to: temporary)
        try stop(.flushedTemporary, interrupt)
        if let previousValue = previous.value {
            try syncWrite(try encoder.encode(previousValue), to: backupTemporary)
            try replace(backupTemporary, backup)
        }
        try stop(.replacedBackup, interrupt)
        try replace(temporary, current)
        try stop(.replacedCurrent, interrupt)
    }
}
func stop(_ phase: Phase, _ requested: Phase?) throws {
    if phase == requested { throw Fault.interrupted(phase) }
}
func replace(_ source: URL, _ destination: URL) throws {
    guard rename(source.path, destination.path) == 0 else { throw Fault.io("rename errno=\(errno)") }
}
func syncWrite(_ data: Data, to url: URL) throws {
    let fd = open(url.path, O_WRONLY | O_CREAT | O_TRUNC, mode_t(0o600))
    guard fd >= 0 else { throw Fault.io("open errno=\(errno)") }
    var descriptorOpen = true
    defer { if descriptorOpen { close(fd) } }
    try data.withUnsafeBytes { bytes in
        var offset = 0
        while offset < bytes.count {
            let count = write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw Fault.io("write errno=\(errno)") }
            offset += count
        }
    }
    guard fsync(fd) == 0 else { throw Fault.io("fsync errno=\(errno)") }
    descriptorOpen = false // close errors are reported; never retry a possibly closed descriptor.
    guard close(fd) == 0 else { throw Fault.io("close errno=\(errno)") }
}

struct AssertionFailure: Error { let message: String }
func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    guard try condition() else { throw AssertionFailure(message: message) }
}
func expect(_ fault: Fault, _ body: () throws -> Void) throws {
    do { try body(); throw AssertionFailure(message: "Expected \(fault)") }
    catch let actual as Fault { try require(actual == fault, "Expected \(fault), got \(actual)") }
}
func sample(_ title: String = "practice", revision: Int = 1) -> Envelope {
    Envelope(titleID: title, revision: revision,
             progress: Progress(completedLevels: ["level-1"], bestScores: ["level-1": 120],
                                unlockedLevels: ["level-1", "level-2"]),
             settings: Settings(musicEnabled: true, effectsEnabled: false, hapticsEnabled: true, language: "en"))
}

let root = fm.temporaryDirectory.appendingPathComponent("save-durability-\(UUID().uuidString)", isDirectory: true)
try fm.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: root) }
var scenarios: [String] = []
func scenario(_ name: String, _ body: (FixtureStore) throws -> Void) throws {
    let store = try FixtureStore(root: root.appendingPathComponent("case-\(scenarios.count)"), titleID: "practice")
    try body(store)
    scenarios.append(name)
    print("PASS \(name)")
}

try scenario("absent files mean first launch") { store in
    let result = try store.load()
    try require(result.value == nil && result.origin == .absent, "Absence must be explicit")
}
try scenario("current round trip preserves progress, score, unlocks and settings") { store in
    try store.write(sample())
    try require(try store.load().value == sample(), "Round-trip mismatch")
}
for phase in Phase.allCases {
    try scenario("replacement interrupted after \(phase.rawValue)") { store in
        try store.write(sample())
        try expect(.interrupted(phase)) { try store.write(sample(revision: 2), interrupt: phase) }
        let restarted = try FixtureStore(root: store.directory.deletingLastPathComponent(), titleID: "practice")
        let expected = phase == .replacedCurrent ? 2 : 1
        try require(try restarted.load().value?.revision == expected, "Only previous or complete new state is accepted")
    }
    try scenario("first write interrupted after \(phase.rawValue)") { store in
        try expect(.interrupted(phase)) { try store.write(sample(), interrupt: phase) }
        let value = try store.load().value
        try require(phase == .replacedCurrent ? value == sample() : value == nil, "Pending file must never be promoted")
    }
}
try scenario("corrupt current recovers previous good and repair preserves recovery") { store in
    try store.write(sample()); try store.write(sample(revision: 2))
    try Data("{truncated".utf8).write(to: store.current)
    let recovered = try store.load()
    try require(recovered.origin == .backup && recovered.value == sample(), "Recovery lost prior valid state")
    try expect(.interrupted(.replacedBackup)) { try store.write(sample(revision: 3), interrupt: .replacedBackup, acknowledgeRecovery: true) }
    try require(try store.load().value == sample(), "Repair replaced good backup with corruption")
    try expect(.recoveryRequired) { try store.write(sample(revision: 3)) }
    try store.write(sample(revision: 3), acknowledgeRecovery: true)
    try require(try store.load().value == sample(revision: 3), "Repair failed")
}
try scenario("missing current recovers backup") { store in
    try store.write(sample()); try store.write(sample(revision: 2)); try fm.removeItem(at: store.current)
    try require(try store.load().origin == .backup, "Missing primary recovery failed")
}
try scenario("corrupt primary without backup remains an explicit error") { store in
    try Data("bad".utf8).write(to: store.current)
    try expect(.corrupt) { _ = try store.load() }
    try expect(.corrupt) { try store.write(sample()) }
}
try scenario("both corrupt remain an explicit error") { store in
    try Data("bad".utf8).write(to: store.current); try Data("bad".utf8).write(to: store.backup)
    try expect(.corrupt) { _ = try store.load() }
}
try scenario("valid current can repair corrupt backup") { store in
    try store.write(sample()); try Data("bad".utf8).write(to: store.backup)
    try store.write(sample(revision: 2))
    try require(try store.read(store.backup)?.0 == sample(), "Backup must become previous validated current")
}
try scenario("v1 migrates deterministically and only once") { store in
    let old = Legacy(titleID: "practice", revision: 7, completedLevelNumbers: [2, 1], bestScore: 230, soundEnabled: false)
    let bytes = try encoder.encode(old)
    try bytes.write(to: store.current)
    let first = try store.load()
    try require(first.migrated && first.value?.progress.completedLevels == ["level-1", "level-2"], "Migration mapping failed")
    try require(first.value?.progress.bestScores == ["legacy-total": 230], "Legacy total must not invent per-level score")
    try require(first.value?.settings.effectsEnabled == false && first.value?.settings.musicEnabled == false, "Legacy sound mapping failed")
    try require(try Data(contentsOf: store.current) == bytes, "Loading may not rewrite migration source")
    var migrated = first.value!
    migrated.revision += 1
    try store.write(migrated)
    try require(try store.load().migrated == false, "Persisted migration must not repeat")
}
try scenario("known-schema semantic corruption recovers backup") { store in
    try store.write(sample()); try store.write(sample(revision: 2))
    var invalid = sample(revision: 3); invalid.progress.bestScores = ["level-1": -1]
    try encoder.encode(invalid).write(to: store.current)
    try require(try store.load().origin == .backup, "Invalid score accepted")
}
try scenario("future primary preserves bytes and refuses fallback or overwrite") { store in
    try store.write(sample()); try store.write(sample(revision: 2))
    let bytes = Data("{\"schemaVersion\":99,\"titleID\":\"practice\",\"unknown\":true}".utf8)
    try bytes.write(to: store.current)
    try expect(.futureVersion(99)) { _ = try store.load() }
    try expect(.futureVersion(99)) { try store.write(sample(revision: 3)) }
    try require(try Data(contentsOf: store.current) == bytes, "Future save overwritten")
}
try scenario("future backup is preserved even when current is valid") { store in
    try store.write(sample())
    let bytes = Data("{\"schemaVersion\":99,\"titleID\":\"practice\"}".utf8)
    try bytes.write(to: store.backup)
    try expect(.futureVersion(99)) { try store.write(sample(revision: 2)) }
    try require(try Data(contentsOf: store.backup) == bytes, "Future backup overwritten")
}
try scenario("two titles with identical level IDs remain isolated") { store in
    let other = try FixtureStore(root: store.directory.deletingLastPathComponent(), titleID: "other-title")
    try store.write(sample()); try other.write(sample("other-title", revision: 4))
    try require(try store.load().value == sample(), "Cross-title read")
    try require(try other.load().value == sample("other-title", revision: 4), "Other-title save missing")
}
try scenario("wrong-title primary refuses fallback and overwrite") { store in
    try store.write(sample()); try store.write(sample(revision: 2))
    let bytes = try encoder.encode(sample("other-title"))
    try bytes.write(to: store.current)
    try expect(.titleMismatch) { _ = try store.load() }
    try expect(.titleMismatch) { try store.write(sample()) }
    try require(try Data(contentsOf: store.current) == bytes, "Alien save overwritten")
}
try scenario("wrong-title backup refuses overwrite") { store in
    try store.write(sample())
    let bytes = try encoder.encode(sample("other-title")); try bytes.write(to: store.backup)
    try expect(.titleMismatch) { try store.write(sample(revision: 2)) }
    try require(try Data(contentsOf: store.backup) == bytes, "Alien backup overwritten")
}
try scenario("invalid title cannot escape its directory") { store in
    try expect(.invalidTitle) { _ = try FixtureStore(root: store.directory, titleID: "../other") }
}
try scenario("unsupported old schema remains explicit") { store in
    try Data("{\"schemaVersion\":0,\"titleID\":\"practice\"}".utf8).write(to: store.current)
    try expect(.unsupportedVersion(0)) { _ = try store.load() }
}
try scenario("duplicate or stale revisions cannot overwrite progress") { store in
    try store.write(sample(revision: 2))
    try expect(.staleRevision) { try store.write(sample(revision: 2)) }
    try expect(.staleRevision) { try store.write(sample(revision: 1)) }
    try require(try store.load().value == sample(revision: 2), "Stale write changed progress")
}
try scenario("missing primary and corrupt backup is not first launch") { store in
    try Data("bad".utf8).write(to: store.backup)
    try expect(.corrupt) { _ = try store.load() }
    try expect(.corrupt) { try store.write(sample()) }
}
try scenario("missing primary and future backup is not first launch") { store in
    try Data("{\"schemaVersion\":99,\"titleID\":\"practice\"}".utf8).write(to: store.backup)
    try expect(.futureVersion(99)) { _ = try store.load() }
}
try scenario("oversized save blocks load and overwrite") { store in
    try Data(repeating: 32, count: maximumSaveBytes + 1).write(to: store.current)
    try expect(.oversized) { _ = try store.load() }
    try expect(.oversized) { try store.write(sample()) }
    try require(try Data(contentsOf: store.current).count == maximumSaveBytes + 1, "Oversized bytes changed")
}
try scenario("filesystem I/O errors do not become corrupt or first launch") { store in
    try fm.createDirectory(at: store.current, withIntermediateDirectories: false)
    do {
        _ = try store.load()
        throw AssertionFailure(message: "Directory read should fail")
    } catch is CocoaError { /* An actual filesystem error propagates, with no default or backup fallback. */ }
}
try scenario("ordered synthetic completion, pause and background snapshots retain latest values") { store in
    // Single-writer ordering proof only; events are fixture inputs, not live shell callbacks.
    let events = ["completion", "pause", "background"] + (0..<20).map { "rapid-update-\($0)" }
    for (index, _) in events.enumerated() {
        var value = sample(revision: index + 1)
        value.progress.bestScores["level-1"] = 120 + index
        try store.write(value)
    }
    let restarted = try FixtureStore(root: store.directory.deletingLastPathComponent(), titleID: "practice")
    try require(try restarted.load().value?.revision == events.count, "Latest snapshot lost")
    try require(try restarted.load().value?.progress.bestScores["level-1"] == 120 + events.count - 1, "Latest score lost")
}
try scenario("export is inspectable; delete-all clears recovery slots and title directory") { store in
    try store.write(sample()); try store.write(sample(revision: 2))
    let export = store.directory.deletingLastPathComponent().appendingPathComponent("user-export.json")
    let loaded = try store.load().value!
    try encoder.encode(loaded).write(to: export)
    try require(try store.decode(Data(contentsOf: export)).0 == loaded, "Export omitted state")
    // Full delete-all mechanics after confirmation; not a settings-preserving progress reset.
    for url in [store.current, store.backup, store.temporary, store.backupTemporary] {
        if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
    }
    try require(try store.load().value == nil, "Delete-all revived previous progress")
    try fm.removeItem(at: store.directory)
    try require(!fm.fileExists(atPath: store.directory.path), "Delete left title data")
    try require(fm.fileExists(atPath: export.path), "App-local deletion must not remove user export")
}
print("\(scenarios.count) scenarios passed; temporary files removed on normal exit.")
