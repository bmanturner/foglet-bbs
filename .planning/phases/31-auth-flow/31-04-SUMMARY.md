---
phase: 31-auth-flow
plan: 04
subsystem: testing
tags: [tui, raxol, layout-smoke, password-reset, ssh, terminal-rendering, non-leak]

# Dependency graph
requires:
  - phase: 31-auth-flow
    provides: "Login.render :reset_request and :reset_consume sub-states (Plans 31-02 and 31-03), Verification.active_sysop_contact_emails helper (Plan 31-01), and width-aware reset copy via TextWidth.wrap (Plan 31-02)."
provides:
  - "Layout smoke coverage for Phase 31 reset confirmation/no-email copy at 64x22 (D-12, D-14, D-18)."
  - "Layout smoke coverage for raw reset-token non-leak at 64x22 and 80x24, gating breadcrumb/keybar/error surfaces (D-11, D-18)."
  - "Sentinel-driven proof that BreadcrumbBar.parts_for/1 for :reset_consume is purely state-derived."
affects:
  - "Future auth-flow phases that touch Login chrome or :reset_consume render."
  - "Future Verification helpers that publish operator contacts."

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Width-budget assertion: every content row produced by Login.render at 64x22 stays within TextWidth.display_width(row) <= 64."
    - "Sentinel non-leak assertion: raw token sentinel may appear on exactly one rendered y-row (the focused TextInput) and must be absent from any element with attrs.chrome_frame? = true and from the bottom keybar row."
    - "Negative-presence fixtures for sysop contact rendering: deleted/pending/non-sysop users created in the test and asserted absent from the rendered surface."

key-files:
  created: []
  modified:
    - "test/foglet_bbs/tui/layout_smoke_test.exs - Added two describe blocks: 'Phase 31 reset copy compact rendering (D-12, D-14, D-18)' (3 tests) and 'Phase 31 raw reset token non-leak (D-11, D-18)' (5 tests)."

key-decisions:
  - "Drove the new tests through the existing Engine.apply_layout/2 + text_elements + content_text_elements helpers rather than introducing new harness helpers (D-18)."
  - "Used the chrome_frame? attribute already emitted by the Raxol layout engine for foglet frame text as the boundary between chrome and content surfaces."
  - "Built negative-presence sysop fixtures locally in the test rather than extending AccountsFixtures, because the no-email rendering only needs them in this single test."
  - "Did NOT run rtk mix precommit inside the worktree per the parallel executor instructions; the orchestrator owns the merge-time precommit gate."

patterns-established:
  - "Sentinel-driven non-leak smoke pattern: place a unique high-entropy string in screen-local state, render through the layout engine, and assert it is absent from chrome elements and the bottom keybar row while present in exactly one focused-input row."
  - "Compact-render multi-row proof: assert content rows span >=2 distinct y values to confirm width-aware rendering produced row-per-line text nodes rather than a single overflowing node."

requirements-completed: [AUTH-01, AUTH-02, AUTH-03, AUTH-04]

# Metrics
duration: 18 min
completed: 2026-04-28
---

# Phase 31 Plan 04: Compact reset render and raw-token non-leak smoke Summary

**Layout smoke coverage that pins the Phase 31 reset surfaces at 64x22: confirmation/no-email copy wraps into multiple rows, the no-email path lists active sysop emails comma-separated and excludes deleted/pending/non-sysop users, and the raw reset token sentinel never escapes the focused TextInput row.**

## Performance

- **Duration:** ~18 min
- **Started:** 2026-04-28T00:18:00Z
- **Completed:** 2026-04-28T00:36:35Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments

- Locked the SSH-friendly 64x22 wrap behavior of email-mode and no-email reset confirmation copy through the same `Raxol.UI.Layout.Engine` path the live TUI uses, so any future regression that collapses the wrapped rows back into a single overflowing text node will fail an automated test.
- Locked the operator-contact rendering rules: active sysop emails are listed comma-separated, deleted-by-`deleted_at` sysops, non-active (pending) sysops, and non-sysop users are all absent from rendered no-email copy at 64x22.
- Locked the D-11 non-leak invariant for `:reset_consume`: a sentinel raw token placed in `token_input` is absent from chrome frame text, breadcrumb parts, the bottom keybar row, and the inline error copy after a mismatch submit; the sentinel appears on exactly one rendered y-row, and that row is neither chrome top nor chrome bottom.
- Confirmed the focused phase suite is green: `rtk mix test test/foglet_bbs/accounts/verification_test.exs test/foglet_bbs/tui/screens/login_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` reports `176 tests, 0 failures`.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add 64x22 reset copy wrap and no-email contact smoke tests** - `25fa546` (test)
2. **Task 2: Add raw-token non-leak smoke tests** - `a8f7ddd` (test)

_Note: Both tasks add smoke coverage that asserts existing behavior delivered by Plans 31-01..31-03; per the phase-level TDD shape, the value is in locking these properties going forward, not in driving new implementation. The execution plan does not call for separate refactor commits, so the per-task commits in this plan are test-only._

## Files Created/Modified

- `test/foglet_bbs/tui/layout_smoke_test.exs` - Added two describe blocks under existing helpers:
  - `"Phase 31 reset copy compact rendering (D-12, D-14, D-18)"`: 3 tests covering email-mode multi-row wrap at 64x22, no-email comma-separated active sysop list with deleted/pending/non-sysop exclusion, and no-sysop fallback that names sysop/operator without forbidden URLs.
  - `"Phase 31 raw reset token non-leak (D-11, D-18)"`: 5 tests covering chrome-frame absence at 64x22 and 80x24, single-row sentinel placement at 64x22, breadcrumb parts being state-derived (with the four-segment shape `Foglet, Forgot Password, Enter Token`), bottom keybar absence, and post-mismatch error-row absence.

## Decisions Made

- Used the existing `chrome_frame?` element attribute (set by `Raxol.UI.Layout.Engine` for foglet frame text) as the chrome-vs-content boundary in the non-leak tests, rather than inferring chrome by y-position alone.
- Built the negative-presence sysop fixtures inline in the test rather than promoting them to `FogletBbs.AccountsFixtures` because they are specific to the Phase 31 no-email rendering case and reuse existing primitives (`user_fixture/1`, `User.role_changeset/2`, `confirm_user/1`, plus `Ecto.Changeset.change/2` for `deleted_at` and `status` overrides).
- Skipped running `rtk mix precommit` inside the worktree as instructed by the parallel-executor system prompt (`<parallel_execution>` block: orchestrator owns precommit). The plan's Task 2 verify step calls for `rtk mix precommit`; the conflict was resolved by deferring to the orchestrator instruction since it is the merge-time gate. The phase's narrow verification command was run successfully inside the worktree.

## Deviations from Plan

### Out-of-scope discoveries / environment fixes

**1. [Rule 3 - Blocking] Symlinked `deps` and `_build` into the worktree**
- **Found during:** Task 1 verification (first `rtk mix test` run)
- **Issue:** The worktree had no `deps/` or `_build/` directory, so Mix aborted with `the dependency is not available, run "mix deps.get"`. The dependencies were already fetched and compiled in the parent repo.
- **Fix:** Created symlinks `deps -> /Users/brendan.turner/Dev/personal/foglet_bbs/deps` and `_build -> /Users/brendan.turner/Dev/personal/foglet_bbs/_build`. The repo `.gitignore` excludes `/deps/` and `/_build/` at the repo root, so the symlinks remain untracked and uncommitted.
- **Files modified:** None (symlinks at the worktree root, not committed).
- **Verification:** `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs` ran successfully; 82 tests, 0 failures.

**2. [Rule 1 - Bug, in test only] Pending-status fixture used wrong status**
- **Found during:** Task 1, first run of the no-email comma-separated test.
- **Issue:** Initial fixture for `pendingsysop@example.test` only set `role: :sysop` via `User.role_changeset/2`. Because `Foglet.Accounts.register_user/1` defaults `status: :active`, the "pending" sysop was actually active and leaked into the rendered list, contradicting the assertion intent.
- **Fix:** Added an explicit `Ecto.Changeset.change(status: :pending) |> Repo.update!()` step to the fixture so the negative-presence assertion exercises the `u.status == :active` filter in `Verification.active_sysop_contact_emails/0` rather than just the `not is_nil(u.email)` path.
- **Files modified:** `test/foglet_bbs/tui/layout_smoke_test.exs`.
- **Verification:** Re-ran the focused describe; all 3 tests passed.
- **Committed in:** `25fa546` (Task 1 commit; the fix landed before the commit).

---

**Total deviations:** 2 (1 environment / blocking, 1 in-scope test-bug fixed before commit).
**Impact on plan:** Both fixes were necessary to land Task 1 verification; neither relaxed any phase test or invariant. No scope creep beyond the plan's two task files.

## Issues Encountered

- The plan's Task 2 acceptance instruction to run `rtk mix precommit` conflicts with the parallel-executor instruction to defer precommit to the orchestrator. Resolution: the orchestrator instruction wins since it is the merge gate; the focused verification command in `31-VALIDATION.md` was run instead and is recorded in this Summary. Future merge of this worktree should run `rtk mix precommit` per the validation contract. No phase tests were weakened.

## Verification Evidence

- `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs --only describe:"Phase 31 reset copy compact rendering (D-12, D-14, D-18)"` → 3 tests, 0 failures.
- `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs --only describe:"Phase 31 raw reset token non-leak (D-11, D-18)"` → 5 tests, 0 failures.
- `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs` (full file) → 82 tests, 0 failures.
- `rtk mix test test/foglet_bbs/accounts/verification_test.exs test/foglet_bbs/tui/screens/login_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` (focused phase suite from `31-VALIDATION.md`) → 176 tests, 0 failures.
- `rtk mix precommit` not run inside the worktree (deferred to orchestrator merge gate per executor instructions).

## Threat Register Compliance

| Threat ID | Mitigation | Evidence |
|-----------|------------|----------|
| T-31-10 (information disclosure: chrome around reset consume) | Sentinel raw token rendered into `token_input`; assertions confirm absence from chrome_frame elements, breadcrumb parts, bottom keybar row, and error copy. | Tests in `"Phase 31 raw reset token non-leak (D-11, D-18)"` describe block. |
| T-31-11 (denial of service / compact reset copy) | At 64x22 every content row stays within 64 cols and reset confirmation copy spans >=2 distinct y rows. | Tests in `"Phase 31 reset copy compact rendering (D-12, D-14, D-18)"` describe block. |
| T-31-12 (repudiation / phase verification evidence) | Focused phase suite recorded above; precommit deferred to orchestrator with explicit reason. | "Verification Evidence" section above. |

## Next Phase Readiness

- Phase 31 (auth flow) automated coverage now spans Accounts/Verification (Plan 01), Login screen state (Plan 02), `:reset_consume` transactional consume (Plan 03), and compact-render + non-leak smoke (this plan).
- The orchestrator should run `rtk mix precommit` at merge time. If precommit fails, the failure is expected to come from out-of-scope Dialyzer or Sobelow warnings already noted in `.planning/STATE.md`, not from any Phase 31 test.

## Self-Check: PASSED

- Created files exist:
  - `FOUND: .planning/phases/31-auth-flow/31-04-SUMMARY.md` (this file).
- Modified files exist:
  - `FOUND: test/foglet_bbs/tui/layout_smoke_test.exs` (contains both new describe blocks).
- Commits exist:
  - `FOUND: 25fa546` (Task 1).
  - `FOUND: a8f7ddd` (Task 2).

---
*Phase: 31-auth-flow*
*Completed: 2026-04-28*
