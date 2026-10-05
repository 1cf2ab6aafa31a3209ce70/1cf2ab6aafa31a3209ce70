import Combine
import DevelopmentContent
import Foundation
import GameCore

/// Experiment-owned state. No renderer types, frame time or traces in saves.
@MainActor
final class RuleSession: ObservableObject, ModuleSession {
    let levelID: String
    @Published private(set) var level: DevelopmentLevel?
    @Published private(set) var removedIndices: [Int] = []
    @Published var playing = false
    @Published var settings = ShellSettings()
    @Published var reducedMotion = false
    private(set) var request: LoadRequest?
    private(set) var inputs: [TimedInput<FixtureAction>] = []
    private var preparationEpoch = UUID()
    private var staged: (LoadRequest, DevelopmentLevel)?
    private var finished = false
    var outcomeHandler: ((ShellOutcome, LoadRequest) -> Void)?
    init(levelID: String) { self.levelID = levelID }
    var columns: Int {
        switch level { case .block(let l): return l.payload.columns
        case .dig(let l): return l.payload.columns; default: return 1 }
    }
    var rows: Int {
        switch level { case .block(let l): return l.payload.rows
        case .dig(let l): return l.payload.rows; default: return 1 }
    }
    func prepare(for request: LoadRequest) async throws {
        try await prepare(for: request, loader: { try BundledContent.load() })
    }
    func recordSuccess(in progress: inout SaveProgress) {
        guard let level else { return }
        _ = progress.recordCompletion(levelID: level.id, score: 1)
    }
    func prepare(for request: LoadRequest, loader: () async throws -> DevelopmentCatalog) async throws {
        try Task.checkCancellation()
        let epoch = UUID()
        preparationEpoch = epoch
        staged = nil
        let catalog = try await loader()
        try Task.checkCancellation()
        guard preparationEpoch == epoch, request.titleID == catalog.envelope.titleID,
              let selected = catalog.levels.first(where: { $0.id == levelID }) else {
            throw ContentValidationError(message: "Missing selected level or superseded preparation")
        }
        staged = (request, selected)
    }
    func begin(for request: LoadRequest) {
        guard let staged, staged.0 == request else { return }
        self.staged = nil
        self.request = request
        inputs = []; removedIndices = []; finished = false
        level = staged.1
    }
    func select(index: Int) {
        guard playing, !finished, let level, let request, (0..<(columns * rows)).contains(index) else { return }
        let next = inputs + [TimedInput(tick: UInt64(inputs.count + 1) * 10, action: FixtureAction(index: index))]
        do {
            let result = try FixtureRules.replay(level: level, fixture: InputFixture(
                levelID: level.id, contentVersion: level.contentVersion, seed: level.seed, inputs: next))
            inputs = next
            removedIndices = result.removedIndices
            if result.completed { finish(.success, request: request) }
        } catch { finish(.failure, request: request) }
    }
    func fail() { guard playing, let request else { return }; finish(.failure, request: request) }
    private func finish(_ outcome: ShellOutcome, request: LoadRequest) {
        guard !finished else { return }
        finished = true
        outcomeHandler?(outcome, request)
    }
}
