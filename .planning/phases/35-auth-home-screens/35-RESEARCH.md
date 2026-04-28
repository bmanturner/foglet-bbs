# Phase 35: Auth & Home Screens - Research

**Researched:** 2026-04-28
**Status:** Complete

## Research Question

What does Phase 35 need in order to migrate Login, Register, Verify, and
MainMenu/oneliners from App-owned local flows to screen-owned
`init/1`, `update/3`, and `render/2` reducers without changing user-facing
auth/home behavior?

## Phase Summary

Phase 35 is a local ownership migration. The phase should keep durable domain
behavior in `Foglet.Accounts`, `Foglet.Accounts.Verification`, and
`Foglet.Oneliners`, while moving key handling, form state, task request
construction, task-result handling, and local MainMenu oneliner state into the
target screen modules.

The most important runtime constraint is that the current App dispatch path only
activates the new reducer path when a screen exports `update/3` and does not
export legacy `handle_key/2`. Rendering similarly prefers `render/2` only when
legacy `render/1` is absent. Plans must therefore migrate each target screen all
the way across the boundary rather than adding new callbacks beside the legacy
ones.

## Source Artifacts Read

- `.planning/phases/35-auth-home-screens/35-CONTEXT.md`
- `.planning/phases/35-auth-home-screens/35-SPEC.md`
- `.planning/REQUIREMENTS.md`
- `.planning/STATE.md`
- `.planning/phases/34-runtime-contract-effects/34-CONTEXT.md`
- `lib/foglet_bbs/tui/screen.ex`
- `lib/foglet_bbs/tui/context.ex`
- `lib/foglet_bbs/tui/effect.ex`
- `lib/foglet_bbs/tui/app.ex`
- `lib/foglet_bbs/tui/screens/login.ex`
- `lib/foglet_bbs/tui/screens/login/state.ex`
- `lib/foglet_bbs/tui/screens/register.ex`
- `lib/foglet_bbs/tui/screens/register/state.ex`
- `lib/foglet_bbs/tui/screens/verify.ex`
- `lib/foglet_bbs/tui/screens/verify/state.ex`
- `lib/foglet_bbs/tui/screens/main_menu.ex`
- `test/foglet_bbs/tui/screens/login_test.exs`
- `test/foglet_bbs/tui/screens/register_test.exs`
- `test/foglet_bbs/tui/screens/verify_test.exs`
- `test/foglet_bbs/tui/screens/main_menu_test.exs`
- `test/foglet_bbs/tui/app_test.exs`
- `.planning/codebase/CONVENTIONS.md`
- `.planning/codebase/STRUCTURE.md`
- `.planning/codebase/TESTING.md`

## Current Architecture Findings

### Phase 34 Runtime Foundation Is Present

`Foglet.TUI.Screen` defines optional `init/1`, `update/3`, and `render/2`
callbacks over screen-local state plus `Foglet.TUI.Context`.
`Foglet.TUI.Context` exposes `current_user`, `session_context`, `session_pid`,
`terminal_size`, `route`, `route_params`, and `domain`. `Foglet.TUI.Effect`
provides `navigate/2`, `task/3`, `open_modal/1`, `dismiss_modal/0`,
`publish/2`, `session/1`, `terminal_size/1`, and `quit/0`.

`Foglet.TUI.App.apply_effect/2` already interprets effects generically. Task
effects run through `Foglet.TUI.Command.task/2` and return
`{:screen_task_result, screen_key, op, result}`; App re-routes those as
`{:task_result, op, result}` into the screen reducer.

### App Still Owns Phase 35 Local Flow

`Foglet.TUI.App` still has production-specific clauses or top-level fields for
the target flows:

- `recent_oneliners`
- `selected_oneliner_index`
- `pending_hide_oneliner_id`
- `{:register_wizard, event}`
- `{:verify_event, event}`
- `{:load_oneliners}`
- `{:oneliners_loaded, entries}`
- `{:open_oneliner_composer}`
- `{:submit_oneliner, payload}`
- `{:oneliner_created, result}`
- `{:open_hide_oneliner_modal, entry_id}`
- `{:submit_hide_oneliner, payload}`
- `{:oneliner_hidden, result}`
- `{:login_result, result}`
- `{:task_error, :login, reason}`

Some of these can be deleted outright after the target screens own the flows.
Modal form submission is the one place where a small generic bridge may remain
necessary because `ModalForm` callbacks currently stash submit payloads in the
process dictionary and App consumes them during `handle_modal_key/3`.

### New-Contract Activation Rules Matter

`App.do_update({:key, key_event}, state)` calls `route_screen_update/3` only
when `new_contract_screen?/2` returns true. That helper requires:

- the screen module exports `update/3`
- the screen module does not export `handle_key/2`

`App.render_screen/1` calls `render(local_state, context)` only when the module
exports `render/2` and does not export `render/1`.

Therefore each migrated screen must remove or stop exporting its legacy
`handle_key/2` and `render/1` callbacks as part of the same plan that adds
`update/3` and `render/2`. Leaving both callback shapes in place will compile
but will keep production input/rendering on the old path.

## Screen Findings

### Login

`Login` already has a map-shaped `Login.State` module and centralized helpers
for menu, form, reset request, reset token, and login result behavior. The
legacy command path currently returns `Command.task(:login, fn ->
{:login_result, authenticate_login(...)} end)` and relies on App
`{:login_result, result}` plus `{:task_error, :login, reason}` clauses.

The migration should keep the existing local state shape, add `init/1`,
`update/3`, and `render/2`, and convert login/reset submissions to
`Effect.task(:login, :login, fun)` style results consumed as
`{:task_result, :login, result}`. Reset-token consumption and reset request
outcomes should also be reducer-owned.

### Register

`Register` has `Register.State` and legacy `handle_wizard_event/2`. Enter on
the invite step emits `{:register_wizard, {:submit_step, :invite_code, value}}`,
which App delegates back into the screen. This is the central loop to collapse.

The migration should convert wizard events into local reducer messages such as
`{:wizard, event}` or direct key/task messages. Registration submission and
verification delivery work should be requested through effects; session
promotion, modal display, navigation, and pending-approval termination should be
effects returned by `Register.update/3`.

### Verify

`Verify` owns local state and helper functions, but developer/test event routing
still goes through App `{:verify_event, event}` to
`Verify.handle_verify_event/2`. Submit/resend behavior should become reducer
messages and task results consumed by `Verify.update/3`.

Tests should drive character entry, backspace, submit, resend, cooldown,
no-user, success, invalid, expired, and delivery failure paths through
`Verify.init/1` and `Verify.update/3`.

### MainMenu

`MainMenu` is documented as stateless but reads and mutates App-shaped state for
oneliners. It currently returns tuple commands for composer/hide actions and
uses helpers that read `recent_oneliners`, `selected_oneliner_index`,
`pending_hide_oneliner_id`, and `current_user` from the App struct.

Add `Foglet.TUI.Screens.MainMenu.State` in
`lib/foglet_bbs/tui/screens/main_menu/state.ex`. The state should own at least:

- `recent_oneliners`
- `selected_oneliner_index`
- `pending_hide_oneliner_id`
- local lifecycle/error fields needed to test load/create/hide result handling

`MainMenu.init/1` should return a state struct and, if an authenticated user is
present, the load request should be driven by `update/3` through either an
explicit initial message in App navigation or a reducer-owned key/message path.
`MainMenu.update/3` should own menu navigation, select up/down, composer open,
composer submit, hide-modal open, hide submit validation, create result, hide
result, and visible action gating.

## Recommended Plan Split

1. Migrate Login to the new reducer boundary and update focused Login/App
   tests.
2. Migrate Register and Verify to the new reducer boundary and update focused
   onboarding tests.
3. Add MainMenu state and migrate oneliner load/create/hide/navigation to
   `MainMenu.update/3`.
4. Remove or reduce remaining App Phase 35 local-flow clauses, update docs, and
   run the integrated auth/home suite.

The first three plans can be built independently enough to keep code review
focused. The fourth plan should depend on them because App clause removal is
only safe once all target screens own their local flows.

## Risks And Mitigations

| Risk | Mitigation |
|------|------------|
| Adding `update/3` without removing `handle_key/2` leaves production on the legacy path. | Each screen migration task must remove legacy callback exports or explicitly change App dispatch only for that screen with tests proving key routing reaches `update/3`. |
| Adding `render/2` without removing `render/1` leaves production rendering on the legacy path. | Each screen plan must verify `render/2` is used by App for the target screen. |
| Screen task closures capture the full App state. | Bind only user, domain module, route/screen key, and input values before creating `Effect.task/3` functions. |
| Modal form submission stays screen-specific in App. | Prefer generic modal submit events/effects. If a bridge remains, document it as generic runtime plumbing and keep MainMenu business state in `MainMenu.State`. |
| App tests keep asserting old top-level oneliner fields. | Move oneliner behavior assertions to `MainMenu.State` and App generic routing tests. |
| Behavior changes hide behind text-only tests. | Use reducer state/effect assertions, task-result assertions, and focused App routing checks; use render smoke only for layout preservation. |

## Validation Architecture

Phase 35 validation should use existing ExUnit infrastructure. The quick test
loop should run only affected TUI screen/App files; the full phase gate should
also run compile with warnings as errors.

Quick command:

`rtk mix test test/foglet_bbs/tui/screens/login_test.exs test/foglet_bbs/tui/screens/register_test.exs test/foglet_bbs/tui/screens/verify_test.exs test/foglet_bbs/tui/screens/main_menu_test.exs test/foglet_bbs/tui/app_test.exs`

Full command:

`rtk mix test test/foglet_bbs/tui/screens/login_test.exs test/foglet_bbs/tui/screens/register_test.exs test/foglet_bbs/tui/screens/verify_test.exs test/foglet_bbs/tui/screens/main_menu_test.exs test/foglet_bbs/tui/app_test.exs test/foglet_bbs/tui/layout_smoke_test.exs && rtk mix compile --warnings-as-errors`

Validation should assert:

- Login reducer emits task/navigation/modal/session effects and consumes
  `{:task_result, :login, result}` without App `{:login_result, _}` clauses.
- Register reducer owns wizard transitions and registration outcomes without
  `{:register_wizard, _}` delegation.
- Verify reducer owns code entry, submit/resend, cooldown, and no-user/error
  outcomes without `{:verify_event, _}` delegation.
- MainMenu state owns oneliner rows, selection, pending hide target, load,
  create, hide, and visible action gating.
- App generic `{:screen_task_result, screen_key, op, result}` routing remains
  the only task-result path needed for target screens.
- Modal precedence, Ctrl+C/quit, session promotion, pending approval
  termination, no-email reset honesty, verification delivery failures, and
  oneliner composer/hide behavior stay covered.

## Research Complete

Phase 35 can proceed with four executable plans: three screen-family migration
plans plus one integration cleanup and verification plan.
