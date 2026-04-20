---
phase: 07-migrate-hand-rolled-ui-components-to-raxol-widgets
plan: "02"
subsystem: tui-widgets
tags:
  - raxol
  - viewport
  - markdown
  - phase-07
  - tdd

dependency_graph:
  requires:
    - "MarkdownBody existing private helpers: group_by_newline/1, line_group_to_row/2"
  provides:
    - "MarkdownBody.render_tuples_as_lines/4 — flat list of Raxol row elements, one per logical line"
    - "PostCard.render_body_lines/5 — body-only flat list, delegates to MarkdownBody"
  affects:
    - "Plan 07-03 (PostReader Viewport integration) — will call PostCard.render_body_lines/5 as Viewport children source"

tech_stack:
  added: []
  patterns:
    - "Additive public API extension — new functions coexist with existing render_tuples/4 and render_from_tuples/5"
    - "TDD RED/GREEN/REFACTOR cycle per task"
    - "_ = binding pattern to silence unused-var warnings while keeping public API readable"

key_files:
  created: []
  modified:
    - lib/foglet_bbs/tui/widgets/post/markdown_body.ex
    - lib/foglet_bbs/tui/widgets/post/post_card.ex
    - test/foglet_bbs/tui/widgets/post/markdown_body_test.exs
    - test/foglet_bbs/tui/widgets/post/post_card_test.exs

decisions:
  - "D-R1 realized: Viewport children must be one element per rendered line — flat list (not a column) is the correct shape"
  - "opts passed through via body_opts/1 even though ignored — keeps future refactors simple if MarkdownBody re-enables windowing"
  - "Empty tuple input returns [] (differs from render_tuples/4 which emits a blank text inside a column — Viewport handles empty children via Enum.slice on [])"

metrics:
  duration: "~20 minutes"
  completed: "2026-04-20"
  tasks_completed: 2
  tasks_total: 2
  files_modified: 4
---

# Phase 07 Plan 02: Post Widget Flat-List API for Viewport Summary

**One-liner:** Additive flat-list rendering API — `MarkdownBody.render_tuples_as_lines/4` and `PostCard.render_body_lines/5` — returning one Raxol element per logical body line for `Display.Viewport` children injection.

## New Public API

### `MarkdownBody.render_tuples_as_lines/4`

```elixir
@spec render_tuples_as_lines([tuple_entry()], pos_integer(), Theme.t(), keyword()) :: [any()]
def render_tuples_as_lines(tuples, width, %Theme{} = theme, opts \\ [])
```

- Returns a plain Elixir list of Raxol view element maps (no column wrapper)
- Each element is either a bare `text/2` (single-run line) or `row/2` (multi-run line)
- List length equals `line_count/1` output for the same input
- `opts` ignored — no windowing (Viewport owns slicing)
- Empty input returns `[]`
- Reuses existing private `group_by_newline/1` and `line_group_to_row/2` helpers

### `PostCard.render_body_lines/5`

```elixir
@spec render_body_lines(post_like(), [MarkdownBody.tuple_entry()], pos_integer(), Theme.t(), keyword()) :: [any()]
def render_body_lines(post, tuples, width, %Theme{} = theme, opts \\ [])
```

- Returns body-only flat list — no "Post X of N" header, no author line, no divider
- Delegates to `MarkdownBody.render_tuples_as_lines/4` via `body_opts/1`
- `_ = post` silences unused-var warning while matching `render_from_tuples/5` call shape

## Decisions Realized

- **D-R1** (from 07-RESEARCH.md Open Questions): Viewport children granularity confirmed as one element per rendered line of the current post. This enables j/k line-by-line scrolling in Plan 07-03.

## Test Counts

| File | New Tests Added | Total After |
|------|----------------|-------------|
| `test/.../markdown_body_test.exs` | 6 | 26 |
| `test/.../post_card_test.exs` | 5 | 23 |

TDD gate compliance verified:
- `test(07-02)` RED commits exist before `feat(07-02)` GREEN commits in git log
- All 49 post widget tests pass; full TUI suite 404 tests, 0 failures

## Downstream Consumer

Plan 07-03 (PostReader Viewport integration) will call `PostCard.render_body_lines/5` to supply pre-rendered themed children to `Viewport.update({:set_children, lines}, vp)`.

## Existing API Preservation

All pre-existing public functions are unchanged and all existing tests pass:
- `MarkdownBody.render/4`, `render_tuples/4`, `line_count/1`
- `PostCard.render/4`, `render_from_tuples/5`, `body_line_count/1`

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None — both new functions are fully wired. Return values are live Raxol element maps produced by the existing `line_group_to_row/2` pipeline.

## Threat Flags

None — UI-only additive refactor. No new network endpoints, auth paths, file access, or schema changes. Identical visible behavior to `render_tuples/4` path, just without the column wrapper.

## TDD Gate Compliance

| Gate | Commit | Status |
|------|--------|--------|
| RED (Task 1) | c1a2b80 | PASS — 6 tests failed before implementation |
| GREEN (Task 1) | 0698f14 | PASS — all 26 tests pass |
| RED (Task 2) | 3c947f8 | PASS — 5 tests failed before implementation |
| GREEN (Task 2) | db93a9f | PASS — all 49 tests pass |

## Self-Check

Files created/modified:

- [x] `lib/foglet_bbs/tui/widgets/post/markdown_body.ex` — contains `def render_tuples_as_lines`
- [x] `lib/foglet_bbs/tui/widgets/post/post_card.ex` — contains `def render_body_lines`
- [x] `test/foglet_bbs/tui/widgets/post/markdown_body_test.exs` — contains `describe "render_tuples_as_lines/4`
- [x] `test/foglet_bbs/tui/widgets/post/post_card_test.exs` — contains `describe "render_body_lines/5`

Commits:
- [x] c1a2b80 — test(07-02) RED MarkdownBody
- [x] 0698f14 — feat(07-02) GREEN MarkdownBody
- [x] 3c947f8 — test(07-02) RED PostCard
- [x] db93a9f — feat(07-02) GREEN PostCard

## Self-Check: PASSED
