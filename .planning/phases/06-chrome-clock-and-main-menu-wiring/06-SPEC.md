# Phase 6: Chrome Clock and Main Menu Wiring — Specification

**Created:** 2026-04-24
**Ambiguity score:** 0.16 (gate: <= 0.20)
**Requirements:** 4 locked

## Goal

The main-menu screen chrome renders a user-preference-aware current date/time in the top-right chrome and keeps main-menu navigation aligned with the role and policy model.

## Background

The TUI already wraps screens through `Foglet.TUI.Widgets.Chrome.ScreenFrame`, with `Foglet.TUI.Widgets.Chrome.StatusBar` rendering the top row. Today the status bar right side renders only `@handle` or `guest`; no top-right date/time exists. `Foglet.TUI.Screens.MainMenu` is stateless and already exposes Account, Moderation, and Sysop entries through `Foglet.TUI.Screens.ShellVisibility`, which centralizes role and invite-policy visibility decisions. `Foglet.TUI.App.subscribe/1` currently provides a 10-second heartbeat interval when a session PID exists, but it does not provide a main-menu clock refresh. Phase 5 is expected to deliver persisted user timezone and 12h/24h preference data plus live session refresh; this phase consumes that preference model rather than redefining it.

## Requirements

1. **Top-right clock rendering**: Authenticated users see the current date and time in the top-right screen chrome on the main menu.
   - Current: `StatusBar.render/2` displays `@handle` or `guest` on the right and has no clock text.
   - Target: The main-menu chrome right side includes the current date and time formatted from the active user's saved timezone and 12h/24h preference.
   - Acceptance: Rendering the main menu with a user whose preferences specify a known timezone and 24-hour format produces top-right chrome text containing the corresponding local date/time in 24-hour form.

2. **Preference defaults**: Clock rendering falls back to system timezone and 12-hour time when saved user preferences are absent.
   - Current: The user schema has a `preferences` map and `theme` field, but no chrome clock consumer exists.
   - Target: A user without saved timezone or clock-format preference still sees a valid date/time using the system timezone and 12-hour display.
   - Acceptance: Rendering the main menu for a user without clock preferences produces a valid 12-hour timestamp and does not crash or fall back to a blank clock.

3. **Minute refresh**: Main-menu time display refreshes at least once per minute without reconnecting.
   - Current: `Foglet.TUI.App.subscribe/1` subscribes to heartbeat ticks when a session PID is present, but no clock tick is scoped to the main menu.
   - Target: While the current screen is `:main_menu`, the app receives a clock-refresh event at least once every 60 seconds and rerenders without requiring user input or reconnect.
   - Acceptance: A test can move app state to `:main_menu`, deliver the clock-refresh message, and observe that the app accepts it without navigation changes; subscription tests prove the main-menu interval is present and is absent or inactive off the main menu.

4. **Navigation visibility consistency**: Main-menu Account, Moderation, and Sysop entries continue to reflect the current role and policy state through the shared visibility source of truth.
   - Current: `MainMenu.visible_menu_items/1`, `MainMenu.visible_menu_keys/1`, and key handlers call `ShellVisibility` for Account, Moderation, and Sysop role gates.
   - Target: Any Phase 5 session-context refresh that changes user role or policy state is reflected when the main menu renders or handles navigation keys, without duplicating role rules in the menu.
   - Acceptance: Tests cover user, moderator, and sysop roles after session-context/current-user updates and prove rendered menu entries and accepted key bindings match `ShellVisibility` decisions.

## Boundaries

**In scope:**
- Main-menu chrome clock rendering in the shared chrome/status-bar path.
- User timezone and 12h/24h preference consumption from the Phase 5 preference model.
- Default clock behavior for users missing saved timezone or time-format preferences.
- Main-menu-scoped minute refresh wiring in the TUI runtime.
- Regression coverage for Account, Moderation, and Sysop menu visibility and key handling against the shared role/policy predicates.

**Out of scope:**
- Account preference editing UI or persistence changes — Phase 5 owns profile and preference management.
- Introducing new timezone preference keys or validation rules beyond consuming Phase 5's locked model — this phase should not redefine the upstream contract.
- Rendering clocks on every non-main-menu screen — MENU-01 and MENU-02 target the main menu and top-right chrome surfaced there.
- Oneliners, social strip content, or quick posting — Phase 7 owns those main-menu additions.
- Replacing actor-aware authorization with menu visibility checks — navigation visibility remains separate from domain authorization.

## Constraints

- Date/time rendering must use the project's approved time contract from Phase 5 and the standard project convention for date/time work; no new date/time dependency is introduced in this phase.
- Clock tests must avoid machine-local-time flakiness by injecting or controlling the instant and timezone used for formatting.
- The minute refresh must not accumulate duplicate per-screen timers as users navigate away from and back to the main menu.
- Existing 80x24 layout smoke coverage must continue to pass with the clock text present.

## Acceptance Criteria

- [ ] Main-menu top-right chrome includes current date/time for authenticated users.
- [ ] Clock output honors saved timezone preference from the Phase 5 user preference model.
- [ ] Clock output honors saved 12-hour versus 24-hour preference from the Phase 5 user preference model.
- [ ] Users without saved clock preferences see a valid system-timezone, 12-hour clock.
- [ ] The main-menu clock refreshes at least once per minute without reconnecting.
- [ ] Account, Moderation, and Sysop menu entries and key bindings remain consistent with `ShellVisibility` for user, moderator, and sysop roles.
- [ ] Existing main-menu and layout smoke tests pass with the added clock text.

## Ambiguity Report

| Dimension           | Score | Min   | Status | Notes |
|---------------------|-------|-------|--------|-------|
| Goal Clarity        | 0.90  | 0.75  | met    | MENU-01 and MENU-02 define the visible outcome. |
| Boundary Clarity    | 0.84  | 0.70  | met    | Explicitly consumes Phase 5 preferences and excludes Account editing and oneliners. |
| Constraint Clarity  | 0.74  | 0.65  | met    | Time dependency, layout, timer, and test-flakiness constraints are stated. |
| Acceptance Criteria | 0.78  | 0.70  | met    | Pass/fail checks cover rendering, defaults, refresh, and navigation visibility. |
| **Ambiguity**       | 0.16  | <=0.20| met    | Weighted clarity passes the spec gate. |

Status: met = meets minimum, below = below minimum (planner treats as assumption)

## Interview Log

| Round | Perspective | Question summary | Decision locked |
|-------|-------------|------------------|-----------------|
| 1 | Researcher | What exists today for chrome and main-menu wiring? | `ScreenFrame`/`StatusBar` exist, main menu is stateless, and `ShellVisibility` already owns role-gated entries; no clock exists. |
| 2 | Researcher + Simplifier | What is the smallest deliverable that satisfies MENU-01 and MENU-02? | Add main-menu chrome clock rendering plus main-menu-scoped minute refresh; do not expand into Account editing or oneliners. |
| 3 | Boundary Keeper | What adjacent work must not be pulled into this phase? | Phase 5 owns preference persistence; Phase 7 owns oneliners; authorization remains domain-owned, not menu-owned. |
| 4 | Failure Analyst | What would cause a verifier to reject the output? | Wrong timezone or 12h/24h format, missing fallback defaults, reconnect-required refresh, duplicated role rules, or broken 80x24 layout. |

---

*Phase: 06-chrome-clock-and-main-menu-wiring*
*Spec created: 2026-04-24*
*Next step: $gsd-discuss-phase 6 — implementation decisions (how to build what's specified above)*
