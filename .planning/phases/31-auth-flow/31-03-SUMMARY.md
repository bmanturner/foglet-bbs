---
phase: 31-auth-flow
plan: 03
subsystem: tui
tags: [elixir, raxol, tui, login, reset-consume, password-reset, atomic-token]

# Dependency graph
requires:
  - phase: 31-auth-flow
    provides: "Verification.consume_reset_token/2 (Plan 31-01)"
  - phase: 31-auth-flow
    provides: "Login.State.reset_request with message/message_category fields and [T] discovery hint (Plan 31-02)"
  - phase: 27-cursor-breadcrumb-polish
    provides: ":reset_consume breadcrumb mapping (Foglet / Forgot Password / Enter Token)"
provides:
  - "Login.State.reset_consume/0 inline sub-state with token/password/password_confirmation TextInput fields"
  - "Login.State.input_key/1 mapping for :token and :password_confirmation"
  - "Login.State.next_reset_consume_focus/1 and prev_reset_consume_focus/1 deterministic focus cycle"
  - "Login.handle_reset_consume_key/2 handling Tab, :backtab, :shift_tab, :enter, :escape, and char passthrough"
  - "Login.render_reset_consume/2 three-row form (token unmasked; password fields masked) with generic inline error copy"
  - "Login.submit_reset_consume/1 calling Verification.consume_reset_token/2 with local mismatch gate"
  - "[T] Reset token menu key entry (D-15 from-menu path)"
  - "T/t in :reset_request handler advancing into :reset_consume (D-15 from-reset-request path)"
  - "Generic, non-leaking error copy for invalid/malformed/expired/already-used tokens (D-10)"
affects:
  - 31-04-layout-smoke-and-non-leak

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Local validation gate (password match) before Accounts boundary call: keeps token row intact when the failure can be detected client-side"
    - "Generic-edge consume errors: invalid/malformed/expired/already-used all collapse to one user-visible string so the screen never leaks token failure mode"
    - "FocusInput-based char routing extended to a 3-field form via input_key/1 — no per-key special casing in handle_reset_consume_key/2"
    - "Symmetric Tab/:backtab focus helpers in State so cycle direction is the single source of truth"
    - "Insert-before-Q menu key composition that lets short labels survive the chrome priority-based command-bar drop logic at 80x24"

key-files:
  created: []
  modified:
    - "lib/foglet_bbs/tui/screens/login/state.ex — added reset_consume/0, input_key/1 for :token and :password_confirmation, next_reset_consume_focus/1, prev_reset_consume_focus/1; updated moduledoc"
    - "lib/foglet_bbs/tui/screens/login.ex — added :reset_consume routing in render/handle_key, T/t menu and reset-request entry, handle_reset_consume_key/2 with tab/backtab/shift_tab/enter/escape, render_reset_consume/2 with field labels and generic error rendering, submit_reset_consume/1 calling Verification.consume_reset_token/2, keys_for(:reset_consume, _), add_reset_consume_key/1 menu composer, three @reset_consume_* error/copy attributes"
    - "test/foglet_bbs/tui/screens/login_test.exs — 19 new tests covering entry from both paths, masked-vs-unmasked field initialization, Tab/:backtab focus cycle, character-into-focused-input routing, password mismatch -> token preserved, success -> menu + state cleared + password updated + token consumed, invalid token -> generic error, malformed-equals-unknown error parity, raw-token-never-leaks (chrome/breadcrumb/key hints), Escape clears all field state"

key-decisions:
  - "Local password-vs-confirmation match gate runs BEFORE Verification.consume_reset_token/2 so a typo in the second password field does not consume the user's only reset token. Tests verify the token row remains in the database after a mismatch."
  - "Generic invalid_or_expired copy ('That reset token did not work. Ask the sysop for a new one.') is byte-identical for malformed, unknown, expired, and already-used tokens. Tests assert err_unknown == err_malformed AND that the copy contains none of {expired, already-used, malformed} so a future copy change cannot accidentally start leaking failure mode."
  - "Three concrete focus atoms (:token, :password, :password_confirmation) instead of an indexed list. State.next_reset_consume_focus/1 and prev_reset_consume_focus/1 own cycle direction; render and handle_key consume both helpers and never special-case keys themselves. This pattern matches the existing toggle_focus/1 for :handle <-> :password and stays inside the established Login focus pattern (D-04, D-06)."
  - "Menu key label is 'Reset token' (12 chars), not 'Enter reset token' (17 chars), so [T] survives alongside [F] Forgot password in the 80x24 chrome command bar. CommandBar drops by descending {priority, order} in the Actions group; both labels classify into Actions priority 30 with Q in the system group, and at full width the Actions row would otherwise overflow at 80 cols and silently drop [T]. The longer 'Enter reset token' phrase is preserved in the no-email message body and in keys_for(:reset_request, _) where Plan 31-02 already established the affordance."
  - "Both :backtab and :shift_tab keys map to the same prev-focus behavior. Different terminals send Shift+Tab as one or the other; matching both keeps focus reverse working under SSH clients and the test harness (existing Foglet forms in account/profile_form.ex use the same pattern)."
  - "Successful consume returns to LoginState.default/0 (just %{sub: :menu}) rather than to a confirmation screen. D-07 specifies 'returns to the logged-out Login menu' and any inline 'Password updated' confirmation would either persist into the menu and risk leaking timing/identity info or require a separate sub-state. Returning to a clean menu matches the SSH-first / no-modal terminal idiom."
  - "Password-changeset failure (rare given a successful token consume) produces generic 'Your new password is not acceptable.' copy and stays on the form. Foglet.Accounts.Verification.consume_reset_token/2 is a single Repo.transact/1, so a changeset failure rolls back the token claim and the user can retry without obtaining a new token from the sysop."

patterns-established:
  - "Three-field inline form with deterministic forward/backward focus cycle, reusable for any future Login auth form that needs more than handle/password and that should stay inline rather than escalate to Modal.Form."
  - "Local-gate-before-boundary submission pattern: when a validation can be done with screen-only state (e.g., field equality) AND the boundary call has a single-use side effect, gate locally first so transient typos do not burn a token."

requirements-completed:
  - AUTH-03
  - AUTH-04

# Metrics
duration: ~15min
completed: 2026-04-28
---

# Phase 31 Plan 03: Login :reset_consume Sub-state Summary

**Logged-out users can now consume an operator-issued raw reset token through the Login screen's inline `:reset_consume` form, which routes through `Verification.consume_reset_token/2` for atomic single-use semantics, surfaces only generic errors for any token failure, and never echoes the raw token through chrome/keys/breadcrumb surfaces.**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-04-28T00:06:27Z
- **Completed:** 2026-04-28T00:21:42Z
- **Tasks:** 2/2
- **Files modified:** 3 (2 lib, 1 test)

## Accomplishments

- `Foglet.TUI.Screens.Login.State.reset_consume/0` returns a fresh
  three-field sub-state with focused_field on :token, the token field
  unmasked, and both password fields masked with `*`. Each entry into
  :reset_consume builds new `TextInput` structs so no field value
  carries across visits (D-04, D-05).
- `Login.State.input_key/1` now maps `:token`, `:password`, and
  `:password_confirmation` to their concrete input keys, allowing the
  existing `FocusInput.get_focused/3` and `update_focused/4` helpers to
  route every non-control key into the focused TextInput without
  special-casing keys per field.
- `Login.State.next_reset_consume_focus/1` and `prev_reset_consume_focus/1`
  encode the focus cycle as the single source of truth. `Login.handle_reset_consume_key/2`
  handles `:tab`, `:backtab`/`:shift_tab`, `:enter`, `:escape`, and
  forwards everything else through `FocusInput`. Focus cycle is
  `:token -> :password -> :password_confirmation -> :token` forward and
  `:token -> :password_confirmation -> :password -> :token` reverse
  (D-06).
- `Login.render_reset_consume/2` renders three field rows (Token, New
  password, Confirm password) with the focused label highlighted via
  `theme.accent.fg` and `[:bold]`. Inline error rendering reuses the
  same `wrapped_text_rows/3` helper Plan 31-02 introduced, so a long
  error message wraps correctly under compact terminal sizes.
- `[T] Reset token` is reachable from the Login menu (`handle_menu_key/2`
  matches both `T` and `t`) and from the `:reset_request` flow
  (`handle_reset_key/2` captures `T`/`t` before its catch-all char
  passthrough). The menu key label is intentionally short ("Reset token"
  rather than "Enter reset token") so it fits in the 80x24 command bar
  alongside `[F] Forgot password` without being dropped by the chrome
  priority-based truncation; the longer "Enter reset token" phrase is
  preserved in the no-email message body and the reset_request key
  hints where Plan 31-02 already established it (D-15).
- `Login.submit_reset_consume/1` does a local password-confirmation
  match check first; on mismatch the form sets a generic
  `"Passwords do not match. Re-enter the new password."` error and does
  *not* call into Accounts. On match the function calls
  `Verification.consume_reset_token(raw_token, %{password: new_password})`.
  The three return shapes from Plan 31-01 map to UX as follows:
  - `{:ok, %User{}}` -> `LoginState.default/0` (returns to the
    logged-out menu and drops every field) (D-07).
  - `{:error, :invalid_or_expired}` -> generic copy that does *not*
    distinguish invalid / malformed / expired / already-used (D-10).
  - `{:error, %Ecto.Changeset{}}` -> generic password-not-acceptable
    copy; the token claim was rolled back inside the Accounts
    transaction so the user can retry without re-requesting a token.
- Raw token values stay only inside the focused token TextInput buffer.
  The keys_for hints (`Tab` / `Shift+Tab` / `Enter` / `Esc`), the form
  title (`Enter reset token`), the breadcrumb
  (`Foglet > Forgot Password > Enter Token`), and every error string
  are derived solely from sub-state and never embed the field value
  (D-11). A dedicated test renders the form with a sentinel token
  string and asserts the breadcrumb and every key-hint-bearing
  rendered text node does not contain that sentinel.

## Task Commits

Each task was committed atomically with `--no-verify`
(parallel-executor mode):

1. **Task 1 (TDD RED): Failing :reset_consume tests** — `da5a9a5` (test)
   - 19 new tests added across three describe blocks
     (`reset_consume entry`, `reset_consume focus`,
     `reset_consume submission`). Pre-implementation: 72 tests, 20
     failures (the 19 new tests plus the modified Plan 31-02 [T] route
     test). One failure was the existing [T] route test from Plan 31-02
     that this plan tightens from "either :update or :no_match" to
     "must transition to :reset_consume".
2. **Task 2 (TDD GREEN): Implementation** — `c4fd553` (feat)
   - Production wiring across `login/state.ex` and `login.ex`. Tests
     post-implementation: 72 tests, 0 failures. Plan verification
     command (`accounts/verification_test.exs` + Login tests) reports
     89/89 green. Broader TUI suite (`test/foglet_bbs/tui/`) reports
     1465/1465 green — no regressions.

## Files Created/Modified

- `lib/foglet_bbs/tui/screens/login/state.ex` — added `reset_consume/0`,
  extended `input_key/1` for `:token` and `:password_confirmation`,
  added `next_reset_consume_focus/1` and `prev_reset_consume_focus/1`.
  Updated the moduledoc to document the new sub-state shape.
- `lib/foglet_bbs/tui/screens/login.ex` — added `@reset_consume_*` copy
  attributes (3), wired `:reset_consume` into `render/1` and
  `handle_key/2` dispatch, added T/t handling in `handle_menu_key/2`
  and `handle_reset_key/2`, added `handle_reset_consume_key/2` for tab
  / backtab / shift_tab / enter / escape / char passthrough, added
  `render_reset_consume/2` and `field_label/3`, added
  `submit_reset_consume/1` calling
  `Verification.consume_reset_token/2`, added `enter_reset_consume/1`,
  added `keys_for(:reset_consume, _)`, added `add_reset_consume_key/1`
  to the menu composer.
- `test/foglet_bbs/tui/screens/login_test.exs` — added
  `reset_consume_state/1` helper, three new describe blocks
  (`reset_consume entry (D-15)`, `reset_consume focus (D-06)`,
  `reset_consume submission (D-07, D-10, D-11)`) totaling 19 tests.
  Tightened the Plan 31-02 `[T] enters reset_consume sub-state` test
  from a permissive "either result" assertion to a strict
  `assert sub == :reset_consume` assertion.

## Decisions Made

- **Local match gate before the boundary:** the only client-side-detectable
  failure for this form is password-vs-confirmation. Plan 31-01 made
  consume single-use, so a typo in the confirmation field that reached
  the boundary would burn the user's only token. Gating locally first
  preserves the row and matches the spirit of "specific side effects,
  generic edge" — local validation does not need to be generic because
  the user already proved possession of a real token to get this far.
- **Generic copy for every token failure mode:** the Plan 31-01
  boundary returns one `{:error, :invalid_or_expired}` atom for
  unknown / malformed / expired / already-used. The screen treats this
  as a single user-visible string. A dedicated test asserts the
  rendered copy contains none of {`expired`, `already-used`,
  `malformed`} so future copy edits cannot accidentally re-introduce
  failure-mode disclosure (D-10).
- **`:backtab` and `:shift_tab` both map to prev-focus:** the
  Foglet codebase already accepts both atoms in
  `account/profile_form.ex` and `account/prefs_form.ex` because
  different SSH clients send Shift+Tab differently. Implementing both
  here keeps reverse focus working across the full client matrix
  without needing to inspect the actual term info.
- **Three concrete focus atoms instead of an index/list:** atoms
  preserve readability in tests, error messages, and stack traces, and
  pattern-match cleanly in `next_reset_consume_focus/1` /
  `prev_reset_consume_focus/1`. An indexed list would have required
  every consumer to know the field order, contradicting D-06's
  emphasis on the established Login focus pattern.
- **Successful consume returns to `:menu` rather than to a
  confirmation screen:** D-07 explicitly says "successful consumption
  also returns to the logged-out Login menu". Any inline confirmation
  on the menu would either persist (and leak that *someone* just
  changed a password) or require a separate `:reset_consume_done`
  state that adds complexity without unlocking new flows. The user
  immediately sees the standard menu, which is the same surface they
  saw pre-consume — the security model is "no signal at all about
  what happened".
- **Menu key label is "Reset token", not "Enter reset token":** the
  80x24 chrome command bar drops Actions-group keys by descending
  `{priority, order}` when `rendered_width > inside_width - 2`. Both
  `[F] Forgot password` and `[T] Enter reset token` would push total
  rendered width to ~78 cols, just over the 76-col budget at 80x24.
  Shortening the menu key label to "Reset token" keeps the total at
  ~72 cols so both keys survive. The longer phrase is preserved
  everywhere it matters for discoverability — the Plan 31-02 no-email
  message body, the `:reset_request` key hint set, and the form title
  in the rendered :reset_consume view itself.
- **Always rebuild the form on entry:** `enter_reset_consume/1` calls
  `LoginState.reset_consume/0` unconditionally, never reusing prior
  state. Repeated visits cannot leak partial token text or stale
  passwords across users on a shared SSH endpoint, and the cost is one
  small allocation per entry.

## Deviations from Plan

**Auto-fixed Issues**

1. **[Rule 3 - Blocking] Menu key label width forced re-tuning.**
   - **Found during:** Task 2 GREEN run.
   - **Issue:** with `[F] Forgot password` and `[T] Enter reset token`
     both classified as Actions priority 30, the chrome command bar
     truncated `[T]` at 80x24 because the combined rendered width of
     `Q Quit  Actions  L Login  R Register  F Forgot password  T Enter reset token`
     was 78 cells against a ~76-col budget.
   - **Fix:** shortened the menu-key label from "Enter reset token"
     to "Reset token" (-5 chars). The longer phrase is preserved in
     the no-email message body, the `:reset_request` key hints, and
     the form title — every other surface that Plan 31-02 already
     anchored on the longer phrase.
   - **Files modified:** `lib/foglet_bbs/tui/screens/login.ex` (label
     value), `test/foglet_bbs/tui/screens/login_test.exs` (test
     assertion updated to match the new label).
   - **Commit:** rolled into the GREEN commit `c4fd553`.

The plan's task 1 RED step was tightened slightly: the Plan 31-02
`[T] enters reset_consume sub-state` test was permissive
(`assert match?({:update, _, _}, result) or result == :no_match`) so it
passed even when [T] was not yet wired. Plan 31-03's RED step replaces
this with a strict assertion that the resulting sub-state is
`:reset_consume`. This is the planned tightening, not a deviation.

## Issues Encountered

- **Edit/Write tool returned success without modifying `lib/`-tree
  files.** Initial Edits to `lib/foglet_bbs/tui/screens/login.ex` and
  `lib/foglet_bbs/tui/screens/login/state.ex` reported success but
  did not change the on-disk files (verified via stat mtime, git
  status, and direct `grep`). The Read tool returned the *intended*
  modifications even though the disk was unchanged, so the
  discrepancy was only visible by running the test suite.
  Workaround: use the Write tool to stage updated content under
  `/tmp/`, then `cp` the staged file into `lib/...`. This pattern
  was confirmed reliable for both files. Note for future executors
  in this worktree shape: prefer `cp`-from-`/tmp/` for files under
  `lib/`. Test files (e.g.,
  `test/foglet_bbs/tui/screens/login_test.exs`) were affected too;
  the same pattern resolved them.
- **Worktree dependency hydration:** the executor worktree starts
  with no `deps/` directory. Resolved by symlinking the parent
  `deps/` (read-only consumption). `_build/` was rebuilt from
  scratch; this is a one-time per-worktree cost and avoids
  concurrent-compile races with sibling agents.

## Threat Model Compliance

| Threat ID | Disposition | Status |
|-----------|-------------|--------|
| T-31-07 (Information Disclosure, reset-consume errors) | mitigate | Mitigated — `consume_reset_token/2` returns one atom for invalid/malformed/expired/already-used, and the screen renders the same `@reset_consume_invalid_or_expired_message` for every such return. A test asserts byte-equality of the error string between an unknown-token and a malformed-token submission, plus negative checks for the words `expired`, `already-used`, and `malformed` in the rendered copy. |
| T-31-08 (Information Disclosure, chrome/status/command hints) | mitigate | Mitigated — `keys_for(:reset_consume, _)` derives only from the sub-state atom, never from field values. Breadcrumb is generated by `BreadcrumbBar.login_parts/1` from `:sub` (Phase 27 contract). A dedicated test renders the form with a sentinel token, then asserts that no rendered text node containing `Tab` / `Shift+Tab` / `Enter` / `Esc` and that no breadcrumb-bearing node contain the sentinel string. Plan 31-04 will add 64x22 layout-smoke non-leak coverage. |
| T-31-09 (Tampering, reset-consume submit) | mitigate | Mitigated — `submit_reset_consume/1` exclusively calls `Verification.consume_reset_token/2`; no `Repo` or `User`-direct calls live in `Login`. The local mismatch gate only consults screen-local field values; if it short-circuits, no Accounts call is made and no row state changes. |

## TDD Gate Compliance

- RED commit (`da5a9a5`, `test(...)`): present and observed 20
  failures across 19 new tests + 1 tightened Plan 31-02 test before
  any implementation.
- GREEN commit (`c4fd553`, `feat(...)`): present and follows the RED
  commit; full Login test file passes 72/72; plan verification command
  (`accounts/verification_test.exs` + `login_test.exs`) passes 89/89.
- REFACTOR commit: not needed — implementation landed in its first
  green form once the menu key label width was tuned (the tuning was
  done in-flight and folded into the GREEN commit rather than as a
  separate refactor).

## Verification

- `rtk mix test test/foglet_bbs/tui/screens/login_test.exs`:
  72 tests, 0 failures.
- `rtk mix test test/foglet_bbs/accounts/verification_test.exs test/foglet_bbs/tui/screens/login_test.exs`:
  89 tests, 0 failures (plan verification command).
- `rtk mix test test/foglet_bbs/tui/`:
  1465 tests, 0 failures (full TUI suite, no regressions).

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Plan 31-04 (layout smoke + non-leak) now has a stable
  `:reset_consume` surface to test. The breadcrumb mapping
  (`Foglet > Forgot Password > Enter Token`) was already in place from
  Phase 27. The reset-consume rendering uses the same wrap-width budget
  as the reset-request flow, so a 64x22 smoke case can reuse the
  pattern Plan 31-02 established.
- Plan 31-04 should add chrome non-leak tests at 64x22 with a
  sentinel raw token in the focused field, asserting that:
  (a) the breadcrumb does not contain the token,
  (b) the keys row does not contain the token,
  (c) the form title row does not contain the token, and
  (d) the error row, when populated, does not contain the token.
- The `Login.handle_key/2` dispatch table now sees `:reset_consume`
  alongside `:login_form` and `:reset_request`. Future auth sub-states
  (e.g., a hypothetical `:resend_verification`) can drop in by adding
  one more case-arm and one more `handle_*_key/2` clause without
  touching the existing branches.

## Self-Check: PASSED

Verified post-write:
- `lib/foglet_bbs/tui/screens/login.ex` — present (701 lines)
- `lib/foglet_bbs/tui/screens/login/state.ex` — present (138 lines)
- `test/foglet_bbs/tui/screens/login_test.exs` — present (1250 lines)
- `.planning/phases/31-auth-flow/31-03-SUMMARY.md` — present
- Commit `da5a9a5` (RED) — present in git log
- Commit `c4fd553` (GREEN) — present in git log

---
*Phase: 31-auth-flow*
*Completed: 2026-04-28*
