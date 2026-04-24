# Phase 0: Screen Shells and Shared Surface Primitives - Research

**Researched:** 2026-04-23
**Domain:** Phoenix + Raxol server-rendered TUI shell architecture [VERIFIED: mix.exs] [VERIFIED: docs/ARCHITECTURE.md]
**Confidence:** HIGH [VERIFIED: local code grep] [CITED: https://hex.pm/packages/phoenix] [CITED: https://hex.pm/packages/raxol]

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
### Navigation and Role Visibility
- **D-01:** Account is a standard main-menu destination for authenticated users.
- **D-02:** Moderation and Sysop entry points use current session-role visibility checks in Phase 0 (`:mod`, `:sysop`) so the shells can be navigated now without pre-empting the actor-aware authorization seam planned for Phase 1.

### Shell Architecture Pattern
- **D-03:** Account, Moderation, and Sysop are first-class `Foglet.TUI.Screen` modules added to `Foglet.TUI.App` routing, rendered through `Foglet.TUI.Widgets.Chrome.ScreenFrame`.
- **D-04:** Each shell owns screen-local tab/focus state under `state.screen_state`, following the existing state-struct pattern already used by other non-trivial screens.

### Tab Model and Shared Invite Primitive
- **D-05:** Shell tabs use `Foglet.TUI.Widgets.Input.Tabs` for stable left/right and digit-based tab navigation instead of ad hoc tab handling.
- **D-06:** Phase 0 introduces a shared `INVITES` shell/tab primitive as reusable state and rendering scaffolding only; it is not a live invite workflow in this phase.
- **D-07:** The shared `INVITES` primitive is future-facing and conditionally shown, so later phases can activate it according to role and config without duplicating shell code.

### Shell Tab Sets
- **D-08:** Account has `PROFILE` and `PREFS` tabs in Phase 0.
- **D-09:** Account also carries the future-facing, conditionally shown `INVITES` tab scaffold in the shell contract.
- **D-10:** Moderation has `QUEUE`, `LOG`, `USERS`, `SANCTIONS`, and `BOARDS` tabs.
- **D-11:** Sysop has `SITE`, `BOARDS`, `LIMITS`, `SYSTEM`, and `USERS` tabs.

### Placeholder, Loading, and Error Semantics
- **D-12:** Shell tabs follow existing TUI semantics: `nil` state means loading, empty collections/states render explicit placeholder copy, and unexpected failures surface through the shared modal/error path rather than fake inline business data.
- **D-13:** Phase 0 placeholder content must stay obviously non-operational and must not introduce fake save actions, fake moderation actions, or fake invite behavior.

### the agent's Discretion
- Exact placeholder copy inside each shell/tab, as long as it stays clearly scaffold-only.
- Whether tab-local state lives in one per-screen struct or a small shared shell-state helper, as long as it stays consistent with existing `screen_state` patterns.
- Exact key-bar labels and menu wording, as long as navigation remains explicit and terminal-native.

### Deferred Ideas (OUT OF SCOPE)
None — analysis stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ACCT-01 | User can open a private Account screen from the TUI main menu. | Add `:account` routing in `Foglet.TUI.App`, add a main-menu entry for authenticated users, and keep Account tab/focus state in `state.screen_state[:account]`. [VERIFIED: lib/foglet_bbs/tui/app.ex] [VERIFIED: lib/foglet_bbs/tui/screens/main_menu.ex] |
| MODR-01 | Moderator can open a Moderation workspace with `QUEUE`, `LOG`, `USERS`, `SANCTIONS`, and `BOARDS` tabs. | Add a first-class `Foglet.TUI.Screens.Moderation` module with parent-owned tabs backed by `Foglet.TUI.Widgets.Input.Tabs` and current-role visibility checks at the menu level only. [VERIFIED: .planning/phases/00-screen-shells-and-shared-surface-primitives/00-CONTEXT.md] [VERIFIED: lib/foglet_bbs/accounts/user.ex] |
| SYSO-01 | Sysop can open a Sysop workspace with `SITE`, `BOARDS`, `LIMITS`, `SYSTEM`, and `USERS` tabs. | Add a first-class `Foglet.TUI.Screens.Sysop` module using the same shell pattern as Moderation, rendered through `ScreenFrame` with placeholder/loading/error branches but no fake write actions. [VERIFIED: .planning/phases/00-screen-shells-and-shared-surface-primitives/00-CONTEXT.md] [VERIFIED: lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex] |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

- Run `mix precommit` after implementation work; it already covers compile warnings, formatting, Credo, Sobelow, and Dialyzer. [VERIFIED: CLAUDE.md]
- Use `Req` for HTTP work and avoid `:httpoison`, `:tesla`, and `:httpc`. [VERIFIED: CLAUDE.md]
- Prefer Elixir stdlib date/time modules and do not add date/time deps unless explicitly needed for parsing. [VERIFIED: CLAUDE.md]
- Read `docs/ARCHITECTURE.md`, `docs/ROADMAP.md`, the vendored `docs/raxol/` docs, and `.planning/` artifacts before non-trivial TUI changes. [VERIFIED: CLAUDE.md]
- Do not put multiple modules in one file. [VERIFIED: CLAUDE.md]
- Do not use `Access` on structs; use field access or changeset helpers instead. [VERIFIED: CLAUDE.md]
- In tests, use `start_supervised!/1` and avoid `Process.sleep/1` and `Process.alive?/1` for synchronization. [VERIFIED: CLAUDE.md]

## Summary

Phase 0 should follow Foglet's existing screen architecture exactly: `Foglet.TUI.App` owns routing, command dispatch, and `screen_state`; each new shell is a first-class `Foglet.TUI.Screen`; and all shell rendering goes through `Foglet.TUI.Widgets.Chrome.ScreenFrame`. That pattern is already how BoardList, ThreadList, PostReader, and MainMenu work today, and it is the lowest-risk way to add Account, Moderation, and Sysop without inventing a second screen model. [VERIFIED: lib/foglet_bbs/tui/app.ex] [VERIFIED: lib/foglet_bbs/tui/screen.ex] [VERIFIED: lib/foglet_bbs/tui/screens/board_list.ex] [VERIFIED: lib/foglet_bbs/tui/screens/thread_list.ex] [VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex]

The standard shell recipe for this phase is: parent-owned tabs via `Foglet.TUI.Widgets.Input.Tabs`, per-screen tab/focus state stored under `state.screen_state`, placeholder/loading branches that reuse `Foglet.TUI.Widgets.Progress.Spinner`, and unexpected failures surfaced through the shared modal path on `state.modal`. Raxol's current Tabs docs still describe the tab bar as keyboard-navigation-only with content switching owned by the parent, so the repo wrapper and the official component docs agree on the same architecture. [VERIFIED: lib/foglet_bbs/tui/widgets/input/tabs.ex] [VERIFIED: lib/foglet_bbs/tui/widgets/progress/spinner.ex] [VERIFIED: lib/foglet_bbs/tui/widgets/modal.ex] [CITED: https://hexdocs.pm/raxol/Raxol.UI.Components.Input.Tabs.html]

The shared `INVITES` primitive should be implemented as screen-adjacent scaffolding, not as a low-level widget and not as three copied tab implementations. It needs to own reusable placeholder/loading/error rendering and a small future-facing state contract, while remaining explicitly non-operational in Phase 0 so later invite persistence and policy phases can attach real behavior without undoing fake commands or fake data. [VERIFIED: .planning/phases/00-screen-shells-and-shared-surface-primitives/00-CONTEXT.md] [VERIFIED: .planning/ROADMAP.md] [VERIFIED: .planning/STATE.md]

**Primary recommendation:** Implement Account, Moderation, and Sysop as new `Foglet.TUI.Screen` modules with dedicated state structs under `state.screen_state`, render them with `ScreenFrame`, drive tabs through `Foglet.TUI.Widgets.Input.Tabs`, and extract one shared `INVITES` surface helper for view/state scaffolding only. Add no new dependencies and no fake operator actions. [VERIFIED: lib/foglet_bbs/tui/app.ex] [VERIFIED: lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex] [VERIFIED: lib/foglet_bbs/tui/widgets/input/tabs.ex] [VERIFIED: .planning/phases/00-screen-shells-and-shared-surface-primitives/00-CONTEXT.md]

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Main-menu entry points for Account, Moderation, and Sysop | Frontend Server (SSR) [VERIFIED: docs/ARCHITECTURE.md] | API / Backend [VERIFIED: lib/foglet_bbs/accounts/user.ex] | The TUI server process renders and routes screens, while role values originate from authenticated user/session state. [VERIFIED: lib/foglet_bbs/tui/screens/main_menu.ex] [VERIFIED: lib/foglet_bbs/ssh/cli_handler.ex] |
| Shell-local tab, focus, and placeholder state | Frontend Server (SSR) [VERIFIED: docs/ARCHITECTURE.md] | — | Existing non-trivial screens already keep UI-only state under `state.screen_state`, and the phase explicitly locks that pattern in. [VERIFIED: lib/foglet_bbs/tui/screens/post_reader/state.ex] [VERIFIED: .planning/phases/00-screen-shells-and-shared-surface-primitives/00-CONTEXT.md] |
| Conditional `INVITES` tab visibility | Frontend Server (SSR) [VERIFIED: .planning/phases/00-screen-shells-and-shared-surface-primitives/00-CONTEXT.md] | API / Backend [VERIFIED: lib/foglet_bbs/config.ex] | The shell decides what to render, but the inputs are current role and invite policy values. [VERIFIED: lib/foglet_bbs/accounts/user.ex] [VERIFIED: lib/foglet_bbs/config.ex] |
| Unexpected shell errors | Frontend Server (SSR) [VERIFIED: lib/foglet_bbs/tui/app.ex] | API / Backend [VERIFIED: lib/foglet_bbs/tui/app.ex] | The shell should surface failures through the shared modal path, while any real failing domain work continues to live behind typed command results. [VERIFIED: lib/foglet_bbs/tui/app.ex] |
| Authorization enforcement for future moderation/sysop actions | API / Backend [VERIFIED: .planning/ROADMAP.md] | Frontend Server (SSR) [VERIFIED: .planning/STATE.md] | Phase 0 uses screen visibility only; real actor-aware authorization is explicitly deferred to Phase 1. [VERIFIED: .planning/phases/00-screen-shells-and-shared-surface-primitives/00-CONTEXT.md] [VERIFIED: .planning/ROADMAP.md] |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Phoenix | `1.8.5` current on Hex; project pinned at `~> 1.8.5` [VERIFIED: mix.exs] [CITED: https://hex.pm/packages/phoenix] | Application foundation and endpoint supervision. [VERIFIED: docs/ARCHITECTURE.md] | The project is already a Phoenix app, and Phoenix 1.8.5 is also the current Hex release as of March 5, 2026. [VERIFIED: mix.exs] [CITED: https://hex.pm/packages/phoenix] |
| Raxol | vendored `2.4.0`; current Hex package `2.4.0` updated April 14, 2026 [VERIFIED: vendor/raxol/mix.exs] [CITED: https://hex.pm/packages/raxol] | TUI runtime, View DSL, keyboard event model, and component base. [VERIFIED: docs/raxol/README.md] | Foglet's TUI already depends on Raxol's TEA loop and components; Phase 0 should extend that runtime, not bypass it. [VERIFIED: docs/raxol/getting-started/CORE_CONCEPTS.md] [VERIFIED: lib/foglet_bbs/tui/app.ex] |
| `Foglet.TUI.App` + `Foglet.TUI.Screen` | repo-local [VERIFIED: lib/foglet_bbs/tui/app.ex] [VERIFIED: lib/foglet_bbs/tui/screen.ex] | Screen routing, command processing, and the screen behavior contract. [VERIFIED: lib/foglet_bbs/tui/app.ex] | Every current screen already plugs in through this pair, and the phase context explicitly locks new shells into that pattern. [VERIFIED: lib/foglet_bbs/tui/screens/main_menu.ex] [VERIFIED: .planning/phases/00-screen-shells-and-shared-surface-primitives/00-CONTEXT.md] |
| `Foglet.TUI.Widgets.Chrome.ScreenFrame` | repo-local [VERIFIED: lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex] | Shared outer shell chrome, title bar, divider, and key bar. [VERIFIED: lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex] | Shell screens should look like every other Foglet screen and reuse the existing chrome contract instead of drawing bespoke borders and key hints. [VERIFIED: lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex] |
| `Foglet.TUI.Widgets.Input.Tabs` | repo-local wrapper over Raxol Tabs [VERIFIED: lib/foglet_bbs/tui/widgets/input/tabs.ex] [CITED: https://hexdocs.pm/raxol/Raxol.UI.Components.Input.Tabs.html] | Stable left/right/home/end/`1-9` tab navigation with Foglet theming. [VERIFIED: lib/foglet_bbs/tui/widgets/input/tabs.ex] | It already wraps the official Raxol component and is covered by dedicated tests for keyboard behavior and theme hygiene. [VERIFIED: test/foglet_bbs/tui/widgets/input/tabs_test.exs] |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `Foglet.TUI.Widgets.Progress.Spinner` | repo-local [VERIFIED: lib/foglet_bbs/tui/widgets/progress/spinner.ex] | Shell-level loading affordance routed through Foglet theming. [VERIFIED: lib/foglet_bbs/tui/widgets/progress/spinner.ex] | Use when a tab state is intentionally `nil` and the shell should show a loading branch. [VERIFIED: .planning/phases/00-screen-shells-and-shared-surface-primitives/00-CONTEXT.md] |
| `Foglet.TUI.Widgets.Modal` + `state.modal` path | repo-local [VERIFIED: lib/foglet_bbs/tui/widgets/modal.ex] [VERIFIED: lib/foglet_bbs/tui/app.ex] | Shared info/warning/error display. [VERIFIED: lib/foglet_bbs/tui/app.ex] | Use for unexpected failures instead of fake inline rows or fake fallback data. [VERIFIED: .planning/phases/00-screen-shells-and-shared-surface-primitives/00-CONTEXT.md] |
| `Foglet.Config` typed accessors | repo-local [VERIFIED: lib/foglet_bbs/config.ex] | Read invite policy and related typed runtime config without introducing raw config plumbing. [VERIFIED: lib/foglet_bbs/config.ex] | Use for conditional `INVITES` visibility once the shell needs current config, but keep domain mutations out of Phase 0. [VERIFIED: .planning/ROADMAP.md] [VERIFIED: .planning/STATE.md] |
| `Raxol.UI.Components.Display.Viewport` | official Raxol component docs available; crawled docs show current API shape [CITED: https://hexdocs.pm/raxol/Raxol.UI.Components.Display.Viewport.html] | Scrollable content container with parent-managed visible height and children. [CITED: https://hexdocs.pm/raxol/Raxol.UI.Components.Display.Viewport.html] | Use only if a shell tab needs real scrolling; do not hand-roll scroll offsets once content outgrows a fixed panel. [VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex] [CITED: https://hexdocs.pm/raxol/Raxol.UI.Components.Display.Viewport.html] |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `Foglet.TUI.Widgets.Input.Tabs` [VERIFIED: lib/foglet_bbs/tui/widgets/input/tabs.ex] | Ad hoc row/text tab bars [ASSUMED] | You would lose the tested key semantics, parent-change contract, and theme wrapper already present in the repo. [VERIFIED: test/foglet_bbs/tui/widgets/input/tabs_test.exs] |
| `ScreenFrame` [VERIFIED: lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex] | Per-screen custom frames [ASSUMED] | That duplicates key-bar/title-bar layout and creates visual drift across shells. [VERIFIED: lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex] |
| `state.screen_state[:screen_name]` [VERIFIED: lib/foglet_bbs/tui/app.ex] | New top-level `App` fields for each shell tab index [ASSUMED] | That leaks screen-local concerns into global app state and breaks the pattern already used by non-trivial screens. [VERIFIED: lib/foglet_bbs/tui/screens/post_reader/state.ex] |
| One shared `INVITES` surface helper [VERIFIED: .planning/phases/00-screen-shells-and-shared-surface-primitives/00-CONTEXT.md] | Three copied `INVITES` tab implementations [ASSUMED] | Duplication would make Phase 4 activation and later invite feature work harder to change consistently. [VERIFIED: .planning/ROADMAP.md] |

**Installation:**
```bash
# No new dependencies are needed for Phase 0.
mix deps.get
```

**Version verification:** Current releases checked on 2026-04-23: Phoenix `1.8.5` published 2026-03-05, Raxol `2.4.0` updated 2026-04-14, Bandit `1.10.4` updated 2026-03-26, and the repo runtime pins Elixir `1.19.5` with OTP `28.3.1`. Phase 0 should not spend scope on dependency churn because the required shell primitives already exist locally. [CITED: https://hex.pm/packages/phoenix] [CITED: https://hex.pm/packages/raxol] [CITED: https://hex.pm/packages/bandit] [VERIFIED: .tool-versions] [VERIFIED: config/config.exs]

## Architecture Patterns

### System Architecture Diagram

```text
SSH key / keyboard input
        |
        v
Foglet.SSH.CLIHandler
  - builds session_context
  - starts Raxol lifecycle
        |
        v
Foglet.TUI.App
  - current_screen router
  - screen_state owner
  - modal owner
  - async command dispatcher
        |
        +----> MainMenu visibility helper
        |        - Account for authenticated user
        |        - Moderation for :mod / :sysop
        |        - Sysop for :sysop
        |
        +----> Account / Moderation / Sysop screen module
                 - render via ScreenFrame
                 - own tab/focus state struct
                 - delegate tab key events to Tabs wrapper
                 - switch active tab content in parent
                 |
                 +----> Shared INVITES surface helper
                 |        - placeholder/loading/error rendering only
                 |        - no generate/revoke/save commands in Phase 0
                 |
                 +----> Shared modal path on unexpected failure
```

The diagram above matches the current Foglet/TUI control flow: SSH session context is built before the app starts, `Foglet.TUI.App` is the routing conductor, and screens remain pure render/handle modules with command dispatch centralized in the app layer. [VERIFIED: lib/foglet_bbs/ssh/cli_handler.ex] [VERIFIED: lib/foglet_bbs/tui/app.ex] [VERIFIED: docs/ARCHITECTURE.md]

### Recommended Project Structure

```text
lib/foglet_bbs/tui/screens/
├── account.ex                 # Account shell render/handle module
├── account/state.ex           # Account screen-local state struct
├── moderation.ex              # Moderation shell render/handle module
├── moderation/state.ex        # Moderation screen-local state struct
├── sysop.ex                   # Sysop shell render/handle module
├── sysop/state.ex             # Sysop screen-local state struct
└── shared/
    ├── invites_surface.ex     # Shared INVITES render + visibility helper
    └── invites_state.ex       # Shared INVITES placeholder/loading state

test/foglet_bbs/tui/screens/
├── account_test.exs
├── moderation_test.exs
├── sysop_test.exs
└── shared/invites_surface_test.exs
```

This mirrors the existing pattern where stateful screens keep a separate state module and avoids the project-specific anti-pattern of nesting multiple modules in one file. [VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex] [VERIFIED: lib/foglet_bbs/tui/screens/post_reader/state.ex] [VERIFIED: CLAUDE.md]

### Pattern 1: App-Routed Pure Shell Screens

**What:** Add new screen atoms to `Foglet.TUI.App`, map each atom in `screen_module_for/1`, and keep Account/Moderation/Sysop modules limited to `render/1`, `handle_key/2`, and optional `init_screen_state/1`. [VERIFIED: lib/foglet_bbs/tui/app.ex] [VERIFIED: lib/foglet_bbs/tui/screen.ex]

**When to use:** Use for all three new shells and for any future screen that needs route ownership plus screen-local state. [VERIFIED: lib/foglet_bbs/tui/screens/board_list.ex] [VERIFIED: lib/foglet_bbs/tui/screens/thread_list.ex]

**Example:**
```elixir
# Source: lib/foglet_bbs/tui/app.ex and lib/foglet_bbs/tui/screens/main_menu.ex
@type screen ::
        :login
        | :main_menu
        | :account
        | :moderation
        | :sysop

defp screen_module_for(:account), do: Screens.Account
defp screen_module_for(:moderation), do: Screens.Moderation
defp screen_module_for(:sysop), do: Screens.Sysop

def handle_key(%{key: :char, char: "A"}, state) do
  ss = Foglet.TUI.Screens.Account.init_screen_state()

  {:update,
   %{state | current_screen: :account, screen_state: Map.put(state.screen_state, :account, ss)},
   []}
end
```

### Pattern 2: Parent-Owned Tabs with Per-Screen State Structs

**What:** Keep the active tab index, focus target, and any shell-only placeholder data in a per-screen struct under `state.screen_state[:screen_name]`; feed keys into `Foglet.TUI.Widgets.Input.Tabs`; and let the parent screen switch content based on the returned `{:tab_changed, index}` action. [VERIFIED: lib/foglet_bbs/tui/widgets/input/tabs.ex] [CITED: https://hexdocs.pm/raxol/Raxol.UI.Components.Input.Tabs.html]

**When to use:** Use whenever tab content belongs to the shell rather than the tab bar widget itself. [CITED: https://hexdocs.pm/raxol/Raxol.UI.Components.Input.Tabs.html]

**Example:**
```elixir
# Source: lib/foglet_bbs/tui/widgets/input/tabs.ex
defstruct tabs: nil, active_tab: 0

def handle_key(event, state) do
  ss = state.screen_state.account
  {tabs, action} = Foglet.TUI.Widgets.Input.Tabs.handle_event(event, ss.tabs)

  new_ss =
    case action do
      {:tab_changed, idx} -> %{ss | tabs: tabs, active_tab: idx}
      _ -> %{ss | tabs: tabs}
    end

  {:update, put_in(state.screen_state.account, new_ss), []}
end
```

### Pattern 3: Placeholder/Loading/Error as a Data Contract

**What:** Use `nil` for loading, empty list or empty map for explicit placeholders, and the shared modal path for unexpected failures. Do not seed fake business rows or fake buttons to make the shell look "complete." [VERIFIED: .planning/phases/00-screen-shells-and-shared-surface-primitives/00-CONTEXT.md] [VERIFIED: lib/foglet_bbs/tui/screens/board_list.ex] [VERIFIED: lib/foglet_bbs/tui/app.ex]

**When to use:** Use for every shell tab in Phase 0, especially the future-facing `INVITES` surface. [VERIFIED: .planning/ROADMAP.md]

**Example:**
```elixir
# Source: lib/foglet_bbs/tui/screens/board_list.ex and lib/foglet_bbs/tui/app.ex
defp render_tab_body(nil, theme) do
  frame = System.monotonic_time(:millisecond) |> abs() |> div(Spinner.frame_duration_ms())

  row style: %{gap: 1} do
    [
      Spinner.render(frame, style: :line, theme: theme),
      text("Loading…", fg: theme.dim.fg)
    ]
  end
end

defp render_tab_body([], theme) do
  text("This surface is scaffolded for a later phase.", fg: theme.warning.fg)
end

# unexpected failure -> set state.modal via the shared app/modal path
```

### Pattern 4: Shared Surface Helper for `INVITES`

**What:** Extract one helper module that owns `INVITES` tab labels, placeholder/loading/error rendering, and conditional visibility rules, while the parent shell still decides where the tab sits in its tab set. [VERIFIED: .planning/phases/00-screen-shells-and-shared-surface-primitives/00-CONTEXT.md]

**When to use:** Use anywhere Account, Moderation, or Sysop needs the same future-facing `INVITES` surface seam. [VERIFIED: .planning/ROADMAP.md]

**Example:**
```elixir
# Source: phase context + existing screen_state pattern
defmodule Foglet.TUI.Screens.Shared.InvitesSurface do
  def visible?(%{role: :sysop}, _policy), do: true
  def visible?(%{role: :mod}, "mods"), do: true
  def visible?(%{role: :user}, "any_user"), do: true
  def visible?(_, _), do: false

  def default_state, do: %{items: []}
  def title, do: "INVITES"
  def render(%{items: nil}, theme), do: render_loading(theme)
  def render(%{items: []}, theme), do: render_placeholder(theme)
end
```

### Anti-Patterns to Avoid

- **Fake business actions:** Do not add Save/Generate/Revoke/Approve commands that are not wired to real domain logic yet. The roadmap explicitly says later phases should not have to undo fake behavior. [VERIFIED: .planning/ROADMAP.md] [VERIFIED: .planning/STATE.md]
- **Ad hoc tab key handling:** Do not rebuild left/right/digit navigation inside each screen; use `Foglet.TUI.Widgets.Input.Tabs`. [VERIFIED: lib/foglet_bbs/tui/widgets/input/tabs.ex] [VERIFIED: test/foglet_bbs/tui/widgets/input/tabs_test.exs]
- **Global app-state leakage:** Do not add top-level `App` fields for shell tab indices or placeholder bodies; keep shell-local state under `state.screen_state`. [VERIFIED: lib/foglet_bbs/tui/app.ex] [VERIFIED: lib/foglet_bbs/tui/screens/post_reader/state.ex]
- **Direct domain I/O in render paths:** Do not fetch real shell data in `render/1`; the current app already routes async work through `Foglet.TUI.Command.task` and typed result messages. [VERIFIED: lib/foglet_bbs/tui/app.ex]
- **Three separate `INVITES` implementations:** Do not let Account, Moderation, and Sysop each invent their own invites placeholder state or copy. [VERIFIED: .planning/phases/00-screen-shells-and-shared-surface-primitives/00-CONTEXT.md] [VERIFIED: .planning/ROADMAP.md]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Tab keyboard navigation | Custom left/right/home/end/`1-9` handlers in each shell [ASSUMED] | `Foglet.TUI.Widgets.Input.Tabs` [VERIFIED: lib/foglet_bbs/tui/widgets/input/tabs.ex] | The wrapper already standardizes key behavior, theming, and test coverage. [VERIFIED: test/foglet_bbs/tui/widgets/input/tabs_test.exs] |
| Outer shell chrome | Custom bordered layout per screen [ASSUMED] | `Foglet.TUI.Widgets.Chrome.ScreenFrame` [VERIFIED: lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex] | Existing screens already share one title/status/key-bar frame contract. [VERIFIED: lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex] |
| Loading indicator | Inline glyph strings or ad hoc animation [ASSUMED] | `Foglet.TUI.Widgets.Progress.Spinner` [VERIFIED: lib/foglet_bbs/tui/widgets/progress/spinner.ex] | The wrapper already delegates to Raxol spinner styles and routes colors through the theme. [VERIFIED: lib/foglet_bbs/tui/widgets/progress/spinner.ex] |
| Error presentation | Inline fake error rows or copied modal code [ASSUMED] | `state.modal` + `Foglet.TUI.Widgets.Modal` [VERIFIED: lib/foglet_bbs/tui/app.ex] [VERIFIED: lib/foglet_bbs/tui/widgets/modal.ex] | The app already owns modal dismissal/confirm semantics globally. [VERIFIED: lib/foglet_bbs/tui/app.ex] |
| Scroll state once a shell grows taller content | Custom `scroll_offset` ints everywhere [ASSUMED] | `Raxol.UI.Components.Display.Viewport` [CITED: https://hexdocs.pm/raxol/Raxol.UI.Components.Display.Viewport.html] [VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex] | Viewport already supports visible-height, content-height, and scroll clamping; PostReader shows the local pattern. [VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex] [CITED: https://hexdocs.pm/raxol/Raxol.UI.Components.Display.Viewport.html] |

**Key insight:** This phase already has the right primitives in-tree. The real risk is architectural drift, not missing libraries. [VERIFIED: lib/foglet_bbs/tui/widgets/README.md] [VERIFIED: .planning/phases/00-screen-shells-and-shared-surface-primitives/00-CONTEXT.md]

## Common Pitfalls

### Pitfall 1: Letting the tab bar own shell behavior

**What goes wrong:** The screen becomes a thin wrapper around the tab widget and later cannot express per-tab placeholder, focus, or visibility logic cleanly. [CITED: https://hexdocs.pm/raxol/Raxol.UI.Components.Input.Tabs.html]

**Why it happens:** Raxol's Tabs component renders the bar and reports selection changes, but content switching is explicitly the parent's job. [CITED: https://hexdocs.pm/raxol/Raxol.UI.Components.Input.Tabs.html]

**How to avoid:** Keep a per-screen struct with `active_tab` and route `{:tab_changed, idx}` into that state; treat the tab widget as navigation only. [VERIFIED: lib/foglet_bbs/tui/widgets/input/tabs.ex]

**Warning signs:** The tab helper starts storing shell-specific placeholder data or there are multiple code paths deciding which tab body to show. [VERIFIED: .planning/phases/00-screen-shells-and-shared-surface-primitives/00-CONTEXT.md]

### Pitfall 2: Losing shell-local state by skipping `state.screen_state`

**What goes wrong:** Focus, active tab, and placeholder state reset unexpectedly on route changes or do not survive modal interactions. [VERIFIED: lib/foglet_bbs/tui/app.ex]

**Why it happens:** The current app contract centralizes local screen state under `state.screen_state`; bypassing it creates one-off lifecycle behavior. [VERIFIED: lib/foglet_bbs/tui/app.ex] [VERIFIED: lib/foglet_bbs/tui/screens/post_reader/state.ex]

**How to avoid:** Give each new shell a state struct in its own file and seed/read it through `state.screen_state[:screen]`. [VERIFIED: lib/foglet_bbs/tui/screens/post_reader/state.ex] [VERIFIED: CLAUDE.md]

**Warning signs:** New `Foglet.TUI.App` struct fields appear just to remember a shell tab index or placeholder flag. [VERIFIED: lib/foglet_bbs/tui/app.ex]

### Pitfall 3: Treating menu visibility as authorization

**What goes wrong:** Phase 0 shells imply permission enforcement even though real actor-aware authorization is not implemented until Phase 1. [VERIFIED: .planning/ROADMAP.md]

**Why it happens:** Role-based menu visibility is convenient and already available from `user.role`, but UI visibility alone is not the same as a policy boundary. [VERIFIED: lib/foglet_bbs/accounts/user.ex] [VERIFIED: .planning/STATE.md]

**How to avoid:** Keep Phase 0 screens read-only and avoid any mutation commands or fake operator actions. [VERIFIED: .planning/phases/00-screen-shells-and-shared-surface-primitives/00-CONTEXT.md]

**Warning signs:** A shell adds a button or keybinding that sounds operational before the backing phase exists. [VERIFIED: .planning/ROADMAP.md]

### Pitfall 4: Digit shortcuts colliding with future numeric input

**What goes wrong:** Pressing `1-9` changes tabs when the user expects digit input for a field or command. [VERIFIED: lib/foglet_bbs/tui/widgets/input/tabs.ex]

**Why it happens:** The local Tabs wrapper explicitly documents that digit shortcuts are consumed by the underlying Raxol component unless the parent filters them first. [VERIFIED: lib/foglet_bbs/tui/widgets/input/tabs.ex] [VERIFIED: test/foglet_bbs/tui/widgets/input/tabs_test.exs]

**How to avoid:** In any shell mode that later accepts numeric input, filter the event before forwarding it to `Tabs.handle_event/2`. [VERIFIED: lib/foglet_bbs/tui/widgets/input/tabs.ex]

**Warning signs:** The shell mixes editable numeric fields and tab navigation in the same mode without an explicit event filter. [VERIFIED: lib/foglet_bbs/tui/widgets/input/tabs.ex]

### Pitfall 5: Copying `INVITES` placeholder logic into every shell

**What goes wrong:** Phase 4 has to edit three divergent placeholders, visibility branches, and keybars to turn on one shared feature. [VERIFIED: .planning/ROADMAP.md]

**Why it happens:** The `INVITES` surface feels small in Phase 0, so duplication looks cheaper than abstraction. [ASSUMED]

**How to avoid:** Extract a single shared surface helper now, but keep it limited to view/state scaffolding rather than low-level rendering-only concerns. [VERIFIED: .planning/phases/00-screen-shells-and-shared-surface-primitives/00-CONTEXT.md]

**Warning signs:** Account, Moderation, and Sysop each have their own copies of invite placeholder strings and visibility rules. [VERIFIED: .planning/phases/00-screen-shells-and-shared-surface-primitives/00-CONTEXT.md]

## Code Examples

Verified patterns from official and local sources:

### Route a new shell through `Foglet.TUI.App`

```elixir
# Source: lib/foglet_bbs/tui/app.ex
defp screen_module_for(:account), do: Screens.Account
defp screen_module_for(:moderation), do: Screens.Moderation
defp screen_module_for(:sysop), do: Screens.Sysop

defp render_screen(state) do
  screen_module_for(state.current_screen).render(state)
end
```

### Use the Tabs wrapper as navigation only

```elixir
# Source: lib/foglet_bbs/tui/widgets/input/tabs.ex
tabs = Foglet.TUI.Widgets.Input.Tabs.init(tabs: ["PROFILE", "PREFS"], active: 0)
{tabs, action} = Foglet.TUI.Widgets.Input.Tabs.handle_event(%{key: :right}, tabs)

case action do
  {:tab_changed, idx} -> %{screen_state | tabs: tabs, active_tab: idx}
  _ -> %{screen_state | tabs: tabs}
end
```

This matches the official Raxol Tabs contract, where the parent is responsible for content switching. [CITED: https://hexdocs.pm/raxol/Raxol.UI.Components.Input.Tabs.html]

### Use the standard loading branch

```elixir
# Source: lib/foglet_bbs/tui/screens/board_list.ex
frame = System.monotonic_time(:millisecond) |> abs() |> div(Spinner.frame_duration_ms())

row style: %{gap: 1} do
  [
    Spinner.render(frame, style: :line, theme: theme),
    text("Loading…", fg: theme.dim.fg)
  ]
end
```

### Keep direct I/O out of screens

```elixir
# Source: lib/foglet_bbs/tui/app.ex
defp do_update({:load_boards}, state) do
  user = state.current_user
  boards_mod = domain_module(state, :boards)

  task =
    Foglet.TUI.Command.task(:load_boards, fn ->
      {:boards_loaded, boards_mod.list_subscribed_boards(user)}
    end)

  {state, [task]}
end
```

The shell phase should stay read-only, but this is still the correct future pattern if a tab later loads real data. [VERIFIED: lib/foglet_bbs/tui/app.ex]

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Planning around Cowboy as Phoenix's default web adapter [ASSUMED] | Phoenix 1.8.5 docs say newly generated apps use `Bandit` via `Bandit.PhoenixAdapter`, and this repo is already configured that way. [CITED: https://hexdocs.pm/phoenix/Phoenix.Endpoint.html] [VERIFIED: config/config.exs] | Phoenix docs current as of 2026-04-23. [CITED: https://hexdocs.pm/phoenix/Phoenix.Endpoint.html] | Do not spend phase effort on outdated endpoint/server assumptions. [VERIFIED: config/config.exs] |
| Hand-built tab strips with content logic mixed into rendering [ASSUMED] | Use `Foglet.TUI.Widgets.Input.Tabs` / Raxol Tabs for navigation and keep content switching in the parent screen. [VERIFIED: lib/foglet_bbs/tui/widgets/input/tabs.ex] [CITED: https://hexdocs.pm/raxol/Raxol.UI.Components.Input.Tabs.html] | Current official Tabs docs crawled last month still describe this contract. [CITED: https://hexdocs.pm/raxol/Raxol.UI.Components.Input.Tabs.html] | Stable key semantics and easier reuse across Account, Moderation, and Sysop. [VERIFIED: test/foglet_bbs/tui/widgets/input/tabs_test.exs] |
| Manual scroll integers for every long panel [ASSUMED] | Use `Viewport` once content needs scrolling. [VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex] [CITED: https://hexdocs.pm/raxol/Raxol.UI.Components.Display.Viewport.html] | PostReader already uses the modern local pattern, and the official Viewport docs still match it. [VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex] [CITED: https://hexdocs.pm/raxol/Raxol.UI.Components.Display.Viewport.html] | Future shell tabs can grow without inventing a second scrolling system. [VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex] |

**Deprecated/outdated:**

- Building an end-user web admin UI for these operations is out of scope for this milestone; the current product direction is terminal-first and the Phoenix endpoint exists for operations and future structured clients. [VERIFIED: .planning/PROJECT.md] [VERIFIED: docs/ARCHITECTURE.md]
- Shipping fake moderation, sysop, or invite actions in Phase 0 is explicitly outdated by the current roadmap and phase state. [VERIFIED: .planning/ROADMAP.md] [VERIFIED: .planning/STATE.md]

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Ad hoc tab bars, custom frames, and copied `INVITES` implementations are the only realistic alternatives worth considering for this phase. [ASSUMED] | Standard Stack / Don't Hand-Roll | Low — it affects recommendation framing, not the locked implementation direction. |
| A2 | The "old approach" rows in State of the Art reflect common historical patterns rather than this repo's current plan. [ASSUMED] | State of the Art | Low — planner decisions still point to the verified current approach. |
| A3 | The `Why it happens` sentence in Pitfall 5 reflects the usual reason duplication appears in early shell phases. [ASSUMED] | Common Pitfalls | Low — mitigation remains the same. |

## Open Questions

1. **Where should current invite-policy visibility data come from in Phase 0?**
   What we know: `CLIHandler` currently injects `registration_mode` into `session_context`, but not `invite_code_generators`; typed accessors for invite policy already exist in `Foglet.Config`. [VERIFIED: lib/foglet_bbs/ssh/cli_handler.ex] [VERIFIED: lib/foglet_bbs/config.ex]
   What's unclear: whether the planner wants menu/shell visibility to consult `Foglet.Config.invite_code_generators/0` directly in Phase 0 or to extend `session_context` now for consistency. [VERIFIED: lib/foglet_bbs/config.ex]
   Recommendation: keep the visibility rule behind one small helper so the planner can choose either input source without changing shell call sites. [VERIFIED: .planning/phases/00-screen-shells-and-shared-surface-primitives/00-CONTEXT.md]

2. **Should the shared `INVITES` primitive live under `tui/screens/shared/` or `tui/widgets/`?**
   What we know: the primitive needs both reusable rendering and reusable state semantics, so it is more than a presentational widget. [VERIFIED: .planning/phases/00-screen-shells-and-shared-surface-primitives/00-CONTEXT.md]
   What's unclear: whether the planner prefers a screen helper namespace or a widget namespace for reuse. [VERIFIED: lib/foglet_bbs/tui/widgets/README.md]
   Recommendation: place it under `tui/screens/shared/` so its state contract stays near the screens that consume it. [VERIFIED: lib/foglet_bbs/tui/screens/post_reader/state.ex] [VERIFIED: CLAUDE.md]

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Elixir | Build, tests, precommit | ✓ [VERIFIED: local command `elixir --version`] | `1.19.5` [VERIFIED: .tool-versions] [VERIFIED: local command `elixir --version`] | — |
| Erlang/OTP | Runtime, Mix, SSH/TUI stack | ✓ [VERIFIED: local command `elixir --version`] | `28.3.1` pinned, OTP 28 active locally [VERIFIED: .tool-versions] [VERIFIED: local command `elixir --version`] | — |
| Mix | `mix test`, `mix precommit` | ✓ [VERIFIED: local command `mix --version`] | `1.19.5` [VERIFIED: local command `mix --version`] | — |
| PostgreSQL on `localhost:5432` | Standard `mix test` alias and full verification flow | ✗ [VERIFIED: local command `pg_isready`] | — | No standard fallback for the normal `mix test` / `mix precommit` path. [VERIFIED: mix.exs] |

**Missing dependencies with no fallback:**

- Local PostgreSQL service for the standard verification path. The project `test` alias runs `ecto.create`, `ecto.migrate`, and a seed script before tests, so normal test execution is blocked until Postgres is available. [VERIFIED: mix.exs] [VERIFIED: local command `pg_isready`]

**Missing dependencies with fallback:**

- None. [VERIFIED: local environment audit]

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | ExUnit via Mix aliases. [VERIFIED: mix.exs] [VERIFIED: test/test_helper.exs] |
| Config file | `test/test_helper.exs`. [VERIFIED: test/test_helper.exs] |
| Quick run command | `mix test test/foglet_bbs/tui/screens/account_test.exs` once the file exists and Postgres is running. [VERIFIED: mix.exs] |
| Full suite command | `mix test` and `mix precommit` after implementation. [VERIFIED: mix.exs] [VERIFIED: CLAUDE.md] |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| ACCT-01 | Main menu routes authenticated user into Account shell with stable `PROFILE` / `PREFS` tabs and read-only placeholders. [VERIFIED: .planning/ROADMAP.md] [VERIFIED: .planning/phases/00-screen-shells-and-shared-surface-primitives/00-CONTEXT.md] | unit + layout smoke [VERIFIED: existing test style in `test/foglet_bbs/tui/screens/main_menu_test.exs`] | `mix test test/foglet_bbs/tui/screens/account_test.exs` [VERIFIED: mix.exs] | ❌ Wave 0 [VERIFIED: `rg --files test`] |
| MODR-01 | Main menu exposes Moderation only for current operator roles and the shell renders `QUEUE` / `LOG` / `USERS` / `SANCTIONS` / `BOARDS`. [VERIFIED: .planning/ROADMAP.md] [VERIFIED: .planning/phases/00-screen-shells-and-shared-surface-primitives/00-CONTEXT.md] | unit + layout smoke [VERIFIED: existing test style in `test/foglet_bbs/tui/layout_smoke_test.exs`] | `mix test test/foglet_bbs/tui/screens/moderation_test.exs` [VERIFIED: mix.exs] | ❌ Wave 0 [VERIFIED: `rg --files test`] |
| SYSO-01 | Main menu exposes Sysop only for `:sysop` and the shell renders `SITE` / `BOARDS` / `LIMITS` / `SYSTEM` / `USERS`. [VERIFIED: .planning/ROADMAP.md] [VERIFIED: .planning/phases/00-screen-shells-and-shared-surface-primitives/00-CONTEXT.md] | unit + layout smoke [VERIFIED: existing test style in `test/foglet_bbs/tui/layout_smoke_test.exs`] | `mix test test/foglet_bbs/tui/screens/sysop_test.exs` [VERIFIED: mix.exs] | ❌ Wave 0 [VERIFIED: `rg --files test`] |

### Sampling Rate

- **Per task commit:** `mix test test/foglet_bbs/tui/screens/account_test.exs` or the narrowest new shell/shared-surface test file that changed. [VERIFIED: mix.exs]
- **Per wave merge:** `mix test` once Postgres is available. [VERIFIED: mix.exs]
- **Phase gate:** `mix precommit` green before `/gsd-verify-work`. [VERIFIED: CLAUDE.md]

### Wave 0 Gaps

- [ ] `test/foglet_bbs/tui/screens/account_test.exs` — covers ACCT-01 shell routing, tab switching, and non-operational placeholders. [VERIFIED: .planning/ROADMAP.md]
- [ ] `test/foglet_bbs/tui/screens/moderation_test.exs` — covers MODR-01 shell routing, role-gated entry visibility, and tab set rendering. [VERIFIED: .planning/ROADMAP.md]
- [ ] `test/foglet_bbs/tui/screens/sysop_test.exs` — covers SYSO-01 shell routing, role-gated entry visibility, and tab set rendering. [VERIFIED: .planning/ROADMAP.md]
- [ ] `test/foglet_bbs/tui/screens/shared/invites_surface_test.exs` — covers shared placeholder/loading/error behavior and visibility helper logic. [VERIFIED: .planning/phases/00-screen-shells-and-shared-surface-primitives/00-CONTEXT.md]
- [ ] Extend `test/foglet_bbs/tui/screens/main_menu_test.exs` — new menu items and role visibility assertions. [VERIFIED: test/foglet_bbs/tui/screens/main_menu_test.exs]
- [ ] Extend `test/foglet_bbs/tui/app_test.exs` — screen routing, `screen_module_for/1`, and `screen_state` seeding for new shells. [VERIFIED: test/foglet_bbs/tui/app_test.exs]
- [ ] Extend `test/foglet_bbs/tui/layout_smoke_test.exs` — Account, Moderation, and Sysop layout smoke coverage. [VERIFIED: test/foglet_bbs/tui/layout_smoke_test.exs]

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | yes [VERIFIED: docs/ARCHITECTURE.md] | Reuse authenticated `current_user` / session state; Phase 0 does not add a new auth path. [VERIFIED: lib/foglet_bbs/ssh/cli_handler.ex] [VERIFIED: lib/foglet_bbs/tui/app.ex] |
| V3 Session Management | yes [VERIFIED: docs/ARCHITECTURE.md] | Route shell visibility from the existing one-session-per-user session model and `session_context`. [VERIFIED: docs/ARCHITECTURE.md] [VERIFIED: lib/foglet_bbs/sessions/session.ex] |
| V4 Access Control | yes [VERIFIED: .planning/ROADMAP.md] | Keep Phase 0 to presentation-only role visibility and defer real actor-aware enforcement to Phase 1. [VERIFIED: .planning/ROADMAP.md] [VERIFIED: .planning/STATE.md] |
| V5 Input Validation | yes [VERIFIED: local code grep] | Whitelist screen atoms, tab labels, and key events through existing screen and tab contracts. [VERIFIED: lib/foglet_bbs/tui/screen.ex] [VERIFIED: lib/foglet_bbs/tui/widgets/input/tabs.ex] |
| V6 Cryptography | no [VERIFIED: phase scope in `.planning/ROADMAP.md`] | None required in this phase because no new secrets or crypto flows are introduced. [VERIFIED: .planning/ROADMAP.md] |

### Known Threat Patterns for Phoenix + SSH TUI shells

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Treating hidden menu entries as real authorization | Elevation of Privilege [VERIFIED: .planning/ROADMAP.md] | Keep Phase 0 screens read-only and reserve real policy enforcement for Phase 1 backend work. [VERIFIED: .planning/ROADMAP.md] [VERIFIED: .planning/STATE.md] |
| Triggering real domain changes from placeholder shell controls | Tampering [VERIFIED: .planning/phases/00-screen-shells-and-shared-surface-primitives/00-CONTEXT.md] | Do not wire fake save/generate/revoke commands until the domain phase exists. [VERIFIED: .planning/STATE.md] |
| Blocking the SSH UI with direct domain I/O in render paths | Denial of Service [VERIFIED: lib/foglet_bbs/tui/app.ex] | Keep render pure and route any future loads through `Foglet.TUI.Command.task` and typed result messages. [VERIFIED: lib/foglet_bbs/tui/app.ex] |
| Duplicated visibility rules drifting across menu and screens | Tampering / Elevation of Privilege [ASSUMED] | Centralize role/config visibility in one helper used by MainMenu and the shells. [VERIFIED: lib/foglet_bbs/accounts/user.ex] [VERIFIED: lib/foglet_bbs/config.ex] |

## Sources

### Primary (HIGH confidence)

- `docs/ARCHITECTURE.md` - system architecture, session layer, and TUI/server boundaries. [VERIFIED: docs/ARCHITECTURE.md]
- `docs/raxol/getting-started/CORE_CONCEPTS.md` - TEA loop and state ownership model. [VERIFIED: docs/raxol/getting-started/CORE_CONCEPTS.md]
- `docs/raxol/cookbook/BUILDING_APPS.md` - state machines, parent-owned views, and layout patterns. [VERIFIED: docs/raxol/cookbook/BUILDING_APPS.md]
- `lib/foglet_bbs/tui/app.ex` - routing, async command handling, modal path, and screen dispatch. [VERIFIED: lib/foglet_bbs/tui/app.ex]
- `lib/foglet_bbs/tui/widgets/input/tabs.ex` - local tab contract and digit-shortcut caveat. [VERIFIED: lib/foglet_bbs/tui/widgets/input/tabs.ex]
- `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex` - shared shell chrome contract. [VERIFIED: lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex]
- `https://hexdocs.pm/phoenix/Phoenix.Endpoint.html` - current Phoenix endpoint and Bandit adapter guidance. [CITED: https://hexdocs.pm/phoenix/Phoenix.Endpoint.html]
- `https://hexdocs.pm/raxol/Raxol.UI.Components.Input.Tabs.html` - official tab component contract. [CITED: https://hexdocs.pm/raxol/Raxol.UI.Components.Input.Tabs.html]
- `https://hexdocs.pm/raxol/Raxol.UI.Components.Display.Viewport.html` - official viewport contract. [CITED: https://hexdocs.pm/raxol/Raxol.UI.Components.Display.Viewport.html]

### Secondary (MEDIUM confidence)

- `https://hex.pm/packages/phoenix` - current Phoenix package version and release date. [CITED: https://hex.pm/packages/phoenix]
- `https://hex.pm/packages/raxol` - current Raxol package version and release date. [CITED: https://hex.pm/packages/raxol]
- `https://hex.pm/packages/bandit` - current Bandit package version and release date. [CITED: https://hex.pm/packages/bandit]
- `https://hex.pm/packages/oban/versions` - current Oban release train for project-stack currency checks. [CITED: https://hex.pm/packages/oban/versions]
- `https://www.hex.pm/packages/phoenix_live_dashboard/0.7.0` - search result exposing current LiveDashboard `0.8.7` version line. [CITED: https://www.hex.pm/packages/phoenix_live_dashboard/0.7.0]

### Tertiary (LOW confidence)

- None. [VERIFIED: research audit]

## Metadata

**Confidence breakdown:**

- Standard stack: HIGH - the required primitives are present in local code, and current package versions were cross-checked against Hex. [VERIFIED: mix.exs] [VERIFIED: lib/foglet_bbs/tui/widgets/input/tabs.ex] [CITED: https://hex.pm/packages/phoenix] [CITED: https://hex.pm/packages/raxol]
- Architecture: HIGH - the repo already demonstrates the exact routing/state/modal patterns this phase should follow. [VERIFIED: lib/foglet_bbs/tui/app.ex] [VERIFIED: lib/foglet_bbs/tui/screens/post_reader.ex]
- Pitfalls: HIGH - the most important traps are documented both in local code/tests and in the phase constraints. [VERIFIED: lib/foglet_bbs/tui/widgets/input/tabs.ex] [VERIFIED: test/foglet_bbs/tui/widgets/input/tabs_test.exs] [VERIFIED: .planning/phases/00-screen-shells-and-shared-surface-primitives/00-CONTEXT.md]

**Research date:** 2026-04-23
**Valid until:** 2026-05-23 for local architecture guidance; 2026-04-30 for package-currency checks. [VERIFIED: local code grep] [CITED: https://hex.pm/packages/phoenix] [CITED: https://hex.pm/packages/raxol]
