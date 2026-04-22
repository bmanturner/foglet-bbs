# Quick Task 260422-hfc: Create State Structs for NewThread and PostComposer - Context

**Gathered:** 2026-04-22
**Status:** Ready for planning

<domain>
## Task Boundary

Create state structs for `Foglet.TUI.Screens.NewThread` and
`Foglet.TUI.Screens.PostComposer`, similar to the recently completed
`PostReader.State` migration.

</domain>

<decisions>
## Implementation Decisions

### Nested Widget State
- `NewThread.State` and `PostComposer.State` own nested stateful widget structs as
  first-class fields. This follows D-14: widget state is hoisted into the screen
  state struct, not initialized in render paths and not stored beside the screen
  state.
- `State.new/1` constructors initialize Raxol/Foglet widget structs that need
  defaults, including `MultiLineInput` and `TextInput`.

### Runtime Shape
- Normal runtime paths should store `%NewThread.State{}` at
  `state.screen_state[:new_thread]` and `%PostComposer.State{}` at
  `state.screen_state[:post_composer]`.
- This app is not in production, so broad legacy plain-map compatibility is out
  of scope. Missing state may initialize to the new struct shape; tests should
  seed state via `init_screen_state/1`.

### Field Naming
- Preserve current semantic field names where practical:
  `NewThread.State` keeps `step`, `boards`, `selected_board_index`, `board`,
  `title_input_state`, `body_input_state`, `focused`, `mode`, `error`, and
  `origin`.
- `PostComposer.State` keeps `mode`, `reply_to`, `error`, `input_state`, and
  supports `origin` because cancel origin is already used by the runtime flow.

</decisions>

<specifics>
## Specific Ideas

- Mirror `PostReader.State`: one module per state struct under a screen-named
  directory, with `init_screen_state/1` delegating to `State.new/1`.
- Avoid nested `get_in(..., [:screen, :field])` against the new structs.
- Keep behavior changes out of scope; this is a state-shape migration.

</specifics>

<canonical_refs>
## Canonical References

- `.planning/quick/260422-gx8-add-postreader-state-state-struct-for-po/RESEARCH.md`
- `.planning/quick/260422-gx8-add-postreader-state-state-struct-for-po/PLAN.md`
- `.planning/workstreams/phase-03-screen-audit/research/PITFALLS.md`
- `.planning/workstreams/phase-03-polish/phases/08-build-local-widget-library-from-raxol-primitives/08-CONTEXT.md`
- `lib/foglet_bbs/tui/screens/post_reader/state.ex`

</canonical_refs>
