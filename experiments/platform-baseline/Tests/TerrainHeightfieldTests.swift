import XCTest
@testable import BaselineLogic

final class TerrainHeightfieldTests: XCTestCase {
    func testDigLocalizesAndClampsExcavation() {
        var field = TerrainHeightfield()
        field.dig(x: 0, z: 0)
        XCTAssertEqual(field.heights[312], -0.08, accuracy: 0.00001)
        XCTAssertEqual(field.heights[0], 0)
        for _ in 0..<20 { field.dig(x: 0, z: 0) }
        XCTAssertEqual(field.heights[312], -0.45, accuracy: 0.00001)
        XCTAssertTrue(field.heights.allSatisfy { $0 >= -0.45 && $0 <= 0 })
    }

    func testSurfaceNormalsRemainUpwardAndUnitLengthAfterDigging() {
        var field = TerrainHeightfield()
        XCTAssertEqual(field.normals.count, field.positions.count)
        XCTAssertTrue(field.normals.allSatisfy { $0 == SIMD3<Float>(0, 1, 0) })
        field.dig(x: 0.12, z: -0.08, radius: 0.35, depth: 0.2)
        let normals = field.normals
        XCTAssertEqual(normals.count, field.positions.count)
        XCTAssertTrue(normals.contains { abs($0.x) > 0.01 || abs($0.z) > 0.01 })
        for normal in normals {
            XCTAssertTrue(normal.x.isFinite && normal.y.isFinite && normal.z.isFinite)
            XCTAssertGreaterThan(normal.y, 0)
            let squaredLength = normal.x * normal.x + normal.y * normal.y + normal.z * normal.z
            XCTAssertEqual(squaredLength, 1, accuracy: 0.00001)
        }
    }

    func testTopologyAndUpwardWinding() {
        let field = TerrainHeightfield()
        XCTAssertEqual(field.positions.count, 625)
        XCTAssertEqual(field.triangleIndices.count, 3456)
        XCTAssertTrue(field.triangleIndices.allSatisfy { $0 < 625 })
        let indices = field.triangleIndices
        let positions = field.positions
        for start in stride(from: 0, to: indices.count, by: 3) {
            let a = positions[Int(indices[start])]
            let b = positions[Int(indices[start + 1])]
            let c = positions[Int(indices[start + 2])]
            let u = b - a
            let v = c - a
            XCTAssertGreaterThan(u.z * v.x - u.x * v.z, 0)
        }
    }
}
