# Quick Research: Create `NewThread.State` and `PostComposer.State`

**Researched:** 2026-04-22
**Scope:** Targeted migration research for typed screen-state structs in `Foglet.TUI.Screens.NewThread` and `Foglet.TUI.Screens.PostComposer`.
**Confidence:** HIGH for codebase facts; MEDIUM for remaining implementation effort because this checkout already contains partial/current state modules.

## User Constraints (from CONTEXT.md)

### Locked Decisions

- `NewThread.State` and `PostComposer.State` own nested stateful widget structs as first-class fields. This follows D-14: widget state is hoisted into the screen state struct, not initialized in render paths and not stored beside the screen state. [VERIFIED: .planning/quick/260422-hfc-create-state-structs-for-newthread-and-p/260422-hfc-CONTEXT.md]
- `State.new/1` constructors initialize Raxol/Foglet widget structs that need defaults, including `MultiLineInput` and `TextInput`. [VERIFIED: .planning/quick/260422-hfc-create-state-structs-for-newthread-and-p/260422-hfc-CONTEXT.md]
- Normal runtime paths should store `%NewThread.State{}` at `state.screen_state[:new_thread]` and `%PostComposer.State{}` at `state.screen_state[:post_composer]`. [VERIFIED: .planning/quick/260422-hfc-create-state-structs-for-newthread-and-p/260422-hfc-CONTEXT.md]
- This app is not in production, so broad legacy plain-map compatibility is out of scope. Missing state may initialize to the new struct shape; tests should seed state via `init_screen_state/1`. [VERIFIED: .planning/quick/260422-hfc-create-state-structs-for-newthread-and-p/260422-hfc-CONTEXT.md]
- Preserve current semantic field names for `NewThread.State`: `step`, `boards`, `selected_board_index`, `board`, `title_input_state`, `body_input_state`, `focused`, `mode`, `error`, and `origin`. [VERIFIED: .planning/quick/260422-hfc-create-state-structs-for-newthread-and-p/260422-hfc-CONTEXT.md]
- Preserve current semantic field names for `PostComposer.State`: `mode`, `reply_to`, `error`, `input_state`, and `origin`. [VERIFIED: .planning/quick/260422-hfc-create-state-structs-for-newthread-and-p/260422-hfc-CONTEXT.md]

### Claude's Discretion

- Mirror `PostReader.State`: one module per state struct under a screen-named directory, with `init_screen_state/1` delegating to `State.new/1`. [VERIFIED: .planning/quick/260422-hfc-create-state-structs-for-newthread-and-p/260422-hfc-CONTEXT.md]
- Avoid nested `get_in(..., [:screen, :field])` against the new structs. [VERIFIED: .planning/quick/260422-hfc-create-state-structs-for-newthread-and-p/260422-hfc-CONTEXT.md]
- Keep behavior changes out of scope; this is a state-shape migration. [VERIFIED: .planning/quick/260422-hfc-create-state-structs-for-newthread-and-p/260422-hfc-CONTEXT.md]

### Deferred Ideas (OUT OF SCOPE)

- None listed in the quick-task CONTEXT.md. [VERIFIED: .planning/quick/260422-hfc-create-state-structs-for-newthread-and-p/260422-hfc-CONTEXT.md]

## Summary

Use the `PostReader.State` migration as the direct precedent: the top-level `App.screen_state` remains a map keyed by screen atom, while each stateful screen entry becomes a concrete struct. [VERIFIED: .planning/quick/260422-gx8-add-postreader-state-state-struct-for-po/RESEARCH.md; lib/foglet_bbs/tui/screens/post_reader/state.ex]

In this checkout, `lib/foglet_bbs/tui/screens/new_thread/state.ex` and `lib/foglet_bbs/tui/screens/post_composer/state.ex` already exist and already initialize nested widget state in `State.new/1`. [VERIFIED: lib/foglet_bbs/tui/screens/new_thread/state.ex; lib/foglet_bbs/tui/screens/post_composer/state.ex] The remaining risk is integration cleanup: code and tests that still use `get_in/2`, `put_in/3`, or old field names against these struct entries will fail because Elixir structs do not implement `Access`. [VERIFIED: AGENTS.md; rg scan of lib/foglet_bbs/tui and test/foglet_bbs/tui]

**Primary recommendation:** Finish the migration by making all NewThread/PostComposer runtime and test paths struct-aware, using dot access and `%State{}` pattern matches, without adding legacy map compatibility. [VERIFIED: CONTEXT.md; PostReader.State precedent]

## Project Constraints (from CLAUDE.md / AGENTS.md)

- Run `mix precommit` after code changes and fix any reported issues. [VERIFIED: CLAUDE.md; AGENTS.md]
- Do not nest multiple modules in the same file; create one `State` module file per screen directory. [VERIFIED: CLAUDE.md; AGENTS.md]
- Struct fields must be accessed with dot access, not `struct[:field]` or nested `get_in/2`. [VERIFIED: CLAUDE.md; AGENTS.md]
- Tests that start processes should use `start_supervised!/1`, and should avoid `Process.sleep/1` and `Process.alive?/1`; this task is expected to be pure state tests unless existing tests require processes. [VERIFIED: CLAUDE.md; AGENTS.md]
- For TUI work, consult vendored Raxol docs and Foglet widget docs; relevant local widget guidance is in `lib/foglet_bbs/tui/widgets/README.md`. [VERIFIED: CLAUDE.md; AGENTS.md]

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|--------------|----------------|-----------|
| Screen-local state shape | TUI screen module | App dispatcher | `NewThread` and `PostComposer` own their per-screen state; `App` stores entries under `screen_state` keys. [VERIFIED: lib/foglet_bbs/tui/screens/new_thread.ex; lib/foglet_bbs/tui/screens/post_composer.ex; lib/foglet_bbs/tui/app.ex] |
| Nested widget state | State struct | Widget module | D-14 stateful widget state is initialized in `State.new/1` and then passed to widget update/render functions. [VERIFIED: lib/foglet_bbs/tui/widgets/README.md; lib/foglet_bbs/tui/screens/new_thread/state.ex; lib/foglet_bbs/tui/screens/post_composer/state.ex] |
| Missing screen-state fallback | Screen module | State struct | Each screen may synthesize a fresh state via `init_screen_state/1` when its `screen_state` entry is absent. [VERIFIED: lib/foglet_bbs/tui/screens/new_thread.ex; lib/foglet_bbs/tui/screens/post_composer.ex] |
| Async board-load integration | App dispatcher | NewThread.State | `App.update({:boards_for_new_thread_loaded, boards}, state)` updates `screen_state[:new_thread].boards`; it must only update a `%NewThread.State{}` or initialize one. [VERIFIED: lib/foglet_bbs/tui/app.ex] |

## Standard Pattern

### State Modules

- Keep `Foglet.TUI.Screens.NewThread.State` in `lib/foglet_bbs/tui/screens/new_thread/state.ex`. [VERIFIED: lib/foglet_bbs/tui/screens/new_thread/state.ex]
- Keep `Foglet.TUI.Screens.PostComposer.State` in `lib/foglet_bbs/tui/screens/post_composer/state.ex`. [VERIFIED: lib/foglet_bbs/tui/screens/post_composer/state.ex]
- `NewThread.init_screen_state/1` should delegate to `State.new/1` after adding config-derived `:max_title_length`. [VERIFIED: lib/foglet_bbs/tui/screens/new_thread.ex]
- `PostComposer.init_screen_state/1` should delegate directly to `State.new/1`. [VERIFIED: lib/foglet_bbs/tui/screens/post_composer.ex]
- `PostReader.State` is the precedent: constructor owns default Raxol widget initialization and the app stores the resulting struct at `screen_state[:post_reader]`. [VERIFIED: lib/foglet_bbs/tui/screens/post_reader/state.ex]

### Nested Widget State

- `NewThread.State.title_input_state` should hold a `%Foglet.TUI.Widgets.Input.TextInput{}` initialized by `TextInput.init/1`. [VERIFIED: lib/foglet_bbs/tui/screens/new_thread/state.ex; lib/foglet_bbs/tui/widgets/input/text_input.ex]
- `NewThread.State.body_input_state` should hold a `%Raxol.UI.Components.Input.MultiLineInput{}` initialized by `MultiLineInput.init/1`. [VERIFIED: lib/foglet_bbs/tui/screens/new_thread/state.ex]
- `PostComposer.State.input_state` should hold a `%Raxol.UI.Components.Input.MultiLineInput{}` initialized by `MultiLineInput.init/1`. [VERIFIED: lib/foglet_bbs/tui/screens/post_composer/state.ex]
- Do not initialize `TextInput` or `MultiLineInput` in render paths; `NewThread.render_compose_step/2` currently has defensive `Map.get(ss, :title_input_state, TextInput.init(...))` fallbacks that can be simplified after struct-only state is enforced. [VERIFIED: lib/foglet_bbs/tui/screens/new_thread.ex]

## Current Integration Findings

- `NewThread.screen_state/1` already accepts only `%NewThread.State{}` and otherwise calls `init_screen_state/0`. [VERIFIED: lib/foglet_bbs/tui/screens/new_thread.ex]
- `PostComposer.composer_screen_state/1` already accepts only `%PostComposer.State{}` and otherwise calls `init_screen_state/1` using terminal width/height defaults. [VERIFIED: lib/foglet_bbs/tui/screens/post_composer.ex]
- `App.update({:boards_for_new_thread_loaded, boards}, state)` still reads with `get_in(state.screen_state, [:new_thread])`; this is safe for fetching the screen entry but should be changed to `Map.get/2` plus `%NewThread.State{}` matching for consistency with struct-only runtime shape. [VERIFIED: lib/foglet_bbs/tui/app.ex]
- Some tests still use nested `get_in(..., [:post_composer, :field])` or `put_in(..., [:screen_state, :post_composer, :reply_to], ...)`, which will fail against `%PostComposer.State{}`. [VERIFIED: test/foglet_bbs/tui/screens/post_composer_test.exs; test/foglet_bbs/tui/screens/post_reader_test.exs]
- Some tests still seed old plain-map `:new_thread` or `:post_composer` entries and should seed via `NewThread.init_screen_state/1` or `PostComposer.init_screen_state/1`. [VERIFIED: test/foglet_bbs/tui/screens/new_thread_test.exs; test/foglet_bbs/tui/app_test.exs]
- `test/foglet_bbs/tui/app_test.exs` contains an old `title_input` expectation for `new_thread`; the struct field is now `title_input_state`. [VERIFIED: test/foglet_bbs/tui/app_test.exs; lib/foglet_bbs/tui/screens/new_thread/state.ex]

## Common Pitfalls

### Pitfall 1: Structs with Access-style tests

**What goes wrong:** Tests call `get_in(s.screen_state, [:post_composer, :mode])` or `put_in(state, [:screen_state, :post_composer, :reply_to], reply_to)` after `:post_composer` is a struct. [VERIFIED: test/foglet_bbs/tui/screens/post_composer_test.exs]

**How to avoid:** Fetch the struct first, assert its type, then use dot access:

```elixir
ss = s.screen_state.post_composer
assert %Foglet.TUI.Screens.PostComposer.State{} = ss
assert ss.mode == :preview
```

### Pitfall 2: Plain-map seeded state bypassing constructors

**What goes wrong:** Tests hand-build `%{step: :compose, body_input_state: ...}` maps and miss fields or use old field names. [VERIFIED: test/foglet_bbs/tui/screens/new_thread_test.exs; test/foglet_bbs/tui/app_test.exs]

**How to avoid:** Build with `NewThread.init_screen_state(step: :compose, board: board, ...)` or `PostComposer.init_screen_state(...)`, then update only the field under test with `%{ss | field: value}`. [VERIFIED: lib/foglet_bbs/tui/screens/new_thread/state.ex; lib/foglet_bbs/tui/screens/post_composer/state.ex]

### Pitfall 3: Reinitializing nested widget state during render

**What goes wrong:** Calling `TextInput.init/1` or `MultiLineInput.init/1` during render resets cursor/value state and violates D-14. [VERIFIED: .planning/workstreams/phase-03-screen-audit/research/PITFALLS.md; lib/foglet_bbs/tui/widgets/README.md]

**How to avoid:** Initialize nested widgets only in `State.new/1` or missing-state fallback. [VERIFIED: lib/foglet_bbs/tui/screens/new_thread/state.ex; lib/foglet_bbs/tui/screens/post_composer/state.ex]

### Pitfall 4: Losing special key clause order

**What goes wrong:** Moving `Ctrl+S`, `Ctrl+C`, or `Tab` below MultiLineInput forwarding lets composer control keys be treated as text input. [VERIFIED: lib/foglet_bbs/tui/screens/new_thread.ex; lib/foglet_bbs/tui/screens/post_composer.ex]

**How to avoid:** Keep explicit screen-level clauses above the fallback `Compose.translate_key/1` forwarding clauses. [VERIFIED: lib/foglet_bbs/tui/screens/new_thread.ex; lib/foglet_bbs/tui/screens/post_composer.ex]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Single-line title editing | Custom title string/cursor fields | `Foglet.TUI.Widgets.Input.TextInput` in `NewThread.State.title_input_state` | Existing widget already wraps Raxol state and provides max-length handling. [VERIFIED: lib/foglet_bbs/tui/widgets/input/text_input.ex] |
| Multiline body editing | Custom textarea state | `Raxol.UI.Components.Input.MultiLineInput` in `body_input_state` / `input_state` | Current screens already route input through `MultiLineInput.update/2` and render through `Compose.render_input/4`. [VERIFIED: lib/foglet_bbs/tui/screens/new_thread.ex; lib/foglet_bbs/tui/screens/post_composer.ex; lib/foglet_bbs/tui/widgets/compose.ex] |
| Legacy map compatibility | Map-normalization layer | Struct-only runtime shape | The quick-task context explicitly says broad plain-map compatibility is out of scope. [VERIFIED: CONTEXT.md] |

## Likely Test Updates

- `test/foglet_bbs/tui/screens/new_thread_test.exs`: import/alias `NewThread.State`, update helper constructors to use `NewThread.init_screen_state/1`, replace old map seed fields such as `title_input` with `title_input_state`, and assert `%State{}` where appropriate. [VERIFIED: test/foglet_bbs/tui/screens/new_thread_test.exs]
- `test/foglet_bbs/tui/screens/post_composer_test.exs`: replace nested `get_in/2` and `put_in/3` access under `:post_composer` with struct fetch + dot access or `%{ss | field: value}` updates. [VERIFIED: test/foglet_bbs/tui/screens/post_composer_test.exs]
- `test/foglet_bbs/tui/screens/post_reader_test.exs`: update reply composer assertions from `get_in(s.screen_state, [:post_composer, :reply_to])` to `s.screen_state.post_composer.reply_to`. [VERIFIED: test/foglet_bbs/tui/screens/post_reader_test.exs]
- `test/foglet_bbs/tui/app_test.exs`: update resize-preservation tests to seed real `PostComposer.State` and `NewThread.State` structs, not maps with mock nested input maps. [VERIFIED: test/foglet_bbs/tui/app_test.exs]
- Keep PostReader validation in scope because `PostReader.handle_key/2` creates `PostComposer` state for replies. [VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex]

## Validation Architecture

| Property | Value |
|----------|-------|
| Framework | ExUnit via Mix. [VERIFIED: mix project conventions and test files] |
| Quick run command | `mix test test/foglet_bbs/tui/screens/new_thread_test.exs test/foglet_bbs/tui/screens/post_composer_test.exs test/foglet_bbs/tui/screens/post_reader_test.exs test/foglet_bbs/tui/app_test.exs` |
| Full suite command | `mix precommit` [VERIFIED: CLAUDE.md; AGENTS.md] |

### Behavior Map

| Behavior | Test Type | Automated Command |
|----------|-----------|-------------------|
| `NewThread.init_screen_state/1` returns `%NewThread.State{}` with nested TextInput/MultiLineInput state | unit | `mix test test/foglet_bbs/tui/screens/new_thread_test.exs` |
| `PostComposer.init_screen_state/1` returns `%PostComposer.State{}` with nested MultiLineInput state | unit | `mix test test/foglet_bbs/tui/screens/post_composer_test.exs` |
| PostReader reply flow stores `%PostComposer.State{}` with `reply_to` and `origin` | integration/unit | `mix test test/foglet_bbs/tui/screens/post_reader_test.exs` |
| App resize and board-load paths preserve typed screen-state entries | integration/unit | `mix test test/foglet_bbs/tui/app_test.exs` |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | None; material findings above were checked against repo files in this session. | All | None. |

## Sources

### Primary

- `AGENTS.md` / `CLAUDE.md` - project rules, Elixir struct pitfall, test/precommit requirements.
- `.planning/quick/260422-hfc-create-state-structs-for-newthread-and-p/260422-hfc-CONTEXT.md` - locked quick-task decisions.
- `.planning/quick/260422-gx8-add-postreader-state-state-struct-for-po/RESEARCH.md` and `PLAN.md` - PostReader.State precedent.
- `.planning/workstreams/phase-03-screen-audit/research/PITFALLS.md` - D-14 nested widget state handling and key-order pitfalls.
- `lib/foglet_bbs/tui/screens/post_reader/state.ex` - precedent struct implementation.
- `lib/foglet_bbs/tui/screens/new_thread.ex` and `lib/foglet_bbs/tui/screens/new_thread/state.ex` - target screen and state shape.
- `lib/foglet_bbs/tui/screens/post_composer.ex` and `lib/foglet_bbs/tui/screens/post_composer/state.ex` - target screen and state shape.
- `lib/foglet_bbs/tui/widgets/README.md`, `lib/foglet_bbs/tui/widgets/input/text_input.ex`, and `lib/foglet_bbs/tui/widgets/compose.ex` - widget contracts.
- `test/foglet_bbs/tui/screens/new_thread_test.exs`, `test/foglet_bbs/tui/screens/post_composer_test.exs`, `test/foglet_bbs/tui/screens/post_reader_test.exs`, and `test/foglet_bbs/tui/app_test.exs` - likely test update points.

## Metadata

**Confidence breakdown:**
- Standard pattern: HIGH - verified against existing PostReader.State and current NewThread/PostComposer state modules.
- Nested widget handling: HIGH - verified against widget docs and existing constructors.
- Remaining integration work: MEDIUM - `rg` found clear stale test/call-site patterns, but implementation may continue changing after this research.

**Research date:** 2026-04-22
**Valid until:** 2026-05-22
