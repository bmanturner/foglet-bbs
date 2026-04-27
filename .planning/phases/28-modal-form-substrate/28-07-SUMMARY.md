---
phase: 28-modal-form-substrate
plan: 07
subsystem: ui
tags: [tui, raxol, modal, form, validation, defensive-programming]

# Dependency graph
requires:
  - phase: 28-modal-form-substrate
    provides: Modal.Form widget (init/1, handle_event/2, focus navigation rem(_, n) clauses)
provides:
  - Modal.Form.init/1 raises ArgumentError with deterministic message when :fields is empty
  - Replaces latent ArithmeticError (rem(_, 0)) crash mode with init-time guard
  - Unit test asserting the raise pattern (form_test.exs BL-03 describe block)
affects: [phase-28 verification re-run, future Modal.Form callers, Sysop SiteForm visibility rules]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Init-time argument validation: raise ArgumentError with a literal-string message before constructing widget structs, instead of allowing downstream rem/division operations to surface obscure ArithmeticError later"

key-files:
  created: []
  modified:
    - lib/foglet_bbs/tui/widgets/modal/form.ex
    - test/foglet_bbs/tui/widgets/modal/form_test.exs

key-decisions:
  - "Validate at init/1 (single guard) rather than per-clause guards in handle_event focus navigation — one obvious raise site, no scattered defensive checks in event-dispatch paths"
  - "Use exact literal message 'Modal.Form requires at least one field; received an empty :fields list' to satisfy the BL-03 grep gate and keep the message useful for debugging"
  - "Follow existing form.ex convention: this is the second `raise ArgumentError` in the file (set_submit_state/2 already raises for :submitting)"

patterns-established:
  - "BL-03 init-time guard pattern: when a widget's later event-handling code uses rem/length over a caller-supplied list, validate non-empty at construction so the crash mode is a message-bearing ArgumentError, not a downstream ArithmeticError"

requirements-completed: [FORM-04]

# Metrics
duration: 8min
completed: 2026-04-27
---

# Phase 28 Plan 07: Modal.Form.init/1 empty-fields guard (BL-03) Summary

**Modal.Form.init/1 now raises ArgumentError with the message "Modal.Form requires at least one field; received an empty :fields list" when :fields is empty, replacing a latent ArithmeticError in focus navigation.**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-04-27T19:21:00Z (approx)
- **Completed:** 2026-04-27T19:29:34Z
- **Tasks:** 3
- **Files modified:** 2

## Accomplishments

- Closed BL-03 from the phase 28 verification report: the latent `rem(_, 0)`
  `ArithmeticError` in `Modal.Form.handle_event/2` focus-navigation clauses
  (form.ex:195-273) is no longer reachable. `init/1` now refuses to construct
  a Form whose `:fields` list is empty.
- Added the `Phase 28 BL-03` describe block to `form_test.exs` documenting the
  raise contract: regex `~r/at least one field/` matches the literal message.
- Confirmed via sanity sweep that no production caller (Account ProfileForm /
  PrefsForm, Sysop SiteForm, App oneliner / hide-oneliner :form modals) hits
  the new guard today — the validation is purely defensive against a future
  visibility rule that could take `Sysop.SiteForm.State.visible_keys/1` to
  zero.

## Task Commits

Each task was committed atomically:

1. **Task 1: RED — failing test asserting init(fields: []) raises ArgumentError** — `8b4e504` (test)
2. **Task 2: GREEN — guard init/1 against empty :fields** — `74a7246` (feat)
3. **Task 3: Sanity sweep — no production caller regressed** — no source edits, no commit (verification-only task)

_TDD note: this plan exercised the RED → GREEN cycle. No REFACTOR was needed
because the guard is a single 4-line `if`-`raise` inserted between the
existing `Keyword.fetch!(opts, :fields)` and `field_states = Enum.map(...)`._

## Files Created/Modified

- `lib/foglet_bbs/tui/widgets/modal/form.ex` — Added `if fields == [] do raise ArgumentError, "..." end` guard inside `init/1` immediately after `Keyword.fetch!(opts, :fields)` and a one-line `@doc` addendum: `Raises ArgumentError if :fields is an empty list (Phase 28 BL-03).`
- `test/foglet_bbs/tui/widgets/modal/form_test.exs` — Appended `describe "init/1 input validation (Phase 28 BL-03)"` with the single `assert_raise ArgumentError, ~r/at least one field/` test.

## Decisions Made

- **Single init-time guard, not per-clause guards.** The plan's `<read_first>`
  pointed at `28-REVIEW.md` BL-03 "Fix" subsection, which canonicalises this
  shape. Per-clause guards in the four `rem(_, n)` call sites would have been
  invasive and scattered the validation; the init-time raise is one obvious
  failure point and matches the existing `set_submit_state/2` raise style.
- **Exact literal message text.** Plan specified the exact string so the
  BL-03 grep gate would match. Used it verbatim.

## Deviations from Plan

None — plan executed exactly as written.

The plan's RED step explicitly anticipated the failure mode (init/1
constructs without complaint, so the `assert_raise` fails); the run produced
exactly the expected `Expected exception ArgumentError but nothing was
raised` failure on the new test, and no other test regressed. The GREEN step
made the new test pass and left all 62 form_test.exs tests green.

Sanity-sweep target tests:
- `rtk mix test test/foglet_bbs/tui/widgets/modal/` — 68 tests, 0 failures
- `rtk mix test test/foglet_bbs/tui/screens/sysop/` — 36 tests, 0 failures
- `rtk mix test test/foglet_bbs/tui/screens/account_test.exs` — 50 tests, 0 failures
- `rtk mix precommit` — passed (compile warn-as-errors, format, Credo, Sobelow, Dialyzer all clean)

## Issues Encountered

- Worktree was missing `deps/`. Ran `rtk mix deps.get` once before the first
  test invocation. Routine worktree setup, not a plan issue.

## TDD Gate Compliance

- RED gate: `8b4e504` (`test(28-07): RED for BL-03 ...`) — present.
- GREEN gate: `74a7246` (`feat(28-07): validate non-empty :fields ...`) — present.
- REFACTOR gate: not applicable (single-line guard, no follow-up cleanup).

## Verification Gate Status

All `<verification>` gates from the plan pass:

- `rtk mix test test/foglet_bbs/tui/widgets/modal/form_test.exs` — exits 0; file contains literal "at least one field".
- `grep -F "Modal.Form requires at least one field" lib/foglet_bbs/tui/widgets/modal/form.ex` — 1 hit (the new guard).
- `grep -E "raise ArgumentError" lib/foglet_bbs/tui/widgets/modal/form.ex | grep -v '^#' | wc -l` — 2 (set_submit_state/2 + init/1).
- All adjacent suites (account, sysop, modal widgets) pass.
- `rtk mix precommit` passes.

## Threat Flags

None — substrate-internal validation only; no new auth, network, file, or
schema surface introduced. T-28-07-01 from the plan threat register is now
mitigated as designed (latent `rem(_, 0)` DoS replaced by deterministic
`ArgumentError`).

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- BL-03 (the third of three blockers identified in `28-VERIFICATION.md`) is
  closed. Combined with 28-05 (BL-01) and 28-06 (BL-02) from the same wave,
  phase 28 is positioned for verification re-run.
- Modal.Form's init-time invariants are now: (a) `:fields` must be non-empty,
  (b) `:on_submit` and `:on_cancel` must be supplied (existing
  `Keyword.fetch!`). No further substrate-substrate gaps were discovered
  during the sanity sweep.

## Self-Check: PASSED

- `lib/foglet_bbs/tui/widgets/modal/form.ex` — FOUND
- `test/foglet_bbs/tui/widgets/modal/form_test.exs` — FOUND
- Commit `8b4e504` (RED) — FOUND
- Commit `74a7246` (GREEN) — FOUND

---
*Phase: 28-modal-form-substrate*
*Completed: 2026-04-27*
