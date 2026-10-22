import Combine
import GameCore
import GamePlatform
import SpriteKit
import SwiftUI
import TileContent

/// Few Tiles, the tile title of Epic 09B (rules in ADR-011), registered
/// through module contract version 1. It owns its rules session, SpriteKit
/// board, tray and accessible controls; the shared shell owns everything else.
@MainActor
final class TileTitleModule: GameModule {
    let title = TitleRegistration(id: "tile-match", displayName: "Few Tiles")
    let loadFailureMessage = "This board could not be loaded. Try again, or return to the menu."
    let session: TileTitleSession
    let scene: TileScene

    init(session: TileTitleSession? = nil) {
        let session = session ?? TileTitleSession()
        self.session = session
        scene = TileScene(session: session)
    }

    var presentation: ShellPresentation { Self.presentation }

    func makeGameplay() -> some View {
        TileBoardView(session: session, scene: scene)
    }

    func makeControls(_ context: ModulePlayContext) -> some View {
        TileControlsView(session: session, context: context)
    }

    func setReducedMotion(_ enabled: Bool) {
        // Boards redraw without animation; there is no motion to reduce yet.
        session.reducedMotion = enabled
    }

    private static let presentation = ShellPresentation(
        openingMessage: "Opening Few Tiles",
        menuHeading: "Few Tiles",
        menuMessage: "Clear each board by taking free tiles into the tray. Three alike in the tray clear away, "
            + "and a tray of seven with no three alike stops play.",
        startLabel: "Play",
        loadingMessage: "Setting up the board",
        pauseMessage: "The board is paused. Resume when you’re ready.",
        audioPauseMessage: "The board paused for an audio interruption. Resume when you’re ready.",
        restartLabel: "Restart board",
        successHeading: "Board cleared",
        successMessage: "Every tile is gone.",
        failureHeading: "Board ended",
        failureMessage: "This board was not cleared, so nothing is recorded. Try it again, or return to the menu.",
        retryLabel: "Try again",
        successRetryLabel: "Next board",
        languageName: "English",
        languageMessage: "Few Tiles currently supports English."
    )
}

/// Title-owned rules state for one board at a time. Preparation chooses the
/// level: the same one again after an unfinished play, otherwise the next from
/// saved progress. Beginning creates a fresh game for it.
@MainActor
final class TileTitleSession: ObservableObject, ModuleSession {
    @Published var playing = false
    @Published var settings = ShellSettings()
    @Published var reducedMotion = false
    @Published private(set) var game: TileGame?
    var outcomeHandler: ((ShellOutcome, LoadRequest) -> Void)?
    private(set) var request: LoadRequest?
    private(set) var level: TileLevel?
    /// The level's place in the catalog, from 1, and the catalog's size.
    private(set) var levelNumber = 0
    private(set) var levelCount = 0
    private(set) var resultSummary: String?
    private var progress = SaveProgress()
    private var preparationEpoch = UUID()
    private var staged: (request: LoadRequest, level: TileLevel, number: Int, count: Int)?
    private var finished = false
    private let loader: () async throws -> TileCatalog

    init(loader: @escaping () async throws -> TileCatalog = { try BundledContent.load() }) {
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
        let next: TileLevel
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
        game = TileGame(level: staged.level)
        resultSummary = nil
        finished = false
    }

    /// Touch and the accessible controls both select through here. A full
    /// tray stays in play, so Undo can take the last move back.
    func select(_ index: Int) {
        guard playing, !finished, var game, let request else { return }
        guard game.select(index) else { return }
        self.game = game
        if game.outcome == .cleared {
            // Only a cleared board's score counts (ADR-011).
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

/// The play page's instruction lines (ADR-011): one on each of the first
/// three boards, and the full-tray notice.
enum TileTeaching {
    static let trayFull = "The tray is full. Undo a move, or end the board."

    static func line(for levelID: String) -> String? {
        switch levelID {
        case "intro-01": return "Select a tile to move it to the tray. Three alike in the tray clear away."
        case "intro-02": return "A tile under another can’t be taken until every tile on it is gone."
        case "intro-03": return "Seven tiles with no three alike fill the tray. Undo takes back your last move."
        default: return nil
        }
    }

    /// A tile's place in whole cells. A tile on an odd layer straddles two
    /// rows and two columns, and says so.
    static func position(of tile: TileBoard.Tile) -> String {
        func span(_ half: Int) -> String { half % 2 == 0 ? "\(half / 2 + 1)" : "\(half / 2 + 1) to \(half / 2 + 2)" }
        return "row \(span(tile.y)), column \(span(tile.x))"
    }

    /// The tray in words, for VoiceOver and the play page.
    static func tray(_ game: TileGame) -> String {
        let free = TileGame.traySlots - game.tray.count
        let slots = free == 0 ? "no slots free" : (free == 1 ? "1 slot free" : "\(free) slots free")
        guard !game.tray.isEmpty else { return "empty, \(slots)" }
        var groups: [(kind: Int, count: Int)] = []
        for index in game.tray {
            let kind = game.board.tiles[index].kind
            if groups.last?.kind == kind { groups[groups.count - 1].count += 1 } else { groups.append((kind, 1)) }
        }
        let names = groups.map { $0.count == 1 ? TileStyle.name($0.kind) : "\($0.count) \(TileStyle.name($0.kind))" }
        return names.joined(separator: ", ") + "; " + slots
    }
}

/// Each kind carries its own symbol and name, so no tile depends on color
/// perception alone.
enum TileStyle {
    static func name(_ kind: Int) -> String {
        ["Empty", "Leaf", "Drop", "Sun", "Moon", "Star", "Heart"][kind]
    }
    static func uiColor(_ kind: Int) -> UIColor {
        [.clear, .systemGreen, .systemBlue, .systemOrange, .systemIndigo, .systemYellow, .systemPink][kind]
    }
    static func symbol(_ kind: Int) -> String {
        ["", "leaf.fill", "drop.fill", "sun.max.fill", "moon.fill", "star.fill", "heart.fill"][kind]
    }
    static func outline(_ kind: Int) -> String {
        ["", "leaf", "drop", "sun.max", "moon", "star", "heart"][kind]
    }
}

struct TileBoardView: View {
    @ObservedObject var session: TileTitleSession
    let scene: TileScene

    var body: some View {
        // The board keeps its shape, with tiles up to 56 points, so a board
        // six tiles across stays as large as the width allows.
        let board = session.game?.board
        let width = CGFloat(board?.width ?? 2), height = CGFloat(board?.height ?? 2)
        VStack(spacing: 12) {
            SpriteView(scene: scene)
                .aspectRatio(width / height, contentMode: .fit)
                .frame(maxWidth: width * 28 + 24)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Tile board")
                .accessibilityValue("\(board?.remaining ?? 0) tiles left, \(board?.free.count ?? 0) free")
                .accessibilityHint("Use the tile buttons below to select with VoiceOver")
                .accessibilityIdentifier("tile.board")
            if let game = session.game { TileTrayView(game: game) }
        }
        .onAppear { scene.synchronize() }
        .onChange(of: session.game) { _, _ in scene.synchronize() }
        .onChange(of: session.playing) { _, _ in scene.synchronize() }
    }
}

/// The seven tray slots, drawn with the same symbols as the board.
struct TileTrayView: View {
    let game: TileGame

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<TileGame.traySlots, id: \.self) { slot in
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.secondarySystemGroupedBackground))
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.secondary, lineWidth: 1)
                    if slot < game.tray.count {
                        let kind = game.board.tiles[game.tray[slot]].kind
                        Image(systemName: TileStyle.symbol(kind))
                            .resizable().scaledToFit().padding(8)
                            .foregroundStyle(Color(uiColor: TileStyle.uiColor(kind)))
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 48)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tray")
        .accessibilityValue(TileTeaching.tray(game))
        .accessibilityIdentifier("tile.tray")
    }
}

/// Accessible play controls. Each free tile is a button that makes the same
/// selection as touching it on the board.
struct TileControlsView: View {
    @ObservedObject var session: TileTitleSession
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
                    .accessibilityIdentifier("tile.level")
                if let line = TileTeaching.line(for: game.levelID) {
                    Text(line).accessibilityIdentifier("tile.teaching")
                }
                Text("Tiles left: \(game.board.remaining)")
                    .accessibilityIdentifier("tile.remaining")
                Text("Score: \(game.score)")
                    .accessibilityIdentifier("tile.score")
                // The tray in words sits next to the tile buttons, so a
                // VoiceOver or keyboard player hears it after every move.
                Text("Tray: \(TileTeaching.tray(game))")
                    .accessibilityIdentifier("tile.tray.summary")
                if game.outcome == .trayFull {
                    Text(TileTeaching.trayFull).accessibilityIdentifier("tile.full")
                }
                // Undo sits above the tiles and appears once there is a move
                // to take back: a dimmed button fails the contrast audit.
                if game.canUndo {
                    ShellActionButton("Undo", id: "tile.undo", prominent: game.outcome == .trayFull, action: session.undo)
                        .disabled(!session.playing)
                }
                // A plain grid, not a lazy one: every free tile keeps an
                // accessible control even while it is scrolled out of view.
                // Covered tiles are not controls; the board draws them dimmed.
                let free = game.outcome == .playing ? game.board.free : []
                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(Array(stride(from: 0, to: free.count, by: perRow)), id: \.self) { start in
                        GridRow {
                            ForEach(free[start..<min(start + perRow, free.count)], id: \.self) { index in
                                tileButton(index, game: game)
                            }
                        }
                    }
                }
            }
            ShellActionButton("Pause", id: "shell.pause", action: context.pause)
            ShellActionButton("End board", id: "shell.fail", action: session.fail)
        }
        .onChange(of: session.game?.outcome == .trayFull) { _, full in
            if full { UIAccessibility.post(notification: .announcement, argument: TileTeaching.trayFull) }
        }
    }

    private func tileButton(_ index: Int, game: TileGame) -> some View {
        let tile = game.board.tiles[index]
        let position = TileTeaching.position(of: tile)
        let name = TileStyle.name(tile.kind)
        let waiting = game.tray.filter { game.board.tiles[$0].kind == tile.kind }.count
        let freed = game.board.uncovers(index).map { TileStyle.name(game.board.tiles[$0].kind) }
        let hint = [waiting == 2 ? "Clears three \(name)" : "Moves to the tray",
                    freed.isEmpty ? nil : "Frees " + Self.list(freed)].compactMap { $0 }.joined(separator: ". ")
        // Text stays in the label color, and a label-colored outline carries
        // the symbol: several kind colors alone fail contrast on the bordered
        // button background, so the fill only repeats the board's color.
        return Button { session.select(index) } label: {
            Label {
                Text(position.prefix(1).uppercased() + position.dropFirst()).foregroundStyle(Color.primary)
            } icon: {
                ZStack {
                    Image(systemName: TileStyle.symbol(tile.kind)).foregroundStyle(Color(uiColor: TileStyle.uiColor(tile.kind)))
                    Image(systemName: TileStyle.outline(tile.kind)).foregroundStyle(Color.primary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .disabled(!session.playing)
        .accessibilityLabel("\(name), \(position), layer \(tile.layer + 1)")
        .accessibilityHint(hint)
        .accessibilityIdentifier("tile.cell.\(index)")
    }

    private static func list(_ names: [String]) -> String {
        names.count < 2 ? names.joined() : names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
    }
}

/// Draws the session's board and converts one touch into a selection. It holds
/// no rule state; frames never advance the game.
@MainActor
final class TileScene: SKScene {
    private weak var session: TileTitleSession?
    private var origin = CGPoint.zero
    private var half: CGFloat = 0
    private var symbols: [String: SKTexture] = [:]

    init(session: TileTitleSession) {
        self.session = session
        super.init(size: CGSize(width: 320, height: 240))
        scaleMode = .resizeFill
        // A grey table, so the tiles' faces in the background color stand out.
        backgroundColor = .systemGray5
    }

    required init?(coder: NSCoder) { fatalError("TileScene is constructed by TileTitleModule") }

    override func didChangeSize(_ oldSize: CGSize) { synchronize() }

    func synchronize() {
        removeAllChildren()
        guard let board = session?.game?.board else { half = 0; return }
        half = min(max(0, size.width - 24) / CGFloat(board.width), max(0, size.height - 24) / CGFloat(board.height))
        guard half > 0 else { return }
        origin = CGPoint(x: (size.width - half * CGFloat(board.width)) / 2,
                         y: (size.height + half * CGFloat(board.height)) / 2)
        let playing = session?.playing == true
        for index in board.tiles.indices where board.present[index] {
            let tile = board.tiles[index]
            let side = half * 2 - 4
            let node = SKShapeNode(rectOf: CGSize(width: side, height: side), cornerRadius: half * 0.3)
            node.position = center(of: tile)
            node.zPosition = CGFloat(tile.layer) * 2
            node.fillColor = .systemBackground
            node.strokeColor = .separator
            node.lineWidth = 1.5
            let shadow = SKShapeNode(rectOf: CGSize(width: side, height: side), cornerRadius: half * 0.3)
            shadow.position = CGPoint(x: 2, y: -3)
            shadow.zPosition = -1
            shadow.fillColor = UIColor.black.withAlphaComponent(0.25)
            shadow.strokeColor = .clear
            node.addChild(shadow)
            let mark = SKSpriteNode(texture: texture(for: tile.kind, side: side * 0.6))
            mark.size = CGSize(width: side * 0.6, height: side * 0.6)
            mark.zPosition = 1
            node.addChild(mark)
            // Covered tiles stay visible, dimmed, so a player can plan ahead.
            let free = board.isFree(index)
            node.alpha = !playing ? 0.6 : (free ? 1 : 0.45)
            addChild(node)
        }
    }

    private func center(of tile: TileBoard.Tile) -> CGPoint {
        CGPoint(x: origin.x + CGFloat(tile.x + 1) * half, y: origin.y - CGFloat(tile.y + 1) * half)
    }

    /// A kind's symbol drawn once per size; SpriteKit has no symbol node.
    private func texture(for kind: Int, side: CGFloat) -> SKTexture {
        let key = "\(kind)-\(Int(side))"
        if let cached = symbols[key] { return cached }
        let configuration = UIImage.SymbolConfiguration(pointSize: side, weight: .semibold)
        let image = UIImage(systemName: TileStyle.symbol(kind), withConfiguration: configuration)?
            .withTintColor(TileStyle.uiColor(kind), renderingMode: .alwaysOriginal) ?? UIImage()
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            let scale = min(side / max(image.size.width, 1), side / max(image.size.height, 1))
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2, width: size.width, height: size.height))
        }
        let texture = SKTexture(image: rendered)
        symbols[key] = texture
        return texture
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard touches.count == 1, let point = touches.first?.location(in: self), let session, session.playing,
              let board = session.game?.board, half > 0 else { return }
        // The topmost drawn tile under the touch; a covered tile ignores it.
        // Tiles on one layer never share a point, and the gap between them
        // selects nothing.
        let reach = half - 2
        let hit = board.tiles.indices.filter { index in
            guard board.present[index] else { return false }
            let center = center(of: board.tiles[index])
            return abs(point.x - center.x) < reach && abs(point.y - center.y) < reach
        }.max { board.tiles[$0].layer < board.tiles[$1].layer }
        if let hit { session.select(hit) }
    }
}
