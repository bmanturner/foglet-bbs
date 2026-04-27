---
phase: 29-sysop-tab-lifecycle-bodies
plan: 01
subsystem: ui
tags:
  - tui
  - sysop
  - lifecycle
  - async-load
  - raxol

# Dependency graph
requires:
  - phase: 28-modal-form-substrate
    provides: SiteForm Modal.Form wrapper, Saved./Esc-reseed contract (D-08, D-12)
provides:
  - Tagged-enum lifecycle (`:not_loaded | :loading | {:loaded, sub} | {:error, reason}`) for the four Sysop tab body slots
  - App-level load triad for BOARDS / LIMITS / SYSTEM / USERS (dispatch + result + put_sysop_*)
  - Tab-switch and first-entry dispatch in Sysop screen / App `{:navigate, :sysop}` chain
  - render_tab_body lifecycle pattern-match honoring `{:error, :forbidden}` before `{:error, _other}` (Pitfall 3)
  - `delegate_to_submodule/5` `{:loaded, sub}` guard — kills "Press any key to load"
  - `Foglet.TUI.Screens.Sysop.UsersView.from_groups/2` pure constructor for App-side load closure
affects: [29-02 retry-and-forbidden, 29-03 users-and-invites, 29-04 site-fields-and-jump]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Tagged-enum lifecycle slots: `:not_loaded | :loading | {:loaded, struct} | {:error, atom}` carrying the existing submodule struct verbatim"
    - "App-level four-slot load triad: per-slot dispatch / result / put_*_loading|loaded|error helpers — extends the moderation single-snapshot precedent"
    - "Closure capture (Pitfall 8): bind `user`/`accounts_mod` outside the task closure so domain_module/2 swap evaluates at dispatch time"
    - "Pattern-match order: `{:error, :forbidden}` matched BEFORE `{:error, _other}` in render and command-bar gating"

key-files:
  created:
    - "test/support/fake_accounts.ex"
  modified:
    - "lib/foglet_bbs/tui/screens/sysop/state.ex"
    - "lib/foglet_bbs/tui/screens/sysop.ex"
    - "lib/foglet_bbs/tui/screens/sysop/users_view.ex"
    - "lib/foglet_bbs/tui/screens/domain.ex"
    - "lib/foglet_bbs/tui/app.ex"
    - "test/foglet_bbs/tui/screens/sysop_test.exs"
    - "test/foglet_bbs/tui/app_test.exs"
    - "test/support/foglet/tui/layout_smoke/sysop_helper.ex"

key-decisions:
  - "D-07: bare tagged values (`:not_loaded | :loading | {:loaded, struct} | {:error, reason}`) — no envelope module"
  - "D-09: delegate_to_submodule/5 splits — SITE keeps lazy-init; lifecycle slots require {:loaded, sub} or :no_match"
  - "D-04: NO direct `Raxol.Core.Runtime.Command.task` calls under any Sysop.* module — all task wrapping in App"
  - "D-05/D-06: tab-switch and `{:navigate, :sysop}` first-entry both gated by `:not_loaded` for idempotency"
  - "Added `:accounts` to `Foglet.TUI.Screens.Domain.@supported_keys` so the test-injection swap works for the USERS load triad"

patterns-established:
  - "Lifecycle slot pattern: state.ex defaults `:not_loaded`; render_tab_body matches the four tags with forbidden-before-generic order; delegate guards on `{:loaded, _}`"
  - "App-side load triad with slot atom argument — generalises moderation's single-snapshot helpers to a multi-slot screen"
  - "Synchronous slot transition: tab-switch flips `:not_loaded → :loading` in the SAME `handle_key/2` return that emits the dispatch tuple, so the Loading panel renders on the first frame after switch"
  - "Test helper convention for tagged-enum slots: `put_*` wraps to `{:loaded, _}` on write, `current_*` unwraps with flunk-on-non-loaded for read assertions"

requirements-completed:
  - SYSOP-01
  - SYSOP-02

# Metrics
duration: 65min
completed: 2026-04-27
---

# Phase 29 Plan 01: Sysop Tab Lifecycle Substrate Summary

**Four-slot tagged-enum lifecycle, App-level load triad, and `{:loaded, sub}`-guarded delegate kill the "Press any key" anti-pattern across BOARDS/LIMITS/SYSTEM/USERS — substrate every other Phase 29 plan stacks on.**

## Performance

- **Duration:** ~65 min
- **Started:** 2026-04-27 (early afternoon)
- **Completed:** 2026-04-27
- **Tasks:** 3
- **Files modified:** 8 (1 created, 7 modified)

## Accomplishments

- `Foglet.TUI.Screens.Sysop.State` now exposes a `lifecycle/1` parameterised typespec; the four lifecycle slots default to `:not_loaded` and accept the full tagged enum without `nil` ever reaching a renderer (D-07, D-10).
- Four App-level load triads in `Foglet.TUI.App.do_update/2` mirror the moderation precedent verbatim — dispatch + result + `put_sysop_loading|loaded|error` helpers — with `user`/`accounts_mod` bound BEFORE the task closure (Pitfall 8).
- `{:navigate, :sysop}` chain calls `maybe_dispatch_initial_sysop_load/1` so first-entry into a lifecycle tab transitions the slot to `:loading` and emits the matching `{:load_sysop_*}` exactly once. Re-entry on `{:loaded, _}` is idempotent.
- `Sysop.handle_key/2` tab-changed branch routes through `maybe_dispatch_lifecycle_load/2` — same idempotency contract.
- `render_tab_body/3` rewritten to pattern-match the tagged enum with `{:error, :forbidden}` BEFORE `{:error, _other}` (Pitfall 3). `loading_panel/forbidden_panel/error_panel` route through `theme.dim.fg`/`theme.warning.fg`/`theme.error.fg` respectively (D-08, D-11, D-12).
- `delegate_to_submodule/5` splits into a SITE clause (lazy-init preserved per D-03) and a lifecycle clause that requires `{:loaded, sub}` and stores the result wrapped (D-09). Non-loaded events return `:no_match`.
- All five "Press any key to load" placeholders removed; SITE now lazy-inits `SiteForm.init([])` inline.
- `Foglet.TUI.Screens.Sysop.UsersView.from_groups/2` extracted as a pure constructor so the App-side load closure can shape the boundary call's `groups` payload without re-issuing the call.
- Test helpers updated to wrap lifecycle slots as `{:loaded, _}` on write and unwrap via `current_*_view/1` on read; layout smoke helper similarly updated. All 1923 project tests pass.

## Task Commits

Each task was committed atomically:

1. **Task 1: Tagged-enum slots in `Sysop.State` + lifecycle test scaffold** — `5860e38` (feat)
2. **Task 2: App-level Sysop load triad + `put_sysop_*` helpers + navigate-:sysop chain** — `22dbfd9` (feat)
3. **Task 3: Sysop screen rewrites — `render_tab_body` lifecycle, delegate guard, tab-switch dispatch, "Press any key" removal** — `f5ff26e` (feat)

## Files Created/Modified

**Created:**
- `test/support/fake_accounts.ex` — Test double for `Foglet.Accounts.list_user_status_admin_targets/1` so the USERS load triad runs without a Repo connection. Mirrors the `FakeModeration` pattern.

**Modified:**
- `lib/foglet_bbs/tui/screens/sysop/state.ex` — Added `lifecycle/1` typespec; flipped the four slot defaults to `:not_loaded`; aliased the four submodule structs so the typespec resolves under Dialyzer.
- `lib/foglet_bbs/tui/screens/sysop.ex` — Rewrote `render_tab_body/3` (lifecycle pattern-match), `delegate_to_submodule/5` (SITE-vs-lifecycle split), `handle_key/2` tab-changed branch (`maybe_dispatch_lifecycle_load`); added `loading_panel`/`forbidden_panel`/`error_panel`/`maybe_dispatch_lifecycle_load`/`dispatch_if_not_loaded` helpers; removed all five "Press any key" literals.
- `lib/foglet_bbs/tui/screens/sysop/users_view.ex` — Added `from_groups/2` pure constructor; existing `init/1` and `refresh_rows/1` unchanged.
- `lib/foglet_bbs/tui/screens/domain.ex` — Added `:accounts` to `@supported_keys` and the `domain_key()` typespec so test-injection works for the USERS load triad.
- `lib/foglet_bbs/tui/app.ex` — Added 4 dispatch + 8 result + 5 helper functions for the Sysop load triad; wired `{:navigate, :sysop}` to `maybe_dispatch_initial_sysop_load/1`; added `default_domain_module(:accounts)`.
- `test/foglet_bbs/tui/screens/sysop_test.exs` — New `lifecycle tagged-enum`, `render_tab_body lifecycle`, `delegate_to_submodule guard`, `tab-switch dispatch` describes (17 new tests). Updated `put_users_view`/`put_boards_view`/`activate_users_tab`/`activate_boards_tab`/`activate_system_tab` to wrap slot values; added `current_*_view/1` and `current_limits_form/1`/`current_system_snapshot/1` unwrappers; rewrote LIMITS Modal.Form primitive presence describe to inject `{:loaded, _}` directly.
- `test/foglet_bbs/tui/app_test.exs` — New `App-level sysop load triad` describe (8 tests) covering dispatch / result-ok / result-error / navigate-chain / idempotent re-entry / round-trip across all four slots. Added `fake_sysop_context/1` setup helper.
- `test/support/foglet/tui/layout_smoke/sysop_helper.ex` — Wrapped pre-loaded slots as `{:loaded, _}` for LIMITS/USERS/SYSTEM size-contract tests.

## Decisions Made

- **`:accounts` joined `Domain.@supported_keys`** — required to allow `domain_module(state, :accounts)` to resolve `FakeAccounts` from the test session_context. Without this, the closure falls back to the real `Foglet.Accounts` and tests hit DB ownership errors. This is a structural extension of the AUDIT-02 baseline; documented in the moduledoc.
- **`default_domain_module(:accounts) -> Foglet.Accounts`** added so the production fallback works when no test override is configured.
- **SITE lazy-init moved into `render_tab_body("SITE", ...)`** — previously the placeholder text covered the nil-default; now there is no placeholder, so the render path lazy-inits `SiteForm.init([])` if the slot is still nil. Matches D-03's "SITE remains synchronous" decision exactly.
- **Test helpers `current_users_view/1` etc. unwrap with `flunk/1`** rather than returning `nil` — surfaces `:not_loaded`/`:loading`/`:error` values immediately when an assertion expects a loaded sub.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added `:accounts` to `Foglet.TUI.Screens.Domain.@supported_keys`**
- **Found during:** Task 2 (App-level load triad tests)
- **Issue:** `Domain.get(ctx, :accounts)` returned `{:error, :not_configured}` because `:accounts` was not in `@supported_keys`. The test-injection `%{domain: %{accounts: FakeAccounts}}` was therefore ignored, and the closure fell back to `default_domain_module(:accounts)` which raised a `FunctionClauseError`.
- **Fix:** Added `:accounts` to `@supported_keys` and the `domain_key()` typespec; added `default_domain_module(:accounts) -> Foglet.Accounts`.
- **Files modified:** `lib/foglet_bbs/tui/screens/domain.ex`, `lib/foglet_bbs/tui/app.ex`
- **Verification:** All 8 sysop_load_triad tests pass; closure now resolves `FakeAccounts` from the test override.
- **Committed in:** `22dbfd9` (Task 2 commit)

**2. [Rule 3 - Blocking] Layout smoke `sysop_helper.ex` wrapped pre-loaded slots as `{:loaded, _}`**
- **Found during:** Task 3 (broader test sweep after Sysop rewrite)
- **Issue:** Layout-smoke helpers were storing raw submodule structs (`Map.put(:limits_form, LimitsForm.init([]))`) — after Phase 29 D-07, those slots store the tagged enum, so `render_tab_body` hit `(CaseClauseError) no case clause matching: %LimitsForm{}`.
- **Fix:** Wrapped each pre-loaded slot as `{:loaded, _}` in the three Sysop helper macros (LIMITS, USERS, SYSTEM).
- **Files modified:** `test/support/foglet/tui/layout_smoke/sysop_helper.ex`
- **Verification:** All 6 layout-smoke failures cleared; full TUI test suite (1385 tests) passes.
- **Committed in:** `f5ff26e` (Task 3 commit)

---

**Total deviations:** 2 auto-fixed (both Rule 3 blocking)
**Impact on plan:** Both deviations were necessary for the planned changes to work end-to-end. No scope creep.

## Issues Encountered

- **Worktree base mismatch at startup.** `git merge-base HEAD <expected>` returned `3226ef9...` instead of `65e02eb...`; recovered with `git reset --hard 65e02eb...`. No work lost.
- **Worktree had no `deps`/`_build`.** Symlinked the parent repo's `deps/` and `_build/` into the worktree to enable `rtk mix compile`/`mix test`. Both directories are gitignored.
- **`:accounts` domain key gap (deviation 1 above).** Initially manifested as a `FunctionClauseError` in `default_domain_module/1`; root cause was the missing `Domain.@supported_keys` entry.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- **Plan 02 (retry-and-forbidden):** Substrate is in place. `[R] Retry` advertising can read `state.screen_state.sysop.<slot>` and gate on `match?({:error, reason}, _) and reason != :forbidden`. `R` keypress can re-dispatch the matching `{:load_sysop_*}` tuple via `process_screen_commands/2`.
- **Plan 03 (users-and-invites):** USERS slot is now reliably `{:loaded, %UsersView{}}` once load completes; per-row keybind gating (D-15) and from→to copy (D-16) can build on `current_users_view/1`-style read paths.
- **Plan 04 (site-fields-and-jump):** Independent of this plan's substrate. `1-N Jump` work is purely render-side.

## Threat Flags

No new security-relevant surface introduced beyond what the threat model anticipates. T-29-01..T-29-04 mitigations all in place:
- T-29-01 (delegate lazy-init EoP) — mitigated via the `{:loaded, sub}` guard in `delegate_to_submodule/5`. Verified by `delegate_to_submodule guard` describe block.
- T-29-02 (stale `{:loaded, _}` after role demotion) — accepted; documented for future SYSOP-FUT-01.
- T-29-03 (direct `Raxol.Core.Runtime.Command.task` call from Sysop.*) — mitigated; D-04 grep test in `render_tab_body lifecycle` describe verifies 0 occurrences across `lib/foglet_bbs/tui/screens/sysop.ex` + `sysop/**`.
- T-29-04 (closure capture of `state` instead of bound `user`/`accounts_mod`) — mitigated; the four dispatch clauses bind values BEFORE the task closure verbatim per the moderation precedent.

## Self-Check: PASSED

All claimed files exist; all task commits present in `git log`.

```
FOUND: lib/foglet_bbs/tui/screens/sysop/state.ex (modified)
FOUND: lib/foglet_bbs/tui/screens/sysop.ex (modified)
FOUND: lib/foglet_bbs/tui/screens/sysop/users_view.ex (modified)
FOUND: lib/foglet_bbs/tui/screens/domain.ex (modified)
FOUND: lib/foglet_bbs/tui/app.ex (modified)
FOUND: test/foglet_bbs/tui/screens/sysop_test.exs (modified)
FOUND: test/foglet_bbs/tui/app_test.exs (modified)
FOUND: test/support/foglet/tui/layout_smoke/sysop_helper.ex (modified)
FOUND: test/support/fake_accounts.ex (created)
FOUND: 5860e38 — feat(29-01): tag Sysop lifecycle slots as :not_loaded enum
FOUND: 22dbfd9 — feat(29-01): add App-level Sysop load triad with put_sysop_* helpers
FOUND: f5ff26e — feat(29-01): rewrite Sysop screen for tagged-enum lifecycle
```

---
*Phase: 29-sysop-tab-lifecycle-bodies*
*Completed: 2026-04-27*
