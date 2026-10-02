# GameCore

An original, offline-first foundation for iPhone and iPad puzzle games. The development title provides a playable lifecycle practice: start, pause, resume, restart, success and failure. Settings and original practice progress are stored locally. Bundled development fixtures cover the four planned game types; complete puzzle rules and titles remain roadmap work. macOS is deferred.

## Build and run

Use macOS with Xcode, an installed iOS Simulator runtime and Python 3.9 or newer. The scripts use Python’s standard library and need no additional packages. Production deployment targets are iOS/iPadOS **18.0**; packages and app targets use Swift 5 language mode. The configured GitHub Actions baseline uses `macos-26`, Xcode 26.6 (`17F113`) and iOS Simulator 26.5, as listed in the [runner inventory](https://raw.githubusercontent.com/actions/runner-images/main/images/macos/macos-26-Readme.md). Local verification uses Xcode 27.0 (`27A266a`), Swift 6.4 and iOS Simulator 26.0; [hosted foundation CI](https://github.com/1cf2ab6aafa31a3209ce70/1cf2ab6aafa31a3209ce70/actions/runs/36933015783) passed on the pinned toolchain and runtime.

Open `GameCore.xcworkspace`, select the `DevelopmentTitle` scheme and an iPhone or iPad simulator, then run. No signing secret, remote dependency or runtime service is required for simulator development.

From the repository root:

```sh
bash scripts/verify.sh
bash scripts/test-mobile.sh
```

`verify.sh` checks generated-project consistency and package/privacy boundaries, runs `GameCore`, `GamePlatform` and title-content tests, validates every bundled fixture, then builds Debug/Release for generic iOS Simulator and unsigned Release for generic iOS. It prints its temporary output directory; optionally pass a new absolute directory as the first argument. The generic iOS build is a compile check, not a device run.

`GamePlatform` declares macOS 10.15 as the minimum for command-line package logic tests. The application remains iOS/iPadOS-only.

`test-mobile.sh` runs app-hosted model tests and UI paths on disposable iPhone 12 and iPad (9th generation) simulator geometries. It selects the newest installed iOS runtime ≥18 unless `GAMECORE_SIM_RUNTIME_VERSION` specifies an exact installed version. It retains logs, runtime inventory, source hashes and `.xcresult` bundles in its printed temporary directory, and removes only the simulators it created. An optional output argument must be a new absolute directory. Pass `--model iphone12` or `--model ipad9` to select one geometry; omitting it runs both. Hosted CI runs the two geometries as independent jobs with separate evidence.

Core tests cover valid and invalid flow transitions, stale preparation results and overlapping pause reasons. Platform tests cover feedback gating and notification lifetime. Mobile tests cover the retained scene, preparation recovery, navigation, durable preferences/progress, recovery and data controls, foreground pause, rotation, large text and Reduce Motion. The runner also verifies a dedicated settings/progress fixture across simulator shutdown and boot.

In the practice, use **Start practice**, **Pause**, **Resume**, **Restart practice**, **Complete practice** or **End practice** to exercise the shell. Backgrounding and audio interruptions pause play until you choose Resume. Settings control sound, music and haptics and persist with practice progress after termination. English is the current supported language. The decorative marker remains still with Reduce Motion, and scrollable menus keep controls reachable at large text sizes. The development title supports a single window on iPad. See [the lifecycle decision](roadmap/decisions/ADR-004-mobile-shell-lifecycle.md) and [content record](Games/DevelopmentTitle/CONTENT.md).

In Settings, **Export local data** opens the native Files exporter. Choose a local destination to keep the copy on the device; an external provider you select may transfer it. App-owned saves are excluded from automatic OS backup, so uninstall or device loss can erase progress. **Reset progress** requires confirmation and keeps preferences; **Delete local data** requires confirmation and clears both. Exported copies remain under your control. If a backup is recovered, review the notice and choose **Use recovered save** before continuing. Unsupported saves are preserved until you explicitly delete them.

Another title uses `GamePlatform.ShellController` and `SharedShellView`, supplying its registration, preparation, scene callbacks, presentation copy and gameplay views. [ShellModel](Games/DevelopmentTitle/ShellModel.swift) and [ShellView](Games/DevelopmentTitle/ShellView.swift) show the practice binding; the [app-hosted fixture](Tests/DevelopmentTitleTests/ShellModelTests.swift) also hosts a separate registration without copying shell code. The final game-module contract remains Spike 06 work.

To regenerate the committed Xcode project and workspace after changing their inputs:

```sh
python3 scripts/generate-project.py
```

The generator uses Python's standard library. CI checks generated files without rewriting them.

## Repository layout

| Path | Responsibility |
| --- | --- |
| `Packages/GameCore` | Renderer-independent core; no platform or title dependency |
| `Packages/GamePlatform` | Shared mobile controller/UI and Apple adapters; depends on local `GameCore` |
| `Games/DevelopmentTitle` | SwiftUI shell and title-owned SpriteKit practice scene |
| `Games/DevelopmentContent` | Original bundled fixtures, title payload validation and the build-time validator |
| `Tests/DevelopmentTitleTests` | App-hosted scene and preparation tests |
| `Tests/DevelopmentTitleUITests` | Mobile navigation, lifecycle, settings and accessibility paths |
| `scripts` | Project generation, structural checks and mobile build/test commands |
| `experiments/platform-baseline` | Disposable SpriteKit/RealityKit investigation and retained evidence |
| `experiments/save-durability` | Disposable Codable filesystem failure/recovery fixtures |
| `roadmap` | Ordered briefs, decisions, audits and validation plans |

Each future title belongs under `Games/<Title>` and owns its rules, rendering, identity and resources. The disposable renderer experiment is separate from production targets.

## Current direction

[ADR-003](roadmap/decisions/ADR-003-simulator-mobile-foundation.md) accepts simulator evidence for mobile development; no physical device is required for this work. Simulator results do not establish device GPU/thermal/battery behavior or physical performance. iOS 18 runtime execution and distribution-readiness checks remain explicit before release; deployment-target compilation is not minimum-runtime execution. [Epic 01](roadmap/epics/01-foundation.md) is complete after local and hosted CI verification. Its [evidence report](roadmap/audits/epic-01-mobile-foundation.md) records the exact checks and clean-copy limits. [Epic 02](roadmap/epics/02-app-shell.md) is complete with the [shell evidence](roadmap/audits/epic-02-app-shell.md). [Spike 03](roadmap/spikes/03-save-durability.md) selects versioned per-title Codable snapshots with previous-good recovery; see [ADR-005](roadmap/decisions/ADR-005-local-save-durability.md) and [fixture evidence](roadmap/audits/spike-03-save-durability.md). [Epic 04](roadmap/epics/04-local-state.md) implements that storage policy; its [evidence report](roadmap/audits/epic-04-local-state.md) records validation and limits. Epic 05 implements [bundled content and reproducible fixtures](docs/bundled-content.md). Its [acceptance evidence](roadmap/audits/epic-05-bundled-content.md) records successful local and hosted checks. Next is the two-developer-day [Spike 06 module comparison](roadmap/spikes/06-module-seam.md), following the [roadmap](ROADMAP.md).

Apps work offline without tracking, telemetry, accounts, ads, purchases or cloud sync. See the [privacy contract](docs/privacy-contract.md), [contribution guide](CONTRIBUTING.md) and [content provenance policy](docs/asset-provenance.md). Project-authored code, documentation and resources use the [MIT license](LICENSE). Third-party material retains its own rights and notices; no candidate repository code or assets are included.
