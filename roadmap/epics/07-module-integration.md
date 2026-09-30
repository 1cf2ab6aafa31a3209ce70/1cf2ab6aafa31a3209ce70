# Epic 07 — Multi-title integration

**Outcome:** Adding a title is a small, documented operation. Two independent app targets use the same core and do not share saves, assets, or title identity by accident.

**Entry:** Spike 06 proved the module interface; Epics 01–05 provide shell, local state, and content. **Next:** Epic 08. This epic depends on all earlier ordered work.

## Scope and tasks

1. Turn the chosen registration interface into the production `GameModule` contract with title metadata, level decoding, rules factory, gameplay view factory, and lifecycle callbacks.
2. Create a small original reference game and a second smoke-test title target with distinct bundle IDs, app icons, content catalogs, and save namespaces.
3. Add a new-title template or generator for project configuration, asset catalogs, localization, privacy metadata, and CI registration. Generated targets must compile before custom gameplay is added.
4. Add contract tests that run a fake module through launch, level load, pause, result, save, and relaunch; verify that module failures show a recoverable shell error.
5. Document which APIs are stable for title authors and how to evolve content and module contracts.

## Acceptance

- Both app targets build and launch using one shared source of core behavior.
- Changing one title's rules, art, levels, or bundle metadata does not require editing another title.
- Removing a title target leaves core tests and the other title building.
- A contributor can create a third skeletal title using documented steps without copying core source files.

**Outside this epic:** Production block, tile, unscrew, or dig mechanics.
