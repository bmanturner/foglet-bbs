# Phase 8: Build local widget library from Raxol primitives — Research

**Researched:** 2026-04-20
**Domain:** Elixir / Raxol TUI — function-form widget wrappers with stateless-facade pattern
**Confidence:** HIGH

## Summary

Phase 8 builds 11 Foglet widgets wrapping Raxol primitives. The critical architectural finding is that **Raxol publishes two parallel surfaces** for nearly every smart component, and the wrappers must choose between them per-widget:

1. **Lightweight DSL functions** in `Raxol.View.Components` — `table/1`, `list/1`, `progress/1`, `tabs/1`, `checkbox/1`, `radio_group/1`, `textarea/1`, `spacer/1`, `divider/1`, `modal/1`, `select/1`, `button/1`. These return plain tagged maps (e.g. `%{type: :table, headers: ..., rows: ...}`) and do not carry any lifecycle. They are the direct output of the block-macro DSL we're already using.

2. **Stateful component modules** in `Raxol.UI.Components.*` — `Input.SelectList`, `Display.Table`, `Display.Tree`, `Display.Progress`, `Input.TextInput`, `Input.Button`, `Input.Checkbox`, `Input.Tabs`, `Input.Menu`, `Progress.Spinner`. These follow `init/1` / `handle_event/3` / `render/2` and support rich props the DSL functions drop on the floor (`enable_search`, `multiple`, `pagination`, `on_submit`, `validator`, `mask_char`, sort/filter, etc.).

The D-14 stateless-facade decision maps one-to-one onto the Viewport pattern Phase 7 already landed: **call the stateful component module's `init/1`, `update/2`, and `render/2` directly as plain functions**, with the wrapper module owning the struct shape and the parent screen holding the struct in `state.screen_state`. No `use Raxol.UI.Components.Base.Component` anywhere in Foglet code — the constraint from REQUIREMENTS.md Locked Decisions is honored because we're *calling* those modules, not *implementing* the behaviour.

Theming integrates through two avenues: (a) per-`text/2` `fg:` / `bg:` keyword args routed from theme slots (proven in every existing widget), and (b) for stateful component modules, the `theme: %{...}` and `style: %{...}` props they already accept (verified in SelectList, Table, Tree, Progress, TextInput, Checkbox, Tabs, Menu). Theme structures needed for component-module props are tiny per-widget maps built inline, not extensions of `Foglet.TUI.Theme`.

**Primary recommendation:** Bundle plans by bucket (Input / Display / List / Progress bundles), four plans total plus one integration plan, because the theme-routing and state-struct patterns repeat across siblings in each bucket. Each widget gets two tests (theme hygiene + smoke render) per D-18. Use `Raxol.Core.Renderer.View` DSL imports in every wrapper — no `use ...Base.Component` anywhere.

## User Constraints (from CONTEXT.md)

### Locked Decisions

**Catalog scope**

- **D-01: Broad smart-component catalog.** Reimplement every smart component with a plausible caller in v1.0–1.4 as a Foglet widget that routes through `Foglet.TUI.Theme`. Speculative inclusion accepted in exchange for consistency and a one-shop library.
- **D-02: Catalog contents (11 widgets).**
  - `Foglet.TUI.Widgets.List.SmartList` — sibling to `List.SelectionList` with search, pagination, multi-select, `max_height`. Inspired by `Raxol.UI.Components.Input.SelectList`.
  - `Foglet.TUI.Widgets.Display.Table` — sortable/filterable/selectable rows with explicit column widths. Wraps `Raxol.UI.Components.Display.Table`.
  - `Foglet.TUI.Widgets.Display.Tree` — hierarchical tree with expand/collapse + keyboard nav. Wraps `Raxol.UI.Components.Display.Tree`. Included despite no current caller (cheap to wrap once the pattern's set).
  - `Foglet.TUI.Widgets.Display.Progress` — animated bar with percentage label. Wraps `Raxol.UI.Components.Display.Progress`.
  - `Foglet.TUI.Widgets.Progress.Spinner` — indeterminate spinner (frame-based, stateless utility). Wraps `Raxol.UI.Components.Progress.Spinner`.
  - `Foglet.TUI.Widgets.Input.TextInput` — single-line input with `on_submit`, `validator`, `mask_char`, `max_length`. Wraps `Raxol.UI.Components.Input.TextInput`.
  - `Foglet.TUI.Widgets.Input.Button` — with `role` (`:primary`, `:secondary`, `:danger`, `:success`), `disabled`, `shortcut`. Wraps `Raxol.UI.Components.Input.Button`.
  - `Foglet.TUI.Widgets.Input.Checkbox` — toggle with `on_toggle`, `disabled`. Wraps `Raxol.UI.Components.Input.Checkbox`.
  - `Foglet.TUI.Widgets.Input.RadioGroup` — single choice from a set. Wraps DSL `radio_group/1`.
  - `Foglet.TUI.Widgets.Input.Tabs` — tab nav with `on_change`, keyboard Left/Right/1–9. Wraps `Raxol.UI.Components.Input.Tabs`.
  - `Foglet.TUI.Widgets.Input.Menu` — nested dropdown/context menu with submenus. Wraps `Raxol.UI.Components.Input.Menu`.

**Catalog exclusions**

- **D-03:** `List.SelectionList` stays lean. Phase 7's delegation to `Raxol.list/1` is the final shape. Richer capabilities land in the new `List.SmartList` sibling.
- **D-04:** Modal and Viewport are Phase 7's work. Phase 8 does not add wrappers for them.
- **D-05:** No general `Input.Textarea` wrapper. `Compose.render_input/3` remains the only MultiLineInput consumer.
- **D-06:** Excluded from catalog: `image`, `code_block`, `markdown_renderer`, chart family.

**Wrapping threshold**

- **D-07:** Minimum wrapper work = theme routing + sensible defaults.
- **D-08:** Defaults live as per-widget module constants. No shared `Widgets.Defaults` module. No expansion of the `Theme` struct with UX tokens.
- **D-09:** Raw Raxol style kwargs are NOT exposed on wrapper APIs. Callers style via theme slots only.

**Namespace organization**

- **D-10:** Raxol-category-aligned sub-namespace buckets under `Foglet.TUI.Widgets.*`: `Input.{TextInput, Button, Checkbox, RadioGroup, Tabs, Menu}`, `Display.{Table, Tree, Progress}`, `Progress.{Spinner}`, `List.{SelectionList, SmartList}`, plus unchanged `Chrome.{ScreenFrame, StatusBar, KeyBar}` and `Post.{MarkdownBody, PostCard}`.
- **D-11:** Existing flat modules `Compose` and `Modal` stay flat — not moved into buckets.
- **D-12:** Discovery via `@moduledoc` + `lib/foglet_bbs/tui/widgets/README.md` index. No top-level `docs/WIDGETS.md`.

**Theming hook + state model**

- **D-13:** Every wrapper takes `theme:` as an explicit keyword arg. Example: `Input.Button.render(label, role: :primary, theme: theme)`.
- **D-14:** Stateless render facade — widget owns struct shape & transitions; parent screen owns lifecycle. Every stateful widget exposes `defstruct`, `init/1` (pure constructor), `handle_event/2` (pure `(event, state) -> {state, action}`), `render/2` (pure `(state, keyword()) -> Raxol.element`). No GenServer, no process per widget instance.
- **D-15:** Key-event routing is the parent screen's responsibility.
- **D-16:** Purely stateless widgets (`Input.Button`, `Input.Checkbox`, `Input.RadioGroup`, `Progress.Spinner`, `Display.Progress`) don't define a state struct — callers pass current value/progress/checked as an arg.

**Implementation depth + test bar**

- **D-17:** Every catalog entry ships with full implementation + tests. No stubs.
- **D-18:** Test bar per widget = theme hygiene (no hardcoded colors; rendering with an alternate theme produces different color output) + smoke render (`render/2` returns a non-nil Raxol element with expected top-level shape).

### Claude's Discretion

- **Exact state struct shapes.** Planner defines `defstruct` fields per widget. Guidance: mirror Raxol's component module option keys where they cleanly apply, plus Foglet-specific fields.
- **Action atoms returned from `handle_event/2`.** Planner picks conventions (`:item_selected`, `:submitted`, `:cancelled`). Keep consistent across widgets where meaning is parallel.
- **Plan breakdown.** Planner decides one-per-plan (11 plans) vs bucket bundles (Input / Display / List / Progress).
- **README index format.** Planner decides table vs list.
- **Default values for module constants.** Planner picks specific defaults (border style, page size, spinner style, tabs active-indicator).

### Deferred Ideas (OUT OF SCOPE)

- `docs/WIDGETS.md` top-level catalog doc.
- `Input.Textarea` general wrapper.
- Expanding `Foglet.TUI.Theme` with non-color UX tokens.
- Shared `Foglet.TUI.Widgets.Defaults` module.
- Wrapping `image`, `code_block`, `markdown_renderer`, charts.
- Moving `Compose` and `Modal` into buckets.

## Project Constraints (from CLAUDE.md)

Directives extracted from `./CLAUDE.md` that apply to every Phase 8 plan:

- **Precommit gate.** `mix precommit` must pass — runs `compile --warnings-as-errors`, `format`, `credo --strict`, `sobelow`, `dialyzer`. Planner should include a precommit run in the final verification step of every plan.
- **HTTP:** Use `Req`, not `:httpoison`/`:tesla`/`:httpc` — not relevant to widget rendering but noted for completeness.
- **Date/time:** Prefer stdlib (`Time`, `Date`, `DateTime`, `Calendar`). `Foglet.TimeAgo` is already in place for LIST-03.
- **Raxol docs pointer:** Whenever reading/writing Raxol code, start at `docs/raxol/README.md` and reach for `docs/raxol/getting-started/WIDGET_GALLERY.md` for primitives. ADRs live in `docs/raxol/adr/`.
- **Elixir gotchas (must apply in every widget):**
  - Block expressions rebind, don't mutate — `if/case/cond` used inside a `handle_event/2` must return the new state as the block value, never rebind `state` inside a branch.
  - Never nest multiple modules in the same file — one wrapper per file.
  - Structs don't implement `Access` — use `struct.field` directly, never `struct[:field]`.
  - OTP primitives need `name:` in child spec — irrelevant here (no GenServers per D-14) but reinforces that we're not introducing processes.
- **Test guidelines:**
  - `start_supervised!/1` for any test-owned processes — irrelevant here (no processes) but implies tests should be purely functional.
  - Avoid `Process.sleep/1` and `Process.alive?/1` — trivially satisfied because widget tests are pure render calls.
- **Phoenix router scope:** Not applicable.
- **Ecto `cast/3`:** Not applicable.

## Phase Requirements

Phase 8 has no ROADMAP-level REQ IDs (per CONTEXT and ROADMAP). The phase-local requirements are derived from CONTEXT.md D-## decisions. Each widget in D-02 produces an implicit requirement; collectively they bind to the validation dimensions in this document.

| ID | Description | Research Support |
|----|-------------|------------------|
| REQ-W-01 | `Foglet.TUI.Widgets.List.SmartList` wraps `Raxol.UI.Components.Input.SelectList` as a stateless facade with theme-routed colors | SelectList source read, theme/style prop shape verified |
| REQ-W-02 | `Foglet.TUI.Widgets.Display.Table` wraps `Raxol.UI.Components.Display.Table` with sortable/filterable/selectable option surface | Table source read, theme slots map to `:box / :header / :row / :selected_row` |
| REQ-W-03 | `Foglet.TUI.Widgets.Display.Tree` wraps `Raxol.UI.Components.Display.Tree` with expand/collapse and keyboard nav | Tree source read, `MapSet expanded` pattern known |
| REQ-W-04 | `Foglet.TUI.Widgets.Display.Progress` wraps `Raxol.UI.Components.Display.Progress` with percentage + label | Progress source read; stateless (D-16) — no state struct |
| REQ-W-05 | `Foglet.TUI.Widgets.Progress.Spinner` wraps `Raxol.UI.Components.Progress.Spinner.spinner/3` as a pure frame-based utility | Spinner is already pure (no lifecycle needed); style atom map |
| REQ-W-06 | `Foglet.TUI.Widgets.Input.TextInput` wraps `Raxol.UI.Components.Input.TextInput` with `on_submit`/`validator`/`mask_char`/`max_length` | TextInput source read, state shape known |
| REQ-W-07 | `Foglet.TUI.Widgets.Input.Button` with `role`/`disabled`/`shortcut` | Button source; stateless (D-16) |
| REQ-W-08 | `Foglet.TUI.Widgets.Input.Checkbox` with `on_toggle`/`disabled` | Checkbox source; stateless (D-16) |
| REQ-W-09 | `Foglet.TUI.Widgets.Input.RadioGroup` — builds from `text/2` primitives (no suitable Raxol component module exists; `radio_group/1` DSL is a lightweight map only) | Verified by reading `radio_group_demo.ex` which itself builds from `text/2` |
| REQ-W-10 | `Foglet.TUI.Widgets.Input.Tabs` wraps `Raxol.UI.Components.Input.Tabs` with `on_change` + Left/Right/1–9 keys | Tabs source read |
| REQ-W-11 | `Foglet.TUI.Widgets.Input.Menu` wraps `Raxol.UI.Components.Input.Menu` with nested submenus | Menu source read, `open_path` + `cursor` shape known |
| REQ-W-12 | `lib/foglet_bbs/tui/widgets/README.md` indexes every catalog entry with one-line descriptions and links | D-12 |
| REQ-W-13 | Every wrapper passes the theme-hygiene + smoke-render test bar | D-18 |

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Widget theme resolution (read from `Foglet.TUI.Theme`) | Wrapper module (`Foglet.TUI.Widgets.*`) | — | Phase 1 D-01 locked theme as session struct; wrappers consume it as opaque arg |
| Widget state lifecycle (hold struct, route events) | Parent screen (`Foglet.TUI.Screens.*`) | Wrapper's `init/1`/`handle_event/2` (pure functions) | D-14/D-15 — screen owns lifecycle, widget provides pure transitions |
| Widget render output | Wrapper's `render/2` | Raxol DSL (`Raxol.Core.Renderer.View` + `Raxol.View.Components`) | `render/2` builds element tree from DSL helpers plus theme slots |
| Smart-component behaviour (search, pagination, sort/filter, expand/collapse, menu navigation) | Stateful Raxol component module called as plain functions (e.g., `Raxol.UI.Components.Input.SelectList.init/1`) | Wrapper adapts the component's state shape into its own `defstruct` | Mirrors Phase 7's Viewport pattern (07-PATTERNS.md §Viewport Plain Module Usage) |
| Keyboard event translation | Parent screen's `handle_key/2` decides which events to forward | Wrapper's `handle_event/2` transforms event → new state + action atom | D-15 is explicit: screen decides which events widget sees |
| Color/style emission | `text/2` call sites inside `render/2` | Theme slot lookup (`theme.primary.fg`, `theme.selected.bg`, etc.) | Every existing widget does this; D-09 forbids raw style kwargs on wrapper APIs |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Raxol (vendored) | as-installed in `vendor/raxol` | TUI rendering primitives and stateful component modules | Sole UI layer for the SSH TUI; already in use across all existing widgets |
| `Raxol.Core.Renderer.View` | same | Block-macro DSL: `column do…end`, `row do…end`, `box do…end`, `text/2`, `spacer/1`, `divider/1` | Every existing Foglet widget imports this; function-form locked by REQUIREMENTS.md |
| `Raxol.View.Components` | same | Lightweight function-form wrappers returning tagged maps (`list/1`, `table/1`, `tabs/1`, `progress/1`, `radio_group/1`) | Used where the DSL shape is sufficient (simple non-interactive display); NOT where stateful behaviour is needed |
| `Raxol.UI.Components.*` (called as plain modules) | same | Stateful components with `init/1`/`handle_event/3`/`render/2` | D-14 stateless facade — call these as plain functions without `use ...Base.Component` |
| ExUnit | stdlib | Testing | Already used in every widget test |

[VERIFIED: vendored Raxol source in `/vendor/raxol/lib/raxol/`; existing widget imports in `/lib/foglet_bbs/tui/widgets/**/*.ex`]

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `Foglet.TUI.Theme` | local | Theme struct with 10 slots (`border, primary, dim, accent, title, error, warning, selected, unselected, status_bar`) | Every wrapper's `render/2` reads from here; NEVER expanded in this phase (D-08) |
| `Raxol.Core.Defaults` | dep `raxol_core` | Canonical default magic numbers (`page_size 10`, `terminal_width 80`, `selected_style %{reverse: true}`) | Reference for choosing our module-constant defaults, not for direct use (D-08 says constants live per-widget) |

[VERIFIED: `/deps/raxol_core/lib/raxol/core/defaults.ex`, `/lib/foglet_bbs/tui/theme.ex`]

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Calling `Raxol.UI.Components.*.render/2` directly as plain functions | `use Raxol.UI.Components.Base.Component` | REJECTED — locked by REQUIREMENTS.md "Function-form only" |
| Stateful component module (e.g., `Raxol.UI.Components.Input.Tabs`) | Lightweight DSL function (`Raxol.View.Components.tabs/1`) | DSL function drops all interactive behaviour (just returns `%{type: :tabs, tabs: ..., active: ...}`); fine for pure display, wrong for interaction. `Input.Tabs` is the right choice because D-02 mandates `on_change` + keyboard nav |
| Per-widget theme struct extension | Keep 10 locked slots, add slots only if the user re-opens D-08 | DEFERRED — D-08 forbids for Phase 8. If a widget *needs* a color not in current slots (e.g., `selected_row_bg` for Table), the research finding is that existing slots cover every case because the `Theme struct` uses hex strings the component modules accept directly |

**Installation:** No new deps required. All Raxol modules already vendored/installed. [VERIFIED: `mix.exs` unchanged across Phase 1–7].

## Architecture Patterns

### System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│  Parent Screen Module (lib/foglet_bbs/tui/screens/*.ex)         │
│                                                                 │
│  - holds widget state in state.screen_state[:<screen>][:widget] │
│  - routes key events (D-15)                                     │
└────────────┬───────────────────────────────────┬────────────────┘
             │                                   │
             │ `WidgetMod.handle_event(evt, st)` │ `WidgetMod.render(st, theme: t)`
             │ pure (event, state) -> {state, action}   │  pure render
             │                                   │
┌────────────▼───────────────────────────────────▼────────────────┐
│  Foglet Wrapper Module (lib/foglet_bbs/tui/widgets/<bucket>/…)  │
│                                                                 │
│  - defstruct (D-14, stateful widgets only)                      │
│  - @default_* module constants (D-08)                           │
│  - init/1  : pure constructor                                   │
│  - handle_event/2 : pure transition                             │
│  - render/2  : pure element tree                                │
└────────────┬───────────────────────────────────┬────────────────┘
             │                                   │
             │ state delegation for behaviour    │ DSL + theme slots
             │                                   │
┌────────────▼────────────┐         ┌────────────▼────────────────┐
│  Raxol.UI.Components.*  │         │  Raxol.Core.Renderer.View   │
│  called as plain funcs  │         │  column, row, box, text,    │
│  (init/1, update/2,     │         │  spacer, divider            │
│   render/2)             │         │  +                          │
│                         │         │  Raxol.View.Components      │
│  SelectList, Table,     │         │  table, list, radio_group,  │
│  Tree, TextInput,       │         │  tabs, progress, etc.       │
│  Checkbox, Tabs, Menu,  │         │  (lightweight DSL maps)     │
│  Button, Progress       │         │                             │
└─────────────────────────┘         └─────────────────────────────┘
             │                                   │
             └───────────────┬───────────────────┘
                             │
                     ┌───────▼──────────┐
                     │ Raxol renderer   │
                     │ (element tree)   │
                     └──────────────────┘
```

**Primary data flow:** Key event → screen's `handle_key/2` decides routing → (if widget event) `WidgetMod.handle_event(event, widget_struct)` → returns `{new_struct, action_atom | nil}` → screen updates its `screen_state` and handles the action (e.g., `:item_selected` fires a screen-level transition). Render pass: screen's `view/1` calls `WidgetMod.render(widget_struct, theme: theme, width: w)` → wrapper consults theme slots + module-constant defaults → returns an element tree built from Raxol DSL primitives.

### Recommended Project Structure

```
lib/foglet_bbs/tui/widgets/
├── README.md                      # D-12: index of every catalog entry
├── chrome/                        # unchanged (Phase 1)
│   ├── screen_frame.ex
│   ├── status_bar.ex
│   └── key_bar.ex
├── compose.ex                     # unchanged (D-11)
├── modal.ex                       # unchanged (D-11, Phase 7 thin adapter)
├── post/                          # unchanged (Phase 1–3)
│   ├── markdown_body.ex
│   └── post_card.ex
├── list/
│   ├── selection_list.ex          # unchanged (D-03)
│   ├── list_row.ex                # unchanged
│   └── smart_list.ex              # NEW (D-02)
├── display/                       # NEW bucket
│   ├── table.ex
│   ├── tree.ex
│   └── progress.ex
├── progress/                      # NEW bucket (single sibling — Spinner)
│   └── spinner.ex
└── input/                         # NEW bucket
    ├── text_input.ex
    ├── button.ex
    ├── checkbox.ex
    ├── radio_group.ex
    ├── tabs.ex
    └── menu.ex

test/foglet_bbs/tui/widgets/
├── list/
│   └── smart_list_test.exs
├── display/
│   ├── table_test.exs
│   ├── tree_test.exs
│   └── progress_test.exs
├── progress/
│   └── spinner_test.exs
└── input/
    ├── text_input_test.exs
    ├── button_test.exs
    ├── checkbox_test.exs
    ├── radio_group_test.exs
    ├── tabs_test.exs
    └── menu_test.exs
```

### Pattern 1: Stateless Widget (D-16)

**What:** Widget takes all state via function args; no `defstruct`, no `init/1`, no `handle_event/2`. Only `render/2` (or `render/3`).
**When to use:** `Input.Button`, `Input.Checkbox`, `Input.RadioGroup`, `Progress.Spinner`, `Display.Progress`.
**Template:** `lib/foglet_bbs/tui/widgets/chrome/key_bar.ex` (positional args + explicit theme kwarg + module-constant defaults).

```elixir
# Source: mirrors lib/foglet_bbs/tui/widgets/chrome/key_bar.ex
defmodule Foglet.TUI.Widgets.Input.Button do
  @moduledoc """
  Themed button widget (D-02, D-13, D-16).

  Stateless — caller supplies label + role + state flags on every render.

  Honours:
    * D-07/D-09 — colors come from theme slots only
    * D-13     — `theme:` is an explicit keyword arg
    * D-16     — no state struct (purely stateless)
  """

  import Raxol.Core.Renderer.View
  alias Foglet.TUI.Theme

  @default_role :secondary

  @type role :: :primary | :secondary | :danger | :success

  @doc """
  Renders a button label.

  Options:
    * `:role` — one of `:primary`, `:secondary`, `:danger`, `:success` (default `:secondary`)
    * `:disabled` — boolean, default `false`
    * `:shortcut` — optional string hint (e.g., `"Ctrl+S"`)
    * `:theme` — required, the `%Foglet.TUI.Theme{}` struct
  """
  @spec render(String.t(), keyword()) :: any()
  def render(label, opts) when is_binary(label) and is_list(opts) do
    role = Keyword.get(opts, :role, @default_role)
    disabled = Keyword.get(opts, :disabled, false)
    shortcut = Keyword.get(opts, :shortcut)
    %Theme{} = theme = Keyword.fetch!(opts, :theme)

    {fg, style} = role_style(role, disabled, theme)
    content = if shortcut, do: " #{label} (#{shortcut}) ", else: " #{label} "

    text(content, fg: fg, style: style)
  end

  defp role_style(_any, true, theme),       do: {theme.dim.fg, [:dim]}
  defp role_style(:primary, false, theme),  do: {theme.accent.fg, [:bold]}
  defp role_style(:danger, false, theme),   do: {theme.error.fg, [:bold]}
  defp role_style(:success, false, theme),  do: {theme.primary.fg, [:bold]}
  defp role_style(_secondary, false, theme), do: {theme.primary.fg, []}
end
```

### Pattern 2: Stateful Widget (D-14)

**What:** Widget owns a `defstruct` and exposes `init/1`, `handle_event/2`, `render/2`. Parent screen holds the struct. No process.
**When to use:** `List.SmartList`, `Display.Table`, `Display.Tree`, `Input.TextInput`, `Input.Tabs`, `Input.Menu`.
**Template:** `lib/foglet_bbs/tui/widgets/compose.ex` (for the shape of `translate_key/1` + `render_input/3`) + Phase 7's Viewport plain-module-usage pattern from `07-PATTERNS.md` §Viewport.

```elixir
# Source: mirrors Phase 7 Viewport plain-module pattern (07-PATTERNS.md)
#         + compose.ex translate_key/1 shape
defmodule Foglet.TUI.Widgets.Display.Tree do
  @moduledoc """
  Hierarchical tree view with expand/collapse + keyboard nav (D-02, D-14).

  Stateless facade over `Raxol.UI.Components.Display.Tree` —
  caller holds the struct, we just transform events and render.

  Honours:
    * D-07/D-09 — theme-routed colors only, no raw style kwargs
    * D-13     — `theme:` keyword arg
    * D-14     — `init/1` + `handle_event/2` + `render/2` (no process)
  """

  import Raxol.Core.Renderer.View
  alias Foglet.TUI.Theme
  alias Raxol.UI.Components.Display.Tree, as: RaxolTree

  @default_indent_size 2

  @type tree_node :: %{
          id: atom(),
          label: String.t(),
          children: [tree_node()]
        }

  @type action :: :node_activated | :node_expanded | :node_collapsed | nil

  defstruct [:raxol_state, :last_action]

  @type t :: %__MODULE__{
          raxol_state: map(),
          last_action: action()
        }

  @doc "Pure constructor; opts: `:nodes`, `:id`, `:indent_size`."
  @spec init(keyword()) :: t()
  def init(opts) do
    nodes = Keyword.get(opts, :nodes, [])
    id = Keyword.get(opts, :id, "tree-#{:erlang.unique_integer([:positive])}")
    indent = Keyword.get(opts, :indent_size, @default_indent_size)

    {:ok, raxol_state} =
      RaxolTree.init(id: id, nodes: nodes, indent_size: indent)

    %__MODULE__{raxol_state: raxol_state, last_action: nil}
  end

  @doc "Pure (event, state) -> {state, action | nil}."
  @spec handle_event(map(), t()) :: {t(), action()}
  def handle_event(event, %__MODULE__{raxol_state: rs} = st) do
    raxol_event = %Raxol.Core.Events.Event{type: :key, data: event}
    {new_rs, _cmds} = RaxolTree.handle_event(raxol_event, rs, %{})
    action = derive_action(rs, new_rs, event)
    {%{st | raxol_state: new_rs, last_action: action}, action}
  end

  @doc "Pure render — takes state + `theme:` keyword."
  @spec render(t(), keyword()) :: any()
  def render(%__MODULE__{raxol_state: rs}, opts) do
    %Theme{} = theme = Keyword.fetch!(opts, :theme)

    # Call the Raxol component's render directly.
    # It returns a %{type: :column, children: ..., style: ...} tagged map.
    rendered = RaxolTree.render(rs, %{})

    # Wrap in a box that applies our theme border if desired
    box style: %{border_fg: theme.border.fg, padding: 0} do
      rendered
    end
  end

  defp derive_action(before, after_state, %{key: :enter}) do
    cond do
      MapSet.size(after_state.expanded) > MapSet.size(before.expanded) -> :node_expanded
      MapSet.size(after_state.expanded) < MapSet.size(before.expanded) -> :node_collapsed
      true -> :node_activated
    end
  end

  defp derive_action(_, _, _), do: nil
end
```

**Key idea:** the wrapper struct holds the Raxol component's map state inside a field (`:raxol_state`). This lets us (a) keep the D-14 API shape (our own `init/1`/`handle_event/2`/`render/2` with simple action atoms), (b) delegate all the complex state transitions to the Raxol source of truth, and (c) never need `use ...Base.Component`. `handle_event/2` translates a plain key-event map into a `%Event{type: :key, data: ...}` struct before calling the Raxol function, and returns a simple action atom alongside the new state.

### Pattern 3: DSL-Only Wrapping (RadioGroup)

**What:** Wrap a DSL function (not a component module) when no stateful component module exists.
**When to use:** `Input.RadioGroup` (verified: the `radio_group_demo.ex` in Raxol itself builds radio groups from `text/2` primitives — there is no `Raxol.UI.Components.Input.RadioGroup` module).

```elixir
# Source: reproduces the pattern from
# vendor/raxol/lib/raxol/playground/demos/radio_group_demo.ex
defmodule Foglet.TUI.Widgets.Input.RadioGroup do
  @moduledoc """
  Themed radio-group widget (D-02, D-13, D-16).

  Stateless — caller passes `selected_index`. No Raxol component module
  exists for radio groups (verified against Raxol source); we compose
  from `text/2` primitives using the same mark convention as Raxol's
  own radio_group_demo.

  Honours:
    * D-07/D-09 — theme-routed colors only
    * D-13     — `theme:` keyword arg
    * D-16     — no state struct (purely stateless)
  """

  import Raxol.Core.Renderer.View
  alias Foglet.TUI.Theme

  @on_marker "(o)"
  @off_marker "( )"

  @spec render([String.t()], non_neg_integer(), keyword()) :: any()
  def render(options, selected_index, opts) when is_list(options) do
    %Theme{} = theme = Keyword.fetch!(opts, :theme)

    rows =
      options
      |> Enum.with_index()
      |> Enum.map(fn {opt, idx} ->
        mark = if idx == selected_index, do: @on_marker, else: @off_marker
        prefix = if idx == selected_index, do: "> ", else: "  "
        fg = if idx == selected_index, do: theme.selected.fg, else: theme.unselected.fg
        text("#{prefix}#{mark} #{opt}", fg: fg)
      end)

    column style: %{gap: 0} do
      rows
    end
  end
end
```

### Anti-Patterns to Avoid

- **`use Raxol.UI.Components.Base.Component`** — violates REQUIREMENTS.md Locked Decisions. Raxol's stateful component modules use this internally; we call those modules as plain functions, we never implement the behaviour ourselves.
- **Exposing raw Raxol style kwargs on wrapper APIs** (D-09) — e.g., `Input.Button.render(label, fg: :cyan, bg: :red, theme: t)`. If a caller wants a one-off color, add a theme slot; the library's consistency wall is the point.
- **Using `String.to_atom/1` on untrusted input** — callers-decide behaviour via atom action codes is fine, but do not atomize user-supplied strings inside widgets. `mix credo --strict` will catch this.
- **Pattern-matching `struct[:field]`** — Elixir structs don't implement `Access`. Always use `struct.field`. Caught by `dialyzer` via the precommit gate.
- **Nested modules in the same file** — every widget in its own file, one `defmodule` per `.ex`.
- **Rebinding `state` inside `if/case` branches** (CLAUDE.md gotcha) — return the new state as the block value:
  ```elixir
  # INVALID inside handle_event/2
  if some_cond do
    state = %{state | foo: bar}
  end

  # VALID
  state =
    if some_cond do
      %{state | foo: bar}
    else
      state
    end
  ```
- **Calling Raxol component `update/2` or `render/2` with `nil` context** when the component expects a map — always pass `%{}` as context (matches Phase 7 Viewport pattern).
- **Per-widget theme struct extensions** — D-08 forbids expanding `Foglet.TUI.Theme` in this phase. If a color isn't in a slot, the answer is "use the nearest slot" or "defer to a future theme-expansion phase", not "add a slot for one widget".

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Scrollable pagination of a long list | Custom `scroll_offset` + slice math | `Raxol.UI.Components.Input.SelectList` (for interactive scroll) or `Raxol.UI.Components.Display.Viewport` (for display-only scroll, Phase 7 pattern) | SelectList already has `scroll_offset`, `visible_height`, `page_size`, `current_page`, `show_pagination`; reinventing is 200+ lines of bug-prone edge cases |
| Type-to-search filtering | Custom key buffer + filtering | `SelectList` with `enable_search: true` + `searchable_fields:` | SelectList already has `search_buffer`, `search_timer`, `is_filtering`, `filtered_options`; the state shape is battle-tested |
| Multi-select with selection persistence across filter changes | Custom `MapSet` + filter-aware selection logic | `SelectList` with `multiple: true` | `selected_indices: MapSet.t()` handles it; our wrapper just exposes the flag |
| Sortable columns in a table | Manual Enum.sort/2 + comparator state | `Raxol.UI.Components.Display.Table` with `options: %{sortable: true}` + `update({:sort, column}, state)` | Table already tracks `sort_by`, `sort_direction`, cycles asc/desc/none |
| Filterable table rows | Custom filter input + predicate application | Table with `options: %{searchable: true}` + `update({:filter, term}, state)` | Table holds `filter_term` and re-slices on every update |
| Tree expand/collapse state | Custom map/set + visible-node computation | `Raxol.UI.Components.Display.Tree` | Holds `expanded :: MapSet.t()` and computes `visible_nodes/1` already; our wrapper delegates |
| Menu navigation with nested submenus | Custom `open_path` stack + cursor logic | `Raxol.UI.Components.Input.Menu` | Handles `open_path :: [atom()]`, cursor tracking, disabled-skip navigation, Escape semantics |
| Tab bar with keyboard nav (Left/Right/Home/End/1–9) | Custom keyboard router | `Raxol.UI.Components.Input.Tabs` | Already handles all 13 keys with wrapping |
| Animated progress bar with percentage label | Custom animation tick + bar glyphs | `Raxol.UI.Components.Display.Progress` | Handles `animation_frame`, `animation_speed`, `animation_chars` sub-cell progression |
| Spinner animation frames | Custom frame arrays | `Raxol.UI.Components.Progress.Spinner.spinner/3` | 10 styles baked in (`:dots`, `:line`, `:circle`, `:arrow`, `:bounce`, `:pulse`, `:wave`, `:dots3`, `:square`, `:flip`); stateless (caller passes frame number) |
| Text-input cursor movement + backspace/delete/mask/validator | Custom character buffer | `Raxol.UI.Components.Input.TextInput` + `TextInput.KeyHandler` | Handles cursor_pos, mask_char, max_length, validator, on_submit/on_change/on_cancel |
| Checkbox toggle | Custom boolean tracking | `Raxol.UI.Components.Input.Checkbox` | Trivial, but consistency demands using the same module for the `on_toggle` callback surface |

**Key insight:** Every smart behaviour in D-02 is already implemented inside a Raxol component module. The Foglet wrapper's job is *exclusively* (a) theme routing and (b) picking sensible defaults. If a wrapper is doing anything more than "build a theme map from slots → call RaxolComponent.init/1 / update/2 / render/2 → emit result inside a themed box", it's doing too much.

## Runtime State Inventory

> This phase is additive — pure new code. No rename, refactor, or migration.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — no persistence touched | None |
| Live service config | None — no external services touched | None |
| OS-registered state | None | None |
| Secrets/env vars | None | None |
| Build artifacts | New `.ex` files land in `lib/foglet_bbs/tui/widgets/**/`; new `.exs` files in `test/foglet_bbs/tui/widgets/**/`. Mix compiles them in place; no stale artifacts | None |

**Nothing found in category:** All five categories confirmed empty — Phase 8 is purely additive code.

## Common Pitfalls

### Pitfall 1: Confusing `Raxol.View.Components.tabs/1` with `Raxol.UI.Components.Input.Tabs`

**What goes wrong:** A naïve wrapper imports `Raxol.View.Components` and calls `tabs(tabs: [...], active: 0)` — the result is a plain `%{type: :tabs, tabs: ..., active: ..., ...}` map with no interactive behaviour. Keyboard events go nowhere. The wrapper "works" in rendering but is inert.
**Why it happens:** The gallery lists both forms on the same page; the DSL form is one line shorter so developers reach for it first.
**How to avoid:** For every widget in D-02, the wrapper must use the stateful `Raxol.UI.Components.*` module (not the `Raxol.View.Components` DSL function) whenever the widget needs keyboard interaction. The DSL function is appropriate only for non-interactive display (e.g., a static progress bar reading a computed percentage). The research below documents the choice per-widget.
**Warning signs:** Widget renders correctly but `handle_event/2` never produces new state, or the wrapper has no `init/1` when D-14 says it should.

### Pitfall 2: Raxol component modules use `Keyword.get/2` on props when the caller passes a map

**What goes wrong:** Several Raxol component `init/1` functions use `Keyword.get(props, :key, default)` — this fails silently when `props` is a `Map` because `Keyword.get/2` on a map returns `nil`. Verified in `Tree.init/1`, `Tabs.init/1`, `Menu.init/1`.
**Why it happens:** Inconsistent prop-shape conventions inside Raxol — some components accept keyword lists, some accept maps, some accept either.
**How to avoid:** When calling a Raxol component's `init/1` from a wrapper, **always pass a keyword list**, not a map. E.g., `RaxolTree.init(id: "…", nodes: […])` not `RaxolTree.init(%{id: "…", nodes: […]})`. The exception is `SelectList.init/1` which explicitly normalizes props via a `validate_props!/1` helper and accepts maps.
**Warning signs:** Default values applied everywhere, callbacks never fire, id is always the random generated one.

### Pitfall 3: Raxol component render paths sometimes produce element-struct shapes, sometimes tagged maps

**What goes wrong:** Tests that assert on tree shape via pattern-matching (e.g., `assert %{type: :column, children: [...]} = result`) may fail when a Raxol upgrade changes the element representation.
**Why it happens:** Raxol is evolving; `%Raxol.Core.Renderer.View.Element{}` structs and plain `%{type: ...}` tagged maps both appear in the render output, depending on which DSL helper produced them.
**How to avoid:** Follow the existing test pattern from `markdown_body_test.exs:7–25` and `list_row_test.exs:9–26`: the `flatten_text/1` + `collect_text/2` helpers accept both shapes because they use `Map.get(node, :content)` and `Map.get(node, :children)` without pattern-matching on the outer struct. Copy this helper verbatim into every new widget test.
**Warning signs:** Tests pass locally but fail after a Raxol version bump; or tests assert on `%{type: :column}` but the actual shape is `%Raxol.Core.Renderer.View.Element{type: :column, …}`.

### Pitfall 4: `style:` on a `column`/`row` macro must be a keyword list, not a map

**What goes wrong:** Calling `column style: %{gap: 0, padding: 1}` crashes the compile with `validate_keyword_opts` error.
**Why it happens:** The block-macro DSL calls `validate_keyword_opts/2` on its outer options and expects a keyword list; only `style:` values can be maps. The mistake is passing the whole opts as a map.
**How to avoid:** Outer opts to `column`/`row`/`box` are always keywords; `style:` values are maps. Pattern:
```elixir
column style: %{gap: 0, justify_content: :space_between} do
  [...]
end
```
**Warning signs:** Compile-time `ArgumentError: expected keyword list, got map` in widget rendering code.

### Pitfall 5: Raxol's `handle_event/3` expects a `%Raxol.Core.Events.Event{}` struct; Foglet's event dispatch uses plain key-event maps

**What goes wrong:** Calling `RaxolComponent.handle_event(%{key: :down}, state, %{})` — Raxol pattern-matches on `%Event{type: :key, data: %{key: :down}}` and the clause fails.
**Why it happens:** Foglet uses bare `%{key: atom, char: ...}` maps in `handle_key/2`; Raxol wraps them in `%Event{}` structs before routing.
**How to avoid:** In the wrapper's `handle_event/2`, wrap the incoming Foglet key-event map before delegating:
```elixir
raxol_event = %Raxol.Core.Events.Event{type: :key, data: event}
{new_rs, _cmds} = RaxolComponent.handle_event(raxol_event, state.raxol_state, %{})
```
**Warning signs:** Widget's `handle_event/2` is called but the state never changes.

### Pitfall 6: Tabs' `1–9` number-key shortcut may conflict with digit input elsewhere

**What goes wrong:** A screen uses `Input.Tabs` alongside another widget that accepts digit input (e.g., a future sysop screen with port-number input). Pressing `5` switches the tab instead of typing.
**Why it happens:** `Raxol.UI.Components.Input.Tabs.handle_event/3` unconditionally consumes `%{key: :char, char: ch}` where `ch in ~w(1 2 3 4 5 6 7 8 9)` (verified in source, lines 77–89).
**How to avoid:** D-15 already places key routing in the parent screen's hands. When a screen mixes Tabs with digit-accepting input, it must gate which widget receives the event. The planner should add a note to the `Input.Tabs` `@moduledoc` explaining this, and the wrapper's `handle_event/2` should honor what the screen sent without second-guessing (callers already filtered).
**Warning signs:** Bug reports where digits do the wrong thing.

### Pitfall 7: Menu expects a full `%{id, label, children, disabled, shortcut}` shape per item; missing keys crash `find_item/2`

**What goes wrong:** Constructing menu items as `%{label: "File", children: [...]}` without `:id` — `Menu.find_item/2` recurses on `children` via `[%{id: id} = item | _rest]` pattern-match, which fails for items without `:id`.
**Why it happens:** Raxol's menu representation is opinionated; every item needs `:id`.
**How to avoid:** The wrapper's `init/1` normalizes caller-supplied menu items, filling in `:id` with `:erlang.unique_integer/1` if absent, `:disabled` with `false`, `:shortcut` with `nil`. Planner should document the item shape in the `@moduledoc`.
**Warning signs:** FunctionClauseError inside `Raxol.UI.Components.Input.Menu.find_item/2`.

### Pitfall 8: `Display.Progress` renders with `:green`/`:black`/`:white` hardcoded defaults when theme is an empty map

**What goes wrong:** Calling `Progress.init(%{progress: 0.5, width: 40})` without `:theme` → the `extract_colors/1` helper (verified at `display/progress.ex:165–172`) uses `Map.get(base_style, :fg, :green)` — i.e., hardcoded atom defaults leak into output.
**Why it happens:** Raxol's Progress component pre-dates strict theming conventions.
**How to avoid:** The wrapper must construct a `theme:` prop map with `fg`, `bg`, `border`, `text` populated from our slots (`theme.primary.fg`, `theme.border.fg`, `theme.dim.fg`, etc.) before calling `Progress.init/1`. The theme-hygiene test will catch this — `inspect(tree) =~ ":green"` must `refute`.
**Warning signs:** Test fails with `":green" in serialized output`; progress bar ignores Foglet palette.

### Pitfall 9: `Raxol.UI.Components.Display.Tree` requires `:nodes` as a list of `%{id, label, children, data}` maps, not keyword lists or structs

**What goes wrong:** Passing `[{:id, "src", label: "src", children: []}]` or a struct-based representation. Tree's `visible_nodes/1` and `find_parent/2` pattern-match on map keys.
**Why it happens:** Same as #7 — opinionated shape.
**How to avoid:** `@moduledoc` documents the node shape explicitly, and `init/1` can accept nested keyword-list input and normalize. For the catalog's purposes, keep the shape matching Raxol's so the mental model transfers.
**Warning signs:** Tree renders empty; FunctionClauseError on `next_in_list/2`.

### Pitfall 10: Raxol's `column`/`row` DSL strips children that are `nil`

**What goes wrong:** Building conditional children with `if` returning `nil` for the false branch — Raxol drops the `nil` from the list, but developers get surprised when the layout "has a gap".
**Why it happens:** Raxol treats `nil` as "no element" for composition ergonomics.
**How to avoid:** Prefer `if condition, do: element, else: empty_placeholder` where the placeholder is a `text("", …)` or a `spacer()` if spacing matters. Alternatively, compose children as `Enum.reject(list, &is_nil/1)` and emit an explicit empty element where needed.
**Warning signs:** Layout gaps in conditional content; tests assert child count but get one less.

## Code Examples

### Example 1: Theme slot routing for a Raxol component module

```elixir
# Source: derived from Table.render/2 reading theme shape (table.ex:36-46)
#         + patterns from 07-PATTERNS.md §Theme Slot Injection
defp build_table_theme(%Foglet.TUI.Theme{} = t) do
  %{
    box: %{border_fg: t.border.fg},
    header: %{fg: t.title.fg, style: [:bold]},
    row: %{fg: t.primary.fg},
    selected_row: %{fg: t.selected.fg, bg: t.selected.bg}
  }
end

# Inside render/2:
def render(%__MODULE__{raxol_state: rs}, opts) do
  theme = Keyword.fetch!(opts, :theme)
  rs_with_theme = %{rs | theme: build_table_theme(theme)}
  RaxolTable.render(rs_with_theme, %{})
end
```

Keys `box`, `header`, `row`, `selected_row` come directly from `Raxol.UI.Components.Table` `@moduledoc` theming section (verified in source lines 36–46). For components without such an explicit map shape (Tabs, Tree, Menu — which use `StyleHelper.merge_component_styles/3`), the wrapper passes slot values as `fg`/`bg`/`border_fg` kwargs on an outer `box` instead.

### Example 2: Raxol event-struct wrapping

```elixir
# Source: mirrors how Raxol components expect events internally
#         (tree.ex:71, tabs.ex:50, menu.ex:73, checkbox.ex:68)
def handle_event(event, %__MODULE__{raxol_state: rs} = st) do
  raxol_event = %Raxol.Core.Events.Event{type: :key, data: event}

  case RaxolTree.handle_event(raxol_event, rs, %{}) do
    {new_rs, []} ->
      action = derive_action(rs, new_rs, event)
      {%{st | raxol_state: new_rs, last_action: action}, action}
  end
end
```

### Example 3: Stateless progress bar with theme routing

```elixir
# Source: pattern combines display/progress.ex props with 07-PATTERNS.md
#         Viewport plain-module usage and D-16's stateless rule.
defmodule Foglet.TUI.Widgets.Display.Progress do
  @moduledoc """..."""

  alias Foglet.TUI.Theme
  alias Raxol.UI.Components.Display.Progress, as: RaxolProgress

  @default_width 40

  @spec render(float(), keyword()) :: any()
  def render(progress, opts) when is_float(progress) and is_list(opts) do
    %Theme{} = theme = Keyword.fetch!(opts, :theme)
    width = Keyword.get(opts, :width, @default_width)
    label = Keyword.get(opts, :label)
    show_pct = Keyword.get(opts, :show_percentage, true)

    {:ok, st} =
      RaxolProgress.init(%{
        progress: progress,
        width: width,
        show_percentage: show_pct,
        label: label,
        theme: %{progress: %{
          fg: theme.accent.fg,
          bg: theme.dim.fg,
          border: theme.border.fg,
          text: theme.primary.fg
        }}
      })

    RaxolProgress.render(st, %{})
  end
end
```

### Example 4: Test template (theme hygiene + smoke render per D-18)

```elixir
# Source: mirrors test/foglet_bbs/tui/widgets/modal_test.exs §theme hygiene
#         and list/list_row_test.exs flatten_text helpers
defmodule Foglet.TUI.Widgets.Input.ButtonTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Input.Button

  # --- flatten_text helpers (copied verbatim from list_row_test.exs:9-26) ---
  defp flatten_text(tree),
    do: tree |> collect_text([]) |> Enum.reverse() |> Enum.join("")
  defp collect_text(nil, acc), do: acc
  defp collect_text(list, acc) when is_list(list),
    do: Enum.reduce(list, acc, &collect_text/2)
  defp collect_text(%{children: children} = node, acc) do
    acc = maybe_add_content(node, acc)
    collect_text(children, acc)
  end
  defp collect_text(%{content: content}, acc) when is_binary(content),
    do: [content | acc]
  defp collect_text(%{text: t}, acc) when is_binary(t), do: [t | acc]
  defp collect_text(_other, acc), do: acc
  defp maybe_add_content(%{content: content}, acc) when is_binary(content),
    do: [content | acc]
  defp maybe_add_content(_node, acc), do: acc

  defp theme, do: Theme.default()
  defp alt_theme, do: Theme.resolve(:danger)

  # D-18 bar #1: smoke render
  describe "render/2 — smoke (D-18)" do
    test "returns a non-nil Raxol element for a primary button" do
      result = Button.render("Save", role: :primary, theme: theme())
      refute is_nil(result)
      assert is_map(result)
      assert Map.has_key?(result, :type)
    end

    test "label appears in the rendered text" do
      result = Button.render("Save", role: :primary, theme: theme())
      assert flatten_text(result) =~ "Save"
    end

    test "shortcut renders alongside label when provided" do
      result =
        Button.render("Save", role: :primary, shortcut: "Ctrl+S", theme: theme())

      assert flatten_text(result) =~ "Ctrl+S"
    end
  end

  # D-18 bar #2: theme hygiene
  describe "render/2 — theme hygiene (D-18)" do
    test "no hardcoded color atoms leak into the tree" do
      for role <- [:primary, :secondary, :danger, :success] do
        tree = Button.render("x", role: role, theme: theme())
        serialized = inspect(tree, printable_limit: :infinity, limit: :infinity)
        refute serialized =~ ":red", "#{role} leaked :red"
        refute serialized =~ ":green", "#{role} leaked :green"
        refute serialized =~ ":cyan", "#{role} leaked :cyan"
        refute serialized =~ ":yellow", "#{role} leaked :yellow"
      end
    end

    test "rendering with an alternate theme produces different color output" do
      default_tree = Button.render("Save", role: :primary, theme: theme())
      alt_tree = Button.render("Save", role: :primary, theme: alt_theme())

      default_out = inspect(default_tree, printable_limit: :infinity, limit: :infinity)
      alt_out = inspect(alt_tree, printable_limit: :infinity, limit: :infinity)

      refute default_out == alt_out,
        "theme slot change must produce a different tree"
    end
  end
end
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Each screen inlines Raxol smart components directly, re-reading theme each time | Centralized `Foglet.TUI.Widgets.*` wrappers that route theme once | This phase (Phase 8) | Consistency wall; screens become shorter; tests become per-widget |
| `use Raxol.UI.Components.Base.Component` with the full behaviour | Call component `init/1`/`update/2`/`render/2` as plain functions; Foglet struct holds the state | Phase 7 for Viewport; generalized in Phase 8 | Keeps REQUIREMENTS "function-form only" lock intact while accessing stateful behaviour |
| Hardcoded ANSI color atoms (`:red`, `:green`, `:cyan`) in widget code | Every color via `theme.<slot>.fg`/`bg`/`style`; hex strings downsampled by Raxol's capability detection | Phase 1 → enforced across Phase 7 → mandatory here (D-07, D-09) | Nine themes (`gray`, `green`, `amber`, `cyan`, `paper`, `magenta`, `danger`, `ice`, `mono`) all work uniformly |

**Deprecated/outdated:**
- No phase-specific deprecations — this is greenfield wrapping work.

## Environment Availability

Phase 8 is purely Elixir + Raxol; nothing external. Omitted per instructions.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `Raxol.UI.Components.Display.Progress.init/1` accepts a `:theme` key mapping to `%{progress: %{fg, bg, border, text}}` | Code Examples §Example 3 | [ASSUMED] Based on reading `extract_colors/1` (progress.ex:165-172). Actual key name/nesting may differ; planner should verify against `StyleHelper.merge_component_styles/3` behaviour during implementation |
| A2 | `Raxol.UI.Components.Input.Tabs` number-key shortcut cannot be disabled via props | Pitfall 6 | [ASSUMED] Source read suggests no opt; risk is low because D-15 places key filtering with the screen anyway |
| A3 | `Raxol.UI.Components.Input.Menu` requires `:id` on every item (no default generation) | Pitfall 7 | [ASSUMED] Based on `find_item/2` pattern-match; planner should verify by supplying incomplete items in a test and seeing whether it FunctionClauseErrors |
| A4 | `Raxol.View.Components.radio_group/1` is display-only (no interactive state) | Pattern 3 | [VERIFIED] Read `radio_group_demo.ex` — it doesn't even use the DSL function, composes from `text/2`. There is no `Raxol.UI.Components.Input.RadioGroup` module |
| A5 | The `validate_keyword_opts/2` failure mode on `column style: %{...}` without an outer keyword is a compile-time error | Pitfall 4 | [ASSUMED] Inferred from `view.ex` macros; low risk, easy to verify at first `mix compile` |

All other claims in this document are either [VERIFIED: source read] or [CITED: `docs/raxol/**/*.md` referenced]. Nothing compliance-critical is assumed.

## Open Questions

1. **Should wrappers wrap their output in an outer `box` at all, or return the Raxol render map bare?**
   - What we know: Phase 7's Modal returns a `column` directly (no outer box — the caller `app.ex` wraps it). Chrome widgets return `box do ... end`. Both patterns exist.
   - What's unclear: Is the "theme border" visible on every widget the intended aesthetic, or should a widget like `Input.Button` render as just the themed text without its own border box?
   - Recommendation: Let the planner decide per-widget based on visual test. Default guidance: interactive widgets that the user "focuses on" (SmartList, Table, Tree, TextInput, Menu) get an outer themed `box` with `border_fg: theme.border.fg`; inline widgets (Button, Checkbox, RadioGroup, Spinner, Progress) return bare and let the screen layout position them.

2. **Which spinner style is Foglet's default (D-08 discretion)?**
   - What we know: Raxol exposes `:dots`, `:line`, `:circle`, `:arrow`, `:bounce`, `:pulse`, `:wave`, `:dots3`, `:square`, `:flip`.
   - What's unclear: The "BBS aesthetic" preference.
   - Recommendation: `:line` (`| / - \`) — maximum terminal compatibility, classic BBS look. Planner picks final value.

3. **Should `SmartList` expose `content_source:` (lazy/paginated data source) or only `options:` (eager list)?**
   - What we know: `Raxol.UI.Components.Input.SelectList` accepts `options: [{"Label", value}]`. `Display.Viewport` accepts `content_source:` for lazy paging.
   - What's unclear: Whether any v1.0–1.4 caller needs lazy paging (e.g., a future "all users" picker over 10k users).
   - Recommendation: `options:` only for now; re-add `content_source:` when a caller appears. Keeps the wrapper API narrow.

4. **What's the "action atom" convention across the catalog?**
   - What we know: `handle_event/2` returns `{state, action}` where action is `nil` or an atom/tuple.
   - Recommendation (planner's discretion per CONTEXT):
     - `:item_selected` / `{:item_selected, value}` — SmartList Enter, Table Enter, Tree Enter on leaf
     - `:submitted` / `{:submitted, value}` — TextInput Enter
     - `:cancelled` — TextInput Esc (when wired), Menu Esc
     - `:tab_changed` / `{:tab_changed, index}` — Tabs on Left/Right/1–9
     - `:node_expanded` / `:node_collapsed` / `:node_activated` — Tree
     - `:menu_action` / `{:menu_action, id}` — Menu leaf Enter
     - `:toggled` / `{:toggled, bool}` — Checkbox on toggle
   - These are consistent across widgets where meaning is parallel (selection → `*_selected`, text submission → `:submitted`, etc.).

5. **Does `Foglet.TUI.Widgets.Input.TextInput` need `translate_key/1` like `Compose` does?**
   - What we know: `Compose.translate_key/1` maps Raxol key events → `MultiLineInput.update/2` messages. `Raxol.UI.Components.Input.TextInput.handle_event/3` already consumes the raw `%Event{}` struct.
   - What's unclear: Whether our wrapper should mirror Compose's explicit translation or delegate to `TextInput.handle_event/3` directly (matching the Pattern 2 delegation shape).
   - Recommendation: Pattern 2 delegation. `Compose` exists because `MultiLineInput` has a different message shape (`update/2`, not `handle_event/3`) and the composer needs to mix cursor rendering with screen-level shortcuts. For the single-line case, just wrap the event in a `%Raxol.Core.Events.Event{}` and call `TextInput.handle_event/3`.

## Validation Architecture

Nyquist validation is enabled by default (`workflow.nyquist_validation` is not explicitly disabled).

### Test Framework

| Property | Value |
|----------|-------|
| Framework | ExUnit (stdlib, Elixir 1.19.2 per project) |
| Config file | `test/test_helper.exs` (already present) |
| Quick run command | `mix test test/foglet_bbs/tui/widgets/<bucket>/<widget>_test.exs` |
| Full suite command | `mix precommit` (runs `compile --warnings-as-errors`, `format`, `credo --strict`, `sobelow`, `dialyzer`, then `mix test`) |
| Widget-bucket command | `mix test test/foglet_bbs/tui/widgets/` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| REQ-W-01 | `SmartList` smoke render returns non-nil element; theme hygiene | unit | `mix test test/foglet_bbs/tui/widgets/list/smart_list_test.exs` | ❌ Wave 0 |
| REQ-W-02 | `Display.Table` smoke render + theme hygiene | unit | `mix test test/foglet_bbs/tui/widgets/display/table_test.exs` | ❌ Wave 0 |
| REQ-W-03 | `Display.Tree` smoke render + theme hygiene | unit | `mix test test/foglet_bbs/tui/widgets/display/tree_test.exs` | ❌ Wave 0 |
| REQ-W-04 | `Display.Progress` smoke render + theme hygiene | unit | `mix test test/foglet_bbs/tui/widgets/display/progress_test.exs` | ❌ Wave 0 |
| REQ-W-05 | `Progress.Spinner` smoke render + theme hygiene | unit | `mix test test/foglet_bbs/tui/widgets/progress/spinner_test.exs` | ❌ Wave 0 |
| REQ-W-06 | `Input.TextInput` smoke render + theme hygiene | unit | `mix test test/foglet_bbs/tui/widgets/input/text_input_test.exs` | ❌ Wave 0 |
| REQ-W-07 | `Input.Button` smoke render + theme hygiene | unit | `mix test test/foglet_bbs/tui/widgets/input/button_test.exs` | ❌ Wave 0 |
| REQ-W-08 | `Input.Checkbox` smoke render + theme hygiene | unit | `mix test test/foglet_bbs/tui/widgets/input/checkbox_test.exs` | ❌ Wave 0 |
| REQ-W-09 | `Input.RadioGroup` smoke render + theme hygiene | unit | `mix test test/foglet_bbs/tui/widgets/input/radio_group_test.exs` | ❌ Wave 0 |
| REQ-W-10 | `Input.Tabs` smoke render + theme hygiene | unit | `mix test test/foglet_bbs/tui/widgets/input/tabs_test.exs` | ❌ Wave 0 |
| REQ-W-11 | `Input.Menu` smoke render + theme hygiene | unit | `mix test test/foglet_bbs/tui/widgets/input/menu_test.exs` | ❌ Wave 0 |
| REQ-W-12 | README exists and lists every catalog widget | integration | `ls lib/foglet_bbs/tui/widgets/README.md && grep -c smart_list lib/foglet_bbs/tui/widgets/README.md` | ❌ Wave 0 |
| REQ-W-13 | Every wrapper passes D-18 bar in CI | suite | `mix precommit` | Existing |

### Sampling Rate

- **Per task commit:** `mix test test/foglet_bbs/tui/widgets/<bucket>/` — fast feedback on the affected bucket.
- **Per wave merge:** `mix test test/foglet_bbs/tui/widgets/` — full widget layer.
- **Phase gate:** `mix precommit` green before `/gsd-verify-work` (runs compile/format/credo/sobelow/dialyzer/tests).

### Wave 0 Gaps

- [ ] `test/foglet_bbs/tui/widgets/list/smart_list_test.exs` — covers REQ-W-01
- [ ] `test/foglet_bbs/tui/widgets/display/table_test.exs` — covers REQ-W-02
- [ ] `test/foglet_bbs/tui/widgets/display/tree_test.exs` — covers REQ-W-03
- [ ] `test/foglet_bbs/tui/widgets/display/progress_test.exs` — covers REQ-W-04
- [ ] `test/foglet_bbs/tui/widgets/progress/spinner_test.exs` — covers REQ-W-05
- [ ] `test/foglet_bbs/tui/widgets/input/text_input_test.exs` — covers REQ-W-06
- [ ] `test/foglet_bbs/tui/widgets/input/button_test.exs` — covers REQ-W-07
- [ ] `test/foglet_bbs/tui/widgets/input/checkbox_test.exs` — covers REQ-W-08
- [ ] `test/foglet_bbs/tui/widgets/input/radio_group_test.exs` — covers REQ-W-09
- [ ] `test/foglet_bbs/tui/widgets/input/tabs_test.exs` — covers REQ-W-10
- [ ] `test/foglet_bbs/tui/widgets/input/menu_test.exs` — covers REQ-W-11
- [ ] `lib/foglet_bbs/tui/widgets/README.md` — covers REQ-W-12

Framework install: **none needed** — ExUnit is stdlib, Raxol is vendored, `Foglet.TUI.Theme` is already the session-resolved snapshot.

### Validation Dimensions (D-18 expansion + orchestrator guidance)

1. **Smoke render** — `WidgetMod.render/2` (or `/1` for stateless-with-positional) returns a non-nil map that has a `:type` key. (Minimum Raxol element shape.)
2. **Theme hygiene** — No hardcoded color atom (`:red`, `:green`, `:cyan`, `:yellow`) leaks into the rendered tree. Rendering with `Theme.resolve(:gray)` produces a different serialized tree than rendering with `Theme.resolve(:danger)`.
3. **Event purity (stateful widgets)** — `WidgetMod.handle_event/2` is pure: same input state + event produces same output state + action. No process creation, no `send/2`, no side effects.
4. **Module-constant defaults** — Each wrapper's `@default_*` constants are used when the caller omits the option. Tests assert against the constant value, not a literal.
5. **Moduledoc D-## references** — Every wrapper's `@moduledoc` cites the D-## decisions it honors (e.g., "Honours D-07, D-09, D-13, D-14"). Verified with a grep test over `lib/foglet_bbs/tui/widgets/**/*.ex`.
6. **Namespace correctness** — File path matches module name per D-10 (`Foglet.TUI.Widgets.Input.Button` → `lib/foglet_bbs/tui/widgets/input/button.ex`). Verified by `mix compile` (module-path mismatches are compile warnings with `--warnings-as-errors`).
7. **README index completeness** — `lib/foglet_bbs/tui/widgets/README.md` lists every module in D-02 with a one-line description.
8. **No stubs (D-17)** — Every `render/2` contains real logic (grep test: no `raise "TODO"`, no `:not_implemented`, no empty function bodies); every stateful widget has a non-trivial `handle_event/2`.
9. **Function-form constraint (REQUIREMENTS-locked)** — Grep test: `use Raxol.UI.Components.Base.Component` MUST NOT appear in any new file under `lib/foglet_bbs/tui/widgets/`.
10. **Precommit green (umbrella validation)** — `mix precommit` passes — compiles warning-free, formatted, credo-clean, sobelow-clean, dialyzer-clean, all tests green.

## Sources

### Primary (HIGH confidence)

- `docs/raxol/getting-started/WIDGET_GALLERY.md` — complete widget catalog, DSL-vs-component-module table (Quick Reference lines 667–703). Confirms which widgets have DSL function-form vs component-module-only.
- `docs/raxol/cookbook/THEMING.md` — inline-color patterns, `fg:`/`bg:` hex string acceptance (lines 9–17), auto-downsampling to ANSI/256/16/mono (lines 36–43).
- `/vendor/raxol/lib/raxol/ui/components/input/select_list.ex` — SmartList basis; options, state keys, lifecycle.
- `/vendor/raxol/lib/raxol/ui/components/display/tree.ex` — Tree basis; `visible_nodes/1`, `expanded :: MapSet`, keyboard map.
- `/vendor/raxol/lib/raxol/ui/components/display/progress.ex` — Progress basis; animation frames, hardcoded atom defaults pitfall.
- `/vendor/raxol/lib/raxol/ui/components/progress/spinner.ex` — Spinner styles, stateless `spinner/3`.
- `/vendor/raxol/lib/raxol/ui/components/input/text_input.ex` — TextInput basis; KeyHandler, state shape.
- `/vendor/raxol/lib/raxol/ui/components/input/button.ex` — Button defstruct + role atoms.
- `/vendor/raxol/lib/raxol/ui/components/input/checkbox.ex` — Checkbox state, `on_toggle` callback.
- `/vendor/raxol/lib/raxol/ui/components/input/tabs.ex` — Tabs keyboard (Left/Right/1–9), wrapping behavior.
- `/vendor/raxol/lib/raxol/ui/components/input/menu.ex` — Menu nested state (`open_path`, `cursor`), Esc semantics.
- `/vendor/raxol/lib/raxol/ui/components/table.ex` — Table theme shape (`box`, `header`, `row`, `selected_row`).
- `/vendor/raxol/lib/raxol/view/components.ex` — Lightweight DSL wrappers (lines 149–367).
- `/vendor/raxol/lib/raxol/core/renderer/view.ex` — Block-macro DSL (`column do…end`, etc.).
- `/vendor/raxol/lib/raxol/playground/demos/radio_group_demo.ex` — Confirms no stateful `RadioGroup` module; radio groups built from `text/2`.
- `/deps/raxol_core/lib/raxol/core/defaults.ex` — Canonical magic numbers (`page_size 10`, `terminal_width 80`).

### Secondary (existing Foglet patterns)

- `lib/foglet_bbs/tui/widgets/list/selection_list.ex` — stateless `render/3` template.
- `lib/foglet_bbs/tui/widgets/compose.ex` — stateful-held-by-parent template.
- `lib/foglet_bbs/tui/widgets/chrome/{screen_frame,key_bar,status_bar}.ex` — theme-slot-only + module-constant defaults templates.
- `lib/foglet_bbs/tui/widgets/modal.ex` — Phase 7 thin-adapter template.
- `lib/foglet_bbs/tui/theme.ex` — Theme struct (do NOT extend per D-08).
- `test/foglet_bbs/tui/widgets/modal_test.exs` — theme-hygiene test pattern.
- `test/foglet_bbs/tui/widgets/list/list_row_test.exs` — `flatten_text/1` + `collect_text/2` helpers to copy.
- `.planning/workstreams/phase-03-polish/phases/07-migrate-hand-rolled-ui-components-to-raxol-widgets/07-PATTERNS.md` — §Viewport Plain Module Usage establishes the D-14 delegation pattern.
- `.planning/workstreams/phase-03-polish/phases/01-widget-foundation-theme-screen-chrome/01-CONTEXT.md` (referenced) — theme slot definitions (Phase 1 D-01) and `session_context.theme` injection (Phase 1 D-03).

### Tertiary

- `docs/raxol/guides/custom_components.md` — View Helpers recommendation (prefer private view functions; use Component behaviour only when publishing a reusable widget). Confirms plain-module-call pattern is the officially preferred route.

## Plan Breakdown Guidance (for planner)

Per CONTEXT D-14's Claude's Discretion and the heavy pattern overlap within buckets, **bundle by bucket** is the better route over one-plan-per-widget (11 plans is ceremony for mechanically similar work).

**Recommended breakdown (5 plans):**

| Plan | Scope | Widgets | Why bundled |
|------|-------|---------|-------------|
| 08-01 | Input bucket (stateless widgets first) | `Input.Button`, `Input.Checkbox`, `Input.RadioGroup` | All three are stateless-per-D-16; share the "render only, no struct" template. RadioGroup has no Raxol component module so it sets the bar for Pattern 3. |
| 08-02 | Input bucket (stateful widgets) | `Input.TextInput`, `Input.Tabs`, `Input.Menu` | All three follow Pattern 2 (delegate to Raxol component module via wrapping `%Event{}` struct). TextInput is simplest; Tabs and Menu exercise the action-atom convention. |
| 08-03 | Display + Progress buckets | `Display.Table`, `Display.Tree`, `Display.Progress`, `Progress.Spinner` | Table and Tree share Pattern 2 with complex theme routing (Table has explicit `%{box, header, row, selected_row}` shape). Display.Progress and Progress.Spinner are stateless and ride along cheaply. |
| 08-04 | List bucket | `List.SmartList` | SmartList is the highest-complexity wrapper (search + pagination + multi-select). Worth its own plan so the state-struct shape and the `SelectList` option surface get careful review. |
| 08-05 | README index + end-to-end smoke (D-12, D-17) | `lib/foglet_bbs/tui/widgets/README.md`; optional integration test that renders one widget from each bucket and asserts no hardcoded atoms across the combined output | Locks in discoverability per D-12 and catches theme-hygiene regressions that slip past per-widget tests. |

**Pattern overlap evidence (for "bundling wins" CONTEXT guidance):**
- All six Input widgets share keyboard conventions (Enter/Space/Esc/Tab), so their wrappers collectively establish the action-atom vocabulary once.
- Both Display widgets (Table, Tree) share the "delegate render to Raxol component + wrap in themed box" pattern.
- Progress.Spinner and Display.Progress are both stateless and use the same stateless-render template — bundling them prevents two near-duplicate plans.

**Outlier watchlist:**
- `Progress.Spinner` — uses `Spinner.spinner/3` directly (stateless utility, returns a string). The wrapper's `render/2` emits `text(...)` rather than delegating to a component render. Planner should note this divergence.
- `Input.Menu` — nested state (`open_path`) is the most complex. Don't underestimate the test-case count.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — every module path and API signature verified in source.
- Architecture: HIGH — stateless-facade pattern is a direct generalization of the Phase 7 Viewport pattern that already landed; D-14 formalizes it.
- Pitfalls: HIGH — #1–#9 are all grounded in source read; #10 is a known Raxol DSL quirk.
- Plan breakdown guidance: MEDIUM — recommendation is based on pattern overlap analysis, not on executed plans. Planner's discretion applies.

**Research date:** 2026-04-20
**Valid until:** 2026-05-20 (30 days — Raxol API has been stable across Phase 1–7 which is ~4 weeks).
