# Phase 40: Verification & Documentation - Context

**Gathered:** 2026-04-29 (assumptions mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 40 is the v2.0 close gate for the TUI runtime migration. It consumes Phase
39 deferred artifacts, closes or explicitly excludes carried-forward cleanup,
proves the migrated `Context`/`Effect`/screen-callback architecture with focused
tests and final gates, and leaves concise documentation for future screen work.

It does not add BBS product capabilities, browser workflows, a new routing
architecture, per-screen processes, broad visual redesign, or a whole-suite test
hygiene rewrite. The Phase 40 SPEC is locked and supplies the requirements and
acceptance criteria.
</domain>

<decisions>
## Implementation Decisions

### Deferred Cleanup Register
- **D-01:** Begin by inventorying every Phase 39 carry-forward item from
  `deferred-items.md`, `39-SUMMARY.md`, and `39-REVIEW-FIX.md`; each item must
  end Phase 40 as fixed, intentionally excluded, or still blocking with clear
  evidence.
- **D-02:** Treat the two Account/MainMenu doomed-submit failures and the two
  remaining Dialyzer warnings as in-scope close-gate work, not optional polish.

### Legacy Callback Cleanup
- **D-03:** Remove or bound production dependence on the transitional screen
  callbacks `render/1`, `handle_key/2`, and `init_screen_state/1` after tests
  and fixtures are moved to `init/1`, `update/3`, and `render/2`.
- **D-04:** Do not sweep nested helper modules into the legacy-callback cleanup
  just because they expose local `handle_key/2` functions; the target is the
  production `Foglet.TUI.Screen` behavior boundary and App fallback dispatch.

### Modal Failure Fix
- **D-05:** Fix the doomed-submit failures by preserving/replaying
  `Modal.Form.submit_state` or explicitly transitioning the modal form to
  `{:error, _}` on async failure; do not delete the behavioral checks or loosen
  them into text-presence assertions.

### Breadcrumb Completion
- **D-06:** Remaining production screens should emit explicit
  `breadcrumb_parts`; retaining `["Foglet"]` is acceptable only when that exact
  breadcrumb is intended and actively tested.

### Verification Strategy
- **D-07:** Build a coverage inventory across auth/home, board/thread,
  post/composer, account, moderation, and sysop families, then fill only the
  reducer/effect, route-entry, and App-shell gaps that the inventory exposes.
- **D-08:** Prefer behavior-level assertions over source-string greps and
  arbitrary rendered-text presence checks. Static checks are acceptable only
  when they guard an architectural invariant and are paired with stronger
  behavior coverage or a documented follow-up.
- **D-09:** Render smoke is a required close-gate evidence item because the SPEC
  says so, but keep it lightweight: use the existing render smoke patterns and
  `rtk mix foglet.tui.render` to produce the minimum useful evidence rather than
  building an expansive terminal-size campaign.

### Documentation
- **D-10:** Write the screen-contract guidance as a TUI-adjacent developer doc
  and link it from `lib/foglet_bbs/tui/widgets/README.md` or the nearest TUI
  README surface. The doc should include practical examples for state ownership,
  effects, tasks, route params, PubSub subscriptions, modal requests, and
  rendering.

### the agent's Discretion
Planners may choose the exact plan slicing and test files, but should preserve
the close-gate shape: clean deferred items first, then remove/bound legacy
surface, fill proof gaps, update docs, run `rtk mix test`, render checks, and
`rtk mix precommit`.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

- `.planning/phases/40-verification-documentation/40-SPEC.md`
- `.planning/ROADMAP.md`
- `.planning/REQUIREMENTS.md`
- `.planning/PROJECT.md`
- `.planning/phases/39-app-shell-simplification/39-SUMMARY.md`
- `.planning/phases/39-app-shell-simplification/deferred-items.md`
- `.planning/phases/39-app-shell-simplification/39-REVIEW-FIX.md`
- `.planning/phases/39-app-shell-simplification/39-CONTEXT.md`
- `.planning/codebase/TESTING.md`
- `.planning/codebase/CONVENTIONS.md`
- `.planning/codebase/ARCHITECTURE.md`
- `lib/foglet_bbs/tui/screen.ex`
- `lib/foglet_bbs/tui/app.ex`
- `lib/foglet_bbs/tui/screens/main_menu.ex`
- `lib/foglet_bbs/tui/screens/board_list.ex`
- `lib/foglet_bbs/tui/screens/sysop.ex`
- `lib/foglet_bbs/tui/widgets/modal/form.ex`
- `lib/foglet_bbs/tui/widgets/modal/form/submit_stash.ex`
- `lib/foglet_bbs/tui/widgets/README.md`
- `test/foglet_bbs/tui/app_runtime_contract_test.exs`
- `test/foglet_bbs/tui/app_struct_test.exs`
- `test/foglet_bbs/tui/app_test.exs`
- `test/foglet_bbs/tui/layout_smoke_test.exs`
- `test/foglet_bbs/tui/screens/account_test.exs`
- `test/foglet_bbs/tui/widgets/chrome/breadcrumb_migration_test.exs`
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Foglet.TUI.App.apply_effect/2`, `apply_effects/2`,
  `route_screen_update/3`, `init_route_screen_state/3`, and
  `context_for_screen_key/2` are the runtime shell seams to test and preserve.
- `Foglet.TUI.Screen` already declares the new `init/1`, `update/3`,
  `render/2`, and optional `subscriptions/2` callbacks, but still includes
  transitional callback declarations.
- `test/foglet_bbs/tui/app_runtime_contract_test.exs`,
  `app_struct_test.exs`, and `app_test.exs` already provide App-shell testing
  patterns for generic effect interpretation, screen-state storage, route
  entry, task routing, PubSub delegation, modal precedence, and struct shape.
- Screen-family tests already exist under `test/foglet_bbs/tui/screens/`; Phase
  40 should inventory and fill gaps rather than duplicate coverage.
- `test/foglet_bbs/tui/layout_smoke_test.exs`, render snapshots, and
  `rtk mix foglet.tui.render` provide existing render verification machinery.

### Established Patterns
- Screen reducers own local state transitions and emit `Foglet.TUI.Effect`
  values; App interprets effects generically.
- Task effects return `{:screen_task_result, screen_key, op, result}` and route
  back through the owning screen's `update/3`.
- Route entry is a generic `:on_route_enter` message sent to the active screen.
- PubSub topics are App-owned only for user-level topics; screen-specific topics
  come from optional `subscriptions/2`.
- Modal and SizeGate precedence remain App-owned runtime concerns, but modal
  submits should re-enter screen reducers through generic routing.
- Tests should assert state, effects, task results, route params, and layout
  contracts before falling back to rendered text.

### Integration Points
- `lib/foglet_bbs/tui/screen.ex` is the cleanup target for transitional callback
  declarations and stale module documentation.
- `lib/foglet_bbs/tui/app.ex` contains the remaining legacy fallback paths:
  `handle_key/2` dispatch fallback, `render/1` fallback, and
  `process_screen_commands/2` legacy command adapter.
- `lib/foglet_bbs/tui/screens/main_menu.ex` rebuilds oneliner modal forms on
  async error and currently needs to satisfy the `Modal.Form` submit-state
  consumer obligation.
- `lib/foglet_bbs/tui/screens/board_list.ex:161` and
  `lib/foglet_bbs/tui/screens/sysop.ex:823` correspond to the remaining
  deferred Dialyzer warnings.
- `test/foglet_bbs/tui/layout_smoke_test.exs` still carries
  `:phase39_login_breadcrumb_pending` markers for breadcrumb follow-up.
</code_context>

<specifics>
## Specific Ideas

- User note during assumption confirmation: targeted render smoke at multiple
  terminal sizes is not personally important. Treat the SPEC-mandated render
  evidence as a lean close-gate proof, not a large bespoke testing effort.
- The Account/MainMenu modal fix should preserve the useful failure semantics:
  doomed submits leave the form recoverable and Escape can dismiss after the
  error path.
- Breadcrumb work should finish explicit screen-owned `breadcrumb_parts`, not
  resurrect `BreadcrumbBar.parts_for/1` pattern matching.
</specifics>

<deferred>
## Deferred Ideas

None — analysis stayed within Phase 40 close-gate scope.
</deferred>
