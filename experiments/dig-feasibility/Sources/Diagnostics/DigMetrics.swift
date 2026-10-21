import Darwin
import Foundation

/// Local, in-memory diagnostics for this disposable experiment (patterns from
/// platform-baseline's FrameStatistics and ProbeMetrics). No persistence beyond the Debug
/// report file, no transport.
///
/// Scene-update intervals are callback timestamps, not presented frames. Mesh and
/// collision timings are ContinuousClock wall time on the simulator host.
@MainActor
final class DigMetrics {
    struct MeshSample { let window: String?; let chunks: Int; let vertices: Int; let triangles: Int; let extractMs: Double; let mainMs: Double }
    struct CollisionSample { let window: String?; let chunk: Int; let triangles: Int; let ms: Double }
    struct CollisionJob { let window: String?; let chunks: Int; let wallMs: Double }
    struct Reload { let kind: String; let ms: Double; let meshMs: Double }
    struct Footprint { let label: String; let bytes: UInt64; let peak: Int64 }

    private(set) var windowName: String?
    private(set) var intervals: [String: [Double]] = [:]
    private var previous: TimeInterval?
    private(set) var mesh: [MeshSample] = []
    private(set) var collision: [CollisionSample] = []
    private(set) var collisionJobs: [CollisionJob] = []
    private(set) var reloads: [Reload] = []
    private(set) var footprints: [Footprint] = []
    private(set) var failures: [String] = []

    func recordFrame(_ timestamp: TimeInterval) {
        guard timestamp.isFinite else { return }
        defer { previous = timestamp }
        guard let previous, timestamp > previous, let windowName else { return }
        intervals[windowName, default: []].append(timestamp - previous)
    }

    /// Suspension and scene reloads are not frame intervals.
    func breakSequence() { previous = nil }
    func begin(_ name: String) { windowName = name }
    func end() { windowName = nil }

    /// Clears the samples of a previous run; reloads and footprints stay.
    func resetSamples() {
        intervals.removeAll()
        mesh.removeAll()
        collision.removeAll()
        collisionJobs.removeAll()
        failures.removeAll()
        windowName = nil
        previous = nil
    }

    func recordMesh(_ sample: MeshSample) { mesh.append(sample) }
    func recordCollision(_ sample: CollisionSample) { collision.append(sample) }
    func recordCollisionJob(_ job: CollisionJob) { collisionJobs.append(job) }
    func recordReload(_ reload: Reload) { reloads.append(reload) }
    func recordFailure(_ text: String) { failures.append(String(text.prefix(200))) }

    @discardableResult
    func snapshotFootprint(_ label: String) -> Footprint {
        let value = Self.footprint()
        let sample = Footprint(label: label, bytes: value.current, peak: value.peak)
        footprints.append(sample)
        return sample
    }

    static func footprint() -> (current: UInt64, peak: Int64) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return (0, 0) }
        return (info.phys_footprint, info.ledger_phys_footprint_peak)
    }

    /// Nearest-rank percentiles, as in platform-baseline.
    nonisolated static func stats(_ values: [Double]) -> [String: Any] {
        let sorted = values.sorted()
        func percentile(_ fraction: Double) -> Double {
            guard !sorted.isEmpty else { return 0 }
            return sorted[max(0, Int((fraction * Double(sorted.count)).rounded(.up)) - 1)]
        }
        return ["count": sorted.count, "p50": round3(percentile(0.5)), "p95": round3(percentile(0.95)),
                "p99": round3(percentile(0.99)), "max": round3(sorted.last ?? 0)]
    }

    nonisolated static func round3(_ value: Double) -> Double { (value * 1_000).rounded() / 1_000 }
    nonisolated static func mib(_ bytes: Int64) -> Double { round3(Double(bytes) / 1_048_576) }

    func intervalReport() -> [String: Any] {
        intervals.mapValues { values -> [String: Any] in
            let ms = values.map { $0 * 1_000 }
            var result = Self.stats(ms)
            let over = values.filter { $0 > 0.0333 }.count
            result["over33"] = over
            result["over33Share"] = values.isEmpty ? 0 : Self.round3(Double(over) / Double(values.count) * 100)
            result["seconds"] = Self.round3(values.reduce(0, +))
            return result
        }
    }

    func meshReport(window: String?) -> [String: Any] {
        let samples = mesh.filter { window == nil || $0.window == window }
        return ["jobs": samples.count,
                "totalMs": Self.stats(samples.map { $0.extractMs + $0.mainMs }),
                "extractMs": Self.stats(samples.map(\.extractMs)),
                "mainActorMs": Self.stats(samples.map(\.mainMs)),
                "chunksMax": samples.map(\.chunks).max() ?? 0,
                "verticesMax": samples.map(\.vertices).max() ?? 0,
                "trianglesMax": samples.map(\.triangles).max() ?? 0]
    }

    func collisionReport(window: String?) -> [String: Any] {
        let chunks = collision.filter { window == nil || $0.window == window }
        let jobs = collisionJobs.filter { window == nil || $0.window == window }
        return ["chunkJobs": chunks.count, "chunkMs": Self.stats(chunks.map(\.ms)),
                "trianglesMax": chunks.map(\.triangles).max() ?? 0,
                "jobs": jobs.count, "jobWallMs": Self.stats(jobs.map(\.wallMs)),
                "jobChunksMax": jobs.map(\.chunks).max() ?? 0]
    }

    func footprintReport() -> [[String: Any]] {
        footprints.map { ["label": $0.label, "MiB": Self.mib(Int64($0.bytes)), "peakMiB": Self.mib($0.peak)] }
    }

    func reloadReport() -> [[String: Any]] {
        reloads.map { ["kind": $0.kind, "ms": Self.round3($0.ms), "meshMs": Self.round3($0.meshMs)] }
    }
}

extension Duration {
    var milliseconds: Double {
        Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1e15
    }
}
