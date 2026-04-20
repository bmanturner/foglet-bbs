---
phase: 07-migrate-hand-rolled-ui-components-to-raxol-widgets
plan: "03"
subsystem: tui-screens
tags:
  - raxol
  - viewport
  - post-reader
  - phase-07
  - tdd

dependency_graph:
  requires:
    - "PostCard.render_body_lines/5 (Plan 07-02)"
    - "Raxol.UI.Components.Display.Viewport.init/1, update/2, render/2"
  provides:
    - "PostReader screen_state[:post_reader] with :viewport (Viewport state) instead of :scroll_offset"
    - "scroll_post/2 delegates to Viewport.update({:scroll_by, delta})"
    - "advance_post/2 resets via Viewport.update({:scroll_to, 0})"
    - "warm_viewport/4 — syncs Viewport children for correct content_height clamping"
  affects:
    - "Any caller relying on screen_state[:post_reader][:scroll_offset] (none outside post_reader.ex)"

tech_stack:
  added: []
  patterns:
    - "Viewport as scroll-state owner — init once in default_screen_state, update via messages"
    - "warm_viewport/4 pattern: populate children before any scroll_by call to give Viewport correct content_height"
    - "Code.ensure_loaded before function_exported? to avoid lazy-load false negatives"
    - "Post header rendered above Viewport (non-scrolling) vs body fed as Viewport children"

key_files:
  created: []
  modified:
    - lib/foglet_bbs/tui/screens/post_reader.ex
    - test/foglet_bbs/tui/screens/post_reader_test.exs

decisions:
  - "D-12 realized: Display.Viewport owns scroll_top and bounds clamping — scroll_offset integer removed"
  - "D-13 preserved: render_cache keyed on {post.id, width} unchanged throughout migration"
  - "D-R1 realized: Viewport children are one element per rendered body line (from PostCard.render_body_lines/5)"
  - "D-04 realized: N/P/space/page_down/page_up reset viewport via Viewport.update({:scroll_to, 0})"
  - "D-05 realized: j/k scroll via Viewport.update({:scroll_by, delta}) — no manual clamp math"
  - "warm_viewport/4 added: pre-populates children before scroll to give Viewport correct content_height"
  - "author_line/get_handle/get_time_ago ported from PostCard (Option A — private duplication over broadening public surface)"
  - "visible_height synced from terminal_size in scroll_post/2 so max_scroll reflects actual window size"

metrics:
  duration: "~10 minutes"
  completed: "2026-04-20"
  tasks_completed: 2
  tasks_total: 2
  files_modified: 2
---

# Phase 07 Plan 03: PostReader Viewport Integration Summary

**One-liner:** PostReader scroll state migrated from manual `scroll_offset` integer + `body_line_count` math to `Raxol.UI.Components.Display.Viewport`, with `warm_viewport/4` ensuring content_height is correct before any scroll operation.

## State Shape Change

`screen_state[:post_reader]` shape before and after:

| Field | Before (pre-Phase-7) | After |
|-------|---------------------|-------|
| `selected_post_index` | integer (unchanged) | integer (unchanged) |
| `scroll_offset` | non_neg_integer | **removed** |
| `viewport` | absent | Viewport state map (scroll_top, content_height, visible_height, children) |
| `render_cache` | `%{{post_id, width} => tuples}` (unchanged) | `%{{post_id, width} => tuples}` (unchanged) |

Legacy migration: `get_screen_state/1` drops `:scroll_offset` via `Map.drop([:scroll_offset])` and merges default_screen_state (which has a fresh Viewport) under any existing data. No crash on old session states.

## Key Functions Changed

| Function | Change |
|----------|--------|
| `default_screen_state/0` | Initializes `Viewport.init(%{show_scrollbar: false, ...})` instead of `scroll_offset: 0` |
| `get_screen_state/1` | Drops `:scroll_offset` from legacy state before merge |
| `scroll_post/2` | Calls `warm_viewport`, then `Viewport.update({:set_visible_height, h})` + `{:scroll_by, delta}` |
| `advance_post/2` | Calls `Viewport.update({:scroll_to, 0})` instead of `%{ss \| scroll_offset: 0}` |
| `render_post_content/5` | Builds non-scrolling header above Viewport; passes body lines to `Viewport.update({:set_children, lines})` |
| `load_posts/2` | Calls `warm_viewport` for post 0 on thread load |
| `warm_viewport/4` | NEW — pre-populates Viewport children from PostCard.render_body_lines/5 |
| `author_line/1` + helpers | NEW (ported from PostCard) — builds non-scrolling post header in PostReader |

## Don't-Hand-Roll Win

Eliminated from `scroll_post/2`:
- `PostCard.body_line_count(post.body)` call
- `max_offset = max(total_lines - available_height, 0)` manual clamp
- `new_offset = (ss.scroll_offset + delta) |> max(0) |> min(max_offset)` manual bounds math

Replaced by `Viewport.update({:scroll_by, delta}, vp)` — Viewport's `clamp_scroll/3` handles all edge cases.

## Decisions Realized

- **D-04:** j/k produce scroll, N/P/space reset to top — both via Viewport messages
- **D-05:** Theming gate applied — Viewport receives pre-themed Raxol elements as children
- **D-12:** Manual scroll_offset + max_lines slice eliminated; Viewport owns windowing
- **D-13:** render_cache preserved verbatim — keyed on `{post.id, width}`, same lifecycle, discarded on Q
- **D-R1:** Children granularity is one element per rendered body line (confirmed by Plan 07-02)

## Phase 7 Completion

All five in-scope decisions from 07-CONTEXT.md are now closed:
- **Modal** (thin adapter, Plan 07-01)
- **SelectionList base** (no change per RESEARCH verdict — already correct pattern)
- **SelectionList full** (no change — hex color incompatibility)
- **PostReader Viewport** (partial replacement, Plans 07-02 + 07-03)
- **StatusBar** (no change per D-16)

Phase 7 goal delivered.

## Test Updates

| Change | Count |
|--------|-------|
| `scroll_offset` assertions → `viewport.scroll_top` | 9 |
| Comments updated | 2 |
| New test: viewport state shape | 1 |
| New test: render_cache preserved through Viewport migration (D-13) | 1 |
| **Total tests** | 32 (up from 30) |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Viewport visible_height not synced before scroll_by**

- **Found during:** Task 2 — `scroll_top` stayed at 0 after j press in tests
- **Issue:** `default_screen_state` initializes `visible_height: 10`. With body of 8 lines, `content_height=8` and `visible_height=10` gives `max_scroll=max(0, 8-10)=0`. Viewport correctly clamped to 0 — but the wrong height was used.
- **Fix:** Added `Viewport.update({:set_visible_height, available_height}, vp)` in `scroll_post/2` before `scroll_by`, using `available_height = max(h - 10, 5)` from the actual terminal size.
- **Files modified:** `lib/foglet_bbs/tui/screens/post_reader.ex`
- **Commit:** b10839d

**2. [Rule 1 - Bug] function_exported? returns false for unloaded modules**

- **Found during:** Task 2 — `warm_cache` and `warm_viewport` were returning 1-tuple fallback for `Foglet.Markdown` in test environment
- **Issue:** `function_exported?(Foglet.Markdown, :render, 1)` returns `false` when the module hasn't been called/loaded yet in the current runtime session (Elixir lazy module loading). The defensive fallback `[{body, :plain}]` was triggered, giving `content_height: 1` regardless of actual body length.
- **Fix:** Added `_ = Code.ensure_loaded(markdown_mod)` before the `function_exported?` check in `parse_body/2`. `Code.ensure_loaded` forces the module to be loaded into the runtime before the check.
- **Files modified:** `lib/foglet_bbs/tui/screens/post_reader.ex`
- **Commit:** b10839d

## Known Stubs

None — all Viewport integration is fully wired. render_cache is live, Viewport children are real themed Raxol elements from `PostCard.render_body_lines/5`.

## Threat Flags

None — UI-only refactor. Scroll state moves from an integer to a map in our screen_state. No new network endpoints, auth paths, file access, or schema changes.

## TDD Gate Compliance

| Gate | Commit | Status |
|------|--------|--------|
| RED (Task 1) | b4570da | PASS — 8 tests failed before implementation |
| GREEN (Task 2) | b10839d | PASS — all 32 tests pass |

## Self-Check

Files modified:
- [x] `lib/foglet_bbs/tui/screens/post_reader.ex` — contains `alias Raxol.UI.Components.Display.Viewport`, `defp warm_viewport`, `Viewport.init`, `Viewport.update`, `Viewport.render`
- [x] `test/foglet_bbs/tui/screens/post_reader_test.exs` — contains `viewport.scroll_top` assertions (14 matches), new viewport shape test, new render_cache preservation test

Commits:
- [x] b4570da — test(07-03): RED — migrate scroll_offset assertions to viewport.scroll_top
- [x] b10839d — feat(07-03): GREEN — integrate Viewport into PostReader (D-12, D-13, D-R1)

## Self-Check: PASSED
