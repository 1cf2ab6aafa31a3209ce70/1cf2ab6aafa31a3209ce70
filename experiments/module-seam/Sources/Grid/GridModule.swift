import DevelopmentContent
import SpriteKit
import SwiftUI

/// Experiment-owned block renderer. The retained scene draws session state;
/// SpriteKit frames and animation never advance the deterministic rules.
@MainActor
final class GridModule: ObservableObject, GameModule {
    let session: RuleSession
    let displayName = "Block grid"
    private let scene: GridScene

    init() {
        let session = RuleSession(levelID: "block-sample-01")
        self.session = session
        self.scene = GridScene(session: session)
    }

    func makeGameplay() -> GridGameplayView {
        GridGameplayView(session: session, scene: scene)
    }

    func makeControls() -> GridControlsView { GridControlsView(session: session) }

    func setReducedMotion(_ enabled: Bool) {
        session.reducedMotion = enabled
        scene.removeAllActions()
    }
}

@MainActor
struct GridGameplayView: View {
    @ObservedObject var session: RuleSession
    let scene: GridScene

    var body: some View {
        SpriteView(scene: scene)
            .frame(minHeight: 180, idealHeight: 220, maxHeight: 260)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Block board")
            .accessibilityIdentifier("grid.surface")
            .onAppear { scene.synchronize() }
            .onChange(of: session.level) { _, _ in scene.synchronize() }
            .onChange(of: session.removedIndices) { _, _ in scene.synchronize() }
            .onChange(of: session.playing) { _, _ in scene.synchronize() }
    }
}

/// VoiceOver and large-text controls use precisely the same rule input as touch.
@MainActor
struct GridControlsView: View {
    @ObservedObject var session: RuleSession

    private var occupiedCells: [Int] {
        guard case .block(let level) = session.level else { return [] }
        return level.payload.occupiedCells.sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Removed blocks: \(session.removedIndices.count)")
                .accessibilityIdentifier("grid.removed")
            Text("Select the blocks in the seeded fixture order.")
                .font(.callout)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 8) {
                ForEach(occupiedCells, id: \.self) { index in
                    let removed = session.removedIndices.contains(index)
                    Button { session.select(index: index) } label: {
                        Label("Block \(index + 1)", systemImage: removed ? "checkmark.circle" : "square.fill")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!session.playing || removed)
                    .accessibilityIdentifier("grid.cell.\(index)")
                    .accessibilityValue(removed ? "Removed" : "Available")
                }
            }
        }
    }
}

@MainActor
final class GridScene: SKScene {
    private weak var session: RuleSession?
    private var gridRect = CGRect.zero
    private var columns = 0
    private var rows = 0
    private var occupied = Set<Int>()
    private var removed = Set<Int>()

    init(session: RuleSession) {
        self.session = session
        super.init(size: CGSize(width: 320, height: 220))
        scaleMode = .resizeFill
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("GridScene is constructed by GridModule") }

    override func didChangeSize(_ oldSize: CGSize) { synchronize() }

    func synchronize() {
        removeAllChildren()
        guard case .block(let level) = session?.level else {
            columns = 0; rows = 0; occupied = []; removed = []
            gridRect = .zero
            return
        }
        columns = level.payload.columns
        rows = level.payload.rows
        occupied = Set(level.payload.occupiedCells)
        removed = Set(session?.removedIndices ?? [])
        let cellSize = min(max(0, size.width - 24) / CGFloat(columns),
                           max(0, size.height - 24) / CGFloat(rows))
        gridRect = CGRect(x: (size.width - cellSize * CGFloat(columns)) / 2,
                          y: (size.height - cellSize * CGFloat(rows)) / 2,
                          width: cellSize * CGFloat(columns), height: cellSize * CGFloat(rows))
        guard cellSize > 0 else { return }
        for index in 0..<(columns * rows) {
            let node = SKShapeNode(rectOf: CGSize(width: max(1, cellSize - 8),
                                                  height: max(1, cellSize - 8)), cornerRadius: 8)
            node.position = CGPoint(x: gridRect.minX + (CGFloat(index % columns) + 0.5) * cellSize,
                                    y: gridRect.maxY - (CGFloat(index / columns) + 0.5) * cellSize)
            node.lineWidth = 2
            node.strokeColor = .gray
            node.fillColor = occupied.contains(index) && !removed.contains(index) ? .systemBlue : .clear
            addChild(node)
            if occupied.contains(index) && !removed.contains(index) {
                let number = SKLabelNode(text: String(index + 1))
                number.fontName = "Helvetica-Bold"
                number.fontSize = min(24, cellSize * 0.35)
                number.verticalAlignmentMode = .center
                number.fontColor = .white
                node.addChild(number)
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard touches.count == 1, let point = touches.first?.location(in: self),
              let session, session.playing, columns > 0, rows > 0,
              gridRect.width > 0, gridRect.height > 0,
              point.x >= gridRect.minX, point.x < gridRect.maxX,
              point.y > gridRect.minY, point.y <= gridRect.maxY else { return }
        let column = Int((point.x - gridRect.minX) / (gridRect.width / CGFloat(columns)))
        let row = Int((gridRect.maxY - point.y) / (gridRect.height / CGFloat(rows)))
        let index = row * columns + column
        guard occupied.contains(index), !removed.contains(index) else { return }
        session.select(index: index)
    }
}
