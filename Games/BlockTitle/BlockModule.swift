import BlockContent
import Combine
import GameCore
import GamePlatform
import SpriteKit
import SwiftUI

/// Blocky Marty, the block title of Epic 09A (rules in ADR-010), registered
/// through module contract version 1. It owns its rules session, SpriteKit
/// board and accessible controls; the shared shell owns everything else.
@MainActor
final class BlockModule: GameModule {
    let title = TitleRegistration(id: "block-match", displayName: "Blocky Marty")
    let loadFailureMessage = "This board could not be loaded. Try again, or return to the menu."
    let session: BlockSession
    let scene: BlockScene

    init(session: BlockSession? = nil) {
        let session = session ?? BlockSession()
        self.session = session
        scene = BlockScene(session: session)
    }

    var presentation: ShellPresentation { Self.presentation }

    func makeGameplay() -> some View {
        BlockBoardView(session: session, scene: scene)
    }

    func makeControls(_ context: ModulePlayContext) -> some View {
        BlockControlsView(session: session, context: context)
    }

    func setReducedMotion(_ enabled: Bool) {
        // Boards redraw without animation; there is no motion to reduce yet.
        session.reducedMotion = enabled
    }

    private static let presentation = ShellPresentation(
        openingMessage: "Opening Blocky Marty",
        menuHeading: "Blocky Marty",
        menuMessage: "Clear each board by selecting groups of two or more touching blocks of one kind. "
            + "Blocks above fall straight down, and columns never move sideways.",
        startLabel: "Play",
        loadingMessage: "Setting up the board",
        pauseMessage: "The board is paused. Resume when you’re ready.",
        audioPauseMessage: "The board paused for an audio interruption. Resume when you’re ready.",
        restartLabel: "Restart board",
        successHeading: "Board cleared",
        successMessage: "Every block is gone.",
        failureHeading: "Board ended",
        failureMessage: "This board was not cleared, so nothing is recorded. Try it again, or return to the menu.",
        retryLabel: "Try again",
        successRetryLabel: "Next board",
        languageName: "English",
        languageMessage: "Blocky Marty currently supports English."
    )
}

/// Title-owned rules state for one board at a time. Preparation chooses the
/// level: the same one again after an unfinished play, otherwise the next from
/// saved progress. Beginning creates a fresh game for it.
@MainActor
final class BlockSession: ObservableObject, ModuleSession {
    @Published var playing = false
    @Published var settings = ShellSettings()
    @Published var reducedMotion = false
    @Published private(set) var game: BlockGame?
    var outcomeHandler: ((ShellOutcome, LoadRequest) -> Void)?
    private(set) var request: LoadRequest?
    private(set) var level: BlockLevel?
    /// The level's place in the catalog, from 1, and the catalog's size.
    private(set) var levelNumber = 0
    private(set) var levelCount = 0
    private(set) var resultSummary: String?
    private var progress = SaveProgress()
    private var preparationEpoch = UUID()
    private var staged: (request: LoadRequest, level: BlockLevel, number: Int, count: Int)?
    private var finished = false
    private let loader: () async throws -> BlockCatalog

    init(loader: @escaping () async throws -> BlockCatalog = { try BundledContent.load() }) {
        self.loader = loader
    }

    func progressDidChange(_ progress: SaveProgress) { self.progress = progress }

    func prepare(for request: LoadRequest) async throws {
        // A cancelled load must not erase a newer one's staged level.
        try Task.checkCancellation()
        let epoch = UUID()
        preparationEpoch = epoch
        staged = nil
        let catalog = try await loader()
        try Task.checkCancellation()
        guard preparationEpoch == epoch, request.titleID == catalog.envelope.titleID else {
            throw ContentValidationError(message: "Superseded preparation or another title's catalog")
        }
        // Restart, Try again and Play after leaving a board replay it; only a
        // cleared board moves on.
        let next: BlockLevel
        if let game, game.outcome != .cleared, let same = catalog.level(id: game.levelID) {
            next = same
        } else {
            next = catalog.nextLevel(after: progress, following: game?.levelID)
        }
        let number = (catalog.levels.firstIndex { $0.id == next.id } ?? 0) + 1
        staged = (request, next, number, catalog.levels.count)
    }

    func begin(for request: LoadRequest) {
        guard let staged, staged.request == request else { return }
        self.staged = nil
        self.request = request
        level = staged.level
        levelNumber = staged.number
        levelCount = staged.count
        game = BlockGame(level: staged.level)
        resultSummary = nil
        finished = false
    }

    /// Touch and the accessible controls both select through here. A stuck
    /// board stays in play, so Undo can take the last move back.
    func select(_ index: Int) {
        guard playing, !finished, var game, let request else { return }
        guard game.select(index) else { return }
        self.game = game
        if game.outcome == .cleared {
            // Only a cleared board's score counts (ADR-010).
            let best = progress.bestScores[game.levelID]
            resultSummary = best.map { game.score > $0 ? "Score: \(game.score), a new best." : "Score: \(game.score). Best: \($0)." }
                ?? "Score: \(game.score)."
            finish(.success, request)
        }
    }

    func undo() {
        guard playing, !finished, var game, game.undo() else { return }
        self.game = game
    }

    func fail() {
        guard playing, !finished, let request else { return }
        finish(.failure, request)
    }

    func recordSuccess(in progress: inout SaveProgress) {
        guard let game, game.outcome == .cleared, let level else { return }
        _ = progress.recordCompletion(levelID: game.levelID, score: game.score, unlocks: level.payload.nextLevelIDs)
    }

    private func finish(_ outcome: ShellOutcome, _ request: LoadRequest) {
        finished = true
        outcomeHandler?(outcome, request)
    }
}

/// The play page's instruction lines (ADR-010): one on each of the first
/// three boards, and the stuck notice.
enum BlockTeaching {
    static let stuck = "No moves left. Undo a move, or end the board."

    static func line(for levelID: String) -> String? {
        switch levelID {
        case "intro-01": return "Select a block in a group of two or more touching blocks of one kind to clear the whole group."
        case "intro-02": return "Blocks above a cleared group fall straight down, so the order you clear groups in matters."
        case "intro-03": return "A block with no matching neighbor stays on the board. Undo takes back your last move."
        default: return nil
        }
    }
}

/// Colors carry a shape too, so no block depends on color perception alone.
enum BlockStyle {
    static func name(_ color: Int) -> String {
        ["Empty", "Coral circle", "Teal square", "Gold triangle", "Violet diamond"][color]
    }
    static func uiColor(_ color: Int) -> UIColor {
        [.clear, .systemRed, .systemTeal, .systemYellow, .systemPurple][color]
    }
    static func symbol(_ color: Int) -> String {
        ["", "circle.fill", "square.fill", "triangle.fill", "diamond.fill"][color]
    }
    static func outline(_ color: Int) -> String {
        ["", "circle", "square", "triangle", "diamond"][color]
    }
}

struct BlockBoardView: View {
    @ObservedObject var session: BlockSession
    let scene: BlockScene

    var body: some View {
        // The board keeps its grid's shape, with cells up to 56 points, so an
        // 8 × 8 board's cells stay as large as the width allows.
        let board = session.game?.board
        let columns = CGFloat(board?.columns ?? 1), rows = CGFloat(board?.rows ?? 1)
        SpriteView(scene: scene)
            .aspectRatio(columns / rows, contentMode: .fit)
            .frame(maxWidth: columns * 56 + 24)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Block board")
            .accessibilityValue("\(remaining) blocks left")
            .accessibilityHint("Use the block buttons below to select with VoiceOver")
            .accessibilityIdentifier("block.board")
            .onAppear { scene.synchronize() }
            .onChange(of: session.game) { _, _ in scene.synchronize() }
            .onChange(of: session.playing) { _, _ in scene.synchronize() }
    }

    private var remaining: Int { session.game?.board.cells.filter { $0 != 0 }.count ?? 0 }
}

/// Accessible play controls. Each block is a button that makes the same
/// selection as touching it on the board.
struct BlockControlsView: View {
    @ObservedObject var session: BlockSession
    let context: ModulePlayContext
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Three buttons a row broke labels into one letter per line at
    /// accessibility text sizes; those sizes get one full-width button a row.
    private var perRow: Int { typeSize.isAccessibilitySize ? 1 : 3 }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ShellHeading("Clear the board", id: "shell.play")
            if let game = session.game {
                Text("Board \(session.levelNumber) of \(session.levelCount)")
                    .accessibilityIdentifier("block.level")
                if let line = BlockTeaching.line(for: game.levelID) {
                    Text(line).accessibilityIdentifier("block.teaching")
                }
                Text("Blocks left: \(game.board.cells.filter { $0 != 0 }.count)")
                    .accessibilityIdentifier("block.remaining")
                Text("Score: \(game.score)")
                    .accessibilityIdentifier("block.score")
                if game.outcome == .stuck {
                    Text(BlockTeaching.stuck).accessibilityIdentifier("block.stuck")
                }
                // Undo sits above the blocks, so a VoiceOver or keyboard
                // player reaches it without passing every block. It appears
                // once there is a move to take back: a dimmed button fails
                // the contrast audit, and the block grid reflows after every
                // move anyway.
                if game.canUndo {
                    ShellActionButton("Undo", id: "block.undo", prominent: game.outcome == .stuck, action: session.undo)
                        .disabled(!session.playing)
                }
                // A plain grid, not a lazy one: every block keeps an accessible
                // control even while it is scrolled out of view.
                let blocks = game.board.cells.indices.filter { game.board.cells[$0] != 0 }
                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(Array(stride(from: 0, to: blocks.count, by: perRow)), id: \.self) { start in
                        GridRow {
                            ForEach(blocks[start..<min(start + perRow, blocks.count)], id: \.self) { index in
                                blockButton(index, board: game.board)
                            }
                        }
                    }
                }
            }
            ShellActionButton("Pause", id: "shell.pause", action: context.pause)
            ShellActionButton("End board", id: "shell.fail", action: session.fail)
        }
        .onChange(of: session.game?.outcome == .stuck) { _, stuck in
            if stuck { UIAccessibility.post(notification: .announcement, argument: BlockTeaching.stuck) }
        }
    }

    private func blockButton(_ index: Int, board: BlockBoard) -> some View {
        let color = board.cells[index]
        let row = index / board.columns + 1, column = index % board.columns + 1
        // Text stays in the label color, and a label-colored outline carries
        // the shape: coral, teal and gold alone fail contrast on the bordered
        // button background, so the fill only repeats the board's color.
        return Button { session.select(index) } label: {
            Label {
                Text("Row \(row), column \(column)").foregroundStyle(Color.primary)
            } icon: {
                ZStack {
                    Image(systemName: BlockStyle.symbol(color)).foregroundStyle(Color(uiColor: BlockStyle.uiColor(color)))
                    Image(systemName: BlockStyle.outline(color)).foregroundStyle(Color.primary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .disabled(!session.playing)
        .accessibilityLabel("Row \(row), column \(column), \(BlockStyle.name(color))")
        .accessibilityHint(board.group(at: index).count >= 2 ? "Clears its group" : "No matching neighbor")
        .accessibilityIdentifier("block.cell.\(index)")
    }
}

/// Draws the session's board and converts one touch into a selection. It holds
/// no rule state; frames never advance the game.
@MainActor
final class BlockScene: SKScene {
    private weak var session: BlockSession?
    private var boardRect = CGRect.zero
    private var columns = 0
    private var rows = 0

    init(session: BlockSession) {
        self.session = session
        super.init(size: CGSize(width: 320, height: 240))
        scaleMode = .resizeFill
        backgroundColor = .secondarySystemGroupedBackground
    }

    required init?(coder: NSCoder) { fatalError("BlockScene is constructed by BlockModule") }

    override func didChangeSize(_ oldSize: CGSize) { synchronize() }

    func synchronize() {
        removeAllChildren()
        guard let board = session?.game?.board else {
            columns = 0; rows = 0; boardRect = .zero
            return
        }
        columns = board.columns
        rows = board.rows
        let cell = min(max(0, size.width - 24) / CGFloat(columns), max(0, size.height - 24) / CGFloat(rows))
        guard cell > 0 else { boardRect = .zero; return }
        boardRect = CGRect(x: (size.width - cell * CGFloat(columns)) / 2, y: (size.height - cell * CGFloat(rows)) / 2,
                           width: cell * CGFloat(columns), height: cell * CGFloat(rows))
        for index in board.cells.indices where board.cells[index] != 0 {
            let color = board.cells[index]
            let center = CGPoint(x: boardRect.minX + (CGFloat(index % columns) + 0.5) * cell,
                                 y: boardRect.maxY - (CGFloat(index / columns) + 0.5) * cell)
            let block = SKShapeNode(rectOf: CGSize(width: cell - 6, height: cell - 6), cornerRadius: cell * 0.18)
            block.position = center
            block.fillColor = BlockStyle.uiColor(color)
            block.strokeColor = .clear
            block.alpha = session?.playing == true ? 1 : 0.6
            block.addChild(Self.mark(color, size: cell * 0.36))
            addChild(block)
        }
    }

    /// A white shape inside each block repeats its color as a form.
    private static func mark(_ color: Int, size: CGFloat) -> SKShapeNode {
        let half = size / 2
        let mark: SKShapeNode
        switch color {
        case 1: mark = SKShapeNode(circleOfRadius: half)
        case 2: mark = SKShapeNode(rectOf: CGSize(width: size, height: size))
        case 3:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: half)); path.addLine(to: CGPoint(x: half, y: -half))
            path.addLine(to: CGPoint(x: -half, y: -half)); path.closeSubpath()
            mark = SKShapeNode(path: path)
        default:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: half)); path.addLine(to: CGPoint(x: half, y: 0))
            path.addLine(to: CGPoint(x: 0, y: -half)); path.addLine(to: CGPoint(x: -half, y: 0)); path.closeSubpath()
            mark = SKShapeNode(path: path)
        }
        mark.fillColor = .white
        mark.strokeColor = .clear
        mark.alpha = 0.9
        return mark
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard touches.count == 1, let point = touches.first?.location(in: self), let session, session.playing,
              columns > 0, rows > 0, boardRect.contains(point) else { return }
        let column = min(columns - 1, Int((point.x - boardRect.minX) / (boardRect.width / CGFloat(columns))))
        let row = min(rows - 1, Int((boardRect.maxY - point.y) / (boardRect.height / CGFloat(rows))))
        session.select(row * columns + column)
    }
}
