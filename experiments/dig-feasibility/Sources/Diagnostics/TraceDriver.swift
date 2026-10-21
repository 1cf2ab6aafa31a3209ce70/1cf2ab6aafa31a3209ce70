#if DEBUG
import DigCore
import Foundation
import UIKit

/// Debug-only driver for the Spike 11 fixture. It issues command k at t0 + k / rate on
/// ContinuousClock through the session's gated `submit`, the same path as touch and the
/// accessible controls. Waits are pause-aware: while the shell is not playing, nothing is
/// submitted and the schedule shifts by the paused time, so no command is dropped.
///
/// Runs write a JSON report to the app's Documents directory (a local developer fixture;
/// verify.py copies it out of the simulator) and a compact summary for the UI test.
@MainActor
final class TraceDriver {
    enum Kind: String { case timing, prefix, fast }

    private weak var session: DigSession?
    private var task: Task<Void, Never>?
    private var pausedTotal: Duration = .zero
    private var cycles: [[String: Any]] = []
    private var refused = 0
    private var runStart = ContinuousClock.now

    init(session: DigSession) { self.session = session }

    func cancel() {
        task?.cancel()
        task = nil
        session?.engine.scripted = false
    }

    func start(_ kind: Kind) {
        guard task == nil, let session, session.playing else { return }
        session.engine.scripted = true
        task = Task { [weak self] in
            do {
                try await self?.run(kind)
            } catch {
                self?.session?.setRun("cancelled")
            }
            self?.session?.engine.scripted = false
            self?.task = nil
        }
    }

    private func run(_ kind: Kind) async throws {
        guard let session else { return }
        refused = 0
        switch kind {
        case .timing: try await runTiming(session)
        case .prefix: try await runPrefix(session)
        case .fast: try await runFast(session)
        }
    }

    // MARK: Runs

    /// Load, 5 s warm-up, I (10 s idle), S (600 commands at 10/s over 60 s),
    /// B (300 commands at 30/s over 10 s), then settle for at most 15 s.
    private func runTiming(_ session: DigSession) async throws {
        let engine = session.engine
        engine.metrics.resetSamples()
        runStart = .now
        session.setRun("warm-up")
        engine.metrics.snapshotFootprint("start")
        var phase = beginPhase()
        try await wait(phase, .seconds(5))
        engine.metrics.begin("I")
        session.setRun("I")
        try await wait(phase, .seconds(15))
        engine.metrics.end()
        engine.metrics.snapshotFootprint("after I")

        session.setRun("S")
        phase = beginPhase()
        engine.metrics.begin("S")
        for (k, command) in Spike11Fixture.traceS.enumerated() {
            try await wait(phase, .milliseconds(100 * k))
            submit(command, "S")
        }
        try await wait(phase, .seconds(60))
        engine.metrics.end()
        try await waitConsumed()
        let afterS = engine.probe
        engine.metrics.snapshotFootprint("after S")

        session.setRun("B")
        phase = beginPhase()
        engine.metrics.begin("B")
        for (k, command) in Spike11Fixture.traceB.enumerated() {
            try await wait(phase, .nanoseconds(Int64(k) * 1_000_000_000 / Int64(Spike11Fixture.bRate)))
            submit(command, "B")
        }
        try await wait(phase, .seconds(10))
        engine.metrics.end()
        try await waitConsumed()
        let afterB = engine.probe
        engine.metrics.snapshotFootprint("after B")

        session.setRun("settle")
        let settleMs = try await settle()
        engine.metrics.snapshotFootprint("after settle")
        let final = engine.probe
        let expected = await engine.expectation()
        var summary = scoreSummary(kind: .timing, afterS: afterS, afterB: afterB, final: final, expected: expected)
        summary["settleMs"] = DigMetrics.round3(settleMs)
        summary["settled"] = final.meshCurrent && final.collisionCurrent && final.physicsSettled
        finish(session, kind: .timing, summary: summary, extra: [:])
    }

    /// One restart cycle: after a shell restart, the first 100 commands of S, a settle,
    /// 2 s idle, then a footprint snapshot and entity/subscription counts.
    private func runPrefix(_ session: DigSession) async throws {
        let engine = session.engine
        if cycles.isEmpty {
            engine.metrics.resetSamples()
            runStart = .now
        }
        let cycle = cycles.count + 1
        session.setRun("cycle \(cycle) running")
        let restored = engine.probe
        let reloadWaitStart = ContinuousClock.now
        while !engine.probe.reloadComplete, reloadWaitStart.duration(to: .now) < .seconds(10) {
            try await Task.sleep(for: .milliseconds(20))
        }
        engine.metrics.begin("R")
        let phase = beginPhase()
        for (k, command) in Spike11Fixture.traceS.prefix(100).enumerated() {
            try await wait(phase, .milliseconds(100 * k))
            submit(command, "R")
        }
        try await waitConsumed()
        let settleMs = try await settle()
        try await Task.sleep(for: .seconds(2))
        engine.metrics.end()
        let footprint = engine.metrics.snapshotFootprint("cycle \(cycle)")
        let probe = engine.probe
        let expected = await engine.expectation()
        let reload = engine.metrics.reloads.last
        let record: [String: Any] = [
            "cycle": cycle,
            "restoredInitialState": restored.restoredInitialState && restored.revision == 0 && restored.score == 0,
            "reloadKind": reload?.kind ?? "none", "reloadMs": DigMetrics.round3(reload?.ms ?? -1),
            "reloadMeshMs": DigMetrics.round3(reload?.meshMs ?? -1),
            "footprintMiB": DigMetrics.mib(Int64(footprint.bytes)), "peakMiB": DigMetrics.mib(footprint.peak),
            "entities": probe.entities, "subscriptions": probe.subscriptions,
            "score": probe.score, "matchesReplay": probe.outcomeDigest == expected.prefixDigest,
            "settleMs": DigMetrics.round3(settleMs), "refused": refused,
        ]
        cycles.append(record)
        var summary = record
        summary["candidate"] = engine.candidate.rawValue
        summary["kind"] = Kind.prefix.rawValue
        finish(session, kind: .prefix, summary: summary, extra: ["cycles": cycles], state: "cycle \(cycle) done")
    }

    /// The same 900 commands at 60 per second, for correctness variants (delays, frame
    /// rate, pause and resume). Not a timing run.
    private func runFast(_ session: DigSession) async throws {
        let engine = session.engine
        engine.metrics.resetSamples()
        runStart = .now
        session.setRun("fast S")
        var phase = beginPhase()
        for (k, command) in Spike11Fixture.traceS.enumerated() {
            try await wait(phase, .nanoseconds(Int64(k) * 1_000_000_000 / 60))
            submit(command, "S")
        }
        try await waitConsumed()
        let afterS = engine.probe
        session.setRun("fast B")
        phase = beginPhase()
        for (k, command) in Spike11Fixture.traceB.enumerated() {
            try await wait(phase, .nanoseconds(Int64(k) * 1_000_000_000 / 60))
            submit(command, "B")
        }
        try await waitConsumed()
        let afterB = engine.probe
        session.setRun("settle")
        let settleMs = try await settle()
        let final = engine.probe
        let expected = await engine.expectation()
        var summary = scoreSummary(kind: .fast, afterS: afterS, afterB: afterB, final: final, expected: expected)
        summary["settleMs"] = DigMetrics.round3(settleMs)
        summary["pauses"] = engine.pauseReport.count
        summary["maxSphereDrift"] = engine.pauseReport.compactMap { $0["sphereDrift"] as? Double }.max() ?? 0
        summary["pausedTickAdvance"] = engine.pauseReport.compactMap { entry -> Int? in
            guard let before = entry["tick"] as? UInt64, let after = entry["tickAfter"] as? UInt64 else { return nil }
            return Int(after) - Int(before)
        }.max() ?? 0
        finish(session, kind: .fast, summary: summary, extra: [:])
    }

    /// After "Reload scene": wait until every chunk is rebuilt, then report.
    func observeReload(before: DigProbe) {
        guard let session else { return }
        let engine = session.engine
        session.setRun("reloading")
        Task { [weak self] in
            let start = ContinuousClock.now
            while !engine.probe.reloadComplete, start.duration(to: .now) < .seconds(10) {
                try? await Task.sleep(for: .milliseconds(20))
            }
            let after = engine.probe
            let reload = engine.metrics.reloads.last
            let summary: [String: Any] = [
                "candidate": engine.candidate.rawValue, "kind": "scene-reload",
                "digestUnchanged": before.outcomeDigest == after.outcomeDigest && before.revision == after.revision, "reloadComplete": after.reloadComplete,
                "reloadKind": reload?.kind ?? "none", "reloadMs": DigMetrics.round3(reload?.ms ?? -1),
                "entitiesBefore": before.entities, "entitiesAfter": after.entities,
                "subscriptionsBefore": before.subscriptions, "subscriptionsAfter": after.subscriptions,
            ]
            self?.session?.setRun("reloaded", summary: Self.json(summary))
        }
    }

    // MARK: Helpers

    private func submit(_ command: DigCommand, _ phase: String) {
        if session?.submit(command, phase: phase) != true { refused += 1 }
    }

    private func beginPhase() -> ContinuousClock.Instant {
        pausedTotal = .zero
        return .now
    }

    /// Sleeps until `start + offset`, extended by any time spent paused.
    private func wait(_ start: ContinuousClock.Instant, _ offset: Duration) async throws {
        while true {
            try Task.checkCancellation()
            if session?.playing != true {
                let pausedAt = ContinuousClock.now
                while session?.playing != true {
                    try await Task.sleep(for: .milliseconds(50))
                }
                pausedTotal += pausedAt.duration(to: .now)
                continue
            }
            let due = start + offset + pausedTotal
            let now = ContinuousClock.now
            if now >= due { return }
            try await Task.sleep(until: min(due, now + .milliseconds(50)), clock: .continuous)
        }
    }

    private func waitConsumed() async throws {
        let start = ContinuousClock.now
        while let engine = session?.engine, engine.probe.pending > 0, start.duration(to: .now) < .seconds(30) {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Waits until mesh and collision describe the latest revision and the probes rest; 15 s at most.
    private func settle() async throws -> Double {
        let start = ContinuousClock.now
        while let engine = session?.engine, start.duration(to: .now) < .seconds(15) {
            let probe = engine.probe
            if probe.meshCurrent && probe.collisionCurrent && probe.physicsSettled { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        return start.duration(to: .now).milliseconds
    }

    private func scoreSummary(kind: Kind, afterS: DigProbe, afterB: DigProbe, final: DigProbe,
                              expected: DigExpectation) -> [String: Any] {
        let controls = Spike11Fixture.controlIDs
        return [
            "candidate": session?.engine.candidate.rawValue ?? "unknown", "kind": kind.rawValue,
            "scoreAfterS": afterS.score, "collectedAfterS": afterS.collected.sorted(),
            "scoreAfterB": afterB.score, "collectedAfterB": afterB.collected.sorted(),
            "finalScore": final.score, "refused": refused,
            "matchesReplay": afterS.collected == expected.afterS && afterB.collected == expected.afterB
                && afterB.outcomeDigest == expected.finalDigest && final.collected == afterB.collected,
            "meetsFixture": afterS.collected == Spike11Fixture.expectedCollectedAfterS
                && afterB.collected == Spike11Fixture.expectedCollectedAfterB && afterB.collected.isDisjoint(with: controls),
            "controlsCollected": afterB.collected.intersection(controls).sorted(),
        ]
    }

    private func finish(_ session: DigSession, kind: Kind, summary: [String: Any], extra: [String: Any],
                        state: String = "done") {
        let engine = session.engine
        let file = "dig-\(engine.candidate.rawValue)-\(session.options.runLabel)-\(kind.rawValue).json"
        var report: [String: Any] = [
            "schema": 1, "candidate": engine.candidate.rawValue, "label": session.options.runLabel, "kind": kind.rawValue,
            "host": Self.hostInfo(),
            "options": ["meshDelayMs": session.options.meshDelay.milliseconds,
                        "collisionDelayMs": session.options.collisionDelay.milliseconds,
                        "preferredFramesPerSecond": session.options.preferredFramesPerSecond ?? 0],
            "instrumentation": [
                "intervals": engine.candidate == .sprite ? "SKScene.update currentTime deltas" : "SceneEvents.Update callback, ProcessInfo.systemUptime deltas",
                "mesh": engine.candidate == .sprite ? "ContinuousClock: band computation plus setTileGroup, main actor"
                    : engine.candidate == .lowlevel ? "ContinuousClock: geometry(for:) off the main actor, then a CPU LowLevelMesh vertex-buffer rewrite on the main actor"
                    : "ContinuousClock: geometry(for:) off the main actor, then MeshDescriptor + MeshResource.generate on the main actor",
                "collision": engine.candidate == .sprite ? "none" : "ContinuousClock wall time per ShapeResource.generateStaticMesh(positions:faceIndices:) chunk, serial within a job, including the async wait",
                "memory": "task_info TASK_VM_INFO phys_footprint snapshots and ledger_phys_footprint_peak",
                "note": "Simulator diagnostics on the Mac host; not presented frames and not device performance",
            ],
            "summary": summary,
            "windows": engine.metrics.intervalReport(),
            "mesh": ["all": engine.metrics.meshReport(window: nil), "S": engine.metrics.meshReport(window: "S"),
                     "B": engine.metrics.meshReport(window: "B"), "R": engine.metrics.meshReport(window: "R")],
            "collision": ["all": engine.metrics.collisionReport(window: nil), "S": engine.metrics.collisionReport(window: "S"),
                          "B": engine.metrics.collisionReport(window: "B"), "R": engine.metrics.collisionReport(window: "R")],
            "lag": ["S": engine.lagReport(phase: "S"), "B": engine.lagReport(phase: "B"), "R": engine.lagReport(phase: "R")],
            "reloads": engine.metrics.reloadReport(),
            "footprints": engine.metrics.footprintReport(),
            "physics": engine.physicsReport,
            "pauses": engine.pauseReport,
            "failures": engine.metrics.failures,
            "commands": engine.commandLog(since: runStart),
        ]
        report.merge(extra) { _, new in new }
        var compact = summary
        compact["file"] = file
        compact["written"] = Self.write(report, name: file)
        session.setRun(state, summary: Self.json(compact))
    }

    private static func write(_ report: [String: Any], name: String) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) else { return false }
        do {
            try data.write(to: URL.documentsDirectory.appending(path: name), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func json(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    private static func hostInfo() -> [String: Any] {
        let environment = ProcessInfo.processInfo.environment
        let screen = UIScreen.main
        return ["simulatorModel": environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "unknown",
                "simulatorDevice": environment["SIMULATOR_DEVICE_NAME"] ?? "unknown",
                "simulatorRuntime": environment["SIMULATOR_RUNTIME_VERSION"] ?? "unknown",
                "simulatorRuntimeBuild": environment["SIMULATOR_RUNTIME_BUILD_VERSION"] ?? "unknown",
                "systemVersion": UIDevice.current.systemVersion,
                "screenPoints": [screen.bounds.width, screen.bounds.height], "scale": screen.scale,
                "processors": ProcessInfo.processInfo.activeProcessorCount]
    }
}
#endif
