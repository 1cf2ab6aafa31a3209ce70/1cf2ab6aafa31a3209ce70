import SwiftUI
import RealityKit

@available(iOS 18.0, macOS 15.0, *)
@MainActor
struct TerrainProbeView: View {
    let isPaused: Bool
    @State private var pauseFlag: Bool
    @State private var savedMotion: PhysicsMotionComponent?
    let onMeasurement: (String) -> Void
    let onFrame: (TimeInterval) -> Void
    @State private var field = TerrainHeightfield()
    @State private var renderedField = TerrainHeightfield()
    @State private var dropCenter = SIMD2<Float>(0, 0)
    @State private var renderedDropCenter = SIMD2<Float>(0, 0)
    @State private var terrain = ModelEntity()
    @State private var ball = ModelEntity()
    @State private var sphereRoot = Entity()
    @State private var collisionSubscription: EventSubscription?
    @State private var updateSubscription: EventSubscription?
    @State private var collisionStatus = "Waiting for sphere contact"
    @State private var settledStatus = "Waiting for settled sphere"
    @State private var dropTime = ProcessInfo.processInfo.systemUptime
    @State private var settledRevision = 0
    @State private var lastPhysicsDiagnostic = 0.0
    @State private var stableSince: TimeInterval?
    @State private var stableHeight: Float = 0
    @State private var busy = false
    @State private var drill = 0
    @State private var revision = 0
    @State private var status = "Preparing terrain…"

    init(isPaused: Bool = false, onMeasurement: @escaping (String) -> Void, onFrame: @escaping (TimeInterval) -> Void = { _ in }) {
        self.isPaused = isPaused
        self._pauseFlag = State(initialValue: isPaused)
        self.onMeasurement = onMeasurement
        self.onFrame = onFrame
    }

    var body: some View {
        VStack {
            RealityView { content in
                content.camera = .virtual
                let camera = PerspectiveCamera()
                camera.look(at: [0, -0.1, 0], from: [0, 1.7, 2.0], relativeTo: nil)
                content.add(camera)
                let light = DirectionalLight()
                light.light.intensity = 2_000
                light.look(at: [0, 0, 0], from: [-1.5, 2.5, 1.0], relativeTo: nil)
                content.add(light)
                content.add(terrain)
                content.add(sphereRoot)
                collisionSubscription = content.subscribe(to: CollisionEvents.Began.self, on: terrain) { event in
                    guard !pauseFlag, event.entityA === ball || event.entityB === ball else { return }
                    collisionStatus = String(format: "Sphere contact y=%.3f x=%.3f z=%.3f dug=(%.3f,%.3f)", ball.position.y, ball.position.x, ball.position.z, renderedDropCenter.x, renderedDropCenter.y)
                    collisionStatus += " revision=\(revision)"
                    onMeasurement("Terrain collision revision=\(revision) \(collisionStatus)")
                }
                updateSubscription = content.subscribe(to: SceneEvents.Update.self) { _ in
                    guard !pauseFlag else { return }
                    let now = ProcessInfo.processInfo.systemUptime
                    onFrame(now)
                    guard settledRevision != revision, revision > 0, now - dropTime >= 1 else { return }
                    let motion = ball.components[PhysicsMotionComponent.self]
                    let velocity = motion?.linearVelocity ?? .zero
                    let speedSquared = velocity.x * velocity.x + velocity.y * velocity.y + velocity.z * velocity.z
                    if now - lastPhysicsDiagnostic >= 1 {
                        lastPhysicsDiagnostic = now
                        settledStatus = String(format: "Settling revision=%d y=%.3f x=%.3f z=%.3f speed=%.3f age=%.1f", revision, ball.position.y, ball.position.x, ball.position.z, sqrt(speedSquared), now - dropTime)
                        onMeasurement("Terrain physics \(settledStatus)")
                    }
                    guard speedSquared < 0.0004 else {
                        stableSince = nil
                        return
                    }
                    guard let since = stableSince else {
                        stableSince = now
                        stableHeight = ball.position.y
                        return
                    }
                    guard abs(ball.position.y - stableHeight) < 0.002 else {
                        stableSince = nil
                        return
                    }
                    guard now - since >= 0.75 else { return }
                    settledRevision = revision
                    settledStatus = String(format: "Sphere settled y=%.3f x=%.3f z=%.3f revision=%d", ball.position.y, ball.position.x, ball.position.z, revision)
                    onMeasurement("Terrain settled revision=\(revision) \(settledStatus)")
                }
                await rebuild()
            }
            .gesture(SpatialTapGesture().targetedToEntity(terrain).onEnded { value in
                guard !busy, !pauseFlag else { return }
                guard let hit = value.hitTest(point: value.location, in: .local).first(where: { $0.entity === terrain }) else { return }
                let point = terrain.convert(position: hit.position, from: nil)
                field.dig(x: point.x, z: point.z)
                dropCenter = [point.x, point.z]
                onMeasurement(String(format: "Terrain targeted tap x=%.3f z=%.3f", point.x, point.z))
                Task { await rebuild() }
            })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Terrain interaction surface")
            .accessibilityIdentifier("terrain.surface")
            .frame(minHeight: 120)
            Text("625 vertices · 1,152 triangles · sphere collision probe")
                .font(.caption)
            Text(settledStatus).font(.caption.monospaced()).accessibilityIdentifier("terrain.settled")
            Text(collisionStatus).font(.caption.monospaced()).accessibilityIdentifier("terrain.collision")
            Text(status).font(.caption.monospaced()).accessibilityIdentifier("terrainStatus")
            HStack {
                Button("Drill next crater") {
                    guard !busy, !pauseFlag else { return }
                    let x = Float(drill % 5 - 2) * 0.24
                    let z = Float((drill / 5) % 5 - 2) * 0.24
                    drill += 1
                    field.dig(x: x, z: z)
                    dropCenter = [x, z]
                    Task { await rebuild() }
                }.accessibilityIdentifier("terrain.drill")
                Button("Reset terrain") {
                    guard !busy, !pauseFlag else { return }
                    field = TerrainHeightfield()
                    dropCenter = [0, 0]
                    drill = 0
                    Task { await rebuild() }
                }.accessibilityIdentifier("terrain.reset")
            }.disabled(busy || pauseFlag)
            Text("Tap/click to dig; buttons repeat a grid. Sphere contact logs collision. Drag and device acceptance pending.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding()
        .onDisappear {
            pauseFlag = true
            collisionSubscription?.cancel()
            updateSubscription?.cancel()
            collisionSubscription = nil
            updateSubscription = nil
            setPhysicsPaused(true)
        }
        .onChange(of: isPaused) { _, paused in
            pauseFlag = paused
            setPhysicsPaused(paused)
            if !paused && terrain.model == nil { Task { await rebuild() } }
        }
    }

    private func rebuild() async {
        guard !busy, !pauseFlag else { return }
        busy = true
        defer { busy = false }
        do {
            let begin = ContinuousClock.now
            var descriptor = MeshDescriptor(name: "original-heightfield")
            descriptor.positions = MeshBuffers.Positions(field.positions)
            descriptor.normals = MeshBuffers.Normals(field.normals)
            descriptor.primitives = .triangles(field.triangleIndices)
            let mesh = try MeshResource.generate(from: [descriptor])
            let meshDuration = begin.duration(to: .now)
            let collisionBegin = ContinuousClock.now
            let shape = try await ShapeResource.generateStaticMesh(positions: field.positions, faceIndices: field.triangleIndices.map { UInt16($0) })
            let collisionDuration = collisionBegin.duration(to: .now)
            guard !pauseFlag else {
                field = renderedField
                dropCenter = renderedDropCenter
                return
            }
            renderedField = field
            renderedDropCenter = dropCenter
            terrain.model = ModelComponent(mesh: mesh, materials: [SimpleMaterial(color: .brown, roughness: 0.9, isMetallic: false)])
            terrain.components.set(CollisionComponent(shapes: [shape], mode: .default, filter: .default))
            terrain.components.set(InputTargetComponent())
            terrain.components.set(PhysicsBodyComponent(shapes: [shape], mass: 1, material: .generate(staticFriction: 0.8, dynamicFriction: 0.8, restitution: 0), mode: .static))
            dropSphere()
            revision += 1
            status = String(format: "Revision %d · mesh %.2f ms · collision %.2f ms", revision, milliseconds(meshDuration), milliseconds(collisionDuration))
            onMeasurement("Terrain \(status); revision=\(revision) vertices=625 triangles=1152")
        } catch {
            field = renderedField
            dropCenter = renderedDropCenter
            guard !pauseFlag else { return }
            status = "Terrain regeneration failed: \(error.localizedDescription)"
            onMeasurement(status)
        }
    }

    private func dropSphere() {
        guard !pauseFlag else { return }
        ball.removeFromParent()
        ball = ModelEntity()
        savedMotion = nil
        let shape = ShapeResource.generateSphere(radius: 0.06)
        ball.model = ModelComponent(mesh: .generateSphere(radius: 0.06), materials: [UnlitMaterial(color: .cyan)])
        ball.position = [dropCenter.x, 0.65, dropCenter.y]
        ball.components.set(CollisionComponent(shapes: [shape]))
        ball.components.set(PhysicsMotionComponent())
        var body = PhysicsBodyComponent(shapes: [shape], mass: 0.1, material: .generate(staticFriction: 0.8, dynamicFriction: 0.8, restitution: 0), mode: .dynamic)
        body.isContinuousCollisionDetectionEnabled = true
        // A vertical probe cannot roll away from the excavated patch.
        body.isTranslationLocked = (x: true, y: false, z: true)
        body.isRotationLocked = (x: true, y: true, z: true)
        body.linearDamping = 1
        ball.components.set(body)
        sphereRoot.addChild(ball)
        collisionStatus = "Sphere dropped; awaiting contact"
        settledStatus = "Waiting for settled sphere"
        dropTime = ProcessInfo.processInfo.systemUptime
        stableSince = nil
    }

    private func setPhysicsPaused(_ paused: Bool) {
        guard var body = ball.components[PhysicsBodyComponent.self] else { return }
        if paused {
            savedMotion = ball.components[PhysicsMotionComponent.self]
            body.mode = .kinematic
            ball.components.set(body)
            ball.components.set(PhysicsMotionComponent())
        } else {
            dropTime = ProcessInfo.processInfo.systemUptime
        stableSince = nil
            body.mode = .dynamic
            ball.components.set(body)
            if let savedMotion { ball.components.set(savedMotion) }
            savedMotion = nil
        }
    }

    private func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }
}
