# Phase 33: Composer Wrap & Boards Interaction - Context

**Gathered:** 2026-04-28 (assumptions mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 33 delivers the locked `POST-02` and `BOARD-01` stabilization fixes: the reply and new-thread body editors visually soft-wrap overlong logical lines using `Foglet.TUI.TextWidth.wrap/2` or an equivalent display-width-aware path without changing `MultiLineInput.value`, and the Boards screen treats Enter on a focused category as a UI-local expand/collapse toggle while preserving Enter-on-board navigation to the thread list. Hard-wrap-on-submit, editor redesign, per-user persisted Boards expansion, web UI, and domain behavior changes remain out of scope.
</domain>

<decisions>
## Implementation Decisions

### Composer Visual Wrap

- **D-01:** Implement composer visual wrapping in the shared `Foglet.TUI.Widgets.Compose.render_input/4` path, not separately in `PostComposer` and `NewThread`. Both screens already delegate edit-mode body rendering to this helper, and wrapping there satisfies reply and new-thread behavior with one shared contract.
- **D-02:** Use `Foglet.TUI.TextWidth.wrap/2` for body display rows while preserving `MultiLineInput.value` as the logical buffer. Rendering may split a logical line into multiple visual `text/2` rows, but submit paths continue reading the original `input_state.value`.
- **D-03:** Keep `MultiLineInput` initialized with `wrap: :none`; this phase adds Foglet-owned visual wrapping around the value rather than relying on Raxol editor state to mutate or manage wrapped text.

### Composer Width And Resize

- **D-04:** Drive wrapping from the current editor width at render time so 80x24 and 64x22 renders reflow from the same stored body string. `PostComposer` and `NewThread` should pass or derive an explicit body-width budget for `Compose.render_input/4`; render must not write resized content back into state.
- **D-05:** Preserve current cursor and key handling through `MultiLineInput.update/2`. Add only enough display mapping for the cursor block to appear in the correct wrapped visual row; do not introduce a replacement editor state model or alternate navigation stack.

### Boards Enter Toggle

- **D-06:** Update `BoardList.handle_key(%{key: :enter}, state)` so `:node_expanded` and `:node_collapsed` results from `BoardTree.handle_event/2` persist the returned `BoardTree` into `screen_state[:board_list]` and return `{:update, state, []}`.
- **D-07:** Keep board leaf Enter behavior unchanged: when `BoardTree.handle_event/2` returns `:node_activated` and `BoardTree.focused_board_entry/1` returns a board, `BoardList` still sets `current_screen: :thread_list`, sets `current_board`, and emits the existing `{:load_threads, board.id}` command.
- **D-08:** Category expand/collapse remains UI-local only. Enter on a category must return no subscribe/unsubscribe/thread/domain mutation commands and must not call any `Foglet.Boards` context function.

### Verification And Tests

- **D-09:** Add focused tests for shared composer wrap behavior, then cover both consuming screens: reply composer and new-thread compose body render an overlong single logical line as multiple visible rows at compact width while the stored value remains byte-equivalent.
- **D-10:** Add resize/reflow coverage using 80x24 and 64x22 render sizes to prove narrower output creates more visual rows without inserting newline characters into the logical buffer.
- **D-11:** Add Boards tests for category Enter collapse/expand indicator changes at compact size, no commands from category Enter, and existing board-leaf Enter navigation command shape.

### the agent's Discretion

- Exact internal helper shape for mapping a logical cursor position onto wrapped visual rows is left to the planner, provided it stays inside `Compose` or a tightly scoped private helper and uses `TextWidth` helpers for display-width safety.
- Exact assertion strategy for visual rows is left to the planner: tests may inspect flattened render output, rendered element rows, or a small helper around `Compose.render_input/4`, as long as they prove wrap occurs without logical-buffer mutation.

### Folded Todos

None.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Locked Requirements

- `.planning/phases/33-composer-wrap-boards-interaction/33-SPEC.md` - Locked Phase 33 requirements, boundaries, constraints, and acceptance criteria.
- `.planning/ROADMAP.md` - Phase 33 goal and success criteria; dependency on Phase 26 `TextWidth.wrap`.
- `.planning/REQUIREMENTS.md` - `POST-02`, `BOARD-01`, and explicit deferrals for hard-wrap-on-submit and persisted board expansion.

### Composer Source

- `lib/foglet_bbs/tui/widgets/compose.ex` - Shared body-editor input rendering and key translation; primary implementation point for visual wrap.
- `lib/foglet_bbs/tui/text_width.ex` - `wrap/2`, `split_at/2`, and display-width helpers for grapheme-safe terminal layout.
- `lib/foglet_bbs/tui/screens/post_composer.ex` - Reply composer render path, submit path, and `Compose.render_input/3` usage.
- `lib/foglet_bbs/tui/screens/post_composer/state.ex` - Reply composer `MultiLineInput` initialization with `wrap: :none`.
- `lib/foglet_bbs/tui/screens/new_thread.ex` - New-thread compose render path and body editor delegation.
- `lib/foglet_bbs/tui/screens/new_thread/state.ex` - New-thread body `MultiLineInput` initialization with `wrap: :none`.
- `lib/foglet_bbs/tui/widgets/composer/editor_frame.ex` - Shared composer shell that frames the body rows and counters.

### Boards Source

- `lib/foglet_bbs/tui/screens/board_list.ex` - Boards screen key handling; Enter branch currently only handles board leaf activation.
- `lib/foglet_bbs/tui/screens/board_list/state.ex` - Screen-local `board_tree` state holder.
- `lib/foglet_bbs/tui/widgets/list/board_tree.ex` - Board directory facade; category glyphs `▾`/`▸`, focused entry helpers, and delegation to `Display.Tree`.
- `lib/foglet_bbs/tui/widgets/display/tree.ex` - Tree action derivation for `:node_expanded`, `:node_collapsed`, and `:node_activated`.

### Tests And Verification

- `test/foglet_bbs/tui/text_width_test.exs` - Existing coverage for `TextWidth.wrap/2` behavior.
- `test/foglet_bbs/tui/screens/post_composer_test.exs` - Reply composer render, key handling, and submit tests to extend.
- `test/foglet_bbs/tui/screens/new_thread_test.exs` - New-thread render and submit tests to extend.
- `test/foglet_bbs/tui/screens/board_list_test.exs` - Existing board leaf Enter and left/right expand tests to extend for category Enter.
- `test/foglet_bbs/tui/widgets/composer/editor_frame_test.exs` - Shared composer shell tests; useful reference for row/body assertions.
- `rtk mix foglet.tui.render post_composer --width 64 --height 22` - Visual inspection path for compact composer layout.
- `rtk mix foglet.tui.render board_list --width 64 --height 22` - Visual inspection path for compact Boards layout.

### Project Conventions

- `AGENTS.md` - TUI screen/widget ownership, theme routing, render purity, and `rtk mix precommit` finish line.
- `docs/raxol/getting-started/WIDGET_GALLERY.md` - Raxol layout primitive reference.
- `lib/foglet_bbs/tui/widgets/README.md` - Widget ownership, theme-routing, and stateful/stateless widget conventions.
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- `Foglet.TUI.TextWidth.wrap/2` already preserves existing newline boundaries, handles display-width wrapping, and has tests for ASCII, wide graphemes, combining marks, emoji, blank lines, empty input, and invalid widths.
- `Foglet.TUI.Widgets.Compose.render_input/4` is the shared edit-body renderer for both composer surfaces. It currently splits only on real newline characters and injects the cursor with `TextWidth.split_at/2`.
- `Foglet.TUI.Widgets.Composer.EditorFrame.render/1` accepts pre-rendered body children, so it can frame multiple visual rows without knowing whether they came from logical or wrapped lines.
- `Foglet.TUI.Widgets.List.BoardTree.handle_event/2` already exposes `:node_expanded`, `:node_collapsed`, and `:node_activated` actions. Its render path already shows category state through `▾` and `▸`.

### Established Patterns

- Composer screens own key handling and state; `Compose` owns the shared input rendering helper. Keeping wrap in `Compose` matches the existing Phase 4 extraction boundary.
- Render functions stay pure over already-loaded state. Composer wrapping and Boards category toggling should not touch Repo, PubSub, or domain contexts.
- Board expand/collapse state already lives in `BoardTree` under `state.screen_state[:board_list]`; no schema, config, or context change is needed.
- Board leaf navigation is command-based and screen-local: update screen state, then emit `{:load_threads, board.id}` for the app to handle.

### Integration Points

- `PostComposer.render/1` calls `composer_body(:edit, ...)`, which delegates to `render_input/3`, which calls `Compose.render_input/3`.
- `NewThread.render_body_section/3` calls `Compose.render_input/4` for edit mode and `MarkdownBody.render/3` for preview mode; only edit mode is in scope.
- `BoardList.handle_key/2` handles arrows through `handle_tree_key/2`, but has a bespoke Enter branch. That Enter branch should be expanded to persist category toggle actions as well as board activation.
- `BoardTree.focused_board_entry/1` intentionally hides tree internals from `BoardList`; keep using it for leaf navigation rather than pattern matching on Raxol tree state in the screen.
</code_context>

<specifics>
## Specific Ideas

- Cursor rendering should remain visually simple: the existing `█` cursor block can move to the wrapped visual row that contains the logical cursor offset.
- Category Enter should feel like parity with the existing Left/Right controls, not a new command mode. The command bar can continue advertising `←/→ Collapse/Expand` and `Enter Open`; no new UI copy is required unless implementation makes the existing hint misleading.
</specifics>

<deferred>
## Deferred Ideas

- `POST-FUT-01`: hard-wrap-on-submit or a user option to insert real newlines at a configured column.
- `BOARD-FUT-01`: persisted per-user Boards expand/collapse state across sessions.
- Composer redesign or replacement with a new full-screen editing model.
- Browser workflows for composing posts or browsing boards.

### Reviewed Todos (not folded)

None - no pending todos matched Phase 33.
</deferred>

---

*Phase: 33-composer-wrap-boards-interaction*
*Context gathered: 2026-04-28*
