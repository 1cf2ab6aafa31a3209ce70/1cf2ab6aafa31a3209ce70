/// Voxel occupancy volume stored in cubic chunks, with per-chunk dirty tracking and
/// face-culled cube surface extraction. Supports cavities and overhangs; the surface is
/// blocky (no smoothing).
///
/// Each chunk owns its own array, so a renderer's snapshot of the field shares storage
/// and the next dig copies only the chunks it touches.
///
/// Extraction emits a quad for every face between a solid voxel and an open neighbour.
/// Above the volume and beyond its sides is open (the arena's outer walls are drawn);
/// below the volume is solid (no bottom faces). Voxels whose centre is below the
/// workload's maximum depth cannot be carved.
public struct VoxelField: ExcavationField {
    public typealias Geometry = SurfaceMesh

    public let countX: Int
    public let countY: Int
    public let countZ: Int
    public let chunkSize: Int
    public let cellSize: Float
    let chunksX: Int
    let chunksY: Int
    let chunksZ: Int
    /// World position of voxel (0, 0, 0)'s minimum corner; the volume's top is y = 0.
    let origin: SIMD3<Float>
    let floorY: Float
    var chunks: [VoxelChunk]

    struct VoxelChunk: Sendable, Equatable {
        /// 1 solid, 0 open; index `(y * size + z) * size + x` in chunk-local coordinates.
        var cells: [UInt8]
    }

    public init(workload: DigWorkload) {
        let size = workload.chunkSize
        precondition(size > 0 && workload.voxelX == workload.voxelZ && workload.arenaSize > 0)
        precondition(workload.voxelX > 0 && workload.voxelY > 0)
        precondition(workload.voxelX % size == 0 && workload.voxelY % size == 0 && workload.voxelZ % size == 0)
        countX = workload.voxelX; countY = workload.voxelY; countZ = workload.voxelZ
        chunkSize = size
        cellSize = workload.arenaSize / Float(countX)
        chunksX = countX / size; chunksY = countY / size; chunksZ = countZ / size
        origin = SIMD3(-workload.arenaSize / 2, -Float(countY) * cellSize, -workload.arenaSize / 2)
        floorY = -workload.maxDepth
        chunks = Array(repeating: VoxelChunk(cells: Array(repeating: 1, count: size * size * size)),
                       count: chunksX * chunksY * chunksZ)
    }

    public var chunkCount: Int { chunks.count }

    /// Occupancy with the extraction boundary rules (open above and beside, solid below).
    public func isSolid(x: Int, y: Int, z: Int) -> Bool {
        if y < 0 { return true }
        if y >= countY || x < 0 || x >= countX || z < 0 || z >= countZ { return false }
        let size = chunkSize
        let chunk = chunkIndex(x / size, y / size, z / size)
        return chunks[chunk].cells[((y % size) * size + z % size) * size + x % size] != 0
    }

    public func surfaceHeight(x: Float, z: Float) -> Float {
        let column = min(max(Int(((x - origin.x) / cellSize).rounded(.down)), 0), countX - 1)
        let row = min(max(Int(((z - origin.z) / cellSize).rounded(.down)), 0), countZ - 1)
        var layer = countY - 1
        while layer >= 0, !isSolid(x: column, y: layer, z: row) { layer -= 1 }
        return origin.y + Float(layer + 1) * cellSize
    }

    public func isOpen(_ point: SIMD3<Float>) -> Bool {
        let local = (point - origin) / cellSize
        let x = Int(local.x.rounded(.down)), z = Int(local.z.rounded(.down))
        guard x >= 0, x < countX, z >= 0, z < countZ else { return true }
        let y = Int(local.y.rounded(.down))
        return !isSolid(x: x, y: y, z: z)
    }

    public mutating func carve(center: SIMD3<Float>, radius: Float) -> DirtyRegion {
        guard radius > 0, radius.isFinite, center.x.isFinite, center.y.isFinite, center.z.isFinite else { return DirtyRegion() }
        let low = (center - radius - origin) / cellSize
        let high = (center + radius - origin) / cellSize
        let minX = max(0, Int(low.x.rounded(.down))), maxX = min(countX - 1, Int(high.x.rounded(.down)))
        let minY = max(0, Int(low.y.rounded(.down))), maxY = min(countY - 1, Int(high.y.rounded(.down)))
        let minZ = max(0, Int(low.z.rounded(.down))), maxZ = min(countZ - 1, Int(high.z.rounded(.down)))
        var region = DirtyRegion()
        guard minX <= maxX, minY <= maxY, minZ <= maxZ else { return region }
        let radiusSquared = radius * radius
        let size = chunkSize
        for y in minY...maxY {
            let centreY = origin.y + (Float(y) + 0.5) * cellSize
            guard centreY >= floorY else { continue }
            for z in minZ...maxZ {
                for x in minX...maxX {
                    let voxelCentre = origin + (SIMD3(Float(x), Float(y), Float(z)) + 0.5) * cellSize
                    let offset = voxelCentre - center
                    guard (offset * offset).sum() < radiusSquared else { continue }
                    let chunk = chunkIndex(x / size, y / size, z / size)
                    let cell = ((y % size) * size + z % size) * size + x % size
                    guard chunks[chunk].cells[cell] != 0 else { continue }
                    chunks[chunk].cells[cell] = 0
                    region.insert(chunk)
                    // A face on a chunk boundary belongs to the neighbouring chunk's voxel too.
                    if x % size == 0, x > 0 { region.insert(chunkIndex(x / size - 1, y / size, z / size)) }
                    if x % size == size - 1, x < countX - 1 { region.insert(chunkIndex(x / size + 1, y / size, z / size)) }
                    if y % size == 0, y > 0 { region.insert(chunkIndex(x / size, y / size - 1, z / size)) }
                    if y % size == size - 1, y < countY - 1 { region.insert(chunkIndex(x / size, y / size + 1, z / size)) }
                    if z % size == 0, z > 0 { region.insert(chunkIndex(x / size, y / size, z / size - 1)) }
                    if z % size == size - 1, z < countZ - 1 { region.insert(chunkIndex(x / size, y / size, z / size + 1)) }
                }
            }
        }
        return region
    }

    public func geometry(chunk: Int) -> SurfaceMesh {
        precondition(chunk >= 0 && chunk < chunks.count)
        let size = chunkSize
        let chunkX = chunk % chunksX
        let chunkZ = (chunk / chunksX) % chunksZ
        let chunkY = chunk / (chunksX * chunksZ)
        let cells = chunks[chunk].cells
        var mesh = SurfaceMesh(chunk: chunk)
        for localY in 0..<size {
            for localZ in 0..<size {
                for localX in 0..<size where cells[(localY * size + localZ) * size + localX] != 0 {
                    let x = chunkX * size + localX, y = chunkY * size + localY, z = chunkZ * size + localZ
                    for face in Self.faces where !isSolid(x: x + face.step.x, y: y + face.step.y, z: z + face.step.z) {
                        let base = UInt32(mesh.positions.count)
                        let corner = SIMD3(Float(x), Float(y), Float(z)) + face.base
                        mesh.positions.append(origin + corner * cellSize)
                        mesh.positions.append(origin + (corner + face.u) * cellSize)
                        mesh.positions.append(origin + (corner + face.u + face.v) * cellSize)
                        mesh.positions.append(origin + (corner + face.v) * cellSize)
                        mesh.normals.append(contentsOf: repeatElement(face.normal, count: 4))
                        mesh.indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
                    }
                }
            }
        }
        return mesh
    }

    public func combine(into hasher: inout DigestHasher) {
        hasher.combine(countX); hasher.combine(countY); hasher.combine(countZ)
        for chunk in chunks { hasher.combine(bytes: chunk.cells) }
    }

    func chunkIndex(_ x: Int, _ y: Int, _ z: Int) -> Int { (y * chunksZ + z) * chunksX + x }

    /// Quad corners are `base`, `base + u`, `base + u + v`, `base + v` with
    /// `cross(u, v) == normal`, so both triangles wind counter-clockwise from outside.
    struct Face {
        let step: SIMD3<Int>
        let normal: SIMD3<Float>
        let base: SIMD3<Float>
        let u: SIMD3<Float>
        let v: SIMD3<Float>
    }

    static let faces: [Face] = [
        Face(step: SIMD3(1, 0, 0), normal: SIMD3(1, 0, 0), base: SIMD3(1, 0, 0), u: SIMD3(0, 1, 0), v: SIMD3(0, 0, 1)),
        Face(step: SIMD3(-1, 0, 0), normal: SIMD3(-1, 0, 0), base: SIMD3(0, 0, 0), u: SIMD3(0, 0, 1), v: SIMD3(0, 1, 0)),
        Face(step: SIMD3(0, 1, 0), normal: SIMD3(0, 1, 0), base: SIMD3(0, 1, 0), u: SIMD3(0, 0, 1), v: SIMD3(1, 0, 0)),
        Face(step: SIMD3(0, -1, 0), normal: SIMD3(0, -1, 0), base: SIMD3(0, 0, 0), u: SIMD3(1, 0, 0), v: SIMD3(0, 0, 1)),
        Face(step: SIMD3(0, 0, 1), normal: SIMD3(0, 0, 1), base: SIMD3(0, 0, 1), u: SIMD3(1, 0, 0), v: SIMD3(0, 1, 0)),
        Face(step: SIMD3(0, 0, -1), normal: SIMD3(0, 0, -1), base: SIMD3(0, 0, 0), u: SIMD3(0, 1, 0), v: SIMD3(1, 0, 0)),
    ]
}
