# Phase 4: MainMenu - Context

**Gathered:** 2026-04-21
**Status:** Ready for planning
**Workstream:** phase-03-screen-audit

<domain>
## Phase Boundary

Audit `main_menu.ex` as a restraint pass, not a redesign:

- keep the welcome line plus the three existing menu rows,
- route theme/domain access through the Phase 0 helpers,
- document the inherited landmines in the moduledoc,
- preserve MainMenu as intentionally stateless and intentionally sparse.

This phase exists to make the screen more explicit and more defensible, not richer.

**In scope:**
- Ensure MainMenu uses the Phase 0 helper pattern required by `MENU-01`.
- Add or expand moduledoc guidance for intentional statelessness (`MENU-05`).
- Preserve and document the render-vs-KeyBar duplication (`MENU-02`).
- Preserve and document the plain `text/2` menu-row rendering (`MENU-03`).
- Reorder the module only as needed to satisfy `AUDIT-18`, with MainMenu's stateless deviation documented.
- Verify `AUDIT-05..22`, `AUDIT-16`, and `AUDIT-17` with extra sparseness scrutiny.

**Out of scope:**
- Any new content row, badge, divider, banner, status detail, date/time line, or session-info panel.
- Any conversion of the menu rows to `SelectionList`, `Button`, or another interactive widget.
- Any new `screen_state[:main_menu]` entry or default state helper.
- Any cleanup that changes the visible density or reinterprets the screen's role.

</domain>

<decisions>
## Implementation Decisions

### Screen density and layout

- **D-01:** Keep the current blank spacer line between the welcome line and the three menu rows.
  The workstream should interpret the roadmap's "exactly 4 content lines" wording as **four
  non-empty content lines**, not as a mandate to remove the existing spacer.
- **D-02:** No additional rows are allowed above, between, or below the existing visible content.
  MainMenu is the most protected screen for future whitespace claims from Milestones 4, 6, and 9.
- **D-03:** The screen remains a minimal gateway, not a dashboard. No "helpful" chrome additions
  are permitted inside the content area.

### Statelessness

- **D-04:** MainMenu remains **intentionally stateless**. There is no `screen_state[:main_menu]`
  key and no `init_screen_state/1` function for this screen.
- **D-05:** The moduledoc must say this explicitly and warn future contributors not to add a
  default state map reflexively just because other screens have one. This is MainMenu's
  documented `AUDIT-19` deviation.

### Load-bearing menu structure

- **D-06:** Keep the duplication between the rendered menu metadata and the KeyBar metadata.
  They serve different output formats and should stay separate rather than being DRYed into a
  shared formatter or shared list shape.
- **D-07:** The `[B]`, `[C]`, and `[Q]` rows remain plain `text/2` calls. `SelectionList`,
  `Button`, and similar widgets are the wrong primitives for this screen.
- **D-08:** KeyBar hints stay unchanged from today's screen behavior.

### Structural scope

- **D-09:** This phase should be treated as a helper/documentation/discipline pass. Beyond any
  required helper swap or section-order cleanup, there should be **no structural rewrite** of the
  screen.
- **D-10:** The existing terminal-size fallback for the compose shortcut path remains valid as-is
  unless the planner finds a rubric-mandated reason to touch it. This phase is not a terminal-size
  rethink.

### the agent's Discretion

- Exact moduledoc wording, as long as it explicitly covers intentional statelessness, preserved
  duplication, and reserved whitespace.
- Whether the helper usage change in `MENU-01` is a no-op because the current code already uses the
  Phase 0 pattern, or whether the requirement is satisfied by verification plus documentation only.
- Exact `AUDIT-18` section ordering for a stateless screen with only `render/1` and `handle_key/2`.

</decisions>

<specifics>
## Specific Ideas

- Keep the current visual rhythm: welcome line, one blank spacer, then the three menu rows.
- If a future contributor wants to add last-callers, badges, or oneliners, that belongs to the
  milestone that owns that feature, not to this audit phase.
- MainMenu should read as "nothing extra here by accident" after this phase.

</specifics>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase requirements

- `.planning/workstreams/phase-03-screen-audit/ROADMAP.md` — Phase 4 goal and success criteria.
- `.planning/workstreams/phase-03-screen-audit/REQUIREMENTS.md` — `MENU-01..MENU-05` plus inherited `AUDIT-05..22`.
- `.planning/workstreams/phase-03-screen-audit/STATE.md` — workstream-level locked decisions, including MainMenu's intentional-stateless expectation.

### Research and landmines

- `.planning/workstreams/phase-03-screen-audit/research/ARCHITECTURE.md` §3.2 — identifies MainMenu as intentionally stateless and calls for that to be documented.
- `.planning/workstreams/phase-03-screen-audit/research/PITFALLS.md` — MainMenu sparseness trap, load-bearing duplication, and terminal-size fallback notes.
- `.planning/workstreams/phase-03-screen-audit/research/SUMMARY.md` — confirms the `@menu_keys` / `@menu_items` duplication is load-bearing.

### Prior phase context this phase inherits

- `.planning/workstreams/phase-03-screen-audit/phases/00-cross-cutting-extractions-prelude/00-CONTEXT.md` — Phase 0 helper API decisions.
- `.planning/workstreams/phase-03-polish/phases/01-widget-foundation-theme-screen-chrome/01-CONTEXT.md` — ScreenFrame, theme, and chrome conventions MainMenu still sits within.

### Code to read before planning

- `lib/foglet_bbs/tui/screens/main_menu.ex` — current screen implementation.
- `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex` — chrome contract MainMenu renders through.
- `lib/foglet_bbs/tui/theme.ex` — theme contract used by the screen.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable assets

- `Foglet.TUI.Theme.from_state/1` is already available and currently used by MainMenu.
- `ScreenFrame.render/4` already wraps the screen correctly.
- `Foglet.TUI.Screens.NewThread.init_screen_state/1` is already the compose-path integration point when `[C]` is pressed.

### Established patterns

- MainMenu currently has no `screen_state` ownership and cleanly returns `:no_match` for unrelated keys.
- The content area is built with a simple `column` and plain `text/2` rows; this matches the workstream's preferred restraint for this screen.
- The current implementation already expresses the screen as a lightweight router rather than a stateful UI surface.

### Integration points

- `[B]` routes to `:board_list` and triggers `{:load_boards}`.
- `[C]` routes to `:new_thread`, seeds `screen_state[:new_thread]`, and triggers `{:load_boards_for_new_thread}`.
- `[Q]` terminates with `{:terminate, :logout}`.

</code_context>

<deferred>
## Deferred Ideas

- Last callers, news, notification badges, and oneliners remain deferred to the milestones that own those features.
- Any attempt to replace the flat menu with a richer widget or multi-pane layout is deferred and out of scope for this audit.
- Removing the spacer line is explicitly deferred for now; the user chose to preserve the current visual rhythm.

</deferred>

---

*Phase: 04-mainmenu*
*Context gathered: 2026-04-21*
