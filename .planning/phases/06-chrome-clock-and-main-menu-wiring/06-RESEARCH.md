# Phase 06: Chrome Clock and Main Menu Wiring - Research

**Researched:** 2026-04-24
**Domain:** Phoenix/Raxol TUI chrome, timer subscriptions, user display preferences
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

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

### Claude's Discretion
- Exact date/time string shape, as long as it includes date and time and clearly distinguishes 12-hour vs 24-hour output.
- Exact helper module/function names for formatting the clock. Prefer a small pure helper if that keeps `StatusBar` simple and tests deterministic.
- Whether `StatusBar.render/2` detects the main-menu scope from `state.current_screen`, from the `title`, or from an explicit option threaded through `ScreenFrame`; prefer the least invasive option that keeps behavior clear and testable.
- Exact interval message atom name, as long as it is distinct from `:heartbeat_tick`.

### Deferred Ideas (OUT OF SCOPE)
None - analysis stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| MENU-01 | User sees current date/time in top-right chrome rendered in saved timezone and 12h/24h preference, defaulting to system timezone and 12-hour time. | Use `StatusBar` through `ScreenFrame`, read Phase 5 fields from `state.current_user`, convert with Timex, and test with injected instants. [VERIFIED: `.planning/REQUIREMENTS.md`, `06-CONTEXT.md`, `status_bar.ex`, HexDocs Timex] |
| MENU-02 | Main-menu time display refreshes at least once per minute without reconnect. | Add a main-menu-only `subscribe_interval/2` entry in `Foglet.TUI.App.subscribe/1` and a no-op update handler distinct from `:heartbeat_tick`. [VERIFIED: `.planning/REQUIREMENTS.md`, `06-CONTEXT.md`, `app.ex`, `docs/raxol/getting-started/QUICKSTART.md`] |
</phase_requirements>

## Summary

Phase 6 should be planned as a narrow TUI wiring phase: keep screen chrome ownership in `Foglet.TUI.Widgets.Chrome.ScreenFrame` and `Foglet.TUI.Widgets.Chrome.StatusBar`, keep `MainMenu` stateless, and add the clock through the shared chrome path only for `:main_menu`. [VERIFIED: `06-CONTEXT.md`, `06-SPEC.md`, `screen_frame.ex`, `status_bar.ex`, `main_menu.ex`]

The time source is not a new persistence concern. Phase 5 owns `users.timezone`, `preferences["time_format"]`, Timex validation/defaulting, and live session refresh; Phase 6 should consume the refreshed `state.current_user` / `state.session_context` snapshot and avoid render-time database reads. [VERIFIED: `05-CONTEXT.md`, `05-SPEC.md`, `06-CONTEXT.md`]

The refresh mechanism belongs in `Foglet.TUI.App.subscribe/1`, using Raxol's interval subscription pattern. Raxol docs show `subscribe_interval(1000, :tick)` returning periodic messages to `update/2`; the current app already uses `subscribe_interval(10_000, :heartbeat_tick)` for session heartbeat. [CITED: `docs/raxol/getting-started/QUICKSTART.md`; VERIFIED: `lib/foglet_bbs/tui/app.ex`]

**Primary recommendation:** Implement a small pure clock formatter plus a main-menu-only `StatusBar` branch and a `:main_menu_clock_tick` no-op update handler. [VERIFIED: `06-CONTEXT.md`, `status_bar.ex`, `app.ex`]

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|--------------|----------------|-----------|
| Clock text rendering | TUI widget layer | TUI app state | `StatusBar` owns top-row right-side chrome, while `state.current_user` / `state.session_context` carry preference data. [VERIFIED: `status_bar.ex`, `screen_frame.ex`, `06-CONTEXT.md`] |
| Clock refresh scheduling | TUI app runtime | Raxol runtime | `Foglet.TUI.App.subscribe/1` already owns timer and custom subscription wiring. [VERIFIED: `app.ex`; CITED: `docs/raxol/getting-started/QUICKSTART.md`] |
| Timezone and format preference persistence | Accounts/session layer | TUI widget consumer | Phase 5 owns persistence and live refresh; Phase 6 consumes the values. [VERIFIED: `05-CONTEXT.md`, `05-SPEC.md`] |
| Account/Moderation/Sysop menu visibility | TUI screen visibility helper | Domain authorization remains separate | `MainMenu` already calls `ShellVisibility` for rendered entries and key handling; authorization is not menu visibility. [VERIFIED: `main_menu.ex`, `shell_visibility.ex`, `.planning/codebase/ARCHITECTURE.md`] |

## Project Constraints (from CLAUDE.md)

- Run `mix precommit` after implementation work; it runs compile, format, Credo, Sobelow, and Dialyzer checks. [VERIFIED: `CLAUDE.md`, `.planning/codebase/CONVENTIONS.md`]
- Use `Req` for HTTP requests and avoid `:httpoison`, `:tesla`, and `:httpc`; this phase should not need HTTP. [VERIFIED: `CLAUDE.md`]
- Prefer Elixir stdlib date/time APIs and do not add a date/time dependency unless asked; Phase 5 explicitly sanctioned Timex for timezone validation/conversion, so Phase 6 should use that existing dependency rather than add another. [VERIFIED: `CLAUDE.md`, `05-CONTEXT.md`, `05-SPEC.md`]
- Read `docs/ARCHITECTURE.md`, Raxol docs, and local widget docs before non-trivial TUI changes. [VERIFIED: `CLAUDE.md`]
- Keep one module per file, avoid struct `Access`, bind block-expression results, and use `start_supervised!/1` for processes in tests. [VERIFIED: `CLAUDE.md`, `.planning/codebase/CONVENTIONS.md`, `.planning/codebase/TESTING.md`]
- Generate migrations with `mix ecto.gen.migration` when needed; this phase should not need migrations because Phase 5 owns preference storage. [VERIFIED: `CLAUDE.md`, `05-SPEC.md`]

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Phoenix | 1.8.5 | App endpoint, PubSub, broader OTP/Phoenix integration. | Existing project dependency; TUI PubSub bridge uses Phoenix.PubSub. [VERIFIED: `mix deps`, `.planning/codebase/ARCHITECTURE.md`] |
| Raxol | 2.4.0 vendored | TUI runtime, view DSL, `subscribe_interval/2`. | Existing TUI app uses `use Raxol.Core.Runtime.Application`. [VERIFIED: `mix deps`, `app.ex`, `docs/raxol/README.md`] |
| Timex | 3.7.13 | Timezone validation and conversion for user-facing timestamps. | Phase 5 locked Timex as the timezone dependency; HexDocs documents `Timezone.exists?/1`, `local/0`, `name_of/1`, and `convert/2`. [CITED: https://hexdocs.pm/timex/Timex.Timezone.html; VERIFIED: `05-CONTEXT.md`] |
| ExUnit | Elixir built-in | Unit and render tests. | Existing TUI tests use `ExUnit.Case`; test helper excludes `:pending`. [VERIFIED: `.planning/codebase/TESTING.md`, `test/foglet_bbs/tui/app_test.exs`] |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `Foglet.TUI.RenderHelpers` | local | Collect text nodes from Raxol render trees. | Use in `MainMenu` / `StatusBar` tests to assert rendered clock and menu text without renderer internals. [VERIFIED: `test/support/foglet/tui/render_helpers.ex`] |
| `Foglet.TUI.Theme` | local | Themed color extraction for chrome. | `StatusBar` already reads `session_context.theme` with fallback to `Theme.default()`. [VERIFIED: `status_bar.ex`, `theme.ex`] |
| `Foglet.TUI.Screens.ShellVisibility` | local | Centralized Account/Moderation/Sysop/invite visibility. | Use for all main-menu rendered entries and key handling; do not duplicate role rules. [VERIFIED: `shell_visibility.ex`, `main_menu.ex`] |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Timex conversion | `DateTime.shift_zone/3` with a configured timezone database | Elixir docs state the default timezone database only handles UTC; Phase 5 already locked Timex, so switching would add config risk. [CITED: https://hexdocs.pm/elixir/DateTime.html; VERIFIED: `05-CONTEXT.md`] |
| `StatusBar` main-menu branch | Render clock directly in `MainMenu` content | Violates locked placement; clock is chrome, not content. [VERIFIED: `06-CONTEXT.md`] |
| Reusing heartbeat tick | Add clock rerender behavior to `:heartbeat_tick` | Locked decision calls for a distinct main-menu clock interval; heartbeat is session-liveness behavior. [VERIFIED: `06-CONTEXT.md`, `app.ex`] |

**Installation:**

```bash
# No new Phase 6 dependency should be installed.
# Phase 5 is expected to add Timex:
mix deps.get
```

**Version verification:** `mix deps` verified Phoenix 1.8.5 and Raxol 2.4.0 locally. [VERIFIED: `mix deps`] Hex package search verified Timex latest/locked expected version as 3.7.13, last updated 2025-06-14. [CITED: https://hex.pm/packages/timex]

## Architecture Patterns

### System Architecture Diagram

```text
Raxol interval (:main_menu_clock_tick)
  -> Foglet.TUI.App.update/2
  -> no-op state return
  -> Raxol rerender
  -> Foglet.TUI.App.view/1
  -> MainMenu.render/1
  -> ScreenFrame.render/4
  -> StatusBar.render/2
  -> ClockFormatter.format(now, user.timezone, user.preferences["time_format"])
  -> top-right chrome text
```

This data flow matches the existing Raxol lifecycle where `subscribe/1` creates recurring events and `update/2` returns the model/commands pair consumed by rendering. [CITED: `docs/raxol/getting-started/QUICKSTART.md`; VERIFIED: `app.ex`]

### Recommended Project Structure

```text
lib/foglet_bbs/tui/
├── app.ex                                  # add main-menu clock subscription + tick handler
├── screens/main_menu.ex                    # preserve ShellVisibility delegation
└── widgets/chrome/
    ├── status_bar.ex                       # main-menu clock right-side composition
    └── clock_formatter.ex                  # small pure helper, if planner chooses helper extraction

test/foglet_bbs/tui/
├── app_test.exs                            # subscription + no-op tick behavior
├── screens/main_menu_test.exs              # menu/key visibility regression
├── widgets/chrome/status_bar_test.exs      # deterministic clock rendering
└── layout_smoke_test.exs                   # keep 80x24 smoke passing
```

The optional helper file keeps deterministic formatting separate from Raxol view construction. [VERIFIED: `06-CONTEXT.md`, `status_bar.ex`, `.planning/codebase/CONVENTIONS.md`]

### Pattern 1: Pure Clock Formatting Helper

**What:** Format an injected UTC instant into user-facing date/time using `user.timezone` and `preferences["time_format"]`. [VERIFIED: `06-CONTEXT.md`; CITED: https://hexdocs.pm/timex/Timex.Timezone.html]

**When to use:** Use from `StatusBar.render/2`; tests should pass a fixed instant or override the now provider so assertions do not depend on wall-clock time. [VERIFIED: `06-CONTEXT.md`]

**Example:**

```elixir
# Source: Phase 6 CONTEXT + HexDocs Timex.Timezone
@spec format(DateTime.t(), map() | nil) :: String.t()
def format(now_utc, user) do
  timezone = user_timezone(user) || system_timezone() || "Etc/UTC"
  time_format = user_time_format(user) || "12h"

  localized =
    case Timex.Timezone.convert(now_utc, timezone) do
      %DateTime{} = dt -> dt
      _ -> Timex.Timezone.convert(now_utc, "Etc/UTC")
    end

  format_localized(localized, time_format)
end
```

### Pattern 2: Main-Menu-Only Subscription

**What:** Add a subscription only when `state.current_screen == :main_menu`, separate from heartbeat and PubSub. [VERIFIED: `06-CONTEXT.md`, `app.ex`]

**When to use:** Use `subscribe_interval(interval_ms, :main_menu_clock_tick)` with `interval_ms <= 60_000`. [CITED: `docs/raxol/getting-started/QUICKSTART.md`; VERIFIED: `06-CONTEXT.md`]

**Example:**

```elixir
# Source: docs/raxol/getting-started/QUICKSTART.md + lib/foglet_bbs/tui/app.ex
clock =
  if state.current_screen == :main_menu do
    [subscribe_interval(60_000, :main_menu_clock_tick)]
  else
    []
  end

heartbeat ++ clock ++ pubsub_subs
```

### Pattern 3: Visibility Helper as Source of Truth

**What:** Keep `MainMenu.visible_menu_items/1`, `visible_menu_keys/1`, and key handlers calling `ShellVisibility`. [VERIFIED: `main_menu.ex`, `shell_visibility.ex`]

**When to use:** Any Account, Moderation, Sysop entry rendering or key acceptance check. [VERIFIED: `06-CONTEXT.md`]

**Example:**

```elixir
# Source: lib/foglet_bbs/tui/screens/main_menu.ex
if ShellVisibility.sysop_visible?(state.current_user) do
  ss = Sysop.init_screen_state([])
  new_screen_state = Map.put(state.screen_state, :sysop, ss)
  {:update, %{state | current_screen: :sysop, screen_state: new_screen_state}, []}
else
  :no_match
end
```

### Anti-Patterns to Avoid

- **Render-time persistence reads:** Widgets should consume `state.current_user` / `state.session_context`; database reads belong in domain/session refresh flows. [VERIFIED: `06-CONTEXT.md`, `.planning/codebase/ARCHITECTURE.md`]
- **Duplicated role checks in `MainMenu`:** Keep role and policy visibility centralized in `ShellVisibility`. [VERIFIED: `06-CONTEXT.md`, `shell_visibility.ex`]
- **Wall-clock dependent tests:** Clock tests must inject/control the instant and timezone. [VERIFIED: `06-CONTEXT.md`, `06-SPEC.md`]
- **Layout-expanding status text:** The status bar must continue to fit current 80x24 smoke expectations. [VERIFIED: `06-CONTEXT.md`, `layout_smoke_test.exs`]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Timezone database and DST conversion | Manual offset math or hardcoded abbreviations | Timex timezone conversion from Phase 5 | Timezone offsets are date-sensitive; Timex docs explicitly describe date-sensitive timezone lookup/conversion. [CITED: https://hexdocs.pm/timex/Timex.Timezone.html] |
| Periodic rerender loop | Custom GenServer or `Process.send_after/3` in screen modules | Raxol `subscribe_interval/2` in `App.subscribe/1` | Existing runtime already routes interval messages into `update/2`. [CITED: `docs/raxol/getting-started/QUICKSTART.md`; VERIFIED: `app.ex`] |
| Menu role/policy matrix | Inline `role == ...` branches in `MainMenu` | `Foglet.TUI.Screens.ShellVisibility` | Prevents render/key/shell drift. [VERIFIED: `shell_visibility.ex`, `main_menu.ex`] |
| Raxol render-tree assertions | Ad hoc map walking in each test | `Foglet.TUI.RenderHelpers.collect_text_values/1` | Existing helper returns DFS text content for screen tests. [VERIFIED: `test/support/foglet/tui/render_helpers.ex`] |

**Key insight:** This phase is mostly glue; the risky work is preserving existing ownership boundaries while adding a deterministic clock seam. [VERIFIED: `06-CONTEXT.md`, `.planning/codebase/ARCHITECTURE.md`]

## Common Pitfalls

### Pitfall 1: Local Time Flakiness

**What goes wrong:** Tests pass only in the developer's timezone or at specific minutes. [VERIFIED: `06-CONTEXT.md`]
**Why it happens:** Formatting reads `DateTime.utc_now()` or system timezone directly inside assertions. [VERIFIED: `06-SPEC.md`]
**How to avoid:** Extract a pure formatter that accepts a fixed instant; isolate system-timezone fallback in a separately testable function. [VERIFIED: `06-CONTEXT.md`]
**Warning signs:** Assertions match `AM`/`PM`, date, or hour without constructing a known UTC instant. [ASSUMED]

### Pitfall 2: Rerender Tick Mutates Navigation State

**What goes wrong:** Clock ticks clear modal state, reload boards, or navigate unexpectedly. [VERIFIED: `06-CONTEXT.md`]
**Why it happens:** Timer handling is mixed into existing heartbeat or screen command logic. [VERIFIED: `app.ex`, `06-CONTEXT.md`]
**How to avoid:** Add a distinct tick atom whose update clause returns `{state, []}`. [VERIFIED: `06-CONTEXT.md`]
**Warning signs:** Tick tests assert only subscription existence, not state identity. [ASSUMED]

### Pitfall 3: Main Menu and Key Bar Drift

**What goes wrong:** A role sees a menu item but the key is not accepted, or the key is accepted while hidden. [VERIFIED: `06-CONTEXT.md`, `main_menu_test.exs`]
**Why it happens:** Rendered items, key-bar entries, and handlers are tested separately but not against the same `ShellVisibility` truth. [VERIFIED: `main_menu.ex`, `shell_visibility.ex`]
**How to avoid:** Add role-table tests covering rendered content, key-bar text, and `handle_key/2` acceptance/rejection for user/mod/sysop. [VERIFIED: `06-CONTEXT.md`]
**Warning signs:** New tests check only text content. [ASSUMED]

### Pitfall 4: Clock Text Breaks 80-Column Chrome

**What goes wrong:** Right-side identity/time text overlaps, wraps, or pushes left status content. [VERIFIED: `06-CONTEXT.md`]
**Why it happens:** `StatusBar` uses `justify_content: :space_between` and visible text length matters at 80 columns. [VERIFIED: `status_bar.ex`, `screen_frame.ex`]
**How to avoid:** Keep the format compact, preserve the left copy, and run/update the existing 80x24 layout smoke test. [VERIFIED: `06-CONTEXT.md`, `layout_smoke_test.exs`]
**Warning signs:** Status text includes full timezone names or seconds. [ASSUMED]

## Code Examples

### Deterministic Formatter Test Shape

```elixir
# Source: Phase 6 CONTEXT + existing ExUnit screen tests
test "formats 24-hour time in a known timezone" do
  user = %{timezone: "America/Chicago", preferences: %{"time_format" => "24h"}}
  instant = ~U[2026-04-24 18:05:00Z]

  assert ClockFormatter.format(instant, user) =~ "13:05"
end
```

### No-Op Clock Tick

```elixir
# Source: lib/foglet_bbs/tui/app.ex update pattern
defp do_update(:main_menu_clock_tick, state) do
  {state, []}
end
```

### StatusBar Integration Shape

```elixir
# Source: lib/foglet_bbs/tui/widgets/chrome/status_bar.ex
right =
  if state.current_screen == :main_menu and state.current_user do
    "#{ClockFormatter.now_for(state.current_user)}  @#{state.current_user.handle}"
  else
    if handle, do: "@#{handle}", else: "guest"
  end
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Status bar right side is only `@handle` or `guest`. | Main-menu status bar should include date/time plus identity in a compact right-side chrome field. | Phase 6. [VERIFIED: `06-CONTEXT.md`, `status_bar.ex`] | Tests must account for the new right-side text while preserving non-main-menu behavior. |
| User-facing timezone not represented in user rows. | Phase 5 adds `users.timezone` and `preferences["time_format"]`. | Phase 5. [VERIFIED: `05-SPEC.md`, `05-CONTEXT.md`] | Planner must ensure Phase 6 depends on Phase 5 completion before implementation. |
| Session heartbeat is the only local interval in `App.subscribe/1`. | Add a dedicated main-menu clock interval. | Phase 6. [VERIFIED: `app.ex`, `06-CONTEXT.md`] | Avoid overloading heartbeat behavior. |

**Deprecated/outdated:**
- Rendering clock text inside `MainMenu` content is out of bounds because clock placement is locked to chrome/status bar. [VERIFIED: `06-CONTEXT.md`]
- Adding a new date/time dependency is out of bounds because Phase 5 locked Timex and AGENTS/CLAUDE discourage date/time deps except sanctioned cases. [VERIFIED: `CLAUDE.md`, `05-CONTEXT.md`]

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Tick tests should assert state identity, not only subscription existence. | Common Pitfalls | Low; planner may write weaker tests that miss accidental mutation. |
| A2 | Full timezone names or seconds are likely too long for 80-column chrome. | Common Pitfalls | Medium; final UI string shape may need adjustment after smoke rendering. |

## Open Questions

1. **Exact clock string format**
   - What we know: It must include date and time, clearly distinguish 12h vs 24h, and fit 80x24. [VERIFIED: `06-CONTEXT.md`]
   - What's unclear: Exact display shape is intentionally left to planner discretion. [VERIFIED: `06-CONTEXT.md`]
   - Recommendation: Use compact forms such as `04/24 1:05 PM` and `04/24 13:05`; omit seconds and long timezone names. [ASSUMED]

2. **Phase 5 implementation names**
   - What we know: Phase 5 contract is `user.timezone` and `user.preferences["time_format"]`. [VERIFIED: `05-CONTEXT.md`]
   - What's unclear: Phase 5 plans/implementation may introduce helper names not visible yet in the current code snapshot. [VERIFIED: `.planning/STATE.md`, `mix.lock`]
   - Recommendation: Planner should include a Wave 0 dependency check for Phase 5 helpers and adapt to existing helper names if present. [VERIFIED: `.planning/ROADMAP.md`]

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| Elixir/Mix | Tests and compilation | Yes | 1.19.5 observed in Mix error stack | None needed. [VERIFIED: `mix help test` output] |
| Phoenix | App/PubSub environment | Yes | 1.8.5 | None. [VERIFIED: `mix deps`] |
| Raxol | TUI runtime/subscriptions | Yes | 2.4.0 vendored | None. [VERIFIED: `mix deps`] |
| Timex | Clock timezone conversion | Not in current lockfile snapshot; expected after Phase 5 | 3.7.13 from Hex | Block Phase 6 implementation until Phase 5 adds it. [VERIFIED: `mix.lock`; CITED: https://hex.pm/packages/timex] |

**Missing dependencies with no fallback:**
- Timex is not currently present in `mix.lock`; Phase 6 depends on Phase 5 adding it. [VERIFIED: `mix.lock`, `05-SPEC.md`]

**Missing dependencies with fallback:**
- None. [VERIFIED: environment audit]

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | ExUnit, built into Elixir. [VERIFIED: `.planning/codebase/TESTING.md`] |
| Config file | `test/test_helper.exs`. [VERIFIED: `.planning/codebase/TESTING.md`] |
| Quick run command | `mix test test/foglet_bbs/tui/widgets/chrome/status_bar_test.exs test/foglet_bbs/tui/app_test.exs test/foglet_bbs/tui/screens/main_menu_test.exs` [VERIFIED: repo test layout] |
| Full suite command | `mix precommit` [VERIFIED: `CLAUDE.md`, `.planning/codebase/CONVENTIONS.md`] |

### Phase Requirements -> Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| MENU-01 | Main-menu chrome renders date/time using saved timezone and 24h preference. | unit/render | `mix test test/foglet_bbs/tui/widgets/chrome/status_bar_test.exs` | Missing - Wave 0. [VERIFIED: `rg --files test/foglet_bbs/tui/widgets/chrome`] |
| MENU-01 | Missing preferences fall back to system timezone and 12h display without crashing. | unit/render | `mix test test/foglet_bbs/tui/widgets/chrome/status_bar_test.exs` | Missing - Wave 0. [VERIFIED: current tests] |
| MENU-02 | `App.subscribe/1` includes clock interval on `:main_menu` and not off main menu. | unit | `mix test test/foglet_bbs/tui/app_test.exs` | Exists. [VERIFIED: `app_test.exs`] |
| MENU-02 | Clock tick returns unchanged state and no commands. | unit | `mix test test/foglet_bbs/tui/app_test.exs` | Exists. [VERIFIED: `app_test.exs`] |
| MENU-01/MENU-02 | 80x24 layout smoke remains stable with clock text. | smoke | `mix test test/foglet_bbs/tui/layout_smoke_test.exs` | Exists. [VERIFIED: `layout_smoke_test.exs`] |
| MENU-01 | Account/Moderation/Sysop rendered entries, key-bar entries, and key bindings match `ShellVisibility`. | unit/render | `mix test test/foglet_bbs/tui/screens/main_menu_test.exs` | Exists, needs expansion. [VERIFIED: `main_menu_test.exs`] |

### Sampling Rate

- **Per task commit:** Run the focused quick command for files changed by that task. [VERIFIED: `.planning/codebase/TESTING.md`]
- **Per wave merge:** Run `mix test test/foglet_bbs/tui/app_test.exs test/foglet_bbs/tui/screens/main_menu_test.exs test/foglet_bbs/tui/layout_smoke_test.exs`. [VERIFIED: test layout]
- **Phase gate:** Run `mix precommit`. [VERIFIED: `CLAUDE.md`]

### Wave 0 Gaps

- [ ] `test/foglet_bbs/tui/widgets/chrome/status_bar_test.exs` - covers deterministic clock formatting and right-side chrome behavior for MENU-01. [VERIFIED: file absent by `rg --files`]
- [ ] Expand `test/foglet_bbs/tui/app_test.exs` - covers main-menu-only clock subscription and no-op tick. [VERIFIED: file exists]
- [ ] Expand `test/foglet_bbs/tui/screens/main_menu_test.exs` - covers role-table consistency with `ShellVisibility` after refreshed state. [VERIFIED: file exists]

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|------------------|
| V2 Authentication | No | Phase assumes authenticated TUI state; no auth flow changes. [VERIFIED: `06-SPEC.md`] |
| V3 Session Management | Yes | Use existing `state.current_user`, `state.session_context`, and `session_pid`; do not add persistence reads or session mutation in render. [VERIFIED: `app.ex`, `06-CONTEXT.md`] |
| V4 Access Control | Yes | Keep visibility in `ShellVisibility`; domain authorization remains separate. [VERIFIED: `shell_visibility.ex`, `06-CONTEXT.md`] |
| V5 Input Validation | No new user input | Clock consumes validated Phase 5 preferences; no new form fields. [VERIFIED: `05-SPEC.md`, `06-SPEC.md`] |
| V6 Cryptography | No | No crypto behavior in scope. [VERIFIED: `06-SPEC.md`] |

### Known Threat Patterns for TUI Chrome/Menu

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Role/menu drift exposes hidden surfaces | Elevation of Privilege | Delegate render and key handling to `ShellVisibility`, and test user/mod/sysop matrices. [VERIFIED: `shell_visibility.ex`, `06-CONTEXT.md`] |
| Render-time DB access leaks timing/failure into chrome | Denial of Service / Information Disclosure | Use live session snapshot and pure formatting; no DB reads in widgets. [VERIFIED: `.planning/codebase/ARCHITECTURE.md`, `06-CONTEXT.md`] |
| Invalid preference crashes status bar | Denial of Service | Fallback invalid/missing timezone to `"Etc/UTC"` and invalid/missing format to `"12h"`. [VERIFIED: `06-CONTEXT.md`, `05-CONTEXT.md`] |

## Sources

### Primary (HIGH confidence)
- `.planning/phases/06-chrome-clock-and-main-menu-wiring/06-CONTEXT.md` - locked decisions and implementation boundaries.
- `.planning/phases/06-chrome-clock-and-main-menu-wiring/06-SPEC.md` - requirements, constraints, acceptance criteria.
- `.planning/phases/05-account-preferences-and-live-session-refresh/05-CONTEXT.md` and `05-SPEC.md` - upstream preference and Timex contract.
- `lib/foglet_bbs/tui/app.ex` - current Raxol subscription and update ownership.
- `lib/foglet_bbs/tui/widgets/chrome/status_bar.ex` and `screen_frame.ex` - chrome ownership.
- `lib/foglet_bbs/tui/screens/main_menu.ex` and `shell_visibility.ex` - navigation visibility ownership.
- `docs/raxol/getting-started/QUICKSTART.md` - `subscribe_interval/2` example.
- https://hexdocs.pm/timex/Timex.Timezone.html - Timex timezone API.
- https://hex.pm/packages/timex - Timex package version and publish metadata.

### Secondary (MEDIUM confidence)
- https://hexdocs.pm/elixir/DateTime.html - stdlib timezone database caveat for `DateTime.shift_zone/3`.
- `.planning/codebase/ARCHITECTURE.md`, `CONVENTIONS.md`, `TESTING.md` - generated codebase maps.

### Tertiary (LOW confidence)
- None.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - verified from local deps, Phase 5 decisions, and HexDocs/Hex package pages.
- Architecture: HIGH - verified from code and project architecture docs.
- Pitfalls: MEDIUM - core risks are verified; warning signs include two assumptions about test strength and final text length.

**Research date:** 2026-04-24
**Valid until:** 2026-05-24 for local architecture; re-check Hex package versions if planning happens later.
