---
gsd_state_version: 1.0
milestone: v2.0
milestone_name: milestone
status: executing
last_updated: "2026-04-29T04:47:42.198Z"
last_activity: 2026-04-29
progress:
  total_phases: 7
  completed_phases: 4
  total_plans: 23
  completed_plans: 25
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-28)

**Core value:** A user can SSH into a living, reliable BBS and participate in conversations through a terminal-native experience that feels like arriving somewhere.
**Current focus:** Phase 39 — app-shell-simplification

## Current Position

Phase: 39 (app-shell-simplification) — EXECUTING
Plan: 7 of 8
Status: Ready to execute
Last activity: 2026-04-29

## Accumulated Context

### Decisions

- v2.0 is an architecture milestone, not a product feature milestone.
- `Foglet.TUI.App` should become a small runtime shell that owns process/session/runtime concerns.
- Screens should own local state, key handling, async-result handling, and render input through `init/update/render`.
- Screens may request domain work through explicit effects; durable behavior and authorization remain in context modules.
- [Phase 34]: New screen callbacks are optional during phases 34-38 so existing production screens keep compiling until migration.
- [Phase 34]: Foglet.TUI.Effect constructors use precise variant return types for Dialyzer-friendly contracts.
- [Phase 34]: Foglet.TUI.Context rejects unknown fields to enforce the screen-facing boundary.
- [Phase 34]: App stores transition route params separately from current_screen so legacy atom routing remains compatible.
- [Phase 34]: App runtime effect tests register sample screens through session_context.domain.screen_modules rather than production-screen-specific clauses.
- [Phase 34]: Task effect success/failure routing uses {:screen_task_result, screen_key, op, result} through screen update/3.
- [Phase 34]: Stateful screens must own first-class state structs with new/1 or document a local state type.
- [Phase 34]: Stateless screens must explicitly return :stateless or %{} from init/1 and avoid App-owned local storage.
- [Phase 34]: Production screen migrations remain deferred to phases 35-38; Phase 39 removes central App screen-specific machinery.
- [Phase 35]: [Phase 35-02]: Register and Verify keep their map-shaped state modules while exposing the Phase 34 screen contract.
- [Phase 35]: [Phase 35-02]: App no longer owns Register or Verify-specific production delegation clauses; onboarding task results route through generic screen_task_result.
- [Phase 35]: [Phase 35-02]: Register uses session effects for Verify routing, main-menu promotion, and pending-approval termination while App remains the runtime interpreter.
- [Phase 35-auth-home-screens]: MainMenu now uses a first-class State struct for recent oneliners, selection, pending hide target, status, and form errors.
- [Phase 35-auth-home-screens]: MainMenu reducer tests assert local state and Effect values instead of legacy handle_key/2 or App top-level oneliner fields.
- [Phase 35-auth-home-screens]: App still carries transitional oneliner compatibility clauses for Plan 35-04 cleanup, but load results now feed MainMenu screen_state.
- [Phase 35-auth-home-screens]: App no longer carries Phase 35 production local-flow do_update clauses for Login, Register, Verify, or MainMenu/oneliners. — Plan 35-04 cleanup completed auth/home screen-owned update loop migration.
- [Phase 35-auth-home-screens]: MainMenu initial and navigation loads enter through MainMenu.update/3 using the generic screen reducer/effect path. — Keeps App as runtime interpreter while MainMenu owns oneliner loading.
- [Phase 35-auth-home-screens]: Modal form submit routing remains App runtime plumbing but carries only a generic screen key, submit kind, and payload. — Preserves modal precedence without App owning target screen business state.
- [Phase 37-post-composer-flow]: PostReader.State owns routed board/thread identity, loaded posts, status, viewport, render cache, and pending read-pointer flush state. — Plan 37-01 migrated the reader into the screen reducer contract.
- [Phase 37-post-composer-flow]: PostReader App wiring now routes entry loads, task results, active-thread refresh, and thread subscriptions through route/local PostReader state instead of App post/read fields. — Plan 37-02 keeps App as runtime interpreter while PostReader owns reader flow state.
- [Phase 37-post-composer-flow]: Successful submit results navigate to PostReader with load_intent: :jump_last so PostReader owns the reload/jump behavior.
- [Phase 37-post-composer-flow]: PostComposer.State is the canonical owner for reply route identity, draft input, preview mode, validation errors, submission status, and submit results.
- [Phase 37-post-composer-flow]: PostComposer requests reply creation through Effect.task/3 while Foglet.Posts remains authoritative for authorization and durable writes.
- [Phase 37-post-composer-flow]: NewThread.State owns route origin, routed board identity, board-load status, submit status, and submit result data. — Plan 37-04 migrated NewThread to the Phase 34 screen reducer contract.
- [Phase 37-post-composer-flow]: NewThread requests board loads and create-thread writes through Effect.task/3 while Foglet.Boards and Foglet.Threads remain authoritative for durable behavior. — Keeps App as runtime interpreter and contexts as domain authority.
- [Phase 37-post-composer-flow]: Successful new-thread creation navigates to ThreadList with board route params and select_thread_id; ThreadList applies and clears that intent after its own reload. — Preserves new-thread selection without NewThread or App pre-writing ThreadList rows.
- [Phase 38-account-operator-workbenches]: Account, Moderation, and Sysop now expose production init/update/render reducer contracts over Foglet.TUI.Context. — Workbench screens own their local key handling, task results, and render inputs.
- [Phase 38-account-operator-workbenches]: App route-entry dispatch now routes MainMenu, Moderation, and Sysop first-load behavior through generic screen updates. — Removes App-owned workbench task/result clauses while preserving App as runtime/effect interpreter.
- [Phase 38-account-operator-workbenches]: Account preference saves refresh session snapshots through Effect.session({:update_preferences, snapshot}). — Keeps screen reducers effect-oriented while Session remains the live session authority.
- [Phase ?]: [Phase 39-01]: Wave 0 ships fail-loud pin tests tagged @tag :phase39_target excluded from default mix test via test_helper.exs; later waves drop tags as work lands.
- [Phase ?]: [Phase 39-01]: Render baselines for five tracked screens (main_menu, board_list, thread_list, post_reader, account) captured at 80x24 with the same ANSI-strip pipeline Plan 39-08 will use, so byte-equivalence diff is apples-to-apples.
- [Phase ?]: [Phase 39-01]: Pre-existing dialyzer warnings on main HEAD (app.ex:63 ThreadEntry.t/0; board_list.ex:161; sysop.ex:810) are deferred — not introduced by Phase 39 — and tracked in deferred-items.md. The app.ex one will be removed naturally by Plan 39-07 struct-field deletion.
- [Phase ?]: [Phase 39-02]: Declared Foglet.TUI.Screen.subscriptions/2 as an optional callback in the new-contract block (after render/2) with arity ordering local_state-first, Context.t()-second per D-05 — unblocking Plans 39-03 and 39-04 implementers without disturbing the transitional callbacks region (Phase 40 owns that).
- [Phase ?]: [Phase 39-03]: Implemented subscriptions/2 on PostReader (thread topic from State.thread_id or atom/string route_params, [] fallback), ThreadList (board topic with same precedence), and BoardList (unconditional boards aggregate). Stateless screens (Login, Register, Verify, MainMenu, Account, Moderation, Sysop, NewThread, PostComposer) intentionally do not implement the optional callback — proves the @optional_callbacks contract from 39-02 in both directions. Unblocks Plan 39-05's App build_pubsub_topics rewrite by making function_exported?/3 return true for all three target screens.
- [Phase ?]: [Phase 39-04]: Each :on_route_enter clause delegates to the existing :load clause rather than reimplementing load logic — preserves test seams and minimizes diff size for Plan 39-08 byte-equivalence.
- [Phase ?]: [Phase 39-04]: PostReader gets two :on_route_enter clauses (state-first + route_params fallback) mirroring subscriptions/2; ThreadList gets a single unconditional clause matching app.ex:834-836's no-user gate.

### Pending Todos

None yet.

### Blockers/Concerns

- Full migration touches every TUI screen and should be split into verifiable slices.
- Existing user-facing behavior must remain stable while the runtime boundary changes.
