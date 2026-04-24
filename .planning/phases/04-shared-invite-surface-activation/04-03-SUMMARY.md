---
phase: 04-shared-invite-surface-activation
plan: 03
subsystem: ui
tags: [tui, moderation, invites, raxol, tdd]
requires:
  - phase: 04-shared-invite-surface-activation
    plan: 01
    provides: Shared live INVITES state, actions, and rendering
provides:
  - Conditional Moderation INVITES tab under the mods runtime invite policy
  - Moderation INVITES rendering and key delegation through shared invite modules
  - Focused Moderation tests for policy visibility, stale-tab clamping, and moderator generation
affects: [moderation-screen, invite-workflows]
tech-stack:
  added: []
  patterns: [Screen-local policy recomputation with shared invite action delegation]
key-files:
  created:
    - .planning/phases/04-shared-invite-surface-activation/04-03-SUMMARY.md
  modified:
    - lib/foglet_bbs/tui/screens/moderation.ex
    - lib/foglet_bbs/tui/screens/moderation/state.ex
    - test/foglet_bbs/tui/screens/moderation_test.exs
key-decisions:
  - "Moderation recomputes ShellVisibility.invites_visible?/2 at render and key-handling time so stale INVITES tabs are rebuilt and clamped."
  - "Moderation INVITES delegates rendering, loading, and mutation keys to InvitesSurface and InvitesActions without importing Foglet.Accounts or Repo."
  - "Moderator invite generation coverage uses the real Accounts policy path under invite_code_generators == \"mods\"."
patterns-established:
  - "Moderation screen state carries shared InvitesState while lifecycle behavior remains in Shared.InvitesActions."
  - "Active-tab key delegation is guarded by the resolved tab label rather than hard-coded indexes."
requirements-completed: [INVT-01, MODR-04]
duration: 6min
completed: 2026-04-24
---

# Phase 04 Plan 03: Moderation INVITES Live Wiring Summary

**Moderation INVITES is live under the mods policy and delegates only to shared invite modules**

## Performance

- **Duration:** 6 min
- **Started:** 2026-04-24T01:42:35Z
- **Completed:** 2026-04-24T01:48:55Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Added shared `InvitesState` ownership to Moderation state with conditional labels that preserve the base tab order and append `INVITES` only when visible.
- Recomputed `ShellVisibility.invites_visible?/2` during render and key handling, rebuilding stale tab widgets and clamping focus when the runtime policy hides `INVITES`.
- Rendered active Moderation `INVITES` through `InvitesSurface.render/2`.
- Delegated active `INVITES` key handling and first tab-entry load through `InvitesActions`.
- Added tests for mods/any_user/sysop_only policy visibility, regular/nil user hiding, stale tab clamping, shared render output, and real moderator generation under `"mods"`.

## Task Commits

1. **Task 1: Add conditional Moderation INVITES tab**
   - `9fae9f5` test: add failing moderation invite visibility tests
   - `fae705c` feat: document moderation invite visibility wiring
   - Note: the main Task 1 implementation was captured by concurrent commit `5bc0610` while staged in this shared worktree; no history was rewritten.
2. **Task 2: Delegate Moderation INVITES actions to shared path**
   - `e5ce248` test: add failing moderation invite action tests
   - `f25d178` feat: delegate moderation invites actions
   - `f223a64` style: format moderation invite tests

## Files Created/Modified

- `lib/foglet_bbs/tui/screens/moderation.ex` - Runtime policy sync, INVITES render dispatch, shared action delegation, and first-load handling.
- `lib/foglet_bbs/tui/screens/moderation/state.ex` - Conditional tab labels and shared invite state ownership.
- `test/foglet_bbs/tui/screens/moderation_test.exs` - Policy matrix, stale-tab clamping, shared body rendering, and moderator generation coverage.
- `.planning/phases/04-shared-invite-surface-activation/04-03-SUMMARY.md` - Execution summary.

## Verification

- `mix test test/foglet_bbs/tui/screens/moderation_test.exs` - passed.
- `mix test test/foglet_bbs/tui/screens/moderation_test.exs test/foglet_bbs/tui/screens/shared/invites_actions_test.exs test/foglet_bbs/tui/screens/shared/invites_surface_test.exs` - passed, 42 tests.
- `mix precommit` - failed on out-of-scope concurrent Sysop alias ordering in `lib/foglet_bbs/tui/screens/sysop.ex` and `lib/foglet_bbs/tui/screens/sysop/state.ex`.

## Acceptance Checks

- `rg -n "invites:|InvitesState|tab_labels\\(.*invites" lib/foglet_bbs/tui/screens/moderation/state.ex` finds shared invite state and conditional labels.
- `rg -n "ShellVisibility\\.invites_visible\\?" lib/foglet_bbs/tui/screens/moderation.ex` finds runtime policy use.
- `rg -n "InvitesSurface\\.render|InvitesActions\\.handle_key|InvitesActions\\.load" lib/foglet_bbs/tui/screens/moderation.ex` finds shared rendering and delegation.
- `rg -n "Accounts\\.create_invite|Accounts\\.revoke_invite|Accounts\\.list_invites|FogletBbs\\.Repo" lib/foglet_bbs/tui/screens/moderation.ex` returns no matches.
- `rg -n "persists exactly one invite|last_generated_code|unlimited|mods" test/foglet_bbs/tui/screens/moderation_test.exs` finds MODR-04 action coverage.

## Decisions Made

- Moderation keeps invite lifecycle behavior out of the screen module; it only resolves visibility, renders the active tab, and delegates keys.
- The active tab is identified by label so hidden-tab policy changes do not leave invite behavior reachable by stale index.
- Entering `INVITES` loads once when `items` is not already a list; generation then refreshes through the shared action path.

## Deviations from Plan

### Auto-fixed Issues

None.

### Execution Notes

- Concurrent work in the same shared worktree committed the staged Task 1 implementation into `5bc0610` before the task commit could be created. I did not rewrite shared history; I added `fae705c` as the Task 1 implementation marker with related module-doc corrections.
- `mix precommit` failure is out of this plan's write ownership: Credo reported alias ordering in Sysop files being modified by the Wave 2 Sysop executor.

## Known Stubs

None for this plan's invite goal. Existing non-INVITES Moderation tab placeholders remain intentional Phase 8 scaffolding.

## Threat Flags

None. The new moderation invite action surface is covered by the plan threat model and delegates mutations to `Foglet.Accounts` through shared invite actions.

## User Setup Required

None.

## TDD Gate Compliance

- RED gate commits exist for both tasks: `9fae9f5`, `e5ce248`.
- GREEN gate commits exist after RED: `fae705c`, `f25d178`.
- Task 1 implementation was partially captured by concurrent commit `5bc0610`; this is documented above.

## Self-Check: PASSED

- Verified summary file exists.
- Verified modified implementation and test files exist.
- Verified commits `9fae9f5`, `fae705c`, `e5ce248`, `f25d178`, and `f223a64` exist in git history.

---
*Phase: 04-shared-invite-surface-activation*
*Completed: 2026-04-24*
