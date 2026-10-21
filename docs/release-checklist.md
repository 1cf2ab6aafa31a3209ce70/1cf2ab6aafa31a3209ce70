# Release checklist

Run this checklist for each title's release candidate. A candidate is a Release build of one tagged revision; every item below uses that revision. Copy the checklist into the title's release record, for example `roadmap/audits/<title>-release-<version>.md`, and mark each item **pass**, **fail** or **not run**, with its evidence and the reason for anything not run. A fail blocks the candidate until it is fixed or a decision record narrows the release.

The checklist covers what one candidate needs. It does not replace the [privacy contract](privacy-contract.md), the [accessibility checklist](accessibility-checklist.md) or the [hardware check](hardware-check.md); it says when each one runs and what to record from it. Simulator results are labeled with runtime, geometry and instrumentation, and they are never presented as device results.

## 1. Candidate identity

- [ ] Title target and `title.json`: title ID, display name and bundle identifier match the title's store record.
- [ ] Marketing version and build number, commit SHA and tag.
- [ ] Xcode version and build used for the Release archive, and the CI toolchain and runtimes that ran the gates.
- [ ] Working tree clean at the tag; `python3 scripts/generate-project.py --check` passes.

## 2. Automated gates

Run locally and confirm in hosted CI on the tagged commit. Hosted CI counts only when every job has completed: a run can report success before its jobs finish, so check each job's status.

- [ ] `bash scripts/verify.sh <new dir>` passes. It checks the generated project, the package boundaries and static privacy surface (`scripts/check-foundation.py`), package, content and validator tests, Debug and Release simulator builds and the unsigned Release iOS build. It scans that Release build for required-reason API references against its privacy manifest (`scripts/check-required-reason-apis.py`) and runs the scanner's seeded-violation self-test.
- [ ] The release gates that `verify.sh` runs on this title's Release iOS bundle pass, each after its seeded-violation self-test: the bundle audit of linked frameworks, embedded code, entitlements, Info.plist entries and privacy manifest (`check-app-bundle.py`); the scan for network, web view, commerce, advertising, tracking, cloud, game-service and push APIs (`check-app-capabilities.py`); the string catalog against the declared languages (`check-localization.py`); provenance for every packaged file (`check-asset-provenance.py`); and a second clean build compared with the first (`check-reproducible-build.py`). Record each gate's last line.
- [ ] `bash scripts/test-mobile.sh <new dir> --title <Target>` passes on the iPhone 12 and iPad (9th generation) simulator geometries. It runs the title's app-hosted tests, UI tests and accessibility audits, and while they run it watches the app process for internet sockets and for networking log entries, failing on any app-originated activity. Record its network summary per geometry, including the largest gap between socket samples. Record the runtime, every `RETRIED` line and its `<model>-retries.json` entry, and handle any failure as [CONTRIBUTING](../CONTRIBUTING.md#ui-test-failures) describes before suspecting the app.
- [ ] The hosted minimum-runtime job passes the title's app-hosted and UI tests on the iOS 18.0 simulator runtime.
- [ ] The simulator regression baselines for startup, scene-update intervals, process memory and package size (`scripts/record-baselines.py`) are recorded for this candidate on both geometries and compared with the title's previous baseline. Explain any regression. These are simulator regression baselines, not device budgets.

## 3. Offline and network behavior

The automated network observation covers only the flows the UI tests exercise. Check the rest by hand, on a simulator or a device, with the network unavailable to the app.

- [ ] With the host offline (or the device in Airplane Mode with Wi-Fi off), a fresh install completes every player flow: first launch, menu, settings, every sound/music/haptics toggle, play, pause, resume, restart, success and failure results, relaunch with saved progress, export, reset progress, delete local data, and recovery after a damaged save where the title supports it.
- [ ] No flow shows a network error, waits on a connection or asks for any permission. Record any prompt.
- [ ] The automated observation reports no app-originated connection for the exercised flows. For the manual flows, record the observation method (for example the Instruments Network template, or a packet capture filtered to the app's process), its duration and the flows covered. Traffic from Apple system services is not app traffic, but list it with its source. Investigate any app-originated connection; it fails the candidate.
- [ ] A short quiet run is evidence for the flows it covered, not proof for every path. Record the coverage in those terms.

## 4. Privacy answers

Answer App Store Connect's privacy questions from the observed behavior above and the built bundle, not from intent. The answers below are the expected ones for a title that follows the privacy contract. A different behavior needs a privacy-contract decision first, not a different answer.

| Question or declaration | Expected answer | Verified by |
| --- | --- | --- |
| Data collection | **Data Not Collected.** The app and its frameworks collect no data types. | No app-originated traffic (section 3); bundle audit finds no networking, analytics, advertising or attribution code; saves stay in the title's local namespace ([ADR-005](../roadmap/decisions/ADR-005-local-save-durability.md)) |
| Tracking | **No.** No tracking, no tracking domains, no `NSUserTrackingUsageDescription` and no App Tracking Transparency call. | Privacy manifest `NSPrivacyTracking` false and `NSPrivacyTrackingDomains` empty (`check-foundation.py`); bundle audit for tracking-permission APIs |
| Privacy manifest collected data | `NSPrivacyCollectedDataTypes` empty | `check-foundation.py` |
| Required-reason APIs | `NSPrivacyAccessedAPITypes` empty while the Release binary references no listed API. If a change adds one, declare the reason that matches its actual use, review the change under the privacy contract, and update the allowed declaration that `check-foundation.py` enforces. | `check-required-reason-apis.py` on the Release iOS build, and its self-test |
| Player export | Not data collection. The player chooses a Files destination; that provider may transfer the copy; the developer receives nothing. | Export UI test and manual export in section 3 |
| Encryption export compliance | The app implements no encryption of its own; file protection comes from the OS. Record the answer given in App Store Connect. | Bundle audit for linked frameworks |

- [ ] Every answer in App Store Connect matches the table, or the difference is explained and approved in the release record.
- [ ] The privacy manifest in the built `.app` is the title's `PrivacyInfo.xcprivacy`, unchanged since its last review.

## 5. Privacy description

The store privacy policy and the description shown with the title must describe the local reset and export path. Use this text, adjusted only for the title's name:

> <Title> works offline and collects no data. It sends nothing to the developer or anyone else, and it shows no ads and offers no purchases or accounts. Your settings and progress are saved only on this device, and automatic backup and sync are turned off for them. To manage them, open Settings in the game and go to Local data:
>
> - **Export local data** saves a JSON copy of your progress and settings to a place you choose in Files. If you choose a cloud provider, that provider may transfer the copy. The developer receives nothing, and the copy stays yours after a reset or deletion.
> - **Reset progress** removes this title's progress and keeps your sound, music, haptics and language settings.
> - **Delete local data** removes this title's progress, settings and recovery files from this device. Other titles and exported copies are not changed.
>
> Deleting the app also removes its saved data. Apple's App Store and TestFlight services handle downloads and updates under Apple's own privacy policy.

- [ ] The published description matches the shipped Settings labels and behavior. Compare each label with the Settings page on the candidate.
- [ ] The description makes no claim the checks above did not verify.

## 6. Accessibility

- [ ] The [accessibility checklist](accessibility-checklist.md) passes on both simulator geometries for this candidate, with results in the title's accessibility record.
- [ ] Every finding has a fix or a tracked title-specific action with an owner file and reason. Shared shell findings name the `GamePlatform` change and its owner.

## 7. Content and provenance

- [ ] The title's content record (`Games/<Title>/CONTENT.md`) covers every packaged asset, level and text, as [asset provenance](asset-provenance.md) requires.
- [ ] Every third-party item in the bundle traces to its license and attribution, the required notices ship in the bundle, and the [inclusion inventory](../roadmap/audits/preflight-inclusion-bom.md) is current.
- [ ] Store screenshots, icon and description are original to this title and use no other game's names, art or layouts.

## 8. Release notes

Fill in this template for the candidate:

```markdown
# <Title> <version> (<build>)

Commit: <sha>, tag <tag>. Built with Xcode <version> (<build>).

## Changes
- <player-visible change, in plain words>

## Fixes
- <fixed problem and where a player would have seen it>

## Accessibility
- <accessibility change or tracked action that affects players, or "No change">

## Privacy
No data collected, no network use, saves stay on the device. <Any change to the privacy answers, or "Unchanged since <version>".>

## Known limits
- Tested on iOS simulators with iPhone 12 and iPad (9th generation) screen sizes, iOS <runtime> and the iOS 18.0 minimum runtime.
- Hardware check: <pass on <devices>, or "not run, ADR-009">.
- Unmeasured on devices: <copy the rows ADR-009 still lists for this title>.
```

## 9. Pre-distribution hardware check

- [ ] The [hardware check](hardware-check.md) passed on one iPhone and one iPad of the supported generations for this candidate, with its record linked.
- [ ] Or, while hardware is unavailable: mark this item **not run, ADR-009**, copy [ADR-009](../roadmap/decisions/ADR-009-release-scope-without-hardware.md)'s unmeasured rows into the release notes, and keep the candidate inside the project's development. It is not distributed.

## Sign-off

Record the reviewer, the date, the candidate's verdict (distributable, candidate only under ADR-009, or blocked) and each item still open.
