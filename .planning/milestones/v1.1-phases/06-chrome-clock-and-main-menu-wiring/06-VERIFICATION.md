---
phase: 06-chrome-clock-and-main-menu-wiring
verified: 2026-04-24T14:09:43Z
status: gaps_found
score: 5/8 must-haves verified
overrides_applied: 0
gaps:
  - truth: "User sees current date and time in top-right chrome rendered in saved timezone and 12h/24h preference."
    status: failed
    reason: "ClockFormatter returns time-only strings, and the current tests explicitly reject the required date text."
    artifacts:
      - path: "lib/foglet_bbs/tui/widgets/chrome/clock_formatter.ex"
        issue: "format_local/2 uses %H:%M and %I:%M %p only; no date component is rendered."
      - path: "test/foglet_bbs/tui/widgets/chrome/status_bar_test.exs"
        issue: "Tests assert refute rendered =~ \"2026-04-24\", so they protect the opposite of MENU-01's date requirement."
    missing:
      - "Include the current date in the chrome clock text, e.g. YYYY-MM-DD HH:MM or YYYY-MM-DD hh:MM AM/PM."
      - "Update deterministic clock/status-bar tests to require date plus time instead of time only."
  - truth: "Non-main-menu chrome still renders the existing right-side identity text without a clock."
    status: failed
    reason: "StatusBar renders the clock for every authenticated screen, not just the main menu, despite Plan 06-02 and Phase 6 validation requiring non-main-menu identity-only behavior."
    artifacts:
      - path: "lib/foglet_bbs/tui/widgets/chrome/status_bar.ex"
        issue: "right_text/1 matches any authenticated current_user and always calls ClockFormatter.format/2."
      - path: "test/foglet_bbs/tui/widgets/chrome/status_bar_test.exs"
        issue: "Test was changed to assert non-main-menu screens also show the time-only clock."
    missing:
      - "Gate clock rendering on current_screen == :main_menu if the Phase 6 main-menu-only scope remains authoritative."
      - "Restore non-main-menu regression coverage for '@handle ' without clock text."
  - truth: "Off-main-menu screens do not subscribe to the main-menu clock tick."
    status: failed
    reason: "App.subscribe/1 adds :main_menu_clock_tick for any authenticated user, regardless of current_screen."
    artifacts:
      - path: "lib/foglet_bbs/tui/app.ex"
        issue: "Clock subscription condition is if state.current_user, not if state.current_screen == :main_menu."
      - path: "test/foglet_bbs/tui/app_test.exs"
        issue: "Test now asserts non-main-menu screens also add the main-menu clock interval, contradicting Plan 06-03 and 06-VALIDATION."
    missing:
      - "Scope subscribe_interval(60_000, :main_menu_clock_tick) to current_screen == :main_menu."
      - "Restore off-main-menu test coverage that rejects :main_menu_clock_tick."
---

# Phase 6: Chrome Clock and Main Menu Wiring Verification Report

**Phase Goal:** Wire the top-right chrome clock and main-menu navigation to the new preference and role model.  
**Verified:** 2026-04-24T14:09:43Z  
**Status:** gaps_found  
**Re-verification:** No - initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | User sees current date and time in top-right chrome rendered in saved timezone and 12h/24h preference, defaulting to system timezone and 12-hour time when no preference has been saved. | FAILED | `ClockFormatter.format/2` converts timezone and honors 12h/24h, but only returns `13:05` or `12:05 AM` (`clock_formatter.ex:65-70`). `status_bar_test.exs:81-83` explicitly refutes `2026-04-24`. |
| 2 | Main-menu time display refreshes at least once per minute without reconnect. | VERIFIED | `App.subscribe/1` emits `subscribe_interval(60_000, :main_menu_clock_tick)` for authenticated states (`app.ex:206-208`), and `do_update(:main_menu_clock_tick, state)` returns `{state, []}` (`app.ex:784`). |
| 3 | Main-menu navigation exposes Account, Moderation, and Sysop according to current role and policy state. | VERIFIED | `MainMenu` renders and handles A/M/S through `ShellVisibility` (`main_menu.ex:115-150`, `main_menu.ex:157-169`); regression tests derive expected behavior from `ShellVisibility` (`main_menu_test.exs:365-392`). |
| 4 | Missing or invalid timezone/time-format data falls back without crashing. | VERIFIED | `valid_timezone/1` and `valid_time_format/1` fall back safely (`clock_formatter.ex:41-54`), and tests cover invalid/missing data (`status_bar_test.exs:49-67`). |
| 5 | Non-main-menu chrome still renders existing right-side identity text without a clock. | FAILED | `StatusBar.right_text/1` always formats a clock for authenticated users (`status_bar.ex:56-58`); tests now assert non-main-menu screens also show clock text (`status_bar_test.exs:101-112`). |
| 6 | The main menu receives a dedicated clock tick at least once per minute. | VERIFIED | The tick is dedicated and separate from heartbeat (`app.ex:199-208`, `app.ex:776-784`). |
| 7 | Off-main-menu screens do not subscribe to the main-menu clock tick. | FAILED | Subscription condition is `if state.current_user`, not current screen (`app.ex:206-208`); test asserts the off-main-menu subscription exists (`app_test.exs:848-865`). |
| 8 | ROADMAP Phase 6 lists all created plans. | VERIFIED | `roadmap.get-phase 6` reports 4 plan entries: 06-01 through 06-04. |

**Score:** 5/8 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `lib/foglet_bbs/tui/widgets/chrome/clock_formatter.ex` | Pure deterministic formatter | PARTIAL | Exists and is wired, but omits the date required by MENU-01. |
| `lib/foglet_bbs/tui/widgets/chrome/status_bar.ex` | Chrome clock integration | PARTIAL | Exists and calls `ClockFormatter`, but renders the clock on all authenticated screens and not only main menu as planned. |
| `lib/foglet_bbs/tui/app.ex` | Main-menu clock subscription and no-op tick | PARTIAL | Tick handler is correct; subscription is not main-menu-scoped. |
| `lib/foglet_bbs/tui/screens/main_menu.ex` | ShellVisibility-backed navigation | VERIFIED | Render and key handling delegate A/M/S visibility decisions to `ShellVisibility`. |
| `test/foglet_bbs/tui/widgets/chrome/status_bar_test.exs` | Deterministic chrome clock coverage | PARTIAL | Deterministic, but now protects time-only clock and off-main-menu clock behavior. |
| `test/foglet_bbs/tui/app_test.exs` | Subscription and no-op update coverage | PARTIAL | Covers interval and no-op update, but asserts off-main-menu subscription exists. |
| `test/foglet_bbs/tui/screens/main_menu_test.exs` | ShellVisibility drift regression | VERIFIED | Role-table tests use `ShellVisibility` as expected source of truth. |
| `.planning/ROADMAP.md` | Phase 6 plan list | VERIFIED | Phase lists four checked plan files. |

### Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| `StatusBar` | `ClockFormatter` | `ClockFormatter.format/2` | WIRED | `status_bar.ex:57` calls formatter with `clock_instant(state)` and user. |
| `StatusBar` | Phase 5 user snapshot | `state.current_user` | WIRED | Formatter consumes `user.timezone` and `user.preferences["time_format"]`; no Repo/Accounts persistence calls found in chrome files. |
| `App.subscribe/1` | Raxol interval | `subscribe_interval(60_000, :main_menu_clock_tick)` | PARTIAL | Interval exists, but the screen guard is wrong for main-menu-only behavior. |
| `App.update/2` | no-op clock tick | `do_update(:main_menu_clock_tick, state)` | WIRED | Explicit clause returns `{state, []}`. |
| `MainMenu` | `ShellVisibility` | render/key predicates | WIRED | `visible_menu_items/1`, `visible_menu_keys/1`, and key handlers call ShellVisibility. |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|---|---|---|---|---|
| `StatusBar` | `current_user.timezone`, `current_user.preferences["time_format"]` | Phase 5 user/session snapshot | Yes | FLOWING, but rendered string omits date. |
| `StatusBar` | `session_context[:clock_now]` / `DateTime.utc_now()` | injected test instant or runtime now | Yes | FLOWING. |
| `App.subscribe/1` | `state.current_screen`, `state.current_user` | Raxol app state | Yes | HOLLOW for screen scoping: current_screen is available but not used in the clock condition. |
| `MainMenu` | `current_user.role`, invite policy | `ShellVisibility` predicates and session/config fallback | Yes | FLOWING. |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| Focused Phase 6 tests | `rtk mix test test/foglet_bbs/tui/widgets/chrome/status_bar_test.exs test/foglet_bbs/tui/app_test.exs test/foglet_bbs/tui/screens/main_menu_test.exs` | 147 tests, 0 failures | PASS, but tests are weakened for the failing date/off-main-menu assertions. |
| Layout smoke | `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs` | 18 tests, 0 failures | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|---|---|---|---|---|
| MENU-01 | 06-01, 06-02, 06-04 | Current date and time in top-right chrome using saved timezone and 12h/24h preference, defaulting to system timezone and 12h. | BLOCKED | Timezone and 12h/24h are implemented, but current date is not rendered; tests refute date text. |
| MENU-02 | 06-01, 06-03, 06-04 | Main-menu time display refreshes at least once per minute without reconnect. | SATISFIED | 60s interval and no-op update handler exist; user-visible refresh path is wired. |

No additional Phase 6 requirement IDs are present in `.planning/REQUIREMENTS.md`; MENU-01 and MENU-02 are both accounted for.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|---|---:|---|---|---|
| `test/foglet_bbs/tui/widgets/chrome/status_bar_test.exs` | 83 | `refute rendered =~ "2026-04-24"` | Blocker | Test protects behavior that contradicts MENU-01 date rendering. |
| `test/foglet_bbs/tui/app_test.exs` | 848 | `non-main-menu screens also add chrome clock interval subscription` | Warning | Test protects behavior that contradicts Plan 06-03 and 06-VALIDATION main-menu-only timer scope. |

### Human Verification Required

None before gap closure. After the clock/date and subscription scoping gaps are fixed, run a manual SSH/TUI smoke check to confirm the top-right chrome reads correctly in an actual terminal and refreshes while staying on the main menu.

### Gaps Summary

Phase 6 is not complete against the goal contract. The main-menu role navigation is wired correctly, and the refresh mechanism exists, but MENU-01 is only partially implemented because the clock omits the date. Two plan-level scope guards also drifted: clock rendering and timer subscription were broadened to authenticated non-main-menu screens, and the tests were changed to assert that broadened behavior instead of the planned main-menu-only behavior.

---

_Verified: 2026-04-24T14:09:43Z_  
_Verifier: Claude (gsd-verifier)_
