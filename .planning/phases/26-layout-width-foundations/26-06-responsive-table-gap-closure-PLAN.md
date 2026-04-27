---
phase: 26
plan: 06
type: execute
wave: 5
depends_on: [05]
gap_closure: true
files_modified:
  - lib/foglet_bbs/tui/widgets/display/table.ex
  - lib/foglet_bbs/tui/widgets/display/console_table.ex
  - lib/foglet_bbs/tui/screens/moderation/state.ex
  - lib/foglet_bbs/tui/screens/shared/invites_state.ex
  - lib/foglet_bbs/tui/screens/account/ssh_keys_state.ex
  - lib/foglet_bbs/tui/screens/sysop/users_view.ex
  - test/foglet_bbs/tui/widgets/display/table_test.exs
  - test/foglet_bbs/tui/widgets/display/console_table_test.exs
  - test/foglet_bbs/tui/screens/moderation_test.exs
  - test/foglet_bbs/tui/layout_smoke_test.exs
  - .planning/phases/26-layout-width-foundations/26-UAT.md
autonomous: true
requirements:
  - LAYOUT-05
tags:
  - tui
  - gap-closure
  - moderation
  - tables
  - width
  - elixir
must_haves:
  truths:
    - "At any sufficiently wide terminal size, shared table-backed screens expand responsive columns enough to show the full column content when the drawable width budget permits it."
    - "When width is constrained, responsive columns still prioritize useful value visibility before truncating."
    - "Long Body and Reason values still truncate cleanly at cell boundaries with `...` or `…`, without crossing the frame."
    - "The current user's non-UTC timezone and 12-hour clock formatting remain intact in Moderation LOG."
    - "The fix improves the shared table-width contract rather than hardcoding a Moderation-only workaround."
  artifacts:
    - path: ".planning/phases/26-layout-width-foundations/26-UAT.md"
      provides: "The exact remaining user-verified failure and expected behavior."
      contains: "### 8. 80x24 Moderation LOG With Long Body/Reason and Non-UTC User Timezone"
    - path: "lib/foglet_bbs/tui/screens/moderation/state.ex"
      provides: "Moderation LOG column definitions and rendered row content."
      contains: "build_log_table"
    - path: "lib/foglet_bbs/tui/widgets/display/table.ex"
      provides: "Shared width-allocation contract for table-backed screens."
      contains: "available_width"
    - path: "lib/foglet_bbs/tui/widgets/display/console_table.ex"
      provides: "Console-table facade used by Moderation and related screens."
      contains: "Table.init"
---

<objective>
Close the final Phase 26 UAT gap: shared table-backed screens, especially Moderation LOG, are still failing the user-visible responsive-width contract even after earlier shared-width work landed.

Purpose: Make the shared table allocator and the Moderation LOG column mix truly responsive across terminal widths, so columns fully reveal their values when there is enough drawable width and degrade cleanly when there is not.
Output: One focused gap-closure patch with regression coverage and updated UAT evidence for Test 8, with the fix framed as a shared responsive-width improvement rather than an 80x24-only tweak.
</objective>

<execution_context>
@/Users/brendan.turner/Dev/personal/foglet_bbs/.codex/get-shit-done/workflows/execute-plan.md
@/Users/brendan.turner/Dev/personal/foglet_bbs/.codex/get-shit-done/templates/summary.md
</execution_context>

<context>
@AGENTS.md
@docs/raxol/getting-started/WIDGET_GALLERY.md
@lib/foglet_bbs/tui/widgets/README.md
@.planning/ROADMAP.md
@.planning/STATE.md
@.planning/phases/26-layout-width-foundations/26-CONTEXT.md
@.planning/phases/26-layout-width-foundations/26-SPEC.md
@.planning/phases/26-layout-width-foundations/26-UAT.md
@.planning/phases/26-layout-width-foundations/26-05-gap-closure-PLAN.md
@lib/foglet_bbs/tui/widgets/display/table.ex
@lib/foglet_bbs/tui/widgets/display/console_table.ex
@lib/foglet_bbs/tui/screens/moderation/state.ex
@lib/foglet_bbs/tui/screens/shared/invites_state.ex
@lib/foglet_bbs/tui/screens/account/ssh_keys_state.ex
@lib/foglet_bbs/tui/screens/sysop/users_view.ex
@test/foglet_bbs/tui/widgets/display/table_test.exs
@test/foglet_bbs/tui/widgets/display/console_table_test.exs
@test/foglet_bbs/tui/screens/moderation_test.exs
@test/foglet_bbs/tui/layout_smoke_test.exs

<observed_failure>
From `26-UAT.md` Test 8:

```text
│┌─────────────────────────────────────────────────────────────────────────────────────────┐│
││When           Actor     Action    Body                             Reason               ││
││04-26 07:29 PM needz     hide_on…  I have arrived!                  Because I can!       ││
│└─────────────────────────────────────────────────────────────────────────────────────────┘│
```

The timestamp is now correct for a non-UTC 12-hour user, so the remaining failure is width behavior: the LOG table is still not responsive enough. The user clarified that the real requirement is broader than `80x24`: when the terminal is wide enough, the table should expand columns enough to show the complete content instead of leaving columns artificially narrow.
</observed_failure>

<interfaces>
Shared table contract:
```elixir
Display.Table.init(columns: cols, rows: rows, width: width)
ConsoleTable.init(columns: cols, rows: rows, width: width)
```

Representative screen contract:
```elixir
Foglet.TUI.Screens.Moderation.State.build_log_table(rows, opts)
```

Known shared-table consumers still in scope for collateral impact review:
```elixir
Foglet.TUI.Screens.Shared.InvitesState
Foglet.TUI.Screens.Account.SSHKeysState
Foglet.TUI.Screens.Sysop.UsersView
```
</interfaces>
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Add regressions that match the real responsive-width failure</name>
  <files>test/foglet_bbs/tui/widgets/display/table_test.exs, test/foglet_bbs/tui/widgets/display/console_table_test.exs, test/foglet_bbs/tui/screens/moderation_test.exs, test/foglet_bbs/tui/layout_smoke_test.exs</files>
  <read_first>
    - `.planning/phases/26-layout-width-foundations/26-UAT.md`
    - `test/foglet_bbs/tui/widgets/display/table_test.exs`
    - `test/foglet_bbs/tui/widgets/display/console_table_test.exs`
    - `test/foglet_bbs/tui/screens/moderation_test.exs`
    - `test/foglet_bbs/tui/layout_smoke_test.exs`
  </read_first>
  <action>
    Add failing regression coverage that reflects the real user-observed responsive-width failure instead of only abstract allocator expectations.

    Required shape:
    - A widget-level assertion proves that when width remains after fixed metadata columns, the shared allocator expands flexible value columns enough to expose the entire content when it fits within the drawable budget.
    - A widget-level assertion also proves that when width is only moderately constrained, the allocator still favors useful value visibility instead of stranding capacity.
    - A Moderation-level assertion proves Body/Reason gain visible content across wider LOG widths while timestamps remain non-UTC/12-hour formatted.
    - Existing smoke coverage continues to assert no frame overflow.
  </action>
  <verify>
    <automated>rtk mix test test/foglet_bbs/tui/widgets/display/table_test.exs test/foglet_bbs/tui/widgets/display/console_table_test.exs test/foglet_bbs/tui/screens/moderation_test.exs test/foglet_bbs/tui/layout_smoke_test.exs</automated>
  </verify>
  <acceptance_criteria>
    - `rtk rg -n "responsive|truncate|visible content|full content|LOG" test/foglet_bbs/tui/widgets/display/table_test.exs test/foglet_bbs/tui/widgets/display/console_table_test.exs test/foglet_bbs/tui/screens/moderation_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` returns new gap-specific coverage.
    - The new regression fails before the fix and passes after it.
  </acceptance_criteria>
  <done>The remaining gap is captured by automated regressions that prove both constrained-width prioritization and wide-width full-content expansion.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: Fix the shared table-width contract and the Moderation LOG column mix</name>
  <files>lib/foglet_bbs/tui/widgets/display/table.ex, lib/foglet_bbs/tui/widgets/display/console_table.ex, lib/foglet_bbs/tui/screens/moderation/state.ex, lib/foglet_bbs/tui/screens/shared/invites_state.ex, lib/foglet_bbs/tui/screens/account/ssh_keys_state.ex, lib/foglet_bbs/tui/screens/sysop/users_view.ex</files>
  <read_first>
    - `lib/foglet_bbs/tui/widgets/display/table.ex`
    - `lib/foglet_bbs/tui/widgets/display/console_table.ex`
    - `lib/foglet_bbs/tui/screens/moderation/state.ex`
    - `lib/foglet_bbs/tui/screens/shared/invites_state.ex`
    - `lib/foglet_bbs/tui/screens/account/ssh_keys_state.ex`
    - `lib/foglet_bbs/tui/screens/sysop/users_view.ex`
  </read_first>
  <action>
    Patch the shared table allocator first, then adjust the Moderation LOG caller only where necessary.

    Constraints:
    - Preserve framed-width safety and current truncation semantics at cell boundaries.
    - Keep timestamp formatting behavior exactly as fixed in the prior pass.
    - The target behavior is not "better at 80x24"; it is "fully responsive when width permits."
    - Avoid a Moderation-only hardcoded exception if the allocator or column metadata can solve the problem generally.
    - Review the other shared-table callers for overly conservative growth metadata so the shared fix is coherent across screens.
  </action>
  <verify>
    <automated>rtk mix test test/foglet_bbs/tui/widgets/display/table_test.exs test/foglet_bbs/tui/widgets/display/console_table_test.exs test/foglet_bbs/tui/screens/moderation_test.exs test/foglet_bbs/tui/layout_smoke_test.exs</automated>
  </verify>
  <acceptance_criteria>
    - Flexible value columns receive additional width when space exists instead of stranding capacity.
    - If the total drawable width is sufficient for the actual cell values, the responsive columns render the full content without unnecessary truncation.
    - Moderation LOG shows more useful Body/Reason content at the UAT width and fully reveals content at wider representative widths when space permits.
    - Existing smoke tests still prove rendered lines stay inside the frame.
    - `rtk mix test test/foglet_bbs/tui/widgets/display/table_test.exs test/foglet_bbs/tui/widgets/display/console_table_test.exs test/foglet_bbs/tui/screens/moderation_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` exits 0.
  </acceptance_criteria>
  <done>The shared table contract and the Moderation LOG configuration together satisfy the broader user-visible responsive-width expectation.</done>
</task>

<task type="auto">
  <name>Task 3: Update UAT evidence for Test 8</name>
  <files>.planning/phases/26-layout-width-foundations/26-UAT.md</files>
  <read_first>
    - `.planning/phases/26-layout-width-foundations/26-UAT.md`
  </read_first>
  <action>
    After the fix lands and focused tests pass, re-run the exact Test 8 SSH verification scenario and, if useful, spot-check a wider terminal to confirm that full-content expansion actually occurs when width permits.

    Overwrite the Test 8 entry in `26-UAT.md` with the rerun outcome and update the gap status accordingly. If the rerun passes, the gap should be cleared. If it still fails, capture the new render evidence verbatim so the next iteration starts from precise user-visible output.
  </action>
  <verify>
    <automated>rtk mix test test/foglet_bbs/tui/screens/moderation_test.exs test/foglet_bbs/tui/layout_smoke_test.exs</automated>
    <manual>Re-run Test 8 from `26-UAT.md` in a real 80x24 SSH session.</manual>
  </verify>
  <acceptance_criteria>
    - `26-UAT.md` reflects the current Test 8 outcome, not stale inferred status.
    - The phase is ready for a follow-up `$gsd-verify-work 26` pass or direct closure if the rerun passes.
  </acceptance_criteria>
  <done>The remaining UAT gap has fresh evidence and a clear resolved-or-still-open state.</done>
</task>

</tasks>

<threat_model>
This work is presentation-only but affects shared table layout used across operator-facing screens. The main risk is a visually improved LOG table that silently causes frame overflow or regresses other table-backed screens. Preserve width clamping and prove safety with focused tests and existing layout smoke coverage.
</threat_model>

<verification>
- `rtk mix test test/foglet_bbs/tui/widgets/display/table_test.exs test/foglet_bbs/tui/widgets/display/console_table_test.exs test/foglet_bbs/tui/screens/moderation_test.exs test/foglet_bbs/tui/layout_smoke_test.exs`
- Real SSH rerun of Test 8 from `.planning/phases/26-layout-width-foundations/26-UAT.md`
</verification>

<success_criteria>
- The remaining phase-26 failure is captured by regression coverage and fixed through the shared table contract plus any necessary Moderation LOG column adjustments.
- The 80x24 SSH Moderation LOG rerun confirms improved value visibility, clean truncation, and correct non-UTC timestamp formatting.
- A wider-width check confirms the responsive columns can fully reveal content when the drawable width budget is sufficient.
</success_criteria>
