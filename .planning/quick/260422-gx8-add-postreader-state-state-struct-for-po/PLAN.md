---
status: complete
task: "Add PostReader.State state struct for PostReader"
flags:
  research: true
  validate: true
---

# Plan: Add PostReader.State

## Goal

Migrate `state.screen_state[:post_reader]` from an untyped plain map to a `%Foglet.TUI.Screens.PostReader.State{}` struct while preserving PostReader behavior.

Runtime paths should write and expect the struct. This app is not in production, so legacy map compatibility is intentionally out of scope.

## Scope

- Add `Foglet.TUI.Screens.PostReader.State` in its own file.
- Preserve the existing field names: `selected_post_index`, `viewport`, `render_cache`.
- Update `PostReader.init_screen_state/1`, `get_screen_state/1`, and `prepare_after_load/3` to use the struct.
- Update `ThreadList` entry and `App` `:posts_loaded` handling so normal paths store `%PostReader.State{}`.
- Update tests to use struct-aware dot access.

## Out of Scope

- No render, scrolling, reply, loading, read-pointer, or flush behavior changes.
- No change to the top-level `Foglet.TUI.App.screen_state` field; it remains a map keyed by screen atom.

## Validation

1. `mix test test/foglet_bbs/tui/screens/post_reader_test.exs`
2. `mix test test/foglet_bbs/tui/app_test.exs`
3. `mix compile --warnings-as-errors`
4. `mix precommit`

## Acceptance Criteria

- `PostReader.init_screen_state/1` returns `%PostReader.State{}`.
- `PostReader.load_posts/2`, navigation, scrolling, and `App.update({:posts_loaded, ...}, state)` write `%PostReader.State{}` into `screen_state[:post_reader]`.
- Plain map state such as `%{selected_post_index: 0}` is not a supported PostReader state shape.
- No code uses nested `get_in(..., [:post_reader, ...])` against the struct.
