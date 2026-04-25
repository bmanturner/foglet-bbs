# Phase 18: Chrome V2 - Research

**Researched:** 2026-04-25  
**Domain:** SSH terminal UI chrome, Raxol layout, width-safe command/status rendering  
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
## Implementation Decisions

### Chrome Data Contract
- **D-01:** Introduce structured Chrome V2 data while keeping `Chrome.ScreenFrame` as the single screen-facing composition boundary.
- **D-02:** Existing plain title and flat key-list callers may be supported through a short compatibility normalizer, but the normalized output must feed `Chrome.CommandBar`.
- **D-03:** Do not preserve `Chrome.KeyBar` as a separate production footer path after caller migration; the old simple key-list path should be an adapter into the grouped command contract only.

### Breadcrumb Ownership
- **D-04:** Derive breadcrumb paths centrally from the current screen plus existing app, screen, and domain state, rooted at `Foglet`.
- **D-05:** Screens should not build final breadcrumb strings ad hoc. They may expose or pass extra context only where that context already exists, such as current board, current thread, compose step, or active operator tab.
- **D-06:** Breadcrumb formatting must stay shared so later facelift phases can change screen bodies without unwinding per-screen chrome behavior.

### Mode-Aware Status
- **D-07:** Status rendering must consume Phase 17 presentation-mode metadata (`:bbs` or `:operator`) rather than deriving mode from active theme, user role, or screen-local conditionals.
- **D-08:** BBS-mode status may show handle, time, unread, or activity atoms when those values are already available; operator-mode status may show handle, scope, time, or system/status atoms when already available.
- **D-09:** Optional status atoms must degrade honestly: absent unread/activity/scope/system data is omitted, falling back to the current guest or `@handle | time` treatment rather than placeholder or fabricated values.

### Responsive Chrome And Tests
- **D-10:** Add focused Chrome V2 primitive and contract tests for breadcrumb resolution, mode-specific status atoms, grouped command ordering, and command truncation priority.
- **D-11:** Extend positioned render/layout coverage for 64x22, 80x24, and at least one wide terminal size using `Raxol.UI.Layout.Engine.apply_layout/2` or an equivalent positioned render path.
- **D-12:** Width and truncation behavior must use the Phase 16 `Foglet.TUI.TextWidth` contract once available, especially for breadcrumbs, status atoms, command groups, and compact fallbacks.
- **D-13:** Tests should assert no overlap or incoherent content displacement, not only that expected text appears somewhere in the render tree.

### the agent's Discretion
- Exact struct/module names for breadcrumb data, status atoms, command groups, and the compatibility normalizer are planner discretion as long as they are local to `Foglet.TUI.Widgets.Chrome` or a clearly shared TUI contract.
- Exact command group labels and default priorities are planner discretion, but they should be stable enough for tests and cover existing purposes such as navigation, actions, system, tabs, fields, save, and refresh.
- Exact wide-terminal extra status atoms are planner discretion; the minimum requirement is honest omission when data is unavailable.

### Folded Todos
None.

### Claude's Discretion
Captured above under "the agent's Discretion". [VERIFIED: .planning/phases/18-chrome-v2/18-CONTEXT.md]

### Deferred Ideas (OUT OF SCOPE)
## Deferred Ideas

None — analysis stayed within phase scope.

### Reviewed Todos (not folded)
None.
</user_constraints>

## Summary

Phase 18 should implement Chrome V2 as a shared TUI composition layer, not as screen-level layout work. `Chrome.ScreenFrame.render/4` is already the single screen-facing boundary for the named screens, and it currently composes `StatusBar`, `divider`, caller content, and `KeyBar`; Chrome V2 should keep that boundary while replacing title/key-list internals with structured breadcrumb/status/command data. [VERIFIED: lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex] [VERIFIED: .planning/phases/18-chrome-v2/18-CONTEXT.md]

The standard implementation path is a small set of pure stateless Chrome modules under `Foglet.TUI.Widgets.Chrome`: `BreadcrumbBar`, `StatusBar` V2 or `StatusAtoms`, `CommandBar`, and a compatibility normalizer for old `{key, description}` lists. [VERIFIED: lib/foglet_bbs/tui/widgets/README.md] [VERIFIED: .planning/phases/18-chrome-v2/18-SPEC.md] These modules should consume `Foglet.TUI.Presentation.mode_for!/1`, `Foglet.TUI.TextWidth`, and `Foglet.TUI.Theme` rather than introducing new mode, width, or styling policies. [VERIFIED: lib/foglet_bbs/tui/presentation.ex] [VERIFIED: lib/foglet_bbs/tui/text_width.ex] [VERIFIED: lib/foglet_bbs/tui/theme.ex]

**Primary recommendation:** Use one normalized `Chrome.t()`-style data contract inside `Chrome.ScreenFrame`, derive breadcrumbs/status centrally from app state, render all commands through `Chrome.CommandBar`, and verify with pure primitive tests plus positioned `Raxol.UI.Layout.Engine.apply_layout/2` size-contract tests at 64x22, 80x24, and 132x50. [VERIFIED: test/foglet_bbs/tui/layout_smoke_test.exs] [VERIFIED: docs/raxol/core/ARCHITECTURE.md]

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|--------------|----------------|-----------|
| Breadcrumb resolution | TUI widget/application layer | Domain state as read-only input | Chrome owns display location strings; screens may expose already-loaded board/thread/tab context but should not format final breadcrumb text. [VERIFIED: .planning/phases/18-chrome-v2/18-CONTEXT.md] |
| Mode-aware status atoms | TUI widget layer | App session context | `Foglet.TUI.Presentation` owns screen mode metadata, and `StatusBar` already reads `current_user` plus `session_context.clock_now` for handle/time. [VERIFIED: lib/foglet_bbs/tui/presentation.ex] [VERIFIED: lib/foglet_bbs/tui/widgets/chrome/status_bar.ex] |
| Grouped command rendering | TUI widget layer | Screen callers provide command intent | `CommandBar` should render grouped hints; current screens already pass key lists to `ScreenFrame`, making caller migration a TUI-only contract change. [VERIFIED: .planning/phases/18-chrome-v2/18-SPEC.md] [VERIFIED: rg "ScreenFrame\\.render"] |
| Width-safe truncation | TUI helper/widget layer | Raxol measurement backend | `Foglet.TUI.TextWidth` wraps `Raxol.UI.TextMeasure`; Chrome should depend on that project helper for all display-width math. [VERIFIED: lib/foglet_bbs/tui/text_width.ex] [VERIFIED: vendor/raxol/lib/raxol/ui/text_measure.ex] |
| Login chrome adoption | TUI screen rendering | Existing auth contexts untouched | Login scope is chrome-only; authentication behavior, registration, reset, and quit flow must not change. [VERIFIED: .planning/phases/18-chrome-v2/18-SPEC.md] |

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CHROME-01 | Shared chrome renders breadcrumb-style locations with deliberate ASCII fallback. | Central `BreadcrumbBar` plus formatter/fallback tests rooted at `Foglet`. [VERIFIED: .planning/REQUIREMENTS.md] |
| CHROME-02 | Shared chrome renders mode-appropriate right-side status fields. | Consume `Foglet.TUI.Presentation.mode_for!/1`; build honest optional atoms from existing state only. [VERIFIED: lib/foglet_bbs/tui/presentation.ex] |
| CHROME-03 | `Chrome.CommandBar` renders grouped commands and truncates lower-priority hints first. | Replace `KeyBar` production rendering with a grouped, priority-aware command bar using `TextWidth`. [VERIFIED: lib/foglet_bbs/tui/widgets/chrome/key_bar.ex] |
| CHROME-04 | Chrome remains usable at 64x22, restores compact treatment around 80x24, and expands at wide sizes. | Extend existing layout smoke tests and use Raxol positioned layout output. [VERIFIED: test/foglet_bbs/tui/layout_smoke_test.exs] |
| CHROME-05 | Existing command-footer path migrates through `Chrome.CommandBar` compatibility adapter. | Keep flat key-list support as normalization only; remove separate production `KeyBar` footer path. [VERIFIED: .planning/phases/18-chrome-v2/18-CONTEXT.md] |
| LOGIN-01 | Login declares Classic Modern BBS mode and receives Chrome V2 without auth behavior changes. | Phase 17 maps `:login` to `:bbs`; Phase 18 should add render assertions while preserving existing login tests. [VERIFIED: lib/foglet_bbs/tui/presentation.ex] [VERIFIED: test/foglet_bbs/tui/screens/login_test.exs] |

## Project Constraints (from CLAUDE.md)

- Use `rtk` as the shell command prefix in this repo. [VERIFIED: AGENTS.md]
- Foglet is SSH-first; Phoenix is infrastructure and Phase 18 must not add end-user browser workflows. [VERIFIED: AGENTS.md]
- TUI behavior belongs in `Foglet.TUI.App` and screens/widgets; domain workflows stay in contexts. [VERIFIED: AGENTS.md]
- Widgets route colors through `Foglet.TUI.Theme`, accept theme explicitly, and keep render functions pure over already-loaded state. [VERIFIED: AGENTS.md] [VERIFIED: lib/foglet_bbs/tui/widgets/README.md]
- For TUI flows, keep global navigation in `Foglet.TUI.App`, screen-local state in screens or sibling state modules, off-process work in `Foglet.TUI.Command`, and reusable display in widgets. [VERIFIED: AGENTS.md]
- Tests should use synchronization rather than `Process.sleep/1`; run `mix precommit` when code changes are complete. [VERIFIED: AGENTS.md]

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Elixir / OTP | Elixir 1.19.5, OTP 28 | Language/runtime for TUI modules and tests | Project runs on this installed toolchain and `mix.exs` requires Elixir `~> 1.17`. [VERIFIED: rtk elixir --version] [VERIFIED: mix.exs] |
| Raxol | 2.4.0 path dependency | View DSL, layout engine, terminal rendering, Unicode measurement | Project depends on `{:raxol, path: "vendor/raxol"}`; registry reports Raxol 2.4.0 as available and vendor `mix.exs` is 2.4.0. [VERIFIED: mix.exs] [VERIFIED: vendor/raxol/mix.exs] [VERIFIED: mix hex.info raxol] |
| `Foglet.TUI.TextWidth` | local | Display-width measurement, truncation, padding, slicing | Phase 16 helper wraps `Raxol.UI.TextMeasure` and is required for layout-sensitive chrome. [VERIFIED: lib/foglet_bbs/tui/text_width.ex] |
| `Foglet.TUI.Presentation` | local | Screen id to `:bbs` / `:operator` mode mapping | Phase 17 contract maps Login/MainMenu/BBS screens to `:bbs` and Account/Moderation/Sysop to `:operator`. [VERIFIED: lib/foglet_bbs/tui/presentation.ex] |
| `Foglet.TUI.Theme` | local | Theme slot routing for chrome styles | Local widget policy forbids hardcoded colors in new widgets and Theme exposes `accent`, `dim`, `title`, `info`, `badge`, `success`, `warning`, `error`, `selected`, and related slots. [VERIFIED: lib/foglet_bbs/tui/widgets/README.md] [VERIFIED: lib/foglet_bbs/tui/theme.ex] |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| ExUnit | bundled with Elixir | Pure widget, screen render, and layout contract tests | Use for all Phase 18 tests under mirrored `test/foglet_bbs/tui/...` paths. [VERIFIED: mix.exs] |
| `Raxol.UI.Layout.Engine` | Raxol 2.4.0 | Positioned render/layout assertions | Use for no-overlap and terminal-size checks. [VERIFIED: docs/raxol/core/ARCHITECTURE.md] [VERIFIED: test/foglet_bbs/tui/layout_smoke_test.exs] |
| `Foglet.TUI.RenderHelpers` | local test helper | DFS collection of render-tree text nodes | Use for primitive/screen tests that do not need positioned coordinates. [VERIFIED: test/support/foglet/tui/render_helpers.ex] |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `Chrome.CommandBar` | Keep `Chrome.KeyBar` as production footer | Rejected by locked decision D-03; keeping both creates parallel footer behavior. [VERIFIED: .planning/phases/18-chrome-v2/18-CONTEXT.md] |
| `Foglet.TUI.TextWidth` | Direct `String.length/1` / `String.slice/3` | Rejected for layout-sensitive chrome because Unicode display width and grapheme boundaries are already centralized. [VERIFIED: lib/foglet_bbs/tui/text_width.ex] |
| Central breadcrumb resolver | Per-screen final breadcrumb strings | Rejected by locked decisions D-04 through D-06. [VERIFIED: .planning/phases/18-chrome-v2/18-CONTEXT.md] |
| New UI library | Another terminal UI stack | Rejected because Foglet already uses Raxol for TEA, widgets, layout, SSH rendering, and tests. [VERIFIED: docs/raxol/core/ARCHITECTURE.md] [VERIFIED: mix.exs] |

**Installation:**

```bash
# No new packages. Use the existing Raxol path dependency and local Foglet helpers.
rtk mix deps.get
```

**Version verification:** Raxol was checked with `rtk mix hex.info raxol`; registry output lists Raxol 2.4.0 and vendor `mix.exs` also declares `@version "2.4.0"`. [VERIFIED: mix hex.info raxol] [VERIFIED: vendor/raxol/mix.exs]

## Architecture Patterns

### System Architecture Diagram

```text
Screen render(state)
  -> caller content element + legacy key list or grouped command data
  -> Chrome.ScreenFrame.render(state, title_or_chrome, content, commands)
      -> Chrome.Normalizer
           -> Chrome model: breadcrumb parts, mode, status atoms, command groups
      -> Breadcrumb resolver
           -> current_screen + screen_state/domain structs -> ["Foglet", ...]
      -> Status atom builder
           -> Presentation.mode_for!(current_screen) + existing session/user data
      -> CommandBar
           -> groups + priorities + TextWidth budget -> visible hints
      -> Raxol View DSL tree
  -> Raxol.UI.Layout.Engine.apply_layout/2
  -> positioned terminal elements
```

This flow keeps screen bodies pure and lets the planner assign Phase 18 work to Chrome modules plus caller normalization. [VERIFIED: lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex] [VERIFIED: docs/raxol/core/ARCHITECTURE.md]

### Recommended Project Structure

```text
lib/foglet_bbs/tui/widgets/chrome/
├── breadcrumb_bar.ex      # breadcrumb data, formatting, truncation, ASCII fallback
├── command_bar.ex         # grouped command rendering and priority truncation
├── screen_frame.ex        # shared composition boundary
├── status_bar.ex          # V2 top chrome/status atom rendering
└── normalizer.ex          # compatibility from title/key-list callers to V2 data

test/foglet_bbs/tui/widgets/chrome/
├── breadcrumb_bar_test.exs
├── command_bar_test.exs
├── normalizer_test.exs
└── status_bar_test.exs
```

Widget files should live under `lib/foglet_bbs/tui/widgets/<bucket>/<name>.ex` and ship mirrored tests under `test/foglet_bbs/tui/widgets/<bucket>/`. [VERIFIED: lib/foglet_bbs/tui/widgets/README.md]

### Pattern 1: Normalize Once At The Frame Boundary

**What:** `ScreenFrame.render/4` should accept current callers while converting title/key-list inputs into one structured Chrome V2 model before rendering. [VERIFIED: .planning/phases/18-chrome-v2/18-CONTEXT.md]

**When to use:** Use this during migration so named screens can move incrementally without preserving `KeyBar` as a production renderer. [VERIFIED: .planning/phases/18-chrome-v2/18-SPEC.md]

**Example:**

```elixir
# Source: local pattern from ScreenFrame.render/4 and Phase 18 D-01/D-03.
def render(state, title_or_chrome, content_element, commands) do
  theme = Theme.from_state(state)
  chrome = Normalizer.normalize(state, title_or_chrome, commands)

  box style: %{border: :single, padding: 1, border_fg: theme.border.fg} do
    column style: %{gap: 0, justify_content: :space_between} do
      [
        column style: %{gap: 0} do
          [
            StatusBar.render(state, chrome, theme),
            divider(char: "─", style: %{fg: theme.border.fg}),
            content_element
          ]
        end,
        CommandBar.render(theme, chrome.command_groups, width: chrome.command_width)
      ]
    end
  end
end
```

### Pattern 2: Breadcrumb Parts, Not Final Strings In Screens

**What:** Store breadcrumb as ordered parts such as `["Foglet", "Boards", board.name]`, format separators in `BreadcrumbBar`, and truncate by display width. [VERIFIED: SCREENS.md] [VERIFIED: .planning/phases/18-chrome-v2/18-CONTEXT.md]

**When to use:** Use for every named screen and any future facelift screen. [VERIFIED: .planning/phases/18-chrome-v2/18-SPEC.md]

**Example:**

```elixir
# Source: Phase 18 D-04/D-06 and TextWidth helper contract.
def render(parts, theme, opts \\ []) do
  width = Keyword.fetch!(opts, :width)
  separator = Keyword.get(opts, :separator, " ▸ ")
  fallback_separator = Keyword.get(opts, :fallback_separator, " > ")

  parts
  |> Enum.map(&to_string/1)
  |> Enum.join(separator)
  |> TextWidth.truncate(width)
  |> then(&text(&1, fg: theme.title.fg, style: Map.get(theme.title, :style, [])))
end
```

### Pattern 3: Status Atoms Are Honest Progressive Enhancement

**What:** Build a list of status atoms from existing state only; drop optional atoms when data is missing or width is constrained. [VERIFIED: .planning/phases/18-chrome-v2/18-CONTEXT.md]

**When to use:** Use for BBS handle/time/unread/activity and operator handle/scope/time/system summaries. [VERIFIED: .planning/phases/18-chrome-v2/18-SPEC.md]

**Example:**

```elixir
# Source: existing StatusBar clock behavior plus Phase 18 D-07/D-09.
def atoms(state) do
  mode = Presentation.mode_for!(Map.fetch!(state, :current_screen))

  [
    handle_atom(state),
    mode_specific_scope_or_activity(mode, state),
    time_atom(state)
  ]
  |> Enum.reject(&is_nil/1)
end
```

### Pattern 4: Priority-Based Command Truncation

**What:** Commands should have group, key, label, and priority metadata; render high-priority groups first and drop lower-priority hints before truncating high-priority text. [VERIFIED: .planning/phases/18-chrome-v2/18-SPEC.md]

**When to use:** Use in `Chrome.CommandBar`; compatibility-normalized flat keys should receive conservative default groups and priorities. [VERIFIED: .planning/phases/18-chrome-v2/18-CONTEXT.md]

**Example:**

```elixir
# Source: existing KeyBar fit_keys/2 pattern upgraded with group/priority.
commands
|> Enum.sort_by(& &1.priority)
|> Enum.reduce_while({[], width}, fn command, {visible, remaining} ->
  rendered = render_hint_text(command)
  hint_width = TextWidth.display_width(rendered)

  if hint_width <= remaining do
    {:cont, {[command | visible], remaining - hint_width}}
  else
    {:halt, {visible, remaining}}
  end
end)
```

### Anti-Patterns to Avoid

- **Screen-built breadcrumb strings:** This violates D-04 through D-06 and makes later screen facelift phases brittle. [VERIFIED: .planning/phases/18-chrome-v2/18-CONTEXT.md]
- **Mode inferred from theme or user role:** Phase 17 explicitly says presentation mode is display metadata keyed by screen id, not authorization or theme state. [VERIFIED: lib/foglet_bbs/tui/presentation.ex]
- **Fake status placeholders:** Optional unread/activity/scope/system atoms must be omitted when unavailable. [VERIFIED: .planning/phases/18-chrome-v2/18-CONTEXT.md]
- **Direct `String.length/1` for chrome width:** `TextWidth` exists specifically for terminal display-width behavior. [VERIFIED: lib/foglet_bbs/tui/text_width.ex]
- **A long-lived `KeyBar` footer:** Phase 18 requires the old simple key-list path to adapt into `CommandBar`, not remain a separate renderer. [VERIFIED: .planning/phases/18-chrome-v2/18-SPEC.md]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Unicode display width | Custom width tables or grapheme math in Chrome | `Foglet.TUI.TextWidth` | It already wraps Raxol display-width splitting and protects grapheme boundaries. [VERIFIED: lib/foglet_bbs/tui/text_width.ex] |
| Terminal layout engine | Manual x/y layout in widgets | Raxol `row`, `column`, `box`, `divider`, and `Layout.Engine.apply_layout/2` tests | Raxol owns view tree layout and positioned rendering. [VERIFIED: docs/raxol/core/ARCHITECTURE.md] |
| Presentation mode routing | Role/theme checks in Chrome | `Foglet.TUI.Presentation.mode_for!/1` | Phase 17 owns exact `:bbs` / `:operator` screen mapping. [VERIFIED: lib/foglet_bbs/tui/presentation.ex] |
| Theme colors | Hardcoded ANSI atoms in new Chrome widgets | `Foglet.TUI.Theme` slots | Local widget policy requires theme-routed styles. [VERIFIED: lib/foglet_bbs/tui/widgets/README.md] |
| Login auth behavior | New auth or navigation logic in Login | Existing Login tests and screen update flow | Phase 18 is chrome-only for Login. [VERIFIED: .planning/phases/18-chrome-v2/18-SPEC.md] |

**Key insight:** Chrome V2 is deceptively small but cross-cutting; hand-rolling per-screen shortcuts would multiply follow-up work across Phases 19 through 25. [VERIFIED: .planning/ROADMAP.md] [VERIFIED: SCREENS.md]

## Common Pitfalls

### Pitfall 1: Keeping `KeyBar` Alive As A Second Footer

**What goes wrong:** Some callers render V2 commands and others still render `KeyBar`, causing inconsistent truncation and grouping. [VERIFIED: .planning/phases/18-chrome-v2/18-SPEC.md]  
**Why it happens:** Existing screens pass simple flat key lists and `ScreenFrame` currently calls `KeyBar.render/2`. [VERIFIED: lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex]  
**How to avoid:** Make `KeyBar` a compatibility wrapper or delete its production use after `CommandBar` lands. [VERIFIED: .planning/phases/18-chrome-v2/18-CONTEXT.md]  
**Warning signs:** Static search still finds `KeyBar.render` in production screen/frame code after migration. [VERIFIED: rg "KeyBar.render"]

### Pitfall 2: Breadcrumbs Consume Screen Body Work

**What goes wrong:** Implementers start redesigning MainMenu, BoardList, PostReader, composer, or operator bodies while adding breadcrumbs. [VERIFIED: .planning/phases/18-chrome-v2/18-SPEC.md]  
**Why it happens:** Breadcrumb examples mention board/thread/tab domain concepts that later phases also redesign. [VERIFIED: SCREENS.md]  
**How to avoid:** Use only already-loaded current board, current thread, compose step, and tab state; defer body primitives to later phases. [VERIFIED: .planning/phases/18-chrome-v2/18-CONTEXT.md]  
**Warning signs:** Phase 18 diffs touch rich rows, board tree row callbacks, post cards, composer editor frame, badges, tables, or inspectors. [VERIFIED: .planning/ROADMAP.md]

### Pitfall 3: Tests Assert Text Presence But Not Layout Safety

**What goes wrong:** Tests pass because expected labels exist, while positioned text overlaps or displaces content at 64x22. [VERIFIED: .planning/phases/18-chrome-v2/18-CONTEXT.md]  
**Why it happens:** Render-tree text collection does not include x/y coordinates. [VERIFIED: test/support/foglet/tui/render_helpers.ex]  
**How to avoid:** Pair pure text tests with `Raxol.UI.Layout.Engine.apply_layout/2` checks that inspect positioned text coordinates and dimensions. [VERIFIED: test/foglet_bbs/tui/layout_smoke_test.exs]  
**Warning signs:** Size tests only use `collect_text_values/1` or `flatten_text/1` and never inspect positioned output. [VERIFIED: test/support/foglet/tui/render_helpers.ex]

### Pitfall 4: Width Budget Ignores Frame Padding And Borders

**What goes wrong:** Breadcrumb/status/commands fit raw terminal width but overflow inside `ScreenFrame` after borders and padding. [VERIFIED: lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex]  
**Why it happens:** `ScreenFrame` uses a bordered, padded box, and `SizeGate` documents chrome overhead. [VERIFIED: lib/foglet_bbs/tui/size_gate.ex]  
**How to avoid:** Compute chrome budgets from effective inner width, or validate through positioned layout at the target terminal sizes. [VERIFIED: test/foglet_bbs/tui/layout_smoke_test.exs]  
**Warning signs:** Tests pass at 80 columns but fail or overlap at 64 columns. [VERIFIED: .planning/REQUIREMENTS.md]

### Pitfall 5: Status Atoms Fabricate Data

**What goes wrong:** Chrome shows fake unread counts, scope labels, or system status because examples mention them. [VERIFIED: .planning/phases/18-chrome-v2/18-CONTEXT.md]  
**Why it happens:** The visual direction lists future optional atoms including unread, terminal size, active theme, and connection state. [VERIFIED: SCREENS.md]  
**How to avoid:** Only render atoms backed by current state; absent values are omitted. [VERIFIED: .planning/phases/18-chrome-v2/18-CONTEXT.md]  
**Warning signs:** Tests expect placeholder values like `unread 0` or `system ok` without source data. [VERIFIED: .planning/phases/18-chrome-v2/18-CONTEXT.md]

## Code Examples

Verified patterns from local sources:

### Width-Safe Truncation

```elixir
# Source: lib/foglet_bbs/tui/text_width.ex
TextWidth.truncate("Foglet ▸ Boards ▸ general", max_width)
TextWidth.display_width(rendered_line) <= max_width
```

### Positioned Layout Contract

```elixir
# Source: test/foglet_bbs/tui/layout_smoke_test.exs
positioned =
  tree
  |> Raxol.UI.Layout.Engine.apply_layout(%{width: 64, height: 22})
  |> List.flatten()

texts = Enum.filter(positioned, &(&1.type == :text))
```

### Existing Time Formatting

```elixir
# Source: lib/foglet_bbs/tui/widgets/chrome/status_bar.ex
clock = ClockFormatter.format(clock_instant(state), user)
"@#{handle} | #{clock}"
```

### Phase 17 Mode Contract

```elixir
# Source: lib/foglet_bbs/tui/presentation.ex
case Presentation.mode_for!(state.current_screen) do
  :bbs -> bbs_status_atoms(state)
  :operator -> operator_status_atoms(state)
end
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Flat centered `[KEY] Description` footer | Grouped command bar with priority truncation | Phase 18 target, specified 2026-04-25 | Planner should create `Chrome.CommandBar` and migrate old key lists through it. [VERIFIED: .planning/phases/18-chrome-v2/18-SPEC.md] |
| Plain `Foglet BBS — {title}` | Breadcrumb model rooted at `Foglet` | Phase 18 target, specified 2026-04-25 | Screens should stop owning final location strings. [VERIFIED: SCREENS.md] |
| `String.length/1`-style layout width | `Foglet.TUI.TextWidth` over Raxol measurement | Phase 16 foundation in current branch | Chrome V2 should use `TextWidth` for all layout-sensitive strings. [VERIFIED: lib/foglet_bbs/tui/text_width.ex] |
| Role/theme-derived presentation assumptions | `Foglet.TUI.Presentation.mode_for!/1` | Phase 17 foundation in current branch | Chrome should use mode metadata, not authorization or theme state. [VERIFIED: lib/foglet_bbs/tui/presentation.ex] |

**Deprecated/outdated:**
- `Chrome.KeyBar` as an independent production footer path is outdated for Phase 18 and should become compatibility-only or be replaced by `Chrome.CommandBar`. [VERIFIED: .planning/phases/18-chrome-v2/18-CONTEXT.md]
- Hardcoded `Foglet BBS — {title}` in status chrome is outdated for Phase 18 breadcrumb requirements. [VERIFIED: lib/foglet_bbs/tui/widgets/chrome/status_bar.ex] [VERIFIED: .planning/REQUIREMENTS.md]

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `132x50` remains the preferred wide test size because Phase 16 already uses it. [ASSUMED] | Validation Architecture | Low; planner can substitute another wide size if project convention changes. |
| A2 | Formatter-level ASCII fallback options are enough for Phase 18, without adding terminal capability detection. [ASSUMED] | Open Questions | Medium; if runtime capability detection is required, planner must add a small capability source or defer fallback automation. |

## Open Questions

1. **Should ASCII fallback be runtime-detectable or option-driven in Phase 18?**
   - What we know: Phase 18 requires deliberate fallback where needed, while Unicode remains primary. [VERIFIED: .planning/phases/18-chrome-v2/18-SPEC.md]
   - What's unclear: Source search found terminal size state and Raxol terminal capability documentation, but no Foglet Chrome-specific runtime flag for Unicode separator fallback. [VERIFIED: rg "unicode|Unicode|ASCII|ascii|fallback|capability|terminal_size"]
   - Recommendation: Implement formatter-level separator/border fallback options and tests, but do not build terminal capability detection in Phase 18. [ASSUMED]

2. **Which exact status atoms have source data today?**
   - What we know: Current `StatusBar` supports guest/handle/time from state. [VERIFIED: lib/foglet_bbs/tui/widgets/chrome/status_bar.ex]
   - What's unclear: Unread/activity/system status may not be available on every named screen. [VERIFIED: .planning/phases/18-chrome-v2/18-CONTEXT.md]
   - Recommendation: Start with handle/time and any already-present scope/tab/system values; omit others until later phases supply data. [VERIFIED: .planning/phases/18-chrome-v2/18-CONTEXT.md]

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| `rtk` | All repo commands | yes | `/opt/homebrew/bin/rtk` | none needed. [VERIFIED: command -v rtk] |
| Elixir / OTP | Compile and tests | yes | Elixir 1.19.5, OTP 28 | none needed. [VERIFIED: rtk elixir --version] |
| Mix | Test and precommit aliases | yes | Mix 1.19.5 | none needed. [VERIFIED: rtk mix --version] |
| PostgreSQL | Full `rtk mix test` alias | no response on 5432 | not detected | Start `docker-compose up postgres` or local Postgres before full suite. [VERIFIED: pg_isready] [VERIFIED: docker-compose.yml] |
| Node | Optional graph tooling only | yes | Node path under nvm v24.11.1 | Graph absent, not blocking. [VERIFIED: command -v node] |

**Missing dependencies with no fallback:**
- PostgreSQL is currently not responding, so full `rtk mix test` may fail until the test database service is started. [VERIFIED: pg_isready]

**Missing dependencies with fallback:**
- Knowledge graph is absent at `.planning/graphs/graph.json`; research continued from local source and planning docs. [VERIFIED: ls .planning/graphs/graph.json]

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | ExUnit with Foglet DataCase for DB-backed layout smoke tests. [VERIFIED: test/foglet_bbs/tui/layout_smoke_test.exs] |
| Config file | `mix.exs` aliases and ExUnit defaults. [VERIFIED: mix.exs] |
| Quick run command | `rtk mix test test/foglet_bbs/tui/widgets/chrome test/foglet_bbs/tui/presentation_test.exs` |
| Full suite command | `rtk mix test` |

### Phase Requirements -> Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| CHROME-01 | Named screens resolve breadcrumbs rooted at `Foglet` | unit | `rtk mix test test/foglet_bbs/tui/widgets/chrome/breadcrumb_bar_test.exs` | no, Wave 0 |
| CHROME-02 | BBS/operator status atom sets differ and omit absent optional data | unit | `rtk mix test test/foglet_bbs/tui/widgets/chrome/status_bar_test.exs` | yes, extend |
| CHROME-03 | Command groups render in priority order and truncate low-priority hints first | unit | `rtk mix test test/foglet_bbs/tui/widgets/chrome/command_bar_test.exs` | no, Wave 0 |
| CHROME-04 | Chrome positioned layout has no overlap at 64x22, 80x24, wide | integration/layout | `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs` | yes, extend |
| CHROME-05 | Old flat key-list path normalizes into `CommandBar` | unit/static | `rtk mix test test/foglet_bbs/tui/widgets/chrome/normalizer_test.exs` | no, Wave 0 |
| LOGIN-01 | Login uses BBS-mode Chrome V2 without auth behavior changes | screen/unit | `rtk mix test test/foglet_bbs/tui/screens/login_test.exs` | yes, extend |

### Sampling Rate

- **Per task commit:** `rtk mix test test/foglet_bbs/tui/widgets/chrome`
- **Per wave merge:** `rtk mix test test/foglet_bbs/tui/widgets/chrome test/foglet_bbs/tui/layout_smoke_test.exs test/foglet_bbs/tui/screens/login_test.exs`
- **Phase gate:** `rtk mix precommit`, after PostgreSQL is available. [VERIFIED: AGENTS.md] [VERIFIED: mix.exs]

### Wave 0 Gaps

- [ ] `test/foglet_bbs/tui/widgets/chrome/breadcrumb_bar_test.exs` - covers CHROME-01.
- [ ] `test/foglet_bbs/tui/widgets/chrome/command_bar_test.exs` - covers CHROME-03.
- [ ] `test/foglet_bbs/tui/widgets/chrome/normalizer_test.exs` - covers CHROME-05.
- [ ] Extend `test/foglet_bbs/tui/widgets/chrome/status_bar_test.exs` for mode-aware status atoms - covers CHROME-02.
- [ ] Extend `test/foglet_bbs/tui/layout_smoke_test.exs` for Chrome V2 positioned size contracts - covers CHROME-04.
- [ ] Extend `test/foglet_bbs/tui/screens/login_test.exs` for BBS-mode Chrome V2 render assertion - covers LOGIN-01.

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|------------------|
| V2 Authentication | yes, preservation only | Do not alter Login authentication behavior; keep existing login tests passing. [VERIFIED: .planning/phases/18-chrome-v2/18-SPEC.md] |
| V3 Session Management | yes, preservation only | Chrome may read session context but must not change session lifecycle. [VERIFIED: AGENTS.md] |
| V4 Access Control | yes, preservation only | Presentation mode is not authorization; access remains in `Foglet.Authorization` and contexts. [VERIFIED: lib/foglet_bbs/tui/presentation.ex] |
| V5 Input Validation | no new user input | Phase 18 renders existing data and commands; it does not add input validation workflows. [VERIFIED: .planning/phases/18-chrome-v2/18-SPEC.md] |
| V6 Cryptography | no | No cryptographic changes are in scope. [VERIFIED: .planning/phases/18-chrome-v2/18-SPEC.md] |

### Known Threat Patterns for TUI Chrome

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| UI-hidden authorization bypass | Elevation of privilege | Treat chrome visibility as advisory only; mutations still require context authorization. [VERIFIED: AGENTS.md] |
| Misleading operator status | Spoofing / Tampering | Omit absent scope/system data rather than rendering fabricated status. [VERIFIED: .planning/phases/18-chrome-v2/18-CONTEXT.md] |
| Auth-flow regression from Login render changes | Tampering | Keep Phase 18 Login changes render-only and run existing Login tests. [VERIFIED: .planning/phases/18-chrome-v2/18-SPEC.md] |

## Sources

### Primary (HIGH confidence)

- `.planning/phases/18-chrome-v2/18-CONTEXT.md` - locked implementation decisions, boundaries, and local code context.
- `.planning/phases/18-chrome-v2/18-SPEC.md` - phase requirements, constraints, and acceptance criteria.
- `.planning/REQUIREMENTS.md` - requirement IDs CHROME-01 through CHROME-05 and LOGIN-01.
- `SCREENS.md` - visual target for Chrome V2, Classic Modern BBS, and Operator Console.
- `AGENTS.md` / `CLAUDE.md` - project directives for SSH-first architecture, TUI widget conventions, and finish line.
- `lib/foglet_bbs/tui/widgets/chrome/*.ex` - current ScreenFrame, StatusBar, and KeyBar implementation.
- `lib/foglet_bbs/tui/text_width.ex` - Phase 16 width helper contract.
- `lib/foglet_bbs/tui/presentation.ex` - Phase 17 mode metadata contract.
- `lib/foglet_bbs/tui/theme.ex` and `lib/foglet_bbs/tui/widgets/README.md` - theme slots and widget rules.
- `docs/raxol/core/ARCHITECTURE.md` and `docs/raxol/getting-started/WIDGET_GALLERY.md` - local Raxol architecture and View DSL reference.

### Secondary (MEDIUM confidence)

- `rtk mix hex.info raxol` - registry metadata confirming Raxol 2.4.0 availability.
- `mix.lock` - resolved dependency versions for Phoenix, Raxol packages, and test tooling.

### Tertiary (LOW confidence)

- None.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - all recommendations use installed/local dependencies and verified project modules.
- Architecture: HIGH - phase context locks the ScreenFrame boundary and local code confirms the current composition path.
- Pitfalls: HIGH - derived from explicit phase decisions and current code shape.
- External ecosystem: MEDIUM - Raxol version was verified via Hex and local vendor files, but no Context7 docs were available for Raxol.

**Research date:** 2026-04-25  
**Valid until:** 2026-05-25 for local architecture; re-check Raxol registry if dependencies are updated before implementation.
