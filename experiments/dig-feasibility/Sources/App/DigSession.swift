import Combine
import DevelopmentContent
import DigCore
import Foundation
import GameCore
import GamePlatform

/// What the shell-facing views show. Published at most twice a second, and at once when
/// score or cursor change, so SwiftUI work stays out of the measured frames.
struct DigStatus: Equatable {
    var score = 0
    var total = 0
    var revision: UInt64 = 0
    var tick: UInt64 = 0
    var cursor = SIMD2<Float>(0, 0)
    var accepted = 0
}

/// Developer run state, read by UI tests (Debug only).
struct RunStatus: Equatable {
    var state = "idle"
    var summary = "{}"
}

/// Title-owned session: the gate for every gameplay input. Touch, accessible controls and
/// the Debug trace driver all call `submit(_:phase:)`, which refuses input unless the shell
/// says the session is playing. Rule state, renderer and physics stay behind `engine`;
/// none of their types cross the module contract.
@MainActor
final class DigSession: ObservableObject, ModuleSession {
    static let levelID = "dig-sample-01"
    let options: DigOptions
    let engine: any DigEngine
    @Published var playing = false {
        didSet { if oldValue != playing { engine.setPlaying(playing) } }
    }
    @Published var settings = ShellSettings()
    @Published private(set) var status = DigStatus()
    @Published private(set) var run = RunStatus()
    var outcomeHandler: ((ShellOutcome, LoadRequest) -> Void)?
    private(set) var request: LoadRequest?
    private var staged: LoadRequest?
    private var preparationEpoch = UUID()
    private var finished = false
    #if DEBUG
    private(set) lazy var driver = TraceDriver(session: self)
    #endif

    init(options: DigOptions) {
        self.options = options
        switch options.candidate {
        case .heightfield, .lowlevel: engine = RealityDigEngine<HeightfieldField>(options: options)
        case .voxel: engine = RealityDigEngine<VoxelField>(options: options)
        case .sprite: engine = SpriteDigEngine(options: options)
        }
        engine.onStatus = { [weak self] in self?.update($0) }
        engine.submitThroughSession = { [weak self] command, phase in self?.submit(command, phase: phase) ?? false }
    }

    func prepare(for request: LoadRequest) async throws {
        try Task.checkCancellation()
        let epoch = UUID()
        preparationEpoch = epoch
        staged = nil
        let catalog = try BundledContent.load()
        try Task.checkCancellation()
        guard preparationEpoch == epoch, request.titleID == catalog.envelope.titleID,
              let level = catalog.levels.first(where: { $0.id == Self.levelID }), case .dig = level else {
            throw ContentValidationError(message: "Missing dig level or superseded preparation")
        }
        staged = request
    }

    func begin(for request: LoadRequest) {
        guard staged == request else { return }
        staged = nil
        self.request = request
        finished = false
        #if DEBUG
        driver.cancel()
        #endif
        engine.begin()
    }

    /// The one gated input method.
    @discardableResult
    func submit(_ command: DigCommand, phase: String = "input") -> Bool {
        guard playing, request != nil, !finished else { return false }
        return engine.accept(command, phase: phase)
    }

    /// Rebuilds the renderer scene from the current rule state; rules are untouched.
    func reloadScene() {
        guard playing, request != nil else { return }
        #if DEBUG
        let before = engine.probe
        engine.reloadScene()
        driver.observeReload(before: before)
        #else
        engine.reloadScene()
        #endif
    }

    func fail() {
        guard playing, let request else { return }
        finish(.failure, request: request)
    }

    func recordSuccess(in progress: inout SaveProgress) {
        _ = progress.recordCompletion(levelID: Self.levelID, score: status.score)
    }

    func setRun(_ state: String, summary: String? = nil) {
        var next = run
        next.state = state
        if let summary { next.summary = summary }
        if next != run { run = next }
    }

    private func update(_ next: DigStatus) {
        if next != status { status = next }
        if let request, next.total > 0, next.score == next.total { finish(.success, request: request) }
    }

    private func finish(_ outcome: ShellOutcome, request: LoadRequest) {
        guard !finished else { return }
        finished = true
        outcomeHandler?(outcome, request)
    }
}
