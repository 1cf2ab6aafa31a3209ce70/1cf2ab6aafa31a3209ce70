import Combine
import DigCore
import Foundation
import RealityKit
import UIKit

/// Candidates A (heightfield) and B (voxel chunks): one `ModelEntity` per geometry chunk.
/// Meshes are `MeshDescriptor` rebuilds of the dirty chunks; collision is a per-chunk
/// `ShapeResource.generateStaticMesh(positions:faceIndices:)`, generated asynchronously and
/// serially within one job, with the whole dirty set installed together.
@MainActor
final class RealityDigEngine<Field: ExcavationField>: RuleEngine<Field> where Field.Geometry == SurfaceMesh {
    private let arView: ARView
    private let relay = GestureRelay()
    private var anchor: AnchorEntity?
    private var chunks: [ModelEntity] = []
    private var markers: [Int: ModelEntity] = [:]
    private var probes: [SphereProbe] = []
    private var cursorEntity: ModelEntity?
    private var subscriptions: [any Cancellable] = []
    /// Candidate A2 only: one CPU-updated LowLevelMesh per chunk, created on first install.
    private var lowLevel: [Int: LowLevelMesh] = [:]
    private var usesLowLevelMesh: Bool { options.candidate == .lowlevel }
    private var installedCollisionRevision: UInt64?
    private var collisionInstalls = 0
    private let terrainMaterial = SimpleMaterial(color: .brown, roughness: 0.9, isMetallic: false)
    private let physicsMaterial = PhysicsMaterialResource.generate(staticFriction: 0.8, dynamicFriction: 0.8, restitution: 0)
    /// Collectibles under these rows (trench items on row z = 20) get a vertical sphere probe.
    private let probeItems = [8, 9, 10, 11]
    static var sphereRadius: Float { 0.03 }

    override init(options: DigOptions) {
        arView = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        super.init(options: options)
        arView.environment.background = .color(.secondarySystemBackground)
        relay.attach(to: arView) { [weak self] point, began in self?.touch(point, began: began) }
    }

    override var view: UIView { arView }

    override func buildScene() {
        let anchor = AnchorEntity(world: .zero)
        let camera = PerspectiveCamera()
        camera.look(at: [0, -0.1, 0], from: [0, 1.7, 2.0], relativeTo: nil)
        anchor.addChild(camera)
        let light = DirectionalLight()
        light.light.intensity = 2_000
        light.look(at: [0, 0, 0], from: [-1.5, 2.5, 1.0], relativeTo: nil)
        anchor.addChild(light)
        chunks = (0..<rules.field.chunkCount).map { index in
            let entity = ModelEntity()
            entity.name = "chunk.\(index)"
            anchor.addChild(entity)
            return entity
        }
        let markerMesh = MeshResource.generateSphere(radius: 0.018)
        let markerMaterial = SimpleMaterial(color: .systemYellow, roughness: 0.4, isMetallic: true)
        markers = [:]
        for item in rules.collectibles {
            let marker = ModelEntity(mesh: markerMesh, materials: [markerMaterial])
            marker.position = item.position
            marker.isEnabled = !item.isCollected
            anchor.addChild(marker)
            markers[item.id] = marker
        }
        let sphereMesh = MeshResource.generateSphere(radius: Self.sphereRadius)
        probes = probeItems.map { id in
            let item = rules.collectibles[id].position
            let probe = SphereProbe(id: id, mesh: sphereMesh, at: SIMD3(item.x, 0.2, item.z), radius: Self.sphereRadius,
                                    material: physicsMaterial)
            anchor.addChild(probe.entity)
            return probe
        }
        let cursor = ModelEntity(mesh: .generateBox(size: [0.05, 0.006, 0.05]), materials: [UnlitMaterial(color: .cyan)])
        anchor.addChild(cursor)
        cursorEntity = cursor
        installedCollisionRevision = nil
        collisionInstalls = 0
        arView.scene.addAnchor(anchor)
        self.anchor = anchor
        subscriptions = [
            arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
                self?.frame(timestamp: ProcessInfo.processInfo.systemUptime)
            },
            arView.scene.subscribe(to: CollisionEvents.Began.self) { [weak self] event in
                self?.contact(event)
            },
        ]
    }

    override func teardownScene() {
        for subscription in subscriptions { subscription.cancel() }
        subscriptions = []
        if let anchor { arView.scene.removeAnchor(anchor) }
        anchor = nil
        chunks = []
        lowLevel = [:]
        markers = [:]
        probes = []
        cursorEntity = nil
    }

    override func startMeshJob(_ job: GeometrySync.Job, field: Field, epoch: Int) {
        let window = metrics.windowName
        let delay = options.meshDelay
        Task { @MainActor [weak self] in
            let (meshes, extractMs) = await Task.detached(priority: .userInitiated) { () -> ([SurfaceMesh], Double) in
                let start = ContinuousClock.now
                let meshes = field.geometry(for: job.region)
                return (meshes, start.duration(to: .now).milliseconds)
            }.value
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard let self, self.shouldInstall(job, epoch: epoch) else { return }
            let start = ContinuousClock.now
            var vertices = 0
            var triangles = 0
            for mesh in meshes {
                vertices += mesh.vertexCount
                triangles += mesh.triangleCount
                do { try self.install(mesh) } catch { self.metrics.recordFailure("mesh \(mesh.chunk): \(error)") }
            }
            self.metrics.recordMesh(.init(window: window, chunks: meshes.count, vertices: vertices, triangles: triangles,
                                          extractMs: extractMs, mainMs: start.duration(to: .now).milliseconds))
            self.didInstall(job)
        }
    }

    private func install(_ mesh: SurfaceMesh) throws {
        guard chunks.indices.contains(mesh.chunk) else { return }
        let entity = chunks[mesh.chunk]
        guard !mesh.positions.isEmpty else {
            entity.model = nil
            return
        }
        if usesLowLevelMesh {
            try installLowLevel(mesh, on: entity)
            return
        }
        var descriptor = MeshDescriptor(name: "chunk")
        descriptor.positions = MeshBuffers.Positions(mesh.positions)
        descriptor.normals = MeshBuffers.Normals(mesh.normals)
        descriptor.primitives = .triangles(mesh.indices)
        let resource = try MeshResource.generate(from: [descriptor])
        if entity.model == nil {
            entity.model = ModelComponent(mesh: resource, materials: [terrainMaterial])
        } else {
            entity.model?.mesh = resource
        }
    }

    /// Fixed topology: indices and part bounds are written once; later updates rewrite only
    /// the interleaved position/normal buffer on the CPU.
    private func installLowLevel(_ mesh: SurfaceMesh, on entity: ModelEntity) throws {
        if let existing = lowLevel[mesh.chunk], existing.vertexCapacity == mesh.vertexCount,
           existing.indexCapacity == mesh.indices.count {
            writeVertices(mesh, into: existing)
            return
        }
        let stride = MemoryLayout<SIMD3<Float>>.stride
        let descriptor = LowLevelMesh.Descriptor(
            vertexCapacity: mesh.vertexCount,
            vertexAttributes: [.init(semantic: .position, format: .float3, layoutIndex: 0, offset: 0),
                               .init(semantic: .normal, format: .float3, layoutIndex: 0, offset: stride)],
            vertexLayouts: [.init(bufferIndex: 0, bufferOffset: 0, bufferStride: stride * 2)],
            indexCapacity: mesh.indices.count, indexType: .uint32)
        let lowLevelMesh = try LowLevelMesh(descriptor: descriptor)
        lowLevelMesh.withUnsafeMutableIndices { raw in
            let indices = raw.bindMemory(to: UInt32.self)
            for (index, value) in mesh.indices.enumerated() { indices[index] = value }
        }
        let xs = mesh.positions.map(\.x), zs = mesh.positions.map(\.z)
        let depth = workload.maxDepth + 0.01
        let bounds = BoundingBox(min: [xs.min() ?? 0, -depth, zs.min() ?? 0], max: [xs.max() ?? 0, 0.01, zs.max() ?? 0])
        lowLevelMesh.parts.replaceAll([LowLevelMesh.Part(indexOffset: 0, indexCount: mesh.indices.count, topology: .triangle,
                                                         materialIndex: 0, bounds: bounds)])
        writeVertices(mesh, into: lowLevelMesh)
        lowLevel[mesh.chunk] = lowLevelMesh
        entity.model = ModelComponent(mesh: try MeshResource(from: lowLevelMesh), materials: [terrainMaterial])
    }

    private func writeVertices(_ mesh: SurfaceMesh, into lowLevelMesh: LowLevelMesh) {
        lowLevelMesh.replaceUnsafeMutableBytes(bufferIndex: 0) { raw in
            let vertices = raw.bindMemory(to: SIMD3<Float>.self)
            for index in 0..<mesh.vertexCount {
                vertices[2 * index] = mesh.positions[index]
                vertices[2 * index + 1] = mesh.normals[index]
            }
        }
    }

    override func startCollisionJob(_ job: GeometrySync.Job, field: Field, epoch: Int) {
        let window = metrics.windowName
        let delay = options.collisionDelay
        Task { @MainActor [weak self] in
            let jobStart = ContinuousClock.now
            let meshes = await Task.detached(priority: .userInitiated) { field.geometry(for: job.region) }.value
            var shapes: [(Int, ShapeResource?)] = []
            var failed = false
            for mesh in meshes {
                guard !mesh.positions.isEmpty else { shapes.append((mesh.chunk, nil)); continue }
                guard let indices = mesh.indices16 else { failed = true; break }
                let start = ContinuousClock.now
                do {
                    let shape = try await ShapeResource.generateStaticMesh(positions: mesh.positions, faceIndices: indices)
                    self?.metrics.recordCollision(.init(window: window, chunk: mesh.chunk, triangles: mesh.triangleCount,
                                                        ms: start.duration(to: .now).milliseconds))
                    shapes.append((mesh.chunk, shape))
                } catch {
                    self?.metrics.recordFailure("collision \(mesh.chunk): \(error)")
                    failed = true
                    break
                }
            }
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard let self else { return }
            if failed {
                self.abandon(job, epoch: epoch)
                return
            }
            guard self.shouldInstall(job, epoch: epoch) else { return }
            for (chunk, shape) in shapes where self.chunks.indices.contains(chunk) {
                let entity = self.chunks[chunk]
                if let shape {
                    entity.components.set(CollisionComponent(shapes: [shape], mode: .default, filter: .default))
                    entity.components.set(PhysicsBodyComponent(shapes: [shape], mass: 1, material: self.physicsMaterial, mode: .static))
                } else {
                    entity.components.remove(CollisionComponent.self)
                    entity.components.remove(PhysicsBodyComponent.self)
                }
            }
            self.installedCollisionRevision = job.revision
            self.collisionInstalls += 1
            self.metrics.recordCollisionJob(.init(window: window, chunks: shapes.count,
                                                  wallMs: jobStart.duration(to: .now).milliseconds))
            for probe in self.probes {
                if probe.isActive { probe.wake() } else if self.sync.isCollisionCurrent { probe.activate() }
            }
            self.didInstall(job)
        }
    }

    override func frameHook(now: TimeInterval) {
        if let cursorEntity {
            let point = rules.cursor
            cursorEntity.position = [point.x, rules.field.surfaceHeight(x: point.x, z: point.y) + 0.004, point.y]
        }
        for probe in probes where probe.isActive {
            probe.observe(now: now) { [rules] x, z in rules.field.surfaceHeight(x: x, z: z) + Self.sphereRadius }
            probe.colliderRevision = installedCollisionRevision
        }
    }

    override func collectedHook(_ ids: [Int]) {
        for id in ids { markers[id]?.isEnabled = false }
    }

    override func pauseHook(_ paused: Bool) -> Double? {
        var drift: Double?
        for probe in probes where probe.isActive {
            if let moved = probe.setPaused(paused) { drift = max(drift ?? 0, moved) }
        }
        return drift
    }

    private func contact(_ event: CollisionEvents.Began) {
        guard !paused else { return }
        for probe in probes where event.entityA === probe.entity || event.entityB === probe.entity {
            probe.recordContact(revision: installedCollisionRevision)
        }
    }

    private func touch(_ point: CGPoint, began: Bool) {
        guard let ray = arView.ray(through: point),
              let hit = rules.field.raycast(origin: ray.origin, direction: ray.direction, maxDistance: 8) else { return }
        touchDig(at: SIMD2(hit.x, hit.z), began: began)
    }

    override var entityCount: Int {
        func count(_ entity: Entity) -> Int { 1 + entity.children.reduce(0) { $0 + count($1) } }
        return anchor.map(count) ?? 0
    }

    override var subscriptionCount: Int { subscriptions.count }

    override var physicsSettled: Bool { probes.allSatisfy { $0.isActive && $0.isSettled } }

    override var physicsReport: [[String: Any]] { probes.map(\.report) }
}

/// A vertical sphere probe over a trench (as in Spike 00): horizontal translation and
/// rotation locked, restitution 0, friction 0.8. First contact and settled rest are
/// recorded separately; rest needs speed below 0.02 su/s and height within 0.002 su for
/// 0.75 s. It stays kinematic until the first full collider set is installed.
@MainActor
final class SphereProbe {
    let id: Int
    let entity: ModelEntity
    let radius: Float
    private let spawn: SIMD3<Float>
    private(set) var isActive = false
    private var savedMotion: PhysicsMotionComponent?
    private var pausedAt: SIMD3<Float>?
    private var activatedAt: TimeInterval?
    private var firstContact: [String: Any]?
    private var settles: [[String: Any]] = []
    private var moving = true
    private var stableSince: TimeInterval?
    private var stableHeight: Float = 0
    var colliderRevision: UInt64?

    init(id: Int, mesh: MeshResource, at position: SIMD3<Float>, radius: Float, material: PhysicsMaterialResource) {
        self.id = id
        self.radius = radius
        spawn = position
        entity = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: .cyan)])
        entity.position = position
        let shape = ShapeResource.generateSphere(radius: radius)
        entity.components.set(CollisionComponent(shapes: [shape]))
        var body = PhysicsBodyComponent(shapes: [shape], mass: 0.1, material: material, mode: .kinematic)
        body.isContinuousCollisionDetectionEnabled = true
        body.isTranslationLocked = (x: true, y: false, z: true)
        body.isRotationLocked = (x: true, y: true, z: true)
        body.linearDamping = 1
        entity.components.set(body)
        entity.components.set(PhysicsMotionComponent())
    }

    var isSettled: Bool { !moving && !settles.isEmpty }

    func activate() {
        guard !isActive, var body = entity.components[PhysicsBodyComponent.self] else { return }
        isActive = true
        activatedAt = ProcessInfo.processInfo.systemUptime
        body.mode = .dynamic
        entity.components.set(body)
    }

    /// A replaced static shape does not always wake a resting body; a tiny downward
    /// velocity (below the rest threshold) does.
    func wake() {
        guard var motion = entity.components[PhysicsMotionComponent.self] else { return }
        if (motion.linearVelocity * motion.linearVelocity).sum() < 0.0001 {
            motion.linearVelocity = [0, -0.01, 0]
            entity.components.set(motion)
        }
    }

    func recordContact(revision: UInt64?) {
        guard firstContact == nil else { return }
        let now = ProcessInfo.processInfo.systemUptime
        firstContact = ["y": DigMetrics.round3(Double(entity.position.y)), "colliderRevision": revision.map { Int($0) } ?? -1,
                        "secondsAfterActivation": DigMetrics.round3(now - (activatedAt ?? now))]
    }

    func observe(now: TimeInterval, expectedRestY: (Float, Float) -> Float) {
        let velocity = entity.components[PhysicsMotionComponent.self]?.linearVelocity ?? .zero
        let speedSquared = (velocity * velocity).sum()
        guard speedSquared < 0.0004 else {
            moving = true
            stableSince = nil
            return
        }
        let y = entity.position.y
        guard let since = stableSince else {
            stableSince = now
            stableHeight = y
            return
        }
        guard abs(y - stableHeight) < 0.002 else {
            stableSince = nil
            return
        }
        guard now - since >= 0.75, moving || settles.isEmpty else { return }
        moving = false
        let expected = expectedRestY(spawn.x, spawn.z)
        settles.append(["y": DigMetrics.round3(Double(y)), "ruleRestY": DigMetrics.round3(Double(expected)),
                        "colliderRevision": colliderRevision.map { Int($0) } ?? -1,
                        "secondsAfterActivation": DigMetrics.round3(now - (activatedAt ?? now))])
        if settles.count > 40 { settles.removeFirst() }
    }

    /// Kinematic while paused, motion restored on resume. Returns the drift over the pause.
    func setPaused(_ paused: Bool) -> Double? {
        guard var body = entity.components[PhysicsBodyComponent.self] else { return nil }
        if paused {
            savedMotion = entity.components[PhysicsMotionComponent.self]
            pausedAt = entity.position
            body.mode = .kinematic
            entity.components.set(body)
            entity.components.set(PhysicsMotionComponent())
            return nil
        }
        let drift = pausedAt.map { Double(simd_distance($0, entity.position)) }
        body.mode = .dynamic
        entity.components.set(body)
        if let savedMotion { entity.components.set(savedMotion) }
        savedMotion = nil
        pausedAt = nil
        stableSince = nil
        return drift
    }

    var report: [String: Any] {
        var result: [String: Any] = ["item": id, "x": DigMetrics.round3(Double(spawn.x)), "z": DigMetrics.round3(Double(spawn.z)),
                                     "active": isActive, "finalY": DigMetrics.round3(Double(entity.position.y)),
                                     "settles": settles]
        if let firstContact { result["firstContact"] = firstContact }
        return result
    }
}
