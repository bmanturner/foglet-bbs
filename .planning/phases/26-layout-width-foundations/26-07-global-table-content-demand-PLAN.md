---
phase: 26
plan: 07
type: execute
wave: 6
depends_on: [06]
gap_closure: true
files_modified:
  - lib/foglet_bbs/tui/widgets/display/table.ex
  - lib/foglet_bbs/tui/widgets/display/console_table.ex
  - lib/foglet_bbs/tui/screens/shared/invites_state.ex
  - lib/foglet_bbs/tui/screens/moderation/state.ex
  - lib/foglet_bbs/tui/screens/account/ssh_keys_state.ex
  - lib/foglet_bbs/tui/screens/sysop/users_view.ex
  - test/foglet_bbs/tui/widgets/display/table_test.exs
  - test/foglet_bbs/tui/widgets/display/console_table_test.exs
  - test/foglet_bbs/tui/layout_smoke_test.exs
  - .planning/phases/26-layout-width-foundations/26-UAT.md
autonomous: true
requirements:
  - LAYOUT-04
  - LAYOUT-05
tags:
  - tui
  - gap-closure
  - widgets
  - tables
  - width
  - elixir
must_haves:
  truths:
    - "Any screen using `Display.Table` or `ConsoleTable` shows all visible column values in full when the drawable width budget is sufficient."
    - "When width is not sufficient, the shared widget degrades by declared column priority instead of static ratio or arbitrary growth alone."
    - "Caller screens describe column priority/minimums; they do not hand-roll responsive width logic per screen."
    - "Low-value or empty columns do not reserve generous width while higher-value columns truncate unnecessarily."
    - "Existing frame safety and cell-boundary truncation semantics remain intact."
  artifacts:
    - path: "lib/foglet_bbs/tui/widgets/display/table.ex"
      provides: "Shared width-resolution contract for all table-backed screens."
      contains: "resolve_widths"
    - path: "lib/foglet_bbs/tui/widgets/display/console_table.ex"
      provides: "Shared facade used by current and future console-table screens."
      contains: "Table.init"
    - path: "lib/foglet_bbs/tui/screens/shared/invites_state.ex"
      provides: "Concrete failing caller where the primary value is currently truncated."
      contains: "@invite_columns"
    - path: ".planning/phases/26-layout-width-foundations/26-UAT.md"
      provides: "Phase 26 user-visible evidence and final gap status."
      contains: "80x24 Sysop INVITES"
---

<objective>
Fix the shared table widget contract so responsiveness is content-aware and global, not limited to one screen or one column set.

Purpose: Make every current and future `Display.Table`/`ConsoleTable` consumer show all values when width permits, then degrade by explicit column priority when width does not permit full visibility.
Output: One shared-widget patch with regression coverage and updated Phase 26 UAT evidence, using INVITES as the concrete failing example and Moderation LOG as a representative regression.
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
@.planning/phases/26-layout-width-foundations/26-06-responsive-table-gap-closure-PLAN.md
@lib/foglet_bbs/tui/widgets/display/table.ex
@lib/foglet_bbs/tui/widgets/display/console_table.ex
@lib/foglet_bbs/tui/screens/shared/invites_state.ex
@lib/foglet_bbs/tui/screens/moderation/state.ex
@lib/foglet_bbs/tui/screens/account/ssh_keys_state.ex
@lib/foglet_bbs/tui/screens/sysop/users_view.ex
@test/foglet_bbs/tui/widgets/display/table_test.exs
@test/foglet_bbs/tui/widgets/display/console_table_test.exs
@test/foglet_bbs/tui/layout_smoke_test.exs

<observed_failure>
From user-provided 80x24 Sysop INVITES evidence:

```text
│┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────┐│
││Code                Status      Created     Used by                                                           ││
││A2TGJQGYMI74JITZAA… available   2026-04-26                                                                    ││
││UITD46JLDWNNOYAXWN… available   2026-04-26                                                                    ││
││TSTUISZHQVGOQA7W5R… available   2026-04-26                                                                    ││
│└──────────────────────────────────────────────────────────────────────────────────────────────────────────────┘│
```

The columns are aligned, but the primary value (`Code`) is still truncated even though the table clearly has spare width in lower-value columns, especially `Used by` for `available` invites. The user clarified the required behavior:

1. This is still a table responsiveness bug.
2. The fix must be global to the shared table widget contract.
3. If all visible values fit, all columns should show their full values.
4. When not everything fits, truncation should happen by priority, not just by static width/grow heuristics.
</observed_failure>

<interfaces>
Shared table contract today:
```elixir
Display.Table.init(columns: cols, rows: rows, width: width)
ConsoleTable.init(columns: cols, rows: rows, width: width)
```

Desired caller metadata shape after this plan:
```elixir
%{
  key: :code,
  label: "Code",
  width: 12,
  grow: 4,
  priority: 100,
  demand: :content
}
```

The exact field names may change during implementation, but the widget must support the concepts of:
- minimum readable width
- current content demand
- priority / sacrifice order
- drawable width budget
</interfaces>
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Add shared-widget regressions for content-aware width resolution</name>
  <files>test/foglet_bbs/tui/widgets/display/table_test.exs, test/foglet_bbs/tui/widgets/display/console_table_test.exs, test/foglet_bbs/tui/layout_smoke_test.exs</files>
  <read_first>
    - `test/foglet_bbs/tui/widgets/display/table_test.exs`
    - `test/foglet_bbs/tui/widgets/display/console_table_test.exs`
    - `test/foglet_bbs/tui/layout_smoke_test.exs`
    - `lib/foglet_bbs/tui/widgets/display/table.ex`
    - `lib/foglet_bbs/tui/widgets/display/console_table.ex`
  </read_first>
  <action>
    Add failing regression coverage at the widget layer for the actual desired contract.

    Required shape:
    - A test proves that if the full visible row values fit inside the drawable width budget, the shared widget resolves widths so all visible values render in full.
    - A test proves that if the values do not all fit, lower-priority columns lose width before higher-priority columns.
    - A test proves empty or short values do not hold width hostage while a higher-priority value-bearing column truncates.
    - Existing smoke coverage still asserts no frame overflow.
  </action>
  <verify>
    <automated>rtk mix test test/foglet_bbs/tui/widgets/display/table_test.exs test/foglet_bbs/tui/widgets/display/console_table_test.exs test/foglet_bbs/tui/layout_smoke_test.exs</automated>
  </verify>
  <acceptance_criteria>
    - `rtk rg -n "priority|content demand|full content|fits|truncate" test/foglet_bbs/tui/widgets/display/table_test.exs test/foglet_bbs/tui/widgets/display/console_table_test.exs` returns new shared-contract coverage.
    - The new regression fails before the shared fix and passes after it.
  </acceptance_criteria>
  <done>The desired global responsiveness contract is locked in by tests before any caller-specific adjustments are made.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: Upgrade the shared table widget from static growth to content-aware priority allocation</name>
  <files>lib/foglet_bbs/tui/widgets/display/table.ex, lib/foglet_bbs/tui/widgets/display/console_table.ex</files>
  <read_first>
    - `lib/foglet_bbs/tui/widgets/display/table.ex`
    - `lib/foglet_bbs/tui/widgets/display/console_table.ex`
    - `test/foglet_bbs/tui/widgets/display/table_test.exs`
    - `test/foglet_bbs/tui/widgets/display/console_table_test.exs`
  </read_first>
  <action>
    Replace the current width-allocation behavior with a shared content-aware algorithm.

    The allocator must:
    - Start from minimum readable widths.
    - Estimate current content demand from the header and visible row values.
    - Spend extra width to satisfy full content when the total budget permits.
    - When the budget does not permit that, allocate by priority/sacrifice order rather than only by `grow`.
    - Preserve framed-width safety and existing truncation-at-cell-boundary semantics.

    Keep the behavior generic. Do not hardcode any knowledge of INVITES, Moderation, or specific column names into the widget.
  </action>
  <verify>
    <automated>rtk mix test test/foglet_bbs/tui/widgets/display/table_test.exs test/foglet_bbs/tui/widgets/display/console_table_test.exs test/foglet_bbs/tui/layout_smoke_test.exs</automated>
  </verify>
  <acceptance_criteria>
    - If the full row values fit, the widget shows them fully without unnecessary truncation.
    - If the full row values do not fit, lower-priority columns sacrifice width before higher-priority columns.
    - Callers can describe priority/minimum behavior without reimplementing width logic.
    - `rtk mix test test/foglet_bbs/tui/widgets/display/table_test.exs test/foglet_bbs/tui/widgets/display/console_table_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` exits 0.
  </acceptance_criteria>
  <done>The shared widget now owns content-aware responsiveness for all current and future table-backed screens.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 3: Update current callers to declare priority instead of relying on lucky width ratios</name>
  <files>lib/foglet_bbs/tui/screens/shared/invites_state.ex, lib/foglet_bbs/tui/screens/moderation/state.ex, lib/foglet_bbs/tui/screens/account/ssh_keys_state.ex, lib/foglet_bbs/tui/screens/sysop/users_view.ex, test/foglet_bbs/tui/widgets/display/console_table_test.exs, test/foglet_bbs/tui/layout_smoke_test.exs</files>
  <read_first>
    - `lib/foglet_bbs/tui/screens/shared/invites_state.ex`
    - `lib/foglet_bbs/tui/screens/moderation/state.ex`
    - `lib/foglet_bbs/tui/screens/account/ssh_keys_state.ex`
    - `lib/foglet_bbs/tui/screens/sysop/users_view.ex`
    - `test/foglet_bbs/tui/layout_smoke_test.exs`
  </read_first>
  <action>
    Update representative current callers to use the new shared contract explicitly.

    Required outcomes:
    - INVITES declares `Code` as the highest-value column and ensures `Used by` yields width when it is lower-value or empty.
    - Moderation LOG remains a representative regression for width growth plus timestamp safety.
    - SSH keys and Sysop users declare sensible priority/minimum behavior under the new contract.

    Avoid screen-local width solvers. The caller should declare metadata, not implement allocation logic.
  </action>
  <verify>
    <automated>rtk mix test test/foglet_bbs/tui/widgets/display/table_test.exs test/foglet_bbs/tui/widgets/display/console_table_test.exs test/foglet_bbs/tui/layout_smoke_test.exs</automated>
  </verify>
  <acceptance_criteria>
    - The INVITES screen can show full invite codes when the total visible values fit in the budget.
    - When full fit is impossible, `Code` is truncated later than lower-priority metadata columns.
    - Other representative callers still fit within frame budgets.
  </acceptance_criteria>
  <done>Current screens are migrated onto the new shared contract without inventing one-off responsiveness behavior.</done>
</task>

<task type="auto">
  <name>Task 4: Update Phase 26 UAT evidence for INVITES and the shared contract</name>
  <files>.planning/phases/26-layout-width-foundations/26-UAT.md, .planning/phases/26-layout-width-foundations/26-HUMAN-UAT.md</files>
  <read_first>
    - `.planning/phases/26-layout-width-foundations/26-UAT.md`
    - `.planning/phases/26-layout-width-foundations/26-HUMAN-UAT.md`
  </read_first>
  <action>
    Update the UAT artifacts so they reflect the actual user-visible scope of this gap.

    Required shape:
    - Test 7 (`80x24 Sysop INVITES`) must explicitly cover full-code visibility when width permits, not just column separation.
    - Test 8 should keep the shared-contract framing rather than a Moderation-only framing.
    - If real SSH reruns are not performed in-session, leave the relevant cases honestly pending with exact follow-up notes.
  </action>
  <verify>
    <automated>rtk rg -n "INVITES|Code|full|width permits|shared contract" .planning/phases/26-layout-width-foundations/26-UAT.md .planning/phases/26-layout-width-foundations/26-HUMAN-UAT.md</automated>
    <manual>Re-run the exact 80x24 Sysop INVITES and 80x24 Moderation LOG scenarios in a real SSH session.</manual>
  </verify>
  <acceptance_criteria>
    - The UAT docs describe the real shared-widget requirement instead of only the earlier alignment-focused wording.
    - Follow-up SSH checks are explicit and reproducible.
  </acceptance_criteria>
  <done>The Phase 26 artifacts match the real product expectation for globally responsive shared tables.</done>
</task>

</tasks>

<threat_model>
This work is presentation-only but changes a shared widget used by multiple operator-facing screens. The main risks are:
- a smarter allocator that accidentally overfits one screen's data shape,
- regressions where full-content fitting breaks frame safety,
- and callers silently depending on previous static-width quirks.

Mitigate these by proving the contract at the widget layer first, then validating representative callers with smoke coverage.
</threat_model>

<verification>
- `rtk mix test test/foglet_bbs/tui/widgets/display/table_test.exs test/foglet_bbs/tui/widgets/display/console_table_test.exs test/foglet_bbs/tui/layout_smoke_test.exs`
- `rtk mix test test/foglet_bbs/tui/screens/moderation_test.exs`
- Real SSH reruns of the exact 80x24 Sysop INVITES and 80x24 Moderation LOG scenarios from `.planning/phases/26-layout-width-foundations/26-UAT.md`
</verification>

<success_criteria>
- The shared table widget shows all visible values when the drawable width permits it.
- When truncation is unavoidable, lower-priority columns sacrifice width before higher-priority columns.
- INVITES, Moderation LOG, and other representative callers inherit the behavior through shared widget metadata rather than one-off screen logic.
- Phase 26 UAT language and evidence now match the real product requirement for globally responsive shared tables.
</success_criteria>
