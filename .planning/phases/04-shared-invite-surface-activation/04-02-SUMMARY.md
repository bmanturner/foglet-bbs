---
phase: 04-shared-invite-surface-activation
plan: 02
subsystem: tui
tags: [account, invites, tui, raxol, tdd]
requires:
  - phase: 04-shared-invite-surface-activation
    plan: 01
    provides: Shared InvitesActions, InvitesState, and live InvitesSurface
provides:
  - Account INVITES tab visibility synchronized from runtime ShellVisibility policy
  - Account active INVITES key delegation to shared InvitesActions
  - Account regression tests for any_user visibility and live invite generation
affects: [account-screen, invite-workflows]
tech-stack:
  added: []
  patterns: [Runtime tab visibility sync, shared invite action delegation]
key-files:
  created: []
  modified:
    - lib/foglet_bbs/tui/screens/account.ex
    - lib/foglet_bbs/tui/screens/account/state.ex
    - test/foglet_bbs/tui/screens/account_test.exs
key-decisions:
  - "Account uses ShellVisibility.invites_visible?/2 on render and handle-key to keep INVITES visibility policy-live."
  - "Account delegates active INVITES keys to InvitesActions and contains no direct invite lifecycle or Repo calls."
  - "Regular-user revoke under any_user surfaces the shared/domain forbidden error because current domain authorization grants users generation, not revocation."
requirements-completed: [INVT-01]
duration: 20min
completed: 2026-04-24
---

# Phase 04 Plan 02: Account INVITES Live Wiring Summary

**Account INVITES is live for regular users under `any_user`, using shared invite actions only**

## Performance

- **Duration:** 20 min
- **Completed:** 2026-04-24T01:50:55Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- Rebuilt Account tab state from `ShellVisibility.invites_visible?/2` during render and handle-key so policy changes in `session_context` take effect without reconnect.
- Preserved `PROFILE`, `PREFS`, then conditional `INVITES` ordering and clamped active tab when INVITES disappears.
- Routed active Account `INVITES` keys through `Foglet.TUI.Screens.Shared.InvitesActions` for load, generate, refresh, selection, and revoke attempts.
- Added Account tests for regular-user `any_user`, `mods`, `sysop_only`, nil-user visibility, runtime visibility changes, persisted generation, refresh, selection, revoke error handling, and hidden-tab generate behavior.

## Task Commits

1. **Task 1: Make Account INVITES visibility policy-live**
   - `5e9d77e` test(04-02): add account invite visibility policy tests
   - `11919fd` feat(04-02): sync account invite tab visibility
2. **Task 2: Delegate active Account INVITES keys to shared actions**
   - `43006c5` test(04-02): add account invite action delegation tests
   - `4551dea` feat(04-02): delegate account invite keys

## Files Created/Modified

- `lib/foglet_bbs/tui/screens/account.ex` - Runtime visibility sync, INVITES key dispatch, load-on-enter, and shared action delegation.
- `lib/foglet_bbs/tui/screens/account/state.ex` - `ensure_visibility/2` helper that rebuilds the Tabs widget from runtime labels.
- `test/foglet_bbs/tui/screens/account_test.exs` - Policy matrix and shared invite delegation regression coverage.

## Decisions Made

- Account visibility remains advisory UI state; invite mutation authorization stays inside `Foglet.Accounts` via shared `InvitesActions`.
- Account does not import or call `Foglet.Accounts` in implementation; tests assert persistence through public context APIs.
- Regular-user revoke is asserted as a shared/domain forbidden error under current authorization rather than changing non-owned authorization code in this plan.

## Deviations from Plan

None - plan scope was executed without Account-local invite business logic.

## Issues Encountered

- `mix precommit` was run and failed on Credo alias-order issues in concurrent Wave 2 Sysop files outside this plan's write ownership:
  - `lib/foglet_bbs/tui/screens/sysop.ex`
  - `lib/foglet_bbs/tui/screens/sysop/state.ex`
- Those files were not modified by this executor.

## Verification

- `mix test test/foglet_bbs/tui/screens/account_test.exs` - passed, 17 tests.
- `mix test test/foglet_bbs/tui/screens/account_test.exs test/foglet_bbs/tui/screens/shared/invites_actions_test.exs` - passed, 29 tests.
- `mix test test/foglet_bbs/tui/screens/account_test.exs test/foglet_bbs/tui/screens/shared/invites_actions_test.exs test/foglet_bbs/tui/screens/shared/invites_surface_test.exs` - passed, 43 tests.
- Acceptance rg checks passed:
  - Runtime visibility sync found in Account state/screen files.
  - Account policy matrix coverage found for `any_user`, `mods`, `sysop_only`, nil user, and visibility changes.
  - Account uses `ShellVisibility.invites_visible?/2`.
  - Account uses `InvitesActions.load/2` and `InvitesActions.handle_key/3`.
  - Account implementation has no `Accounts.*invite*` or Repo access.

## Known Stubs

- Existing Account `PROFILE` and `PREFS` placeholder copy remains in `lib/foglet_bbs/tui/screens/account.ex`; it predates this plan and belongs to Phase 05 Account preferences/profile work.

## Self-Check: PASSED

- Verified summary file exists.
- Verified modified implementation and test files exist.
- Verified task commits `5e9d77e`, `11919fd`, `43006c5`, and `4551dea` exist in git history.

---
*Phase: 04-shared-invite-surface-activation*
*Completed: 2026-04-24*
