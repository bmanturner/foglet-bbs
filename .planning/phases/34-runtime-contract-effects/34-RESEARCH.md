# Phase 34: Runtime Contract & Effects - Research

**Researched:** 2026-04-28
**Status:** Ready for planning

## RESEARCH COMPLETE

## Executive Summary

Phase 34 should land as a focused runtime foundation rather than a broad screen
migration. The codebase already has the old contract (`Foglet.TUI.Screen`
`render/1`, `handle_key/2`, optional `init_screen_state/1`), the runtime owner
(`Foglet.TUI.App`), a task wrapper (`Foglet.TUI.Command.task/2`), context
precedent (`Foglet.TUI.SessionContext`), domain override lookup
(`Foglet.TUI.Screens.Domain`), and screen state structs in several screen
families. The plan should introduce the new contract, `Context`, `Effect`, and
generic App helpers with test-only or foundation sample screens so later
phases can migrate production screens deliberately.

Do not add a dual-runtime fallback. Existing untouched screen paths can remain
reachable through the current App clauses during phases 35-38, but Phase 34's
new helpers should prove the new path directly and avoid auto-detecting old
callback shapes.

## Source Inputs

- `.planning/phases/34-runtime-contract-effects/34-SPEC.md`
- `.planning/phases/34-runtime-contract-effects/34-CONTEXT.md`
- `.planning/REQUIREMENTS.md`
- `.planning/ROADMAP.md`
- `docs/ARCHITECTURE.md`
- `lib/foglet_bbs/tui/screen.ex`
- `lib/foglet_bbs/tui/app.ex`
- `lib/foglet_bbs/tui/command.ex`
- `lib/foglet_bbs/tui/session_context.ex`
- `lib/foglet_bbs/tui/screens/domain.ex`
- `test/foglet_bbs/tui/app_test.exs`
- `vendor/raxol/lib/raxol/core/runtime/command.ex`

## Implementation Findings

### Screen Contract

`Foglet.TUI.Screen` currently exposes:

- `render/1`
- `handle_key/2`
- optional `init_screen_state/1`

Phase 34 should revise this behavior to document and type:

- `init/1`
- `update/3`
- `render/2`

The cleanest plan is to make the new callbacks the behavior contract and prove
them with a sample screen module in tests. Existing production screens can keep
their old functions until their migration phases, but they should not be
treated as compliant with the new contract through a runtime fallback.

### Context Boundary

`Foglet.TUI.SessionContext` is a strong precedent for typed boundaries. The new
`Foglet.TUI.Context` should wrap only screen-facing runtime data:

- `current_user`
- `session_context`
- `session_pid`
- `terminal_size`
- `route`
- `route_params`
- `domain`

It must not expose App-owned screen storage such as `board_list`, `posts`,
`recent_oneliners`, `current_thread_list`, or raw `screen_state`.

Context construction belongs near App/runtime helpers because App owns the live
runtime state. Domain override lookup can reuse the same `:domain` map shape
already consumed by `Foglet.TUI.Screens.Domain`.

### Effect Vocabulary

Effects should be explicit data with constructor functions in
`Foglet.TUI.Effect`. Required categories:

- `navigate`
- `task`
- `modal`
- `publish`
- `session`
- `terminal`
- `quit`

Use structs or documented tuple shapes that are easy to pattern match. A struct
with fields such as `type`, `payload`, and `target` is flexible enough, but
constructors should make the concrete contract obvious and testable.

### Generic App Interpretation

`Foglet.TUI.App` already converts old screen command tuples into Raxol commands
through `process_screen_commands/2`, and many specific `do_update/2` clauses
still mutate screen-specific fields. Phase 34 should add public or testable
runtime helpers that interpret generic `Effect` values without naming a
production screen.

Useful helper boundaries:

- `current_route/1`
- `current_screen_state/1`
- `screen_state_for/2`
- `put_screen_state/3`
- `build_context/1` and `build_context/2`
- `init_screen_state/3`
- `apply_effect/2`
- `apply_effects/2`

These helpers can coexist with old clauses while making the new path explicit.

### Task Result Routing

`Foglet.TUI.Command.task/2` wraps `Raxol.Core.Runtime.Command.task/1` and
returns `{:task_error, op, reason}` on exceptions. Raxol wraps task returns as
`{:command_result, inner}` before delivery to App update. Phase 34 should keep
using this plumbing, but task effects need enough identity to route success and
failure back to the requesting screen's `update/3`.

Recommended task effect payload:

- `id` or `op`
- `screen` or `route`
- `run` zero-arity function
- optional success/failure wrapper names

The App interpreter can wrap the task closure so success becomes
`{:screen_task_result, screen_key, op, {:ok, result}}` and failure becomes
`{:screen_task_result, screen_key, op, {:error, reason}}`, then route that
message through the sample screen's `update/3` in tests.

### Navigation And State

Current navigation is `{:navigate, screen}` with special cases for
`:main_menu`, `:moderation`, and `:sysop`. New navigation effects should carry
route params and initialize target screen state via the new `init/1` contract.

Screen state should be stored by route/screen key. Phase 34 can introduce a
route key shape such as `{:screen, screen_atom}` or `{screen_atom, params}` as a
foundation, while leaving legacy top-level fields for later cleanup phases.

### State Struct Convention

Existing state structs include:

- `Foglet.TUI.Screens.BoardList.State`
- `Foglet.TUI.Screens.PostReader.State`
- `Foglet.TUI.Screens.Account.State`
- `Foglet.TUI.Screens.Sysop.State`

Phase 34 should document this as the convention and prove it with a sample
stateful screen state struct. Stateless screens should explicitly return a
documented sentinel or empty local state from `init/1` rather than relying on
App fields.

## Planning Recommendations

Split the implementation into three plans:

1. Contract and data types: `Screen`, `Context`, `Effect`, and focused tests.
2. Runtime helper/interpreter path in `Foglet.TUI.App` with sample screen
   routing, navigation params, and task result delivery.
3. Preservation and documentation: state convention docs/tests plus targeted
   existing behavior tests.

This keeps the new data contracts stable before App integration, then uses App
tests to prove effects without migrating production screens.

## Pitfalls

- Do not implement a runtime branch that detects whether a module has old or
  new callbacks and silently falls back. That violates D-04 and masks migration
  gaps.
- Do not pass `%Foglet.TUI.App{}` to new `render/2` or `update/3`. Context is
  the screen boundary.
- Do not make task effects execute domain work synchronously in `update/2`.
  They must use `Foglet.TUI.Command.task/2`.
- Do not move all production screen state in Phase 34. That belongs to phases
  35-39.
- Do not write brittle visual tests that only assert incidental text presence.
  Use reducer/effect/helper assertions and one smoke path preservation check.

## Validation Architecture

### Test Targets

- `test/foglet_bbs/tui/screen_test.exs` proves the new behavior contract with
  sample modules and state structs.
- `test/foglet_bbs/tui/context_test.exs` proves context construction includes
  required fields and excludes App-owned screen storage.
- `test/foglet_bbs/tui/effect_test.exs` proves every required effect category
  has a constructor and matchable shape.
- `test/foglet_bbs/tui/app_runtime_contract_test.exs` proves App helpers
  initialize state, build context, interpret effects, route task success and
  failure, and preserve route params.
- `test/foglet_bbs/tui/app_test.exs` remains green for existing init/update
  behavior.
- `test/foglet_bbs/tui/command_test.exs` remains green for task wrapper
  behavior if present; otherwise App runtime tests should execute command task
  closures directly.
- `test/foglet_bbs/tui/layout_smoke_test.exs` can be run as the preservation
  smoke path if the phase touches render dispatch.

### Commands

- Quick targeted suite:
  `rtk mix test test/foglet_bbs/tui/screen_test.exs test/foglet_bbs/tui/context_test.exs test/foglet_bbs/tui/effect_test.exs test/foglet_bbs/tui/app_runtime_contract_test.exs test/foglet_bbs/tui/app_test.exs`
- Full finish-line suite:
  `rtk mix precommit`

### Sampling Rule

After each task that changes runtime contracts or App helpers, run the targeted
suite. Before marking the phase complete, run `rtk mix precommit`.

## Requirement Coverage Notes

- RUNTIME-01: new behavior contract and sample screen tests.
- RUNTIME-02: App routing helpers and screen update dispatch tests.
- RUNTIME-03: `Foglet.TUI.Context` construction and exclusion tests.
- EFFECT-01: `Foglet.TUI.Effect` constructors and shape tests.
- EFFECT-02: App effect interpreter and `Foglet.TUI.Command.task/2` conversion.
- EFFECT-03: task success/failure routing back through sample screen `update/3`.
- EFFECT-04: navigation effects initialize screen state and expose route params.
- STATE-01: state struct convention and sample stateful/stateless declarations.
