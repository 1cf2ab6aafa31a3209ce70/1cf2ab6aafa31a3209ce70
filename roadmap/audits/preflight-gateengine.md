# GateEngine reuse audit

**Reviewed:** 2026-09-30. **Decision:** decline for the starting foundation; no GateEngine code, assets, or dependencies enter gamecore. **Applies to:** Spike 00. **Owner:** gamecore platform/rendering maintainer (role, not an assigned individual). **Reversal cost now:** low, because nothing is integrated; a later adoption would require a new dependency/asset review and comparative prototypes. Reversal after adoption would be high because the engine owns windowing, lifecycle, rendering, input, resources, and entity/component systems.

## Revision and scope

[GateEngine revision `8ac4b58b5465c165f408b240b92c67a1948797da`](https://github.com/STREGAsGate/GateEngine/tree/8ac4b58b5465c165f408b240b92c67a1948797da), commit date 2026-03-02, “Add nodes accessor”, was cloned into `/private/tmp/gamecore-reuse-audit/GateEngine`. The shallow checkout pins source content; it does not establish full contributor/release history. This review covers the Apple default package configuration and its resolved packages, with non-Apple branches noted separately. No upstream demo artwork was used.

The [manifest](https://github.com/STREGAsGate/GateEngine/blob/8ac4b58b5465c165f408b240b92c67a1948797da/Package.swift) requires Swift tools 6.2, uses Swift 5 language mode, and declares macOS 14, iOS 17, and tvOS 17. These are upstream requirements, not gamecore's chosen minimums. GameMath, GateUtilities, Shaders, ECS macros, image/font decoders, scripting, and FBX import are dependencies of the main engine target. Default traits are empty; `DISTRIBUTE` enables SIMD and distribution-oriented behavior. SwiftSyntax's lower version bound changes with the compiler, reaching 604.0.0 on Swift 6.4. There is no upstream `Package.resolved` in the inspected checkout, so its revision alone does not freeze the remote dependency graph.

## Build evidence

Host: macOS 27.0 build 26A428, arm64. `xcodebuild -version` returned Xcode 27.0, build 27A266a. `swift --version` returned Apple Swift 6.4 (`swiftlang-6.4.0.34.1`, clang `2100.3.34.1`), target `arm64-apple-macosx27.0.0`.

Commands, run from the disposable checkout unless stated:

```sh
git clone --depth 1 https://github.com/STREGAsGate/GateEngine.git /private/tmp/gamecore-reuse-audit/GateEngine
git rev-parse HEAD
swift package resolve
swift build --target GateEngine --configuration debug
```

For a future reproduction, fetch the full recorded commit and run `git checkout --detach 8ac4b58b5465c165f408b240b92c67a1948797da` before building; checking out today's default branch is not equivalent. Preserve/recreate the three exact remote pins in the inventory rather than accepting a new resolution. The original audit used the just-cloned HEAD, confirmed with `git rev-parse HEAD`; detached checkout is a reproduction instruction, not a command claimed as executed.

The first resolve attempt exited 1 because sandboxed SwiftPM could not write `/Users/d/.cache/clang/ModuleCache`; the diagnostic included `Operation not permitted` and `unable to load standard library`. That was an environment restriction, not an upstream compilation failure. The inspected manifest, macro sources, and build configuration contained no enabled custom shell build plugin. An approved unsandboxed `swift build` resolved the three packages listed below and **succeeded, exit 0**, ending:

```text
[725 / 725] GateEngine
Build complete! (55.04 secs.)
```

The displayed progress separator above is normalized from SwiftPM's narrow-space formatting. Relevant compiler warnings were:

```text
Dependencies/LibSPNG/src/spng.c:1212:13: warning: inflateValidate() not available, SPNG_CTX_IGNORE_ADLER32 will be ignored
Sources/GameMath/3D Types/3D Physics/3D Colliders/Triangles/CollisionTriangle.swift:204:22: warning: This is broken
Sources/GameMath/3D Types/3D Physics/3D Colliders/OrientedBoundingBox3D.swift:359:18: warning: This might be wrong
Sources/GameMath/3D Types/3D Physics/3D Colliders/BoundingEllipsoid3D.swift:73:9: warning: code after 'return' will never be executed
```

These are warnings, not measured failures of the proposed terrain mechanic. They nevertheless require targeted collision tests before using those paths. The source of the collision warning is [CollisionTriangle.swift](https://github.com/STREGAsGate/GateEngine/blob/8ac4b58b5465c165f408b240b92c67a1948797da/Sources/GameMath/3D%20Types/3D%20Physics/3D%20Colliders/Triangles/CollisionTriangle.swift#L204).

A separate, original minimal macOS executable was created at `/private/tmp/gamecore-reuse-audit/GateEngineSmoke`, with this manifest and source (retained here to reproduce after temporary files disappear):

```swift
// Package.swift
// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "GateEngineSmoke", platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../GateEngine")],
    targets: [.executableTarget(name: "Smoke", dependencies: [
        .product(name: "GateEngine", package: "GateEngine")])])
```

```swift
// Sources/Smoke/Smoke.swift
import GateEngine
@main
final class Smoke: GameDelegate {
    init() {}
    func didFinishLaunching(game: Game, options: LaunchOptions) async {}
    func createMainWindow(using manager: WindowManager, with identifier: String) throws -> Window {
        try manager.createWindow(identifier: identifier,
            rootViewController: ViewController(title: "Audit smoke"))
    }
    nonisolated func gameIdentifier() -> StaticString? { "local.gamecore.audit" }
}
```

Its lockfile was copied from the resolved engine checkout; source remained unmodified. Build command:

```sh
swift build --package-path /private/tmp/gamecore-reuse-audit/GateEngineSmoke --scratch-path /private/tmp/gamecore-reuse-audit/GateEngine/.build --product Smoke --configuration debug
```

**Minimal executable result:** succeeded, exit 0, `Build complete! (6.51 secs.)`. This only compiles and links an empty-window host against the engine; it is not a board/terrain visual prototype or an observed window launch.

No executable was launched, no runtime traffic captured, and no iOS, release, hardware frame-pacing, memory, terrain, or accessibility measurements were taken. Library and executable compilation are separate from those acceptance checks. Logs were kept in `/private/tmp/gamecore-reuse-audit/gateengine-{resolve,build,smoke}.log`; the useful durable excerpts and commands are above.

## License, resources, and dependency inventory

The root [LICENSE](https://github.com/STREGAsGate/GateEngine/blob/8ac4b58b5465c165f408b240b92c67a1948797da/LICENSE) is Apache-2.0. Redistribution needs its license and applicable notices, retained copyright/attribution, and notices on modified files; it does not grant use of the author's trademarks. The [NOTICE](https://github.com/STREGAsGate/GateEngine/blob/8ac4b58b5465c165f408b240b92c67a1948797da/NOTICE) collects several third-party licenses. Some engine files have an “All Rights Reserved” copyright header; the repository-wide Apache license is the declared code license, not evidence that each bundled third-party asset has been separately cleared.

The following is an **observed candidate inventory**, not an approved production bill of materials. No third-party inclusion is proposed. The remote pins came from the actual successful resolution. Their manifests contain no further external package requirements in this default Apple graph; internal package modules are not additional repositories.

| Component | Exact revision/version observed | Apple role | License/notice disposition |
| --- | --- | --- | --- |
| GateEngine, GameMath, GateUtilities, Shaders, ECSMacros, Apple/OpenGL adapters | Engine revision above | Runtime plus build-time macro | Apache-2.0; retain root license and applicable NOTICE entries; mark changes |
| swift-atomics | 1.3.1, `0442cb5a3f98ab802acb777929fdb446bda11a34` | Runtime Atomics and its internal shim | [Apache-2.0 with Swift runtime exception](https://github.com/apple/swift-atomics/blob/0442cb5a3f98ab802acb777929fdb446bda11a34/LICENSE.txt); retain license for redistributed source and assess distributed form |
| swift-collections | 1.7.1, `98ef3c98609a1e31b7e157b5b619579001a789d6` | Runtime Collections umbrella and internal collection modules | [Apache-2.0 with Swift runtime exception](https://github.com/apple/swift-collections/blob/98ef3c98609a1e31b7e157b5b619579001a789d6/LICENSE.txt); same disposition |
| swift-syntax | 604.0.0, `050f1a346fbbac0ca2cfb15a95274f7bd1cf0ccf` | Build-time macro compiler support and internal syntax/parser modules | [Apache-2.0 with Swift runtime exception](https://github.com/apple/swift-syntax/blob/050f1a346fbbac0ca2cfb15a95274f7bd1cf0ccf/LICENSE.txt); distinguish build tool redistribution from runtime |
| LibSPNG | Vendored at engine revision; header 0.7.3 | PNG decoding; depends on miniz | BSD-2-Clause; preserve copyright, terms and disclaimer in source and binary documentation |
| miniz | Vendored at engine revision; `MZ_VERSION` 11.0.2 | Compression for LibSPNG | MIT; retain copyright and permission notice |
| TrueType / stb_truetype + stb_rect_pack | Vendored at engine revision; headers v1.26 and v1.01 | Font rasterization/atlas packing | Embedded dual MIT/public-domain texts; elect MIT and retain notices if adopting; not separately enumerated in root NOTICE |
| Gravity | Vendored at engine revision; header 0.8.5 | Scripting VM/compiler including optional file/environment helpers | MIT; retain copyright and permission notice |
| uFBX | Vendored at engine revision; header 0.5.0 | FBX importer | MIT alternative supplied in NOTICE (also public-domain alternative in its own LICENSE); retain MIT notice |
| SDL_GameControllerDB | Bundled snapshot at engine revision, file says SDL 2.0.16 format; no separate upstream commit pinned | Controller mappings, copied resource | zlib-style notice in root NOTICE; preserve notice, identify changes and do not misrepresent origin |
| Fonts, primitives, textures, logos | Bundled at engine revision | Copied by the main target | **Not cleared:** see asset findings below |

Vendored source evidence: [Dependencies](https://github.com/STREGAsGate/GateEngine/tree/8ac4b58b5465c165f408b240b92c67a1948797da/Dependencies). Header version strings identify embedded versions, not proof of untouched upstream tarballs; their reproducible identity is the engine Git revision.

Non-Apple/disabled inventory: HTML5 conditionally adds WebAPIKit (from 0.1.0) and JavaScriptKit (from 0.16.0), and changes Atomics to exactly 1.1.0. Those packages and their transitive graph were not resolved or cleared. Windows adapters include Direct3D12/XAudio2 and system libraries. Linux/Android declarations include Linux support/OpenGL and OpenALSoft; OpenALSoft is not linked by the Apple target, and its GateEngine dependency entry is commented. Vorbis dependency/target entries are commented out. Root NOTICE contains Vorbis and OpenAL Soft terms, including an LGPL text, but that does **not** make the observed Apple build an OpenAL/LGPL build. New platforms would require a new complete graph and license review.

The target unconditionally copies [its resource directory](https://github.com/STREGAsGate/GateEngine/tree/8ac4b58b5465c165f408b240b92c67a1948797da/Sources/GateEngine/Resources/_PackageResources/GateEngine): four Tuffy fonts, Micro/Babel bitmap fonts, controller database, OBJ primitives, checker texture, and GateEngine logo variants. [Font.swift](https://github.com/STREGAsGate/GateEngine/blob/8ac4b58b5465c165f408b240b92c67a1948797da/Sources/GateEngine/Resources/Text/Font.swift#L149) makes Tuffy the default. No separate font/art provenance or license files were found beside those resources or in root NOTICE. This is an unresolved redistribution review, not a claim that the fonts are necessarily unlicensed. A future adopter must establish their rights and notices or remove/replace the resources and associated defaults; simply avoiding a font call does not prevent the package resource copy. Gamecore must retain its own title identity and must not reuse the engine branding or demo screenshots as title artwork.

## Runtime data flows and capabilities

This section reports static tracing, not a runtime privacy certification.

- On Apple platforms, resource loaders resolve package/app/file paths, then call the file-system adapter. `Data(contentsOf:)` receives a `URL(fileURLWithPath:)`, not a remote URL: [AsynchronousFileSystem](https://github.com/STREGAsGate/GateEngine/blob/8ac4b58b5465c165f408b240b92c67a1948797da/Sources/GateEngine/System/Platforms/FileSystem/AsynchronousFileSystem.swift#L73). The synchronous adapter uses the same local-file construction.
- Saves use Application Support beneath `Game.info.identifier`; cache and temporary paths use the same identifier: [AppleFileSystem](https://github.com/STREGAsGate/GateEngine/blob/8ac4b58b5465c165f408b240b92c67a1948797da/Sources/GateEngine/System/Platforms/Platform%20Implementations/Apple/AppleFileSystem.swift). A stable distinct identifier would be necessary for each title. AppKit/UIKit persist window title/screen/fullscreen metadata in UserDefaults; these are local engine settings, not gameplay analytics.
- UIKit creates an NSUserActivity for scene/window activation. No explicit iCloud, sign-in, Game Center, ads, purchases, attribution, analytics, crash SDK, push, or tracking-permission implementation was found in the inspected Apple code/manifests. GameController input is not Game Center. No engine `PrivacyInfo.xcprivacy` was present. A future app would still need an actual privacy-manifest/required-reason API audit, including UserDefaults, and verification of entitlements and the built artifact.
- The [WASI resource implementation](https://github.com/STREGAsGate/GateEngine/blob/8ac4b58b5465c165f408b240b92c67a1948797da/Sources/GateEngine/System/Platforms/Platform%20Implementations/WASI/WASIPlatform.swift#L74) uses browser `fetch`, including HEAD requests. That is embedded platform behavior, not an optional title feature, but it is outside the Apple configuration reviewed here. Enabling HTML5 would not meet the roadmap's no-app-network rule without a separate design and review.
- The engine exposes resource search paths, filesystem writes, and Gravity file/environment helpers. These expand the maintenance and input-safety surface even without an observed native network client. Its debug logs include local resource errors; no remote log sink was found. Permission/capability searches found no native camera, microphone, location, push, or tracking request implementation in the reviewed sources. A standalone package cannot prove the entitlements of a future host app; the unrelated Extras syntax-highlighting utility is not an engine app target.

Searches covered `URLSession`, `CFNetwork`, `NWConnection`, `import Network`, socket/network APIs, `GameKit`, `CloudKit`, `StoreKit`, tracking/analytics/crash SDK names, UserDefaults, notification/location/camera APIs, and the concrete loader/save call sites. Public-repository and SwiftPM network access during this audit was development-time package fetching, not evidence of an app network request.

## Maintenance and decision

The last checked-out commit is about seven months before this review. The [macOS workflow](https://github.com/STREGAsGate/GateEngine/blob/8ac4b58b5465c165f408b240b92c67a1948797da/.github/workflows/macOS.yml) schedules daily builds/tests and uses Xcode 26.1; corresponding iOS/tvOS workflows and multiple math/engine/script test targets exist. Their presence does not establish the latest CI run passed. Current CI outcomes, maintainer responsiveness, and full release cadence were not verified. The successful local Xcode 27 build is stronger evidence for this host than a README badge, but leaves runtime correctness and mobile support untested.

Decline is based on a mismatch in scope and maintenance cost, not inability to compile or an observed Apple telemetry violation. The default engine brings a compiler macro dependency, broad rendering/platform infrastructure, parsers and scripting, copied resources needing additional provenance work, and collision paths already marked uncertain. There is no measured board/terrain benefit that justifies replacing the roadmap's first-party default.

**Spike 00 disposition:** GateEngine is not retained for the conditional board/terrain comparison. Spike 00 proceeds with SwiftUI/SpriteKit and RealityKit. No comparative performance conclusion is claimed. If those prototypes reveal a concrete gap that GateEngine might address, the platform/rendering maintainer can reopen this decision: first close resource/license gaps and lock the graph, then implement identical board and terrain interactions on the selected oldest devices; record package/build and shipped-size cost, frame pacing, memory, collision correctness, lifecycle/input fit, and offline runtime checks. Until then, there is no GateEngine adoption work or unresolved blocker to the first-party foundation.
