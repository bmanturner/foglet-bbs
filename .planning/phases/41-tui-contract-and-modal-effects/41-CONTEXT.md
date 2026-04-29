# Phase 41: TUI Contract And Modal Effects - Context

**Gathered:** 2026-04-29 (assumptions mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 41 retires the remaining legacy TUI screen compatibility surface and replaces hidden modal-submit process-dictionary handoffs with an explicit effect path. The phase is limited to the canonical screen contract, modal-submit routing, test/smoke-helper migration, direct round-trip coverage, and `SCREEN_CONTRACT.md` cleanup.

Locked requirements come from `41-SPEC.md`: `Foglet.TUI.Screen` exposes only `init/1`, `update/3`, `render/2`, and optional `subscriptions/2`; production screens stop exposing public `render/1`, `handle_key/2`, and `init_screen_state/1` compatibility helpers; tests and smoke helpers stop depending on screen-level `init_screen_state/1`; modal submits route through `Foglet.TUI.Effect`; modal-submit process-dictionary handoffs are removed; and direct App-shell tests prove success and visible failure paths.
</domain>

<decisions>
## Implementation Decisions

### Screen Contract Cleanup
- **D-01:** Remove `render/1`, `handle_key/2`, and `init_screen_state/1` from `Foglet.TUI.Screen` as behavior and optional callbacks. Do not preserve a public compatibility behavior surface.
- **D-02:** Remove public production-screen compatibility helpers that implement the old screen callbacks. Where setup is still useful, move it to explicit state constructors such as `State.new/1`, private helpers, or canonical `init/1` with a `Foglet.TUI.Context`.
- **D-03:** Migrate screen tests, render fixtures, and layout smoke helpers to construct state through `init/1`, App route initialization, or first-class state constructors. Do not keep direct test dependencies on screen-level `init_screen_state/1`.

### Modal Submit Effects
- **D-04:** Add a first-class modal-submit effect to `Foglet.TUI.Effect`, using a typed constructor that carries the target screen key, submit kind, and payload.
- **D-05:** Preserve the target screen reducer boundary shape as `{:modal_submit, kind, payload}`. The new effect path changes routing mechanics, not screen reducer semantics.
- **D-06:** Make `Modal.Form` submit callbacks return or emit explicit effect data rather than relying on process dictionary side channels. App interprets the modal-submit effect and routes it to the target screen with `route_screen_update/3`.
- **D-07:** Replace all modal-submit process-dictionary handoffs in scope: App's `pending_screen_modal_submit`, `Modal.Form.SubmitStash`, Account profile/prefs form submit stashes, Sysop site form submit stash, and `Sysop.BoardsView` `pending_submit`. Delete `SubmitStash` and its tests if no production or relevant test code references it after migration.

### Coverage And Failure Behavior
- **D-08:** Add direct App-shell modal-submit round-trip coverage from `Modal.Form.handle_event/2` through App effect interpretation to the target screen reducer.
- **D-09:** Cover missing or invalid modal-submit targets with a visible failure path. A submit that silently does nothing is not acceptable behavior.
- **D-10:** Existing unrelated `Process.put/get` test fakes may remain when they are not modal-submit routing mechanisms. The grep acceptance should distinguish unrelated test dependency stubs from modal-submit payload handoffs.

### the agent's Discretion
- Downstream agents may choose the exact effect type/payload naming, but it should fit existing `%Foglet.TUI.Effect{type, payload}` conventions and be easy to grep.
- Downstream agents may choose whether `Modal.Form.handle_event/2` returns effects directly or preserves its action tuple with effect metadata, provided the submit payload stays explicit all the way back to App or the owning screen.

### Folded Todos
No matching todos were folded into this phase.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

- `.planning/phases/41-tui-contract-and-modal-effects/41-SPEC.md`
- `.planning/ROADMAP.md`
- `.planning/REQUIREMENTS.md`
- `.planning/PROJECT.md`
- `.planning/codebase/CONCERNS.md`
- `lib/foglet_bbs/tui/SCREEN_CONTRACT.md`
- `lib/foglet_bbs/tui/screen.ex`
- `lib/foglet_bbs/tui/effect.ex`
- `lib/foglet_bbs/tui/app.ex`
- `lib/foglet_bbs/tui/widgets/modal/form.ex`
- `lib/foglet_bbs/tui/widgets/modal/form/submit_stash.ex`
- `lib/foglet_bbs/tui/screens/main_menu.ex`
- `lib/foglet_bbs/tui/screens/account/state.ex`
- `lib/foglet_bbs/tui/screens/account/profile_form.ex`
- `lib/foglet_bbs/tui/screens/account/prefs_form.ex`
- `lib/foglet_bbs/tui/screens/sysop/site_form.ex`
- `lib/foglet_bbs/tui/screens/sysop/site_form/state.ex`
- `lib/foglet_bbs/tui/screens/sysop/boards_view.ex`
- `test/foglet_bbs/tui/app_test.exs`
- `test/foglet_bbs/tui/effect_test.exs`
- `test/foglet_bbs/tui/layout_smoke_test.exs`
- `test/foglet_bbs/tui/widgets/modal/form_test.exs`
- `test/foglet_bbs/tui/widgets/modal/form/submit_stash_test.exs`
- `docs/raxol/getting-started/WIDGET_GALLERY.md`
- `lib/foglet_bbs/tui/widgets/README.md`
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Foglet.TUI.Context` is the existing narrow screen-facing runtime context and should be used by migrated tests and fixtures.
- `Foglet.TUI.Effect` already models navigation, task, modal open/dismiss, publish, session, terminal, and quit requests as `%Effect{type, payload}` values.
- `Foglet.TUI.App.apply_effect/2` and `route_screen_update/3` are the existing places to interpret effects and deliver normalized messages to screen reducers.
- `Modal.Form.handle_event/2` already returns `{new_form, action}` and calls `on_submit` exactly once when the last focused field receives Enter.

### Established Patterns
- Production screen state is already owned by screen modules and stored in App by screen key; App routes messages to `screen.update(message, local_state, context)`.
- App rendering already prefers `render/2`; missing `render/2` currently falls back to a bounded empty view with a warning rather than calling `render/1`.
- Task effects return to screens as `{:task_result, op, result}`; modal-submit effects should mirror this explicit routing style and arrive at target reducers as `{:modal_submit, kind, payload}`.
- Widget stateful contracts use `init/1`, `handle_event/2`, and `render/2`; this supports keeping `Modal.Form` stateful while making its submit result explicit.

### Integration Points
- `Foglet.TUI.Screen` behavior cleanup affects all production screen modules still exposing compatibility callbacks.
- `Foglet.TUI.App.handle_modal_key/3` is the central App-shell modal event boundary for form modals.
- `Foglet.TUI.Widgets.Modal.Form.handle_event/2` is the submit/cancel action boundary.
- `MainMenu`, Account profile/prefs forms, Sysop site form, and Sysop boards view are current modal-submit handoff consumers.
- `app_test.exs`, screen tests, render fixtures, and `layout_smoke_test.exs` carry many old `init_screen_state/1` dependencies that planning should handle deliberately.
</code_context>

<specifics>
## Specific Ideas

- Prefer a grep-verifiable cleanup: no old callback declarations in `Foglet.TUI.Screen`, no public production-screen old callback helpers, no `init_screen_state` references in TUI tests or `SCREEN_CONTRACT.md`, and no modal-submit process-dictionary keys in production code.
- Preserve existing user-facing modal behavior while changing the route from hidden process state to explicit effects.
- Visible failure can be an App-owned error modal or another existing TUI-visible failure mechanism, but it must not be silent.
</specifics>

<deferred>
## Deferred Ideas

None - analysis stayed within phase scope.

### Reviewed Todos (not folded)
No matching todos were found for this phase.
</deferred>
