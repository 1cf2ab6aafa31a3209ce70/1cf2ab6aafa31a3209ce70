# Epic 07 — Multi-title integration

**Outcome:** Adding a title is a small, documented operation. Two independent app targets use the same core and do not share saves, assets, or title identity by accident.

**Entry:** Spike 06 proved the module interface; Epics 01–05 provide shell, local state, and content. **Next:** Spike 11. This epic depends on all earlier ordered work.

## Scope and tasks

1. Turn the chosen registration interface into the production `GameModule` contract with title metadata, level decoding, rules factory, gameplay view factory, and lifecycle callbacks. First close the open validation in [ADR-006](../decisions/ADR-006-game-module-seam.md): rerun the full focused seam checks on the promoted sources, on both simulator geometries and in hosted CI.
2. Use the existing development practice as the second, smoke-test title target. Build the reference game as the first vertical slice of the [block title](09a-block-title.md): one or two original levels and only the rules the contract tests need. Give both targets distinct bundle IDs, app icons, content catalogs, and save namespaces. Epic 09A extends this slice rather than replacing it.
3. Add a new-title template or generator, extending `scripts/generate-project.py`, for project configuration, asset catalogs, localization, privacy metadata, and CI registration. Generated targets must compile before custom gameplay is added.
4. Add contract tests that run a fake module through launch, level load, pause, result, save, and relaunch; verify that module failures show a recoverable shell error.
5. Scale CI with the number of targets. Run a title's app-hosted and UI tests when that title or a shared package changes; run shared-package checks on every change. Keep each job within the workflow timeout with headroom. Every title's UI tests run through the collector, which retries a failed case once and checks each failure against the simulator input fault behind N06.
6. Document which APIs title authors can rely on and how to evolve content and module contracts. Publish the contract as version 1, provisional until Spike 11 confirms that a terrain title fits it.

## Acceptance

- Both app targets build and launch using one shared source of core behavior.
- ADR-006's seam checks pass on both simulator geometries and in hosted CI at the promoted revision.
- Changing one title's rules, art, levels, or bundle metadata does not require editing another title.
- Removing a title target leaves core tests and the other title building.
- A contributor can create a third skeletal title using documented steps without copying core source files.

**Outside this epic:** Complete block, tile, unscrew, or dig mechanics. The reference slice carries only what the contract tests need.

## Status — 2026-10-19

Complete for mobile simulator acceptance. [Module contract version 1](../decisions/ADR-007-module-contract-v1.md), provisional until Spike 11, carries the practice title and the Block Match reference slice, each with its own bundle identifier, icon, catalog and save namespace. Titles come from `title.json` manifests, which drive generation, checks, the mobile test runner and CI. `scripts/new-title.py` creates a third title that builds and passes its tests before any gameplay, and [Adding a title](../../docs/adding-a-title.md) documents what a title may rely on. The [evidence report](../audits/epic-07-module-integration.md) maps each acceptance item to local and hosted checks. Spike 11's entry gate is satisfied.
