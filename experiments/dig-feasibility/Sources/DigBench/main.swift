// Mac host micro-benchmark for Spike 11 CPU geometry. Not a simulator or device result.
// Run from experiments/dig-feasibility: swift run -c release DigBench [options]
import DigCore
import Foundation

struct Options {
    var workload = DigWorkload.default
    var iterations = 5
}

func parseOptions() -> Options {
    var options = Options()
    var arguments = CommandLine.arguments.dropFirst().makeIterator()
    func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n" + usage).utf8))
        exit(2)
    }
    func dims(_ text: String?, _ count: Int) -> [Int] {
        guard let parts = text?.split(separator: "x").compactMap({ Int($0) }), parts.count == count, parts.allSatisfy({ $0 > 0 })
        else { fail("expected \(count) positive integers separated by x") }
        return parts
    }
    while let flag = arguments.next() {
        switch flag {
        case "--iterations": options.iterations = max(2, Int(arguments.next() ?? "") ?? 0)
        case "--heightfield": options.workload.heightfieldResolution = dims(arguments.next(), 1)[0]
        case "--voxels":
            let value = dims(arguments.next(), 3)
            options.workload.voxelX = value[0]; options.workload.voxelY = value[1]; options.workload.voxelZ = value[2]
        case "--chunk": options.workload.chunkSize = dims(arguments.next(), 1)[0]
        case "--mask":
            let value = dims(arguments.next(), 2)
            options.workload.maskColumns = value[0]; options.workload.maskRows = value[1]
        case "--brush": options.workload.brushRadiusFraction = Float(arguments.next() ?? "") ?? options.workload.brushRadiusFraction
        case "--digs-per-second": options.workload.digsPerSecond = dims(arguments.next(), 1)[0]
        case "--duration": options.workload.durationSeconds = dims(arguments.next(), 1)[0]
        case "--collectibles": options.workload.collectibleCount = Int(arguments.next() ?? "") ?? options.workload.collectibleCount
        case "--seed": options.workload.seed = UInt64(arguments.next() ?? "") ?? options.workload.seed
        case "--help", "-h": print(usage); exit(0)
        default: fail("unknown option \(flag)")
        }
    }
    return options
}

let usage = """
usage: DigBench [--iterations N] [--heightfield N] [--voxels XxYxZ] [--chunk N] [--mask WxH]
                [--brush FRACTION] [--digs-per-second N] [--duration S] [--collectibles N] [--seed N]
"""

func sysctlString(_ name: String) -> String {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
    var buffer = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return "unknown" }
    return String(cString: buffer)
}

func milliseconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) * 1e3 + Double(duration.components.attoseconds) / 1e15
}

/// Nearest-rank percentile.
func percentile(_ sorted: [Double], _ p: Double) -> Double {
    guard !sorted.isEmpty else { return .nan }
    let rank = Int((p * Double(sorted.count)).rounded(.up))
    return sorted[min(sorted.count - 1, max(0, rank - 1))]
}

func summary(_ values: [Double]) -> String {
    let sorted = values.sorted()
    return String(format: "p50 %.4f  p95 %.4f  p99 %.4f  max %.4f", percentile(sorted, 0.5), percentile(sorted, 0.95),
                  percentile(sorted, 0.99), sorted.last ?? .nan)
}

func counts(_ values: [Int]) -> String {
    let sorted = values.sorted()
    guard !sorted.isEmpty else { return "n/a" }
    return "p50 \(sorted[(sorted.count - 1) / 2])  max \(sorted.last!)"
}

struct Sizes { var primary: Int; var secondary: Int }

func run<Field: ExcavationField>(_ type: Field.Type, label: String, units: (String, String), options: Options,
                                 sizes: (Field.Geometry) -> Sizes) {
    let clock = ContinuousClock()
    var rebuildMs: [Double] = []
    var stepMs: [Double] = []
    var fullMs: [Double] = []
    var primary: [Int] = []
    var secondary: [Int] = []
    var chunkCounts: [Int] = []
    var finalTotals = Sizes(primary: 0, secondary: 0)
    var collected = 0
    var revisions: UInt64 = 0
    var chunkTotal = 0
    for iteration in 0..<options.iterations {
        let measured = iteration > 0 // iteration 0 warms caches and code paths
        var rules = DigRules<Field>(workload: options.workload)
        chunkTotal = rules.field.chunkCount
        var initial: [Field.Geometry] = []
        let full = clock.measure { initial = rules.field.geometry(for: rules.field.allChunks) }
        if measured { fullMs.append(milliseconds(full)) }
        _ = initial
        rules.load(trace: options.workload.makeTrace())
        // Hold the last snapshot across the next step, as a renderer building off the main
        // actor would, so the step timing includes copy-on-write of touched storage.
        var snapshot = rules.field
        while !rules.isFinished {
            var report = DigFrameReport()
            let step = clock.measure { report = rules.step() }
            guard !report.dirty.isEmpty else { continue }
            snapshot = rules.field
            var output: [Field.Geometry] = []
            let build = clock.measure { output = snapshot.geometry(for: report.dirty) }
            guard measured else { continue }
            stepMs.append(milliseconds(step))
            rebuildMs.append(milliseconds(build))
            let total = output.map(sizes).reduce(Sizes(primary: 0, secondary: 0)) {
                Sizes(primary: $0.primary + $1.primary, secondary: $0.secondary + $1.secondary)
            }
            primary.append(total.primary)
            secondary.append(total.secondary)
            chunkCounts.append(report.dirty.chunks.count)
        }
        finalTotals = rules.field.geometry(for: rules.field.allChunks).map(sizes)
            .reduce(Sizes(primary: 0, secondary: 0)) { Sizes(primary: $0.primary + $1.primary, secondary: $0.secondary + $1.secondary) }
        collected = rules.score
        revisions = rules.revision
    }
    print("\n## \(label)")
    print("chunks: \(chunkTotal); field revisions per run: \(revisions); collectibles collected: \(collected)/\(options.workload.collectibleCount)")
    print("samples: \(rebuildMs.count) rebuilds (\(options.iterations - 1) measured runs; warm-up run excluded)")
    print("dirty-region geometry CPU ms : \(summary(rebuildMs))")
    print("rule step with dig CPU ms    : \(summary(stepMs))")
    print("full rebuild CPU ms (initial): \(summary(fullMs))")
    print("dirty chunks per rebuild     : \(counts(chunkCounts))")
    print("\(units.0) per rebuild\(String(repeating: " ", count: max(0, 17 - units.0.count))): \(counts(primary))")
    print("\(units.1) per rebuild\(String(repeating: " ", count: max(0, 17 - units.1.count))): \(counts(secondary))")
    print("final full field             : \(finalTotals.primary) \(units.0), \(finalTotals.secondary) \(units.1)")
}

let options = parseOptions()
let workload = options.workload
#if DEBUG
let configuration = "debug (numbers not representative; use -c release)"
#else
let configuration = "release"
#endif
print("# DigBench — Mac host CPU measurement")
print("NOT a simulator or device result. Single thread, ContinuousClock around each call, no renderer, no GPU.")
print("host: \(sysctlString("hw.model")), \(sysctlString("machdep.cpu.brand_string")), \(ProcessInfo.processInfo.activeProcessorCount) active cores")
print("os: \(ProcessInfo.processInfo.operatingSystemVersionString); build: \(configuration)")
print("""
workload: arena \(workload.arenaSize) units; heightfield \(workload.heightfieldResolution)x\(workload.heightfieldResolution) vertices \
(tiles of \(workload.heightfieldTileQuads) quads); voxels \(workload.voxelX)x\(workload.voxelY)x\(workload.voxelZ) in \
\(workload.chunkSize)^3 chunks; mask \(workload.maskColumns)x\(workload.maskRows) in \(workload.maskTileSize)^2 tiles; \
brush \(workload.brushRadiusFraction) of arena; dig depth \(workload.digDepthFraction); \(workload.digsPerSecond) digs/s \
for \(workload.durationSeconds) s at \(workload.tickRate) Hz; \(workload.collectibleCount) collectibles; seed \(workload.seed)
""")

run(HeightfieldField.self, label: "Heightfield (2.5D)", units: ("vertices", "triangles"), options: options) {
    Sizes(primary: $0.vertexCount, secondary: $0.triangleCount)
}
run(VoxelField.self, label: "Voxel chunks (face-culled cubes)", units: ("vertices", "triangles"), options: options) {
    Sizes(primary: $0.vertexCount, secondary: $0.triangleCount)
}
run(SideViewMask.self, label: "2D side-view mask (coverage + marching-squares cases)", units: ("solid cells", "contour segments"),
    options: options) {
    Sizes(primary: $0.solidCellCount, secondary: $0.contourSegmentCount)
}
