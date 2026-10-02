import Foundation
import GameCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum LocalSaveError: Error, Equatable, Sendable, LocalizedError {
    case invalidTitleID, invalidSnapshot, corrupt, oversized, titleMismatch
    case futureVersion(Int), unsupportedVersion(Int), recoveryRequired, staleGeneration
    case io(String)

    public var errorDescription: String? {
        switch self {
        case .invalidTitleID: return "This title has an invalid local save identifier."
        case .invalidSnapshot: return "The game supplied invalid save data. Your existing local data has been preserved."
        case .corrupt, .oversized:
            return "Local save data could not be read. You can delete local data to start again; this permanently removes its progress and preferences."
        case .titleMismatch:
            return "This save belongs to another title. It has been left unchanged. Deleting local data permanently removes it."
        case .futureVersion, .unsupportedVersion:
            return "This save format is not supported by this app version. It has been left unchanged. Try an app version that supports it; deleting local data permanently removes it."
        case .recoveryRequired: return "A previous good save is available. Confirm recovery before saving changes."
        case .staleGeneration: return "This save was cancelled because local data was reset or deleted."
        case .io(let detail): return "Local storage is temporarily unavailable. Unlock the device and retry. (\(detail))"
        }
    }
}

/// One store is the sole writer for a title. Its actor methods never suspend
/// inside a filesystem transaction, so reset/delete cannot interleave with saves.
public actor LocalSaveStore {
    public nonisolated let titleID: String
    public nonisolated let directory: URL
    private let defaultSettings: ShellSettings
    private let supportedLanguages: [String]
    private var generation = UUID()
    private let manager = FileManager.default
    private let maximumBytes = 1_048_576
    // Internal injection operates at real filesystem boundaries for package tests.
    enum WritePhase: CaseIterable { case partialStaging, staged, backupPromoted, currentPromoted }
    var interruptAt: WritePhase?
    private var failAttributes = false

    private var current: URL { directory.appendingPathComponent("save.json") }
    private var backup: URL { directory.appendingPathComponent("save.previous.json") }
    private var staging: URL { directory.appendingPathComponent("save.pending") }
    private var backupStaging: URL { directory.appendingPathComponent("backup.pending") }

    public static func applicationSupportRoot() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
            .appendingPathComponent("GameCoreSaves", isDirectory: true)
    }

    public init(titleID: String, root: URL, defaultSettings: ShellSettings = ShellSettings(),
                supportedLanguages: [String] = ["en"]) throws {
        guard !titleID.isEmpty, titleID.utf8.count <= 80,
              titleID.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 })
        else { throw LocalSaveError.invalidTitleID }
        guard root.isFileURL, supportedLanguages.contains(defaultSettings.language),
              !supportedLanguages.isEmpty else { throw LocalSaveError.invalidSnapshot }
        self.titleID = titleID
        self.directory = root.appendingPathComponent(titleID, isDirectory: true)
        self.defaultSettings = defaultSettings
        self.supportedLanguages = supportedLanguages
    }

    public func load() throws -> SaveLoadResult {
        try prepareDirectory()
        let selected = try select()
        if selected.migrated && !selected.recovered {
            let migrated = try nextSnapshot(settings: selected.snapshot.settings,
                                            progress: selected.snapshot.progress, previous: selected.snapshot)
            try write(migrated, previous: selected.snapshot)
            return result(migrated, migrated: true)
        }
        return result(selected.snapshot, recovered: selected.recovered, migrated: selected.migrated)
    }

    public func save(settings: ShellSettings, progress: SaveProgress, generation token: UUID,
                     acknowledgeRecovery: Bool = false) throws -> SaveLoadResult {
        guard token == generation else { throw LocalSaveError.staleGeneration }
        try prepareDirectory()
        let selected = try select()
        guard !selected.recovered || acknowledgeRecovery else { throw LocalSaveError.recoveryRequired }
        let value = try nextSnapshot(settings: settings, progress: progress, previous: selected.snapshot)
        try write(value, previous: selected.exists ? selected.snapshot : nil)
        return result(value)
    }

    public func acknowledgeRecovery(generation token: UUID) throws -> SaveLoadResult {
        guard token == generation else { throw LocalSaveError.staleGeneration }
        try prepareDirectory()
        let selected = try select()
        guard selected.recovered else { return result(selected.snapshot) }
        let value = try nextSnapshot(settings: selected.snapshot.settings,
                                     progress: selected.snapshot.progress, previous: selected.snapshot)
        try write(value, previous: selected.snapshot)
        return result(value, migrated: selected.migrated)
    }

    /// Progress reset preserves preferences. Unrecoverable data cannot supply
    /// validated preferences; the player can instead explicitly delete all data.
    public func resetProgress(settings: ShellSettings? = nil) throws -> SaveLoadResult {
        generation = UUID()
        try prepareDirectory()
        let selected = try select()
        let value = try nextSnapshot(settings: settings ?? selected.snapshot.settings,
                                     progress: SaveProgress(), previous: selected.snapshot)
        // Both committed copies contain the reset state. A later recovery must
        // never resurrect progress that a successful reset erased.
        try write(value, previous: value)
        return result(value)
    }

    public func deleteLocalData() throws -> SaveLoadResult {
        generation = UUID()
        try prepareDirectory()
        try removeOwnedFiles()
        return result(defaultSnapshot())
    }

    /// Only a validated selected snapshot can leave the store. Export itself
    /// neither changes storage nor implicitly acknowledges backup recovery.
    public func exportData() throws -> Data {
        try prepareDirectory()
        return try encode(try select().snapshot)
    }

    private struct Selected {
        let snapshot: SaveSnapshot
        let recovered: Bool
        let migrated: Bool
        let exists: Bool
    }
    private struct VersionHeader: Decodable { let schemaVersion: Int }
    private struct Header: Decodable { let schemaVersion: Int; let titleID: String }
    private struct Legacy: Decodable {
        let schemaVersion: Int, titleID: String, revision: Int
        let completedLevelNumbers: [Int], bestScore: Int, soundEnabled: Bool
    }

    private func result(_ value: SaveSnapshot, recovered: Bool = false,
                        migrated: Bool = false) -> SaveLoadResult {
        SaveLoadResult(snapshot: value, generation: generation, recovered: recovered, migrated: migrated)
    }
    private func defaultSnapshot() -> SaveSnapshot {
        SaveSnapshot(titleID: titleID, settings: defaultSettings)
    }
    private func nextSnapshot(settings: ShellSettings, progress: SaveProgress,
                              previous: SaveSnapshot) throws -> SaveSnapshot {
        guard previous.revision < Int.max else { throw LocalSaveError.invalidSnapshot }
        let value = SaveSnapshot(titleID: titleID, revision: previous.revision + 1,
                                 settings: settings, progress: progress)
        guard valid(value) else { throw LocalSaveError.invalidSnapshot }
        return value
    }

    private func select() throws -> Selected {
        var damaged = false
        do {
            if let value = try read(current) {
                return Selected(snapshot: value.0, recovered: false, migrated: value.1, exists: true)
            }
        } catch LocalSaveError.corrupt { damaged = true }
        // Future/wrong-title versions and I/O errors never fall back or downgrade.
        if let value = try read(backup) {
            return Selected(snapshot: value.0, recovered: true, migrated: value.1, exists: true)
        }
        guard !damaged else { throw LocalSaveError.corrupt }
        return Selected(snapshot: defaultSnapshot(), recovered: false, migrated: false, exists: false)
    }

    private func read(_ url: URL) throws -> (SaveSnapshot, Bool)? {
        let attributes: [FileAttributeKey: Any]
        do { attributes = try manager.attributesOfItem(atPath: url.path) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
        catch { throw LocalSaveError.io(error.localizedDescription) }
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw LocalSaveError.corrupt }
        guard let count = attributes[.size] as? NSNumber, count.intValue <= maximumBytes else {
            throw LocalSaveError.oversized
        }
        let bytes: Data
        do { bytes = try Data(contentsOf: url) }
        catch { throw LocalSaveError.io(error.localizedDescription) }
        guard bytes.count <= maximumBytes else { throw LocalSaveError.oversized }
        let version: VersionHeader
        do { version = try JSONDecoder().decode(VersionHeader.self, from: bytes) }
        catch { throw LocalSaveError.corrupt }
        // A newer envelope can rename fields. Recognizing the version alone is
        // enough to preserve its bytes without interpreting today's shape.
        guard version.schemaVersion <= 2 else { throw LocalSaveError.futureVersion(version.schemaVersion) }
        guard [1, 2].contains(version.schemaVersion) else { throw LocalSaveError.unsupportedVersion(version.schemaVersion) }
        let header: Header
        do { header = try JSONDecoder().decode(Header.self, from: bytes) }
        catch { throw LocalSaveError.corrupt }
        guard header.titleID == titleID else { throw LocalSaveError.titleMismatch }
        guard header.schemaVersion <= 2 else { throw LocalSaveError.futureVersion(header.schemaVersion) }
        switch header.schemaVersion {
        case 2:
            guard let value = try? JSONDecoder().decode(SaveSnapshot.self, from: bytes), valid(value)
            else { throw LocalSaveError.corrupt }
            return (value, false)
        case 1:
            guard let old = try? JSONDecoder().decode(Legacy.self, from: bytes), old.revision >= 0,
                  old.bestScore >= 0, old.completedLevelNumbers.count <= 10_000,
                  old.completedLevelNumbers.allSatisfy({ $0 > 0 }),
                  Set(old.completedLevelNumbers).count == old.completedLevelNumbers.count
            else { throw LocalSaveError.corrupt }
            let value = SaveSnapshot(titleID: titleID, revision: old.revision,
                settings: ShellSettings(soundEnabled: old.soundEnabled, musicEnabled: old.soundEnabled,
                                        language: defaultSettings.language),
                progress: SaveProgress(completedLevels: old.completedLevelNumbers.sorted().map { "level-\($0)" },
                                       bestScores: ["legacy-total": old.bestScore], unlockedLevels: ["level-1"]))
            guard valid(value) else { throw LocalSaveError.corrupt }
            return (value, true)
        default: throw LocalSaveError.unsupportedVersion(header.schemaVersion)
        }
    }

    private func valid(_ value: SaveSnapshot) -> Bool {
        func identifier(_ value: String) -> Bool { !value.isEmpty && value.utf8.count <= 120 }
        return value.schemaVersion == 2 && value.titleID == titleID && value.revision >= 0 &&
            supportedLanguages.contains(value.settings.language) && value.settings.language.utf8.count <= 64 &&
            value.progress.bestScores.count <= 10_000 &&
            value.progress.bestScores.allSatisfy { identifier($0.key) && $0.value >= 0 } &&
            [value.progress.completedLevels, value.progress.unlockedLevels].allSatisfy {
                $0.count <= 10_000 && $0.allSatisfy(identifier) && Set($0).count == $0.count
            }
    }
    private func encode(_ value: SaveSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        guard data.count <= maximumBytes else { throw LocalSaveError.oversized }
        return data
    }

    private func write(_ value: SaveSnapshot, previous: SaveSnapshot?) throws {
        // Valid current is not permission to overwrite an alien/future backup.
        do { _ = try read(backup) }
        catch LocalSaveError.corrupt { }
        let data = try encode(value)
        if interruptAt == .partialStaging {
            try syncWrite(Data(data.prefix(data.count / 2)), to: staging)
            try stop(.partialStaging)
        }
        try syncWrite(data, to: staging)
        try stop(.staged)
        if let previous {
            try syncWrite(try encode(previous), to: backupStaging)
            try promote(backupStaging, to: backup)
        }
        try stop(.backupPromoted)
        try promote(staging, to: current)
        try stop(.currentPromoted)
    }

    private func stop(_ phase: WritePhase) throws {
        if interruptAt == phase { throw LocalSaveError.io("Injected interruption at \(phase)") }
    }
    func setInterruption(_ phase: WritePhase?) { interruptAt = phase }
    func setAttributeFailure(_ value: Bool) { failAttributes = value }

    private func prepareDirectory() throws {
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            let attributes = try manager.attributesOfItem(atPath: directory.path)
            guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw LocalSaveError.io("Invalid save directory") }
            try applyAttributes(directory)
        } catch let error as LocalSaveError { throw error }
          catch { throw LocalSaveError.io(error.localizedDescription) }
    }

    private func applyAttributes(_ url: URL) throws {
        if failAttributes { throw LocalSaveError.io("Injected unavailable file attributes") }
        #if os(iOS)
        do {
            try manager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                      ofItemAtPath: url.path)
            var resourceURL = url
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try resourceURL.setResourceValues(values)
            let actual = try resourceURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
            let attributes = try manager.attributesOfItem(atPath: url.path)
            let protectionValue = attributes[.protectionKey]
            let protectionName = (protectionValue as? FileProtectionType)?.rawValue ?? (protectionValue as? String)
            let protectionMatches: Bool
            #if targetEnvironment(simulator)
            // The iOS simulator accepts setAttributes but can omit Data
            // Protection metadata. Only that absence is a capability exception;
            // any present class must match, and real devices always verify it.
            protectionMatches = protectionValue == nil ||
                protectionName == FileProtectionType.completeUntilFirstUserAuthentication.rawValue
            #else
            protectionMatches = protectionName == FileProtectionType.completeUntilFirstUserAuthentication.rawValue
            #endif
            guard actual.isExcludedFromBackup == true, protectionMatches
            else {
                let protection = protectionValue.map { "\($0) (\(type(of: $0)))" } ?? "absent"
                throw LocalSaveError.io("Save file attributes were not applied: excluded=\(String(describing: actual.isExcludedFromBackup)); protection=\(protection)")
            }
        } catch let error as LocalSaveError { throw error }
          catch { throw LocalSaveError.io(error.localizedDescription) }
        #endif
    }

    private func syncWrite(_ bytes: Data, to url: URL) throws {
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, mode_t(0o600))
        guard descriptor >= 0 else { throw posixError("open") }
        var closed = false
        defer { if !closed { close(descriptor) } }
        try applyAttributes(url)
        try bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw posixError("write") }
                offset += count
            }
        }
        guard fsync(descriptor) == 0 else { throw posixError("fsync file") }
        closed = true
        guard close(descriptor) == 0 else { throw posixError("close file") }
    }
    private func promote(_ source: URL, to destination: URL) throws {
        guard rename(source.path, destination.path) == 0 else { throw posixError("rename") }
        try applyAttributes(destination)
        try syncDirectory()
    }
    private func syncDirectory() throws {
        let descriptor = open(directory.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw posixError("open directory") }
        let syncResult = fsync(descriptor)
        let syncErrno = errno
        let closeResult = close(descriptor)
        guard syncResult == 0 else { throw LocalSaveError.io("fsync directory errno=\(syncErrno)") }
        guard closeResult == 0 else { throw posixError("close directory") }
    }
    private func posixError(_ operation: String) -> LocalSaveError {
        .io("\(operation) errno=\(errno)")
    }
    private func removeOwnedFiles() throws {
        for url in [current, backup, staging, backupStaging] {
            do { try manager.removeItem(at: url) }
            catch let error as CocoaError where error.code == .fileNoSuchFile { continue }
            catch { throw LocalSaveError.io(error.localizedDescription) }
        }
        try syncDirectory()
    }
}
