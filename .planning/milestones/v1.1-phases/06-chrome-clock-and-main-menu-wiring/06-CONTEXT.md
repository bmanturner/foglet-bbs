# Phase 06: chrome-clock-and-main-menu-wiring - Context

**Gathered:** 2026-04-24 (assumptions mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

The main-menu chrome renders the authenticated user's current date/time using the Phase 5 preference model, refreshes that display at least once per minute while the user remains on the main menu, and keeps Account, Moderation, and Sysop main-menu navigation aligned with the shared role and policy visibility source of truth. This phase consumes Phase 5 preferences; it does not add preference editing, broaden timestamp conversion across every screen, or add Phase 7 oneliner/social-strip behavior.

</domain>

<decisions>
## Implementation Decisions

### Clock Rendering Placement
- **D-01:** Add the chrome clock in `Foglet.TUI.Widgets.Chrome.StatusBar`, reached through the existing `ScreenFrame.render/4` path, rather than rendering clock text directly inside `Foglet.TUI.Screens.MainMenu`.
- **D-02:** Scope the clock to main-menu chrome behavior so non-main-menu screens keep their existing right-side `@handle` or `guest` status-bar behavior unless planning discovers a lower-risk way to pass explicit chrome options through `ScreenFrame`.
- **D-03:** Preserve the existing left-side status copy, `" Foglet BBS - #{title}"`, and fit the new right-side clock/identity text inside the current 80x24 layout smoke expectations.

### Time Preference Source
- **D-04:** Consume the Phase 5 contract directly: `user.timezone` is the timezone source and `user.preferences["time_format"]` is the 12-hour/24-hour display source.
- **D-05:** Prefer the refreshed live `state.current_user` and `state.session_context` snapshot produced by Phase 5 over adding a new persistence read during status-bar render.
- **D-06:** Default missing timezone to the system timezone with `"Etc/UTC"` as the safe fallback, matching Phase 5's defaulting model; default missing time format to `"12h"`.
- **D-07:** Use the approved Phase 5/Timex timestamp conversion contract and the project date/time convention; do not introduce another date/time dependency.

### Main-Menu Clock Refresh
- **D-08:** Add a dedicated main-menu clock interval in `Foglet.TUI.App.subscribe/1`, separate from the existing 10-second session heartbeat.
- **D-09:** Subscribe to the clock interval only when `state.current_screen == :main_menu` so navigating away from and back to the main menu does not accumulate unrelated off-screen timers.
- **D-10:** Handle the clock-refresh message as a no-op state update that triggers a render without changing navigation, screen state, modal state, or loaded domain data.
- **D-11:** Keep the interval no slower than 60 seconds; the exact tick cadence within that bound is planner discretion.

### Navigation Visibility Consistency
- **D-12:** Keep Account, Moderation, and Sysop menu rendering and key handling delegated to `Foglet.TUI.Screens.ShellVisibility`.
- **D-13:** Do not duplicate role, invite-policy, or operator visibility rules inside `MainMenu`.
- **D-14:** Add regression coverage proving rendered entries, key-bar entries, and accepted key bindings match `ShellVisibility` for regular user, moderator, and sysop roles after current-user/session-context refresh.

### Testing and Determinism
- **D-15:** Clock formatting tests must inject or otherwise control the instant being formatted; tests must not depend on wall-clock time or the machine-local timezone.
- **D-16:** Add focused tests for 24-hour rendering in a known timezone, missing-preference 12-hour fallback, and main-menu-only clock subscription behavior.
- **D-17:** Existing 80x24 layout smoke coverage must continue to pass with the clock text present.

### the agent's Discretion
- Exact date/time string shape, as long as it includes date and time and clearly distinguishes 12-hour vs 24-hour output.
- Exact helper module/function names for formatting the clock. Prefer a small pure helper if that keeps `StatusBar` simple and tests deterministic.
- Whether `StatusBar.render/2` detects the main-menu scope from `state.current_screen`, from the `title`, or from an explicit option threaded through `ScreenFrame`; prefer the least invasive option that keeps behavior clear and testable.
- Exact interval message atom name, as long as it is distinct from `:heartbeat_tick`.

### Folded Todos
None - `gsd-sdk query todo.match-phase 06` returned 0 matches.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase Scope and Requirements
- `.planning/phases/06-chrome-clock-and-main-menu-wiring/06-SPEC.md` - locked Phase 6 requirements, boundaries, constraints, and acceptance criteria.
- `.planning/phases/05-account-preferences-and-live-session-refresh/05-SPEC.md` - upstream preference model: `users.timezone`, `preferences["time_format"]`, Timex validation/conversion, and live session refresh.
- `.planning/ROADMAP.md` - Phase 6 goal, dependencies, and success criteria.
- `.planning/REQUIREMENTS.md` - `MENU-01`, `MENU-02`, and related Account/operations surface requirements.
- `.planning/PROJECT.md` - terminal-first constraints, main-menu personalization goals, and milestone decisions.

### Prior Decisions
- `.planning/phases/00-screen-shells-and-shared-surface-primitives/00-CONTEXT.md` - Account/Moderation/Sysop main-menu entries and shell visibility pattern.
- `.planning/phases/01-authorization-and-scope-backbone/01-CONTEXT.md` - stale `current_user` risks and the distinction between visibility and authorization.
- `.planning/phases/04-shared-invite-surface-activation/04-CONTEXT.md` - `ShellVisibility.invites_visible?/2` as shared policy visibility seam.

### TUI and Codebase Patterns
- `.planning/codebase/ARCHITECTURE.md` - TUI lifecycle, `TUI.App.subscribe/1`, PubSub/custom subscription pattern, and Raxol app ownership.
- `.planning/codebase/CONVENTIONS.md` - module layout, specs, screen/widget conventions, and precommit expectations.
- `.planning/codebase/TESTING.md` - ExUnit, TUI render helper, and deterministic process-test patterns.
- `docs/ARCHITECTURE.md` - system architecture, TUI/session layering, and screen-oriented app model.
- `docs/raxol/README.md` - Raxol documentation entry point.
- `docs/raxol/getting-started/WIDGET_GALLERY.md` - available Raxol layout primitives.
- `lib/foglet_bbs/tui/widgets/README.md` - local themed widget overview.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Foglet.TUI.Widgets.Chrome.ScreenFrame` - existing wrapper for screen chrome; all relevant screens already render through it.
- `Foglet.TUI.Widgets.Chrome.StatusBar` - current top-row widget that owns right-side `@handle` / `guest` text and is the natural clock integration point.
- `Foglet.TUI.Screens.MainMenu` - stateless main-menu screen that already delegates chrome to `ScreenFrame` and menu visibility to `ShellVisibility`.
- `Foglet.TUI.Screens.ShellVisibility` - shared source of truth for Account, Moderation, Sysop, and invite-surface visibility.
- `Foglet.TUI.App.subscribe/1` - existing Raxol subscription hook with `subscribe_interval/2` usage for heartbeat.
- `Foglet.TUI.Theme.from_state/1` - existing theme extraction pattern for chrome/widgets.
- `Foglet.Accounts.User` - current user struct; Phase 5 adds `timezone` while `preferences` already stores JSON presentation flags.

### Established Patterns
- Screens remain pure render/handle modules; `Foglet.TUI.App` owns routing, subscriptions, and lifecycle messages.
- `ScreenFrame` owns the outer frame, status bar, divider, content area, and key bar; individual screens do not hand-roll chrome.
- Session/UI presentation state flows through `state.current_user` and `state.session_context`; widgets should not perform database reads while rendering.
- `ShellVisibility` is rendering/navigation visibility only; domain authorization remains separate.
- Raxol interval subscriptions deliver messages to `update/2`, where no-op state returns can still drive a rerender.

### Integration Points
- `lib/foglet_bbs/tui/widgets/chrome/status_bar.ex` - add clock-aware right-side composition and deterministic formatting seam.
- `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex` - possible integration point if an explicit status-bar option is preferred.
- `lib/foglet_bbs/tui/screens/main_menu.ex` - preserve stateless behavior while adding regression tests for visibility and key bindings.
- `lib/foglet_bbs/tui/app.ex` - add main-menu-only clock interval and clock-refresh handler.
- `test/foglet_bbs/tui/screens/main_menu_test.exs` - extend role visibility/key-binding coverage.
- `test/foglet_bbs/tui/app_test.exs` - extend subscription and clock-refresh update coverage.
- `test/foglet_bbs/tui/layout_smoke_test.exs` - ensure 80x24 smoke rendering remains stable with clock text.

</code_context>

<specifics>
## Specific Ideas

- The clock should feel like chrome/status information, not a new main-menu content row.
- MainMenu should remain stateless; the refresh mechanism belongs in the app lifecycle/subscription layer.
- The right-side status bar may combine identity and time, but must avoid pushing content into the 80-column smoke layout.

</specifics>

<deferred>
## Deferred Ideas

None - analysis stayed within phase scope.

</deferred>

---

*Phase: 06-chrome-clock-and-main-menu-wiring*
*Context gathered: 2026-04-24*
