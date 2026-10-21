import DigCore
import Foundation
import SpriteKit
import UIKit

final class DigSpriteScene: SKScene {
    var onUpdate: (@MainActor (TimeInterval) -> Void)?

    override func update(_ currentTime: TimeInterval) {
        MainActor.assumeIsolated { onUpdate?(currentTime) }
    }
}

/// Candidate C: the heightfield rules (same grid and brush as A) drawn top-down as a
/// 48 x 48 `SKTileMapNode` with ten 0.045 su depth bands. There is no collision lane:
/// the rules look up the cell, and nothing physical responds to the excavation.
@MainActor
final class SpriteDigEngine: RuleEngine<HeightfieldField> {
    static let side: CGFloat = 480
    static let bands = 10
    static let bandDepth: Float = 0.045
    private let skView = SKView()
    private let relay = GestureRelay()
    private let groups: [SKTileGroup]
    private let tileSet: SKTileSet
    private var scene: DigSpriteScene?
    private var tileMap: SKTileMapNode?
    private var installed: [UInt8] = []
    private var markers: [Int: SKShapeNode] = [:]
    private var cursorNode: SKShapeNode?
    private var reducedMotion = false
    private var cells: Int { Spike11Fixture.cells }

    override init(options: DigOptions) {
        let tile = CGSize(width: Self.side / CGFloat(Spike11Fixture.cells), height: Self.side / CGFloat(Spike11Fixture.cells))
        groups = (0..<Self.bands).map { band in
            SKTileGroup(tileDefinition: SKTileDefinition(texture: Self.texture(band: band), size: tile))
        }
        tileSet = SKTileSet(tileGroups: groups)
        super.init(options: options)
        skView.ignoresSiblingOrder = true
        if let fps = options.preferredFramesPerSecond { skView.preferredFramesPerSecond = fps }
        relay.attach(to: skView) { [weak self] point, began in self?.touch(point, began: began) }
    }

    override var view: UIView { skView }
    override var usesCollision: Bool { false }

    private static func texture(band: Int) -> SKTexture {
        let fraction = CGFloat(band) / CGFloat(bands - 1)
        let color = UIColor(red: 0.86 - 0.55 * fraction, green: 0.74 - 0.52 * fraction, blue: 0.52 - 0.40 * fraction, alpha: 1)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .nearest
        return texture
    }

    override func buildScene() {
        let scene = DigSpriteScene(size: CGSize(width: Self.side, height: Self.side))
        scene.scaleMode = .aspectFit
        scene.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        scene.backgroundColor = .secondarySystemBackground
        let tile = Self.side / CGFloat(cells)
        let map = SKTileMapNode(tileSet: tileSet, columns: cells, rows: cells, tileSize: CGSize(width: tile, height: tile),
                                fillWith: groups[0])
        scene.addChild(map)
        installed = Array(repeating: 0, count: cells * cells)
        markers = [:]
        for item in rules.collectibles {
            let marker = SKShapeNode(circleOfRadius: tile * 0.45)
            marker.position = scenePoint(SIMD2(item.position.x, item.position.z))
            marker.strokeColor = .systemYellow
            marker.lineWidth = 1.5
            marker.fillColor = .clear
            marker.zPosition = 1
            marker.isHidden = item.isCollected
            scene.addChild(marker)
            markers[item.id] = marker
        }
        let cursor = SKShapeNode(rectOf: CGSize(width: tile * 1.4, height: tile * 1.4))
        cursor.strokeColor = .cyan
        cursor.lineWidth = 2
        cursor.zPosition = 2
        scene.addChild(cursor)
        cursorNode = cursor
        scene.onUpdate = { [weak self] time in self?.frame(timestamp: time) }
        tileMap = map
        self.scene = scene
        skView.presentScene(scene)
    }

    override func teardownScene() {
        scene?.onUpdate = nil
        scene?.removeAllChildren()
        scene = nil
        tileMap = nil
        markers = [:]
        cursorNode = nil
        skView.presentScene(nil)
    }

    /// The "mesh" lane for 2D: recompute depth bands for the dirty chunks' cells and set
    /// only the tiles whose band changed.
    override func startMeshJob(_ job: GeometrySync.Job, field: HeightfieldField, epoch: Int) {
        let window = metrics.windowName
        let start = ContinuousClock.now
        var changes: [(Int, UInt8)] = []
        let quads = field.tileQuads
        let tiles = (cells + quads - 1) / quads
        for chunk in job.region.sortedChunks {
            let rowStart = (chunk / tiles) * quads, columnStart = (chunk % tiles) * quads
            for z in rowStart..<min(cells, rowStart + quads) {
                for x in columnStart..<min(cells, columnStart + quads) {
                    let band = Self.band(field: field, x: x, z: z)
                    if band != installed[z * cells + x] { changes.append((z * cells + x, band)) }
                }
            }
        }
        let computeMs = start.duration(to: .now).milliseconds
        let chunkCount = job.region.chunks.count
        let delay = options.meshDelay
        if delay == .zero {
            finishTiles(job, epoch: epoch, changes: changes, computeMs: computeMs, chunks: chunkCount, window: window)
        } else {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: delay)
                self?.finishTiles(job, epoch: epoch, changes: changes, computeMs: computeMs, chunks: chunkCount, window: window)
            }
        }
    }

    private func finishTiles(_ job: GeometrySync.Job, epoch: Int, changes: [(Int, UInt8)], computeMs: Double,
                             chunks: Int, window: String?) {
        guard shouldInstall(job, epoch: epoch), let tileMap else { return }
        let start = ContinuousClock.now
        for (index, band) in changes {
            tileMap.setTileGroup(groups[Int(band)], forColumn: index % cells, row: cells - 1 - index / cells)
            installed[index] = band
        }
        metrics.recordMesh(.init(window: window, chunks: chunks, vertices: changes.count, triangles: 0,
                                 extractMs: computeMs, mainMs: start.duration(to: .now).milliseconds))
        didInstall(job)
    }

    private static func band(field: HeightfieldField, x: Int, z: Int) -> UInt8 {
        let r = field.resolution
        let depth = -(field.heights[z * r + x] + field.heights[z * r + x + 1]
                      + field.heights[(z + 1) * r + x] + field.heights[(z + 1) * r + x + 1]) / 4
        return UInt8(min(bands - 1, max(0, Int(depth / bandDepth))))
    }

    override func frameHook(now: TimeInterval) {
        cursorNode?.position = scenePoint(rules.cursor)
    }

    override func collectedHook(_ ids: [Int]) {
        for id in ids {
            guard let marker = markers[id] else { continue }
            marker.fillColor = .systemYellow
            if reducedMotion {
                marker.isHidden = true
            } else {
                // Decorative drop animation; off under Reduce Motion.
                marker.run(.sequence([.group([.scale(to: 2.2, duration: 0.35), .fadeOut(withDuration: 0.35)]), .hide()]))
            }
        }
    }

    override func setReducedMotion(_ reduced: Bool) {
        reducedMotion = reduced
    }

    override func pauseHook(_ paused: Bool) -> Double? {
        scene?.isPaused = paused
        return nil
    }

    private func scenePoint(_ plane: SIMD2<Float>) -> CGPoint {
        let scale = Self.side / CGFloat(Spike11Fixture.arenaSize)
        return CGPoint(x: CGFloat(plane.x) * scale, y: -CGFloat(plane.y) * scale)
    }

    private func touch(_ point: CGPoint, began: Bool) {
        guard let scene else { return }
        let location = scene.convertPoint(fromView: point)
        let scale = CGFloat(Spike11Fixture.arenaSize) / Self.side
        let half = Spike11Fixture.arenaSize / 2
        let x = Float(location.x * scale), z = Float(-location.y * scale)
        guard abs(x) <= half, abs(z) <= half else { return }
        touchDig(at: SIMD2(x, z), began: began)
    }

    override var entityCount: Int {
        func count(_ node: SKNode) -> Int { 1 + node.children.reduce(0) { $0 + count($1) } }
        return scene.map(count) ?? 0
    }

    override var subscriptionCount: Int { scene?.onUpdate == nil ? 0 : 1 }
}
