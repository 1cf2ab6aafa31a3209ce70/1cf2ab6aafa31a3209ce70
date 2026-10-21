/// Field coordinates are arena scene units: x and z span `-arenaSize/2 ... arenaSize/2`,
/// y points up, and undisturbed ground is at y = 0. The 2D side view uses x and y and
/// ignores z.
///
/// A field is the rule-owned truth for excavation. Rendered meshes and collision shapes
/// are views of one field revision; they never feed back into rules.
public protocol ExcavationField: Sendable {
    /// CPU output for one geometry chunk (`SurfaceMesh` or `MaskTile`).
    associatedtype Geometry: Sendable

    init(workload: DigWorkload)

    /// Geometry chunks are numbered `0..<chunkCount`. A dirty region names chunks.
    var chunkCount: Int { get }

    /// Smallest represented feature in scene units; ray queries step at half this size.
    var cellSize: Float { get }

    /// Height of the rule-field surface under a plane point, clamped to the arena.
    func surfaceHeight(x: Float, z: Float) -> Float

    /// True when the point is excavated, above ground, or outside the arena horizontally.
    func isOpen(_ point: SIMD3<Float>) -> Bool

    /// Removes material inside the sphere, never below the workload's maximum depth.
    /// Returns every chunk whose geometry changed, including neighbours whose shared
    /// normals, faces or contour cases depend on a changed sample. Empty means no change.
    mutating func carve(center: SIMD3<Float>, radius: Float) -> DirtyRegion

    /// Builds one chunk from this field value. Pure; safe to call on a snapshot off the
    /// main actor.
    func geometry(chunk: Int) -> Geometry

    /// Feeds the field contents, in a fixed order, into a digest.
    func combine(into hasher: inout DigestHasher)
}

extension ExcavationField {
    /// Geometry for the region's chunks in ascending chunk order.
    public func geometry(for region: DirtyRegion) -> [Geometry] {
        region.sortedChunks.map(geometry(chunk:))
    }

    /// Every chunk, for the initial build or after a restart.
    public var allChunks: DirtyRegion { DirtyRegion(chunks: Set(0..<chunkCount)) }

    /// Rule-field hit test. Marches from `origin` (which must be open) in half-cell steps
    /// and refines the first solid sample by bisection. Features thinner than half a cell
    /// can be missed. Renderers convert a touch ray to this query instead of trusting a
    /// collision mesh that may describe an older revision.
    public func raycast(origin: SIMD3<Float>, direction: SIMD3<Float>, maxDistance: Float) -> SIMD3<Float>? {
        let length = (direction * direction).sum().squareRoot()
        guard length > 0, length.isFinite, maxDistance > 0, maxDistance.isFinite,
              origin.x.isFinite, origin.y.isFinite, origin.z.isFinite, isOpen(origin) else { return nil }
        let unit = direction / length
        let step = cellSize * 0.5
        var travelled: Float = 0
        while travelled < maxDistance {
            let next = min(travelled + step, maxDistance)
            if !isOpen(origin + unit * next) {
                var open = travelled
                var solid = next
                for _ in 0..<12 {
                    let middle = (open + solid) * 0.5
                    if isOpen(origin + unit * middle) { open = middle } else { solid = middle }
                }
                return origin + unit * solid
            }
            travelled = next
        }
        return nil
    }
}

/// A set of geometry chunk indices.
public struct DirtyRegion: Sendable, Equatable {
    public private(set) var chunks: Set<Int>
    public init(chunks: Set<Int> = []) { self.chunks = chunks }
    public var isEmpty: Bool { chunks.isEmpty }
    /// Deterministic iteration order for building and installing chunks.
    public var sortedChunks: [Int] { chunks.sorted() }
    public mutating func formUnion(_ other: DirtyRegion) { chunks.formUnion(other.chunks) }
    mutating func insert(_ chunk: Int) { chunks.insert(chunk) }
}

/// 64-bit FNV-1a over explicitly ordered little-endian bytes. Independent of Swift's
/// per-process randomized `Hasher`, so equal state gives an equal digest across runs.
public struct DigestHasher: Sendable {
    public private(set) var value: UInt64 = 0xcbf2_9ce4_8422_2325
    public init() {}

    public mutating func combine(_ byte: UInt8) {
        value ^= UInt64(byte)
        value = value &* 0x0000_0100_0000_01b3
    }

    public mutating func combine(_ word: UInt64) {
        for shift in stride(from: 0, to: 64, by: 8) { combine(UInt8(truncatingIfNeeded: word >> UInt64(shift))) }
    }

    public mutating func combine(_ number: Int) { combine(UInt64(bitPattern: Int64(number))) }
    public mutating func combine(_ number: Float) { combine(UInt64(number.bitPattern)) }
    public mutating func combine(bytes: [UInt8]) { for byte in bytes { combine(byte) } }
}
