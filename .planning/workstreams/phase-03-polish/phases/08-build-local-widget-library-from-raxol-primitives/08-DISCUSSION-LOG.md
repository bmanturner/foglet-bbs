# Phase 8: Build local widget library from Raxol primitives — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in `08-CONTEXT.md` — this log preserves the alternatives considered.

**Date:** 2026-04-20
**Phase:** 08-build-local-widget-library-from-raxol-primitives
**Areas discussed:** Widget selection scope, Wrapping threshold, Namespace organization, Theming hook + impl depth

---

## Widget selection scope

### Q1: Selection approach for which smart components Phase 8 reimplements/enhances?

| Option | Description | Selected |
|--------|-------------|----------|
| Roadmap-driven (v1.0–1.4) | Target what upcoming milestones need (Presence, sysop admin, profiles, search). Produces ~6–8 widgets with clear immediate callers. | |
| Enhance-what-we-have + targeted few | Level up `SelectionList` with search/pagination, plus 3–4 most obvious missing pieces (TextInput, Button, Table, Progress/Spinner). | |
| Broad smart-component catalog | Reimplement essentially every smart component (SelectList-enhanced, Table, TextInput, Button, Checkbox, RadioGroup, Tabs, Menu, Progress, Spinner, Tree). | ✓ |
| Enhance SelectionList only, defer rest | Narrow bet: SelectionList gets search/pagination/multi-select this phase; everything else waits. | |

**User's choice:** Broad smart-component catalog.
**Notes:** User reframed the initial gray-area framing — clarified that Phase 8 is not about wrapping "sole primitives" (text/column/row/spacer) but about reimplementing the *smarter* gallery components with Foglet theming. Selection scope question and all downstream gray areas were re-scoped accordingly.

### Q2: SelectionList enhancement strategy — extend in place or sibling?

| Option | Description | Selected |
|--------|-------------|----------|
| Enhance SelectionList in place | Optional `search:`, `page_size:`, `multi_select:` props on existing `List.SelectionList.render/3`. | |
| Sibling `List.SmartList` | Keep `SelectionList` lean (current API); add `List.SmartList` for richer needs. | ✓ |
| Defer to planner | Record must-land features; let planning pick the shape. | |

**User's choice:** Sibling `List.SmartList`.

### Q3: `Display.Tree` inclusion?

| Option | Description | Selected |
|--------|-------------|----------|
| Include | Add to scope — covers sysop config grouping, any hierarchical display. | ✓ |
| Exclude | Skip; re-evaluate when a caller appears. | |

**User's choice:** Include.

### Q4: Low-priority display widgets (image, code_block, markdown_renderer, chart family)?

| Option | Description | Selected |
|--------|-------------|----------|
| Exclude all | None in scope. No v1.0–1.4 caller; `markdown_renderer` already rejected in Phase 7. | ✓ |
| Include sparkline/progress-family only | Add `sparkline` alongside Progress/Spinner for admin dashboard speculative need. | |
| Defer | Let planner decide per-widget based on research. | |

**User's choice:** Exclude all.

### Q5: Modal and Viewport — does Phase 8 add Foglet wrappers?

| Option | Description | Selected |
|--------|-------------|----------|
| Leave alone — Phase 7 owns them | Phase 7's `Widgets.Modal` thin adapter + direct `Display.Viewport` usage in PostReader stand. | ✓ |
| Add `Display.Viewport` wrapper | Add themed Viewport wrapper for future reuse. | |
| Add both wrappers | Include in catalog for completeness. | |

**User's choice:** Leave alone — Phase 7 owns them.

### Q6: `textarea` / `Input.MultiLineInput` general wrapper?

| Option | Description | Selected |
|--------|-------------|----------|
| Leave Compose as the only consumer | `Widgets.Compose.render_input/3` is the only MultiLineInput caller; add a general wrapper when a non-compose caller appears. | ✓ |
| Add `Input.Textarea` | General themed multi-line input wrapper in scope. | |
| Extract Compose.render_input into Input.Textarea | Promote + refactor Compose to consume it. | |

**User's choice:** Leave Compose as the only consumer.

---

## Wrapping threshold

### Q1: Minimum wrapper work?

| Option | Description | Selected |
|--------|-------------|----------|
| Theme routing + sensible defaults | Route theme colors/style + pick Foglet-native defaults. No new behavior, no API simplification. | ✓ |
| Theme routing + API shaping | Also reshape awkward Raxol APIs (SelectList option tuples, Table column_widths). | |
| Theme routing only | Minimal — inject theme colors, pass everything else through. | |

**User's choice:** Theme routing + sensible defaults.

### Q2: Where do defaults live?

| Option | Description | Selected |
|--------|-------------|----------|
| Per-widget module constants | Each widget defines its own defaults (`@default_border :single`). | ✓ |
| Shared `Foglet.TUI.Widgets.Defaults` | One module centralizes defaults (border, density, page size, animation). | |
| Extend `Foglet.TUI.Theme` with UX defaults | Theme carries non-color tokens alongside color slots. | |

**User's choice:** Per-widget module constants.

### Q3: Raw Raxol style kwargs — expose or not?

| Option | Description | Selected |
|--------|-------------|----------|
| Don't expose; always route via theme | Wrapper API hides raw style kwargs. Consistency wall enforced. | ✓ |
| Expose but default to theme | Escape hatch for edge cases at cost of bypassable consistency. | |
| Expose fully, document the convention | Pass through Raxol's full style API; rely on review. | |

**User's choice:** Don't expose; always route via theme.

---

## Namespace organization

### Q1: How should new widgets be grouped under `Foglet.TUI.Widgets.*`?

| Option | Description | Selected |
|--------|-------------|----------|
| Raxol-category-aligned buckets | `Input.*`, `Display.*`, `Progress.*`, `List.*` — maps 1:1 to gallery. | ✓ |
| Domain-first buckets | `Chrome`, `Post`, `List`, `Form`, `Feedback`, `Nav`. | |
| Flat namespace for new widgets | `Foglet.TUI.Widgets.{Button, TextInput, Table, ...}` directly. | |

**User's choice:** Raxol-category-aligned buckets.

### Q2: Existing flat `Compose` and `Modal` — move into buckets or leave?

| Option | Description | Selected |
|--------|-------------|----------|
| Leave as-is | `Widgets.Compose` and `Widgets.Modal` stay flat. | ✓ |
| Move into buckets | `Form.Compose`, `Overlay.Modal` — pay caller-update tax for uniformity. | |

**User's choice:** Leave as-is.

### Q3: Top-level catalog doc (`docs/WIDGETS.md`)?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — single catalog doc | `docs/WIDGETS.md` listing every widget with signature, theme slots, example. | |
| @moduledoc only, plus a widgets README | `lib/foglet_bbs/tui/widgets/README.md` one-line index; `@moduledoc` carries detail. | ✓ |
| @moduledoc only | No README; rely on IDE/ExDoc. | |

**User's choice:** @moduledoc only, plus a widgets README.

---

## Theming hook + impl depth

### Q1: How do Phase 8 wrappers receive theme?

| Option | Description | Selected |
|--------|-------------|----------|
| Explicit `theme` kwarg | `Input.Button.render(label, role: :primary, theme: theme)`. | ✓ |
| Full `state` arg (like `SizeGate.render/1`) | Wrapper extracts theme internally from state. | |
| Mix by tier | Low-level = explicit `theme`; high-level = full `state`. | |

**User's choice:** Explicit `theme` kwarg.

### Q2: State model for stateful Raxol components in a stateless widget layer

| Option | Description | Selected |
|--------|-------------|----------|
| Stateless render facade; parent screen owns state | Widget exposes `init_state/1`, `handle_event/3`, `render/2` as pure functions; parent keeps struct in `screen_state`. | ✓ (after clarification) |
| Full pass-through to Raxol's component lifecycle | `use Raxol.UI.Components.Base.Component` — violates REQUIREMENTS locked decision. | |
| Reinvent state in a Foglet idiom | Foglet-specific state shape and transitions. | |

**User's choice:** Stateless render facade; parent screen owns state.
**Notes:** User asked for clarification on what "owns state" means for a search-enabled list. Confirmed: widget module owns struct shape + transitions (init/handle_event/render); parent screen owns lifecycle (holds struct in `screen_state`, routes key events to widget). No GenServer per widget. Follow-up confirmation question locked this in.

### Q3: Implementation depth per widget?

| Option | Description | Selected |
|--------|-------------|----------|
| Full impl + tests for every catalog entry | Every widget ships complete with defaults, handlers, tests. | ✓ |
| Full for high-use, stubs for speculative | Full for SmartList/TextInput/Button/Progress/Spinner; stubs for Tree/Menu/RadioGroup/Tabs. | |
| Stubs for all + one exemplar | Every entry as stub; one reference widget fully built. | |

**User's choice:** Full impl + tests for every catalog entry.

### Q4: Test bar per wrapper?

| Option | Description | Selected |
|--------|-------------|----------|
| Theme hygiene + smoke render | No hardcoded colors + `render` returns non-nil element with expected top-level shape. | ✓ |
| Theme hygiene only | Check color routing; skip render shape. | |
| Full behavior per widget | Every meaningful prop variant tested. | |

**User's choice:** Theme hygiene + smoke render.

---

## Claude's Discretion (per CONTEXT.md)

- Exact state struct fields per widget.
- Action atom conventions returned from `handle_event/2`.
- Plan breakdown (one-per-widget vs bundled by bucket).
- README index format.
- Specific default values for module constants (border style, page size, spinner style, tabs active-indicator, etc.).

## Deferred Ideas (per CONTEXT.md)

- `docs/WIDGETS.md` top-level doc.
- `Input.Textarea` general wrapper.
- Expanding `Foglet.TUI.Theme` with non-color UX tokens.
- Shared `Foglet.TUI.Widgets.Defaults` module.
- Wrapping `image`, `code_block`, `markdown_renderer`, chart family.
- Moving `Compose`/`Modal` into buckets.
