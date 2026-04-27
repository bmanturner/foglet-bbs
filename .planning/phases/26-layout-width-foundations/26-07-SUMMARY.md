---
phase: 26-layout-width-foundations
plan: 07
subsystem: ui
tags: [tui, tables, width, console-table, elixir, raxol]

requires:
  - phase: 26-layout-width-foundations
    provides: [shared table growth contract, responsive table gap closure]
provides:
  - Shared content-aware table width allocation driven by visible demand and caller priority
  - Explicit priority metadata for INVITES, Moderation, SSH keys, and Sysop USERS table callers
  - Reconciled Phase 26 UAT evidence for the shared-table contract follow-up
affects: [phase-26, invites, moderation-log, console-table, human-uat]

tech-stack:
  added: []
  patterns:
    - Shared table callers declare minimum width, priority, and content demand while the widget owns allocation.
    - Human SSH UAT remains pending when regression coverage passes but the exact terminal rerun was not performed in-session.

key-files:
  created:
    - .planning/phases/26-layout-width-foundations/26-07-SUMMARY.md
  modified:
    - lib/foglet_bbs/tui/widgets/display/table.ex
    - lib/foglet_bbs/tui/screens/shared/invites_state.ex
    - lib/foglet_bbs/tui/screens/moderation/state.ex
    - lib/foglet_bbs/tui/screens/account/ssh_keys_state.ex
    - lib/foglet_bbs/tui/screens/sysop/users_view.ex
    - test/foglet_bbs/tui/widgets/display/table_test.exs
    - test/foglet_bbs/tui/widgets/display/console_table_test.exs
    - .planning/phases/26-layout-width-foundations/26-UAT.md
    - .planning/phases/26-layout-width-foundations/26-HUMAN-UAT.md

key-decisions:
  - "Moved full-content fit and sacrifice order into the shared table allocator instead of adding more screen-local width hacks."
  - "Recorded Tests 7 and 8 as human-needed because this session did not rerun the exact 80x24 SSH scenarios after the allocator changed."

patterns-established:
  - "Display.Table computes widths from minimums, visible content demand, and column priority before using grow-based remainder distribution."
  - "Caller screens express table value importance with metadata; the widget decides how to spend or sacrifice width."

requirements-completed:
  - LAYOUT-04
  - LAYOUT-05

duration: 35min
completed: 2026-04-26
---

# Phase 26 Plan 07: Global Table Content Demand Summary

**Shared table widgets now allocate width from visible content demand and caller priority, so INVITES and other table-backed screens stop truncating high-value columns while lower-value space sits unused**

## Performance

- **Duration:** 35 min
- **Started:** 2026-04-26T23:50:00Z
- **Completed:** 2026-04-27T00:25:00Z
- **Tasks:** 4
- **Files modified:** 10 planned files, plus one unrelated formatter-only test diff from `mix precommit`

## Accomplishments

- Added regression coverage proving the shared contract for full-content fit, priority-based sacrifice, and reclaiming width from empty low-value columns.
- Replaced static table growth behavior with a shared allocator that starts from minimums, measures visible content demand, and spends width by caller priority.
- Migrated representative callers onto explicit priority metadata and updated Phase 26 UAT docs so the remaining work is honest human SSH confirmation, not an undocumented implementation gap.

## Task Commits

No commit was created in this session.

## Files Created/Modified

- `lib/foglet_bbs/tui/widgets/display/table.ex` - Introduced content-aware, priority-driven width resolution for shared tables.
- `lib/foglet_bbs/tui/screens/shared/invites_state.ex` - Declared INVITES column priority so Code yields last and empty `Used by` stops reserving width.
- `lib/foglet_bbs/tui/screens/moderation/state.ex` - Declared representative LOG, USERS, and BOARDS table priorities under the shared contract.
- `lib/foglet_bbs/tui/screens/account/ssh_keys_state.ex` - Declared sensible priority/demand metadata for SSH key columns.
- `lib/foglet_bbs/tui/screens/sysop/users_view.ex` - Declared shared-table priority metadata for USERS headers/empty-state rendering.
- `test/foglet_bbs/tui/widgets/display/table_test.exs` - Added widget-level regressions for fit, sacrifice order, and empty-column reclaim.
- `test/foglet_bbs/tui/widgets/display/console_table_test.exs` - Added console-table regressions using the INVITES scenario and updated compact-width expectations to the new contract.
- `.planning/phases/26-layout-width-foundations/26-UAT.md` - Reframed Tests 7 and 8 around the shared-table contract and left them pending for live SSH reruns.
- `.planning/phases/26-layout-width-foundations/26-HUMAN-UAT.md` - Added explicit follow-up expectations for full-content fit and shared-contract behavior.
- `lib/foglet_bbs/tui/widgets/input/text_input.ex` - Removed one unused alias and one impossible error branch so compile-with-warnings-as-errors no longer fails before the real gates.

## Decisions Made

- Used `priority` and `demand: :content` as the caller-facing contract because it maps directly to the user-visible requirement without forcing each screen to implement its own width policy.
- Kept human SSH evidence pending for the 80x24 INVITES and Moderation LOG scenarios because regression coverage is not a substitute for the exact live terminal rerun.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Cleared unrelated `TextInput` compile warnings so `mix precommit` could reach the real project gates**
- **Found during:** Task 4 (verification)
- **Issue:** `rtk mix precommit` stopped at `--warnings-as-errors` because `Foglet.TUI.Widgets.Input.TextInput` had an unused alias and an impossible `{:error, reason}` branch.
- **Fix:** Removed the unused alias and simplified `RaxolTextInput.init/1` to a direct `{:ok, state}` match.
- **Files modified:** `lib/foglet_bbs/tui/widgets/input/text_input.ex`
- **Verification:** `rtk mix precommit` advanced through compile, Credo, and Sobelow after the fix.
- **Committed in:** none

---

**Total deviations:** 1 auto-fixed (1 blocking verification issue)
**Impact on plan:** No scope creep in the table work itself. The extra fix only unblocked project verification.

## Issues Encountered

- `mix precommit` still fails at Dialyzer with 102 warnings in unrelated files such as `lib/foglet_bbs/tui/presentation.ex`, `lib/foglet_bbs/tui/screens/login/state.ex`, `lib/foglet_bbs/tui/screens/register/state.ex`, `lib/foglet_bbs/tui/screens/verify/state.ex`, and several Mix tasks. None of the reported Dialyzer errors point at the Phase 26 Plan 07 table/widget files.
- `mix precommit` reformatted `test/foglet_bbs/tui/screens/board_list_test.exs` even though it was outside this plan’s write set. The diff is formatting-only.

## User Setup Required

None.

## Next Phase Readiness

The shared table allocator and representative callers are ready for downstream use. Phase 26 still needs the exact 80x24 SSH reruns for Sysop INVITES and Moderation LOG to clear the remaining human-needed UAT notes.

## Verification

- `rtk mix test test/foglet_bbs/tui/widgets/input/text_input_test.exs test/foglet_bbs/tui/widgets/display/table_test.exs test/foglet_bbs/tui/widgets/display/console_table_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` - passed, 126 tests.
- `rtk rg -n "priority|content demand|full content|fits|truncate" test/foglet_bbs/tui/widgets/display/table_test.exs test/foglet_bbs/tui/widgets/display/console_table_test.exs` - passed, showing the new contract coverage.
- `rtk rg -n "INVITES|Code|full|width permits|shared contract" .planning/phases/26-layout-width-foundations/26-UAT.md .planning/phases/26-layout-width-foundations/26-HUMAN-UAT.md` - passed, showing the updated UAT wording.
- `rtk mix precommit` - compile, Credo, and Sobelow passed after the `TextInput` cleanup; Dialyzer still fails with existing unrelated warnings outside this plan’s files.

---
*Phase: 26-layout-width-foundations*
*Completed: 2026-04-26*
