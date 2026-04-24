---
phase: 04-shared-invite-surface-activation
plan: 04
subsystem: tui
tags: [sysop, invites, tui, shared-surface, tdd]
requires:
  - phase: 04-shared-invite-surface-activation
    plan: 01
    provides: Shared live invite state, actions, and rendering modules
provides:
  - Conditional Sysop INVITES tab for sysop-allowed invite policies
  - Sysop INVITES render and key delegation through shared invite modules
  - Sysop regression coverage for policy visibility, digit navigation, and invite generation
affects: [sysop-screen, invite-workflows]
tech-stack:
  added: []
  patterns: [Runtime policy recomputes tab labels, TUI screens delegate invite lifecycle to shared actions]
key-files:
  created: []
  modified:
    - lib/foglet_bbs/tui/screens/sysop.ex
    - lib/foglet_bbs/tui/screens/sysop/state.ex
    - test/foglet_bbs/tui/screens/sysop_test.exs
key-decisions:
  - "Sysop INVITES visibility is recomputed from ShellVisibility.invites_visible?/2 so runtime policy changes rebuild and clamp tabs."
  - "Sysop invite lifecycle behavior routes through InvitesActions and InvitesSurface only; sysop.ex has no direct Accounts invite or Repo calls."
requirements-completed: [INVT-01, SYSO-05]
duration: 11min
completed: 2026-04-24
---

# Phase 04 Plan 04: Sysop INVITES Live Wiring Summary

**Sysop INVITES tab wired to the shared live invite surface and shared invite actions**

## Performance

- **Duration:** 11 min
- **Started:** 2026-04-24T01:42:51Z
- **Completed:** 2026-04-24T01:53:27Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- Added conditional Sysop `INVITES` labels for `sysop_only`, `mods`, and `any_user` policies while keeping nil and non-sysop users out of the Sysop invite surface.
- Extended Sysop state with shared `InvitesState`, runtime tab labels, active-tab clamping, and tab rebuilds when invite visibility changes.
- Routed Sysop `INVITES` rendering through `InvitesSurface.render/2`.
- Routed Sysop `INVITES` key handling through `InvitesActions.handle_key/3` and one-time tab-entry loading through `InvitesActions.load/2`.
- Preserved existing `SITE`, `BOARDS`, `LIMITS`, and `SYSTEM` submodule dispatch.
- Added regression tests proving digit `6` reaches `INVITES`, sysop generation persists exactly one invite under `sysop_only`, and `sysop.ex` has no direct invite lifecycle or Repo calls.

## Task Commits

1. **Task 1: Add conditional Sysop INVITES tab**
   - `28c332f` test(04-04): add failing sysop invite tab tests
   - `33f5df6` feat(04-04): add conditional sysop invites tab
2. **Task 2: Delegate Sysop INVITES actions to shared path**
   - `1b00189` test(04-04): add failing sysop invite delegation tests
   - `89bbff2` feat(04-04): delegate sysop invites to shared actions

## Files Created/Modified

- `lib/foglet_bbs/tui/screens/sysop/state.ex` - Added shared invite state, conditional label construction, and runtime tab refresh/clamping.
- `lib/foglet_bbs/tui/screens/sysop.ex` - Added shared invite rendering, key delegation, tab-entry loading, and dynamic jump hinting.
- `test/foglet_bbs/tui/screens/sysop_test.exs` - Added Sysop invite policy, navigation, shared delegation, and persistence coverage.

## Decisions Made

- Sysop tabs are rebuilt from runtime `ShellVisibility.invites_visible?/2` instead of treating the initial tab set as immutable.
- Shared invite actions receive normalized key values from Sysop, while Sysop remains responsible only for screen-state writeback.
- Sysop tests use a persisted sysop actor for invite generation so `Accounts` authorization and FK constraints are exercised.

## Deviations from Plan

None - plan executed as written.

## Issues Encountered

- Mix occasionally required elevated execution because `Mix.Sync.PubSub` opens a local TCP socket and the sandbox returned `:eperm`.
- Other wave agents committed unrelated planning and Account/Moderation work while this plan ran. Those changes were left untouched.

## User Setup Required

None.

## Known Stubs

None.

## Threat Flags

None.

## Verification

- `mix test test/foglet_bbs/tui/screens/sysop_test.exs`
- `mix test test/foglet_bbs/tui/screens/sysop_test.exs test/foglet_bbs/tui/screens/shared/invites_actions_test.exs`
- `mix test test/foglet_bbs/tui/screens/sysop_test.exs test/foglet_bbs/tui/screens/shared/invites_actions_test.exs test/foglet_bbs/tui/screens/shared/invites_surface_test.exs`
- `mix precommit`

## TDD Gate Compliance

- RED gate commits present: `28c332f`, `1b00189`
- GREEN gate commits present after RED: `33f5df6`, `89bbff2`

## Self-Check: PASSED

- Verified summary file exists.
- Verified modified implementation and test files exist.
- Verified task commits `28c332f`, `33f5df6`, `1b00189`, and `89bbff2` exist in git history.

---
*Phase: 04-shared-invite-surface-activation*
*Completed: 2026-04-24*
