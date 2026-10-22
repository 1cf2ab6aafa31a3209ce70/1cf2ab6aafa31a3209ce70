import DigCore
import Foundation
import GameCore
import UIKit

/// Title-owned renderer and rule loop. Never crosses the module contract.
@MainActor
protocol DigEngine: AnyObject {
    var view: UIView { get }
    var candidate: DigCandidate { get }
    var metrics: DigMetrics { get }
    var probe: DigProbe { get }
    var onStatus: ((DigStatus) -> Void)? { get set }
    /// Set by the session; touch input calls it so touch takes the same gated path as controls.
    var submitThroughSession: ((DigCommand, String) -> Bool)? { get set }
    /// While a scripted trace runs, surface touches are ignored so they cannot alter it.
    var scripted: Bool { get set }
    func begin()
    func reloadScene()
    func setPlaying(_ playing: Bool)
    func accept(_ command: DigCommand, phase: String) -> Bool
    func setReducedMotion(_ reduced: Bool)
    func expectation() async -> DigExpectation
    func commandLog(since start: ContinuousClock.Instant) -> [[String: Any]]
    func lagReport(phase: String?) -> [String: Any]
    var physicsReport: [[String: Any]] { get }
    var pauseReport: [[String: Any]] { get }
}

struct DigProbe {
    var score = 0
    var collected: Set<Int> = []
    var revision: UInt64 = 0
    var tick: UInt64 = 0
    var digest: UInt64 = 0
    var outcomeDigest: UInt64 = 0
    var pending = 0
    var meshCurrent = false
    var collisionCurrent = false
    var reloadComplete = false
    var physicsSettled = true
    var entities = 0
    var subscriptions = 0
    var restoredInitialState = true
}

/// Headless replay of the fixture on the same build and device: the live run must match it.
struct DigExpectation: Sendable {
    var prefixDigest: UInt64
    var afterS: Set<Int>
    var afterB: Set<Int>
    var finalDigest: UInt64

    static func make<Field: ExcavationField>(_ type: Field.Type) -> DigExpectation {
        var rules = DigRules<Field>(workload: Spike11Fixture.workload)
        Spike11Fixture.replay(Array(Spike11Fixture.traceS.prefix(100)), into: &rules, perTick: 1)
        let prefix = Spike11Fixture.outcomeDigest(rules)
        Spike11Fixture.replay(Array(Spike11Fixture.traceS.dropFirst(100)), into: &rules, perTick: 1)
        let afterS = Set(rules.collectibles.filter(\.isCollected).map(\.id))
        Spike11Fixture.replay(Spike11Fixture.traceB, into: &rules, perTick: 1)
        return DigExpectation(prefixDigest: prefix, afterS: afterS,
                              afterB: Set(rules.collectibles.filter(\.isCollected).map(\.id)),
                              finalDigest: Spike11Fixture.outcomeDigest(rules))
    }
}

struct CommandRecord {
    let phase: String
    let acceptedAt: ContinuousClock.Instant
    var consumed = false
    /// Field revision this command contributed to; nil when the dig changed nothing.
    var revision: UInt64?
    var meshLagMs: Double?
    var collisionLagMs: Double?
}

/// Shared rule loop and pending-geometry bookkeeping for every candidate.
///
/// Frame callbacks run `advance(frameDelta:)`; frame cadence only decides how many fixed
/// ticks run. Mesh and collision jobs follow `GeometrySync`: one job per lane in flight,
/// coalesced to the latest revision, installed only for the current scene epoch and rule
/// generation. A job finishing while paused is discarded and its region re-queued for
/// resume. Input never waits for geometry.
@MainActor
class RuleEngine<Field: ExcavationField>: DigEngine {
    let options: DigOptions
    let workload = Spike11Fixture.workload
    let metrics = DigMetrics()
    var onStatus: ((DigStatus) -> Void)?
    var submitThroughSession: ((DigCommand, String) -> Bool)?
    var scripted = false
    private(set) var rules: DigRules<Field>
    private(set) var sync: GeometrySync
    private(set) var paused = true
    private(set) var sceneEpoch = 0
    private(set) var reloadComplete = false
    private(set) var restoredInitialState = true
    private(set) var pauses: [[String: Any]] = []
    private let initialDigest: UInt64
    private let expectationTask: Task<DigExpectation, Never>
    private var records: [CommandRecord] = []
    private var consumedIndex = 0
    private var meshIndex = 0
    private var collisionIndex = 0
    private var lastTimestamp: TimeInterval?
    private var reloadStart: ContinuousClock.Instant?
    private var reloadMeshMs: Double?
    private var reloadKind = "load"
    private var loads = 0
    private var lastStatus = DigStatus()
    private var lastStatusTime: TimeInterval = 0
    private var lastTouch: SIMD2<Float>?
    private var pauseStarted: ContinuousClock.Instant?

    init(options: DigOptions) {
        self.options = options
        rules = DigRules<Field>(workload: Spike11Fixture.workload)
        sync = GeometrySync(field: rules.field, collisionInterval: 0)
        initialDigest = rules.digest
        expectationTask = Task.detached(priority: .utility) { DigExpectation.make(Field.self) }
    }

    var candidate: DigCandidate { options.candidate }
    var view: UIView { preconditionFailure("Subclass supplies the view") }
    var usesCollision: Bool { true }

    // MARK: Subclass hooks

    func buildScene() {}
    func teardownScene() {}
    func startMeshJob(_ job: GeometrySync.Job, field: Field, epoch: Int) {}
    func startCollisionJob(_ job: GeometrySync.Job, field: Field, epoch: Int) {}
    func frameHook(now: TimeInterval) {}
    func collectedHook(_ ids: [Int]) {}
    func pauseHook(_ paused: Bool) -> Double? { nil }
    func setReducedMotion(_ reduced: Bool) {}
    var entityCount: Int { 0 }
    var subscriptionCount: Int { 0 }
    var physicsSettled: Bool { true }
    var physicsReport: [[String: Any]] { [] }
    var pauseReport: [[String: Any]] { pauses }

    // MARK: Lifecycle

    /// Fresh rule state for a new shell request, then a full scene reload.
    func begin() {
        let report = rules.restart()
        rules.isPaused = paused
        restoredInitialState = rules.digest == initialDigest && rules.score == 0 && rules.revision == 0
        records.removeAll()
        consumedIndex = 0; meshIndex = 0; collisionIndex = 0
        lastTouch = nil
        sync.record(report)
        loads += 1
        reload(kind: loads == 1 ? "load" : "restart")
    }

    /// Rebuilds every renderer entity from the current rule field; rules are unchanged.
    func reloadScene() {
        sync = GeometrySync(field: rules.field, collisionInterval: 0)
        var report = DigFrameReport()
        report.revision = rules.revision
        sync.record(report)
        reload(kind: "scene")
    }

    private func reload(kind: String) {
        sceneEpoch += 1
        metrics.breakSequence()
        lastTimestamp = nil
        reloadStart = .now
        reloadMeshMs = nil
        reloadKind = kind
        reloadComplete = false
        teardownScene()
        buildScene()
        publish(force: true)
        issueJobs()
    }

    func setPlaying(_ playing: Bool) {
        guard paused == playing else { return }
        paused = !playing
        rules.isPaused = paused
        lastTimestamp = nil
        metrics.breakSequence()
        let drift = pauseHook(paused)
        if paused {
            pauseStarted = .now
            pauses.append(["tick": rules.tick, "revision": rules.revision])
        } else if let started = pauseStarted, !pauses.isEmpty {
            pauses[pauses.count - 1]["seconds"] = DigMetrics.round3(started.duration(to: .now).milliseconds / 1_000)
            pauses[pauses.count - 1]["tickAfter"] = rules.tick
            if let drift { pauses[pauses.count - 1]["sphereDrift"] = DigMetrics.round3(drift) }
            pauseStarted = nil
        }
        publish(force: true)
        if playing { issueJobs() }
    }

    func accept(_ command: DigCommand, phase: String) -> Bool {
        guard !paused, rules.schedule(command) else { return false }
        records.append(CommandRecord(phase: phase, acceptedAt: .now))
        return true
    }

    /// Converts a surface touch on the rule field into a dig through the session gate.
    func touchDig(at point: SIMD2<Float>, began: Bool) {
        guard !scripted else { return }
        if !began, let last = lastTouch {
            let delta = point - last
            guard (delta * delta).sum() >= (rules.field.cellSize * 0.4) * (rules.field.cellSize * 0.4) else { return }
        }
        lastTouch = point
        _ = submitThroughSession?(.dig(x: point.x, z: point.y), "touch")
    }

    // MARK: Frame loop

    func frame(timestamp: TimeInterval) {
        guard !paused else { return }
        let delta = lastTimestamp.map { timestamp - $0 } ?? 0
        lastTimestamp = timestamp
        metrics.recordFrame(timestamp)
        let pendingBefore = rules.pendingCommandCount
        let report = rules.advance(frameDelta: delta)
        sync.record(report)
        let consumed = pendingBefore - rules.pendingCommandCount
        if consumed > 0 {
            let revision: UInt64? = report.dirty.isEmpty ? nil : report.revision
            for index in consumedIndex..<min(records.count, consumedIndex + consumed) {
                records[index].consumed = true
                records[index].revision = revision
            }
            consumedIndex = min(records.count, consumedIndex + consumed)
        }
        if !report.collected.isEmpty { collectedHook(report.collected) }
        issueJobs()
        frameHook(now: timestamp)
        publish(force: false)
    }

    func issueJobs() {
        guard !paused else { return }
        if let job = sync.nextMeshJob() { startMeshJob(job, field: rules.field, epoch: sceneEpoch) }
        if usesCollision, let job = sync.nextCollisionJob(tick: rules.tick) {
            startCollisionJob(job, field: rules.field, epoch: sceneEpoch)
        }
    }

    /// True when a finished job may be installed now. Stale epochs are dropped; a job
    /// finishing while paused is discarded and its region re-queued for resume.
    func shouldInstall(_ job: GeometrySync.Job, epoch: Int) -> Bool {
        guard epoch == sceneEpoch else { return false }
        if paused {
            sync.abandon(job)
            return false
        }
        return sync.complete(job)
    }

    func abandon(_ job: GeometrySync.Job, epoch: Int) {
        guard epoch == sceneEpoch else { return }
        sync.abandon(job)
    }

    func didInstall(_ job: GeometrySync.Job) {
        let now = ContinuousClock.now
        switch job.lane {
        case .mesh:
            while meshIndex < consumedIndex {
                if let revision = records[meshIndex].revision {
                    guard revision <= job.revision else { break }
                    records[meshIndex].meshLagMs = records[meshIndex].acceptedAt.duration(to: now).milliseconds
                }
                meshIndex += 1
            }
        case .collision:
            while collisionIndex < consumedIndex {
                if let revision = records[collisionIndex].revision {
                    guard revision <= job.revision else { break }
                    records[collisionIndex].collisionLagMs = records[collisionIndex].acceptedAt.duration(to: now).milliseconds
                }
                collisionIndex += 1
            }
        }
        if let start = reloadStart {
            if reloadMeshMs == nil, sync.isMeshCurrent { reloadMeshMs = start.duration(to: now).milliseconds }
            if sync.isMeshCurrent, !usesCollision || sync.isCollisionCurrent {
                let total = start.duration(to: now).milliseconds
                metrics.recordReload(.init(kind: reloadKind, ms: total, meshMs: reloadMeshMs ?? total))
                reloadStart = nil
                reloadComplete = true
            }
        }
        issueJobs()
    }

    // MARK: Status and reports

    private func publish(force: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        let status = DigStatus(score: rules.score, total: rules.collectibles.count, revision: rules.revision,
                               tick: rules.tick, cursor: rules.cursor, accepted: records.count)
        guard status != lastStatus else { return }
        guard force || status.score != lastStatus.score || status.cursor != lastStatus.cursor
                || now - lastStatusTime >= 0.5 else { return }
        lastStatus = status
        lastStatusTime = now
        onStatus?(status)
    }

    var probe: DigProbe {
        DigProbe(score: rules.score, collected: Set(rules.collectibles.filter(\.isCollected).map(\.id)),
                 revision: rules.revision, tick: rules.tick, digest: rules.digest,
                 outcomeDigest: Spike11Fixture.outcomeDigest(rules), pending: rules.pendingCommandCount,
                 meshCurrent: sync.isMeshCurrent, collisionCurrent: !usesCollision || sync.isCollisionCurrent,
                 reloadComplete: reloadComplete, physicsSettled: physicsSettled, entities: entityCount,
                 subscriptions: subscriptionCount, restoredInitialState: restoredInitialState)
    }

    func expectation() async -> DigExpectation { await expectationTask.value }

    func commandLog(since start: ContinuousClock.Instant) -> [[String: Any]] {
        records.enumerated().map { index, record in
            var entry: [String: Any] = ["k": index, "phase": record.phase,
                                        "acceptedMs": DigMetrics.round3(start.duration(to: record.acceptedAt).milliseconds)]
            if let revision = record.revision { entry["revision"] = revision }
            if let lag = record.meshLagMs { entry["meshLagMs"] = DigMetrics.round3(lag) }
            if let lag = record.collisionLagMs { entry["collisionLagMs"] = DigMetrics.round3(lag) }
            return entry
        }
    }

    func lagReport(phase: String?) -> [String: Any] {
        let selected = records.filter { phase == nil || $0.phase == phase }
        let changed = selected.filter { $0.revision != nil }
        var report: [String: Any] = ["commands": selected.count, "changing": changed.count,
                                     "meshLagMs": DigMetrics.stats(changed.compactMap(\.meshLagMs)),
                                     "meshUnresolved": changed.filter { $0.meshLagMs == nil }.count]
        if usesCollision {
            report["collisionLagMs"] = DigMetrics.stats(changed.compactMap(\.collisionLagMs))
            report["collisionUnresolved"] = changed.filter { $0.collisionLagMs == nil }.count
        }
        return report
    }
}

/// UIKit gesture targets cannot live in a generic class; this relays them as closures.
@MainActor
final class GestureRelay: NSObject {
    private var handler: ((CGPoint, Bool) -> Void)?

    func attach(to view: UIView, handler: @escaping (CGPoint, Bool) -> Void) {
        self.handler = handler
        let pan = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tap(_:))))
    }

    @objc private func pan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began: handler?(gesture.location(in: gesture.view), true)
        case .changed: handler?(gesture.location(in: gesture.view), false)
        default: break
        }
    }

    @objc private func tap(_ gesture: UITapGestureRecognizer) {
        if gesture.state == .ended { handler?(gesture.location(in: gesture.view), true) }
    }
}
