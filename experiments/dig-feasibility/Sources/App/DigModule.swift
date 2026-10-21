import GameCore
import GamePlatform
import SwiftUI
import UIKit

/// The terrain title's registration through contract version 1. Everything terrain-specific
/// (rules, fields, renderers, physics, hit testing, controls) stays in this target.
@MainActor
final class DigModule: GameModule {
    let title = TitleRegistration(id: "development-practice", displayName: "Dig study")
    let session: DigSession

    init(options: DigOptions) {
        session = DigSession(options: options)
    }

    var presentation: ShellPresentation { .dig }

    func makeGameplay() -> DigGameplayView {
        DigGameplayView(session: session)
    }

    func makeControls(_ context: ModulePlayContext) -> DigControlsView {
        DigControlsView(session: session, context: context)
    }

    func setReducedMotion(_ enabled: Bool) {
        session.engine.setReducedMotion(enabled)
    }
}

extension ShellPresentation {
    static let dig = ShellPresentation(
        openingMessage: "Opening dig study", menuHeading: "Dig feasibility study",
        menuMessage: "Drag across the ground to dig and uncover buried items. Cursor controls dig without dragging.",
        startLabel: "Start digging", loadingMessage: "Loading dig site", pauseMessage: "Resume to keep digging.",
        audioPauseMessage: "Audio interrupted. Resume when ready.", restartLabel: "Restart dig",
        successHeading: "Every item found", successMessage: "The dig was recorded locally.",
        failureHeading: "Dig ended", failureMessage: "No completion was recorded.", retryLabel: "Dig again",
        languageName: "English", languageMessage: "Experiment supports English.")
}

@MainActor
struct DigGameplayView: View {
    @ObservedObject var session: DigSession

    var body: some View {
        let status = session.status
        VStack(alignment: .leading, spacing: 6) {
            DigSurface(engine: session.engine)
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Dig site, \(session.options.candidate.rawValue) view")
                .accessibilityValue("Score \(status.score) of \(status.total)")
                .accessibilityHint("Drag to dig. The cursor controls below dig without dragging.")
                .accessibilityIdentifier("dig.surface")
            Text("Score \(status.score) of \(status.total)")
                .font(.headline)
                .accessibilityIdentifier("dig.score")
            Text("rev=\(status.revision) tick=\(status.tick) accepted=\(status.accepted)")
                .font(.caption.monospaced())
                .accessibilityIdentifier("dig.status")
            #if DEBUG
            Text("Run: \(session.run.state)")
                .font(.caption.monospaced())
                .accessibilityLabel(session.run.state)
                .accessibilityIdentifier("dig.run.state")
            Text("Run summary")
                .font(.caption2)
                .accessibilityValue(session.run.summary)
                .accessibilityIdentifier("dig.run.summary")
            #endif
        }
    }
}

@MainActor
struct DigControlsView: View {
    @ObservedObject var session: DigSession
    let context: ModulePlayContext

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ShellHeading("Dig running", id: "shell.play")
            #if DEBUG
            HStack(spacing: 8) {
                ShellActionButton("Run trace", id: "dig.run.timing") { session.driver.start(.timing) }
                ShellActionButton("Run cycle", id: "dig.run.prefix") { session.driver.start(.prefix) }
                ShellActionButton("Fast trace", id: "dig.run.fast") { session.driver.start(.fast) }
            }
            #endif
            Text(String(format: "Cursor x %.2f, z %.2f", session.status.cursor.x, session.status.cursor.y))
                .accessibilityIdentifier("dig.cursor")
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    Color.clear.frame(height: 1)
                    move("North", "north", dx: 0, dz: -1)
                    Color.clear.frame(height: 1)
                }
                GridRow {
                    move("West", "west", dx: -1, dz: 0)
                    ShellActionButton("Dig", id: "dig.dig", prominent: true) { session.submit(.digAtCursor, phase: "control") }
                        .accessibilityLabel("Dig at cursor")
                    move("East", "east", dx: 1, dz: 0)
                }
                GridRow {
                    Color.clear.frame(height: 1)
                    move("South", "south", dx: 0, dz: 1)
                    Color.clear.frame(height: 1)
                }
            }
            ShellActionButton("Reload scene", id: "dig.reload") { session.reloadScene() }
            ShellActionButton("Pause", id: "shell.pause", action: context.pause)
            ShellActionButton("End session", id: "shell.fail", action: session.fail)
        }
    }

    private func move(_ title: String, _ id: String, dx: Int, dz: Int) -> some View {
        ShellActionButton(title, id: "dig.cursor.\(id)") { session.submit(.moveCursor(dx: dx, dz: dz), phase: "control") }
            .accessibilityLabel("Move cursor \(title.lowercased())")
    }
}

/// Hosts the module-retained renderer view; the engine keeps its scene across shell views.
@MainActor
private struct DigSurface: UIViewRepresentable {
    let engine: any DigEngine

    func makeUIView(context: Context) -> UIView { engine.view }
    func updateUIView(_ view: UIView, context: Context) {}
}
