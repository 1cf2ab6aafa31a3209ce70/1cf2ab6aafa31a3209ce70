/// CPU triangle geometry for one chunk, in arena scene units. Triangles wind
/// counter-clockwise seen from outside: `cross(p1 - p0, p2 - p0)` points along the
/// outward normal, matching the Spike 00 heightfield convention.
public struct SurfaceMesh: Sendable, Equatable {
    public let chunk: Int
    public var positions: [SIMD3<Float>]
    /// Unit length and finite; one per position.
    public var normals: [SIMD3<Float>]
    /// Three per triangle, indexing `positions`.
    public var indices: [UInt32]

    public init(chunk: Int, positions: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = [], indices: [UInt32] = []) {
        self.chunk = chunk; self.positions = positions; self.normals = normals; self.indices = indices
    }

    public var vertexCount: Int { positions.count }
    public var triangleCount: Int { indices.count / 3 }

    /// 16-bit indices (for example for a static collision shape), or nil when the chunk
    /// has more than 65,536 vertices.
    public var indices16: [UInt16]? {
        guard positions.count <= Int(UInt16.max) + 1 else { return nil }
        return indices.map { UInt16(truncatingIfNeeded: $0) }
    }
}

/// One tile of the 2D side-view mask, drawable by SpriteKit without this package
/// knowing about SpriteKit.
public struct MaskTile: Sendable, Equatable {
    public let chunk: Int
    /// First cell column and row covered by this tile. Row 0 is the bottom row of the mask.
    public let originColumn: Int
    public let originRow: Int
    public let width: Int
    public let height: Int
    /// `width * height` bytes, 255 solid and 0 excavated, row-major from the tile's
    /// bottom row. Usable as an alpha mask; check orientation against the texture API used.
    public var coverage: [UInt8]
    /// Marching-squares case (0...15) per square whose lower-left sample is a tile cell,
    /// row-major from the bottom. Bits: 1 lower-left, 2 lower-right, 4 upper-right,
    /// 8 upper-left; a set bit is solid. Samples outside the mask are open above and to
    /// the sides and solid below.
    public var contourCases: [UInt8]

    public init(chunk: Int, originColumn: Int, originRow: Int, width: Int, height: Int,
                coverage: [UInt8], contourCases: [UInt8]) {
        self.chunk = chunk; self.originColumn = originColumn; self.originRow = originRow
        self.width = width; self.height = height; self.coverage = coverage; self.contourCases = contourCases
    }

    /// Contour line segments implied by the cases (ambiguous cases 5 and 10 give two).
    public var contourSegmentCount: Int {
        contourCases.reduce(0) { total, value in
            switch value {
            case 0, 15: return total
            case 5, 10: return total + 2
            default: return total + 1
            }
        }
    }

    public var solidCellCount: Int { coverage.reduce(0) { $0 + ($1 == 0 ? 0 : 1) } }
}
