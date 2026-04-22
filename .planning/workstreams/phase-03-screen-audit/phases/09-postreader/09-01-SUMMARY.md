---
phase: 09-postreader
plan: "01"
subsystem: tui-screens
tags:
  - post-reader
  - spinner
  - loading-ux
  - render-purity
  - callback-contract
  - audit
dependency_graph:
  requires:
    - "lib/foglet_bbs/tui/widgets/progress/spinner.ex"
    - "lib/foglet_bbs/tui/screens/domain.ex"
    - "lib/foglet_bbs/tui/widgets/post/post_card.ex"
    - "lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex"
  provides:
    - "lib/foglet_bbs/tui/screens/post_reader.ex"
    - "test/foglet_bbs/tui/screens/post_reader_test.exs"
  affects: []
tech_stack:
  added: []
  patterns:
    - "Spinner.render/2 one-row composition for loading affordances (BoardList/ThreadList pattern)"
    - "Static source inspection test for render-purity boundary enforcement"
    - "__ENV__.file-relative path resolution for source-scanning tests"
key_files:
  created: []
  modified:
    - "lib/foglet_bbs/tui/screens/post_reader.ex"
    - "test/foglet_bbs/tui/screens/post_reader_test.exs"
decisions:
  - "D-05/D-06: Spinner adoption with do-block row syntax (not keyword-arg form) to produce populated children"
  - "D-07/D-08: Render purity enforced via both moduledoc and static source test"
  - "D-03/D-04: load_posts/2 and flush_read_pointers/2 documented as intentional public contract surface"
metrics:
  duration: "~6 minutes"
  completed: "2026-04-22"
  tasks_completed: 2
  tasks_total: 2
  files_modified: 2
---

# Phase 09 Plan 01: PostReader Screen Audit Summary

**One-liner:** Spinner loading UX, load-absorb moduledoc, callback dead-code audit evidence, and executable render-purity guardrails for PostReader (READER-01..07, AUDIT-05..22).

## What Was Built

### Task 1: PostReader implementation updates (`post_reader.ex`)

- **Spinner loading branch** (`render_loading/1`): replaced plain `"Loading posts..."` text with `Spinner.render/2` + `text("Loading…")` in a `row do [...] end` block (matching BoardList pattern). Added `alias Foglet.TUI.Widgets.Progress.Spinner`.
- **`@moduledoc` expansion** with three new sections:
  - `## Load-absorb behavior` documenting that `advance_post/2` and `scroll_post/2` return `{:update, state, []}` when posts are nil/empty, absorbing keypresses and preventing global handler bleed-through (READER-07, AUDIT-18 deviation note).
  - `## Public callbacks` documenting intentional public surface for `load_posts/2` and `flush_read_pointers/2` (READER-02, D-03, D-04).
  - `## Render-path purity` documenting the no-writes-in-render-helpers constraint (READER-05, D-07, D-08).
- **Dead-code audit comments** added inline to `@doc` for both `load_posts/2` and `flush_read_pointers/2` per AUDIT-12.
- Domain helper fallback parity for `:posts`/`:boards`/`:threads`/`:markdown` preserved exactly (READER-01, D-01, D-02).
- PostCard + Viewport render pipeline left unchanged (READER-04).

**Line count delta:** 449 → 502 (+53). Increase is purely documentation/comments (moduledoc sections + `@doc` audit notes) and the spinner alias addition. Visible row count in loading state unchanged (one row, same density as before).

### Task 2: PostReader regression tests (`post_reader_test.exs`)

- **`describe "render/1 loading state"`**: asserts canonical `"Loading…"` text for nil posts and empty posts; asserts legacy `"Loading posts..."` text does not appear (READER-03, AUDIT-11).
- **Dead-code audit ownership markers**: added `# intentional callback surface (READER-02, D-03, D-04)` comments to both `load_posts/2` and `flush_read_pointers/2` test bodies.
- **`describe "load-absorb behavior (READER-07)"`**: 6 tests covering n/p/space/j/k keys on nil and empty posts returning `{:update, state, []}` with no extra commands.
- **`describe "render helper purity (READER-05, D-07, D-08)"`**: static source-inspection test that reads `post_reader.ex` at test time, scans all `defp render_*` bodies, and asserts no `put_in(`, `%{state |`, or `Map.put(` writes appear.

**Line count delta:** 604 → 725 (+121). All additions are new test coverage.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed row macro syntax for spinner children**
- **Found during:** Task 2 test loop — `render/1 loading state empty posts list` failed
- **Issue:** `row(style: %{gap: 1}, do: [...])` keyword-arg form produces an empty `children: []` flex node in the render tree. The Raxol View DSL requires the `do ... end` block form for children to be populated.
- **Fix:** Changed to `row style: %{gap: 1} do [...] end` syntax (matching ThreadList's existing pattern).
- **Files modified:** `lib/foglet_bbs/tui/screens/post_reader.ex`
- **Commit:** 0f585cd

**2. [Rule 1 - Bug] Fixed source path resolution in purity guard test**
- **Found during:** Task 2 test loop — purity guard test panicked with `File.Error: no such file or directory`
- **Issue:** `Path.join(:code.priv_dir(:foglet_bbs), "../../lib/...")` resolved to a path inside `_build/test/lib/lib/...` which doesn't exist.
- **Fix:** Changed to `__ENV__.file |> Path.dirname() |> Path.join("../../../../lib/...")` which resolves relative to the test file's source location.
- **Files modified:** `test/foglet_bbs/tui/screens/post_reader_test.exs`
- **Commit:** 0f585cd

## Known Stubs

None — all new behavior is wired and verified by tests.

## Threat Flags

No new security-relevant surface introduced. All threat mitigations from the plan's STRIDE register were applied:

| Threat | Disposition | Evidence |
|--------|-------------|----------|
| T-09-01: Domain module tampering | mitigated | `Domain.get/2` + explicit fallback preserved in load/flush/parse paths |
| T-09-02: Loading DoS via key churn | mitigated | Load-absorb semantics tested and documented in moduledoc |
| T-09-03: Render-path state corruption | mitigated | Purity boundary documented in moduledoc + locked by static source test |
| T-09-04: Callback dead-code repudiation | mitigated | `@doc` audit notes + test ownership comments for both callbacks |

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| Task 1 | `bd9a51b` | feat(09-01): implement spinner loading, moduledoc load-absorb docs, and callback contract evidence |
| Task 2 | `0f585cd` | test(09-01): add spinner loading, callback-contract, purity-guard, and load-absorb tests |

## Quality Gate Results

- `mix test test/foglet_bbs/tui/screens/post_reader_test.exs`: 40 tests, 0 failures
- `mix precommit`: green (compile --warnings-as-errors, format, credo --strict, sobelow, dialyzer all pass)
- Purity grep (`defp render_*` bodies): no state writes found
- Spinner + Loading… grep: matches confirmed in `render_loading/1`
- Domain.get + fallback grep: all 4 call sites confirmed

## Self-Check: PASSED

- [x] `lib/foglet_bbs/tui/screens/post_reader.ex` — exists, modified
- [x] `test/foglet_bbs/tui/screens/post_reader_test.exs` — exists, modified
- [x] Task 1 commit `bd9a51b` — confirmed in git log
- [x] Task 2 commit `0f585cd` — confirmed in git log
- [x] 40 tests pass, `mix precommit` green
