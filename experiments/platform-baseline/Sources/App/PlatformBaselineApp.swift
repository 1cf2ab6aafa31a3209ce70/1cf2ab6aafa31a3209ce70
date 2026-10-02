import SwiftUI
import SpriteKit

@main
struct PlatformBaselineApp: App {
    var body: some Scene {
        WindowGroup {
            #if os(macOS)
            BaselineView()
                .frame(minWidth: 320, minHeight: 520)
            #else
            BaselineView()
            #endif
        }
    }
}

@MainActor
private final class ProbeSession: ObservableObject {
    let metrics = ProbeMetrics()
    let blocks = BoardScene(mode: .blocks)
    let panel = BoardScene(mode: .panel)

    init() {
        for scene in [blocks, panel] {
            scene.scaleMode = .resizeFill
            scene.onFrame = { [weak self] in self?.metrics.recordFrame($0) }
            scene.onAction = { [weak self] in self?.metrics.recordAction($0) }
            scene.onResize = { [weak self] in self?.metrics.recordLayout($0) }
        }
    }

    func setPaused(_ paused: Bool, mode: ProbeMode) {
        let active: BoardScene? = mode == .blocks ? blocks : mode == .panel ? panel : nil
        for scene in [blocks, panel] {
            let shouldPause = paused || scene !== active
            scene.isPaused = shouldPause
            scene.view?.isPaused = shouldPause
        }
    }
}

private enum ProbeMode: String, CaseIterable {
    case blocks = "Blocks"
    case panel = "Panel"
    case terrain = "Terrain"
}

private struct BaselineView: View {
    @StateObject private var session = ProbeSession()
    @Environment(\.scenePhase) private var scenePhase
    @State private var mode = ProbeMode.blocks
    @State private var paused = false
    @FocusState private var rendererFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            content(compact: geometry.size.height < 500)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            rendererFocused = true
            session.setPaused(paused || scenePhase != .active, mode: mode)
        }
        .onChange(of: scenePhase) { _, phase in
            session.setPaused(paused || phase != .active, mode: mode)
            session.metrics.reset()
            session.metrics.recordAction("Lifecycle: \(String(describing: phase))")
        }
    }

    private func content(compact: Bool) -> some View {
        VStack(spacing: compact ? 6 : 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Platform baseline").font(.title2.bold())
                    if !compact {
                        Text("SPIKE 00 · ORIGINAL FIRST-PARTY PROTOTYPES")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(paused ? "Resume" : "Pause") {
                    paused.toggle()
                    session.setPaused(paused || scenePhase != .active, mode: mode)
                    session.metrics.reset()
                    session.metrics.recordAction(paused ? "Paused" : "Resumed")
                    if !paused { rendererFocused = true }
                }
                .accessibilityIdentifier("probe.pause")
            }
            HStack {
                ForEach(ProbeMode.allCases, id: \.self) { item in
                    Button(item.rawValue) {
                        mode = item
                        session.setPaused(paused || scenePhase != .active, mode: item)
                        session.metrics.reset()
                        session.metrics.recordAction("Selected \(item.rawValue)")
                        rendererFocused = true
                    }
                    .buttonStyle(.bordered)
                    .tint(mode == item ? .cyan : .gray)
                    .accessibilityIdentifier("mode.\(item.rawValue.lowercased())")
                }
                Spacer()
            }
            let layout = compact
                ? AnyLayout(HStackLayout(alignment: .top, spacing: 12))
                : AnyLayout(VStackLayout(spacing: 12))
            layout {
                renderer
                MetricsView(metrics: session.metrics).frame(width: compact ? 220 : nil)
            }
        }
        .padding(compact ? 8 : 16)
        .background(Color(red: 0.035, green: 0.055, blue: 0.09))
    }

    private var renderer: some View {
        Group {
                if mode == .terrain {
                    TerrainProbeView(isPaused: paused || scenePhase != .active,
                                     onMeasurement: session.metrics.recordTerrainMeasurement,
                                     onFrame: session.metrics.recordFrame)
                        .allowsHitTesting(!paused && scenePhase == .active)
                } else {
                    SpriteView(scene: mode == .blocks ? session.blocks : session.panel,
                               isPaused: paused || scenePhase != .active,
                               preferredFramesPerSecond: 60)
                        .id(mode)
                        .accessibilityLabel("\(mode.rawValue) interaction surface")
                        .accessibilityIdentifier("probe.renderer")
                        .allowsHitTesting(!paused && scenePhase == .active)
                        .focusable()
                        .focused($rendererFocused)
                        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .space, .return]) { press in
                            guard !paused && scenePhase == .active else { return .ignored }
                            let key: String
                            switch press.key {
                            case .leftArrow: key = "left"
                            case .rightArrow: key = "right"
                            case .upArrow: key = "up"
                            case .downArrow: key = "down"
                            case .space: key = "space"
                            default: key = "return"
                            }
                            (mode == .blocks ? session.blocks : session.panel).handleKey(key)
                            return .handled
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct MetricsView: View {
    @ObservedObject var metrics: ProbeMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(metrics.summary).accessibilityIdentifier("metrics.summary")
            Text(metrics.lastAction).accessibilityIdentifier("metrics.action")
            Text(metrics.terrainSummary).accessibilityIdentifier("metrics.terrain")
            Text(metrics.layoutSummary).lineLimit(1).accessibilityIdentifier("metrics.layout")
        }
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}
