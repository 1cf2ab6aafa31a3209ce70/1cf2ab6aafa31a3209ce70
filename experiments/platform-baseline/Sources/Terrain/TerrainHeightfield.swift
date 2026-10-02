import Foundation

/// Original disposable simulation; deliberately independent of RealityKit.
struct TerrainHeightfield {
    let side: Int
    let width: Float
    private(set) var heights: [Float]

    init(side: Int = 25, width: Float = 1.6) {
        precondition(side >= 2 && width > 0)
        self.side = side
        self.width = width
        heights = Array(repeating: 0, count: side * side)
    }

    mutating func dig(x: Float, z: Float, radius: Float = 0.24, depth: Float = 0.08) {
        guard radius > 0, depth > 0 else { return }
        for row in 0..<side {
            for column in 0..<side {
                let px = Float(column) / Float(side - 1) * width - width / 2
                let pz = Float(row) / Float(side - 1) * width - width / 2
                let distance = sqrt((px - x) * (px - x) + (pz - z) * (pz - z))
                if distance < radius {
                    let index = row * side + column
                    heights[index] = max(-0.45, heights[index] - depth * (1 - distance / radius))
                }
            }
        }
    }

    var positions: [SIMD3<Float>] {
        heights.indices.map { index in
            SIMD3(Float(index % side) / Float(side - 1) * width - width / 2,
                  heights[index], Float(index / side) / Float(side - 1) * width - width / 2)
        }
    }

    /// Geometry-derived normals keep this calculation testable without a renderer.
    var normals: [SIMD3<Float>] {
        let spacing = width / Float(side - 1)
        return heights.indices.map { index in
            let row = index / side
            let column = index % side
            let left = max(0, column - 1)
            let right = min(side - 1, column + 1)
            let back = max(0, row - 1)
            let front = min(side - 1, row + 1)
            let dx = (heights[row * side + right] - heights[row * side + left]) / (Float(right - left) * spacing)
            let dz = (heights[front * side + column] - heights[back * side + column]) / (Float(front - back) * spacing)
            let normal = SIMD3<Float>(-dx, 1, -dz)
            return normal / sqrt(normal.x * normal.x + normal.y * normal.y + normal.z * normal.z)
        }
    }

    var triangleIndices: [UInt32] {
        var result: [UInt32] = []
        for row in 0..<(side - 1) {
            for column in 0..<(side - 1) {
                let a = UInt32(row * side + column)
                let b = a + 1
                let c = a + UInt32(side)
                result.append(contentsOf: [a, c, b, b, c, c + 1])
            }
        }
        return result
    }
}
