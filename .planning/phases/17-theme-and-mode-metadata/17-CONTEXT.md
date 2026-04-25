# Phase 17: theme-and-mode-metadata - Context

**Gathered:** 2026-04-25 (assumptions mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 17 establishes the TUI presentation-mode and semantic-theme contracts that later facelift phases consume. It adds an explicit shared contract for `:bbs` and `:operator` screen modes, locks mode declarations for every current TUI screen id, extends `Foglet.TUI.Theme` with concrete `success`, `info`, and `badge` slots across all palettes, and documents/tests the theme-slot mappings for tabs, rows, badges, command hints, and editor states. It must not add Chrome V2 rendering, new facelift widgets, rich rows, command bars, editor frames, badge widgets, or visible screen layout conversions.
</domain>

<decisions>
## Implementation Decisions

### Mode Contract
- **D-01:** Implement the presentation-mode contract as a shared TUI-level API keyed by existing screen ids, rather than deriving mode inside individual render functions.
- **D-02:** The only supported presentation modes are exactly `:bbs` and `:operator`.
- **D-03:** Unsupported or unknown screen ids must be handled deliberately, with focused tests proving the behavior.

### Screen Mode Coverage
- **D-04:** Lock mode declarations for every current TUI screen id, not only the screens named in `SCREENS.md`.
- **D-05:** `:login`, `:register`, `:verify`, `:main_menu`, `:board_list`, `:thread_list`, `:post_reader`, `:new_thread`, and `:post_composer` resolve to `:bbs`.
- **D-06:** `:account`, `:moderation`, and `:sysop` resolve to `:operator`.
- **D-07:** Register and Verify are included because the mode contract should cover all current app-routed screens; they follow the BBS/authentication rhythm rather than the operator-console rhythm.

### Theme Slot Extension
- **D-08:** Add `success`, `info`, and `badge` as first-class fields in `%Foglet.TUI.Theme{}`, the `@type t`, `@slot_keys`, and every existing palette map.
- **D-09:** Initially synthesize the new semantic slots from existing palette colors where appropriate; do not retune palettes or perform contrast redesign in Phase 17.
- **D-10:** `Theme.resolve/1`, `Theme.default/0`, and `Theme.from_state/1` must return snapshots with non-empty `success`, `info`, and `badge` maps for every existing theme id.

### Theme Mapping Contract
- **D-11:** Capture tab, row, badge, command hint, and editor-state mappings as a project-local contract with tests that validate referenced slot names against `Foglet.TUI.Theme`.
- **D-12:** Do not implement new `Display.Badge`, `List.RichRow`, `Chrome.CommandBar`, `Composer.EditorFrame`, table preset, inspector, or visible layout-conversion behavior in this phase.
- **D-13:** Mapping coverage must include selected/unselected tabs, row selected/unread/normal/metadata/disabled states, badge info/success/warning/error/accent states, command group/key/destructive/inactive states, and editor focus/counter states.

### Theme Independence
- **D-14:** Mode resolution must ignore `state.session_context.theme`, `theme_id`, Account theme preview state, and any active palette data.
- **D-15:** User-selected theme changes color treatment only; it must not change a screen's presentation mode or layout category.

### the agent's Discretion
- Exact module name and public function names for the mode contract are planner discretion, provided downstream code has one documented source of truth for screen-to-mode resolution.
- Exact file location for the theme mapping contract is planner discretion. It may live in code, docs, or both, as long as tests can prove referenced slots exist on `Foglet.TUI.Theme`.

### Folded Todos
None.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Locked Phase Scope
- `.planning/phases/17-theme-and-mode-metadata/17-SPEC.md` - Locked Phase 17 requirements, boundaries, constraints, acceptance criteria, and interview decisions.
- `.planning/ROADMAP.md` §Phase 17 - Milestone position, dependency, requirements, and success criteria.
- `.planning/REQUIREMENTS.md` §Mode And Theme Contracts - Requirement IDs `MODE-01`, `THEME-01`, and `THEME-02`.
- `SCREENS.md` §Visual Direction, §Theme Implementation Notes, and §Recommended Implementation Order - v1.3 product mode split and semantic theme mapping guidance.

### Prior Dependency
- `.planning/phases/16-unicode-width-foundation/16-CONTEXT.md` - Width helper boundary and deferred facelift scope that Phase 17 must preserve.

### TUI Contract And Theme Code
- `lib/foglet_bbs/tui/app.ex` - Current screen id type, routing, and render dispatch.
- `lib/foglet_bbs/tui/screen.ex` - Existing screen behavior, currently without mode metadata.
- `lib/foglet_bbs/tui/theme.ex` - Current flat theme snapshot, palette registry, slot list, and fallback resolution.

### Widget Theme Mapping Evidence
- `lib/foglet_bbs/tui/widgets/README.md` - Widget organization and no-hardcoded-color convention.
- `lib/foglet_bbs/tui/widgets/input/tabs.ex` - Existing tab theme-slot mapping pattern.
- `lib/foglet_bbs/tui/widgets/list/list_row.ex` - Existing row selected/unread/metadata mapping pattern.
- `lib/foglet_bbs/tui/widgets/chrome/key_bar.ex` - Existing command key hint mapping pattern.
- `lib/foglet_bbs/tui/widgets/compose.ex` - Existing composer/editor rendering path.
- `docs/raxol/getting-started/WIDGET_GALLERY.md` - Raxol widget conventions for TUI work.
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Foglet.TUI.App` already owns the canonical `current_screen` value and dispatches to screen modules through `screen_module_for/1`.
- `Foglet.TUI.Theme` already centralizes all palette definitions, theme ids, Raxol theme registration, and per-session theme snapshots.
- Existing widget tests use flattened rendered trees and color-leak helpers to prove theme-routed behavior without hardcoded color atoms.

### Established Patterns
- Cross-cutting TUI helpers belong under `lib/foglet_bbs/tui/`; reusable widgets belong under `lib/foglet_bbs/tui/widgets/`.
- Render functions should stay pure over already-loaded state and route styling through `Foglet.TUI.Theme`.
- Widget contracts are documented in moduledocs and backed by focused tests under mirrored `test/foglet_bbs/tui/...` paths.
- Phase 17 should add metadata and theme contracts without changing existing screen rendering behavior.

### Integration Points
- `lib/foglet_bbs/tui/app.ex` currently includes these screen ids: `:login`, `:register`, `:verify`, `:main_menu`, `:board_list`, `:thread_list`, `:post_reader`, `:post_composer`, `:new_thread`, `:account`, `:moderation`, and `:sysop`.
- `lib/foglet_bbs/tui/theme.ex` currently defines `border`, `primary`, `dim`, `accent`, `title`, `error`, `warning`, `selected`, `unselected`, and `status_bar`; Phase 17 adds `success`, `info`, and `badge`.
- `lib/foglet_bbs/tui/screens/account.ex` previews themes by substituting a candidate theme into render state; mode resolution must not read this theme data.
- Existing widgets already encode partial mappings: tabs use selected/unselected/border/accent, rows use selected/primary/unselected/dim, key hints use accent/dim, and composer input uses primary.
</code_context>

<specifics>
## Specific Ideas

- Treat presentation mode as product metadata, not a theme variant.
- Cover every current app-routed screen id so future Chrome V2 can ask for mode without handling holes for Register or Verify.
- Keep new theme slots boring and complete first; palette taste and screenshot-driven contrast tuning can happen later.
</specifics>

<deferred>
## Deferred Ideas

None - discussion stayed within phase scope.

### Reviewed Todos (not folded)
None.
</deferred>

---

*Phase: 17-theme-and-mode-metadata*
*Context gathered: 2026-04-25*
