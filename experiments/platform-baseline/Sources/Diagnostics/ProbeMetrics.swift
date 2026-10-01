import Foundation
import Combine
import Darwin

/// Local diagnostics for this disposable experiment. No persistence or network transport.
@MainActor
final class ProbeMetrics: ObservableObject {
    @Published var summary = "Local probe: waiting for frames"
    private var frames = FrameStatistics()
    private var lastRefresh: TimeInterval?
    @Published var lastAction = "none"
    @Published var terrainSummary = "not measured"
    @Published var layoutSummary = "Board viewport not measured"

    func recordFrame(_ time: TimeInterval) {
        frames.record(time)
        guard frames.intervals.count >= 60 else { return }
        guard lastRefresh == nil || time - (lastRefresh ?? time) >= 1 else { return }
        lastRefresh = time
        refresh()
    }

    func reset() {
        frames.reset()
        lastRefresh = nil
        lastAction = "none"
        terrainSummary = "not measured"
        refresh()
    }

    func pause() {
        frames.breakSequence()
        lastRefresh = nil
    }

    func recordAction(_ text: String) {
        lastAction = String(text.prefix(160))
        refresh()
    }

    func recordLayout(_ size: CGSize) {
        layoutSummary = "Board viewport \(Int(size.width)) × \(Int(size.height))"
    }

    func recordTerrainMeasurement(_ text: String) {
        terrainSummary = String(text.prefix(240))
        refresh()
    }

    private func refresh() {
        let result = frames.snapshot
        let memory = Self.physicalFootprint().map { String(format: "%.1f MiB", Double($0) / 1_048_576) } ?? "unavailable"
        guard result.count >= 60 else {
            summary = "Local probe: warming up \(result.count)/60 intervals · footprint \(memory)"
            return
        }
        summary = String(format: "Window %d intervals · p50/p95/p99 %.1f/%.1f/%.1f ms · worst %.1f ms · >33.3 ms %d · footprint %@",
                         result.count, result.p50 * 1_000, result.p95 * 1_000, result.p99 * 1_000,
                         result.worst * 1_000, result.over33Milliseconds, memory)
    }

    private static func physicalFootprint() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return nil }
        return info.phys_footprint
    }
}
