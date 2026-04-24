---
phase: 04-shared-invite-surface-activation
plan: 01
subsystem: ui
tags: [tui, invites, accounts, raxol, tdd]
requires:
  - phase: 03-invite-persistence-and-registration-enforcement
    provides: Persisted invite creation, listing, status mapping, revocation, and invite-only registration enforcement
provides:
  - Shared live INVITES state and action module backed by Foglet.Accounts invite APIs
  - Shared live INVITES renderer for available, consumed, and revoked invite lifecycle rows
  - Focused shared invite tests for state preservation, Accounts delegation, error mapping, and required rendering fields
affects: [account-screen, moderation-screen, sysop-screen, invite-workflows]
tech-stack:
  added: []
  patterns: [Shared TUI action module delegates only to context APIs, TDD red-green-refactor per shared surface]
key-files:
  created:
    - lib/foglet_bbs/tui/screens/shared/invites_actions.ex
    - test/foglet_bbs/tui/screens/shared/invites_actions_test.exs
  modified:
    - lib/foglet_bbs/tui/screens/shared/invites_state.ex
    - lib/foglet_bbs/tui/screens/shared/invites_surface.ex
    - test/foglet_bbs/tui/screens/shared/invites_surface_test.exs
key-decisions:
  - "Shared INVITES actions delegate live behavior only through Foglet.Accounts.create_invite/1, list_invites/1, and revoke_invite/2."
  - "Mutation failures set visible state errors without optimistic local invite changes or last-generated-code updates."
  - "Successful generate and revoke operations refresh display state from Accounts.list_invites/1."
patterns-established:
  - "TUI shared action path returns {:ok, %InvitesState{}} or :no_match for key dispatch."
  - "Invite rows render the Accounts status map directly, without Repo access or TUI-side filtering."
requirements-completed: [INVT-01, MODR-04, SYSO-05]
duration: 7min
completed: 2026-04-24
---

# Phase 04 Plan 01: Shared Invite Surface Activation Summary

**Live shared INVITES state, actions, and row rendering backed only by Foglet.Accounts invite APIs**

## Performance

- **Duration:** 7 min
- **Started:** 2026-04-24T01:31:29Z
- **Completed:** 2026-04-24T01:38:37Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments

- Added `Foglet.TUI.Screens.Shared.InvitesActions` as the single shared path for loading, refreshing, generating, selecting, revoking, and key dispatch.
- Expanded `InvitesState` with live list, selection, loading, error, generated-code, and frame fields plus state transition helpers.
- Replaced INVITES render copy with live empty state, lifecycle rows, generated-code banner, visible errors, and operator key hints.
- Added TDD coverage proving Accounts delegation, state preservation on failures, and required available/consumed/revoked row fields.

## Task Commits

1. **Task 1: Create shared live invite state and actions**
   - `775175d` test: add failing shared invite action tests
   - `2ab3d12` feat: implement shared invite actions
   - `7968e4a` refactor: clean up invite error mapping
2. **Task 2: Replace scaffold rendering with live invite rows**
   - `7427ae5` test: add failing live invite surface tests
   - `bfb2bd5` feat: render live shared invite rows

## Files Created/Modified

- `lib/foglet_bbs/tui/screens/shared/invites_actions.ex` - Shared live action module using only `Foglet.Accounts` invite APIs.
- `lib/foglet_bbs/tui/screens/shared/invites_state.ex` - Live state struct and transition helpers for list, selection, loading, error, and generated code.
- `lib/foglet_bbs/tui/screens/shared/invites_surface.ex` - Live renderer for invite lifecycle rows, empty state, banners, errors, and key hints.
- `test/foglet_bbs/tui/screens/shared/invites_actions_test.exs` - Focused action tests for delegation, persistence, error mapping, and state preservation.
- `test/foglet_bbs/tui/screens/shared/invites_surface_test.exs` - Focused render tests for lifecycle fields, banners, errors, and key hints.

## Decisions Made

- Shared invite behavior stays behind `Foglet.Accounts` so the TUI never imports Repo, Bodyguard, Config, or Invite schema modules.
- Generate/revoke success refreshes from `Accounts.list_invites/1` instead of locally fabricating state.
- Failed generate/revoke operations preserve `items`, `selected_index`, and `last_generated_code` while setting a visible error string.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Fixed Credo refactor finding in error mapping**
- **Found during:** Plan verification (`mix precommit`)
- **Issue:** Credo flagged `Enum.map/2 |> Enum.join/2` in `InvitesActions.error_message/1`.
- **Fix:** Replaced the pipeline with `Enum.map_join/3`.
- **Files modified:** `lib/foglet_bbs/tui/screens/shared/invites_actions.ex`
- **Verification:** `mix test test/foglet_bbs/tui/screens/shared/invites_actions_test.exs test/foglet_bbs/tui/screens/shared/invites_surface_test.exs`; `mix precommit`
- **Committed in:** `7968e4a`

---

**Total deviations:** 1 auto-fixed (Rule 3)
**Impact on plan:** No scope change; the fix was required for project precommit compliance.

## Issues Encountered

- TDD red tests initially failed at compile time because the planned state fields did not exist yet; this was the expected RED gate for Task 1.
- Concurrent GSD work added unrelated Phase 05/07 documentation commits on `main` while this plan was executing. Those commits were left untouched.

## User Setup Required

None - no external service configuration required.

## Known Stubs

None.

## Next Phase Readiness

Account, Moderation, and Sysop screens can now delegate INVITES tab behavior to the shared action and render modules. The shared implementation is live, tested, and preserves `Foglet.Accounts` as the invite trust boundary.

## Self-Check: PASSED

- Verified summary file exists.
- Verified created/modified implementation and test files exist.
- Verified task commits `775175d`, `2ab3d12`, `7427ae5`, `bfb2bd5`, and `7968e4a` exist in git history.

---
*Phase: 04-shared-invite-surface-activation*
*Completed: 2026-04-24*
