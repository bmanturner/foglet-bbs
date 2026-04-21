# Phase 8: Build local widget library from Raxol primitives — Context

**Gathered:** 2026-04-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Pre-build a local library of `Foglet.TUI.Widgets.*` wrappers around the *smart* (higher-complexity) Raxol components — the ones providing real UX like search, pagination, multi-select, validation, keyboard navigation, sort/filter, progress indicators, and menus. Every wrapper routes color/style through the `Foglet.TUI.Theme` struct and sets Foglet-native defaults.

**Explicitly NOT in scope:** wrapping base primitives (`text`, `column`, `row`, `box`, `spacer`, `divider`) — those stay direct DSL calls via `import Raxol.Core.Renderer.View`. This phase targets the *smarter* gallery components, not the layout/text leaves.

**Posture:** planning work for milestones ahead. No new user-visible behavior ships this phase; screens that consume these widgets land in Milestones 4–14. Size the phase around delivering a complete catalog with theme wiring + smoke tests.

</domain>

<decisions>
## Implementation Decisions

### Catalog scope

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

### Catalog exclusions

- **D-03: `List.SelectionList` stays lean.** Phase 7's delegation to `Raxol.list/1` is the final shape. Richer capabilities (search, pagination, multi-select) land in the new `List.SmartList` sibling, **not** by expanding `SelectionList`'s prop surface.
- **D-04: Modal and Viewport are Phase 7's work.** Phase 8 does not add Foglet wrappers for `Raxol.UI.Components.Modal` (Phase 7 produces `Widgets.Modal` as a thin adapter per 07-CONTEXT D-07/D-08) or `Raxol.UI.Components.Display.Viewport` (Phase 7 integrates it into PostReader directly).
- **D-05: No general `Input.Textarea` wrapper.** `Foglet.TUI.Widgets.Compose.render_input/3` remains the only `MultiLineInput` consumer. Add a general wrapper only when a non-compose caller appears.
- **D-06: Excluded from the catalog entirely:** `image`, `code_block`, `markdown_renderer` (explicitly rejected per Phase 7 D-02 — custom `Post.MarkdownBody` wins), and the chart family (`sparkline`, `line_chart`, `bar_chart`, `scatter_chart`, `heatmap`). No known v1.0–1.4 caller; reopen if one appears.

### Wrapping threshold

- **D-07: Minimum wrapper work = theme routing + sensible defaults.** Every wrapper routes colors/style from `Foglet.TUI.Theme` into the Raxol component's style props *and* picks Foglet-native defaults (border style, padding, density, page size, animation cadence, selected/unselected slots). No new behavior layered on top, no API simplification — just theme consistency + defaults.
- **D-08: Defaults live as per-widget module constants.** Each wrapper defines its own defaults inline (`@default_border :single`, `@default_page_size 10`, etc.). No shared `Widgets.Defaults` module. No expansion of the `Theme` struct with UX tokens.
- **D-09: Raw Raxol style kwargs are NOT exposed on wrapper APIs.** Callers style via theme slots only. If a caller needs a one-off color that isn't in the theme, the answer is either (a) add a theme slot or (b) live with the standard look. The consistency wall is the point of the library.

### Namespace organization

- **D-10: Raxol-category-aligned sub-namespace buckets** under `Foglet.TUI.Widgets.*`:
  - `Input.{TextInput, Button, Checkbox, RadioGroup, Tabs, Menu}`
  - `Display.{Table, Tree, Progress}`
  - `Progress.{Spinner}`
  - `List.{SelectionList, SmartList}` (extends existing bucket)
  - `Chrome.{ScreenFrame, StatusBar, KeyBar}` and `Post.{MarkdownBody, PostCard}` unchanged.
- **D-11: Existing flat modules stay flat.** `Foglet.TUI.Widgets.Compose` and `Foglet.TUI.Widgets.Modal` are NOT moved into buckets. Not worth churning callers for aesthetics; Phase 7 just landed `Modal` as a thin adapter.
- **D-12: Discovery = `@moduledoc` + `lib/foglet_bbs/tui/widgets/README.md` index.** README has a one-line entry per widget module pointing at each file. No top-level `docs/WIDGETS.md` catalog — `@moduledoc` carries the detail, README is the index.

### Theming hook + state model

- **D-13: Every wrapper takes `theme:` as an explicit keyword arg.** Example signatures:
  ```elixir
  Input.Button.render(label, role: :primary, theme: theme)
  Display.Table.render(table_state, theme: theme)
  ```
  Consistent across the catalog; composable; testable in isolation. Screens read theme from `state.session_context.theme` (established in Phase 1 D-03) and thread it through. Deviates from `SizeGate.render/1`'s full-`state` pattern — that's a SizeGate-specific choice, not the catalog-wide convention.
- **D-14: Stateless render facade — widget owns struct shape & transitions; parent screen owns lifecycle.** For stateful widgets (SmartList, Table, Tree, TextInput with validation, Tabs, Menu) every widget module exposes:
  - a state struct (`defstruct ...`) defining the state shape (search_query, selected_index, page, expanded_ids, validator state, etc.)
  - `init/1` — pure constructor returning a new struct
  - `handle_event/2` — pure `(event, state) -> {state, action}` (action is `nil` or a simple atom/tuple the screen handles)
  - `render/2` — pure `(state, keyword()) -> Raxol.element`
  No GenServer, no process per widget instance. Parent screen stores the struct in `state.screen_state[:screen_name][:widget_name]` and routes relevant key events into `handle_event/2`. Matches Phase 7's Viewport integration pattern.
- **D-15: Key-event routing is the parent screen's responsibility.** The screen module decides which key events are handled by the widget vs the screen itself (e.g., `Esc` may exit the screen even though a widget is in search mode). Widgets never receive events they shouldn't act on.
- **D-16: Purely stateless widgets pass state explicitly.** `Input.Button`, `Input.Checkbox`, `Input.RadioGroup`, `Progress.Spinner`, `Display.Progress` don't define a state struct — callers pass the current value/progress/checked flag as an arg (or a keyword opt). Only widgets that genuinely own internal state (search query, expanded nodes, scroll position) define structs.

### Implementation depth + test bar

- **D-17: Every catalog entry ships with full implementation + tests.** No stubs, no "flesh out later" placeholders. If a widget is in the catalog (D-02), its `render/2` and `handle_event/2` (where applicable) are complete, its defaults are set, and it passes the test bar in D-18.
- **D-18: Test bar per widget = theme hygiene + smoke render.** Two guarantees:
  1. **Theme hygiene test:** no hardcoded colors in the module — every color reachable via a `theme.<slot>` lookup. Assert that rendering with an alternate theme produces different color output.
  2. **Smoke render test:** `render/2` (or `render/1` for stateless widgets) returns a non-nil Raxol element with the expected top-level shape (e.g., `Display.Table.render/2` returns a box containing a column). No prop-matrix coverage; integration covers richer cases as screens land.

### Claude's Discretion

- **Exact state struct shapes.** Planner defines the `defstruct` fields per widget. Guidance: mirror the Raxol component module's option keys where they cleanly apply (so mental model transfers from Raxol docs), plus any Foglet-specific fields.
- **Action atoms returned from `handle_event/2`.** Planner picks conventions (`:item_selected`, `:submitted`, `:cancelled`, etc.). Keep them consistent across widgets where the meaning is parallel.
- **Plan breakdown.** Planner decides whether widgets land one-per-plan (11 plans) or bundled by bucket (Input / Display / List / Progress). Bundling likely wins for overlapping patterns (e.g., all Input.* share keyboard conventions).
- **README index format.** Planner decides format (table vs list) for `lib/foglet_bbs/tui/widgets/README.md`.
- **Default values for module constants.** Planner picks specific defaults (border style, page size, spinner style, tabs active-indicator, etc.) drawing on Phase 1's chrome aesthetic.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Raxol widget catalog — CRITICAL FIRST READ
- `docs/raxol/getting-started/WIDGET_GALLERY.md` — The source gallery. Every catalog entry in D-02 maps to a section in this doc. Planner reads each target component's gallery entry and the linked component module path (e.g., `Raxol.UI.Components.Input.SelectList`) for full options.

### Theming contract — CRITICAL FIRST READ
- `docs/raxol/cookbook/THEMING.md` — Determines how each Raxol component accepts `Foglet.TUI.Theme`-derived colors (hex `fg:`/`bg:`/`style:` props). Every D-07 theme-routing decision depends on what the underlying component accepts. Same gate Phase 7 applied to migrations.

### Raxol DSL constraint
- `memory/feedback_raxol_modern_dsl.md` — Function-form only. Block-macro DSL (`column/row/box do...end`). No `use Raxol.UI.Components.Base.Component`, no legacy function-form. Hard wall — D-14's stateless facade is the Foglet way to reconcile Raxol's stateful components with this constraint.

### Workstream requirements and roadmap
- `.planning/workstreams/phase-03-polish/REQUIREMENTS.md` — Locked Decisions table (function-form only, `ThemeManager` rejected).
- `.planning/workstreams/phase-03-polish/ROADMAP.md` — Phase 8 depends on Phase 7; success criteria TBD (to be derived during planning from this CONTEXT).

### Prior phase context
- `.planning/workstreams/phase-03-polish/phases/01-widget-foundation-theme-screen-chrome/01-CONTEXT.md` — Theme slot definitions (D-01: `border`, `primary`, `dim`, `accent`, `title`, `error`, `warning`, `selected`, `unselected`, `status_bar`), widget namespace convention (D-10: `Foglet.TUI.Widgets.{Cluster}.{Widget}`), theme injection point (D-03: `CLIHandler.build_context/3`), stateless-rendering model (`SelectionList.render/3`).
- `.planning/workstreams/phase-03-polish/phases/07-migrate-hand-rolled-ui-components-to-raxol-widgets/07-CONTEXT.md` — Theming gate pattern (D-04/D-05: full replacement vs thin adapter based on theme-injection support); Modal as thin adapter (D-07/D-08); Viewport integration in PostReader (D-12/D-13); `SelectionList` base delegating to `Raxol.list/1`; reasons `MarkdownRenderer` and verify-screen input were kept hand-rolled (D-02).

### Raxol component modules (read per-widget during planning)
- `Raxol.UI.Components.Input.SelectList` — basis for `List.SmartList`.
- `Raxol.UI.Components.Display.Table` — basis for `Display.Table`.
- `Raxol.UI.Components.Display.Tree` — basis for `Display.Tree`.
- `Raxol.UI.Components.Display.Progress` — basis for `Display.Progress`.
- `Raxol.UI.Components.Progress.Spinner` — basis for `Progress.Spinner`.
- `Raxol.UI.Components.Input.TextInput` — basis for `Input.TextInput`.
- `Raxol.UI.Components.Input.Button` — basis for `Input.Button`.
- `Raxol.UI.Components.Input.Checkbox` — basis for `Input.Checkbox`.
- `Raxol.UI.Components.Input.Tabs` — basis for `Input.Tabs`.
- `Raxol.UI.Components.Input.Menu` — basis for `Input.Menu`.

### Existing Foglet widget patterns (templates for new widgets)
- `lib/foglet_bbs/tui/widgets/list/selection_list.ex` — stateless render function pattern; `render(items, selected_index, row_renderer_fn)`. Template for purely stateless new widgets.
- `lib/foglet_bbs/tui/widgets/compose.ex` — stateful-widget-held-by-parent pattern; `translate_key/1` + `render_input/3` mirror the `handle_event/2` + `render/2` shape D-14 describes. Reference template for SmartList, Table, Tree, etc.
- `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex` — positional-args + internal theme lookup pattern (reference; D-13 deviates in favor of explicit `theme:` kwarg for catalog widgets).
- `lib/foglet_bbs/tui/widgets/chrome/key_bar.ex` — theme-slot-only styling, module-constant defaults. Minimal template for D-07/D-08/D-09.

### Theme struct and injection
- `lib/foglet_bbs/tui/theme.ex` — Theme struct (slots per Phase 1 D-01). Not expanded in Phase 8 (D-08).
- `lib/foglet_bbs/ssh/cli_handler.ex` — `build_context/3` where theme lands in `session_context` (Phase 1 D-03).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable assets
- `Foglet.TUI.Theme` struct with locked slot names — every new widget reads from these, never hardcodes colors (D-07, D-09).
- `Foglet.TUI.Widgets.Compose.render_input/3` + `translate_key/1` — proof that a stateful-widget-as-pure-functions pattern works in this codebase. D-14 generalizes it.
- `Foglet.TUI.Widgets.List.SelectionList.render/3` — proof that parent-owns-state pattern scales. `List.SmartList` sits alongside it (D-03), not in place of it.
- `Raxol.Core.Renderer.View` DSL (`column/row/box do...end`, `spacer`, `divider`, `text`) — available to every new widget's `render/2`.

### Established patterns (reinforced or extended)
- Widget module lives in `lib/foglet_bbs/tui/widgets/<bucket>/<widget>.ex` (Phase 1 D-10).
- `@moduledoc` documents signature + locked decisions with D-## references (template: `screen_frame.ex`, `key_bar.ex`).
- Screen modules store widget state in `state.screen_state[:screen_name][:widget_name]` (Phase 1 D-07, applied to all SelectionList/PostReader today).
- Function-form only — no `use Raxol.UI.Components.Base.Component` (REQUIREMENTS Locked Decision; `memory/feedback_raxol_modern_dsl.md`).

### Integration points
- Every future screen in `lib/foglet_bbs/tui/screens/` will `alias Foglet.TUI.Widgets.*` and consume these widgets.
- `CLIHandler.build_context/3` at `lib/foglet_bbs/ssh/cli_handler.ex:314` — theme already injected into `session_context`. No changes needed.
- `lib/foglet_bbs/tui/app.ex` event dispatch — screens continue to own key routing; Phase 8 widgets slot into the same flow.

### New conventions introduced by Phase 8
- **Explicit `theme:` kwarg** (D-13) becomes the catalog-wide default, distinct from older `SizeGate.render/1` full-state pattern. Applies to Phase 8 widgets only — does not retroactively change existing widgets.
- **`init/1` + `handle_event/2` + `render/2` function triplet** (D-14) for stateful widgets — new for the catalog; inspired by Raxol's component-module shape but without processes.
- **Module-constant defaults** (D-08) — formalizes an existing informal practice.

</code_context>

<specifics>
## Specific Ideas

- **Gallery-first discoverability.** The catalog mirrors `WIDGET_GALLERY.md` organization deliberately — a dev reading the Raxol gallery can translate any smart component to its Foglet wrapper by category + name. This is the whole reason for Raxol-category-aligned buckets (D-10) over domain-first naming.
- **Consistency wall is deliberate** (D-09). Not exposing raw style kwargs is the point of the library — otherwise we have N subtly-different button colorings across screens. If a caller insists they need a one-off color, the fix is to add a theme slot, not to carve an escape hatch.
- **Stateful-but-no-process pattern** (D-14) is the second-order theming gate. Raxol's component modules are full-lifecycle (`init/1`/`handle_event/3`/`render/2`) and technically usable via `use ...Base.Component`, but our `function-form only` constraint (REQUIREMENTS locked) forbids it. D-14 captures what that constraint produces in practice: same function triplet, callers hold the struct.
- **Tree inclusion is speculative-but-cheap** (D-02). Once the state-model pattern is set for one hierarchical widget, Tree costs little more than a render function + keyboard handler. Worth grabbing now rather than later.
- **User intent for Phase 8:** not "wrap every Raxol primitive". Intent is "reimplement the smart components that would otherwise be re-invented ad-hoc as each upcoming milestone lands a screen that needs them". Keep that framing when evaluating marginal additions.

</specifics>

<deferred>
## Deferred Ideas

- **`docs/WIDGETS.md` top-level catalog doc.** Rejected for this phase in favor of `@moduledoc` + a README index (D-12). Reopen if the widget count grows past ~20 or if CLAUDE.md needs a single widget-docs link.
- **`Input.Textarea` general wrapper.** Deferred until a non-compose caller appears (D-05).
- **Expanding `Foglet.TUI.Theme` with non-color UX tokens** (border style, density, spacing). Not this phase (D-08). Reconsider when a second theme lands or when screens show visible divergence in spacing/density.
- **Shared `Foglet.TUI.Widgets.Defaults` module.** Rejected for this phase (D-08) in favor of per-widget constants. Reopen if duplication across widgets becomes meaningful (e.g., 4+ widgets share a literal default value).
- **Wrapping `image`, `code_block`, `markdown_renderer`, charts.** Out of scope (D-06). Reopen per-widget when a calling screen materializes.
- **Moving `Compose` and `Modal` into buckets** (e.g., `Form.Compose`, `Overlay.Modal`). Rejected (D-11) — caller-update cost not worth cosmetic consistency.

</deferred>

---

*Phase: 08-build-local-widget-library-from-raxol-primitives*
*Context gathered: 2026-04-20*
