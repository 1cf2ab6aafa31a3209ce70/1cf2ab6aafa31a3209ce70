# GameCore

An original, offline-first foundation for iPhone and iPad puzzle games. The current app is an empty development title that imports two local Swift packages; gameplay and a playable app shell are later roadmap work. macOS is deferred.

## Build and run

Use macOS with Xcode, an installed iOS Simulator runtime and Python 3.9 or newer. The scripts use Python’s standard library and need no additional packages. Production deployment targets are iOS/iPadOS **18.0**; packages and app targets use Swift 5 language mode. The configured GitHub Actions baseline uses `macos-26`, Xcode 26.6 (`17F113`) and iOS Simulator 26.5, as listed in the [runner inventory](https://raw.githubusercontent.com/actions/runner-images/main/images/macos/macos-26-Readme.md). Local verification uses Xcode 27.0 (`27A266a`), Swift 6.4 and iOS Simulator 26.0; the configured remote workflow has not yet been executed.

Open `GameCore.xcworkspace`, select the `DevelopmentTitle` scheme and an iPhone or iPad simulator, then run. No signing secret, remote dependency or runtime service is required for simulator development.

From the repository root:

```sh
bash scripts/verify.sh
bash scripts/test-mobile.sh
```

`verify.sh` checks generated-project consistency and package/privacy boundaries, compiles the empty core's test target and platform package, then builds Debug/Release for generic iOS Simulator and unsigned Release for generic iOS. It prints its temporary output directory; optionally pass a new absolute directory as the first argument. The generic iOS build is a compile check, not a device run.

`test-mobile.sh` builds and launches the development title on disposable iPhone 12 and iPad (9th generation) simulator geometries. It selects the newest installed iOS runtime ≥18 unless `GAMECORE_SIM_RUNTIME_VERSION` specifies an exact installed version. It retains logs, runtime inventory and `.xcresult` bundles in its printed temporary directory, and removes only the simulators it created. An optional output argument must be a new absolute directory.

The core intentionally has no domain API or runtime test cases yet. Structural checks verify its independent dependency boundary; add executable pure-logic tests with the first domain behavior. The app smoke test covers launch, layout and lifecycle, rather than gameplay.

To regenerate the committed Xcode project and workspace after changing their inputs:

```sh
python3 scripts/generate-project.py
```

The generator uses Python's standard library. CI checks generated files without rewriting them.

## Repository layout

| Path | Responsibility |
| --- | --- |
| `Packages/GameCore` | Renderer-independent core; no platform or title dependency |
| `Packages/GamePlatform` | Apple platform adapters; depends on local `GameCore` |
| `Games/DevelopmentTitle` | Thin empty mobile SwiftUI app importing both packages |
| `Tests/DevelopmentTitleUITests` | Mobile foundation smoke test |
| `scripts` | Project generation, structural checks and mobile build/test commands |
| `experiments/platform-baseline` | Disposable SpriteKit/RealityKit investigation and retained evidence |
| `roadmap` | Ordered briefs, decisions, audits and validation plans |

Each future title belongs under `Games/<Title>` and owns its rules, rendering, identity and resources. The disposable renderer experiment is separate from production targets.

## Current direction

[ADR-003](roadmap/decisions/ADR-003-simulator-mobile-foundation.md) accepts simulator evidence for the mobile foundation; no physical device is required for this work. Simulator results do not establish device GPU/thermal/battery behavior or physical performance. iOS 18 runtime execution and distribution-readiness checks remain explicit before release; deployment-target compilation is not minimum-runtime execution. [Epic 01](roadmap/epics/01-foundation.md) implementation and local build/UI checks are complete; hosted CI acceptance remains pending. The [evidence report](roadmap/audits/epic-01-mobile-foundation.md) records the exact checks and clean-copy limits. Epic 02 has not begun; later work follows the [roadmap](ROADMAP.md).

Apps work offline without tracking, telemetry, accounts, ads, purchases or cloud sync. See the [privacy contract](docs/privacy-contract.md), [contribution guide](CONTRIBUTING.md) and [content provenance policy](docs/asset-provenance.md). Project-authored code, documentation and resources use the [MIT license](LICENSE). Third-party material retains its own rights and notices; no candidate repository code or assets are included.
