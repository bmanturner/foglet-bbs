# Roadmap: Foglet BBS

## Milestones

- [x] **v2.0 TUI Runtime Shell & Screen Update Loops** — Phases 34-40 shipped 2026-04-29 ([archive](milestones/v2.0-ROADMAP.md))
- [ ] **v2.1 Stability & Maintenance Hardening** — Phases 41-46 planned from `.planning/codebase/CONCERNS.md`

## Phases

<details>
<summary>v2.0 TUI Runtime Shell & Screen Update Loops (Phases 34-40) — SHIPPED 2026-04-29</summary>

- [x] Phase 34: Runtime Contract & Effects (3/3 plans) — completed 2026-04-28
- [x] Phase 35: Auth & Home Screens (4/4 plans) — completed 2026-04-28
- [x] Phase 36: Board & Thread Directory Flow (3/3 plans) — completed 2026-04-28
- [x] Phase 37: Post & Composer Flow (5/5 plans) — completed 2026-04-29
- [x] Phase 38: Account & Operator Workbenches (4/4 plans) — completed 2026-04-29
- [x] Phase 39: App Shell Simplification (8/8 plans) — completed 2026-04-29
- [x] Phase 40: Verification & Documentation (5/5 plans) — completed 2026-04-29

</details>

- [ ] **Phase 41: Screen Contract Compatibility Retirement** — Remove the bounded legacy screen callback surface and migrate remaining tests/helpers to the v2.0 contract.
  - **Requirements:** TUI-01, TUI-02
  - **Success criteria:**
    1. `Foglet.TUI.Screen` no longer declares legacy compatibility callbacks.
    2. Production screen modules no longer expose legacy `render/1`, `handle_key/2`, or `init_screen_state/1` clauses unless an explicit non-production test helper owns the compatibility.
    3. Smoke and reducer tests exercise `init/1`, `update/3`, and `render/2` seams rather than broad App-state callbacks.
    4. TUI render smoke checks still pass for representative screens.

- [ ] **Phase 42: Modal Submit Effects & App Runtime Helpers** — Replace process-dictionary modal submit plumbing and extract cohesive App shell helper modules.
  - **Requirements:** TUI-03, TUI-04, QUAL-02
  - **Success criteria:**
    1. Modal form submit emits a first-class `Foglet.TUI.Effect` value instead of stashing payloads in the process dictionary.
    2. `Foglet.TUI.App` interprets modal-submit effects and routes them to the target screen through `update/3`.
    3. Direct tests cover modal-submit effect routing and the success round trip.
    4. Routing, modal, subscriptions, or effect interpretation helpers are extracted where they reduce `App` concentration while preserving runtime ownership.

- [ ] **Phase 43: Screen Decomposition & PostReader Render Hygiene** — Split oversized screen responsibilities and harden PostReader cache/purity behavior.
  - **Requirements:** TUI-05, POST-02, POST-03
  - **Success criteria:**
    1. The largest screen modules named by the concerns audit have clearer state/render/reducer boundaries or explicit documented residual scope.
    2. PostReader drops stale-width render-cache entries on terminal resize or otherwise prevents old-width cache growth.
    3. Automated protection catches render-path state mutation in PostReader render helpers.
    4. Existing reader/composer/account/operator behavior remains covered by focused tests and render inspection.

- [ ] **Phase 44: Content Query Performance & Domain Cleanup** — Add large-thread/post query safeguards and clean up confusing domain/persistence seams.
  - **Requirements:** POST-01, POST-04, DOM-01, DOM-02
  - **Success criteria:**
    1. PostReader can request posts in batches or through a cursor-based query path instead of relying only on full-thread eager loads.
    2. Soft-delete filtering is centralized or comprehensively verified for post/thread list paths.
    3. The misleading `Foglet.Boards.Supervisor.boot_board_servers/0` stub is removed or made impossible to mistake for production boot behavior.
    4. `Foglet.Boards.Server` direct `Repo.transaction/1` usage is either documented with the `Ecto.Multi` error-shape rationale or converted without losing reply-path semantics.

- [ ] **Phase 45: SSH And Session Runtime Hardening** — Bound SSH auth stash state, centralize channel termination, and cover session replacement edge paths.
  - **Requirements:** SSH-01, SSH-02, SSH-03, SSH-04, SESS-01
  - **Success criteria:**
    1. `Foglet.SSH.PubkeyStash` orphan entries expire through TTL, sweep, or an equivalent bounded cleanup mechanism.
    2. Guest-to-user SSH promotion produces structured audit visibility with peer context when available.
    3. SSH channel termination has one helper that owns alt-screen leave, lifecycle/session cleanup, and connection counter decrement behavior.
    4. Tests cover connection-counter balance across normal termination, over-limit rejection, and crash/error paths.
    5. Tests directly exercise the `replace_then_promote/3` forced-termination fallback.

- [ ] **Phase 46: Dialyzer Baseline & Concerns Closure Verification** — Reduce warning debt and prove every concerns-audit item has a disposition.
  - **Requirements:** QUAL-01, QUAL-03
  - **Success criteria:**
    1. Every `.dialyzer_ignore.exs` entry named by the concerns audit is fixed, narrowed, or explicitly retained with rationale.
    2. A v2.1 verification artifact maps each `.planning/codebase/CONCERNS.md` item to fixed, tested, documented-retained, or intentionally deferred with user-approved rationale.
    3. The full `rtk mix precommit` gate passes.
    4. PROJECT, REQUIREMENTS, ROADMAP, and STATE traceability reflect completed v2.1 scope.

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 34. Runtime Contract & Effects | v2.0 | 3/3 | Complete | 2026-04-28 |
| 35. Auth & Home Screens | v2.0 | 4/4 | Complete | 2026-04-28 |
| 36. Board & Thread Directory Flow | v2.0 | 3/3 | Complete | 2026-04-28 |
| 37. Post & Composer Flow | v2.0 | 5/5 | Complete | 2026-04-29 |
| 38. Account & Operator Workbenches | v2.0 | 4/4 | Complete | 2026-04-29 |
| 39. App Shell Simplification | v2.0 | 8/8 | Complete | 2026-04-29 |
| 40. Verification & Documentation | v2.0 | 5/5 | Complete | 2026-04-29 |
| 41. Screen Contract Compatibility Retirement | v2.1 | 0/TBD | Planned | — |
| 42. Modal Submit Effects & App Runtime Helpers | v2.1 | 0/TBD | Planned | — |
| 43. Screen Decomposition & PostReader Render Hygiene | v2.1 | 0/TBD | Planned | — |
| 44. Content Query Performance & Domain Cleanup | v2.1 | 0/TBD | Planned | — |
| 45. SSH And Session Runtime Hardening | v2.1 | 0/TBD | Planned | — |
| 46. Dialyzer Baseline & Concerns Closure Verification | v2.1 | 0/TBD | Planned | — |

## Next

Start Phase 41 with `$gsd-plan-phase 41`.

---
*Roadmap updated: 2026-04-29 after v2.1 milestone initialization*
