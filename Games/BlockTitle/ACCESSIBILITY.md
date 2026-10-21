# Accessibility record: Block Match reference slice

This record applies the [accessibility checklist](../../docs/accessibility-checklist.md) to Block Match, the Epic 08 reference title. It lists each result, every fix and every tracked action. The automated checks are in [BlockAccessibilityUITests](../../Tests/BlockTitleUITests/BlockAccessibilityUITests.swift), [BlockTitleUITests](../../Tests/BlockTitleUITests/BlockTitleUITests.swift) and [BlockModuleTests](../../Tests/BlockTitleTests/BlockModuleTests.swift).

## Environment

Recorded 2026-10-20 on the Epic 08 working tree based on `b0276d8`, uncommitted. Host Mac14,6 (Apple M2 Max), macOS 27.2, Xcode 27.1 (`27A9275`), iOS Simulator 26.0 (`23A5287g`) on owned simulators with iPhone 12 and iPad (9th generation) geometry, Debug build, portrait. Every result here is a simulator observation. Hosted CI later passed these tests on iOS 26.5 and on the iOS 18.0 minimum runtime on both geometries, after the iOS 18.0 settings findings below ([evidence](../../roadmap/audits/epic-08-release-baseline.md#hosted-ci)).

The final run of all 6 app-hosted and 7 UI tests (`BlockTitleTests`, `BlockTitleUITests`) passed on both geometries on the first attempt, with no XCTest retry. Apart from the settings sheet, the audits reported nothing on any page at either text size on either geometry, so no repeat-filtered or excused finding hides a Block Match page result. The runs used `xcodebuild test-without-building` with the same retry and time-allowance flags as `scripts/test-mobile.sh`, on simulators named for this work, rather than `scripts/test-mobile.sh` itself.

## Results

| Checklist item | How it was checked | Result |
| --- | --- | --- |
| 1. Labels and traits | Audits on menu, settings, play, pause, success and failure at default size and AX3; `testBlockButtonsDescribeEveryBlockAndClearTheBoardWithoutTheBoard` asserts the board's label and value and every block button's label | Pass on Block Match's pages; settings findings tracked as S-2 and S-3 |
| 2. Focus order | The same test compares the play page's element positions; manual step with Accessibility Inspector | Automated proxy passes; manual step: not run (needs an interactive Accessibility Inspector session) |
| 3. Large text | Audits with `--shell-large-text` (AX3, without `.dynamicType`); the default-size audit with the simulator's text size set to AX3 and AX5 | Pass after fix F-2. The DEBUG override does not reach the settings sheet (S-1); the system AX3 and AX5 sizes are checked manually below |
| 4. Color-independent cues | `testEveryBlockColorHasADistinctShapeAndName`; result headings asserted by text; contrast audit | Pass after fix F-1 |
| 5. Reduced motion | `testReducedMotionReachesTheSessionAndTheBoardRunsNoActions`; `testReducedMotionKeepsPlayPauseAndResultsReachable` | Pass. The board has no animation: it redraws in one step, so there is no motion to reduce |
| 6. Audio and haptics | Settings audit; Block Match plays no sound or haptic of its own, only the shell's success, failure and selection cues | Pass; device output is in the hardware check |
| 7. Alternate input | `testBlockButtonsDescribeEveryBlockAndClearTheBoardWithoutTheBoard` clears a board with the buttons only; `hitRegion` audit; touch and buttons share `BlockSession.select(_:)` | Pass |

## Fixes

- **F-1 Block button text failed contrast.** The block buttons drew their whole label, text included, in the block's color: coral, teal or gold text on the grey bordered button. The audit failed every block button on the play page at both sizes. The text now uses the primary label color. With colored symbols alone, the iPad geometry still failed the buttons, because a teal or gold shape on grey is too faint to carry its shape, so each symbol now has a primary-colored outline and the fill only repeats the board's color. Owner: `Games/BlockTitle/BlockModule.swift`.
- **F-2 Block buttons broke into one letter per line at accessibility sizes.** Three buttons a row left each label about 80 points, so at AX3 "Row 2, column 1" wrapped one letter per line and each button grew to almost 600 points tall. No audit reported it as clipped; the contrast audit and the attached screenshot showed it. At accessibility sizes the grid now has one full-width button a row. Owner: `Games/BlockTitle/BlockModule.swift`.
- **F-3 Block Match had no DEBUG presentation overrides.** The title now reads `--shell-large-text` and `--shell-reduced-motion` like the practice title, so its UI tests can run at AX3 and with reduced motion. Owner: `Games/BlockTitle/BlockTitleApp.swift`.

## Tracked actions

Block Match has no open title-owned action. The settings sheet belongs to the shared shell, `SharedShellSettingsView` in `Packages/GamePlatform/Sources/GamePlatform/SharedShellView.swift`, so its findings are shell actions for the `GamePlatform` owners. The audit test excuses each one on the settings page only, naming the entry below.

| ID | Finding | Change needed in GamePlatform | Status |
| --- | --- | --- | --- |
| S-1 | The DEBUG `--shell-large-text` override, which each title applies to its root view, does not reach the settings sheet. UIKit presents the sheet with the process's own text size, so UI tests see settings at the default size. Production is unaffected: the system text size reaches the sheet. | In `SharedShellView`, read `@Environment(\.dynamicTypeSize) private var dynamicTypeSize` and present `SharedShellSettingsView(controller: controller, presentation: presentation).dynamicTypeSize(dynamicTypeSize)` inside `.sheet`. Then remove the large-text skip in `BlockAccessibilityUITests.auditEveryPage`. | Open; large-text settings checked manually meanwhile |
| S-2 | Contrast below 4.5:1 at body size (the audit's "nearly passed") on the section headers Feedback, Language and Local data; the language message and storage note, drawn with `.foregroundStyle(.secondary)`; the Language value; Export local data in the accent tint; Reset progress and Delete local data in system red. On iOS 18.0 only, Done in the accent tint on the sheet's bar. | Drop `.foregroundStyle(.secondary)` from the language message and storage note. Give each `Section` an explicit header, `Text("Feedback").foregroundStyle(.primary)`. Draw the three local-data buttons as `Label` with primary-colored text and a colored symbol (`square.and.arrow.up`, `arrow.counterclockwise`, `trash`), keeping `role: .destructive` for Reset and Delete. Give Done a tint that meets 4.5:1 on the bar on iOS 18. | Open |
| S-3 | The default-size audit reports Done, the three local-data buttons and the export explanation as not scaling with Dynamic Type, and Delete local data as clipped. | Probably none: the AX3 screen recording shows Done, the three buttons and the explanation growing with the text size, so these look like audit false positives. Confirm once S-1 lets the large-text audit reach the sheet; if a report remains, give the affected rows a scalable text style | Open; confirm after S-1 |
| S-4 | On the iPad (9th generation) geometry the settings sheet carries one `elementDetection` report ("potentially inaccessible text") that the audit cannot resolve to an element. | Inspect the sheet with Accessibility Inspector, find the text element without an accessibility representation, and expose it or hide it as decoration. | Open |

## Manual steps

| Step | Result |
| --- | --- |
| System text size AX5 (`xcrun simctl ui <device> content_size accessibility-extra-extra-extra-large`), default-size audit test, iPad (9th generation) geometry | Every page traversed. Before the repeat rule existed, the first audit after one scroll on the play page reported contrast failures on plain black text (save status, heading, counts, first block button), the settling pattern the rule now discards. Not re-run with the rule |
| Same, iPhone 12 geometry | Menu and settings traversed with only the excused settings findings. The play page could not be traversed: the audit varies the text size while it runs, the long page reflows and the scroll position is lost. The screen recording shows the AX5 play page with one full-width button a row and no clipped text |
| System text size AX3, settings sheet, iPhone 12 | The recording shows the section text, buttons and export explanation growing with the text size; see S-3 |
| Dark appearance (`xcrun simctl ui <device> appearance dark`), both audit tests, both geometries | Pass on both geometries at both sizes, settings excuses aside. On iPhone 12 the first audit after the first scroll of the play page reported contrast on the block buttons and Pause and one unmatched text element; the repeat audit a second later did not, so the rule discarded them |
| Focus after page changes with Accessibility Inspector; Full Keyboard Access; Grayscale filter | Not run: they need an interactive simulator session. Run them before the title ships |
| VoiceOver speech, Voice Control and haptic output | Not run: the simulator has none of them. They belong to the [hardware check](../../docs/hardware-check.md), which ADR-009 records as not run |
