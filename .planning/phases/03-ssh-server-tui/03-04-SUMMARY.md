---
plan: 03-04
phase: 03-ssh-server-tui
status: complete
completed_at: 2026-04-18
---

# Plan 03-04 Summary: BBS Screens — MainMenu, BoardList, ThreadList, PostReader, PostComposer

## What Was Built

Replaced all five Plan 03 stub screens with real implementations. Wired read-pointer tracking (SSH-09) and the PostComposer with Markdown/preview toggle (D-28), Ctrl+S submit (D-29), Ctrl+C cancel (D-30), and max_post_length enforcement (D-31). All 259 tests pass; no pending stubs remain anywhere in Phase 3.

## Key Deliverables

### MainMenu

- Single-key shortcuts: `B`/`b` → `:board_list` + `{:load_boards}` command; `C`/`c` → `:post_composer` (new thread, empty draft); `Q`/`q` → `{:terminate, :logout}`
- Uses `StatusBar` + `KeyBar` widgets

### BoardList

- Domain-adapter pattern: `domain_module(state, :boards)` resolves to injected fake or `Foglet.Boards`
- `load_boards/1` calls `boards_mod.list_subscribed_boards/1`; graceful fallback to `[]` when Phase 2 not executed
- Selection state in `state.screen_state[:board_list][:selected_index]`; `j`/`k`/`↑`/`↓` navigation bounded by list length
- Enter transitions to `:thread_list` + `{:load_threads, board_id}` command
- `render_board_rows/2` and `render_board_row/3` extracted to keep `render/1` under cyclomatic complexity limit

### ThreadList

- `load_threads/2` calls `threads_mod.list_threads/1` via domain adapter
- `sort_threads/1`: sticky-first, then newest-`last_post_at`-first within each group
- `render_thread_rows/2` and `render_thread_row/3` extracted for complexity
- Enter → `:post_reader` + `{:load_posts, thread_id}`; `C` → composer (new thread); `Q` → `:board_list`

### PostReader

- `load_posts/2` calls `posts_mod.list_posts/1` via domain adapter
- `render_post_content/2` extracted to two clauses (empty/loading vs active post); `render_post_items/4` uses domain adapter for `Foglet.Markdown.render/1`
- `n`/`N`/space → next post; `p`/`P` → prev; `R` → composer with `reply_to` set in screen_state
- Local read-pointer: `state.read_position[thread_id]` updated on each `advance_post/2`
- SSH-09 flush: `Q` emits `{:flush_read_pointers, ctx}` — App dispatches to `flush_read_pointers/2`
- `flush_read_pointers/2` extracted into `flush_board_pointer/3`, `flush_thread_pointer/3`, `clear_read_position/2` to satisfy cyclomatic complexity limit

### PostComposer

- Layout: header, optional quote context (first 5 lines of reply-to, D-27), text buffer, char count, key bar
- Tab toggles `screen_state[:post_composer][:mode]` between `:edit` and `:preview` (D-28)
- Ctrl+S: validates non-empty + length ≤ `max_post_length`; calls `posts_mod.create_reply/3`; transitions to `:post_reader` on success (D-29)
- Ctrl+C: immediate cancel to `:thread_list`, no confirmation (D-30)
- `max_post_length` sourced from `session_context[:max_post_length]` → `Config.get!("max_post_length")` → `@default_max_post_length` (8192) (D-31)

### App.ex Updates

- Added `current_thread_list: nil` to `defstruct` and `@type t`
- Added `do_update/2` clauses for `{:load_boards}`, `{:load_threads, board_id}`, `{:load_posts, thread_id}`, `{:flush_read_pointers, ctx}`

## Domain Adapter Pattern

All five screens use the same pattern:

```elixir
defp domain_module(state, key) do
  ctx = Map.get(state, :session_context) || %{}
  get_in(ctx, [:domain, key]) || default_domain(key)
end
```

Tests inject fake modules via `session_context: %{domain: %{boards: FakeBoards, ...}}`. Production uses real `Foglet.Boards`/`Threads`/`Posts`/`Markdown` modules with `function_exported?/3` guards for graceful Phase 2 fallback.

## Test Results

- 63 screen tests green (main_menu: 5, board_list: 7, thread_list: 6, post_reader: 7, post_composer: 8 + prior login/register/verify: 26, modal: 5)
- Full suite: 259 tests + 1 property, 0 failures
- Zero `@tag :pending` remaining anywhere in `test/foglet_bbs/tui/`
- `mix precommit` exits 0

## Raxol Key Event Format

All key events use string map format (`%{key: "ctrl_s"}`, `%{key: "tab"}`, `%{key: "enter"}`) matching the existing Login/Verify/Register patterns. No adjustments were needed from the plan's assumed format.

## Phase 2 API Availability at Test Time

At test time, Phase 2 IS executed (all domain modules present). The `function_exported?/3` guards were exercised in tests via the domain adapter injection pattern — fake modules with the correct function signatures were used rather than the real Phase 2 modules, ensuring isolation.

## Manual Verification Items (for `/gsd-verify-work`)

1. SSH into dev daemon, complete login + verify, navigate: Main Menu → Boards → board → thread → read posts (read pointers advance in `state.read_position`) → reply (composer opens with quote context) → Tab toggles preview → Ctrl+S submits → new post appears → Ctrl+C cancels other compose → Q to main menu
2. Terminal resize during reading — TUI re-layouts without crashing (SSH-06)
3. `Foglet.Boards.list_subscribed_boards/1` returns subscribed boards with `unread_count` field populated from Phase 2 read pointers
4. PostReader `flush_read_pointers/2` actually persists to DB via `Foglet.Boards.advance_board_read_pointer/3` and `Foglet.Threads.advance_read_pointer/3` (live Phase 2 integration)

## Self-Check: PASSED

- `grep 'def load_boards' lib/foglet_bbs/tui/screens/board_list.ex` — matches
- `grep 'def load_posts' lib/foglet_bbs/tui/screens/post_reader.ex` — matches
- `grep 'def flush_read_pointers' lib/foglet_bbs/tui/screens/post_reader.ex` — matches
- `grep ':flush_read_pointers' lib/foglet_bbs/tui/screens/post_reader.ex` — matches
- `grep 'advance_board_read_pointer' lib/foglet_bbs/tui/screens/post_reader.ex` — matches
- `grep 'advance_read_pointer' lib/foglet_bbs/tui/screens/post_reader.ex` — matches
- `grep 'max_post_length' lib/foglet_bbs/tui/screens/post_composer.ex` — matches
- `grep ':flush_read_pointers' lib/foglet_bbs/tui/app.ex` — matches
- `grep 'current_thread_list' lib/foglet_bbs/tui/app.ex` — matches
- `grep -r '@tag :pending' test/foglet_bbs/tui/` — no matches
- `mix test` — 259 tests + 1 property, 0 failures
- `mix precommit` exits 0
