---
phase: 35-auth-home-screens
verified: 2026-04-28T20:50:45Z
status: passed
score: 20/20 must-haves verified
overrides_applied: 0
deferred:
  - truth: "Full current worktree App/layout smoke command is green"
    addressed_in: "Phase 36"
    evidence: "Phase 36 goal: Migrate board and thread browsing so directory state and async loads belong to BoardList/ThreadList; current failures are BoardList/ThreadList render arity/test harness failures covered by SCREEN-03."
---

# Phase 35: Auth & Home Screens Verification Report

**Phase Goal:** Prove the pattern on entry and home flows by migrating Login, Register, Verify, and MainMenu/oneliners.
**Verified:** 2026-04-28T20:50:45Z
**Status:** passed
**Re-verification:** No - initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Login, Register, Verify, and MainMenu no longer require App-specific result clauses for their local flows. | VERIFIED | `lib/foglet_bbs/tui/app.ex` has generic `{:screen_task_result, key, op, result}` routing at line 1033 and no `do_update` clauses for `:register_wizard`, `:verify_event`, `:login_result`, `:load_oneliners`, `:submit_oneliner`, or hide/oneliner result messages. |
| 2 | Auth task results and reset/verification errors are handled by the owning screen reducer. | VERIFIED | Login handles `:login`, `:reset_request`, and `:reset_token` task results at lines 119-186; Register handles `:register` and `:verification_delivery` at lines 109-126; Verify handles `:verify_submit` and `:verify_resend` at lines 119-142. |
| 3 | MainMenu owns recent oneliners and selected oneliner state. | VERIFIED | `MainMenu.State` defines `recent_oneliners`, `selected_oneliner_index`, `pending_hide_oneliner_id`, `oneliner_status`, and `oneliner_errors` in `lib/foglet_bbs/tui/screens/main_menu/state.ex`; App no longer has top-level oneliner fields. |
| 4 | Existing auth/home tests and render fixtures pass after migration. | VERIFIED | Target screen tests pass: `rtk mix test test/foglet_bbs/tui/screens/login_test.exs test/foglet_bbs/tui/screens/register_test.exs test/foglet_bbs/tui/screens/verify_test.exs test/foglet_bbs/tui/screens/main_menu_test.exs` => 163 tests, 0 failures. `rtk mix compile --warnings-as-errors` passes. Full App/layout command is currently blocked by deferred Phase 36 BoardList/ThreadList render migration failures. |
| 5 | D-01: Login keeps map-shaped `Login.State` while exposing `init/1`, `update/3`, and `render/2`. | VERIFIED | `Login.init/1`, `Login.update/3`, and `Login.render/2` exist at lines 81-190 and use `LoginState.default/0` / local map state. |
| 6 | D-02: Login submission uses the task effect path and consumes `{:task_result, :login, result}`. | VERIFIED | `Effect.task(:login, :login, fn -> ... end)` is emitted at line 799; task results are consumed at lines 119-126. |
| 7 | D-03: Login/reset behavior is preserved, including reset honesty and reset-token consumption. | VERIFIED | Reset request and token consumption emit `Effect.task/3` at lines 726 and 780; task-result branches preserve generic email/no-email/token failure copy at lines 133-186. |
| 8 | D-14: Login tests assert reducer state/effects through `init/1` and `update/3`. | VERIFIED | `test/foglet_bbs/tui/screens/login_test.exs` drives `Login.init/1`, `Login.update/3`, and `Login.render/2`; no production `Login.handle_key/2` export remains. |
| 9 | D-04: Register and Verify preserve wizard/code-entry semantics in screen reducers. | VERIFIED | Register owns key and wizard messages at lines 67-107; Verify owns escape, backspace, enter, code entry, submit, and resend messages at lines 72-117. |
| 10 | D-05: `{:register_wizard, event}` and `{:verify_event, event}` are no longer App production delegation clauses. | VERIFIED | Search found no matching `do_update` clauses in `lib/foglet_bbs/tui/app.ex`. Register/Verify tests call screen reducers directly. |
| 11 | D-06: Registration, verification delivery, submit, and resend domain work remains in contexts and is requested through effects. | VERIFIED | Register wraps `accounts_mod.register_*` and verification delivery in `Effect.task(:register, :register, ...)`; Verify wraps `deliver_verification_code/1` and `verify_email_code/2` in task effects. |
| 12 | D-16: Pending approval termination and verification delivery failures remain covered. | VERIFIED | Register result handling emits `Effect.session({:terminate_after_modal, :pending_approval})` and verification failure modals; focused reducer tests cover these paths. |
| 13 | D-07: MainMenu is stateful. | VERIFIED | `Foglet.TUI.Screens.MainMenu.State` exists and `MainMenu.init/1` returns `State.new(context)`. |
| 14 | D-08: MainMenu.State owns oneliner rows, selection, pending hide target, and lifecycle fields. | VERIFIED | `defstruct` in `state.ex` contains the required fields and helpers for load, selection, pending hide, and errors. |
| 15 | D-09: App top-level oneliner fields are no longer source of truth. | VERIFIED | App grep found no `recent_oneliners`, `selected_oneliner_index`, or `pending_hide_oneliner_id`; tests use `App.screen_state_for(state, :main_menu)`. |
| 16 | D-10: MainMenu keeps visible-action gating and role-aware hide behavior. | VERIFIED | MainMenu uses `ShellVisibility` for account/moderation/sysop navigation and `selected_hideable_oneliner/1`/authorization-aware gating for hide actions. |
| 17 | D-11: MainMenu owns composer/hide decisions and create/hide task results. | VERIFIED | MainMenu handles `{:modal_submit, :oneliner_composer, ...}`, `{:modal_submit, :hide_oneliner, ...}`, `:submit_oneliner`, and `:submit_hide_oneliner` task results at lines 241-377. |
| 18 | D-12: Remaining modal bridge is generic runtime plumbing, not MainMenu business state. | VERIFIED | App modal submit handling only takes `{screen_key, kind, payload}` from `:pending_screen_modal_submit` and routes `{:modal_submit, kind, payload}` via `route_screen_update/3`; business validation lives in MainMenu. |
| 19 | D-13/D-15: App remains generic runtime/effect interpreter and tests prove generic routing. | VERIFIED | App applies task effects into `{:screen_task_result, screen_key, op, ...}` at lines 215-234 and routes effects through screen reducers. App tests assert generic screen task routing for target screens. |
| 20 | D-17: Tests avoid brittle text-only assertions for the migrated contract. | VERIFIED | Target screen tests assert reducer state and `Effect` values; text collection appears in render smoke helpers but does not replace reducer/effect assertions. |

**Score:** 20/20 truths verified

### Deferred Items

Items not yet met but explicitly addressed in later milestone phases.

| # | Item | Addressed In | Evidence |
|---|------|-------------|----------|
| 1 | Full current worktree App/layout smoke command is green. | Phase 36 | Current failures are `BoardList.render/1` and `ThreadList.render/1`/`render/2` arity/state-shape failures. ROADMAP Phase 36 and requirement SCREEN-03 explicitly cover BoardList and ThreadList migration and canonical render smoke checks. |

### Required Artifacts

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `lib/foglet_bbs/tui/screens/login.ex` | `init/1`, `update/3`, `render/2`; no legacy local-flow exports | VERIFIED | Exports new contract; no `def handle_key` or `def render(state)` found. |
| `lib/foglet_bbs/tui/screens/register.ex` | `init/1`, `update/3`, `render/2`; no `handle_wizard_event/2` or `handle_key/2` | VERIFIED | Register reducer owns key, wizard, register task, and delivery result messages. |
| `lib/foglet_bbs/tui/screens/verify.ex` | `init/1`, `update/3`, `render/2`; no `handle_verify_event/2` or `handle_key/2` | VERIFIED | Verify reducer owns code entry, submit, resend, cooldown, and task-result handling. |
| `lib/foglet_bbs/tui/screens/main_menu.ex` | Stateful reducer owns navigation, modal submits, and oneliner task results | VERIFIED | MainMenu emits navigation/modal/task/quit effects and consumes load/create/hide task results. |
| `lib/foglet_bbs/tui/screens/main_menu/state.ex` | MainMenu local state struct | VERIFIED | Struct and helpers exist with documented fields. |
| Target tests | Reducer/effect coverage | VERIFIED | Four migrated screen test files pass: 163 tests, 0 failures. |

### Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| Screens | App async runtime | `Effect.task/3` -> `Command.task/2` -> `{:screen_task_result, screen_key, op, result}` | VERIFIED | `App.apply_effect/2` wraps task success/failure and tags by requesting screen key. |
| App task result | Screen reducers | `route_screen_update(state, key, {:task_result, op, result})` | VERIFIED | `do_update({:screen_task_result, key, op, result}, state)` routes generically. |
| Modal form submit | MainMenu reducer | Process-stashed `{screen_key, kind, payload}` -> `{:modal_submit, kind, payload}` | VERIFIED | App bridge is generic; MainMenu owns composer/hide validation and task creation. |
| MainMenu screen state | Render | `MainMenu.render(local_state, context)` reads `MainMenu.State` | VERIFIED | Render model uses `recent_oneliners`, `selected_oneliner_index`, and `pending_hide_oneliner_id` from local state. |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|---|---|---|---|---|
| Login | Auth/reset results | `Effect.task` closures call Accounts/Auth/Verification domain modules; App routes results back | Yes | VERIFIED |
| Register | Registration/verification outcomes | `Effect.task(:register, :register, ...)` calls Accounts and Verification domains | Yes | VERIFIED |
| Verify | Code submit/resend outcomes | `Effect.task(:verify_submit/:verify_resend, :verify, ...)` calls Verification domain | Yes | VERIFIED |
| MainMenu | Recent oneliners | `Effect.task(:load_oneliners, :main_menu, ...)` calls Oneliners domain; result populates `MainMenu.State.recent_oneliners` | Yes | VERIFIED |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| Target screen reducer/effect suites pass | `rtk mix test test/foglet_bbs/tui/screens/login_test.exs test/foglet_bbs/tui/screens/register_test.exs test/foglet_bbs/tui/screens/verify_test.exs test/foglet_bbs/tui/screens/main_menu_test.exs` | 163 tests, 0 failures | PASS |
| Compile gate passes | `rtk mix compile --warnings-as-errors` | Exit 0 | PASS |
| Integrated App/layout command in current worktree | `rtk mix test ... app_test.exs layout_smoke_test.exs` | Fails on BoardList/ThreadList render migration issues, not Phase 35 target screens | DEFERRED |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|---|---|---|---|---|
| SCREEN-01 | 35-01, 35-02, 35-04 | Login, Register, and Verify own auth/onboarding key handling, local state, task requests, and auth/verification results through the new update loop. | SATISFIED | Login/Register/Verify reducers export `init/1`, `update/3`, `render/2`, emit task effects, and consume task results locally; App-specific local-flow clauses are absent. |
| SCREEN-02 | 35-03, 35-04 | MainMenu owns oneliner state, composer/hide modal requests, oneliner task results, and menu navigation through the new update loop. | SATISFIED | MainMenu.State owns rows/selection/pending hide/errors; MainMenu.update/3 handles navigation, modal submit, load/create/hide task results. |

No orphaned Phase 35 requirements found: `.planning/REQUIREMENTS.md` maps only SCREEN-01 and SCREEN-02 to Phase 35, and both are claimed by plan frontmatter.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|---|---:|---|---|---|
| `lib/foglet_bbs/tui/screens/main_menu.ex` | 17 | Historical docs mention Phase 0 shells as read-only placeholders | INFO | Not a Phase 35 blocker; unrelated wording, no stub behavior. |
| Target files | - | Empty initial state/default assertions in tests and normal nil checks | INFO | Grep matches are tests/defaults/errors, not user-visible hardcoded stub data. |

### Human Verification Required

None. This phase is a reducer/effect ownership migration with focused automated reducer tests and compile checks. No external service or manual visual acceptance is required for the phase decision.

### Gaps Summary

No Phase 35 goal-blocking gaps found. The migrated auth/home screens own their local state, key handling, task requests, and task results. App is reduced to generic runtime/effect/task/modal routing for these flows.

Current worktree note: full App/layout smoke execution is blocked by BoardList/ThreadList render contract failures introduced by later directory-flow work. That is deferred to Phase 36/SCREEN-03 and was not counted as a Phase 35 gap.

---

_Verified: 2026-04-28T20:50:45Z_
_Verifier: the agent (gsd-verifier)_
