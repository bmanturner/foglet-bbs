---
phase: 07-oneliners-and-main-menu-social-strip
plan: 02
subsystem: tui
tags:
  - main-menu
  - oneliners
  - raxol
requires:
  - 07-01
provides:
  - ONEL-01 main-menu oneliner strip rendering
affects:
  - lib/foglet_bbs/tui/screens/main_menu.ex
  - test/foglet_bbs/tui/screens/main_menu_test.exs
  - test/foglet_bbs/tui/layout_smoke_test.exs
tech-stack:
  added: []
  patterns:
    - stateless Raxol screen renderer
    - app-state-driven split pane
key-files:
  created:
    - .planning/phases/07-oneliners-and-main-menu-social-strip/07-02-SUMMARY.md
  modified:
    - lib/foglet_bbs/tui/screens/main_menu.ex
    - test/foglet_bbs/tui/screens/main_menu_test.exs
    - test/foglet_bbs/tui/layout_smoke_test.exs
decisions:
  - MainMenu reads only state.recent_oneliners and does not own persistence or screen-local editor state.
  - Oneliner rows are capped at five and clipped to a fixed one-line presentation target.
metrics:
  completed_at: 2026-04-24T03:05:01Z
  tasks_completed: 2
  task_commits: 2
---

# Phase 07 Plan 02: Main Menu Oneliner Strip Summary

Stateless split-pane MainMenu rendering now shows recent loaded oneliners and exposes an authenticated composer command without database reads.

## Completed Tasks

| Task | Name | Commit | Files |
| ---- | ---- | ------ | ----- |
| 1 | Extend MainMenu tests for split-pane oneliners | 0f64161 | `test/foglet_bbs/tui/screens/main_menu_test.exs`, `test/foglet_bbs/tui/layout_smoke_test.exs` |
| 2 | Implement stateless split-pane MainMenu rendering and O key command | 655ac6b | `lib/foglet_bbs/tui/screens/main_menu.ex`, `test/foglet_bbs/tui/layout_smoke_test.exs` |

## What Changed

- Added MainMenu render tests for nil/empty oneliner state, one row, bounded many-row display, long handle/body clipping, no timestamps, preserved statelessness, and `[O]` command dispatch.
- Updated the 80x24 layout smoke test to assert `Oneliners` and a sample `@alice  hello` row render alongside existing menu affordances.
- Changed `Foglet.TUI.Screens.MainMenu.render/1` to compose existing navigation with a right-side `Oneliners` panel using `split_pane/1`.
- Added authenticated `O`/`o` key handling that emits only `{:open_oneliner_composer}`.

## Verification

- `mix test test/foglet_bbs/tui/screens/main_menu_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` passed: 44 tests, 0 failures.
- `mix precommit` passed, including compile, format, Credo, Sobelow, and Dialyzer. Dialyzer reported 84 existing ignored warnings and completed successfully.

## Deviations from Plan

### Auto-fixed Issues

None - plan executed as written.

## Known Stubs

None blocking this plan. Stub-pattern scan found only existing placeholder test data and existing non-null assertions outside the oneliner strip implementation.

## Threat Flags

None. The new render path consumes already-loaded app state only, limits rows to five, clips row content, and emits no persistence or moderation commands.

## Self-Check: PASSED

- Summary file exists at `.planning/phases/07-oneliners-and-main-menu-social-strip/07-02-SUMMARY.md`.
- Task commit `0f64161` exists in git history.
- Task commit `655ac6b` exists in git history.
- No shared tracking artifacts (`.planning/STATE.md`, `.planning/ROADMAP.md`) were modified.
