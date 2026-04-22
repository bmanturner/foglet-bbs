---
status: complete
task: "Create state structs for NewThread and PostComposer"
completed: 2026-04-22
---

# Summary: Create NewThread.State and PostComposer.State

Added typed screen-state structs for `Foglet.TUI.Screens.NewThread` and
`Foglet.TUI.Screens.PostComposer`, following the nested widget-state decision
from `260422-hfc-CONTEXT.md`.

## Changes

- Added `Foglet.TUI.Screens.NewThread.State` with direct fields for local
  screen state and nested `TextInput` / `MultiLineInput` widget state.
- Added `Foglet.TUI.Screens.PostComposer.State` with direct fields for local
  screen state and nested `MultiLineInput` widget state.
- Updated NewThread, PostComposer, MainMenu, ThreadList, PostReader, and App
  integration paths to store the new structs at `state.screen_state[:new_thread]`
  and `state.screen_state[:post_composer]`.
- Updated affected TUI tests to seed state through constructors and avoid nested
  Access-style field reads through the new structs.

## Validation

- `mix test test/foglet_bbs/tui/screens/new_thread_test.exs test/foglet_bbs/tui/screens/post_composer_test.exs test/foglet_bbs/tui/screens/main_menu_test.exs test/foglet_bbs/tui/screens/post_reader_test.exs test/foglet_bbs/tui/screens/thread_list_test.exs test/foglet_bbs/tui/app_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` — 228 tests, 0 failures.
- `mix test test/foglet_bbs/tui/screens/new_thread_test.exs` — 38 tests, 0 failures after warning cleanup.
- `mix compile --warnings-as-errors` — passed.
- `mix precommit` — passed.
- Plan checker rerun — `## VERIFICATION PASSED`.

## Notes

- The app still keeps top-level `screen_state` as a map keyed by screen atom.
- Broad legacy plain-map compatibility for these two screen-state entries is
  intentionally out of scope.
