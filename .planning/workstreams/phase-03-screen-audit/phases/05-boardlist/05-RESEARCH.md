# Phase 5: BoardList — Research

**Researched:** 2026-04-22
**Domain:** Elixir TUI screen audit — BoardList helper/state cleanup, loading affordance, and dead-code seam disposition
**Confidence:** HIGH (grounded in direct reads of `board_list.ex`, `app.ex`, `board_list_test.exs`, and workstream roadmap/requirements/context)

## Summary

Phase 5 is a focused, low-risk audit pass on `lib/foglet_bbs/tui/screens/board_list.ex`.
The screen already uses `SelectionList` + `ListRow` correctly and already routes
Theme/Domain through Phase-0 helpers (`Theme.from_state/1`, `Screens.Domain.get/2`).

Remaining required deltas are specific and bounded:

1. Add `init_screen_state/1` and remove repeated inline defaults like `%{selected_index: 0}` (`AUDIT-19`).
2. Resolve `load_boards/1` dead-code ambiguity by keeping it as a documented test seam (`@doc false`) because production loading is owned by `App.do_update({:load_boards}, state)` (`BOARDS-02`, `AUDIT-12`).
3. Replace static loading text with a spinner-backed loading row for the real async load path (`BOARDS-03`, user-locked decision in `05-CONTEXT.md` D-01/D-02).
4. Keep list widget usage and row-gutter restraint unchanged (`BOARDS-04`, `AUDIT-17 Region 2`).

## Current Code Read

### `lib/foglet_bbs/tui/screens/board_list.ex`

- Uses `Theme.from_state(state)` in `render/1` and `Domain.get/2` fallback in `domain_module/2` (already compliant with BOARDS-01).
- Uses `SelectionList.render/3` + `ListRow.render/3` for loaded rows (already compliant with BOARDS-04).
- Repeats `%{selected_index: 0}` fallback in multiple functions (`render/1`, `handle_key/2`, `move_selection/2`) and lacks public `init_screen_state/1`.
- Uses plain `text("Loading...", ...)` for pending list load (ASCII `...`, no spinner).
- Exposes public `load_boards/1` with a public docstring implying production ownership, but App owns real loading.

### `lib/foglet_bbs/tui/app.ex`

- Production board loading is implemented in `do_update({:load_boards}, state)` and handled by `{:boards_loaded, boards}`.
- Screen command processing dispatches `{:load_boards}` tuples from screens into App update flow.
- This confirms `BoardList.load_boards/1` is not part of production dispatch.

### `test/foglet_bbs/tui/screens/board_list_test.exs`

- Multiple tests call `BoardList.load_boards/1` directly, confirming it is actively used as a test seam.
- This supports the Phase 5 decision to keep but hide/document the function (`@doc false`) rather than delete.

## Evidence Snapshot

- `wc -l lib/foglet_bbs/tui/screens/board_list.ex` => `120` (pre-phase baseline).
- `rg -n "load_boards" lib test` shows `BoardList.load_boards/1` callsites in `board_list_test.exs` and no production call path.
- Current loading text in BoardList is `"Loading..."` (to be normalized to `"Loading…"` while adopting spinner row).

## Validation Architecture

### Automated checks

- Focused suite: `mix test test/foglet_bbs/tui/screens/board_list_test.exs`
- Full project gate: `mix precommit`
- Scope fence check: `git diff --name-only` only touches:
  - `lib/foglet_bbs/tui/screens/board_list.ex`
  - `test/foglet_bbs/tui/screens/board_list_test.exs`
- Dead-code audit evidence: `rg -n "load_boards" lib test`
- AUDIT-05 gate checks (single-file):
  - `rg -n ':red|:green|:cyan|:yellow|:blue|:magenta|:white|:black|"#[0-9a-fA-F]{6}"|\\e\[|\\x1b|%\{.*theme.*\||box style.*border|IO\.(write|puts|inspect)|\{80, 24\}|\(Map\.get\(state, :session_context\) \|\| %\{\}\) \|> Map\.get\(:theme\)|get_in\(ctx, \[:domain' lib/foglet_bbs/tui/screens/board_list.ex`

### Required behavior assertions

- `j`/`k`/Enter navigation behavior unchanged.
- `Q/q` behavior unchanged.
- Loading state is now spinner-backed and only shown during real in-flight load (`state.board_list == nil`).
- Empty state (`state.board_list == []`) stays warning text and no row-gutter additions.
- `init_screen_state/1` exists and is used for default fallback state.

## Risks and Landmines

- Do not add any extra board-row metadata in left/right gutters (reserved for M4/M6).
- Do not alter `SelectionList` or `ListRow` usage pattern.
- Do not move production loading ownership from App into BoardList.
- Do not split this into cross-screen cleanup; Phase 5 is single-screen scope.

## Recommended Plan Shape

One execute plan in Wave 1 covering:

1. BoardList code updates (initializer, spinner loading affordance, `load_boards/1` doc-seam clarification).
2. BoardList tests updated to lock new initializer/spinner/dead-code-seam expectations while preserving existing navigation invariants.

