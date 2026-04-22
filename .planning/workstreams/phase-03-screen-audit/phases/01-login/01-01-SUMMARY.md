---
phase: 01-login
plan: 01
subsystem: ui
tags: [tui, elixir, textinput, raxol, login, with-chain, screen-audit]

# Dependency graph
requires:
  - phase: 00-cross-cutting-extractions-prelude
    provides: Theme.from_state/1, TextInput bordered:false option, AUDIT rubric baseline

provides:
  - Login screen refactored: TextInput adoption, flat state shape, with-chain auth
  - init_screen_state/1 added to Login (AUDIT-19)
  - Key routing pattern (D-06) precedent for Phase 2 (Register) and Phase 7 (NewThread)
  - Inline label+TextInput row layout (D-02) precedent for downstream phases
  - input_key/1 helper mapping :handle/:password focused_field atoms to map keys

affects:
  - phase: 02-register (inherits D-02/D-04/D-06/D-14 patterns)
  - phase: 07-new-thread (inherits D-02/D-06 patterns)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "D-06 key routing: screen intercepts Tab/Enter/Escape, delegates char/backspace/cursor to TextInput"
    - "D-04 flat login sub-state: handle_input/password_input/error at top level, no nested form map"
    - "D-02 inline label+TextInput row: text label + TextInput.render(bordered:false) in row with gap:0"
    - "D-03 lazy TextInput init: structs created in enter_login_form/1, init_screen_state returns %{sub: :menu}"
    - "D-08 with-chain auth: authenticate first, then :active status guard, then dispatch on post_login_screen"
    - "TextInput cursor placement: use TextInput.handle_event(%{key: :end}, ti) in tests to seed pre-typed values"

key-files:
  created: []
  modified:
    - lib/foglet_bbs/tui/screens/login.ex
    - test/foglet_bbs/tui/screens/login_test.exs

key-decisions:
  - "with chain uses :active status guard as second clause rather than wrapping post_login_screen in {:ok,_} — post_login_screen/1 returns atom directly"
  - "input_key/1 helper introduced to map :handle/:password focused_field atoms to :handle_input/:password_input map keys"
  - "test form_state/2 helper uses text_input_at_end/1 to position cursor after seeded value, matching real user behavior"
  - "line count target (120-180) not met due to preserved maybe_register/start_verify_flow/moduledoc expansion; behavior goal met"

patterns-established:
  - "D-06 key routing: screen intercepts Tab/Enter/Escape; delegates everything else to focused TextInput"
  - "D-02 inline row layout: text label + TextInput.render(bordered:false, theme:theme) inside row style:%{gap:0}"
  - "D-14 lazy init: init_screen_state/1 returns %{sub: :menu}; TextInput structs created lazily in enter_login_form/1"
  - "Test pattern: seed TextInput value, then send :end event to position cursor, then run test events"

requirements-completed: [LOGIN-01, LOGIN-02, LOGIN-03, LOGIN-04, LOGIN-05, LOGIN-06]

# Metrics
duration: ~60min
completed: 2026-04-21
---

# Phase 01 Plan 01: Login Screen Audit Summary

**Login screen refactored from 347 to 340 lines by adopting TextInput widgets with flat state shape, key routing pattern (D-06), and with-chain auth; all 6 hand-rolled form helpers deleted**

## Performance

- **Duration:** ~60 min
- **Started:** 2026-04-21T16:30:00Z
- **Completed:** 2026-04-21T17:31:40Z
- **Tasks:** 4 (1a, 1b, 2, 3)
- **Files modified:** 2

## Accomplishments

- Deleted all 6 hand-rolled form plumbing functions (`format_input_line`, `input_fg`, `focus_style`, `mask_password`, `drop_last_grapheme`, `append_to_focused`) per LOGIN-02
- Added `init_screen_state/1` returning `%{sub: :menu}` per AUDIT-19/D-03; TextInput structs created lazily in `enter_login_form/1`
- Rewrote `handle_form_key/2` family following D-06 key routing pattern: Tab/Enter/Escape intercepted, all other events delegated to focused TextInput
- Rewrote `render_login_form/2` to use inline `text` label + `TextInput.render(bordered:false)` row layout per D-02
- Rewrote `submit_login/1` as `with` chain: authenticate → guard `:active` status → dispatch via `handle_auth_success/3` per D-08
- Updated moduledoc to document Config.get safety (D-07), new state shape (D-04), and `init_screen_state/1` (AUDIT-19)
- Updated all 30 tests to use flat TextInput state shape; added 2 `init_screen_state/1` tests; all pass

## Task Commits

Each task was committed atomically:

1. **Tasks 1a + 1b + 2: Login screen rewrite** - `105f724` (refactor)
2. **Task 3: Test updates** - `fe6e733` (test)

**Plan metadata:** committed with SUMMARY (docs)

## Files Created/Modified

- `/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/screens/login.ex` — Full rewrite: TextInput adoption, flat state, D-06 routing, D-08 with-chain auth, init_screen_state/1, moduledoc expansion
- `/Users/brendan.turner/Dev/personal/foglet_bbs/test/foglet_bbs/tui/screens/login_test.exs` — Updated all tests to flat TextInput state shape; added init_screen_state/1 describe block; added text_input_at_end/1 helper

## Decisions Made

- `post_login_screen/1` returns `:verify | :main_menu` directly (not `{:ok, screen}`), so the `with` chain uses `:active <- user.status` as the second guard clause rather than a second `with` arm on post_login_screen. Plan's suggested `{:ok, screen} <- Accounts.post_login_screen(user)` was incorrect.
- Added `input_key/1` helper (`defp input_key(:handle), do: :handle_input`) to map the `focused_field` atom (`:handle`/`:password`) to the corresponding map key (`:handle_input`/`:password_input`). This was required because the plan's `focused_input/1` used `Map.get(login_ss, focused)` directly which would look up key `:handle` instead of `:handle_input`.
- Test `form_state/2` helper applies `text_input_at_end/1` (sends `:end` event to TextInput) after seeding values. This is required because `TextInput.init(value: "al")` places the cursor at position 0, not end, so subsequent typing inserts at position 0. The `:end` event moves the cursor to the correct end position, matching real user behavior.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed focused_input/1 and update_focused_input/2 mapping :handle → :handle_input**
- **Found during:** Task 1b (TextInput adoption)
- **Issue:** The plan's suggested `focused_input/1` used `Map.get(login_ss, focused)` where `focused` is `:handle`, but the key in the map is `:handle_input`. This caused `nil` to be passed to `TextInput.handle_event/2`, crashing on char input.
- **Fix:** Added `input_key/1` private helper; `focused_input/1` and `update_focused_input/2` call `input_key(focused)` to get the correct map key.
- **Files modified:** `lib/foglet_bbs/tui/screens/login.ex`
- **Verification:** All typing/backspace tests pass
- **Committed in:** `105f724`

**2. [Rule 1 - Bug] Fixed submit_login/1 with-chain for post_login_screen return type**
- **Found during:** Task 2 (with-chain rewrite)
- **Issue:** Plan suggested `{:ok, screen} <- Accounts.post_login_screen(user)` but `post_login_screen/1` returns the atom `:verify | :main_menu` directly. The with clause raised `WithClauseError`.
- **Fix:** Changed second with clause to `:active <- user.status`, then calls `Accounts.post_login_screen(user)` directly in the success block. `else` branches match `:pending` and `:suspended` atoms.
- **Files modified:** `lib/foglet_bbs/tui/screens/login.ex`
- **Verification:** All auth flow tests pass including verify/main_menu routing
- **Committed in:** `105f724`

**3. [Rule 1 - Bug] Fixed test form_state/2 cursor positioning for pre-seeded TextInput values**
- **Found during:** Task 3 (test updates)
- **Issue:** `TextInput.init(value: "al")` sets cursor to position 0. Typing "ice" inserts at pos 0 each time, giving `"iceal"` instead of `"alice"`. Backspace at pos 0 is a no-op.
- **Fix:** Added `text_input_at_end/1` helper that sends `%{key: :end}` event to move cursor to end. Applied in `form_state/2` to both handle and password inputs after init.
- **Files modified:** `test/foglet_bbs/tui/screens/login_test.exs`
- **Verification:** All 30 tests pass
- **Committed in:** `fe6e733`

---

**Total deviations:** 3 auto-fixed (all Rule 1 bugs)
**Impact on plan:** All fixes were necessary for correctness. The plan's code snippets had two concrete bugs (wrong map key lookup, wrong with-clause pattern). No scope creep.

### Line Count Deviation

The plan specified `min_lines: 120, max_lines: 180`. The resulting file is 340 lines.

Root cause: The 120-180 target was based on deleting ~70 lines of hand-rolled helpers. However:
- `maybe_register/1` + `first_step_for_mode/1` (~25 lines): preserved per plan ("unchanged")
- `start_verify_flow/2` (~25 lines): preserved per plan ("unchanged")
- `maybe_log_verify_code` compile-time conditional (~10 lines): preserved per plan
- Moduledoc expanded from ~19 to ~32 lines (per plan requirements for D-07/AUDIT-19 docs)
- New `input_key/1` helper (+5 lines): required by Rule 1 bug fix

The file is shorter than the original (340 vs 347 lines), all behavior is preserved, and the hand-rolled plumbing is fully eliminated. The line count target was not achievable without deleting preserved functions.

## Issues Encountered

None beyond the 3 auto-fixed bugs documented above.

## Next Phase Readiness

- D-06 key routing pattern is documented and ready to be inherited by Phase 2 (Register) and Phase 7 (NewThread)
- D-02 inline label+TextInput row layout is established and ready for reuse
- D-04 flat state shape pattern (handle_input/password_input/error) is the canonical form for two-field forms
- `text_input_at_end/1` test helper pattern documented for Phase 2 and 7 test authors

## Known Stubs

None — all behaviors are wired end-to-end with real TextInput structs and live auth calls.

## Threat Flags

No new network endpoints, auth paths, file access patterns, or schema changes introduced. This plan is a UI refactor only; authentication logic is unchanged.

## Self-Check: PASSED

- `lib/foglet_bbs/tui/screens/login.ex` — EXISTS, 340 lines
- `test/foglet_bbs/tui/screens/login_test.exs` — EXISTS, 30 tests passing
- Commit `105f724` — EXISTS (refactor: login screen rewrite)
- Commit `fe6e733` — EXISTS (test: test updates)
- All AUDIT-05 grep gates — ZERO matches confirmed
- `mix precommit` — PASSED (0 issues, dialyzer 74 skips all pre-existing)

---
*Phase: 01-login*
*Completed: 2026-04-21*
