---
status: complete
task: "Add PostReader.State state struct for PostReader"
completed_at: "2026-04-22"
---

# Summary

Added `Foglet.TUI.Screens.PostReader.State` and migrated normal PostReader runtime paths to store `%PostReader.State{}` at `state.screen_state[:post_reader]`.

## Changes

- Added `lib/foglet_bbs/tui/screens/post_reader/state.ex` with `new/1`.
- Updated `PostReader.init_screen_state/1`, `prepare_after_load/3`, and internal screen-state reads to use the struct.
- Updated `ThreadList` entry into PostReader and `App.update({:posts_loaded, ...}, state)` to write struct state.
- Updated tests to use struct-aware field access.

## Validation

- `mix test test/foglet_bbs/tui/screens/post_reader_test.exs` — passed
- `mix test test/foglet_bbs/tui/app_test.exs` — passed
- `mix compile --warnings-as-errors` — passed
- `mix precommit` — passed

Verifier result: PASS.
