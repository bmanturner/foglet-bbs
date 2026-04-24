# Phase 06: chrome-clock-and-main-menu-wiring - Discussion Log (Assumptions Mode)

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md - this log preserves the analysis.

**Date:** 2026-04-24
**Phase:** 06-chrome-clock-and-main-menu-wiring
**Mode:** assumptions
**Areas analyzed:** Clock Rendering, Time Preference Source, Main-Menu Clock Refresh, Navigation Visibility Consistency, Testing and Determinism

## Assumptions Presented

### Clock Rendering
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Add the clock in `Foglet.TUI.Widgets.Chrome.StatusBar`, not directly in `MainMenu`, and scope it to main-menu chrome behavior. | Likely | `lib/foglet_bbs/tui/screens/main_menu.ex`; `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex`; `lib/foglet_bbs/tui/widgets/chrome/status_bar.ex`; `.planning/phases/06-chrome-clock-and-main-menu-wiring/06-SPEC.md` |

### Time Preference Source
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Consume Phase 5's `user.timezone` and `user.preferences["time_format"]` model directly, with live `state.current_user` / `state.session_context` as the render source. | Likely | `.planning/phases/05-account-preferences-and-live-session-refresh/05-SPEC.md`; `lib/foglet_bbs/accounts/user.ex`; `lib/foglet_bbs/tui/app.ex` |

### Main-Menu Clock Refresh
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Add a dedicated main-menu clock interval in `Foglet.TUI.App.subscribe/1`, separate from the existing 10-second heartbeat, and handle a no-op clock refresh update. | Likely | `lib/foglet_bbs/tui/app.ex`; `test/foglet_bbs/tui/app_test.exs`; `.planning/phases/06-chrome-clock-and-main-menu-wiring/06-SPEC.md` |

### Navigation Visibility Consistency
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Keep Account, Moderation, and Sysop rendering and key handling delegated to `ShellVisibility`; add regression coverage rather than new role logic. | Confident | `lib/foglet_bbs/tui/screens/main_menu.ex`; `lib/foglet_bbs/tui/screens/shell_visibility.ex`; `test/foglet_bbs/tui/screens/main_menu_test.exs`; `.planning/phases/00-screen-shells-and-shared-surface-primitives/00-CONTEXT.md`; `.planning/phases/04-shared-invite-surface-activation/04-CONTEXT.md` |

### Testing and Determinism
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Clock formatting tests must inject or otherwise control the instant and timezone instead of depending on wall-clock time. | Confident | `.planning/phases/06-chrome-clock-and-main-menu-wiring/06-SPEC.md`; `.planning/codebase/TESTING.md` |

## Corrections Made

No corrections - all assumptions confirmed.
