---
phase: 26
plan: 05
type: execute
wave: 4
depends_on: [02, 03, 04]
gap_closure: true
files_modified:
  - lib/foglet_bbs/tui/screens/board_list.ex
  - lib/foglet_bbs/tui/widgets/list/board_tree.ex
  - test/foglet_bbs/tui/screens/board_list_test.exs
  - test/foglet_bbs/tui/layout_smoke_test.exs
  - lib/foglet_bbs/tui/screens/moderation/state.ex
  - lib/foglet_bbs/tui/widgets/display/table.ex
  - test/foglet_bbs/tui/screens/moderation_test.exs
autonomous: true
requirements:
  - LAYOUT-03
  - LAYOUT-05
tags:
  - tui
  - gap-closure
  - boards
  - moderation
  - elixir
must_haves:
  truths:
    - "At 64x22, the Boards screen uses the compact body region densely enough that the primary tree visibly fills the frame instead of leaving large blank spans."
    - "At 64x22, Boards category and board rows stay inside the frame and above the command bar while remaining navigable."
    - "At 80x24, the Moderation LOG table uses available width responsively so Body and Reason expose more visible content when space exists."
    - "The Moderation LOG timezone and 12-hour preference fix remains intact while responsive width behavior is corrected."
  artifacts:
    - path: ".planning/phases/26-layout-width-foundations/26-UAT.md"
      provides: "Verified gap list and exact failing terminal evidence."
      contains: "## Gaps"
    - path: "lib/foglet_bbs/tui/screens/board_list.ex"
      provides: "Compact Boards body budgeting."
      contains: "render_board_content"
    - path: "lib/foglet_bbs/tui/widgets/list/board_tree.ex"
      provides: "Visible-row windowing for oversized board trees."
      contains: "visible_height"
    - path: "lib/foglet_bbs/tui/screens/moderation/state.ex"
      provides: "Moderation LOG table column definitions and row building."
      contains: "build_log_table"
    - path: "lib/foglet_bbs/tui/widgets/display/table.ex"
      provides: "Shared width allocation used by LOG tables."
      contains: "available_width"
---

<objective>
Close the two remaining Phase 26 UAT gaps without reopening already-passed compact layout work.

Purpose: Boards still underfills the compact 64x22 body, and Moderation LOG still leaves value visibility on the table at 80x24 even after the time-format fix.
Output: One focused gap-closure patch with regression coverage, ready for `$gsd-execute-phase 26 --gaps-only`.
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
@.planning/phases/26-layout-width-foundations/26-RESEARCH.md
@.planning/phases/26-layout-width-foundations/26-SPEC.md
@.planning/phases/26-layout-width-foundations/26-UAT.md
@.planning/phases/26-layout-width-foundations/26-02-tabs-moderation-fit-PLAN.md
@.planning/phases/26-layout-width-foundations/26-03-boards-viewport-PLAN.md
@lib/foglet_bbs/tui/screens/board_list.ex
@lib/foglet_bbs/tui/widgets/list/board_tree.ex
@lib/foglet_bbs/tui/screens/moderation/state.ex
@lib/foglet_bbs/tui/widgets/display/table.ex
@test/foglet_bbs/tui/screens/board_list_test.exs
@test/foglet_bbs/tui/screens/moderation_test.exs
@test/foglet_bbs/tui/layout_smoke_test.exs

<observed_failures>
From `26-UAT.md` after retest:

1. Boards at 64x22 still shows large blank spans with only a few visible rows:
   `Announcements`, `Lounge`, summary line, then a mostly empty body to the command bar.

2. Moderation LOG at 80x24 now shows `04-26 07:29 PM`, so timezone and 12-hour formatting are fixed, but the user still reports:
   "the table doesn't stretch responsively so I can see every value even when there's enough space"
</observed_failures>

<interfaces>
Compact Boards contract:
```elixir
BoardTree.render(tree, theme: theme, width: width, visible_height: visible_height)
```

Moderation LOG contract:
```elixir
State.build_log_table(rows, timezone: tz, width: width)
Display.Table.init(columns: cols, rows: rows, width: width)
```

The width passed into widgets is drawable inner-frame width, not raw terminal columns.
</interfaces>
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Fix Boards compact body density at 64x22</name>
  <files>lib/foglet_bbs/tui/screens/board_list.ex, lib/foglet_bbs/tui/widgets/list/board_tree.ex, test/foglet_bbs/tui/screens/board_list_test.exs, test/foglet_bbs/tui/layout_smoke_test.exs</files>
  <read_first>
    - `.planning/phases/26-layout-width-foundations/26-UAT.md` gap for test 6
    - `lib/foglet_bbs/tui/screens/board_list.ex`
    - `lib/foglet_bbs/tui/widgets/list/board_tree.ex`
    - `test/foglet_bbs/tui/screens/board_list_test.exs`
    - `test/foglet_bbs/tui/layout_smoke_test.exs`
  </read_first>
  <behavior>
    - Oversized Boards directories do not leave a mostly empty body at 64x22.
    - Primary tree rows get priority over optional compact chrome such as spacer/detail rows.
    - Focused rows remain visible while navigating.
  </behavior>
  <action>
    Start by adding a failing regression that matches the retest evidence rather than the earlier inferred root cause.

    In `test/foglet_bbs/tui/screens/board_list_test.exs` or `test/foglet_bbs/tui/layout_smoke_test.exs`, create an overlarge directory fixture at `{64, 22}` and assert the rendered body contains a meaningful density of visible tree rows instead of only one or two rows separated by large blank spans. Use a measurable assertion tied to the flattened render output, for example counting visible board/category lines in the body region or asserting the blank-line run length stays below a compact threshold.

    Then update `lib/foglet_bbs/tui/screens/board_list.ex` to rebalance `reserved_rows` and `visible_height` for compact screens:
    - Primary tree density wins at 64x22.
    - Omit nonessential blank spacer rows before details when they would reduce visible tree density.
    - Show details only if at least one row remains after giving the tree a healthy compact budget.
    - Do not add new navigation state outside `BoardTree`.

    Adjust `lib/foglet_bbs/tui/widgets/list/board_tree.ex` only if the screen-level fix reveals an off-by-one or separator-row accounting bug in the visible window logic.
  </action>
  <verify>
    <automated>rtk mix test test/foglet_bbs/tui/screens/board_list_test.exs test/foglet_bbs/tui/layout_smoke_test.exs</automated>
  </verify>
  <acceptance_criteria>
    - `rtk rg -n "64x22|visible_height|blank|density|overlarge" test/foglet_bbs/tui/screens/board_list_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` returns new compact-density regression coverage.
    - Layout smoke at `{64, 22}` fails if the Boards body collapses back to the sparse shape reported in UAT.
    - Existing Boards navigation expectations still pass.
    - `rtk mix test test/foglet_bbs/tui/screens/board_list_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` exits 0.
  </acceptance_criteria>
  <done>Boards compact rendering fills the 64x22 frame body with the primary tree instead of leaving large empty spans.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: Make Moderation LOG use 80x24 width more aggressively</name>
  <files>lib/foglet_bbs/tui/screens/moderation/state.ex, lib/foglet_bbs/tui/widgets/display/table.ex, test/foglet_bbs/tui/screens/moderation_test.exs, test/foglet_bbs/tui/layout_smoke_test.exs</files>
  <read_first>
    - `.planning/phases/26-layout-width-foundations/26-UAT.md` gap for test 8
    - `lib/foglet_bbs/tui/screens/moderation/state.ex`
    - `lib/foglet_bbs/tui/widgets/display/table.ex`
    - `test/foglet_bbs/tui/screens/moderation_test.exs`
    - `test/foglet_bbs/tui/layout_smoke_test.exs`
  </read_first>
  <behavior>
    - LOG table width allocation uses available 80x24 body width to expose more Body and Reason content.
    - The `07:29 PM` style timestamp remains intact for non-UTC 12-hour users.
    - No frame overflow is introduced.
  </behavior>
  <action>
    First add a failing regression that proves the current LOG table leaves too much value content truncated at 80x24 despite available width.

    The test should render Moderation LOG at a realistic `80x24`-derived width with a long body/reason row and assert more than the current narrow slice is visible in the flattened output. Tie the assertion to concrete visible content expansion, not just absence of overflow. For example: compare expected visible substring length for Body/Reason, or assert the responsive column widths allocated to those fields exceed the old compact allocation.

    Then diagnose the actual source before patching:
    - If `lib/foglet_bbs/tui/screens/moderation/state.ex` still uses overly conservative fixed or ratio widths for LOG columns, loosen those definitions first.
    - If the shared allocator in `lib/foglet_bbs/tui/widgets/display/table.ex` is holding back width from flex columns, fix the allocator without regressing other tables.

    Keep the timezone/clock-preference behavior intact. Do not reintroduce fixed `24h` formatting while adjusting LOG columns.
  </action>
  <verify>
    <automated>rtk mix test test/foglet_bbs/tui/screens/moderation_test.exs test/foglet_bbs/tui/layout_smoke_test.exs</automated>
  </verify>
  <acceptance_criteria>
    - `rtk rg -n "07:29 PM|PM|Reason|Body|width" test/foglet_bbs/tui/screens/moderation_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` returns timestamp-preserving responsive-width coverage.
    - A regression proves Body/Reason show more visible content at the 80x24 LOG width than before the fix.
    - No rendered LOG line exceeds the framed width budget.
    - `rtk mix test test/foglet_bbs/tui/screens/moderation_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` exits 0.
  </acceptance_criteria>
  <done>Moderation LOG uses the available 80x24 width responsively while preserving the fixed timezone/12-hour behavior.</done>
</task>

<task type="auto">
  <name>Task 3: Run focused Phase 26 gap verification</name>
  <files>.planning/phases/26-layout-width-foundations/26-UAT.md, .planning/phases/26-layout-width-foundations/26-HUMAN-UAT.md</files>
  <read_first>
    - `.planning/phases/26-layout-width-foundations/26-UAT.md`
    - `.planning/phases/26-layout-width-foundations/26-HUMAN-UAT.md`
  </read_first>
  <action>
    After Tasks 1 and 2 land, run the focused automated suites and then re-run only the two remaining manual scenarios from the UAT file:
    - Test 6: `64x22 Boards Overlarge Directory`
    - Test 8: `80x24 Moderation LOG With Long Body/Reason and Non-UTC User Timezone`

    Overwrite the corresponding entries in `26-UAT.md` with the rerun outcomes and update `26-HUMAN-UAT.md` if that checklist is being kept in sync.
  </action>
  <verify>
    <automated>rtk mix test test/foglet_bbs/tui/screens/board_list_test.exs test/foglet_bbs/tui/screens/moderation_test.exs test/foglet_bbs/tui/layout_smoke_test.exs</automated>
    <manual>Re-run the exact SSH checks for tests 6 and 8 from `26-UAT.md`.</manual>
  </verify>
  <acceptance_criteria>
    - Only the two still-open UAT failures are in scope for the rerun.
    - The resulting summaries are ready for another `$gsd-verify-work 26`.
  </acceptance_criteria>
  <done>The remaining Phase 26 gaps have a focused rerun path with no unrelated retest scope.</done>
</task>

</tasks>

<threat_model>
These are presentation-path fixes only. Do not add new persistence writes, authorization branches, or SSH lifecycle side effects. Main risk is overfitting compact layout behavior in one screen and regressing another; keep shared table changes covered by focused tests and smoke assertions.
</threat_model>

<verification>
Run, in order:

1. `rtk mix test test/foglet_bbs/tui/screens/board_list_test.exs test/foglet_bbs/tui/layout_smoke_test.exs`
2. `rtk mix test test/foglet_bbs/tui/screens/moderation_test.exs test/foglet_bbs/tui/layout_smoke_test.exs`
3. `rtk mix precommit`
4. Re-run UAT tests 6 and 8 from `.planning/phases/26-layout-width-foundations/26-UAT.md`
</verification>

<success_criteria>
- The plan addresses only the two gaps still failing after retest.
- The plan is executable by `$gsd-execute-phase 26 --gaps-only`.
- Boards and Moderation LOG both gain regression coverage tied to the observed SSH failures.
</success_criteria>
