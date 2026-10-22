# Adding a title

A title is an app target that registers one module with the shared shell. It owns its rules, levels, renderer, controls, icon and copy; the shared packages own menus, lifecycle pauses, settings, feedback and local saves. Titles never share a save namespace, bundle identifier or content catalog, and adding, changing or removing one never edits another.

## Create a skeleton

From the repository root:

```sh
python3 scripts/new-title.py UnscrewTitle --title-id unscrew --display-name "Unscrew" --game-type unscrew
bash scripts/verify.sh
bash scripts/test-mobile.sh --title UnscrewTitle
```

The script copies [scripts/title-template](../scripts/title-template), renders a placeholder app icon and regenerates the Xcode project. It creates:

| Path | Contents |
| --- | --- |
| `Games/UnscrewTitle/title.json` | The manifest: target, stable title ID, home-screen name, bundle identifier, content package and test directories |
| `Games/UnscrewTitle/UnscrewTitleApp.swift` | The composition root: `TitleStorage`, `ShellFeedbackController` and `ModuleHost` |
| `Games/UnscrewTitle/UnscrewTitleModule.swift` | The module, its session, its gameplay view and its play controls |
| `Games/UnscrewTitle/Assets.xcassets` | The app icon, one opaque 1024-pixel PNG |
| `Games/UnscrewTitle/Localizable.xcstrings` | The title's String Catalog, English source |
| `Games/UnscrewTitle/PrivacyInfo.xcprivacy` | The reviewed privacy manifest: no tracking, collected data or required-reason APIs. `verify.sh` checks it against the Release build |
| `Games/UnscrewTitle/Info.plist`, `CONTENT.md` | Single-window scene configuration; the content record to keep current |
| `Games/UnscrewContent` | The content package: catalog, levels, payload validation, `UnscrewContentValidator` and package tests |
| `Tests/UnscrewTitleTests`, `Tests/UnscrewTitleUITests` | App-hosted tests through the real host and save store, and a native UI test |

The skeleton's session completes a level after a configured number of selections. It builds, validates and passes its tests before any gameplay exists; replace its rules, renderer, controls and levels with the title's own.

Nothing else needs editing. The generator, `scripts/check-foundation.py`, `scripts/verify.sh`, `scripts/test-mobile.sh` and CI read titles from the manifests. CI tests a title on both simulator geometries when its own paths or a shared path change. To remove a title, delete its four directories and run `python3 scripts/generate-project.py`. `scripts/test-title-lifecycle.py` proves both operations on disposable copies.

## What a title can rely on

These are the module contract, [version 1](../roadmap/decisions/ADR-007-module-contract-v1.md), which Spike 11 confirmed for a terrain title without change ([ADR-008](../roadmap/decisions/ADR-008-dig-terrain-feasibility.md)). A title uses only these shared APIs:

- **`GameModule`** supplies `title` (a `TitleRegistration` whose ID is the save namespace and the catalog's `titleID`), `presentation` (`ShellPresentation` copy), `loadFailureMessage`, the retained `session`, `makeGameplay()`, `makeControls(_:)` and `setReducedMotion(_:)`.
- **`ModuleSession`** receives `playing`, `settings` and `progressDidChange(_:)`. It decodes a level in `prepare(for:)`, creates fresh rule state in `begin(for:)`, reports each result through `outcomeHandler` with the request it belongs to, ends a session in `fail()`, and records completions in `recordSuccess(in:)` by stable level ID.
- **`ModulePlayContext`** lends play controls the reduced-motion state and the shell's pause action. `ShellHeading` and `ShellActionButton` give controls the shell's look and accessibility identifiers; play controls use `shell.play`, `shell.pause` and `shell.fail`.
- **`ModuleHost`**, **`ModuleShellView`** and **`TitleStorage`** assemble the app, as the template's app file shows.
- **`GameCore`** supplies `CatalogEnvelope`, `LevelEnvelope`, `SaveProgress`, `InputFixture`, `GameTickClock` and `DeterministicRNG` for title-owned rules and fixtures.

The shell guarantees that `playing` is true only while input is accepted; that backgrounding, audio interruptions and Pause stop input until the player resumes; that outcomes for any request but the current one are ignored; that settings and progress arrive once and then only on change; and that a thrown preparation error shows the load-failure message with Try again and the menu. Everything else in `GamePlatform`, including `ShellController`, is shell implementation. A title must not drive the controller directly.

A session checks cancellation before changing staged state, as the template does, so a superseded load never erases a newer one. Rules advance only on input, never on frames or wall-clock time, and the renderer only draws session state.

## Evolving content

A title's content package owns its payload schema and validation. Follow the [bundled content guide](bundled-content.md): stable level IDs identify achievements across releases, catalog order is presentation only, and the content version is independent of the save schema. The validator runs in every build and in `scripts/verify.sh`, so an invalid level fails before packaging. Record new material in `CONTENT.md` under the [provenance policy](asset-provenance.md).

## Evolving the contract

`contractVersion` is a source-integration version, separate from content and save versions; the host accepts version 1 and refuses any other before preparation. Change the contract only for a need that a real title demonstrates. A change every title can adopt without behavior change, such as an optional callback with a default, stays version 1; record it in ADR-007. Any other change introduces version 2: a named adapter that translates version 2 to version 1 with tests, or a separately versioned host that titles opt into. Never reinterpret an existing version.

Localization: SwiftUI text literals in a title's own views resolve through its `Localizable.xcstrings`. `ShellPresentation` copy is plain strings and is not localized yet; titles currently support English.
