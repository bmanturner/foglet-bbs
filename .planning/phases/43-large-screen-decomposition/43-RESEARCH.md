# Phase 43: Large Screen Decomposition - Research

## RESEARCH COMPLETE

## Objective

Research how to plan Phase 43 so `PostReader`, `Sysop`, `Login`, `MainMenu`, `NewThread`, and `Account` can be decomposed into clear reducer-facing screen modules, sibling state owners, and sibling render entry points without changing SSH-first TUI behavior.

## Sources Read

- `.planning/phases/43-large-screen-decomposition/43-CONTEXT.md`
- `.planning/phases/43-large-screen-decomposition/43-SPEC.md`
- `.planning/REQUIREMENTS.md`
- `.planning/STATE.md`
- `lib/foglet_bbs/tui/SCREEN_CONTRACT.md`
- `lib/foglet_bbs/tui/widgets/README.md`
- `docs/raxol/getting-started/WIDGET_GALLERY.md`
- Current source and test files for all six target screens

## Phase Requirement

- `TUI-05`: Maintainer can work on the largest TUI screens through separated reducer/state/render modules where the concerns audit identified mixed responsibilities.

## Current State

All six target screens already have sibling `State` modules:

| Screen | Top-level file | Lines | State owner | Existing submodules |
|--------|----------------|-------|-------------|---------------------|
| PostReader | `lib/foglet_bbs/tui/screens/post_reader.ex` | 803 | `post_reader/state.ex` | none under `post_reader/` beyond state |
| Sysop | `lib/foglet_bbs/tui/screens/sysop.ex` | 647 | `sysop/state.ex` | `BoardsView`, `UsersView`, `SiteForm`, `LimitsForm`, `SystemSnapshot` |
| Login | `lib/foglet_bbs/tui/screens/login.ex` | 901 | `login/state.ex` | shared `FocusInput` |
| MainMenu | `lib/foglet_bbs/tui/screens/main_menu.ex` | 818 | `main_menu/state.ex` | none under `main_menu/` beyond state |
| NewThread | `lib/foglet_bbs/tui/screens/new_thread.ex` | 522 | `new_thread/state.ex` | none under `new_thread/` beyond state |
| Account | `lib/foglet_bbs/tui/screens/account.ex` | 562 | `account/state.ex` | `ProfileForm`, `PrefsForm`, `SSHKeysSurface`, `SSHKeysActions`, `SSHKeysState` |

The mixed responsibility gap is concentrated in top-level render helpers:

- `PostReader` owns `render_post_content/5`, `render_local_post_content/5`, loading/error/empty rendering, frame assembly, post card body parsing, viewport rendering, and frame model creation in the same module as reducer, subscriptions, read-pointer flushing, and cache-warming helpers.
- `Sysop` owns authorization rendering, frame assembly, keybar construction, tab body dispatch, loading/error panels, and render model creation beside task result, tab selection, save/retry/revoke, and delegated tab update logic.
- `Login` owns menu, login form, reset request, reset token form, text input layout, and keybar selection beside login/reset reducers and task result handling.
- `MainMenu` owns command descriptors, route/oneliner reducers, modal builders, visible destination/action helpers, panel width helpers, navigation panel rendering, and oneliner panel rendering in one file.
- `NewThread` owns board picker rendering, composer rendering, title/body input rendering, frame model creation, and compose hints beside board loading, field edits, validation, and create-thread effects.
- `Account` owns frame assembly, keybar construction, active tab dispatch, theme preview routing, and render model creation beside account reducer logic and existing surface action modules.

## Recommended Decomposition Pattern

Use one sibling render module per target screen:

- `Foglet.TUI.Screens.PostReader.Render` in `lib/foglet_bbs/tui/screens/post_reader/render.ex`
- `Foglet.TUI.Screens.Sysop.Render` in `lib/foglet_bbs/tui/screens/sysop/render.ex`
- `Foglet.TUI.Screens.Login.Render` in `lib/foglet_bbs/tui/screens/login/render.ex`
- `Foglet.TUI.Screens.MainMenu.Render` in `lib/foglet_bbs/tui/screens/main_menu/render.ex`
- `Foglet.TUI.Screens.NewThread.Render` in `lib/foglet_bbs/tui/screens/new_thread/render.ex`
- `Foglet.TUI.Screens.Account.Render` in `lib/foglet_bbs/tui/screens/account/render.ex`

Use a consistent public entry point where practical:

```elixir
@spec render(State.t(), Context.t()) :: any()
def render(%State{} = state, %Context{} = context)
```

For screens that currently normalize nil or legacy map state in the top-level module (`Sysop`, `Account`, `Login`, `MainMenu`), keep normalization in the reducer-facing module and delegate only after a canonical local state or existing map sub-state has been selected. This keeps render modules pure and makes state ownership explicit.

Top-level screen modules should retain:

- `@behaviour Foglet.TUI.Screen`
- `init/1`
- `update/3`
- optional `subscriptions/2`
- effect creation and task result handling
- modal submit handling
- public non-render seams already used by behavior tests, such as `PostReader.load_posts/2`, `PostReader.flush_read_pointers/2`, `MainMenu.visible_destinations/1`, `MainMenu.visible_actions/1`, and `MainMenu.__nav_panel_inner_width__/1`

Render modules should own:

- `ScreenFrame.render/4` calls
- chrome and keybar model assembly
- tab/body/panel/form/composer render helper families
- display-only width calculations
- existing widget orchestration
- existing `Raxol.Core.Renderer.View` imports needed to produce view trees

Render modules must not own:

- Repo calls
- PubSub subscriptions
- `Effect.task/3`, `Effect.navigate/2`, `Effect.open_modal/1`, or any other task/runtime effect creation
- domain writes
- state mutation for reducer semantics

## Suggested Extraction Order

1. `NewThread` and `Login`: smaller or self-contained render surfaces with focused reducer tests already present.
2. `MainMenu`: medium-risk because command descriptors feed both rendering and reducer behavior; keep command descriptors and public visibility helpers in the reducer-facing module unless implementation proves they are render-only.
3. `Sysop` and `Account`: tab shells already delegate substantial body rendering to surface modules; render extraction should orchestrate those existing modules instead of replacing them.
4. `PostReader`: highest risk because render helpers are interleaved with cache warming and read-pointer behavior. Extract render helpers while leaving `warm_viewport/4`, `load_posts/2`, read-pointer flushing, subscriptions, and Phase 44 eager-loading/cache-invalidation concerns in the reducer/state side.

This order keeps each plan independently testable and avoids leaving a screen half-migrated.

## Existing Test Surfaces

Per-screen tests already exercise reducer and effect behavior:

- `test/foglet_bbs/tui/screens/new_thread_test.exs` covers route initialization, board load effects, board picker navigation, compose field focus, validation, submit effects, task result routing, and structural composer boundaries.
- `test/foglet_bbs/tui/screens/login_test.exs` covers login/reset state transitions and task result behavior.
- `test/foglet_bbs/tui/screens/main_menu_test.exs` covers navigation, oneliner state, modal submit paths, visibility helpers, and App/local state integration.
- `test/foglet_bbs/tui/screens/sysop_test.exs` covers tab visibility, task result routing, retry behavior, users view actions, config-accountability protections, and invite visibility.
- `test/foglet_bbs/tui/screens/account_test.exs` covers profile/prefs/SSH keys/invites behavior and account shell interactions.
- `test/foglet_bbs/tui/screens/post_reader_test.exs` covers route identity, loading, subscriptions, thread activity, read-pointer flushing, navigation, and cache-related state behavior.
- `test/foglet_bbs/tui/layout_smoke_test.exs` already renders all six target screens through smoke helpers and has structural fit/overlap assertions in several sections.

Implementation plans should add focused tests that prove ownership boundaries rather than asserting text exists:

- module/file existence and top-level `render/2` delegation checks using source-shape assertions are acceptable for decomposition contract coverage;
- reducer/effect tests should continue to drive `Screen.update/3`;
- render smoke checks should use existing layout helpers or `rtk mix foglet.tui.render` evidence.

## Risks And Mitigations

| Risk | Why it matters | Mitigation |
|------|----------------|------------|
| Moving reducer helpers into render modules by accident | Render modules would stop being pure and create confusing ownership | Plan tasks must grep render modules for `Effect.`, `Repo`, `PubSub`, `Config.put`, `start`, and domain writes |
| Breaking tests that call private render-adjacent public seams | `MainMenu.__nav_panel_inner_width__/1`, visibility helpers, and `PostReader.load_posts/2` are used by current tests | Preserve public non-render seams unless explicitly replaced with behavior-equivalent tests |
| PostReader cache/read-pointer behavior changes during render extraction | Phase 44 owns eager loading and cache eviction; this phase must not rewrite them | Leave `warm_viewport/4`, `render_cache` mutation plumbing, load intent, and read-pointer flushing in the top-level module/state side |
| Sysop/Account submodule boundaries get flattened | Existing surface modules are already useful decomposition boundaries | Render modules should orchestrate `BoardsView`, `UsersView`, `ProfileForm`, `PrefsForm`, `SSHKeysSurface`, and `InvitesSurface` |
| Tests drift into text-presence checks | AGENTS.md explicitly forbids pure UI text-presence tests | Use structural module/delegation assertions, state/effect assertions, and positioned layout fit/overlap smoke helpers |

## Validation Architecture

Use existing ExUnit and TUI smoke infrastructure. No new framework is needed.

Quick per-plan commands:

- `rtk mix test test/foglet_bbs/tui/screens/new_thread_test.exs test/foglet_bbs/tui/screens/login_test.exs`
- `rtk mix test test/foglet_bbs/tui/screens/main_menu_test.exs`
- `rtk mix test test/foglet_bbs/tui/screens/sysop_test.exs test/foglet_bbs/tui/screens/account_test.exs`
- `rtk mix test test/foglet_bbs/tui/screens/post_reader_test.exs`
- `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs`

Full phase verification:

- `rtk mix test test/foglet_bbs/tui/screens/new_thread_test.exs test/foglet_bbs/tui/screens/login_test.exs test/foglet_bbs/tui/screens/main_menu_test.exs test/foglet_bbs/tui/screens/sysop_test.exs test/foglet_bbs/tui/screens/account_test.exs test/foglet_bbs/tui/screens/post_reader_test.exs test/foglet_bbs/tui/layout_smoke_test.exs`
- `rtk mix compile --warnings-as-errors`
- `rtk mix precommit`

Render evidence should cover these screen names where the renderer supports them:

- `rtk mix foglet.tui.render login --no-frame`
- `rtk mix foglet.tui.render main_menu --no-frame`
- `rtk mix foglet.tui.render new_thread --no-frame`
- `rtk mix foglet.tui.render account --no-frame`
- `rtk mix foglet.tui.render sysop --no-frame`
- `rtk mix foglet.tui.render post_reader --no-frame`

## Planning Implications

Recommended plan split:

1. Establish documentation and the first low-risk render modules for `NewThread` and `Login`.
2. Extract `MainMenu.Render` while preserving command descriptors and public visibility helpers.
3. Extract `Sysop.Render` and `Account.Render` around existing surface modules.
4. Extract `PostReader.Render` last and avoid Phase 44 content-query/cache changes.
5. Run cross-screen smoke/contract verification and finalize docs.

Every plan should list `TUI-05` in `requirements` and cite the relevant `D-XX` decisions in `<must_haves>`.

