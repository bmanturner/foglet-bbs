---
phase: 03-ssh-server-tui
plan: "07"
subsystem: tui
tags: [gap-closure, keybar, modal, markdown, new-thread, preview]
dependency_graph:
  requires: []
  provides:
    - KeyBar pinned to bottom across all 9 screens (justify_content: :space_between)
    - StatusBar divider on Main Menu
    - Modal word-wrap at 50 chars, correct key hint, screen_state cleared on dismiss
    - Markdown.render/1 returns [{text, style_atom}] tuple list
    - NewThread edit/preview toggle via Tab on body field
    - PostComposer and PostReader render formatted Markdown output
  affects:
    - lib/foglet_bbs/markdown.ex
    - lib/foglet_bbs/tui/screens/main_menu.ex
    - lib/foglet_bbs/tui/screens/login.ex
    - lib/foglet_bbs/tui/screens/new_thread.ex
    - lib/foglet_bbs/tui/screens/post_composer.ex
    - lib/foglet_bbs/tui/screens/post_reader.ex
    - lib/foglet_bbs/tui/widgets/modal.ex
tech_stack:
  added: []
  patterns:
    - justify_content: :space_between two-child column for KeyBar pinning
    - marker-based two-pass Markdown parser (HTML -> NUL-delimited markers -> tuples)
    - render_markdown_tuples/1 private helper in each consuming screen
key_files:
  created: []
  modified:
    - lib/foglet_bbs/markdown.ex
    - lib/foglet_bbs/tui/screens/main_menu.ex
    - lib/foglet_bbs/tui/screens/login.ex
    - lib/foglet_bbs/tui/screens/register.ex
    - lib/foglet_bbs/tui/screens/verify.ex
    - lib/foglet_bbs/tui/screens/board_list.ex
    - lib/foglet_bbs/tui/screens/thread_list.ex
    - lib/foglet_bbs/tui/screens/post_reader.ex
    - lib/foglet_bbs/tui/screens/post_composer.ex
    - lib/foglet_bbs/tui/screens/new_thread.ex
    - lib/foglet_bbs/tui/widgets/modal.ex
    - test/foglet_bbs/markdown_test.exs
    - test/foglet_bbs/tui/screens/main_menu_test.exs
    - test/foglet_bbs/tui/screens/login_test.exs
    - test/foglet_bbs/tui/screens/new_thread_test.exs
    - test/foglet_bbs/tui/screens/post_composer_test.exs
    - test/foglet_bbs/tui/screens/post_reader_test.exs
    - test/foglet_bbs/tui/widgets/modal_test.exs
    - test/foglet_bbs/tui/layout_smoke_test.exs
decisions:
  - Marker-based two-pass Markdown parser chosen over Floki (no new dep required)
  - render_markdown_tuples/1 duplicated into 3 screen modules (not extracted to shared module — only 3 consumers, revisit if 4th appears)
  - compose_tab_hint/1 extracted as a separate function to keep render_compose_step cyclomatic complexity within credo limit
metrics:
  duration: ~45 minutes
  completed: "2026-04-19T17:57:52Z"
  tasks_completed: 3
  files_modified: 19
---

# Phase 03 Plan 07: UAT Gap Closure — KeyBar, Modal, Markdown Preview, NewThread Composer

One-liner: Closed 5 UAT gaps — KeyBar pinning via justify_content, modal word-wrap + routing fix, Markdown.render/1 rewritten to return `[{text, style_atom}]` tuples, and NewThread composer gained Tab-toggleable edit/preview mode.

## Tasks Completed

### Task 1: Fix KeyBar pinning and StatusBar divider across all 9 screens (Gaps 1 and 2)

Commit: e4c2844

All 9 screen files (`login.ex`, `register.ex`, `verify.ex`, `main_menu.ex`, `board_list.ex`, `thread_list.ex`, `post_reader.ex`, `post_composer.ex`, `new_thread.ex`) were restructured:

- Removed `spacer(flex: 1)` from all screens (it silently drops the `:flex` key in Raxol's layout engine)
- Changed the outer column style to `%{gap: 0, justify_content: :space_between}`
- Wrapped all pre-KeyBar content into a nested inner `column style: %{gap: 0}` as child 1
- KeyBar becomes child 2 — space-between pushes it to the bottom

`main_menu.ex` also received the Gap 2 fix: `divider()` added immediately after `StatusBar.render(...)`.

Tests added to `main_menu_test.exs`:
- Gap 1: asserts `justify_content: :space_between` is present in rendered tree
- Gap 2: asserts a divider element appears after the StatusBar row (tree traversal helper)

### Task 2: Fix pending/suspended modal overflow, dismiss routing, and key hint (Gap 3)

Commit: 200f163

**modal.ex (Gap 3a + Gap 3c):**
- Added `@wrap_width 50` module attribute
- Added `word_wrap/2` private helper (whitespace-boundary splitting)
- Changed `render/1` to call `word_wrap(msg, @wrap_width)` and emit one `text/2` per wrapped line
- Changed `key_hint_for(_)` from `"[Enter] OK   [Esc] Dismiss"` to `"[Enter] OK"` — Esc is not advertised as a separate dismiss key

**login.ex (Gap 3b):**
- Changed `:pending` and `:suspended` clauses in `submit_login/1` to include `screen_state: %{}` alongside `modal:` — ensures dismissing the modal returns to the Login landing menu, not the login form

Tests added:
- modal_test.exs: Test A (120-char message wraps to ≤50-char lines), Test B (`:info` ends with `"[Enter] OK"` only), Test C (`:confirm` still shows `"[Y] Yes   [N] No"`)
- login_test.exs: Test D (`:pending` user sets `screen_state: %{}`), Test E (`:suspended` user sets `screen_state: %{}`)

### Task 3: Restructure Markdown.render/1 and add preview tabs to New Thread (Gaps 4 and 5)

Commit: 7d1c143

**markdown.ex (Gap 5, part 1) — full rewrite:**
- Changed `@spec render/1` return type from `String.t()` to `[{String.t(), style_atom()}]`
- Kept `strip_ansi/1` unchanged (T-2-03 preserved — ESC bytes stripped before MDEx parse)
- New marker-based two-pass pipeline:
  1. `strip_ansi/1` strips raw ESC sequences from user input
  2. `MDEx.to_html!/1` parses CommonMark to HTML
  3. `transform_html_to_markers/1` replaces HTML tags with `\x00BOLD_OPEN\x00`-style markers
  4. `parse_markers/1` splits on markers and reduces to `[{text, style_atom}]`
  5. `clean_tuples/1` splits plain text on `\n`, deduplicates consecutive newlines
- Removed `String.trim_trailing()` from `transform_html_to_markers/1` to preserve block-level `{"\n", :plain}` separators (heading test required this)

markdown_test.exs completely rewritten with 23 tests covering: bold, italic, inline code, headings, plain text, mixed content, ANSI injection defense (T-2-03), links, images, code blocks.

**post_composer.ex + post_reader.ex (Gap 5, part 2):**
- Added private `render_markdown_tuples/1` helper to both modules
- `post_composer.ex`: `:preview` branch now calls `render_markdown_tuples(render_preview(state, draft))` instead of `text(render_preview(...), fg: :green)`
- `render_preview/2` fallback changed to return `[{draft, :plain}]` (was returning bare string)
- `post_reader.ex`: `render_post_items/4` now calls `render_markdown_tuples(markdown_mod.render(body))` and embeds the column element directly

**new_thread.ex (Gap 4):**
- Added `mode: :edit` to `init_screen_state/1` map
- Added `render_body_section/2` helper (extracted from render_compose_step to reduce complexity)
- Added `compose_tab_hint/1` helper using pattern matching for the three Tab hint states
- Added `render_preview_text/2` to call the injected markdown module
- Added `render_markdown_tuples/1` (same helper as post_composer/post_reader)
- `render_compose_step/2` now uses `body_section = render_body_section(state, ss)` with mode-aware rendering
- Tab handler changed from simple focus toggle to: `if focused == :body -> toggle mode, else -> advance focus`
- KeyBar hint shows "Preview" / "Edit" / "Switch field" based on focus + mode

new_thread_test.exs updated:
- Added `mode: :edit` to `compose_state/1` helper and all inline `ss` maps
- Replaced "Tab switches focus from :body to :title" test with new Tests 8, 9, 10:
  - Test 8: Tab on `:body` in `:edit` mode → `mode` becomes `:preview`
  - Test 9: Tab on `:body` in `:preview` mode → `mode` becomes `:edit`
  - Test 10: Tab on `:title` advances focus to `:body`, mode stays `:edit`

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Heading test failure after markdown rewrite**
- Found during: Task 3 step 3a GREEN verification
- Issue: `String.trim_trailing()` in `transform_html_to_markers/1` was stripping the `\n` block separator emitted by heading replacements, causing `# Title` to return `[{"TITLE", :underline}]` without the required `{"\n", :plain}`
- Fix: Removed `String.trim_trailing()` call — block newlines are preserved as `{"\n", :plain}` tuples
- Files modified: `lib/foglet_bbs/markdown.ex`
- Commit: 7d1c143

**2. [Rule 1 - Bug] FakeMarkdown in post_composer_test and post_reader_test returned bare string**
- Found during: Task 3 step 3b test run
- Issue: `FakeMarkdown.render/1` returned `"MD[...]"` string instead of `[{text, style_atom}]` tuple list; `render_markdown_tuples/1` guards `is_list(tuples)` raised FunctionClauseError
- Fix: Updated both `FakeMarkdown` test modules to return `[{"MD[...]", :plain}]`
- Files modified: `test/foglet_bbs/tui/screens/post_composer_test.exs`, `test/foglet_bbs/tui/screens/post_reader_test.exs`
- Commit: 7d1c143

**3. [Rule 1 - Bug] layout_smoke_test compose step ss map missing :mode key**
- Found during: Task 3 full TUI test suite run
- Issue: `test/foglet_bbs/tui/layout_smoke_test.exs` built an inline compose step `ss` map without `mode:` — `render_compose_step/2` raised `KeyError: key :mode not found`
- Fix: Added `mode: :edit` to the inline map at line 586
- Files modified: `test/foglet_bbs/tui/layout_smoke_test.exs`
- Commit: 7d1c143

**4. [Rule 2 - Credo] Refactoring fixes required by mix precommit**
- Found during: `mix credo --strict` run (part of precommit alias)
- Issues: `Enum.map/2 |> Enum.join/2` → `Enum.map_join/3`; `cond` with one condition → `if`; cyclomatic complexity > 9 in `render_compose_step/2`; double `Enum.reject` in modal_test; string with >3 quotes in markdown_test
- Fix: Applied all credo-suggested refactors; extracted `compose_tab_hint/1` and `render_body_section/2` to reduce cyclomatic complexity
- Files modified: `lib/foglet_bbs/markdown.ex`, `lib/foglet_bbs/tui/screens/new_thread.ex`, `test/foglet_bbs/tui/widgets/modal_test.exs`, `test/foglet_bbs/markdown_test.exs`
- Commit: 7d1c143

## Known Stubs

None — all plan goals are implemented and wired to real data.

## Deferred Issues

**Pre-existing Dialyzer failures in `lib/foglet_bbs/ssh/cli_handler.ex`** (57 total errors, 54 skipped): These exist in the codebase prior to this plan and are not caused by any changes in 03-07. Files modified in this plan introduce no new Dialyzer warnings. This is out of scope for this plan.

**`render_markdown_tuples/1` is duplicated in 3 modules** (PostComposer, PostReader, NewThread): The plan explicitly calls for duplication at this stage. If a 4th consumer appears, extract to `Foglet.TUI.Widgets.MarkdownRenderer` or similar.

## Threat Flags

None — all security-relevant surfaces were covered by the existing threat model (T-03-gc3-01, T-03-gc3-03). The new `render_markdown_tuples/1` helper renders only parsed tuples from `Markdown.render/1`, which itself runs `strip_ansi/1` before parsing — no new injection surface introduced.

## Self-Check: PASSED

- FOUND: lib/foglet_bbs/markdown.ex
- FOUND: lib/foglet_bbs/tui/screens/new_thread.ex
- FOUND: lib/foglet_bbs/tui/screens/post_composer.ex
- FOUND: lib/foglet_bbs/tui/screens/post_reader.ex
- Commits e4c2844, 200f163, 7d1c143 all exist in git log
- `grep -rn "spacer(flex" lib/foglet_bbs/tui/screens/` returns zero matches
- `justify_content: :space_between` count: 10 (9 screens + new_thread has 2 render functions)
- `mix test test/foglet_bbs/tui/ test/foglet_bbs/markdown_test.exs` → 239 tests, 0 failures
