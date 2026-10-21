# Pre-distribution hardware check

Simulators cannot show how a title behaves on a phone or tablet. [ADR-003](../roadmap/decisions/ADR-003-simulator-mobile-foundation.md) therefore makes hardware-only behavior a named check before distribution, not an exit criterion for development work. This page defines that check. [ADR-009](../roadmap/decisions/ADR-009-release-scope-without-hardware.md) records what a release may claim while no hardware is available.

Run the check once per title for each release candidate that will leave the developer's hands, including external TestFlight, and again when a change touches rendering, the frame loop, content size, audio or input. Every candidate step of the [release checklist](release-checklist.md) must already pass, because the check uses the candidate build itself.

## Devices

Use at least one physical iPhone and one physical iPad:

| Role | Reference device | Acceptable substitute |
| --- | --- | --- |
| iPhone | iPhone 12 (A14 Bionic) | Another iPhone that runs iOS 18 or later and is no faster than an A14 |
| iPad | iPad (9th generation) (A13 Bionic) | Another iPad that runs iPadOS 18 or later and is no faster than an A13 |

A faster substitute may supplement the reference devices but cannot replace them, because the budgets below are set for these chips. Prefer the lowest installed OS at or above the 18.0 deployment floor. Record when a device runs a later OS than the floor.

## Setup

1. Install the release candidate: Release configuration, the candidate's source revision, signed for development or ad hoc distribution, and no DEBUG launch arguments. Delete any earlier install first, so the run starts with no saved data.
2. Charge to at least 80 %, then unplug. Turn off Low Power Mode. Fix brightness at 50 % with Auto-Brightness off. Turn on Airplane Mode, with Wi-Fi and Bluetooth off as well.
3. Let the device sit idle on a table, out of its case, for 10 minutes before the first measurement. Record the room temperature.
4. Use Xcode Instruments from the Xcode version that built the candidate. Keep every trace file with the evidence.

## Procedure

Each step names the measurement, the method and what passes. The budgets are [ADR-002](../roadmap/decisions/ADR-002-platform-rendering-baseline.md)'s physical targets. A simulator value never stands in for one of them.

1. **Startup.** Run 5 cold launches, each after a device restart or after force-quitting the app and waiting 30 seconds, then 5 warm launches. Use the Instruments App Launch template. Record the time to the first frame and the time until the menu's Play button responds to a tap. There is no startup budget yet: record the median and maximum. A launch the system terminates, or one over 2 seconds to an interactive menu, is a finding.
2. **Frame pacing.** Play the title's sustained workload for 10 minutes with the Animation Hitches template (or Core Animation frame intervals where Hitches is unavailable). For Blocky Marty the workload is repeated clears and restarts of every shipped board by touch. Pass: presented-frame interval p95 ≤ 20 ms and p99 ≤ 33.4 ms over the whole window, at 60 Hz. Record the hitch-time ratio and the longest hitch. Scene-update intervals are not presented frames.
3. **Memory.** Use the Allocations template with VM Tracker, or Xcode's memory report. Record the peak footprint during the frame-pacing workload, and the footprint after each of 10 consecutive returns to the menu followed by a new game. Then send Simulate Memory Warning from Xcode during play. Pass: peak ≤ 150 MiB for a board or panel title and ≤ 250 MiB for a terrain title; no growth larger than 1 MiB between consecutive restarts after the third; the app survives the memory warning with its game intact.
4. **Thermal behavior.** Continue play for 20 minutes in total, with the thermal state track in Instruments (System Trace or Power Profiler). Record the thermal state at the start, every 5 minutes and at the end, the battery drop over the 20 minutes, and frame pacing for the first and last 5 minutes. Pass: the thermal state never goes above Fair, and the last 5 minutes still meet the frame-pacing budget.
5. **Touch.** On each device, in portrait and landscape:
   - Make 20 deliberate taps on board cells, including every corner and edge cell. Each must select the cell under the finger. Record misses.
   - Tap two cells in quick succession, rest a second finger on the board while tapping with another, and drag across the board. None may select a cell the player did not tap, and none may crash or stall.
   - Pause, rotate, resume and play on. Background the app with the Home gesture or button, return, and resume.
   - Turn on VoiceOver and play a board using only swipes and double taps. After each page change (start, pause, resume, both results, back to menu), VoiceOver focus must be on the new page, not on a control that disappeared. For Blocky Marty, also strand a block (on the second board, clear the group of three first, then the group of five): VoiceOver must announce "No moves left. Undo a move, or end the board.", and Undo must bring the board back. Turn on Voice Control and play a board by saying the block names or numbers.
   - Turn on Settings > Accessibility > Display & Text Size > Color Filters > Grayscale and open every page. Every block kind must stay distinguishable. The simulator has no Color Filters setting.
   - With the ring/silent switch on and off, and with headphones connected and then removed, confirm sound effects, music and haptics follow the Settings toggles, and that removing headphones pauses play.

## Record

Add the result to the title's audit, for example `roadmap/audits/<title>-hardware-check.md`, with:

| Field | Value |
| --- | --- |
| Title, version and build number | |
| Source revision and configuration | Release; commit SHA |
| Xcode version and build | |
| Device model, chip, OS version and build | One row per device |
| Battery at start, room temperature, date and tester | |
| Startup | Cold and warm median and maximum, to first frame and to interactive menu |
| Frame pacing | p95, p99, hitch-time ratio, longest hitch, instrument and template |
| Memory | Peak footprint, per-restart footprints, memory-warning result |
| Thermal | States at 0, 5, 10, 15 and 20 minutes; battery drop; first and last 5 minutes p95 and p99 |
| Touch | Misses out of 20, multi-touch and drag results, rotation and background results, VoiceOver (focus after page changes included), Voice Control, Grayscale and audio/haptic results |
| Verdict per step | Pass, fail or not tested, with the reason |
| Evidence | Paths to traces, screen recordings and notes |

A failed step blocks distribution until the title fixes it or a decision record narrows the release. A step not tested stays listed as unmeasured in that release's notes, as ADR-009 requires.
