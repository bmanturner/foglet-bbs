# Phase 1: Widget foundation + theme + screen chrome — Context

**Gathered:** 2026-04-19
**Status:** Ready for planning

<domain>
## Phase Boundary

Establish the widget foundation and theme struct that every downstream phase consumes. Deliver consistent screen chrome (bordered ScreenFrame, themed StatusBar, KeyBar) and a shared SelectionList across all existing screens. No correctness work (unread counts, markdown rendering) lands until this is done.

Every screen the user visits — login, register, verify, main menu, board list, thread list, post reader, post composer, new thread — must render through `ScreenFrame` by end of this phase.

</domain>

<decisions>
## Implementation Decisions

### Theme — Foglet.TUI.Theme struct

- **D-01:** Theme struct has the following semantic slots: `border`, `primary`, `dim`, `accent`, `title`, `error`, `warning`, `selected`, `unselected`, `status_bar`. Each slot is a map of Raxol style props (e.g., `%{fg: "#cccccc"}` or `%{fg: "#000000", bg: "#aaaaaa", style: [:bold]}`).
- **D-02:** Two named themes are defined in the codebase:
  - **`:gray`** (default for v1.0.1):
    ```elixir
    %{
      border:     %{fg: "#555555"},
      primary:    %{fg: "#cccccc"},
      dim:        %{fg: "#888888"},
      accent:     %{fg: "#ffb000", style: [:bold]},
      title:      %{fg: "#ffb000", style: [:bold]},
      error:      %{fg: "#ff5555", style: [:bold]},
      warning:    %{fg: "#ffff55"},
      selected:   %{fg: "#000000", bg: "#aaaaaa", style: [:bold]},
      unselected: %{fg: "#cccccc"},
      status_bar: %{fg: "#000000", bg: "#aaaaaa"}
    }
    ```
  - **`:green`** (alternative, defined but not active):
    ```elixir
    %{
      border:     %{fg: "#22aa44"},
      primary:    %{fg: "#33ff66"},
      dim:        %{fg: "#22aa44"},
      accent:     %{fg: "#ffb000", style: [:bold]},
      title:      %{fg: "#33ff66", style: [:bold]},
      error:      %{fg: "#ff5555", style: [:bold]},
      warning:    %{fg: "#ffff55"},
      selected:   %{fg: "#000000", bg: "#33ff66", style: [:bold]},
      unselected: %{fg: "#33ff66"},
      status_bar: %{fg: "#000000", bg: "#33ff66"}
    }
    ```
- **D-03:** `CLIHandler.build_context/3` resolves the theme once per session and injects it into `session_context`. For v1.0.1 it hardcodes `:gray`. The `:green` theme is fully defined but unused — no switching logic needed.
- **D-04:** No Raxol `ThemeManager`. The `Foglet.TUI.Theme` struct is the entire theming system for v1.0.1.

### ScreenFrame — Chrome widget

- **D-05:** `ScreenFrame.render/4` uses positional args:
  ```elixir
  ScreenFrame.render(state, title, content_element, key_list)
  ```
  `content_element` is a pre-built Raxol element (result of `column/row/box do...end`). `key_list` is the same `[{key_label, description}]` format KeyBar already accepts.
- **D-06:** Internal ScreenFrame layout (matches FRAME-01):
  `outer bordered box → column → StatusBar → divider → content_element → KeyBar`
- **D-07:** ScreenFrame reads `state.current_user` for handle and `state.session_context.theme` (or a default) for colors. Screens pass `state` as-is — no pre-extraction.

### StatusBar format

- **D-08:** StatusBar left side: `"Foglet BBS — {title}"` (title is the string passed as second arg to ScreenFrame). Right side: `"@{handle}"` when authenticated, `"guest"` otherwise. Existing format preserved.
- **D-09:** StatusBar background uses `theme.status_bar.bg`; text uses `theme.status_bar.fg`. This replaces the current `fg: :green` hardcode.

### Widget namespace

- **D-10:** All new widgets live in the `Foglet.TUI.Widgets.*` sub-namespace:
  - `Chrome.ScreenFrame` — outer frame + chrome assembly
  - `Chrome.StatusBar` — top bar (replaces flat `Widgets.StatusBar`)
  - `Chrome.KeyBar` — bottom key hint bar (replaces flat `Widgets.KeyBar`)
  - `List.SelectionList` — shared selection list renderer
  - `List.ListRow` — individual list row renderer
  - `Post.MarkdownBody` — markdown-to-terminal renderer (consumed by Phase 2)
  - `Post.PostCard` — post display card (consumed by Phase 2)
- **D-11:** Old flat modules `Foglet.TUI.Widgets.StatusBar` and `Foglet.TUI.Widgets.KeyBar` are deleted. All callers are updated in the same pass as the ScreenFrame migration. No delegate aliases left behind.
- **D-12:** Full screen migration in Phase 1 — every screen in `lib/foglet_bbs/tui/screens/` is refactored to call `ScreenFrame.render/4` and all hardcoded `fg: :green` colors are replaced with theme slot references.

### SelectionList API

### Claude's Discretion
- **SelectionList state ownership:** Parent screen owns `selected_index` (already tracked in `state.screen_state`). `SelectionList.render/3` accepts `(items, selected_index, row_renderer_fn)` and is pure rendering — no internal state. Key handling stays in the screen module. This is consistent with Raxol's stateless rendering model.
- **Post.MarkdownBody and Post.PostCard:** Define the module stubs and type specs in Phase 1 (since they're part of WIDGET-01 namespace); actual rendering implementation is the work of Phase 2. Stubs prevent Phase 2 from needing to create new files mid-plan.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Workstream Requirements and Roadmap
- `.planning/workstreams/phase-03-polish/REQUIREMENTS.md` — All v1.0.1 requirements with locked decisions table (widget style, ThemeManager rejection, etc.)
- `.planning/workstreams/phase-03-polish/ROADMAP.md` — Phase sequence, success criteria, dependency chain

### Raxol DSL Constraint
- `memory/feedback_raxol_modern_dsl.md` — CRITICAL: function-form widget constraint. Use `column/row/box do...end` block macros only. No `use Raxol.UI.Components.Base.Component`, no legacy `panel/1`, no `box(children:)` function-form.

### Existing Widget Code
- `lib/foglet_bbs/tui/widgets/status_bar.ex` — Current StatusBar (to be replaced by Chrome.StatusBar)
- `lib/foglet_bbs/tui/widgets/key_bar.ex` — Current KeyBar (to be replaced by Chrome.KeyBar)
- `lib/foglet_bbs/tui/widgets/modal.ex` — Modal widget (not in scope for this phase — note it exists)
- `lib/foglet_bbs/ssh/cli_handler.ex` — CLIHandler with `build_context/3` (theme injection point)

### All screens to migrate
- `lib/foglet_bbs/tui/screens/` — All 9 screens get ScreenFrame treatment in this phase

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Foglet.TUI.Widgets.StatusBar` — existing function-form, takes `%{handle:, location:}`. Becomes `Chrome.StatusBar`; API changes slightly to accept state+theme.
- `Foglet.TUI.Widgets.KeyBar` — existing function-form, takes `[{key, desc}]` list. Becomes `Chrome.KeyBar`; theme colors replace `style: [:dim]` hardcode.
- `lib/foglet_bbs/tui/widgets/modal.ex` — exists, not in scope but don't break it during migration.

### Established Patterns
- All screens use `import Raxol.Core.Renderer.View` for `box/column/row/text/divider` macros — continue this pattern in all new widgets.
- Screen state is keyed by screen name: `state.screen_state[:board_list][:selected_index]` — SelectionList doesn't touch this; screens own their state.
- `CLIHandler.build_context/3` already builds a context map injected into `state.session_context` — add `theme: Foglet.TUI.Theme.default()` here.

### Integration Points
- `CLIHandler.build_context/3` at `lib/foglet_bbs/ssh/cli_handler.ex:314` — theme injection point
- Every screen's `render/1` function — ScreenFrame migration point
- `state.current_user` — handle extraction for StatusBar (already used by existing StatusBar)
- 58 hardcoded color references across TUI screens — all get replaced with theme slot lookups

### Hardcoded Colors to Eliminate
- `fg: :green` — replace with `theme.primary.fg` (or `theme.unselected.fg` for list rows, `theme.selected.fg` for selected rows)
- `fg: :cyan` — replace with `theme.accent.fg`
- `fg: :red` — replace with `theme.error.fg`
- `fg: :yellow` — replace with `theme.warning.fg`
- `style: [:dim]` on text — keep as-is (dim is a style, not a color); pair with `theme.dim.fg` when needed

</code_context>

<specifics>
## Specific Ideas

- User provided exact hex color values for both themes — use these precisely, no approximation.
- Gray/amber theme `status_bar: %{fg: "#000000", bg: "#aaaaaa"}` creates a reverse-video bar effect — this is intentional, mimics classic BBS chrome.
- Green theme `status_bar: %{fg: "#000000", bg: "#33ff66"}` same inverted treatment with the green palette.
- `Post.MarkdownBody` and `Post.PostCard` stubs in Phase 1 are intentional scope management — they exist as placeholders so Phase 2 doesn't need to create new files.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 01-widget-foundation-theme-screen-chrome*
*Context gathered: 2026-04-19*
