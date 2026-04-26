---
phase: 26
plan: 03
type: execute
wave: 2
depends_on: [01]
files_modified:
  - lib/foglet_bbs/tui/screens/board_list.ex
  - lib/foglet_bbs/tui/widgets/list/board_tree.ex
  - test/foglet_bbs/tui/screens/board_list_test.exs
  - test/foglet_bbs/tui/widgets/list/board_tree_test.exs
  - test/foglet_bbs/tui/layout_smoke_test.exs
autonomous: true
requirements:
  - LAYOUT-03
user_setup: []
tags:
  - tui
  - boards
  - viewport
  - elixir
must_haves:
  truths:
    - "Boards category+board list is constrained to the available body region at 64x22."
    - "Boards row width is a drawable inner-frame width, not raw terminal columns; at 64 columns the tree/details budget must be no greater than the frame-safe content width."
    - "Excess boards remain reachable with existing Up/Down navigation."
    - "Selection/cursor ownership stays in `BoardTree` / `Display.Tree`; no parallel screen-local selected index is introduced."
---

<objective>
Constrain the Boards screen's category+board tree to an internal visible region so overlarge directories stay inside the 64x22 frame and remain navigable.
</objective>

<context>
@.planning/phases/26-layout-width-foundations/26-CONTEXT.md
@.planning/phases/26-layout-width-foundations/26-RESEARCH.md
@.planning/phases/26-layout-width-foundations/26-SPEC.md
@lib/foglet_bbs/tui/screens/board_list.ex
@lib/foglet_bbs/tui/widgets/list/board_tree.ex
@lib/foglet_bbs/tui/widgets/display/tree.ex
@test/foglet_bbs/tui/screens/board_list_test.exs
@test/foglet_bbs/tui/widgets/list/board_tree_test.exs
@test/foglet_bbs/tui/layout_smoke_test.exs
</context>

<tasks>

<task type="auto">
  <name>Task 1: Add BoardTree visible-height windowing</name>
  <files>lib/foglet_bbs/tui/widgets/list/board_tree.ex, test/foglet_bbs/tui/widgets/list/board_tree_test.exs</files>
  <read_first>
    - lib/foglet_bbs/tui/widgets/list/board_tree.ex
    - lib/foglet_bbs/tui/widgets/display/tree.ex
    - test/foglet_bbs/tui/widgets/list/board_tree_test.exs
  </read_first>
  <action>
    Extend `BoardTree.render/2` to accept optional `visible_height: n`.

    Required behavior:
    - Default remains current behavior when `visible_height` is absent or `:all`.
    - When `visible_height` is an integer, derive the current cursor position from `tree.raxol_state.cursor` and `RaxolTree.visible_nodes(rs)`.
    - Render a contiguous window of at most `visible_height` visible rows that includes the cursor.
    - Do not mutate cursor or expanded state during render.
    - Preserve existing row rendering and width truncation. The `width:` option remains a drawable content width supplied by the caller, not raw terminal columns.
  </action>
  <verify>
    <automated>rtk mix test test/foglet_bbs/tui/widgets/list/board_tree_test.exs</automated>
  </verify>
  <acceptance_criteria>
    - `rtk rg -n "visible_height" lib/foglet_bbs/tui/widgets/list/board_tree.ex test/foglet_bbs/tui/widgets/list/board_tree_test.exs` returns matches in both files.
    - A BoardTree test builds more than 20 visible rows, renders with `visible_height: 8`, and asserts top-level rendered row count is `<= 8`.
    - A BoardTree test moves the cursor below the initial window and asserts the focused board label appears in the rendered text.
    - `rtk mix test test/foglet_bbs/tui/widgets/list/board_tree_test.exs` exits 0.
  </acceptance_criteria>
</task>

<task type="auto">
  <name>Task 2: Apply compact Boards screen body budgeting</name>
  <files>lib/foglet_bbs/tui/screens/board_list.ex, test/foglet_bbs/tui/screens/board_list_test.exs, test/foglet_bbs/tui/layout_smoke_test.exs</files>
  <read_first>
    - lib/foglet_bbs/tui/screens/board_list.ex
    - lib/foglet_bbs/tui/widgets/list/board_tree.ex
    - test/foglet_bbs/tui/screens/board_list_test.exs
    - test/foglet_bbs/tui/layout_smoke_test.exs
  </read_first>
  <action>
    Add `body_height(state)` to `BoardList` and pass `visible_height:` into `BoardTree.render/2`.

    Concrete target:
    - At `{64, 22}`, use `visible_height = max(body_height - reserved_rows, 3)`.
    - Keep `row_width(state)` as a drawable content-width helper. For `{cols, rows}`, subtract the frame border and padding before passing `width:` to `BoardTree.render/2`, `details_strip/4`, or `wide_inspector/4`; do not pass raw `cols`.
    - Reserve rows for feedback if present, the detail strip when it can fit, and wide inspector only at `width >= 100`.
    - At compact height, omit the blank spacer line before details if it would push rows below the frame.
    - Keep `details_strip/4` at compact width only if there is at least one reserved row; otherwise primary tree wins.
    - Do not implement category Enter toggling; Phase 33 owns `BOARD-01`.
  </action>
  <verify>
    <automated>rtk mix test test/foglet_bbs/tui/screens/board_list_test.exs test/foglet_bbs/tui/layout_smoke_test.exs</automated>
  </verify>
  <acceptance_criteria>
    - `rtk rg -n "visible_height:" lib/foglet_bbs/tui/screens/board_list.ex` returns one match.
    - `rtk rg -n "body_height" lib/foglet_bbs/tui/screens/board_list.ex` returns at least one match.
    - BoardList tests include an overlarge directory fixture with more rows than the compact visible region and assert rendered row count stays bounded.
    - Layout smoke includes Boards at `{64, 22}` with overlarge data and no rendered text y-position outside the screen height.
    - Layout smoke includes Boards at `{64, 22}` with no rendered text line where `x + display_width(text) > 64`; tree/detail content budgets used by the screen are `<= 60`.
    - Existing BoardList navigation tests still pass.
    - `rtk mix test test/foglet_bbs/tui/screens/board_list_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` exits 0.
  </acceptance_criteria>
</task>

</tasks>

<threat_model>
Presentation-only tree windowing. No board mutations or subscription commands change. Risk is misleading navigation if focused rows disappear; tests must prove the focused entry remains visible after cursor movement.
</threat_model>

<verification>
- `rtk mix test test/foglet_bbs/tui/widgets/list/board_tree_test.exs`
- `rtk mix test test/foglet_bbs/tui/screens/board_list_test.exs`
- `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs`
</verification>

<success_criteria>
- Overlarge Boards directories render inside 64x22 frame bounds.
- Focused row remains visible while navigating.
- Details/inspector output yields to primary tree content at compact sizes.
</success_criteria>
