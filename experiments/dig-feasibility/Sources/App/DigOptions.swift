import Foundation

enum DigCandidate: String, CaseIterable, Sendable {
    /// A: 49 x 49 heightfield in 16 RealityKit chunks with per-chunk static collision.
    case heightfield
    /// A2: candidate A with each fixed-topology chunk in a CPU-written `LowLevelMesh`
    /// (iOS 18), tried because the MeshDescriptor path missed the 4 ms mesh budget.
    case lowlevel
    /// B: 48 x 16 x 48 voxels in 9 RealityKit chunks with per-chunk static collision.
    case voxel
    /// C: the heightfield rules drawn top-down as a 48 x 48 SpriteKit tile map; no collision.
    case sprite
}

/// Developer options. Only Debug builds read launch arguments; the trace, delays and
/// labels are developer fixtures and never reach saves.
struct DigOptions: Equatable, Sendable {
    var candidate: DigCandidate = .heightfield
    var runLabel = "manual"
    var meshDelay: Duration = .zero
    var collisionDelay: Duration = .zero
    var preferredFramesPerSecond: Int?

    static var launch: DigOptions {
        #if DEBUG
        return parse(ProcessInfo.processInfo.arguments)
        #else
        return DigOptions()
        #endif
    }

    static func parse(_ arguments: [String]) -> DigOptions {
        var options = DigOptions()
        func value(_ name: String) -> String? {
            guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        if let raw = value("--dig-candidate"), let candidate = DigCandidate(rawValue: raw) { options.candidate = candidate }
        if let label = value("--dig-run-label"), !label.isEmpty,
           label.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) {
            options.runLabel = String(label.prefix(80))
        }
        if let raw = value("--dig-mesh-delay-ms"), let ms = Int(raw), (0...2_000).contains(ms) { options.meshDelay = .milliseconds(ms) }
        if let raw = value("--dig-collision-delay-ms"), let ms = Int(raw), (0...2_000).contains(ms) { options.collisionDelay = .milliseconds(ms) }
        if let raw = value("--dig-fps"), let fps = Int(raw), [30, 60, 120].contains(fps) { options.preferredFramesPerSecond = fps }
        return options
    }
}
