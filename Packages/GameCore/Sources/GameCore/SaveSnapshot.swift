import Foundation

/// The shared progress contract contains identifiers and maxima, not game rules.
/// A title supplies explicit unlock identifiers after a successful completion.
public struct SaveProgress: Codable, Equatable, Sendable {
    public private(set) var completedLevels: [String]
    public private(set) var bestScores: [String: Int]
    public private(set) var unlockedLevels: [String]

    public init(completedLevels: [String] = [], bestScores: [String: Int] = [:],
                unlockedLevels: [String] = []) {
        self.completedLevels = completedLevels
        self.bestScores = bestScores
        self.unlockedLevels = unlockedLevels
    }

    /// Repeated callbacks cannot duplicate completion/unlocks or reduce a best score.
    @discardableResult
    public mutating func recordCompletion(levelID: String, score: Int? = nil,
                                          unlocks: [String] = []) -> Bool {
        let previous = self
        if !completedLevels.contains(levelID) { completedLevels.append(levelID) }
        completedLevels.sort()
        if let score, score >= 0 { bestScores[levelID] = max(bestScores[levelID] ?? 0, score) }
        unlockedLevels = Array(Set(unlockedLevels + unlocks)).sorted()
        return previous != self
    }
}

/// Version 2 retains the Spike 03 JSON wire format, including effectsEnabled.
public struct SaveSnapshot: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let titleID: String
    public let revision: Int
    public let settings: ShellSettings
    public let progress: SaveProgress

    public init(schemaVersion: Int = 2, titleID: String, revision: Int = 0,
                settings: ShellSettings = ShellSettings(), progress: SaveProgress = SaveProgress()) {
        self.schemaVersion = schemaVersion
        self.titleID = titleID
        self.revision = revision
        self.settings = settings
        self.progress = progress
    }
}

/// A generation belongs to one store lifetime; reset/delete invalidates old writes.
public struct SaveLoadResult: Equatable, Sendable {
    public let snapshot: SaveSnapshot
    public let generation: UUID
    public let recovered: Bool
    public let migrated: Bool

    public init(snapshot: SaveSnapshot, generation: UUID, recovered: Bool = false, migrated: Bool = false) {
        self.snapshot = snapshot
        self.generation = generation
        self.recovered = recovered
        self.migrated = migrated
    }
}
