import SpriteKit

/// The title owns its renderer and sample content. The shared shell owns the flow.
@MainActor
final class DevelopmentScene: SKScene {
    private let marker = SKShapeNode(circleOfRadius: 24)
    private let halo = SKShapeNode(circleOfRadius: 58)
    private(set) var acceptsGameInput = false
    private(set) var reducedMotion = false
    private(set) var preparationCount = 0

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = UIColor.secondarySystemGroupedBackground
        marker.fillColor = .systemTeal
        marker.strokeColor = .clear
        halo.strokeColor = .systemTeal
        halo.lineWidth = 2
        halo.alpha = 0.4
        addChild(halo)
        addChild(marker)
        isUserInteractionEnabled = false
        isPaused = true
        layoutContent()
    }

    required init?(coder: NSCoder) {
        fatalError("DevelopmentScene is created by its title")
    }

    func prepareSession() {
        preparationCount += 1
        marker.removeAllActions()
        marker.setScale(1)
        layoutContent()
        updateMotion()
    }

    func setPlaying(_ playing: Bool) {
        acceptsGameInput = playing
        isUserInteractionEnabled = playing
        isPaused = !playing
        updateMotion()
    }

    func setReducedMotion(_ enabled: Bool) {
        reducedMotion = enabled
        updateMotion()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        layoutContent()
    }

    private func layoutContent() {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        marker.position = center
        halo.position = center
    }

    private func updateMotion() {
        guard acceptsGameInput, !reducedMotion else {
            marker.removeAction(forKey: "practice-breathing")
            marker.setScale(1)
            return
        }
        guard marker.action(forKey: "practice-breathing") == nil else { return }
        let expand = SKAction.scale(to: 1.25, duration: 1.2)
        expand.timingMode = .easeInEaseOut
        let contract = SKAction.scale(to: 1, duration: 1.2)
        contract.timingMode = .easeInEaseOut
        marker.run(.repeatForever(.sequence([expand, contract])), withKey: "practice-breathing")
    }
}
