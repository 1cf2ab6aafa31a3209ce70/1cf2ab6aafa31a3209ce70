import XCTest
@testable import DigCore

final class FieldTests: XCTestCase {
    let workload = DigWorkload.default

    // MARK: Heightfield

    func testHeightfieldDigIsLocalAndClampedToMaxDepth() {
        var field = HeightfieldField(workload: workload)
        let radius = workload.brushRadius
        let region = field.carve(center: SIMD3(0, radius - workload.digDepth, 0), radius: radius)
        XCTAssertFalse(region.isEmpty)
        // (0, 0) lies between vertices, so the interpolated depth is slightly shallower.
        XCTAssertEqual(field.surfaceHeight(x: 0, z: 0), -workload.digDepth, accuracy: 2e-3)
        for row in 0..<field.resolution {
            for column in 0..<field.resolution {
                let x = Float(column) * field.spacing - 0.5
                let z = Float(row) * field.spacing - 0.5
                if (x * x + z * z).squareRoot() >= radius {
                    XCTAssertEqual(field.heights[row * field.resolution + column], 0, "vertex outside brush changed")
                }
            }
        }
        for _ in 0..<60 {
            let surface = field.surfaceHeight(x: 0, z: 0)
            _ = field.carve(center: SIMD3(0, surface - workload.digDepth + radius, 0), radius: radius)
        }
        XCTAssertEqual(field.surfaceHeight(x: 0, z: 0), -workload.maxDepth, accuracy: 1e-5)
        XCTAssertTrue(field.heights.allSatisfy { $0 >= -workload.maxDepth && $0 <= 0 })
        XCTAssertTrue(field.carve(center: SIMD3(0, 5, 0), radius: radius).isEmpty, "sphere above ground removes nothing")
        XCTAssertTrue(field.carve(center: SIMD3(.nan, 0, 0), radius: radius).isEmpty)
    }

    func testHeightfieldDirtyTilesIncludeNormalNeighbours() {
        var field = HeightfieldField(workload: workload)
        // Interior of tile (1, 1): vertices 16...32 on both axes.
        let centre = Float(24) * field.spacing - 0.5
        let small = field.spacing * 1.5
        XCTAssertEqual(field.carve(center: SIMD3(centre, small - 0.01, centre), radius: small).chunks, [1 * 4 + 1])
        // A vertex on the shared border column 32 touches tiles 1 and 2 in x.
        let border = Float(32) * field.spacing - 0.5
        let region = field.carve(center: SIMD3(border, small - 0.01, centre), radius: small)
        XCTAssertEqual(region.chunks, [1 * 4 + 1, 1 * 4 + 2])
    }

    func testHeightfieldMeshBoundsWindingAndNormals() {
        let field = runTrace(HeightfieldField.self).field
        var vertices = 0
        for mesh in field.geometry(for: field.allChunks) {
            assertMeshInvariants(mesh)
            vertices += mesh.vertexCount
            XCTAssertNotNil(mesh.indices16)
            for start in stride(from: 0, to: mesh.indices.count, by: 3) {
                let a = mesh.positions[Int(mesh.indices[start])]
                let b = mesh.positions[Int(mesh.indices[start + 1])]
                let c = mesh.positions[Int(mesh.indices[start + 2])]
                XCTAssertGreaterThan(cross(b - a, c - a).y, 0, "heightfield triangle faces down")
            }
            XCTAssertTrue(mesh.normals.allSatisfy { $0.y > 0 })
        }
        // 63 quads per side split 16/16/16/15, so tiles span 17, 17, 17 and 16 vertices.
        XCTAssertEqual(vertices, 67 * 67)
        XCTAssertGreaterThan(field.heights.filter { $0 < 0 }.count, 0)
    }

    // MARK: Voxels

    func testVoxelDigIsLocalAndRespectsFloor() {
        var field = VoxelField(workload: workload)
        let before = field
        let centre = SIMD3<Float>(0.1, -0.02, -0.1)
        let radius = workload.brushRadius
        XCTAssertFalse(field.carve(center: centre, radius: radius).isEmpty)
        var removed = 0
        for y in 0..<field.countY {
            for z in 0..<field.countZ {
                for x in 0..<field.countX where before.isSolid(x: x, y: y, z: z) != field.isSolid(x: x, y: y, z: z) {
                    removed += 1
                    let voxelCentre = field.origin + (SIMD3(Float(x), Float(y), Float(z)) + 0.5) * field.cellSize
                    let offset = voxelCentre - centre
                    XCTAssertLessThan((offset * offset).sum(), radius * radius)
                }
            }
        }
        XCTAssertGreaterThan(removed, 0)
        for _ in 0..<80 {
            let surface = field.surfaceHeight(x: 0.1, z: -0.1)
            _ = field.carve(center: SIMD3(0.1, surface - workload.digDepth + radius, -0.1), radius: radius)
        }
        let floor = field.surfaceHeight(x: 0.1, z: -0.1)
        XCTAssertGreaterThanOrEqual(floor, -workload.maxDepth - field.cellSize)
        XCTAssertLessThanOrEqual(floor, -workload.maxDepth + field.cellSize)
        for y in 0..<field.countY {
            let voxelCentreY = field.origin.y + (Float(y) + 0.5) * field.cellSize
            if voxelCentreY < -workload.maxDepth {
                for z in 0..<field.countZ { for x in 0..<field.countX { XCTAssertTrue(field.isSolid(x: x, y: y, z: z)) } }
            }
        }
    }

    func testVoxelChunkDirtyTracking() {
        var field = VoxelField(workload: workload)
        let cell = field.cellSize
        func world(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> { field.origin + SIMD3(x, y, z) * cell }
        // Inside chunk (x 1, y 1, z 1), away from its faces: only that chunk.
        let interior = field.carve(center: world(24, 24, 24), radius: cell * 2)
        XCTAssertEqual(interior.chunks, [field.chunkIndex(1, 1, 1)])
        // Clearing voxel x = 32 (first voxel of chunk x 2) exposes a face of chunk x 1's voxel 31.
        let boundary = field.carve(center: world(32.5, 24.5, 24.5), radius: cell * 0.6)
        XCTAssertEqual(boundary.chunks, [field.chunkIndex(2, 1, 1), field.chunkIndex(1, 1, 1)])
        // Repeating an identical carve changes nothing.
        XCTAssertTrue(field.carve(center: world(32.5, 24.5, 24.5), radius: cell * 0.6).isEmpty)
        // Top layer of chunk y 1 borders open sky only, so no chunk above is added.
        let top = field.carve(center: world(40.5, 31.5, 40.5), radius: cell * 0.6)
        XCTAssertEqual(top.chunks, [field.chunkIndex(2, 1, 2)])
    }

    func testVoxelExtractionBoundsWindingNormalsAndFlatTop() {
        let flat = VoxelField(workload: workload)
        let meshes = flat.geometry(for: flat.allChunks)
        let upward = meshes.reduce(0) { total, mesh in
            total + stride(from: 0, to: mesh.indices.count, by: 3).filter { mesh.normals[Int(mesh.indices[$0])].y == 1 }.count
        }
        XCTAssertEqual(upward, 2 * workload.voxelX * workload.voxelZ, "flat volume exposes one top quad per column")
        let field = runTrace(VoxelField.self).field
        for mesh in field.geometry(for: field.allChunks) {
            assertMeshInvariants(mesh)
            XCTAssertNotNil(mesh.indices16)
            for start in stride(from: 0, to: mesh.indices.count, by: 3) {
                let a = mesh.positions[Int(mesh.indices[start])]
                let b = mesh.positions[Int(mesh.indices[start + 1])]
                let c = mesh.positions[Int(mesh.indices[start + 2])]
                let facing = (cross(b - a, c - a) * mesh.normals[Int(mesh.indices[start])]).sum()
                XCTAssertGreaterThan(facing, 0, "voxel triangle winds against its outward normal")
            }
        }
    }

    // MARK: 2D side view

    func testSideViewMaskCarveLocalityClampAndTiles() {
        var mask = SideViewMask(workload: workload)
        XCTAssertEqual(mask.cells.count, 128 * 96)
        XCTAssertEqual(mask.chunkCount, 8 * 6)
        let radius = workload.brushRadius
        let region = mask.carve(center: SIMD3(0, radius - workload.digDepth, 0.3), radius: radius)
        XCTAssertFalse(region.isEmpty)
        XCTAssertFalse(mask.isOpen(SIMD3(0, -workload.digDepth - mask.cellSize, 0)))
        XCTAssertTrue(mask.isOpen(SIMD3(0, -workload.digDepth + mask.cellSize, 99)), "z is ignored")
        XCTAssertEqual(mask.surfaceHeight(x: 0, z: 0), -workload.digDepth, accuracy: mask.cellSize)
        XCTAssertEqual(mask.surfaceHeight(x: -0.4, z: 0), 0)
        for row in 0..<mask.rows {
            for column in 0..<mask.columns where mask.cells[row * mask.columns + column] == 0 {
                let dx = mask.originX + (Float(column) + 0.5) * mask.cellSize
                let dy = mask.originY + (Float(row) + 0.5) * mask.cellSize - (radius - workload.digDepth)
                XCTAssertLessThan(dx * dx + dy * dy, radius * radius)
            }
        }
        for _ in 0..<80 {
            let surface = mask.surfaceHeight(x: 0, z: 0)
            _ = mask.carve(center: SIMD3(0, surface - workload.digDepth + radius, 0), radius: radius)
        }
        XCTAssertEqual(mask.surfaceHeight(x: 0, z: 0), -workload.maxDepth, accuracy: mask.cellSize)
        for row in 0..<mask.rows where mask.originY + (Float(row) + 0.5) * mask.cellSize < -workload.maxDepth {
            XCTAssertTrue((0..<mask.columns).allSatisfy { mask.isSolid(column: $0, row: row) })
        }
    }

    func testSideViewMaskTilesCoverageAndContours() {
        let flat = SideViewMask(workload: workload)
        let topRight = flat.geometry(chunk: flat.chunkCount - 1)
        XCTAssertEqual(topRight.width, 16)
        XCTAssertEqual(topRight.height, 16)
        XCTAssertTrue(topRight.coverage.allSatisfy { $0 == 255 })
        // Bottom rows are interior (15) except the arena's right edge; the top row meets open sky (3).
        XCTAssertEqual(topRight.contourCases[0], 15)
        XCTAssertEqual(topRight.contourCases[15 * 16], 3)
        XCTAssertEqual(topRight.contourCases[15 * 16 + 15], 1)
        XCTAssertEqual(topRight.contourCases[15], 9)
        var mask = flat
        let region = mask.carve(center: SIMD3(0.2, workload.brushRadius - workload.digDepth, 0), radius: workload.brushRadius)
        for tile in mask.geometry(for: region) {
            for row in 0..<tile.height {
                for column in 0..<tile.width {
                    let solid = mask.isSolid(column: tile.originColumn + column, row: tile.originRow + row)
                    XCTAssertEqual(tile.coverage[row * tile.width + column], solid ? 255 : 0)
                }
            }
        }
        XCTAssertGreaterThan(mask.geometry(for: region).reduce(0) { $0 + $1.contourSegmentCount }, 0)
    }

    // MARK: Incremental rebuild matches full rebuild

    func testIncrementalChunkRebuildsMatchFullRebuild() {
        assertIncrementalMatchesFull(HeightfieldField.self)
        assertIncrementalMatchesFull(VoxelField.self)
        assertIncrementalMatchesFull(SideViewMask.self)
    }

    func testRaycastResolvesAgainstRuleField() {
        var rules = VoxelRules()
        rules.schedule(.dig(x: 0, z: 0))
        rules.schedule(.dig(x: 0, z: 0))
        _ = rules.step()
        let hit = rules.field.raycast(origin: SIMD3(0, 1, 0), direction: SIMD3(0, -1, 0), maxDistance: 3)
        XCTAssertNotNil(hit)
        XCTAssertEqual(hit!.y, rules.field.surfaceHeight(x: 0, z: 0), accuracy: 1e-3)
        XCTAssertLessThan(hit!.y, 0)
        XCTAssertNil(rules.field.raycast(origin: SIMD3(0, 1, 0), direction: SIMD3(0, 1, 0), maxDistance: 3))
        XCTAssertNil(rules.field.raycast(origin: SIMD3(0, -0.4, 0.3), direction: SIMD3(0, -1, 0), maxDistance: 3),
                     "ray starting inside solid ground is refused")
    }

    // MARK: Helpers

    func runTrace<Field: ExcavationField>(_ type: Field.Type) -> DigRules<Field> {
        var rules = DigRules<Field>(workload: workload)
        XCTAssertTrue(rules.load(trace: workload.makeTrace()))
        while !rules.isFinished { _ = rules.step() }
        return rules
    }

    func assertIncrementalMatchesFull<Field: ExcavationField>(_ type: Field.Type, file: StaticString = #filePath, line: UInt = #line)
    where Field.Geometry: Equatable {
        var rules = DigRules<Field>(workload: workload)
        rules.load(trace: workload.makeTrace())
        var installed = Dictionary(uniqueKeysWithValues: zip(0..<rules.field.chunkCount, rules.field.geometry(for: rules.field.allChunks)))
        while !rules.isFinished {
            let report = rules.step()
            for chunk in report.dirty.sortedChunks { installed[chunk] = rules.field.geometry(chunk: chunk) }
        }
        let full = rules.field.geometry(for: rules.field.allChunks)
        for (chunk, geometry) in full.enumerated() {
            XCTAssertEqual(installed[chunk], geometry, "chunk \(chunk) of \(Field.self) missed by dirty tracking", file: file, line: line)
        }
    }

    func assertMeshInvariants(_ mesh: SurfaceMesh, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(mesh.indices.count % 3, 0, file: file, line: line)
        XCTAssertEqual(mesh.normals.count, mesh.positions.count, file: file, line: line)
        XCTAssertTrue(mesh.indices.allSatisfy { Int($0) < mesh.positions.count }, "index out of bounds", file: file, line: line)
        for normal in mesh.normals {
            XCTAssertTrue(normal.x.isFinite && normal.y.isFinite && normal.z.isFinite, file: file, line: line)
            XCTAssertEqual((normal * normal).sum(), 1, accuracy: 1e-5, file: file, line: line)
        }
        for position in mesh.positions {
            XCTAssertTrue(position.x.isFinite && position.y.isFinite && position.z.isFinite, file: file, line: line)
        }
    }
}

func cross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
    SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
}
