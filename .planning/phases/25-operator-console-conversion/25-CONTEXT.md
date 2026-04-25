# Phase 25: operator-console-conversion - Context

**Gathered:** 2026-04-25 (assumptions mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 25 converts Account, Moderation, and Sysop screen tab bodies from bespoke padded-string rendering to the Phase 24 operator-console primitive layer (`Display.Badge`, `Display.KvGrid`, `Display.ConsoleTable`, refreshed `Modal.Form`). It is a presentation-layer conversion: domain workflows, authorization checks, context mutations, and PubSub wiring do not change. Converted tabs must degrade cleanly at 64x22 and reach their compact form at 80x24. `Workspace.Inspector` live wiring is deferred to v1.4 and remains explicitly out of scope. No new behavior tests, no new chrome variants, no theme-palette tuning, no wide-terminal layout enhancements beyond 80x24, no new moderation case-management workflows.

</domain>

<decisions>
## Implementation Decisions

### Modal.Form Reuse Strategy For Tab Bodies

- **D-01:** Use `Foglet.TUI.Widgets.Modal.Form` directly inline as a tab body for Account profile, Account preferences, Sysop site, and Sysop limits forms. The screen owns the `%Modal.Form{}` struct in its sibling `state.ex`, calls `Modal.Form.handle_event/2`, and renders with `Modal.Form.render(form, theme: theme)` — exactly matching the established `lib/foglet_bbs/tui/screens/sysop/boards_view.ex` precedent.
- **D-02:** Do **not** introduce a parallel "tab-body adapter" module. SPEC R1's "or a tab-body adapter" wording is a fallback only; the existing body-only rendering contract on `Modal.Form` is sufficient.
- **D-03:** For Account preferences, extend `Modal.Form` with a RadioGroup-style enum field that supports arrow-key cycling for the theme swatch and other enumerated preferences. This keeps prefs uniform with the other four forms and preserves the user's existing arrow-cycle interaction without forcing a Tab/Enter-only path. Existing prefs save/dirty/error behavior tests must continue to pass.

### ConsoleTable Adoption And Selection Ownership

- **D-04:** Listings convert to `Foglet.TUI.Widgets.Display.ConsoleTable` for Account SSH keys; Moderation log, users, boards, invites; and Sysop boards, users, categories.
- **D-05:** Selection state moves out of bespoke screen-local `selected_index` fields into the `ConsoleTable` (and its wrapped `Display.Table`) cursor. Screens hold the `%ConsoleTable{}` in sibling `state.ex`, route key events through `ConsoleTable.handle_event/2`, and dispatch domain side effects on the returned `Table.action()` (`{state, action}` tuple). This matches `screens/sysop/boards_view.ex:443-485`.
- **D-06:** No domain mutations move into `ConsoleTable` or any other widget. Authorization, context calls, and PubSub remain in screens.

### Destructive-Action Styling

- **D-07:** Reuse the existing `Foglet.TUI.Presentation.theme_mappings().commands.destructive => :error` mapping for destructive actions (delete board/category, ban user, etc.). Tab-body destructive command-bar entries set `destructive?: true`; inline emphasis routes through the same mapping helper used by `Chrome.CommandBar` and `Workspace.Inspector`.
- **D-08:** Do **not** add a new `:destructive` slot to the `Foglet.TUI.Theme` struct. Theme-palette changes are explicitly out of scope (UI-03).

### Layout Smoke Harness Shape

- **D-09:** Extend `test/foglet_bbs/tui/layout_smoke_test.exs` with **per-tab** size-contract blocks for each of the 11 converted tabs (Account: profile, prefs, ssh_keys; Moderation: log, users, boards, invites; Sysop: site, limits, boards, users, system). Activate the tab via the screen's `active_tab` (or equivalent) state key and iterate `[{64, 22}, {80, 24}]`.
- **D-10:** Each per-tab block asserts (a) rendered output stays within bounds, (b) at least one Phase 24 primitive sentinel is present (e.g., a known empty-state copy line, badge label, or kv-grid label), and (c) primitives do not overlap. Wide-terminal `132x50` is not required this phase.
- **D-11:** Pattern after the existing Phase 22/20 size-contract loops at `layout_smoke_test.exs:273-353` — not the shell-only operator tests at lines 1735-1824, which only render shells without activated tab bodies.

### Theme-Hygiene Test Style

- **D-12:** Use the existing `Foglet.TUI.WidgetHelpers.color_atom_leaked?/2` and `color_names/0` helpers from `test/support/foglet/tui/widget_helpers.ex` for the "no hardcoded color atoms" assertion (R8). Render the converted tab, serialize, and refute each color name. This matches the Phase 24 precedent across `badge_test`, `kv_grid_test`, `console_table_test`, and `modal/form_test`.
- **D-13:** Do not substitute a static source grep — it false-positives on docstrings and misses macro-expanded atoms.

### Ordering And Parallelism

- **D-14:** Wave 0 establishes shared scaffolding before screen conversion: shared empty-state copy strings (or a small helper), the per-tab smoke-test fixture pattern, and any RadioGroup/enum field extension on `Modal.Form` required by D-03.
- **D-15:** After wave 0, Account, Moderation, and Sysop convert in parallel. The three screens have disjoint sibling `state.ex` modules and disjoint context dependencies (`Foglet.Accounts` vs `Foglet.Boards`/`Foglet.Authorization` vs `Foglet.Config`), so parallel work has no shared write surface.
- **D-16:** Sysop is the highest-surface conversion (5 tabs across `site_form`, `limits_form`, `boards_view`, `users_view`, `system_snapshot`). Moderation is read-only-honest and the lowest-risk wave. Account carries the prefs RadioGroup work from D-03.
- **D-17:** Each screen wave finishes with its own per-tab render tests and per-tab layout smoke tests before being merged.

### Behavior Preservation Guardrails

- **D-18:** No domain logic, authorization, or PubSub wiring moves into widgets or into Phase 25 code. All `Foglet.Accounts`, `Foglet.Boards`, and `Foglet.Config` mutation paths remain unchanged.
- **D-19:** All pre-existing Account, Moderation, Sysop, `Display.Table`, and `Modal.Form` test suites must pass unmodified. No assertion weakening.
- **D-20:** `Workspace.Inspector` is not referenced from `lib/foglet_bbs/tui/screens/` in this phase; grep check enforces this in CI/precommit.

### Claude's Discretion

- Exact column definitions and dense-default presets per `ConsoleTable` instance, provided columns are stable, headers labeled, empty-state copy honest, and selection preserved.
- Exact wording of empty-state copy strings (e.g., "No SSH keys", "No moderation events"), provided they are honest about read-only state where applicable and routed through theme dim/info slots.
- Whether the Wave 0 RadioGroup field becomes a public `Modal.Form` field type or a private internal addition, provided arrow-cycling preserves the prefs UX and submit/dirty/error semantics are unchanged.
- Exact split of waves into PRs (one per screen vs combined), provided test coverage and behavior preservation hold.

### Folded Todos

None — `gsd-sdk query todo.match-phase 25` returned `todo_count: 0`.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Locked Phase Scope

- `.planning/phases/25-operator-console-conversion/25-SPEC.md` — Locked Phase 25 spec, 8 requirements, ambiguity 0.18.
- `.planning/ROADMAP.md` §Phase 25 — Milestone position and dependencies.
- `.planning/REQUIREMENTS.md` §Operator Console Conversion — `ACCOUNT-01`, `MOD-01`, `SYSOP-01`.
- `SCREENS.md` §Account, §Moderation, §Sysop — Target operator-console surfaces.
- `SCREENS.md` §Visual Direction and §Design Principles — Operator Console rhythm and shared primitive stack.

### Dependency Contracts

- `.planning/phases/24-operator-console-primitives/24-CONTEXT.md` — Phase 24 primitive contracts, theme routing, body-only `Modal.Form`, fixture/test conventions.
- `.planning/phases/24-operator-console-primitives/24-VERIFICATION.md` — Confirmation of what Phase 24 actually shipped.
- `.planning/phases/17-theme-and-mode-metadata/17-CONTEXT.md` — Operator mode metadata and theme-mapping contract; the `commands.destructive` slot lives here.
- `.planning/phases/18-chrome-v2/18-CONTEXT.md` — Chrome integration boundary and the `[{64,22},{80,24},{132,50}]` size-contract precedent.
- `.planning/phases/16-unicode-width-foundation/16-CONTEXT.md` — `Foglet.TUI.TextWidth` width-safe helpers used by primitives.

### Existing Code Touch Points

- `lib/foglet_bbs/tui/widgets/modal/form.ex` — Body-only render contract; the inline tab-body API. Lines 17 (docstring) and 144-169 (render) are the relevant anchors. Phase 25 may extend with a RadioGroup-style enum field (D-03).
- `lib/foglet_bbs/tui/widgets/display/console_table.ex` — Operator-console table wrapper with selectable/`last_action` semantics (lines 36-72).
- `lib/foglet_bbs/tui/widgets/display/badge.ex` and `kv_grid.ex` — Theme-routed display primitives.
- `lib/foglet_bbs/tui/widgets/display/table.ex` — Underlying `ConsoleTable` wrapper target.
- `lib/foglet_bbs/tui/screens/sysop/boards_view.ex` — Canonical inline-`Modal.Form` precedent (lines 34, 147-148, 235-294, 443-485).
- `lib/foglet_bbs/tui/screens/account.ex` and `screens/account/{profile_form,prefs_form,ssh_keys_surface,state}.ex` — Conversion targets for Account.
- `lib/foglet_bbs/tui/screens/moderation.ex` and `screens/moderation/state.ex` — Conversion targets for Moderation.
- `lib/foglet_bbs/tui/screens/sysop.ex` and `screens/sysop/{site_form,limits_form,boards_view,users_view,system_snapshot,state}.ex` — Conversion targets for Sysop.
- `lib/foglet_bbs/tui/presentation.ex` — `theme_mappings().badges` and `theme_mappings().commands.destructive` slot (lines 42-46, 96-101).
- `lib/foglet_bbs/tui/theme.ex` — Semantic theme slots; **do not add new slots this phase**.
- `lib/foglet_bbs/tui/widgets/chrome/command_bar.ex` — Reference consumer of `destructive?` flag (lines 26, 87, 250).
- `lib/foglet_bbs/tui/widgets/workspace/inspector.ex` — Reference destructive-styling consumer (line 76); not wired in this phase.
- `lib/foglet_bbs/tui/widgets/README.md` — Widget conventions; update if D-03 adds a public field type.

### Test Anchors

- `test/foglet_bbs/tui/layout_smoke_test.exs` — Size-contract harness. Per-tab fixture work extends this. Pattern after lines 273-353 (Phase 22/20 size-contract loops); shell tests at 1735-1824 are not the right precedent.
- `test/support/foglet/tui/widget_helpers.ex` — `color_atom_leaked?/2` and `color_names/0` for theme-hygiene assertions (lines 21, 38, 60).
- `test/foglet_bbs/tui/widgets/display/{badge,kv_grid,console_table,table}_test.exs` — Phase 24 theme-hygiene and primitive-presence patterns.
- `test/foglet_bbs/tui/widgets/modal/form_test.exs` — `Modal.Form` behavior coverage; extends here if D-03 adds RadioGroup field.
- `test/foglet_bbs/tui/screens/{account,moderation,sysop}*_test.exs` — Existing screen behavior tests that must keep passing unmodified.

### Project Conventions

- `AGENTS.md` — TUI boundaries (App vs screens vs widgets), theme-routing rules, no `Process.sleep/1` in tests, `start_supervised!/1`, `mix precommit` finish line.
- `.planning/codebase/CONVENTIONS.md` — Repo-wide conventions.
- `.planning/codebase/TESTING.md` — Test approach and helper conventions.
- `.planning/codebase/STRUCTURE.md` — Module/folder layout.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- `Modal.Form` body-only contract — already used inline as a tab body in `sysop/boards_view.ex`. Phase 25 reuses this pattern across four more forms.
- `Display.ConsoleTable` — already includes selectable behavior, dense defaults, empty-state copy, and `last_action`-based dispatch.
- `Display.Badge` and `Display.KvGrid` — theme-routed, width-safe, ready for direct consumption.
- `Foglet.TUI.WidgetHelpers.color_atom_leaked?/2` — established theme-hygiene assertion helper.
- `commands.destructive` theme mapping — already wired through `Chrome.CommandBar` and `Workspace.Inspector` consumers; Phase 25 inherits without theme changes.
- `layout_smoke_test.exs` size-contract loop pattern (`for {width, height} <- [{64, 22}, {80, 24}]`) — proven precedent for per-tab adoption.

### Established Patterns

- Stateful widgets stored in sibling `state.ex` modules with `init/1`/`handle_event/2`/`render/2` lifecycle (the `boards_view.ex` precedent).
- Screen-owned event routing: `handle_key` dispatches to widget `handle_event/2`, inspects `{state, action}` tuple, performs domain side effects via context modules.
- Theme routing through `Foglet.TUI.Presentation.theme_mappings()` only — never `Theme` slot atoms hardcoded in screens.
- Per-tab render tests asserting primitive sentinel presence + empty-state copy on empty fixtures.

### Integration Points

- Account screens consume `Foglet.Accounts` for profile/prefs/SSH-key mutations.
- Moderation screens consume `Foglet.Authorization` scopes and read-only context queries.
- Sysop screens consume `Foglet.Config` (with actor-aware `put/3`) and `Foglet.Boards` for board/category management.
- All three already declare `:operator` mode (Phase 17) and use Chrome V2 (Phase 18).

</code_context>

<specifics>
## Specific Ideas

- **Account prefs RadioGroup field (D-03):** User chose to extend `Modal.Form` with a RadioGroup-style enum field rather than keep prefs bespoke. The theme-swatch and any other enumerated preference should cycle on arrow keys while preserving the form's submit/dirty/error contract.
- **Selection moves into ConsoleTable (D-05):** Don't keep parallel `selected_index` state in screen modules; the wrapped `Display.Table` cursor is the single source of truth.
- **Per-tab smoke fixtures (D-09):** 11 converted tabs at `[{64, 22}, {80, 24}]` — that's the explicit count to plan against.

</specifics>

<deferred>
## Deferred Ideas

- **Live wiring of `Workspace.Inspector`** — UI-02, deferred to v1.4. No production usage in Phase 25.
- **Wide-terminal layouts beyond 80x24** — UI-05 enhancement; not required.
- **New theme palette slots / color tuning** — UI-03; explicitly excluded.
- **New moderation case-management workflows** (queue review, sanctions) — UI-04; deferred.
- **Ultra-compact chrome variants** — UI-01; deferred.

### Reviewed Todos (not folded)

None — no todos matched Phase 25.

</deferred>
