# Phase 34: Runtime Contract & Effects - Context

**Gathered:** 2026-04-28 (assumptions mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 34 establishes Foglet's TUI runtime foundation: the new screen contract,
screen context boundary, explicit effect vocabulary, generic App effect
interpreter helpers, task-result routing proof, navigation/route-param proof,
and state-struct conventions. It does not migrate every production screen,
delete existing screen-specific App clauses, add product capabilities, add a
browser UI, replace Raxol, or introduce per-screen processes.
</domain>

<spec_lock>
## Specification Lock

`.planning/phases/34-runtime-contract-effects/34-SPEC.md` locks 8 requirements
and the phase boundaries. Downstream agents MUST read it before planning. Do
not duplicate or reinterpret the requirements from memory; use the SPEC as the
source of truth for what must be delivered and what remains out of scope.
</spec_lock>

<decisions>
## Implementation Decisions

### Screen Contract
- **D-01:** Define the new `Foglet.TUI.Screen` boundary around `init/1`,
  `update/3`, and `render/2`.
- **D-02:** The new callbacks operate on screen-local state plus
  `Foglet.TUI.Context`; screens should not receive or depend on the full
  `%Foglet.TUI.App{}` struct through the new contract.
- **D-03:** Focus Phase 34 tests on sample/foundation screens that prove the
  new contract without forcing all production screen families to migrate in
  this phase.

### Migration Boundary
- **D-04:** Do not add a runtime "old screen vs new screen" fallback detector or
  compatibility layer that hides incomplete migration.
- **D-05:** Existing untouched screen paths may remain in place until phases
  35-38, but the new foundation should not depend on an adapter that quietly
  re-routes old callback shapes.
- **D-06:** Full production screen migrations remain deferred to phases 35-38;
  final deletion of central App screen-specific machinery remains deferred to
  phase 39.

### Context Shape
- **D-07:** Add `Foglet.TUI.Context` as a narrow typed boundary built from App
  runtime data.
- **D-08:** Context should expose current user, session context, session pid,
  terminal size, route params, and domain override access.
- **D-09:** Context should not expose screen-specific App storage such as
  `board_list`, `current_thread_list`, `posts`, `recent_oneliners`, or
  arbitrary `screen_state` internals.

### Effect Model
- **D-10:** Prefer an explicit `Foglet.TUI.Effect` API with typed constructors
  over ad hoc tuple commands.
- **D-11:** Required effect categories are navigation, task, modal
  open/dismiss, publish/session operations, terminal/session updates, and quit.
- **D-12:** Task effects must continue to execute through
  `Foglet.TUI.Command.task/2` so domain work stays off the Raxol update path.
- **D-13:** Task effects must tag success and failure with enough route or
  screen identity to route results through the requesting screen's `update/3`.

### Navigation And State Storage
- **D-14:** Navigation effects should initialize the target screen state via
  the new contract and carry route params such as board, thread, post, or
  origin.
- **D-15:** Phase 34 should establish helper APIs for current route lookup,
  current screen-state access, screen-state initialization, context
  construction, and effect interpretation.
- **D-16:** The implementation should move toward screen-state storage by
  route/screen key without removing top-level legacy App fields until the
  later migration and cleanup phases.

### State And Verification
- **D-17:** Stateful screens should use first-class state structs with `new/1`
  or an explicitly documented local state type.
- **D-18:** Stateless screens should explicitly declare that they do not store
  local state.
- **D-19:** Phase 34 tests should prove reducer/effect contracts and generic
  App helpers. They should not be visual redesign tests or brittle assertions
  that only check for text presence.
- **D-20:** Preserve existing TUI App init/update/view behavior, modal
  precedence, SizeGate behavior, session hooks, command delivery, and at least
  one current screen or render smoke path.

### the agent's Discretion
- Exact struct field names inside `Foglet.TUI.Effect` are flexible if all
  required effect categories remain typed, testable, and easy to pattern-match.
- Exact helper function names are flexible if they make the App/runtime
  boundary obvious and keep screen-owned logic out of App.
- The representative sample screen can be test-only or a tiny foundation
  module, as long as it proves initialization, update, render, task routing,
  navigation params, and state-struct conventions.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Locked Phase Scope
- `.planning/phases/34-runtime-contract-effects/34-SPEC.md` - Locked Phase 34
  requirements, boundaries, constraints, and acceptance criteria.
- `.planning/ROADMAP.md` - v2.0 phase sequencing, Phase 34 goal, and dependency
  notes.
- `.planning/REQUIREMENTS.md` - v2.0 runtime, effect, state, app-shell, and
  verification requirements.
- `.planning/PROJECT.md` - SSH-first product boundary and v2.0 milestone
  intent.

### TUI And Raxol Runtime
- `docs/ARCHITECTURE.md` - TUI/Raxol layer, SSH-first architecture, and
  session/domain ownership notes.
- `docs/raxol/getting-started/WIDGET_GALLERY.md` - Raxol layout, command, and
  component vocabulary used by Foglet screens/widgets.
- `lib/foglet_bbs/tui/widgets/README.md` - Existing widget state convention:
  stateful widgets use `init/1`, `handle_event/2`, and `render/2`; stateless
  widgets expose render functions.

### Codebase Maps
- `.planning/codebase/ARCHITECTURE.md` - Current App, screen, session, domain,
  PubSub, and state-flow map.
- `.planning/codebase/CONVENTIONS.md` - Elixir module, spec, test, OTP, and
  precommit conventions.
- `.planning/codebase/STRUCTURE.md` - Source/test layout and TUI file
  organization.
- `.planning/codebase/TESTING.md` - ExUnit, TUI, OTP, and render smoke testing
  patterns.
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `lib/foglet_bbs/tui/session_context.ex` - Existing typed SSH-to-App boundary;
  useful precedent for `Foglet.TUI.Context`.
- `lib/foglet_bbs/tui/screens/domain.ex` - Existing domain override lookup
  helper for tests and screen/domain boundary calls.
- `lib/foglet_bbs/tui/command.ex` - Existing safe wrapper around
  `Raxol.Core.Runtime.Command.task/1`; task effects should build on this.
- `lib/foglet_bbs/tui/pub_sub_forwarder.ex` - Existing bridge for PubSub into
  Raxol subscription messages.
- `lib/foglet_bbs/tui/screens/post_reader/state.ex`,
  `lib/foglet_bbs/tui/screens/board_list/state.ex`,
  `lib/foglet_bbs/tui/screens/account/state.ex`, and
  `lib/foglet_bbs/tui/screens/sysop/state.ex` - Existing state-struct examples.

### Established Patterns
- Current screens implement `render/1`, `handle_key/2`, and optional
  `init_screen_state/1` from `lib/foglet_bbs/tui/screen.ex`.
- `Foglet.TUI.App` currently normalizes Raxol events, routes keys, owns modal
  and SizeGate precedence, subscribes to PubSub topics, and processes screen
  command tuples through `process_screen_commands/2`.
- Raxol command tasks deliver results as `{:command_result, result}`; App
  already re-dispatches that wrapper through `do_update/2`.
- Widgets already model the smaller local reducer style, making them the best
  local precedent for screen mini update loops.
- Tests mirror source paths under `test/foglet_bbs/...`; existing TUI tests use
  focused reducer assertions, App-shell tests, and render smoke coverage.

### Integration Points
- `lib/foglet_bbs/tui/app.ex` - Main integration point for context
  construction, route/screen-state helpers, effect interpretation, task-result
  routing, modal precedence, SizeGate behavior, and command delivery.
- `lib/foglet_bbs/tui/screen.ex` - Contract update point for the new
  `init/update/render` callbacks.
- `vendor/raxol/lib/raxol/core/runtime/application.ex` and
  `vendor/raxol/lib/raxol/core/runtime/command.ex` - Local Raxol runtime
  behavior and task-command contract.
- `test/foglet_bbs/tui/app_test.exs` - Existing App behavior coverage that
  should remain green and be extended for generic effect interpretation.
- `test/foglet_bbs/tui/layout_smoke_test.exs` - Existing render smoke harness
  for preservation checks when needed.
</code_context>

<specifics>
## Specific Ideas

- User confirmed the assumptions-mode pass without corrections.
- No product or visual redesign requirements were added during discussion.
- No external research is required; Raxol's relevant runtime behavior is
  vendored locally under `vendor/raxol`.
</specifics>

<deferred>
## Deferred Ideas

None - analysis stayed within phase scope.
</deferred>

---

*Phase: 34-runtime-contract-effects*
*Context gathered: 2026-04-28*
