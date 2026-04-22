---
status: planned
task: "Create state structs for NewThread and PostComposer"
phase: 260422-hfc-create-state-structs-for-newthread-and-p
plan: 1
type: execute
wave: 1
depends_on: []
files_modified:
  - lib/foglet_bbs/tui/screens/new_thread/state.ex
  - lib/foglet_bbs/tui/screens/new_thread.ex
  - lib/foglet_bbs/tui/screens/thread_list.ex
  - lib/foglet_bbs/tui/app.ex
  - lib/foglet_bbs/tui/screens/post_composer/state.ex
  - lib/foglet_bbs/tui/screens/post_composer.ex
  - lib/foglet_bbs/tui/screens/post_reader.ex
  - test/foglet_bbs/tui/screens/new_thread_test.exs
  - test/foglet_bbs/tui/screens/post_composer_test.exs
  - test/foglet_bbs/tui/screens/main_menu_test.exs
  - test/foglet_bbs/tui/screens/post_reader_test.exs
  - test/foglet_bbs/tui/screens/thread_list_test.exs
  - test/foglet_bbs/tui/app_test.exs
autonomous: true
requirements:
  - QUICK-260422-hfc
must_haves:
  truths:
    - "NewThread runtime state is stored as %Foglet.TUI.Screens.NewThread.State{} at state.screen_state[:new_thread]."
    - "PostComposer runtime state is stored as %Foglet.TUI.Screens.PostComposer.State{} at state.screen_state[:post_composer]."
    - "Nested TextInput and MultiLineInput state is initialized by State.new/1 or init_screen_state/1, not by render paths."
    - "Existing compose, cancel, submit, preview, resize-gate, and reply-origin behavior is preserved."
  artifacts:
    - path: "lib/foglet_bbs/tui/screens/new_thread/state.ex"
      provides: "NewThread.State struct and constructor"
      exports: ["new/1"]
    - path: "lib/foglet_bbs/tui/screens/post_composer/state.ex"
      provides: "PostComposer.State struct and constructor"
      exports: ["new/1"]
    - path: "lib/foglet_bbs/tui/screens/new_thread.ex"
      provides: "NewThread screen-state integration"
      contains: "alias Foglet.TUI.Screens.NewThread.State"
    - path: "lib/foglet_bbs/tui/screens/post_composer.ex"
      provides: "PostComposer screen-state integration"
      contains: "alias Foglet.TUI.Screens.PostComposer.State"
  key_links:
    - from: "lib/foglet_bbs/tui/screens/new_thread.ex"
      to: "lib/foglet_bbs/tui/screens/new_thread/state.ex"
      via: "init_screen_state/1 delegates to State.new/1"
      pattern: "State\\.new"
    - from: "lib/foglet_bbs/tui/screens/post_composer.ex"
      to: "lib/foglet_bbs/tui/screens/post_composer/state.ex"
      via: "init_screen_state/1 and missing-state fallback delegate to State.new/1"
      pattern: "State\\.new"
    - from: "lib/foglet_bbs/tui/screens/post_reader.ex"
      to: "state.screen_state[:post_composer]"
      via: "reply navigation stores PostComposer.State with origin: :post_reader"
      pattern: "PostComposer\\.init_screen_state"
---

# Plan: Create NewThread.State and PostComposer.State

## Goal

Migrate `state.screen_state[:new_thread]` and `state.screen_state[:post_composer]` from untyped plain maps to `%Foglet.TUI.Screens.NewThread.State{}` and `%Foglet.TUI.Screens.PostComposer.State{}` while preserving current screen behavior.

This implements the locked nested-widget-state decision from `260422-hfc-CONTEXT.md`: stateful widget structs are first-class fields owned by the screen state struct, initialized by constructors, and not initialized in render paths.

## Source Coverage Audit

| Source | Item | Coverage |
|--------|------|----------|
| CONTEXT | `NewThread.State` and `PostComposer.State` own nested widget structs per D-14 | Tasks 1 and 2 |
| CONTEXT | Runtime paths store structs at `state.screen_state[:new_thread]` and `state.screen_state[:post_composer]` | Tasks 1 and 2 |
| CONTEXT | Broad legacy plain-map compatibility is out of scope; missing state may initialize to struct shape | Tasks 1, 2, and 3 |
| CONTEXT | Preserve field names, including `PostComposer.State.origin` | Tasks 1 and 2 |
| RESEARCH | Avoid `get_in(..., [:screen, :field])` against structs | Tasks 1, 2, and 3 |
| RESEARCH | Preserve compose behavior and validate with focused tests plus precommit | Task 3 |

## Scope

- Add one state module per screen under the screen-named directory.
- Delegate `init_screen_state/1` to the new constructors.
- Update runtime call sites that mutate or seed these screen states to preserve the struct shape.
- Update tests to assert and seed concrete state structs.

## Out of Scope

- No changes to compose, render, submit, cancel, preview, resize-gate, read-position, or domain behavior.
- No change to the top-level `Foglet.TUI.App.screen_state` representation; it remains a map keyed by screen atom.
- No broad compatibility layer for legacy plain-map screen states.

## Tasks

<task type="auto" tdd="true">
  <name>Task 1: Add and wire NewThread.State</name>
  <files>lib/foglet_bbs/tui/screens/new_thread/state.ex, lib/foglet_bbs/tui/screens/new_thread.ex, lib/foglet_bbs/tui/screens/thread_list.ex, lib/foglet_bbs/tui/app.ex</files>
  <behavior>
    - `NewThread.init_screen_state/1` returns `%Foglet.TUI.Screens.NewThread.State{}`.
    - `State.new/1` initializes `title_input_state` with `TextInput.init/1` and `body_input_state` with `MultiLineInput.init/1`.
    - New-thread board selection, direct compose entry from ThreadList, board-loading updates, and compose cancellation preserve `%NewThread.State{}`.
  </behavior>
  <action>Create `Foglet.TUI.Screens.NewThread.State` in `lib/foglet_bbs/tui/screens/new_thread/state.ex` with `@type t`, `defstruct`, and `new/1`. Keep the semantic fields named `step`, `boards`, `selected_board_index`, `board`, `title_input_state`, `body_input_state`, `focused`, `mode`, `error`, and `origin` per locked context. Move widget default initialization into `State.new/1`; pass the configured thread-title cap from `NewThread.init_screen_state/1` as an option so existing cap behavior is preserved. In `NewThread`, alias `State`, change `init_screen_state/1` to return `State.t()`, replace render-path `Map.get(ss, :title_input_state, ...)` fallbacks with direct struct field access, and use struct updates (`%{ss | ...}`) for all mutations. In `ThreadList` and `App` new-thread paths, update state with struct-safe updates and do not use `Map.merge/2` in a way that can obscure the intended struct shape.</action>
  <verify>
    <automated>mix test test/foglet_bbs/tui/screens/new_thread_test.exs</automated>
  </verify>
  <done>`NewThread.init_screen_state/1`, board-selection transitions, ThreadList direct-compose entry, and board-load completion all store `%NewThread.State{}` while preserving existing behavior.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: Add and wire PostComposer.State</name>
  <files>lib/foglet_bbs/tui/screens/post_composer/state.ex, lib/foglet_bbs/tui/screens/post_composer.ex, lib/foglet_bbs/tui/screens/post_reader.ex</files>
  <behavior>
    - `PostComposer.init_screen_state/1` returns `%Foglet.TUI.Screens.PostComposer.State{}`.
    - `State.new/1` initializes `input_state` with `MultiLineInput.init/1`.
    - Reply navigation from PostReader stores `%PostComposer.State{origin: :post_reader}` and cancel routes back to `:post_reader`.
    - Missing `:post_composer` screen state initializes to the new struct shape.
  </behavior>
  <action>Create `Foglet.TUI.Screens.PostComposer.State` in `lib/foglet_bbs/tui/screens/post_composer/state.ex` with `@type t`, `defstruct`, and `new/1`. Keep fields `mode`, `reply_to`, `error`, `input_state`, and `origin`; default `origin` to `:main_menu`. In `PostComposer`, alias `State`, change `init_screen_state/1` and the private `composer_screen_state/1` fallback to delegate to `State.new/1`, use `Map.get(state.screen_state, :post_composer)` for the top-level screen-state map, and remove nested plain-map fallback behavior for screen states missing `input_state`. Keep `build_reply_attrs/2` and `cancel/1` struct-safe by reading `ss.reply_to` and `ss.origin`. In `PostReader`, keep the reply navigation path struct-safe by setting origin on the `%PostComposer.State{}` returned by `PostComposer.init_screen_state/1`.</action>
  <verify>
    <automated>mix test test/foglet_bbs/tui/screens/post_composer_test.exs</automated>
  </verify>
  <done>`PostComposer.init_screen_state/1`, missing-state fallback, input handling, submit, cancel, and PostReader reply entry all operate on `%PostComposer.State{}` without changing user-visible behavior.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 3: Update tests and run final validation</name>
  <files>test/foglet_bbs/tui/screens/new_thread_test.exs, test/foglet_bbs/tui/screens/post_composer_test.exs, test/foglet_bbs/tui/screens/main_menu_test.exs, test/foglet_bbs/tui/screens/post_reader_test.exs, test/foglet_bbs/tui/screens/thread_list_test.exs, test/foglet_bbs/tui/app_test.exs</files>
  <behavior>
    - Tests seed screen states via `init_screen_state/1` or the new state constructors instead of hand-written plain maps.
    - Tests assert concrete state structs where the runtime shape matters.
    - Tests avoid nested `get_in`/`put_in` through struct fields; use direct field access and struct updates.
  </behavior>
  <action>Update NewThread, PostComposer, MainMenu, PostReader, ThreadList, and App tests to reflect the new supported runtime state shape. Add aliases for `NewThread.State` and `PostComposer.State` where useful. Replace hand-written `%{new_thread: %{...}}` and `%{post_composer: %{...}}` fixtures with `NewThread.init_screen_state/1`, `PostComposer.init_screen_state/1`, or struct updates from those constructors. Convert assertions such as `get_in(state.screen_state, [:post_composer, :mode])`, `get_in(state, [:screen_state, :new_thread, :step])`, and `put_in(..., [:screen_state, :post_composer, :origin], ...)` to struct-safe access/update. Keep existing behavioral assertions intact; this is a state-shape migration only.</action>
  <verify>
    <automated>mix test test/foglet_bbs/tui/screens/new_thread_test.exs test/foglet_bbs/tui/screens/post_composer_test.exs test/foglet_bbs/tui/screens/main_menu_test.exs test/foglet_bbs/tui/screens/post_reader_test.exs test/foglet_bbs/tui/screens/thread_list_test.exs test/foglet_bbs/tui/app_test.exs</automated>
    <automated>mix compile --warnings-as-errors</automated>
    <automated>mix precommit</automated>
  </verify>
  <done>Focused tests, warnings-as-errors compile, and `mix precommit` pass with all updated tests using the struct runtime shape.</done>
</task>

## Threat Model

## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Terminal key events -> TUI screen handlers | Untrusted terminal input updates compose state. |
| TUI screen state -> domain create calls | User-authored title/body text crosses into thread/post creation. |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-260422-hfc-01 | T | `NewThread.handle_key/2`, `PostComposer.handle_key/2` | accept | No new input paths are introduced; existing max-length and empty-body/title checks remain unchanged and covered by tests. |
| T-260422-hfc-02 | D | State constructors | mitigate | Constructors initialize widget state once and missing-state fallback creates bounded default widgets; no render-path reinitialization loops. |
| T-260422-hfc-03 | I | Screen-state structs | accept | State contains draft text already held in memory before this migration; no logging, persistence, or serialization is added. |

## Verification

Run:

1. `mix test test/foglet_bbs/tui/screens/new_thread_test.exs test/foglet_bbs/tui/screens/post_composer_test.exs test/foglet_bbs/tui/screens/main_menu_test.exs test/foglet_bbs/tui/screens/post_reader_test.exs test/foglet_bbs/tui/screens/thread_list_test.exs test/foglet_bbs/tui/app_test.exs`
2. `mix compile --warnings-as-errors`
3. `mix precommit`

## Success Criteria

- `%NewThread.State{}` and `%PostComposer.State{}` modules exist in their own files.
- `NewThread.init_screen_state/1` and `PostComposer.init_screen_state/1` return concrete structs.
- Runtime screen-state entries for `:new_thread` and `:post_composer` are structs on normal paths.
- Nested widget states remain first-class fields on the screen state structs.
- No nested `get_in(..., [:post_composer, :field])` or `get_in(..., [:new_thread, :field])` access remains where the second hop would target a struct.
- Focused tests and `mix precommit` pass.

## Output

After implementation, create `.planning/quick/260422-hfc-create-state-structs-for-newthread-and-p/SUMMARY.md`.
