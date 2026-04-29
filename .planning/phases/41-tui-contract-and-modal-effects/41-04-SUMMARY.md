---
phase: 41-tui-contract-and-modal-effects
plan: 41-04
subsystem: tui
tags: [elixir, raxol, tui, modal-effects, process-cleanup]

requires:
  - phase: 41-tui-contract-and-modal-effects
    provides: first-class modal submit effects and App routing (41-03)
  - phase: 41-tui-contract-and-modal-effects
    provides: canonical screen/test setup (41-02)
provides:
  - Account profile and prefs forms submit through explicit modal-submit effects
  - Sysop SiteForm validation submits through explicit modal-submit effects
  - Sysop BoardsView board/category forms submit through explicit modal-submit effects
  - Modal.Form.SubmitStash removed from production and tests
affects: [tui-modal-submit, account-screen, sysop-screen, main-menu-oneliners]

tech-stack:
  added: []
  patterns:
    - Modal form callbacks return Foglet.TUI.Effect.modal_submit/3
    - Owning screens unwrap explicit submit results without process dictionaries
    - App-shell modal submits route to reducers as {:modal_submit, kind, payload}

key-files:
  created:
    - .planning/phases/41-tui-contract-and-modal-effects/41-04-SUMMARY.md
  modified:
    - lib/foglet_bbs/tui/screens/account/state.ex
    - lib/foglet_bbs/tui/screens/account/profile_form.ex
    - lib/foglet_bbs/tui/screens/account/prefs_form.ex
    - lib/foglet_bbs/tui/screens/sysop/site_form.ex
    - lib/foglet_bbs/tui/screens/sysop/site_form/state.ex
    - lib/foglet_bbs/tui/screens/sysop/boards_view.ex
    - lib/foglet_bbs/tui/screens/main_menu.ex
    - lib/foglet_bbs/tui/screens/sysop/limits_form.ex
    - test/foglet_bbs/tui/screens/account_test.exs
    - test/foglet_bbs/tui/screens/sysop_test.exs
  deleted:
    - lib/foglet_bbs/tui/widgets/modal/form/submit_stash.ex
    - test/foglet_bbs/tui/widgets/modal/form/submit_stash_test.exs

key-decisions:
  - "Kept existing Account inline command tuples while carrying submit payloads through Effect.modal_submit/3."
  - "Encoded Sysop SiteForm validation success/failure inside the explicit modal-submit payload so synchronous Config.put/3 behavior stayed local."
  - "Used BoardsView modal_kind values as modal-submit kinds to validate explicit board/category submit results."
  - "Removed SubmitStash entirely after migrating remaining consumers."

patterns-established:
  - "Inline Modal.Form consumers can consume {:submitted, %Effect{type: :modal_submit}} directly without involving App."
  - "Global Modal.Form overlays should return Effect.modal_submit/3 and rely on App to route reducer messages."

requirements-completed: [TUI-03, QUAL-02]

duration: 45min
completed: 2026-04-29
---

# Phase 41 Plan 41-04: Modal Submit Stash Removal Summary

**All known modal-submit process-dictionary handoffs are removed; modal form payloads now travel through explicit effects or explicit local submit results.**

## Performance

- **Duration:** 45 min
- **Completed:** 2026-04-29T19:41:05Z
- **Tasks:** 4
- **Files modified:** 10
- **Files deleted:** 2

## Accomplishments

- Replaced Account profile/prefs `SubmitStash` callbacks with `Effect.modal_submit(:account, ...)` and updated inline form handlers to unwrap explicit submit effects while preserving `{:account_save_profile, attrs}` and `{:account_save_prefs, attrs}`.
- Replaced Sysop SiteForm `SubmitStash` usage with `Effect.modal_submit(:sysop, :site_settings, {:ok | :error, payload})`.
- Replaced BoardsView `pending_submit` process dictionary transfer with kind-aware `Effect.modal_submit(:sysop, modal_kind, payload)` callbacks and updated tests to use the same explicit path.
- Deleted `Foglet.TUI.Widgets.Modal.Form.SubmitStash` and its dedicated tests.
- Removed the remaining MainMenu App pending-submit process handoff discovered during the final audit.

## Task Commits

1. **Task 41-04-01: Account form submit stash removal** - `a9db2edc` (`refactor`)
2. **Task 41-04-02: Sysop SiteForm submit stash removal** - `22320a8e` (`refactor`)
3. **Task 41-04-03: BoardsView pending submit removal** - `747e1ca9` (`refactor`)
4. **Task 41-04-04: SubmitStash deletion and final audit cleanup** - `f69cf8ec` (`refactor`)
5. **Precommit follow-up: Account alias ordering** - `bcb8e811` (`style`)

## Files Created/Modified

- `lib/foglet_bbs/tui/screens/account/state.ex` - Account forms now return modal-submit effects.
- `lib/foglet_bbs/tui/screens/account/profile_form.ex` - Profile handler consumes explicit submit effects.
- `lib/foglet_bbs/tui/screens/account/prefs_form.ex` - Prefs handler consumes explicit submit effects.
- `lib/foglet_bbs/tui/screens/sysop/site_form.ex` - SiteForm wrapper consumes explicit site-settings submit effects.
- `lib/foglet_bbs/tui/screens/sysop/site_form/state.ex` - SiteForm builder returns explicit site-settings submit effects.
- `lib/foglet_bbs/tui/screens/sysop/boards_view.ex` - Board/category forms return kind-aware modal-submit effects.
- `lib/foglet_bbs/tui/screens/main_menu.ex` - Oneliner global modal forms now return modal-submit effects directly.
- `lib/foglet_bbs/tui/screens/sysop/limits_form.ex` - Removed stale SubmitStash documentation references.
- `test/foglet_bbs/tui/screens/account_test.exs` - Updated modal lock lifecycle expectations for the explicit MainMenu submit path.
- `test/foglet_bbs/tui/screens/sysop_test.exs` - Replaced BoardsView process-dictionary submit fakes with explicit modal-submit effects.
- `lib/foglet_bbs/tui/widgets/modal/form/submit_stash.ex` - Deleted.
- `test/foglet_bbs/tui/widgets/modal/form/submit_stash_test.exs` - Deleted.

## Decisions Made

- Account tab forms keep their inline save command behavior; `Effect.modal_submit/3` is used as the explicit result carrier from `Modal.Form`, not as an App-dispatched global modal in that path.
- SiteForm continues to perform validation before persistence; the validation result is now carried in the effect payload rather than hidden state.
- BoardsView validates the submitted effect kind against the active `modal_kind` before dispatching create/edit behavior.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Removed leftover MainMenu App pending-submit handoff**
- **Found during:** Task 41-04-04 final audit
- **Issue:** `lib/foglet_bbs/tui/screens/main_menu.ex` still wrote `{Foglet.TUI.App, :pending_screen_modal_submit}` for oneliner modals, which failed the plan-level grep.
- **Fix:** Changed oneliner modal callbacks to return `Effect.modal_submit(:main_menu, kind, payload)` directly and updated the affected lock lifecycle tests.
- **Files modified:** `lib/foglet_bbs/tui/screens/main_menu.ex`, `test/foglet_bbs/tui/screens/account_test.exs`
- **Commit:** `f69cf8ec`

**2. [Rule 3 - Blocking] Removed stale SubmitStash comments in LimitsForm**
- **Found during:** Task 41-04-04 final audit
- **Issue:** `limits_form.ex` comments still described SubmitStash as the canonical payload mechanism after the helper was deleted.
- **Fix:** Removed stale SubmitStash commentary while preserving existing render behavior.
- **Files modified:** `lib/foglet_bbs/tui/screens/sysop/limits_form.ex`
- **Commit:** `f69cf8ec`

**3. [Rule 3 - Blocking] Fixed Credo alias ordering after effect aliases were added**
- **Found during:** `rtk mix precommit`
- **Issue:** Credo flagged alias ordering in Account modules touched by task 41-04-01.
- **Fix:** Reordered aliases and reran focused Account tests plus precommit.
- **Files modified:** `lib/foglet_bbs/tui/screens/account/state.ex`, `lib/foglet_bbs/tui/screens/account/profile_form.ex`, `lib/foglet_bbs/tui/screens/account/prefs_form.ex`
- **Commit:** `bcb8e811`

## Known Stubs

None introduced by this plan. Stub-pattern scan hits were pre-existing placeholder strings for input fields and existing test assertions/empty-state checks, not unimplemented modal-submit behavior.

## Threat Flags

None. This plan changed TUI payload routing and tests only; it added no network endpoints, auth paths, persistence schema changes, file access paths, or new trust-boundary surfaces.

## Verification

- `rtk rg -n "SubmitStash|Process\\.(get|put|delete)" lib/foglet_bbs/tui/screens/account/state.ex lib/foglet_bbs/tui/screens/account/profile_form.ex lib/foglet_bbs/tui/screens/account/prefs_form.ex` - no matches.
- `rtk rg -n "Effect\\.modal_submit\\(:account, :profile|Effect\\.modal_submit\\(:account, :prefs|:account_save_profile|:account_save_prefs" lib/foglet_bbs/tui/screens/account` - expected explicit constructors and command tuples found.
- `rtk mix test test/foglet_bbs/tui/screens/account_test.exs` - 62 tests, 0 failures.
- `rtk rg -n "SubmitStash|Process\\.(get|put|delete)" lib/foglet_bbs/tui/screens/sysop/site_form.ex lib/foglet_bbs/tui/screens/sysop/site_form/state.ex` - no matches.
- `rtk rg -n "Effect\\.modal_submit\\(:sysop" lib/foglet_bbs/tui/screens/sysop/site_form.ex lib/foglet_bbs/tui/screens/sysop/site_form/state.ex` - expected explicit constructors found.
- `rtk mix test test/foglet_bbs/tui/screens/sysop_test.exs` - 106 tests, 0 failures.
- `rtk rg -n "pending_submit|Process\\.(get|put|delete)" lib/foglet_bbs/tui/screens/sysop/boards_view.ex test/foglet_bbs/tui/screens/sysop_test.exs` - no matches.
- `rtk rg -n "Effect\\.modal_submit|\\{:modal_submit" lib/foglet_bbs/tui/screens/sysop/boards_view.ex` - expected explicit submit path found.
- `test ! -f lib/foglet_bbs/tui/widgets/modal/form/submit_stash.ex && test ! -f test/foglet_bbs/tui/widgets/modal/form/submit_stash_test.exs` - passed.
- `rtk rg -n "pending_screen_modal_submit|SubmitStash|pending_submit" lib/foglet_bbs/tui test/foglet_bbs/tui` - no matches.
- `rtk rg -n "Process\\.(get|put|delete)" lib/foglet_bbs/tui test/foglet_bbs/tui` - only unrelated test fakes remain.
- `rtk mix test test/foglet_bbs/tui/widgets/modal/form_test.exs test/foglet_bbs/tui/app_test.exs test/foglet_bbs/tui/screens/account_test.exs test/foglet_bbs/tui/screens/sysop_test.exs` - 365 tests, 0 failures.
- `rtk mix precommit` - passed.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Phase 41 modal-submit cleanup is complete. Later App/runtime extraction can assume modal submit payloads are explicit effects or explicit local submit results, with no production process-dictionary handoff.

## Self-Check: PASSED

- Summary file exists at `.planning/phases/41-tui-contract-and-modal-effects/41-04-SUMMARY.md`.
- Task and follow-up commits found in git history: `a9db2edc`, `22320a8e`, `747e1ca9`, `f69cf8ec`, `bcb8e811`.
- No STATE.md or ROADMAP.md updates were made by this executor; pre-existing `.planning/STATE.md` and `.claude/worktrees/` worktree entries remain unstaged.

---
*Phase: 41-tui-contract-and-modal-effects*
*Completed: 2026-04-29*
