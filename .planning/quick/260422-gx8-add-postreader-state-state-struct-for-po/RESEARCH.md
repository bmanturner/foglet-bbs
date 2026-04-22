# Quick Research: Add `PostReader.State`

**Researched:** 2026-04-22
**Scope:** Add a typed state struct for `Foglet.TUI.Screens.PostReader` without changing PostReader behavior.

## Final Decision

Use `%Foglet.TUI.Screens.PostReader.State{}` as the supported representation for `state.screen_state[:post_reader]`.

This app is not in production, so old plain-map PostReader state is not supported. Normal entry and load paths initialize or preserve the struct. Tests should seed `PostReader.init_screen_state/1`, not `%{selected_post_index: 0}` maps.

## Struct Shape

`PostReader.State` keeps the three existing fields:

- `selected_post_index`
- `viewport`
- `render_cache`

The struct constructor owns the default Raxol viewport setup that previously lived in `PostReader.init_screen_state/1`.

## Implementation Notes

- Keep `Foglet.TUI.App.screen_state` as a top-level map keyed by screen atom.
- Store `%PostReader.State{}` at `screen_state[:post_reader]`.
- `PostReader.init_screen_state/1` should return `%PostReader.State{}`.
- `ThreadList` entry into PostReader should call `PostReader.init_screen_state/1`.
- `App.update({:posts_loaded, posts, opts}, state)` should accept an existing `%PostReader.State{}` or initialize one when absent.
- Do not use nested `get_in(..., [:post_reader, ...])` against the struct.

## Validation

- `mix test test/foglet_bbs/tui/screens/post_reader_test.exs`
- `mix test test/foglet_bbs/tui/app_test.exs`
- `mix compile --warnings-as-errors`
- `mix precommit`
