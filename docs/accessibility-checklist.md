# Accessibility checklist

Every title passes this checklist on the iPhone 12 and iPad (9th generation) simulator geometries before its release candidate is accepted, and records the result in its own accessibility record, such as [Blocky Marty's](../Games/BlockTitle/ACCESSIBILITY.md). The [release checklist](release-checklist.md) links here.

Each item says how it is checked:

- **Test:** an app-hosted or UI test in the title's test targets. It runs in `scripts/test-mobile.sh` and in CI.
- **Audit:** a UI test that calls `XCUIApplication.performAccessibilityAudit` on the page. The system audit checks contrast, element detection, hit regions, element descriptions, Dynamic Type, clipped text and traits. A title's audit test runs it on the menu, settings, play, pause and both result pages, from the top of each page and again after each scroll until the page's last control is in view, once at the default text size and once with `--shell-large-text`. Two kinds of report are not counted, because the audit samples whatever is drawn at the element's position: an element partly outside the window or cut off by the edge of the page's scroll view (an iPad sheet ends above the window's bottom), and a contrast report for content that a scroll has moved under the status or navigation bar. The first pass audits that band unscrolled. A failure counts only if a second audit a second later, at the same position, repeats it, because a page still settling after a scroll or a size change can fail once. Every report, counted or not, is kept in the test's `audit-log-*.txt` attachment. A seeded-violation test launches the title with `--ui-test-seed-accessibility-violation`, which adds an unlabeled 20-point control in DEBUG builds, and fails unless the same audit, filters and excuses report it.
- **Manual:** a step a person performs. The iOS Simulator does not run VoiceOver, so its manual steps use Accessibility Inspector on the simulator, and spoken output waits for the [hardware check](hardware-check.md). The simulator also has no Color Filters setting, so the Grayscale step runs in the hardware check too.

For Full Keyboard Access on the simulator, connect the Mac keyboard (I/O > Keyboard > Connect Hardware Keyboard); XCUITest's `typeKey` does not reach Full Keyboard Access. Tab moves between groups, Control-Tab moves item by item, the arrow keys move within a list, Space activates and Escape closes a sheet or dialog. Focus shows as a highlight on the control. [Blocky Marty's record](../Games/BlockTitle/ACCESSIBILITY.md#interactive-steps) describes how its steps were scripted without a person.

The DEBUG launch arguments `--shell-large-text` (accessibility size AX3) and `--shell-reduced-motion` override presentation traits for UI tests without changing the production flow. They pin the text size, so the large-text audit leaves out the `.dynamicType` check, which needs to change the size itself; the default-size audit includes it. The shell passes the overridden size on to its settings sheet, so the large-text audit covers settings too. Copy the reference title's audit test, [BlockAccessibilityUITests](../Tests/BlockTitleUITests/BlockAccessibilityUITests.swift), when adding one for a new title.

## Checklist

### 1. VoiceOver labels and traits

| Item | Check | Pass |
| --- | --- | --- |
| Every control has a label that names its action or object, and no control is announced only by an image or identifier. | Audit (`sufficientElementDescription`, `elementDetection`) | No finding without a tracked action |
| Game pieces are named by position and kind, not by color alone, for example "Row 2, column 1, Coral circle". | Test asserts the labels of a known board | Labels match the board |
| The renderer is either one element with a label and a value that states what is left, or hidden when it only decorates. Its hint points to the accessible controls. | Test reads the renderer's label and value before and after a move | The value follows the game state |
| Page headings carry the header trait; buttons carry the button trait; disabled controls report it. | Audit (`trait`); Manual: Accessibility Inspector's rotor lists one heading per page | No finding; headings listed |

### 2. Focus order

| Item | Check | Pass |
| --- | --- | --- |
| The play page reads top to bottom: title, renderer, save status, page heading, counts, pieces in row order, then Pause and the end action. | Test compares element positions as a proxy for reading order; Manual: step through the page with Accessibility Inspector's navigation | Order as listed |
| After each page change (start, pause, resume, result, back to menu), focus lands on the new page, not on a removed element. | Manual: Accessibility Inspector on both geometries; VoiceOver in the hardware check | Focus is on the new page's content |

### 3. Large text

| Item | Check | Pass |
| --- | --- | --- |
| Menu, settings, play, pause and result pages keep every control reachable and unclipped at an accessibility text size. | Audit with `--shell-large-text` (`textClipped`, `hitRegion`, `contrast`); Test plays a board at that size | No finding without a tracked action; every control reachable by scrolling |
| Text follows the system text size. | Audit at default size (`dynamicType`) | No finding without a tracked action |
| The system text size at AX3 and AX5 leaves every page usable, settings included. | Manual: on an owned simulator, `xcrun simctl ui <device> content_size accessibility-extra-large` (then `accessibility-extra-extra-extra-large`), run the default-size audit test against it, and read its screenshots and findings | Same findings as at the default size; nothing clipped or overlapping; every control reachable |

### 4. Color-independent cues

| Item | Check | Pass |
| --- | --- | --- |
| Every piece kind has its own shape and name, so color is never the only difference. | Test checks that each kind has a distinct shape and name | Distinct |
| Outcomes and state are stated in text, not only by color, sound or haptics. | Test waits for the result headings and counts by text | Present |
| Text and controls meet contrast against their background, in light and dark appearance. | Audit (`contrast`); Manual: open each page in dark appearance (`xcrun simctl ui <device> appearance dark`) and convert each page's screenshot to grayscale (`sips -m "/System/Library/ColorSync/Profiles/Generic Gray Gamma 2.2 Profile.icc"`); hardware check: Settings > Accessibility > Display & Text Size > Color Filters > Grayscale | No finding without a tracked action; every piece distinguishable in grayscale |

### 5. Reduced motion

| Item | Check | Pass |
| --- | --- | --- |
| The reduced-motion trait reaches the title's session through `setReducedMotion(_:)` and `ModulePlayContext.reducesMotion`. | Test drives the shell's reduced-motion setting and reads the session | Session follows the trait |
| With reduced motion, the title runs no decorative movement, scaling or parallax; a state change is shown in one step or a cross-fade. | Test checks the renderer runs no actions with the trait on (and, for a title with no animation, none at all) | No action, or only cross-fades |
| Play, pause and results stay reachable with reduced motion. | UI test with `--shell-reduced-motion` | Passes |

### 6. Audio and haptic controls

| Item | Check | Pass |
| --- | --- | --- |
| Settings offers Sound effects, Music and Haptics, each reachable and labelled. | Audit of the settings page; the practice title's UI tests change and persist them | No finding without a tracked action |
| Title cues go through the shell's feedback controller, so the three settings, interruptions and route changes govern them. A title plays no sound or haptic of its own. | Package tests for `ShellFeedbackController`; code review of the title | Title has no other audio or haptic output |
| Nothing is conveyed by sound or haptics alone. | Review against item 4's text cues | Every cue has a text equivalent |
| Output follows the toggles on a device. | Manual, hardware check: the simulator has no haptics | Recorded by the hardware check |

### 7. Alternate input path

| Item | Check | Pass |
| --- | --- | --- |
| Every gameplay action can be made with standard buttons of at least 44 points, with no drag, precise position, multi-finger gesture or timing. | UI test completes a board using only the buttons, without touching the renderer; Audit (`hitRegion`) | Board completes |
| Touch on the renderer and the buttons make the same move through the same session call. | Test of the session; the touch and button UI tests reach the same state | Same result |
| Pieces removed from play lose their controls; pieces still in play keep them, even when scrolled out of view. | UI test | As stated |
| Full Keyboard Access and Voice Control reach every control. | Manual: with a hardware keyboard on the simulator and Full Keyboard Access on, Tab to each control and activate it; Voice Control in the hardware check | Board completes from the keyboard |

## Running the checks

```sh
bash scripts/test-mobile.sh <new absolute dir> --title <Target>
```

This runs the title's tests on both geometries. The audit tests attach a screenshot and an `audit-findings-*.txt` report for each text size to the result bundle, listing every finding with its page, audit type and element, including excused ones. On a UI failure, follow [CONTRIBUTING](../CONTRIBUTING.md#ui-test-failures): read the simulator log for the N06, N09 and N10 signatures before changing app code. An audit failure whose element is `-` (the audit cannot resolve it) may come from a system banner drawn over the app rather than from the app: on 2026-10-20 a fresh iPad (9th generation) simulator showed "Ready for Apple Intelligence" over the Block Match menu, the `elementDetection` audit reported "Potentially inaccessible text" at its repeat as well, and the retry passed. Check the `audit-*` screenshot before changing the title.

## Findings

A finding gets a fix or a tracked action before the title ships:

- **Title-owned and small:** fix it in the title and add or extend the test that found it.
- **Title-owned and larger:** add a tracked action to the title's accessibility record with the owner file, the reason and the release it must land by. If the audit test must pass meanwhile, add an excuse in the test with the same page, audit type and element, pointing at that entry. An excuse with no record entry is a defect.
- **Shared shell (`Packages/GamePlatform`):** record it in the title's accessibility record with the exact `GamePlatform` change needed, and raise it with the shell's owners. Excuse it in the title's audit test only on the page where it occurs, pointing at that entry. The shell change removes the excuse from every title.
