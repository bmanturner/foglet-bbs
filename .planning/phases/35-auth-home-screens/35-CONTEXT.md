# Phase 35: Auth & Home Screens - Context

**Gathered:** 2026-04-28 (assumptions mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Login, Register, Verify, and MainMenu/oneliners move to screen-owned
`init/1`, `update/3`, and `render/2` flows over screen-local state plus
`Foglet.TUI.Context`. This phase preserves existing auth/home behavior while
removing Phase 35 local-flow ownership from `Foglet.TUI.App`. It does not
migrate board/thread/post/account/operator screens, remove every remaining
legacy App clause, redesign the TUI, change durable auth/oneliner domain
behavior, or add browser-facing product workflows.
</domain>

<spec_lock>
## Specification Lock

`.planning/phases/35-auth-home-screens/35-SPEC.md` locks 7 requirements and
the phase boundaries. Downstream agents MUST read it before planning. Do not
duplicate or reinterpret the requirements from memory; use the SPEC as the
source of truth for what must be delivered and what remains out of scope.
</spec_lock>

<decisions>
## Implementation Decisions

### Login Migration
- **D-01:** `Foglet.TUI.Screens.Login` should keep its existing map-shaped
  `Foglet.TUI.Screens.Login.State` for this phase, but expose `init/1`,
  `update/3`, and `render/2` around that local map instead of App-shaped state.
- **D-02:** Login task submission should use the Phase 34 task effect path,
  returning success/failure through `{:screen_task_result, :login, :login,
  result}` and consuming it as `{:task_result, :login, result}` inside
  `Login.update/3`.
- **D-03:** Existing login/reset behavior is preservation work, not redesign:
  menu/form/reset-token subflows, invalid credentials, pending/rejected/
  suspended modals, verification routing, no-email reset honesty, and reset
  token consumption should keep their current user-facing behavior.

### Register And Verify Migration
- **D-04:** `Register` and `Verify` should preserve current wizard/code-entry
  semantics and migrate event handling directly into reducer messages rather
  than through App-specific hooks.
- **D-05:** `{:register_wizard, event}` becomes Register-local reducer input;
  `{:verify_event, event}` becomes Verify-local reducer input. App should not
  retain production-specific delegation clauses for these events.
- **D-06:** Domain work for registration, verification delivery, verification
  submit, and resend remains in `Foglet.Accounts` and
  `Foglet.Accounts.Verification`; screens request work via effects and consume
  results through the owning screen update loop.

### MainMenu Oneliner Ownership
- **D-07:** `Foglet.TUI.Screens.MainMenu` becomes stateful in this phase.
- **D-08:** Add a first-class MainMenu local state module, expected at
  `lib/foglet_bbs/tui/screens/main_menu/state.ex`, owning recent oneliners,
  selected oneliner index, pending hide target, and any local load/create/hide
  lifecycle fields needed for reducer tests.
- **D-09:** App top-level fields `recent_oneliners`,
  `selected_oneliner_index`, and `pending_hide_oneliner_id` should no longer be
  the source of truth for MainMenu oneliner behavior after this phase.
- **D-10:** MainMenu keeps existing visible-action gating and role-aware
  hide-oneliner behavior; menu/oneliner visuals are not redesigned.

### Modal And Form Submission Boundary
- **D-11:** App remains the generic runtime/modal interpreter, but MainMenu
  owns the decisions to open the oneliner composer, submit oneliners, open hide
  confirmation/forms, submit hide requests, and handle create/hide results.
- **D-12:** Retire App process-dictionary stash helpers for oneliner form
  submission if the modal callback can emit a generic screen event or effect
  cleanly. If a small bridge remains necessary, it must be generic runtime
  plumbing and documented as not owning MainMenu business state.
- **D-13:** Modal precedence, SizeGate behavior, session routing, quit, and
  command dispatch remain App/runtime responsibilities.

### Testing Strategy
- **D-14:** Rewrite focused auth/home tests toward `init/1` and `update/3`
  reducer/effect assertions instead of legacy `handle_key/2`,
  `handle_login_result/2`, `handle_wizard_event/2`, or App-owned local fields.
- **D-15:** App tests should prove generic task/effect routing and the absence
  of Phase 35 local-flow clauses, not reassert the old screen-specific App
  behavior.
- **D-16:** Preserve existing behavioral edge cases in tests: session
  promotion, pending approval termination, modal precedence, Ctrl+C/quit,
  no-email reset honesty, verification delivery failures, oneliner
  composer/hide behavior, and role/action visibility.
- **D-17:** Avoid brittle tests that only assert text presence. Use state,
  effects, domain-result handling, and render smoke/layout contracts where
  appropriate.

### the agent's Discretion
- Exact reducer message names are flexible if they are screen-owned and do not
  require production-specific App clauses.
- Exact MainMenu state struct field names are flexible if the state owns all
  oneliner list, selection, pending hide, and task-result lifecycle concerns.
- The migration may keep map-shaped local state for Login/Register/Verify
  during this phase if converting to structs would add risk without improving
  the ownership boundary.

### Folded Todos
None.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Locked Phase Scope
- `.planning/phases/35-auth-home-screens/35-SPEC.md` - Locked Phase 35
  requirements, boundaries, constraints, and acceptance criteria.
- `.planning/ROADMAP.md` - v2.0 phase sequencing, Phase 35 goal, and
  cross-cutting constraints.
- `.planning/PROJECT.md` - SSH-first product boundary and v2.0 milestone
  intent.
- `.planning/REQUIREMENTS.md` - v2.0 screen ownership requirements and Phase
  35 requirement mapping.

### Runtime Foundation
- `.planning/phases/34-runtime-contract-effects/34-CONTEXT.md` - Prior locked
  decisions for `Foglet.TUI.Context`, `Foglet.TUI.Effect`, task routing,
  screen-state conventions, and migration boundaries.
- `.planning/phases/34-runtime-contract-effects/34-SPEC.md` - Phase 34
  foundation requirements that Phase 35 builds on.
- `lib/foglet_bbs/tui/screen.ex` - New screen behavior contract and
  transitional legacy callbacks.
- `lib/foglet_bbs/tui/context.ex` - Narrow screen-facing runtime context.
- `lib/foglet_bbs/tui/effect.ex` - Explicit effect constructors and task
  effect shape.
- `lib/foglet_bbs/tui/app.ex` - App runtime shell, generic effect
  interpretation, legacy Phase 35 clauses to migrate away from, and task-result
  routing.

### Target Screens
- `lib/foglet_bbs/tui/screens/login.ex` - Current Login render/key/result
  behavior and reset/auth logic.
- `lib/foglet_bbs/tui/screens/login/state.ex` - Current Login local state
  shape.
- `lib/foglet_bbs/tui/screens/register.ex` - Current Register wizard behavior
  and legacy `handle_wizard_event/2` hook.
- `lib/foglet_bbs/tui/screens/register/state.ex` - Current Register local
  state shape.
- `lib/foglet_bbs/tui/screens/verify.ex` - Current Verify code-entry,
  submit, resend, and cooldown behavior.
- `lib/foglet_bbs/tui/screens/verify/state.ex` - Current Verify local state
  shape.
- `lib/foglet_bbs/tui/screens/main_menu.ex` - Current MainMenu destinations,
  visible actions, oneliner rendering, and legacy App-shaped state access.

### Tests And Codebase Maps
- `test/foglet_bbs/tui/screens/login_test.exs` - Existing auth/reset behavior
  coverage to migrate to reducer/effect assertions.
- `test/foglet_bbs/tui/screens/register_test.exs` - Existing registration
  wizard and delivery coverage.
- `test/foglet_bbs/tui/screens/verify_test.exs` - Existing verification
  submit/resend/cooldown coverage.
- `test/foglet_bbs/tui/screens/main_menu_test.exs` - Existing MainMenu and
  oneliner behavior coverage to move off App-owned fields.
- `test/foglet_bbs/tui/app_test.exs` - Existing App runtime tests and legacy
  auth/home clauses to update.
- `.planning/codebase/CONVENTIONS.md` - Elixir module, state, docs, specs, and
  precommit conventions.
- `.planning/codebase/STRUCTURE.md` - Source/test layout and state-module
  placement conventions.
- `.planning/codebase/TESTING.md` - ExUnit, TUI, and render smoke testing
  patterns.
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Foglet.TUI.Screen` already defines `init/1`, `update/3`, and `render/2`
  while retaining transitional legacy callbacks.
- `Foglet.TUI.Context` already exposes the narrow screen-facing data needed by
  migrated reducers: current user, session context, session pid, terminal size,
  route, route params, and domain overrides.
- `Foglet.TUI.Effect.task/3` and `Foglet.TUI.App.apply_effect/2` already route
  task success/failure into `{:screen_task_result, screen_key, op, result}`.
- Existing `Login.State`, `Register.State`, and `Verify.State` modules provide
  most of the local data shapes needed for reducer migration.
- MainMenu has no state module yet; adding one follows the established
  `screens/<screen>/state.ex` convention.

### Established Patterns
- TUI screen tests mirror screen modules under `test/foglet_bbs/tui/screens/`.
- Existing reducer/state tests should assert data and effects directly, not
  parse rendered text as the primary behavior proof.
- Domain side effects stay in contexts and verification modules; screens are
  responsible for requesting work and presenting outcomes.
- App owns runtime concerns: modal precedence, terminal/SizeGate handling,
  process/session coordination, generic effect interpretation, and command
  dispatch.

### Integration Points
- `lib/foglet_bbs/tui/app.ex` currently contains the Phase 35 local-flow
  handlers to remove or reduce to generic routing: `{:login_result, _}`,
  `{:task_error, :login, _}`, `{:register_wizard, _}`, `{:verify_event, _}`,
  `{:load_oneliners}`, `{:oneliners_loaded, _}`,
  `{:open_oneliner_composer}`, `{:submit_oneliner, _}`,
  `{:oneliner_created, _}`, `{:open_hide_oneliner_modal, _}`,
  `{:submit_hide_oneliner, _}`, and `{:oneliner_hidden, _}`.
- `App.route_screen_update/3` is the generic hook for migrated screens to
  receive key/task/update messages.
- `App.init_route_screen_state/3`, `App.context_for_screen_key/2`, and
  `App.apply_effects/2` are the likely runtime helpers planners should reuse
  rather than inventing a parallel dispatch path.
</code_context>

<specifics>
## Specific Ideas

- User confirmed the assumptions-mode pass without corrections.
- No visual redesign, new auth features, or browser workflows were added during
  discussion.
- No external research is required; the relevant runtime behavior is local in
  Phase 34 artifacts and the vendored Raxol/Foglet codebase.
</specifics>

<deferred>
## Deferred Ideas

None - analysis stayed within phase scope.
</deferred>

---

*Phase: 35-auth-home-screens*
*Context gathered: 2026-04-28*
