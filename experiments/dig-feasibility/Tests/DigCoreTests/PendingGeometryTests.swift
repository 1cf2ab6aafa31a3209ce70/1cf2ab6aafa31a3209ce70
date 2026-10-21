import XCTest
@testable import DigCore

final class PendingGeometryTests: XCTestCase {
    let workload = DigWorkload.default

    func testMeshBuildsCoalesceToLatestRevision() {
        var rules = HeightfieldRules(workload: workload)
        var sync = GeometrySync(field: rules.field, collisionInterval: 6)
        let initial = sync.nextMeshJob()
        XCTAssertEqual(initial?.region, rules.field.allChunks)
        XCTAssertEqual(initial?.revision, 0)
        XCTAssertTrue(sync.complete(initial!))

        rules.schedule(.dig(x: -0.3, z: -0.3))
        sync.record(rules.step())
        let first = sync.nextMeshJob()!
        XCTAssertEqual(first.revision, 1)
        XCTAssertNil(sync.nextMeshJob(), "one mesh build in flight")

        // Rules keep advancing while revision 1 is pending.
        rules.schedule(.dig(x: 0.3, z: 0.3))
        let second = rules.step()
        sync.record(second)
        rules.schedule(.dig(x: 0.3, z: -0.3))
        let third = rules.step()
        sync.record(third)
        XCTAssertEqual(rules.revision, 3)
        XCTAssertNil(sync.nextMeshJob())

        XCTAssertTrue(sync.complete(first))
        XCTAssertEqual(sync.meshRevision, 1)
        XCTAssertFalse(sync.isMeshCurrent)
        let coalesced = sync.nextMeshJob()!
        XCTAssertEqual(coalesced.revision, 3, "revision 2 is skipped, not built")
        var expected = second.dirty
        expected.formUnion(third.dirty)
        XCTAssertEqual(coalesced.region, expected)
        XCTAssertFalse(sync.complete(first), "a completed job cannot be installed twice")
        XCTAssertTrue(sync.complete(coalesced))
        XCTAssertTrue(sync.isMeshCurrent)
        XCTAssertEqual(sync.meshJobsIssued, 3)
    }

    func testRestartRefusesStaleCompletions() {
        var rules = VoxelRules(workload: workload)
        var sync = GeometrySync(field: rules.field, collisionInterval: 0)
        rules.schedule(.dig(x: 0, z: 0))
        sync.record(rules.step())
        let mesh = sync.nextMeshJob()!
        let collision = sync.nextCollisionJob(tick: rules.tick)!
        sync.record(rules.restart())
        XCTAssertFalse(sync.complete(mesh))
        XCTAssertFalse(sync.complete(collision))
        XCTAssertNil(sync.meshRevision)
        let rebuild = sync.nextMeshJob()!
        XCTAssertEqual(rebuild.revision, 0)
        XCTAssertEqual(rebuild.region, rules.field.allChunks)
        XCTAssertTrue(sync.complete(rebuild))
    }

    func testCollisionRunsAtLowerCadenceAndAbandonRequeues() {
        var rules = HeightfieldRules(workload: workload)
        var sync = GeometrySync(field: rules.field, collisionInterval: 6)
        let initial = sync.nextCollisionJob(tick: rules.tick)!
        XCTAssertTrue(sync.complete(initial))
        var issuedAt: [UInt64] = []
        for tick in 0..<30 {
            rules.schedule(.dig(x: Float(tick) * 0.02 - 0.3, z: 0))
            sync.record(rules.step())
            if let job = sync.nextCollisionJob(tick: rules.tick) {
                issuedAt.append(rules.tick)
                XCTAssertEqual(job.revision, rules.revision)
                XCTAssertTrue(sync.complete(job))
            }
        }
        XCTAssertEqual(issuedAt, [6, 12, 18, 24, 30], "collision starts at most once per 6 ticks after the initial build")
        XCTAssertEqual(sync.collisionJobsIssued, 6)

        rules.schedule(.dig(x: 0.4, z: 0.4))
        sync.record(rules.step())
        let mesh = sync.nextMeshJob()!
        sync.abandon(mesh)
        XCTAssertNil(sync.meshInFlight)
        XCTAssertTrue(sync.nextMeshJob()!.region.chunks.isSuperset(of: mesh.region.chunks), "failed build is retried")
    }

    func testInputResolvesAgainstRuleFieldWhileGeometryIsPending() {
        var rules = HeightfieldRules(workload: workload)
        var sync = GeometrySync(field: rules.field, collisionInterval: 30)
        XCTAssertTrue(sync.complete(sync.nextMeshJob()!))
        XCTAssertTrue(sync.complete(sync.nextCollisionJob(tick: 0)!))
        let installedCollisionField = rules.field

        for _ in 0..<5 {
            rules.schedule(.dig(x: 0.1, z: 0.1))
            sync.record(rules.step())
        }
        // Collision is throttled, so the installed collision shape still describes revision 0.
        XCTAssertNil(sync.nextCollisionJob(tick: rules.tick))
        XCTAssertEqual(sync.collisionRevision, 0)
        XCTAssertEqual(rules.revision, 5)

        // A touch ray straight down at the dig: the rule field reports the new floor,
        // while the stale collision field would still report flat ground.
        let ray = (origin: SIMD3<Float>(0.1, 1, 0.1), direction: SIMD3<Float>(0, -1, 0))
        let ruleHit = rules.field.raycast(origin: ray.origin, direction: ray.direction, maxDistance: 3)!
        let staleHit = installedCollisionField.raycast(origin: ray.origin, direction: ray.direction, maxDistance: 3)!
        XCTAssertEqual(staleHit.y, 0, accuracy: 1e-4)
        XCTAssertEqual(ruleHit.y, rules.field.surfaceHeight(x: 0.1, z: 0.1), accuracy: 1e-3)
        XCTAssertLessThan(ruleHit.y, -0.05)
        // The next dig lands on the rule surface, not on the stale shape.
        XCTAssertEqual(rules.digCenter(x: ruleHit.x, z: ruleHit.z).y,
                       ruleHit.y - workload.digDepth + workload.brushRadius, accuracy: 1e-3)
    }

    /// A renderer loop with mesh builds that take several frames and throttled collision:
    /// rule outcomes match a geometry-free replay, and the installed chunks end equal to a
    /// full rebuild of the final field.
    func testDelayedGeometryDoesNotChangeRulesAndConverges() {
        assertDelayedGeometry(HeightfieldField.self)
        assertDelayedGeometry(VoxelField.self)
        assertDelayedGeometry(SideViewMask.self)
    }

    func assertDelayedGeometry<Field: ExcavationField>(_ type: Field.Type, file: StaticString = #filePath, line: UInt = #line)
    where Field.Geometry: Equatable {
        var reference = DigRules<Field>(workload: workload)
        reference.load(trace: workload.makeTrace())
        while !reference.isFinished { _ = reference.step() }

        var rules = DigRules<Field>(workload: workload)
        rules.load(trace: workload.makeTrace())
        var sync = GeometrySync(field: rules.field, collisionInterval: 6)
        var installed: [Int: Field.Geometry] = [:]
        var pending: (job: GeometrySync.Job, snapshot: Field, readyFrame: Int)?
        var frame = 0
        var maxLag: UInt64 = 0
        func pump() {
            if let work = pending, frame >= work.readyFrame {
                let output = work.snapshot.geometry(for: work.job.region)
                if sync.complete(work.job) { for item in zip(work.job.region.sortedChunks, output) { installed[item.0] = item.1 } }
                pending = nil
            }
            if pending == nil, let job = sync.nextMeshJob() {
                XCTAssertEqual(job.revision, rules.revision, file: file, line: line)
                pending = (job, rules.field, frame + 1 + frame % 4) // 1-4 frames of build latency
            }
            if let job = sync.nextCollisionJob(tick: rules.tick) { XCTAssertTrue(sync.complete(job), file: file, line: line) }
        }
        while !rules.isFinished {
            sync.record(rules.advance(frameDelta: 1.0 / 60))
            pump()
            maxLag = max(maxLag, rules.revision - (sync.meshRevision ?? 0))
            frame += 1
        }
        for _ in 0..<10 { pump(); frame += 1 }
        XCTAssertEqual(rules.digest, reference.digest, file: file, line: line)
        XCTAssertGreaterThan(maxLag, 0, "the mesh lagged the rules at least once", file: file, line: line)
        XCTAssertTrue(sync.isMeshCurrent, file: file, line: line)
        XCTAssertLessThan(sync.meshJobsIssued, Int(rules.revision) + 1, "builds were coalesced", file: file, line: line)
        let full = rules.field.geometry(for: rules.field.allChunks)
        for (chunk, geometry) in full.enumerated() {
            XCTAssertEqual(installed[chunk], geometry, "\(Field.self) chunk \(chunk)", file: file, line: line)
        }
    }
}
