/// 2D side-view excavation mask: square cells across arena x (horizontal) and y (down
/// from the surface). Commands' z is ignored. The renderer draws `MaskTile`s, for example
/// as an alpha texture or as marching-squares tile variants.
public struct SideViewMask: ExcavationField {
    public typealias Geometry = MaskTile

    public let columns: Int
    public let rows: Int
    public let tileSize: Int
    public let cellSize: Float
    let originX: Float
    /// y of the mask's bottom edge; the top edge is y = 0.
    let originY: Float
    let floorY: Float
    let tilesX: Int
    let tilesY: Int
    /// 1 solid, 0 open; row-major, row 0 at the bottom.
    public private(set) var cells: [UInt8]

    public init(workload: DigWorkload) {
        precondition(workload.maskColumns > 0 && workload.maskRows > 0 && workload.maskTileSize > 0 && workload.arenaSize > 0)
        columns = workload.maskColumns; rows = workload.maskRows; tileSize = workload.maskTileSize
        cellSize = workload.arenaSize / Float(columns)
        originX = -workload.arenaSize / 2
        originY = -Float(rows) * cellSize
        floorY = -workload.maxDepth
        tilesX = (columns + tileSize - 1) / tileSize
        tilesY = (rows + tileSize - 1) / tileSize
        cells = Array(repeating: 1, count: columns * rows)
    }

    public var chunkCount: Int { tilesX * tilesY }

    /// Occupancy with boundary rules: open above and to the sides, solid below.
    public func isSolid(column: Int, row: Int) -> Bool {
        if row < 0 { return true }
        guard row < rows, column >= 0, column < columns else { return false }
        return cells[row * columns + column] != 0
    }

    public func surfaceHeight(x: Float, z: Float) -> Float {
        let column = min(max(Int(((x - originX) / cellSize).rounded(.down)), 0), columns - 1)
        var row = rows - 1
        while row >= 0, !isSolid(column: column, row: row) { row -= 1 }
        return originY + Float(row + 1) * cellSize
    }

    public func isOpen(_ point: SIMD3<Float>) -> Bool {
        let column = Int(((point.x - originX) / cellSize).rounded(.down))
        guard column >= 0, column < columns else { return true }
        return !isSolid(column: column, row: Int(((point.y - originY) / cellSize).rounded(.down)))
    }

    /// Carves a circle in the x/y plane; `center.z` is ignored.
    public mutating func carve(center: SIMD3<Float>, radius: Float) -> DirtyRegion {
        guard radius > 0, radius.isFinite, center.x.isFinite, center.y.isFinite else { return DirtyRegion() }
        let minColumn = max(0, Int(((center.x - radius - originX) / cellSize).rounded(.down)))
        let maxColumn = min(columns - 1, Int(((center.x + radius - originX) / cellSize).rounded(.down)))
        let minRow = max(0, Int(((center.y - radius - originY) / cellSize).rounded(.down)))
        let maxRow = min(rows - 1, Int(((center.y + radius - originY) / cellSize).rounded(.down)))
        var region = DirtyRegion()
        guard minColumn <= maxColumn, minRow <= maxRow else { return region }
        let radiusSquared = radius * radius
        for row in minRow...maxRow {
            let centreY = originY + (Float(row) + 0.5) * cellSize
            guard centreY >= floorY else { continue }
            for column in minColumn...maxColumn where cells[row * columns + column] != 0 {
                let dx = originX + (Float(column) + 0.5) * cellSize - center.x
                let dy = centreY - center.y
                guard dx * dx + dy * dy < radiusSquared else { continue }
                cells[row * columns + column] = 0
                // The cell's own tile, plus tiles whose marching squares sample it
                // (squares whose lower-left sample is one column left and/or one row down).
                for sampleRow in max(0, row - 1)...row {
                    for sampleColumn in max(0, column - 1)...column {
                        region.insert((sampleRow / tileSize) * tilesX + sampleColumn / tileSize)
                    }
                }
            }
        }
        return region
    }

    public func geometry(chunk: Int) -> MaskTile {
        precondition(chunk >= 0 && chunk < chunkCount)
        let originColumn = (chunk % tilesX) * tileSize
        let originRow = (chunk / tilesX) * tileSize
        let width = min(tileSize, columns - originColumn)
        let height = min(tileSize, rows - originRow)
        var coverage: [UInt8] = []
        var cases: [UInt8] = []
        coverage.reserveCapacity(width * height)
        cases.reserveCapacity(width * height)
        for row in originRow..<(originRow + height) {
            for column in originColumn..<(originColumn + width) {
                coverage.append(cells[row * columns + column] != 0 ? 255 : 0)
                var value: UInt8 = 0
                if isSolid(column: column, row: row) { value |= 1 }
                if isSolid(column: column + 1, row: row) { value |= 2 }
                if isSolid(column: column + 1, row: row + 1) { value |= 4 }
                if isSolid(column: column, row: row + 1) { value |= 8 }
                cases.append(value)
            }
        }
        return MaskTile(chunk: chunk, originColumn: originColumn, originRow: originRow, width: width, height: height,
                        coverage: coverage, contourCases: cases)
    }

    public func combine(into hasher: inout DigestHasher) {
        hasher.combine(columns); hasher.combine(rows)
        hasher.combine(bytes: cells)
    }
}
