---
phase: 29-sysop-tab-lifecycle-bodies
plan: 02
subsystem: ui
tags:
  - tui
  - sysop
  - users
  - retry
  - authorization

# Dependency graph
requires:
  - phase: 29-sysop-tab-lifecycle-bodies
    plan: 01
    provides: Tagged-enum lifecycle, App-level load triad, render_tab_body lifecycle pattern-match
provides:
  - Public Foglet.Accounts.valid_status_transitions/1 predicate (UI-side gating uses the same source as the writer)
  - Render-time footer + per-row keybind gating in UsersView (D-15, A2 disambiguation)
  - From→to error copy for {:error, :invalid_transition} (D-16, no `invalid_transition` substring leaks)
  - [R] Retry advertising in Sysop command bar gated by active-tab error tag (D-13)
  - R keypress handler that re-dispatches the matching {:load_sysop_*} on retryable errors and falls through on loaded/forbidden tabs
affects: [29-03 users-and-invites, 29-04 site-fields-and-jump]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Render-time footer pattern: footer_text/1 consults Accounts.valid_status_transitions/1 for the focused row's source status"
    - "A2 disambiguation: same-target keybinds disambiguate by source status ([A] only on :pending, [U] only on :suspended)"
    - "Source-aware no-op pattern: maybe_transition/3 gates the keypress against the focused row's status — non-advertised keys are pure no-ops"
    - "From→to error copy pattern: error builder takes (handle, focused_status, target_status) so stale-row failures explain themselves to the operator"
    - "Retry hand-off pattern: a specific keypress clause that may or may not consume the event delegates to a private do_handle_key/2 helper for fall-through, instead of returning :no_match (which would short-circuit subsequent clauses)"

key-files:
  created: []
  modified:
    - "lib/foglet_bbs/accounts.ex"
    - "lib/foglet_bbs/tui/screens/sysop.ex"
    - "lib/foglet_bbs/tui/screens/sysop/users_view.ex"
    - "test/foglet_bbs/accounts/accounts_test.exs"
    - "test/foglet_bbs/tui/screens/sysop_test.exs"

key-decisions:
  - "D-14 placement: valid_status_transitions/1 sits adjacent to the private permit_status_transition/2 in lib/foglet_bbs/accounts.ex so the rules-source-of-truth invariant is visible at a glance"
  - "D-15 implementation: footer_text/1 + maybe_transition/3 use the same Accounts.valid_status_transitions/1 predicate, so footer advertising and keypress gating cannot diverge"
  - "D-16 source binding: from→to copy uses the focused row's *displayed* (potentially stale) source status, not the DB-side status returned by the boundary — the operator sees the same source in the error as they saw in the row"
  - "D-13 fall-through via do_handle_key/2: returning :no_match from the R-clause would short-circuit subsequent function clauses (Elixir does not auto-fall-through inside a function), so the R-clause delegates to a private helper instead"
  - "Existing 'invalid row action surfaces message' test (line 1077) was rewritten to assert the new no-op semantics — keypress is gated, message stays nil, no boundary call"
  - "Existing 'renders empty state' test (line 894) was updated to assert [j/k] Move (the only key advertised on empty rows) instead of [A] Approve"

# Metrics
duration: 11min
completed: 2026-04-27
---

# Phase 29 Plan 02: Retry, Forbidden Distinction & USERS From→To Copy Summary

**Operator-facing behaviors that complete SYSOP-02 and SYSOP-05: a public read-only predicate replaces UI-side mirrors of the transition graph, the USERS footer/keybinds gate per focused-row status, transition errors render as named from→to copy, and `[R] Retry` distinguishes itself from `[R] Reject` and from the forbidden tab through active-tab slot inspection.**

## Performance

- **Duration:** ~11 min (including TDD red/green for all three tasks)
- **Started:** 2026-04-27 ~20:56 UTC
- **Completed:** 2026-04-27 ~21:07 UTC
- **Tasks:** 3 (each TDD: red → green commit pair)
- **Files modified:** 5 (3 lib, 2 test)
- **Tests:** 21 new tests (4 valid_status_transitions, 9 keybind gating + 1 grep guard, 1 from→to + 1 grep, 8 retry advertising/dispatch — minus a couple of edits to existing tests). Full project suite: 1945 tests pass.

## Decision Locations

| Decision | Where it lives | Verification |
|----------|----------------|--------------|
| **D-13** advertising | `sysop.ex` `defp maybe_add_retry/2` (line 104) — appends an `Action` group only when `Map.get(ss, slot)` matches `{:error, reason} when reason != :forbidden` | `retry_advertising` describe (3 tests) |
| **D-13** dispatch | `sysop.ex` `def handle_key(%{key: :char, char: c} = event, state) when c in ["r", "R"]` (line 237) — flips slot to `:loading` and emits `dispatch_for(active_label)`; otherwise hands off to `do_handle_key/2` | `retry_dispatch` describe (5 tests) |
| **D-13** slot map | `sysop.ex` `defp slot_for/1` (4 tab→atom clauses) and `defp dispatch_for/1` (4 tab→tuple clauses) | per-tab dispatch test (BOARDS distinct from USERS) |
| **D-14** predicate | `lib/foglet_bbs/accounts.ex:217-220` — `def valid_status_transitions(:pending\|:active\|:suspended\|:rejected)`, placed immediately after the private `permit_status_transition/2` clauses (line 187-191) so the rules-source-of-truth invariant is visually obvious | `valid_status_transitions/1` describe in `test/foglet_bbs/accounts/accounts_test.exs` (4 cases) |
| **D-15** footer | `users_view.ex` `defp footer_text/1` (2 clauses — empty rows, general) — consults `Accounts.valid_status_transitions(focused_status)` | `users_keybind_gating` describe (4 advertising tests + empty-rows test) |
| **D-15** keypress gating | `users_view.ex` `defp maybe_transition/3` (2 clauses — empty rows, general) — checks `focused_status == required_from and target in Accounts.valid_status_transitions(focused_status)` | `users_keybind_gating` describe (3 no-op tests covering A on :active, U on :pending, S on :pending) |
| **D-16** copy builder | `users_view.ex` `defp invalid_transition_message/3` (line 287) — `"Cannot change @#{handle} from #{from} to #{to}."` | `users_from_to_copy` describe — stale-row injection asserts message format AND grep guard against rendered `"invalid_transition"` substring |
| **A2** disambiguation | `users_view.ex` four `handle_key/2` char-key clauses bind `required_from` per key (`A→:pending`, `R→:pending`, `S→:active`, `U→:suspended`) — same target `:active` for `A`/`U` distinguishes by source | `users_keybind_gating` test "pressing U on focused :pending row is a no-op (A2: source must be :suspended)" |

## Test Counts

| Describe | Count | Status |
|----------|-------|--------|
| `valid_status_transitions/1` (accounts_test.exs) | 4 | Green |
| `USERS keybind gating` | 8 | Green |
| `USERS from→to copy` | 2 | Green (1 stale-row injection + 1 grep guard) |
| `[R] Retry advertising` | 3 | Green |
| `[R] Retry dispatch` | 5 | Green |
| **New tests this plan** | **22** | **All green** |
| Full sysop_test.exs | 99 | All green |
| Full TUI suite | 1403 | All green |
| Full project suite | 1945 | All green |

## Confirmations

- **No rendered output contains `invalid_transition`** — verified by `users_from_to_copy` describe's grep guard. The substring appears only in the `{:error, :invalid_transition}` pattern-match (line 271) and the helper function name `invalid_transition_message/3` (lines 270, 287). String literals scanned by regex are zero.
- **`[R] Reject` on USERS still works on a focused `:pending` row** — preserved through the do_handle_key/2 hand-off pattern. The retry handler returns to `do_handle_key/2` (not `:no_match`) when the active tab is `{:loaded, _}`, so the event continues through Tabs.handle_event → delegate_to_active_tab → UsersView.handle_key → the `c in ["R", "r"]` clause, which routes through `maybe_transition(state, :pending, :rejected)`. Verified by the existing `USERS tab actions` "rejects pending users" test (line 1073) — passes with the new gating in place.
- **`R` on `:forbidden` tab is a no-op** — verified by `retry_dispatch` test "pressing R on USERS in {:error, :forbidden} is a no-op". The retry handler matches the `_` clause (since `:forbidden` is excluded by guard), hands off to `do_handle_key/2`, and Tabs ignores `R`, returning the state unchanged with no `{:load_sysop_*}` command.
- **Stale-row failures are user-explainable** — verified by the from→to test that persists a user as `:active` but injects a UsersView struct with the row tagged `:pending`. UI gate sees `:pending` source, allows `[A]`, boundary checks DB and rejects with `:invalid_transition`. Operator sees `Cannot change @stale_user from pending to active.` — the displayed source matches what the row showed.

## Task Commits

Each task was committed atomically (red + green pair):

1. **Task 1 (RED):** `fe577db` — `test(29-02): add failing tests for valid_status_transitions/1`
2. **Task 1 (GREEN):** `57fdd1f` — `feat(29-02): expose Foglet.Accounts.valid_status_transitions/1`
3. **Task 2 (RED):** `6a9ed4a` — `test(29-02): add failing tests for USERS keybind gating + from->to copy`
4. **Task 2 (GREEN):** `9fa8fdb` — `feat(29-02): gate USERS keybinds + render-time footer + from->to copy`
5. **Task 3 (RED):** `9c0b49a` — `test(29-02): add failing tests for [R] Retry advertising + dispatch`
6. **Task 3 (GREEN):** `af2181d` — `feat(29-02): advertise [R] Retry on errored active tab + R re-dispatch`

## Files Created/Modified

**Created:** none

**Modified:**
- `lib/foglet_bbs/accounts.ex` — Added `valid_status_transitions/1` (4 clauses + doctests + typespec) immediately after the private `permit_status_transition/2`. No other change to the module.
- `lib/foglet_bbs/tui/screens/sysop.ex` — Changed `sysop_commands/1` → `sysop_commands/2` (now takes `ss`); added `maybe_add_retry/2`, `slot_for/1` (4 + nil), `dispatch_for/1` (4); added a new `handle_key/2` clause for `c in ["r", "R"]` with retryable-error fast path and `do_handle_key/2` hand-off otherwise; extracted the broad `handle_key/2` body into a private `do_handle_key/2` helper.
- `lib/foglet_bbs/tui/screens/sysop/users_view.ex` — Removed the `@footer` constant; added render-time `footer_text/1` (2 clauses); replaced four char-key handlers with source-aware versions that delegate to `maybe_transition/3` (2 clauses); added a `{:error, :invalid_transition}` branch in `transition/2` that calls the new `invalid_transition_message/3` builder; dropped the `error_message(:invalid_transition)` clause.
- `test/foglet_bbs/accounts/accounts_test.exs` — New `valid_status_transitions/1` describe (4 tests) inserted between `transition_user_status/3` and `list_user_status_admin_targets/1` describes.
- `test/foglet_bbs/tui/screens/sysop_test.exs` — Three new describes: `[R] Retry advertising`, `[R] Retry dispatch`, `USERS keybind gating`, `USERS from→to copy` (16 new tests). Updated existing tests at lines 894 (empty state — now expects `[j/k] Move` not `[A] Approve`) and ~1077 ("invalid row action" — now asserts no-op semantics).

## Decisions Made

- **`R`-clause hand-off via `do_handle_key/2` (not `:no_match`).** Returning `:no_match` from a function clause would NOT fall through to subsequent `def handle_key/2` clauses — Elixir resolves clauses by pattern match, not by inspecting the return value. To preserve the existing `[R] Reject` keybind on a `{:loaded, _}` USERS tab, the retry-clause delegates to a private `do_handle_key/2` that contains the original broad-clause body. This is the cleanest way to express "first try retry; if not retryable, do the normal thing." Documented inline.
- **Stale-row from→to source binding.** When the boundary returns `{:error, :invalid_transition}`, the displayed source status (the row's tag, not `selected_user.status`) is bound into the message. This means a stale UsersView (row says `:pending` but DB has `:active`) produces `Cannot change @user from pending to active.` — consistent with what the operator just saw. This was a deliberate choice over `selected_user.status` (which would surface the DB truth and look confusing relative to the row).
- **The `users_from_to_copy` grep guard scans string literals only.** An earlier draft of the test inspected line content but flagged the helper function name `invalid_transition_message`. The correct semantic guard is "no string literal contains `invalid_transition`" — implemented via `Regex.scan(~r/"([^"\\]|\\.)*"/, contents)`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking] Deps + _build symlinks (worktree environment)**
- **Found during:** Task 1 startup
- **Issue:** Worktree had no `deps/` or `_build/` — `rtk mix test` would compile from scratch in an isolated environment, taking minutes.
- **Fix:** Symlinked `deps/` and `_build/` from the parent repo (same convention as Plan 01 used; both directories are gitignored).
- **Files modified:** None tracked.
- **Committed in:** None (filesystem-only).

**2. [Rule 1 — Bug] Initial retry-clause returned `:no_match`, breaking `[R] Reject`**
- **Found during:** Task 3 GREEN — full sysop_test.exs run after the new R-clause was added.
- **Issue:** The first GREEN draft returned `:no_match` from the retry clause when the slot was not retryable. This made `[R] Reject` in the existing `USERS tab actions` test (line 1073) fail because Elixir does not fall through to subsequent `def handle_key/2` clauses based on the return value of the first matching clause — the whole function returned `:no_match`.
- **Fix:** Extracted the broad `handle_key/2` body into a private `do_handle_key/2` helper. The retry clause calls `do_handle_key(event, state)` on the non-retryable path so the original broad-clause behavior runs.
- **Files modified:** `lib/foglet_bbs/tui/screens/sysop.ex`
- **Verification:** All 99 sysop_test.exs tests pass, including the previously-existing "rejects pending users" test that exercises the fall-through path.
- **Committed in:** `af2181d` (Task 3 GREEN)

**3. [Plan refinement] Test of "invalid row action" was rewritten, not removed**
- **Found during:** Task 2 RED setup
- **Issue:** The existing test at line 1077 (`"invalid row action surfaces message without mutating"`) hit the boundary's `{:error, :invalid_transition}` by selecting an active row and pressing R. After Task 2's gating, that keypress is a UI no-op — no boundary call, no message. The test would always fail in its old form.
- **Fix:** Rewrote the test to assert the new no-op semantics: `R` on a focused `:active` row leaves `current_users_view(state).message == nil` and the user's DB status unchanged. Renamed to "invalid row action is a no-op (Phase 29 D-15: pressing R on :active is gated)".
- **Files modified:** `test/foglet_bbs/tui/screens/sysop_test.exs`
- **Committed in:** `6a9ed4a` (Task 2 RED)

**4. [Plan refinement] Empty-state test updated for render-time footer**
- **Found during:** Task 2 RED setup
- **Issue:** The existing test at line 894 (`"renders empty state and key hints"`) asserted `[A] Approve` was advertised on an empty UsersView. After Task 2's render-time footer, an empty rows list returns `[j/k] Move` only.
- **Fix:** Updated the assertion from `[A] Approve` to `[j/k] Move`. Functionality preserved; expectation aligned with new D-15 contract.
- **Files modified:** `test/foglet_bbs/tui/screens/sysop_test.exs`
- **Committed in:** `9fa8fdb` (Task 2 GREEN)

**5. [Plan path correction] `accounts_test.exs` lives at `test/foglet_bbs/accounts/accounts_test.exs`, not `test/foglet_bbs/accounts_test.exs`**
- **Found during:** Task 1 placement scan
- **Issue:** The plan referred to `test/foglet_bbs/accounts_test.exs`. The actual file (containing the existing `transition_user_status/3` describe) lives at `test/foglet_bbs/accounts/accounts_test.exs`.
- **Fix:** Inserted the new describe in the correct file. No new file created.
- **Files modified:** `test/foglet_bbs/accounts/accounts_test.exs`
- **Committed in:** `fe577db` (Task 1 RED)

**6. [Plan refinement] Acceptance grep `char: c\\) when c in [...]` shape changed**
- **Found during:** Task 3 GREEN verification
- **Issue:** The plan's acceptance grep `char: c\\) when c in \\[\"r\", \"R\"\\]` expected the keypress clause to have shape `def handle_key(%{key: :char, char: c}, state) when c in ["r", "R"] do`. The actual implementation needs to bind the full event to forward to `do_handle_key/2`, so the head reads `def handle_key(%{key: :char, char: c} = event, state) when c in ["r", "R"] do`.
- **Fix:** None — the spirit of the criterion (R-clause exists) is met. The literal regex is one character off (extra `= event` binding before `, state`).
- **Verification:** `grep -nE 'char: c.*= event.* when c in \\["r", "R"\\]'` returns 1 line.

---

**Total deviations:** 6 (1 environmental, 1 bug auto-fix, 4 test/spec refinements that flow naturally from D-15 / D-13 contracts)
**Impact on plan:** None on scope; all deviations are mechanical adjustments to fit the existing codebase's conventions and the test idioms in place.

## Issues Encountered

- **Worktree base mismatch on startup.** `git merge-base HEAD <expected>` returned `3226ef9...` instead of the expected `a1f9dc6...`; recovered with `git reset --hard a1f9dc6...` (the prescribed worktree_branch_check protocol). No work lost.
- **No `deps/` or `_build/` in the worktree.** Symlinked from the parent repo (same as Plan 01).
- **`do_handle_key/2` extraction (deviation 2 above).** A non-obvious Elixir-semantics gotcha — `:no_match` is a return value, not a clause-fallthrough signal. The fix is straightforward but worth noting: any "may-or-may-not-consume-this-key" handler in a screen module needs the hand-off pattern.

## User Setup Required

None.

## Next Plan Readiness

- **Plan 03 (users-and-invites):** USERS gating substrate is in place. INVITES focus + `[X] Revoke` work can lay alongside the existing `delegate_to_invites/3` path without affecting the USERS-side keybinds.
- **Plan 04 (site-fields-and-jump):** Independent of this plan's substrate — `1-N Jump` work is purely render-side.

## Threat Flags

No new security-relevant surface introduced beyond what the threat model anticipates. T-29-05..T-29-08 mitigations all in place:

- **T-29-05 (Hidden keybind treated as authorization):** mitigated. The writer (`Accounts.transition_user_status/3` at `accounts.ex:249-274`) re-checks `permit_status_transition/2` regardless of UI gating. A malicious actor sending `transition_user_status(actor, user, :active)` directly still gets `{:error, :invalid_transition}` if the row is `:active`. Verified via the `users_from_to_copy` test which exercises this exact path (UI claims `:pending`, boundary rejects).
- **T-29-06 (`{:error, :forbidden}` panel as auth check):** mitigated. The forbidden panel is rendered AFTER the boundary returned `:forbidden` from `Accounts.list_user_status_admin_targets/1`. The UI does not gate the call.
- **T-29-07 (Stale `{:loaded, _}` after role demotion):** accepted. Same as T-29-02 in Plan 01. SYSOP-FUT-01 (background prefetch) deferred. The `[R] Retry` keybind is the manual recovery path.
- **T-29-08 (Error message reveals user handle):** accepted. The handle is already visible in the focused row; the from→to copy reveals nothing the operator did not already see. Documented in the threat register.

## Self-Check: PASSED

All claimed files exist; all task commits present in `git log`.

```
FOUND: lib/foglet_bbs/accounts.ex
FOUND: lib/foglet_bbs/tui/screens/sysop.ex
FOUND: lib/foglet_bbs/tui/screens/sysop/users_view.ex
FOUND: test/foglet_bbs/accounts/accounts_test.exs
FOUND: test/foglet_bbs/tui/screens/sysop_test.exs
FOUND: fe577db — test(29-02): add failing tests for valid_status_transitions/1
FOUND: 57fdd1f — feat(29-02): expose Foglet.Accounts.valid_status_transitions/1
FOUND: 6a9ed4a — test(29-02): add failing tests for USERS keybind gating + from->to copy
FOUND: 9fa8fdb — feat(29-02): gate USERS keybinds + render-time footer + from->to copy
FOUND: 9c0b49a — test(29-02): add failing tests for [R] Retry advertising + dispatch
FOUND: af2181d — feat(29-02): advertise [R] Retry on errored active tab + R re-dispatch
```

---
*Phase: 29-sysop-tab-lifecycle-bodies*
*Completed: 2026-04-27*
