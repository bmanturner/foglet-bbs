---
phase: 40
slug: verification-documentation
created: 2026-04-29
---

# Phase 40 — Pattern Map

## Purpose

Map the likely Phase 40 edit targets to existing code patterns so execution can
stay close to the current TUI runtime style.

## Runtime Contract Patterns

| Target | Existing analog | Pattern to reuse |
|--------|-----------------|------------------|
| App generic effect tests | `test/foglet_bbs/tui/app_runtime_contract_test.exs` | Register sample screens through `session_context.domain.screen_modules`; assert `App.apply_effect/2`, `App.update/2`, `App.view/1`, and `App.screen_state_for/2` outcomes instead of checking rendered text. |
| App struct invariants | `test/foglet_bbs/tui/app_struct_test.exs` | Pin the App struct field set and absence of screen-specific storage fields. |
| Route-entry and subscriptions | `test/foglet_bbs/tui/app_test.exs` | Use production screen modules and App state fixtures to verify generic routing paths. |
| Screen reducer boundary | `test/foglet_bbs/tui/screens/*_test.exs` | Call `Screen.update(message, local_state, context)` and assert returned local state plus `Foglet.TUI.Effect` values. |
| Render boundary | `lib/foglet_bbs/tui/render_fixtures.ex` and `mix foglet.tui.render` | Populate `%App{}` with screen-local state via `App.put_screen_state/3`, then render through `App.view/1`. |

## Legacy Callback Cleanup

| File | Current role | Closest migration path |
|------|--------------|------------------------|
| `lib/foglet_bbs/tui/app.ex` | Still has fallback production dispatch to `handle_key/2` and `render/1`. | Follow the existing `new_contract_screen?/2`, `route_screen_update/3`, and `render_screen/1` guard style, but make missing new callbacks a no-op/logged failure or explicit raise only after all production screens are migrated. |
| `lib/foglet_bbs/tui/screen.ex` | Declares both new and transitional callbacks. | Preserve `init/1`, `update/3`, `render/2`, and optional `subscriptions/2`; remove or bound legacy callbacks after tests/fixtures stop requiring them. |
| `lib/foglet_bbs/tui/screens/post_reader.ex` | Has both `render/2` and legacy `render/1`/`handle_key/2`. | Existing `update/3` clauses and `State` helpers should replace direct legacy test calls. |
| `lib/foglet_bbs/tui/screens/post_composer.ex` | Has `render/2` plus legacy render/key bodies. | Use `PostComposer.State.new/1` and reducer messages instead of App-shaped fixture maps. |
| `lib/foglet_bbs/tui/screens/new_thread.ex` | Has `render/2` plus legacy render/key bodies. | Use `NewThread.State.new/1`, `init/1`, and reducer messages; avoid source-grep render tests. |
| `lib/foglet_bbs/tui/render_fixtures.ex` | Still calls `init_screen_state/1` for several screens. | Replace with `screen |> App.build_context() |> Screen.init()` or direct state constructors where a screen exposes a first-class `State.new/1`. |

## Modal Failure Pattern

| Target | Existing analog | Pattern to reuse |
|--------|-----------------|------------------|
| Modal submit lock release | `test/foglet_bbs/tui/screens/account_test.exs` BL-01 tests | Preserve state-machine assertions around `Modal.Form.submit_state`; failed submit must become `{:error, _}` and Escape must dismiss. |
| Modal.Form state transitions | `test/foglet_bbs/tui/widgets/modal/form_test.exs` | Use `Modal.Form.set_submit_state/2` for terminal states; do not manually mutate arbitrary form internals unless the public helper cannot express the state. |
| MainMenu oneliner modal handling | `lib/foglet_bbs/tui/screens/main_menu.ex` | Keep screen-owned task-result handling; App only routes `{:modal_submit, kind, payload}` and task results through generic update. |

## Breadcrumb Patterns

| Target | Existing analog | Pattern to reuse |
|--------|-----------------|------------------|
| Explicit screen breadcrumbs | `lib/foglet_bbs/tui/screens/thread_list.ex`, `post_reader.ex`, `post_composer.ex`, `new_thread.ex`, `sysop.ex` | Pass `%{breadcrumb_parts: [...]}` to `ScreenFrame.render/4`; compute labels from screen-local state and `Context`, not App legacy fields. |
| Breadcrumb tests | `test/foglet_bbs/tui/widgets/chrome/breadcrumb_migration_test.exs` | Capture the rendered tree and extract breadcrumb segments; assert the screen emitted non-empty/specific parts. |
| Pending layout tests | `test/foglet_bbs/tui/layout_smoke_test.exs` | Remove `:phase39_login_breadcrumb_pending` once Login explicit breadcrumb expectations are active. |

## Verification And Evidence Patterns

| Target | Existing analog | Pattern to reuse |
|--------|-----------------|------------------|
| Layout size smoke | `test/foglet_bbs/tui/layout_smoke_test.exs` | Use `Engine.apply_layout/2` with `{64,22}`, `{80,24}`, `{132,50}` and assert positioned elements fit within width/height. |
| Manual render evidence | `mix foglet.tui.render` task | Record exact commands and pass/fail result in a Phase 40 summary/evidence doc. |
| Final gates | `.planning/codebase/CONVENTIONS.md` | Run `rtk mix test` and `rtk mix precommit`; precommit chains compile, deps, format, Credo, Sobelow, and Dialyzer. |

## Documentation Pattern

Create a TUI-adjacent guide, for example `lib/foglet_bbs/tui/SCREEN_CONTRACT.md`
or `lib/foglet_bbs/tui/README.md`, and link it from
`lib/foglet_bbs/tui/widgets/README.md` or the nearest TUI README surface. The
guide should include concrete snippets or checklists for:

- screen-local state ownership
- `init/1`
- `update/3`
- `render/2`
- `Foglet.TUI.Context`
- `Foglet.TUI.Effect`
- task effects and `{:task_result, op, result}`
- route params
- optional `subscriptions/2`
- modal requests
- render fixtures and `mix foglet.tui.render`

## Non-Patterns To Avoid

- Do not assert arbitrary rendered text just to prove behavior.
- Do not move domain side effects into App, SSH handlers, or render functions.
- Do not introduce end-user browser workflows.
- Do not broaden Phase 40 into all legacy text assertions across the repo.
- Do not treat nested helper `handle_key/2` functions as automatically invalid;
  target production `Foglet.TUI.Screen` legacy boundary and App fallback dispatch.
