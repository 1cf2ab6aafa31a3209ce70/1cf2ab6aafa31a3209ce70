import SpriteKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Disposable input and rendering experiment; deliberately owns no persistent game state.
final class BoardScene: SKScene {
    enum Mode: String, CaseIterable { case blocks, panel }
    let mode: Mode
    var onFrame: ((TimeInterval) -> Void)?
    var onAction: ((String) -> Void)?
    var onResize: ((CGSize) -> Void)?
    private var selected = 0
    private var removed: Set<Int> = []
    private var boardOrigin = CGPoint.zero
    private var cellSize: CGFloat = 1
    private let content = SKNode()
    private let selection = SKShapeNode()
    private var columns: Int { mode == .blocks ? 8 : 4 }
    private var rows: Int { mode == .blocks ? 8 : 3 }

    init(mode: Mode) {
        self.mode = mode
        super.init(size: CGSize(width: 640, height: 640))
        scaleMode = .resizeFill
        backgroundColor = SKColor(red: 0.06, green: 0.08, blue: 0.13, alpha: 1)
        addChild(content)
        selection.strokeColor = .white
        selection.lineWidth = 3
        selection.fillColor = .clear
        selection.zPosition = 10
        content.addChild(selection)
    }

    required init?(coder: NSCoder) { fatalError("Use init(mode:)") }

    override func didMove(to view: SKView) {
        rebuild()
        onResize?(size)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        rebuild()
        onResize?(size)
    }
    override func update(_ currentTime: TimeInterval) { onFrame?(currentTime) }

    private func rebuild() {
        content.children.filter { $0 !== selection }.forEach { $0.removeFromParent() }
        let geometry = BoardGeometry(columns: columns, rows: rows, viewport: size)
        cellSize = geometry.cellSize
        boardOrigin = geometry.origin
        if mode == .panel {
            let plate = SKShapeNode(rect: CGRect(x: boardOrigin.x - 8, y: boardOrigin.y - 8,
                                                width: cellSize * CGFloat(columns) + 16,
                                                height: cellSize * CGFloat(rows) + 16), cornerRadius: 18)
            plate.fillColor = SKColor(red: 0.30, green: 0.35, blue: 0.42, alpha: 1)
            plate.strokeColor = .lightGray
            content.addChild(plate)
        }
        let colors: [SKColor] = [.systemTeal, .systemOrange, .systemPink, .systemPurple]
        for index in 0..<(columns * rows) where !removed.contains(index) {
            let node: SKShapeNode
            if mode == .blocks {
                node = SKShapeNode(rectOf: CGSize(width: cellSize - 6, height: cellSize - 6), cornerRadius: 7)
                node.fillColor = colors[(index + index / columns) % colors.count]
            } else {
                node = SKShapeNode(circleOfRadius: cellSize * 0.24)
                node.fillColor = .systemYellow
                let slot = SKShapeNode(rectOf: CGSize(width: cellSize * 0.30, height: 4))
                slot.fillColor = .darkGray
                slot.strokeColor = .clear
                node.addChild(slot)
            }
            node.strokeColor = .clear
            node.position = center(of: index)
            content.addChild(node)
        }
        updateSelection()
    }

    private func center(of index: Int) -> CGPoint {
        BoardGeometry(columns: columns, rows: rows, viewport: size).center(of: index)
    }

    private func updateSelection() {
        let side = max(1, cellSize - 2)
        selection.path = CGPath(rect: CGRect(x: -side / 2, y: -side / 2, width: side, height: side), transform: nil)
        selection.position = center(of: selected)
    }

    private func activate(at point: CGPoint) {
        guard !isPaused else { return }
        guard let index = BoardGeometry(columns: columns, rows: rows, viewport: size).index(at: point) else { return }
        selected = index
        activateSelected()
    }

    private func activateSelected() {
        guard !isPaused else { return }
        if removed.contains(selected) { removed.remove(selected) } else { removed.insert(selected) }
        rebuild()
        onAction?("\(mode.rawValue): cell \(selected + 1) \(removed.contains(selected) ? "removed" : "restored")")
    }

    func handleKey(_ key: String) {
        guard !isPaused else { return }
        switch key {
        case "left": selected = (selected / columns) * columns + max(0, selected % columns - 1)
        case "right": selected = (selected / columns) * columns + min(columns - 1, selected % columns + 1)
        case "down": selected = max(selected % columns, selected - columns)
        case "up": selected = min((rows - 1) * columns + selected % columns, selected + columns)
        case "space", "return": activateSelected(); return
        default: return
        }
        updateSelection()
        onAction?("Keyboard selected cell \(selected + 1)")
    }

    #if os(macOS)
    override func mouseDown(with event: NSEvent) { activate(at: event.location(in: self)) }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123: handleKey("left")
        case 124: handleKey("right")
        case 125: handleKey("down")
        case 126: handleKey("up")
        case 36: handleKey("return")
        case 49: handleKey("space")
        default: super.keyDown(with: event); return
        }
    }
    #else
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first { activate(at: touch.location(in: self)) }
    }
    #endif
}
