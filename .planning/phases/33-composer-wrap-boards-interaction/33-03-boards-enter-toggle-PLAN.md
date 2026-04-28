---
phase: 33-composer-wrap-boards-interaction
plan: 03
type: execute
wave: 1
depends_on: []
files_modified:
  - lib/foglet_bbs/tui/screens/board_list.ex
  - test/foglet_bbs/tui/screens/board_list_test.exs
autonomous: true
requirements:
  - BOARD-01
tags:
  - tui
  - boards
  - raxol
  - interaction

must_haves:
  truths:
    - "D-06: BoardList.handle_key/2 persists BoardTree returned for :node_expanded and :node_collapsed Enter actions"
    - "D-07: board leaf Enter still navigates to :thread_list, sets current_board, and emits {:load_threads, board.id}"
    - "D-08: category expand/collapse remains UI-local with no Foglet.Boards context calls and no commands"
    - "D-11: tests cover category Enter collapse/expand indicator changes, no commands, and board-leaf Enter navigation"
  artifacts:
    - path: "lib/foglet_bbs/tui/screens/board_list.ex"
      provides: "Enter key category toggle handling for Boards screen"
      contains: ":node_collapsed"
    - path: "test/foglet_bbs/tui/screens/board_list_test.exs"
      provides: "Regression coverage for category Enter and board leaf Enter"
      contains: "▸"
---

<objective>
Make Enter on a focused Boards category toggle the category's expanded state in screen-local `BoardTree` state, update the visible `▸`/`▾` indicator, and preserve existing board-leaf Enter navigation.
</objective>

<execution_context>
@/Users/brendan.turner/Dev/personal/foglet_bbs/.codex/get-shit-done/workflows/execute-plan.md
@/Users/brendan.turner/Dev/personal/foglet_bbs/.codex/get-shit-done/templates/summary.md
</execution_context>

<context>
@AGENTS.md
@docs/raxol/getting-started/WIDGET_GALLERY.md
@lib/foglet_bbs/tui/widgets/README.md
@.planning/phases/33-composer-wrap-boards-interaction/33-CONTEXT.md
@.planning/phases/33-composer-wrap-boards-interaction/33-RESEARCH.md
@lib/foglet_bbs/tui/screens/board_list.ex
@lib/foglet_bbs/tui/screens/board_list/state.ex
@lib/foglet_bbs/tui/widgets/list/board_tree.ex
@lib/foglet_bbs/tui/widgets/display/tree.ex
@test/foglet_bbs/tui/screens/board_list_test.exs
</context>

<threat_model>
T-33-02: A category toggle could accidentally trigger board navigation, subscription commands, or persistence. Mitigation: handle only `:node_expanded` and `:node_collapsed` with `{:update, state, []}`, add no context calls, and test command list is exactly empty for category Enter.
</threat_model>

<tasks>

<task type="auto" tdd="false">
  <name>Task 1: Persist category Enter expand/collapse actions in BoardList</name>
  <files>lib/foglet_bbs/tui/screens/board_list.ex</files>
  <read_first>
    - lib/foglet_bbs/tui/screens/board_list.ex
    - lib/foglet_bbs/tui/screens/board_list/state.ex
    - lib/foglet_bbs/tui/widgets/list/board_tree.ex
    - lib/foglet_bbs/tui/widgets/display/tree.ex
  </read_first>
  <action>
    Update `BoardList.handle_key(%{key: :enter}, state)` so the `case BoardTree.handle_event(%{key: :enter}, tree)` branch handles three semantic actions:

    1. `{%BoardTree{} = new_tree, action}` when `action in [:node_expanded, :node_collapsed]`:
       - Return `{:update, put_ss(state, %{ss | board_tree: new_tree}), []}`.
       - Do not set `current_screen`, `current_board`, or `screen_state[:thread_list]`.
       - Do not emit any commands.

    2. `{%BoardTree{} = new_tree, :node_activated}`:
       - Preserve existing board-leaf behavior exactly: if `BoardTree.focused_board_entry(new_tree)` returns `%{board: board}`, set `current_board: board`, set `current_screen: :thread_list`, store `%{ss | board_tree: new_tree}` under `screen_state[:board_list]`, set `screen_state[:thread_list]` to `%{selected_index: 0}`, and emit `[{:load_threads, board.id}]`.
       - If no board is focused, return `:no_match`.

    3. `_other`:
       - Preserve `:no_match`.

    Do not call `Foglet.Boards`, `Domain.get`, Repo, PubSub, subscribe, unsubscribe, thread loading, or any context function for category Enter.
  </action>
  <verify>
    <automated>rtk mix format lib/foglet_bbs/tui/screens/board_list.ex</automated>
  </verify>
  <acceptance_criteria>
    - `rtk rg -n ":node_expanded|:node_collapsed" lib/foglet_bbs/tui/screens/board_list.ex` prints matches.
    - `rtk rg -n "subscribe_to_board|unsubscribe_from_board|load_threads" lib/foglet_bbs/tui/screens/board_list.ex` still shows `load_threads` only in the `:node_activated` board-leaf branch and subscribe/unsubscribe only in their existing helper functions.
    - `rtk mix format lib/foglet_bbs/tui/screens/board_list.ex` exits 0.
  </acceptance_criteria>
</task>

<task type="auto" tdd="false">
  <name>Task 2: Replace category Enter no-op test with toggle and no-command coverage</name>
  <files>test/foglet_bbs/tui/screens/board_list_test.exs</files>
  <read_first>
    - test/foglet_bbs/tui/screens/board_list_test.exs
    - lib/foglet_bbs/tui/screens/board_list.ex
    - lib/foglet_bbs/tui/widgets/list/board_tree.ex
  </read_first>
  <action>
    Replace the existing test named `"enter on a category parent does not open a board"` with tests that prove the new locked behavior.

    Add or update tests to assert:
    - Starting from `BoardList.load_boards(%{state | terminal_size: {64, 22}})`, the initial render contains `"▾"` and `"Tech"`.
    - First `%{key: :enter}` on the focused category returns `{:update, collapsed, []}`.
    - Collapsed render contains `"▸"` and does not contain `"Tech"`.
    - Second `%{key: :enter}` on the same focused category returns `{:update, expanded, []}`.
    - Expanded render contains `"▾"` and `"Tech"`.
    - `collapsed.current_screen == :board_list` and `collapsed.current_board` is unchanged or nil.
    - The existing board-leaf Enter test still passes and still asserts `{:load_threads, "b1"}`.
  </action>
  <verify>
    <automated>rtk mix test test/foglet_bbs/tui/screens/board_list_test.exs</automated>
  </verify>
  <acceptance_criteria>
    - `test/foglet_bbs/tui/screens/board_list_test.exs` contains `terminal_size: {64, 22}` in a category Enter test.
    - `test/foglet_bbs/tui/screens/board_list_test.exs` contains assertions for both `"▸"` and `"▾"`.
    - `test/foglet_bbs/tui/screens/board_list_test.exs` contains `assert cmds == []` or pattern matches `{:update, collapsed, []}` for category Enter.
    - `rtk mix test test/foglet_bbs/tui/screens/board_list_test.exs` exits 0.
  </acceptance_criteria>
</task>

</tasks>

<verification>
Run:

```bash
rtk mix test test/foglet_bbs/tui/screens/board_list_test.exs
rtk mix foglet.tui.render board_list --width 64 --height 22
```
</verification>

<success_criteria>
- Category Enter toggles collapsed then expanded state.
- Visible category glyph changes between `▸` and `▾`.
- Category Enter emits no commands and performs no domain work.
- Board leaf Enter continues navigating to `:thread_list` and emits `{:load_threads, board.id}`.
</success_criteria>
