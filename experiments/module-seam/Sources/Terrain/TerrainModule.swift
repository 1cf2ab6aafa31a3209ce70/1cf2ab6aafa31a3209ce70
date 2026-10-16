import Combine
import DevelopmentContent
import RealityKit
import SwiftUI
import UIKit

/// Disposable title-owned renderer; rules, shell flow and saves stay outside it.
@MainActor
final class TerrainModule: ObservableObject, GameModule {
    let session: RuleSession
    let displayName = "Terrain study"
    private let renderer: TerrainRenderer

    convenience init() {
        self.init(session: RuleSession(levelID: "dig-sample-01"))
    }

    init(session: RuleSession) {
        self.session = session
        renderer = TerrainRenderer(session: session)
    }

    func makeGameplay() -> TerrainGameplayView {
        TerrainGameplayView(session: session, renderer: renderer)
    }

    func makeControls() -> TerrainControlsView {
        TerrainControlsView(session: session)
    }

    func setReducedMotion(_ reduced: Bool) {
        session.reducedMotion = reduced
        // This study has no decorative or physics animation to suspend.
    }
}

@MainActor
struct TerrainGameplayView: View {
    @ObservedObject var session: RuleSession
    let renderer: TerrainRenderer

    var body: some View {
        TerrainSurface(session: session, renderer: renderer)
            .frame(minHeight: 260, idealHeight: 300, maxHeight: 360)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Terrain with \(session.rows) rows and \(session.columns) columns")
            .accessibilityValue("\(session.removedIndices.count) cells dug")
            .accessibilityHint("Use the cell controls below to dig with accessibility")
            .accessibilityIdentifier("terrain.surface")
    }
}

@MainActor
struct TerrainControlsView: View {
    @ObservedObject var session: RuleSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dug cells: \(session.removedIndices.count)")
                .accessibilityIdentifier("terrain.removed")
            Text("Select a terrain cell. The marked cells use the loaded dig fixture.")
                .font(.caption)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                ForEach(0..<max(0, session.columns * session.rows), id: \.self) { index in
                    Button {
                        guard session.playing else { return }
                        session.select(index: index)
                    } label: {
                        Text("Cell \(index + 1)")
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.bordered)
                    .disabled(!session.playing || session.removedIndices.contains(index))
                    .accessibilityLabel("Dig row \(index / max(session.columns, 1) + 1), column \(index % max(session.columns, 1) + 1)")
                    .accessibilityValue(session.removedIndices.contains(index) ? "Dug" : "Undug")
                    .accessibilityIdentifier("terrain.cell.\(index)")
                }
            }
        }
    }
}

@MainActor
private struct TerrainSurface: UIViewRepresentable {
    @ObservedObject var session: RuleSession
    let renderer: TerrainRenderer

    func makeUIView(context: Context) -> ARView {
        renderer.synchronize()
        return renderer.view
    }

    func updateUIView(_ view: ARView, context: Context) {
        renderer.synchronize()
    }
}

/// Stable ownership requires no scene-update subscription or frame-driven rules.
@MainActor
final class TerrainRenderer: NSObject {
    let view: ARView
    private let session: RuleSession
    private let anchor = AnchorEntity(world: .zero)
    private var cells: [Int: ModelEntity] = [:]
    private var renderedLevel: DevelopmentLevel?
    private var renderedRemoved: [Int] = []

    init(session: RuleSession) {
        self.session = session
        view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        super.init()
        view.environment.background = .color(.secondarySystemBackground)
        let camera = PerspectiveCamera()
        camera.look(at: [0, 0, 0], from: [0, 3.4, 3.4], relativeTo: nil)
        anchor.addChild(camera)
        let light = DirectionalLight()
        light.light.intensity = 2_000
        light.look(at: [0, 0, 0], from: [-2, 4, 2], relativeTo: nil)
        anchor.addChild(light)
        view.scene.addAnchor(anchor)
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(selectCell(_:))))
    }

    func synchronize() {
        if renderedLevel != session.level {
            for entity in cells.values { entity.removeFromParent() }
            cells.removeAll()
            renderedLevel = session.level
            renderedRemoved = []
            if case .dig(let level) = session.level {
                let columns = level.payload.columns
                let rows = level.payload.rows
                let unit: Float = 0.48
                for index in 0..<(columns * rows) {
                    // Original stepped columns are a tiny heightfield placeholder.
                    let height: Float = 0.12 + Float(index % 3) * 0.035
                    let size = SIMD3<Float>(unit * 0.9, height, unit * 0.9)
                    let marked = level.payload.targetCells.contains(index)
                    let color: UIColor = marked ? .systemTeal : .systemBrown
                    let cell = ModelEntity(mesh: .generateBox(size: size),
                                           materials: [SimpleMaterial(color: color, roughness: 0.9, isMetallic: false)])
                    cell.name = "terrain.cell.\(index)"
                    cell.position = [
                        (Float(index % columns) - Float(columns - 1) / 2) * unit,
                        height / 2,
                        (Float(index / columns) - Float(rows - 1) / 2) * unit
                    ]
                    cell.components.set(CollisionComponent(shapes: [.generateBox(size: size)]))
                    anchor.addChild(cell)
                    cells[index] = cell
                }
            }
        }
        if renderedRemoved != session.removedIndices {
            renderedRemoved = session.removedIndices
            for (index, entity) in cells {
                entity.isEnabled = !renderedRemoved.contains(index)
            }
        }
    }

    @objc private func selectCell(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended, session.playing,
              let hit = view.entity(at: gesture.location(in: view)),
              let index = cells.first(where: { $0.value === hit })?.key else { return }
        session.select(index: index)
        synchronize()
    }
}
