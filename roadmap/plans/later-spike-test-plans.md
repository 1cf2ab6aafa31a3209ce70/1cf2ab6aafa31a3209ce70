# Later spike test preparation

**Status:** Preparation only. No prototypes, production contracts, technology choices, or roadmap dependency changes are established here.

These plans make future investigations reproducible. Execute each only after its entry gate is met; the roadmap remains ordered. [ADR-003](../decisions/ADR-003-simulator-mobile-foundation.md) accepts simulator-only mobile foundation development with an iOS/iPadOS 18.0 deployment floor. Use iPhone 12 and iPad (9th generation) simulator geometry; physical hardware is unavailable and macOS is outside current scope. Retained simulator timings are diagnostic observations, not physical performance or minimum-runtime certification.

For each eventual run, retain the source revision, toolchain, configuration, host/simulator runtime/geometry, fixture or input sequence, expected result, actual result, and local evidence path. Keep fixtures synthetic and evidence manually shared; no production telemetry is required.

## Spike 03 — Local save durability

**Entry:** [Epic 02](../epics/02-app-shell.md) must provide the working shell and its lifecycle transitions. **Brief:** [Spike 03](../spikes/03-save-durability.md). **Timebox:** One developer day.

Inputs are synthetic completion, score, unlock and settings records for two title identifiers, one prior-schema fixture, and the shell's interruption behavior. The future comparison is a Codable file versus a local database against those actual needs; this plan selects neither.

| Scenario | Observable evidence |
| --- | --- |
| First launch with absent data; ordinary save and reload | Defined defaults and exact round-trip values, including title ID and schema version |
| Terminate before replacement, at replacement, and after replacement | Reproducible fault points and reload result; only an intact previous or new record is recovered, with no partial progress silently accepted |
| Corrupt primary data; valid or corrupt previous-good backup | Explicit recovery/error result for each combination; preserved recoverable progress and no overwrite before recovery is resolved |
| Load prior schema twice; reject unsupported future schema | Expected migrated values and repeat-run behavior; documented unsupported-version handling |
| Reuse a level ID across two titles; inject a title identifier mismatch | Independent progress remains isolated, and a mismatched record cannot become another title's progress |
| Save during background/pause and rapid repeated updates | Defined ordering and final persisted value after relaunch, tied to shell events rather than assumed callback timing |
| Export, reset and delete local data | Inspectable export and reload behavior after each action; documented scope of settings/progress and confirmation that no developer contact is needed |

Stop after the one-day comparison and record the smallest justified strategy, unresolved cases, and executable interruption/migration fixtures required by the brief. Do not expand into a generalized database layer or cloud/account design. A missing recovery proof remains an open exit criterion. Simulator termination/fault injection establishes tested software recovery paths, not physical power-loss or storage-device durability.

## Spike 06 — Game-module seam

**Entry:** [Epic 05](../epics/05-content.md) must establish the level contract; existing shell and save services must be available. **Brief:** [Spike 06](../spikes/06-module-seam.md). **Timebox:** Two developer days.

Inputs are one validated grid level, one terrain placeholder level, their content versions/seeds, and accepted platform/rendering evidence. Both future prototypes use the existing shell. The disposable Spike 00 sample supplies observations, not a production module contract.

| Scenario | Observable evidence |
| --- | --- |
| Register and load each module, including malformed content | Both compile and enter play; invalid content produces the defined shell error rather than a partial scene |
| Pause/resume, background/foreground, restart and repeated loading | Input suspension and restored state; one active scene and one set of subscriptions after each cycle |
| Input, success/failure, settings changes and save callbacks | Explicit callback/state sequence for each module; title-owned rules determine outcomes and services receive the intended title/level identity |
| Replay the same pure-rule fixture with the same seed | Matching outcome independent of renderer lifetime and display update cadence |
| Build separate title targets and pure-rule tests | Dependency diagram and source/API inspection show no SpriteKit, RealityKit or Metal types crossing the shared core contract |
| Compare protocol/factory, generic and plugin-style registration | A small compiling comparison, concrete costs and at least one rejected over-generalized API; retain shared behavior only when both modules demonstrate it |
| Exercise a proposed contract evolution | Documented migration rule and affected call sites, with an example showing how existing title targets adapt |

Stop at two days with compiling prototypes, registration documentation, dependency diagram and the required decision record. Missing entry services do not justify reimplementing them in the spike. Keep simulation, hit testing, physics, rendering and genre-specific UI title-owned unless evidence demonstrates a shared need.

## Spike 11 — Dig feasibility

**Entry:** [Epic 10](../epics/10-unscrew-title.md) must be complete, including the established production module contract and earlier release gates. **Brief:** [Spike 11](../spikes/11-dig-feasibility.md). **Timebox:** Three developer days.

Inputs are the accepted mobile platform matrix and simulator Spike 00 evidence, a fixed arena/workload, deterministic input fixtures, the existing `GameModule` interface, and the two selected mobile simulator geometries. Recheck current Apple guidance and the brief's two external examples at execution time; any candidate dependency requires pinned-source/license review before adoption. No external code or adoption decision is included in this preparation.

| Scenario | Observable evidence |
| --- | --- |
| Continuous excavation/growth, collection and collision | Identified input sequence, visible terrain change, object response over changed geometry and rule-owned score; distinguish first contact from settled response |
| Run identical rules with different render cadences and delayed mesh/collision work | Matching deterministic outcomes and an explicit policy for interaction while geometry updates are pending |
| Repeated restart, pause/resume and scene reload | Restored initial rule state, suspended input/physics as intended, no duplicated subscriptions and bounded memory across repeated cycles |
| Sustained workload on both selected simulator geometries | Host/runtime, instrumentation, duration, scene-update intervals, mesh/collision CPU timings, available process-memory metrics and reload time; separate any actual presentation measurements. Physical GPU, battery/thermal and device memory-pressure behavior remain unmeasured. |
| Compare heightfield, voxel/chunk mesh and 2D approximation narrowly | Same player action/workload and comparable measurements where applicable; explicit mechanic limitations such as overhangs or collision lag |
| Mobile touch and accessible non-precision control | Observable completion of the same actions without precision dragging; semantic controls and interruption behavior checked in the mobile environment |
| Integrate through the existing module interface | Compiling registration and API inspection demonstrate no terrain-specific types added to core services |

Fix the workload and target budgets before comparison, using accepted baseline evidence rather than inventing thresholds after a run. Record separate results for each simulator geometry and distinguish sustained presented timing from diagnostic scene-update samples. Set simulator workload limits using comparable observations rather than importing physical budget claims. Keep missing minimum-runtime and distribution evidence explicit without blocking development or adding Mac work.

Stop at three days with a reproducible prototype, measurements, decision record and risk mitigations. Scope the resulting mechanic to deformable 3D terrain, simplified chunks or 2D excavation. If no 3D candidate meets the agreed budget, record the measured failure and the brief's 2D fallback for Epic 12; do not extend the spike into an unbounded engine project.
