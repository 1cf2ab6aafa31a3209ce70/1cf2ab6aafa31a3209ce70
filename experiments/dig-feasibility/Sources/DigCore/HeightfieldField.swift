/// 2.5D heightfield: one height per grid vertex, fixed topology, no overhangs or cavities.
/// The Spike 00 `TerrainHeightfield`, enlarged and split into geometry tiles.
/// Tiles share border vertices; normals use global finite differences, so tiles are seamless.
public struct HeightfieldField: ExcavationField {
    public typealias Geometry = SurfaceMesh

    /// Vertices per side.
    public let resolution: Int
    public let tileQuads: Int
    public let arenaSize: Float
    public let maxDepth: Float
    /// Row-major heights; row is the z index, column the x index.
    public private(set) var heights: [Float]
    let tilesPerSide: Int
    let spacing: Float

    public init(workload: DigWorkload) {
        precondition(workload.heightfieldResolution >= 2 && workload.heightfieldTileQuads >= 1 && workload.arenaSize > 0)
        resolution = workload.heightfieldResolution
        tileQuads = workload.heightfieldTileQuads
        arenaSize = workload.arenaSize
        maxDepth = workload.maxDepth
        heights = Array(repeating: 0, count: resolution * resolution)
        tilesPerSide = (resolution - 1 + tileQuads - 1) / tileQuads
        spacing = arenaSize / Float(resolution - 1)
    }

    public var chunkCount: Int { tilesPerSide * tilesPerSide }
    public var cellSize: Float { spacing }

    public func surfaceHeight(x: Float, z: Float) -> Float {
        let half = arenaSize / 2
        let gx = min(max((x + half) / spacing, 0), Float(resolution - 1))
        let gz = min(max((z + half) / spacing, 0), Float(resolution - 1))
        let column = min(Int(gx), resolution - 2)
        let row = min(Int(gz), resolution - 2)
        let fx = gx - Float(column)
        let fz = gz - Float(row)
        let base = row * resolution + column
        let near = heights[base] + (heights[base + 1] - heights[base]) * fx
        let far = heights[base + resolution] + (heights[base + resolution + 1] - heights[base + resolution]) * fx
        return near + (far - near) * fz
    }

    public func isOpen(_ point: SIMD3<Float>) -> Bool {
        let half = arenaSize / 2
        guard abs(point.x) <= half, abs(point.z) <= half else { return true }
        return point.y >= surfaceHeight(x: point.x, z: point.z)
    }

    public mutating func carve(center: SIMD3<Float>, radius: Float) -> DirtyRegion {
        guard radius > 0, radius.isFinite, center.x.isFinite, center.y.isFinite, center.z.isFinite else { return DirtyRegion() }
        let half = arenaSize / 2
        let lowColumn = max(0, Int(((center.x - radius + half) / spacing).rounded(.up)))
        let highColumn = min(resolution - 1, Int(((center.x + radius + half) / spacing).rounded(.down)))
        let lowRow = max(0, Int(((center.z - radius + half) / spacing).rounded(.up)))
        let highRow = min(resolution - 1, Int(((center.z + radius + half) / spacing).rounded(.down)))
        guard lowColumn <= highColumn, lowRow <= highRow else { return DirtyRegion() }
        let radiusSquared = radius * radius
        var changed: (minRow: Int, maxRow: Int, minColumn: Int, maxColumn: Int)?
        for row in lowRow...highRow {
            for column in lowColumn...highColumn {
                let dx = Float(column) * spacing - half - center.x
                let dz = Float(row) * spacing - half - center.z
                let distanceSquared = dx * dx + dz * dz
                guard distanceSquared < radiusSquared else { continue }
                let index = row * resolution + column
                let bottom = center.y - (radiusSquared - distanceSquared).squareRoot()
                let lowered = max(-maxDepth, min(heights[index], bottom))
                guard lowered < heights[index] else { continue }
                heights[index] = lowered
                if let bounds = changed {
                    changed = (min(bounds.minRow, row), max(bounds.maxRow, row),
                               min(bounds.minColumn, column), max(bounds.maxColumn, column))
                } else {
                    changed = (row, row, column, column)
                }
            }
        }
        guard let bounds = changed else { return DirtyRegion() }
        // Neighbouring vertices' normals read changed heights, so widen by one vertex.
        let rows = tileRange(forVertices: max(0, bounds.minRow - 1)...min(resolution - 1, bounds.maxRow + 1))
        let columns = tileRange(forVertices: max(0, bounds.minColumn - 1)...min(resolution - 1, bounds.maxColumn + 1))
        var region = DirtyRegion()
        for tileRow in rows { for tileColumn in columns { region.insert(tileRow * tilesPerSide + tileColumn) } }
        return region
    }

    public func geometry(chunk: Int) -> SurfaceMesh {
        precondition(chunk >= 0 && chunk < chunkCount)
        let tileRow = chunk / tilesPerSide
        let tileColumn = chunk % tilesPerSide
        let rows = vertexRange(tile: tileRow)
        let columns = vertexRange(tile: tileColumn)
        let width = columns.count
        var mesh = SurfaceMesh(chunk: chunk)
        mesh.positions.reserveCapacity(rows.count * width)
        mesh.normals.reserveCapacity(rows.count * width)
        let half = arenaSize / 2
        for row in rows {
            for column in columns {
                mesh.positions.append(SIMD3(Float(column) * spacing - half, heights[row * resolution + column],
                                            Float(row) * spacing - half))
                mesh.normals.append(normal(row: row, column: column))
            }
        }
        mesh.indices.reserveCapacity((rows.count - 1) * (width - 1) * 6)
        for localRow in 0..<(rows.count - 1) {
            for localColumn in 0..<(width - 1) {
                let a = UInt32(localRow * width + localColumn)
                let b = a + 1
                let c = a + UInt32(width)
                mesh.indices.append(contentsOf: [a, c, b, b, c, c + 1])
            }
        }
        return mesh
    }

    public func combine(into hasher: inout DigestHasher) {
        hasher.combine(resolution)
        for height in heights { hasher.combine(height) }
    }

    func normal(row: Int, column: Int) -> SIMD3<Float> {
        let left = max(0, column - 1), right = min(resolution - 1, column + 1)
        let back = max(0, row - 1), front = min(resolution - 1, row + 1)
        let dx = (heights[row * resolution + right] - heights[row * resolution + left]) / (Float(right - left) * spacing)
        let dz = (heights[front * resolution + column] - heights[back * resolution + column]) / (Float(front - back) * spacing)
        let vector = SIMD3<Float>(-dx, 1, -dz)
        return vector / (vector * vector).sum().squareRoot()
    }

    /// Vertex indices covered by a tile; neighbouring tiles share their border vertex.
    func vertexRange(tile: Int) -> ClosedRange<Int> {
        let start = tile * tileQuads
        return start...min(start + tileQuads, resolution - 1)
    }

    /// Tiles whose vertex ranges include any vertex in `vertices`.
    func tileRange(forVertices vertices: ClosedRange<Int>) -> ClosedRange<Int> {
        let low = max(0, (vertices.lowerBound + tileQuads - 1) / tileQuads - 1)
        let high = min(tilesPerSide - 1, vertices.upperBound / tileQuads)
        return low...high
    }
}
