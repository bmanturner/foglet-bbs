# Phase 19: main-menu-dashboard - Context

**Gathered:** 2026-04-25 (assumptions mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 19 tightens the existing Main Menu (`Foglet.TUI.Screens.MainMenu`) into the Classic Modern BBS front porch from `SCREENS.md`: visible direct destination keys in a boxed Navigation panel, an Oneliners panel side-by-side, a non-duplicative Chrome V2 command bar that surfaces actions only, and proven side-by-side layout at 64x22, 80x24, and at least one wider terminal size. Phase 19 does NOT add a destination cursor, Enter-to-open behavior, new dashboard data queries (unread/board/session/moderation counts), an Activity panel, browser workflows, Chrome V2 frame rewrites, or facelifts to other screens.

</domain>

<decisions>
## Implementation Decisions

### Dedup Architecture
- **D-01:** Build one canonical "visible destinations" list and one canonical "visible actions" list inside `MainMenu`. The body Navigation panel renders from the destinations list; the command bar renders from the actions list. Both flow from the same source-of-truth so the two cannot drift, and the dedup contract is "destinations and actions are mutually exclusive sets" rather than a post-hoc subtraction.
- **D-02:** `Foglet.TUI.Widgets.Chrome.CommandBar`, `Chrome.Normalizer`, and `Chrome.ScreenFrame` remain passive widgets. Main Menu's "what is a destination vs. action" rule does NOT leak into shared chrome; this preserves Phase 18 D-01/D-02.

### Body Destinations vs. Command Bar Actions
- **D-03:** Body Navigation panel rows are destinations only. The full destination set (subject to role gating via `Foglet.TUI.Screens.ShellVisibility`) is:
  - `B` Boards (always for any session)
  - `C` Compose thread (always for any session)
  - `A` Account (when `ShellVisibility.account_visible?/1`)
  - `M` Moderation (when `ShellVisibility.moderation_visible?/1`)
  - `S` Sysop (when `ShellVisibility.sysop_visible?/1`)
  - `Q` Logout (always — kept in body to match the SCREENS.md sketch as a session-control row alongside the destination rows)
- **D-04:** Command bar shows ACTIONS that are NOT destinations:
  - `O` Post Oneliner (whenever `current_user` is non-nil) — moved out of the body per the destinations-vs-actions principle.
  - `H` Hide oneliner (when a hideable oneliner is selected AND user is mod or sysop)
  - `↑/↓ Select` oneliner (when `recent_oneliners` is non-empty) — surfaces the existing row-selection behavior so it is discoverable.
- **D-05:** `H` authorization continues through `Bodyguard.permit?(Foglet.Authorization, :hide_oneliner, user, :site)`. Tests must lock that `H` does NOT appear in the command bar for regular users even when an oneliner is selected, and that it DOES appear for mod/sysop users with a non-empty hideable oneliner focused. (`:hide_oneliner` is in `@mod_site_actions` per `lib/foglet_bbs/authorization.ex:58`; sysops are permitted globally; regular users hit the deny fallthrough.)
- **D-06:** No fallback affordance is invented to keep the command bar populated. If a session has no `O` (anonymous), no `H` (regular user or no hideable focus), and no oneliners (empty list), the command bar may render with empty groups — `CommandBar.render/3` already handles this via `Enum.reject(&(&1.commands == []))`.

### Body Visual (SCREENS.md Adoption)
- **D-07:** Adopt the SCREENS.md Main Menu visual shape. The body has a boxed `┌ Navigation ┐` panel on the left and a boxed `┌ Oneliners ┐` panel on the right. The Activity panel from the SCREENS.md sketch is explicitly OUT (per user direction; consistent with SPEC out-of-scope on new dashboard data queries).
- **D-08:** Navigation panel rows are shaped as `glyph + label + right-aligned key`. Recommended glyph set from `SCREENS.md` §Main Menu lines 270-280:
  - `●` Boards
  - `✎` Compose thread
  - `◇` Account
  - `⚑` Moderation
  - `▣` Sysop
  - `↯` Logout
  Glyphs route through theme slots (Phase 17 added `success`/`info`/`badge` slots), never hardcoded color atoms. Right-aligned key column uses `Foglet.TUI.TextWidth` so multi-cell glyphs and labels stay flush.
- **D-09:** The Phase 19 delta adopts SCREENS.md visual shape ONLY. It does NOT adopt SCREENS.md's selection-list / Up-Down-cursor / Enter-to-open destination behavior — Phase 19 SPEC requirement 2 explicitly rejects a destination cursor.
- **D-10:** Glyph selection is planner discretion within the SCREENS.md set. If positioned-render tests at 64x22 prove glyph cell width breaks alignment in any size contract, fall back to ASCII-only rows shaped as `[K] Label  →` or revert to the existing `  [K] Label` rows for that row. This is the same deliberate ASCII-fallback convention Chrome V2 used for breadcrumbs (Phase 18 D-04).
- **D-11:** Replace the current `Welcome back, handle.` line. The Navigation panel header is the boxed `Navigation` label; no marketing-style welcome line.

### Side-by-Side Layout
- **D-12:** Continue using `split_pane(direction: :horizontal, ...)` (the only horizontal-split callsite in `lib/foglet_bbs/tui`). Do NOT introduce manual `TextWidth` column math, do NOT add a compact-mode threshold that hides panels at narrower widths, and do NOT replace `split_pane` with a custom layout primitive in this phase. The ratio and `min_size` may be tuned by the planner so the boxed panels both fit at 64x22.
- **D-13:** Prove the 64x22 / 80x24 / wider contract via positioned-render tests using `Raxol.UI.Layout.Engine.apply_layout/2` at the `[{64,22}, {80,24}, {132,50}]` triple Phase 18 standardized in `test/foglet_bbs/tui/layout_smoke_test.exs:119-183`.
- **D-14:** Oneliner clipping continues through `Foglet.TUI.TextWidth.slice_to_width/2` (already at `lib/foglet_bbs/tui/screens/main_menu.ex:318-320`). Existing `@oneliner_handle_limit`, `@oneliner_body_limit`, and `@oneliner_display_limit` constants are planner discretion to retune for the boxed panel, as long as the empty / one-row / many-row / long-Unicode acceptance criteria are still met.

### Test Coverage Shape
- **D-15:** Behavior coverage extends `test/foglet_bbs/tui/screens/main_menu_test.exs` (do not create a new file). Required test additions:
  - Role visibility for body destinations: anonymous (B/C/Q only), authenticated user (B/C/A/Q), mod (B/C/A/M/Q), sysop (B/C/A/M/S/Q).
  - Direct hotkey preservation: `B`, `C`, `A`, `M`, `S`, `Q` keep their current screen-transition or terminate behavior, gated by `ShellVisibility`.
  - Negative path: `Enter` returns `:no_match` for destinations.
  - Command bar non-duplication: none of `B/C/A/M/S` appear in any command-bar group.
  - Command bar action visibility: `O` appears for any authenticated user; `H` appears only for mod/sysop AND when a hideable oneliner is selected; `↑/↓ Select` appears only when `recent_oneliners` is non-empty.
  - Oneliner panel: nil/empty entries, single oneliner, more than `@oneliner_display_limit` entries, long Unicode-safe clipping (combining marks and CJK characters per Phase 16 width-test fixtures).
- **D-16:** Size-contract coverage extends `test/foglet_bbs/tui/layout_smoke_test.exs` with a Main Menu positioned-render block at `[{64,22}, {80,24}, {132,50}]`. Assertions:
  - Both Navigation and Oneliners panels render side-by-side (no stacking, no panel collapse).
  - No two text elements share `{x, y}` such that they overlap.
  - Oneliner rows are clipped to fit the right-panel inner width without multiline overflow.
- **D-17:** Do not create `main_menu_layout_test.exs` or any other new file. Phase 18 placed its size contracts inside `layout_smoke_test.exs`, establishing precedent.

### Claude's Discretion
- Exact module/struct names for the destinations-vs-actions split (D-01, D-04) are planner discretion. They should produce one canonical source of truth so the body and command bar can never drift.
- Exact glyph atoms (D-08) are planner discretion within the SCREENS.md suggested set; the ASCII-fallback gate point is planner discretion.
- Exact label text on command-bar action atoms is planner discretion (e.g., `O` may render as "Post Oneliner" in the body-replacement plan or "Oneliner" if width forces it). The labelled command-bar contract (`%{key, label, priority}` per `Chrome.CommandBar.normalize_groups/1`) must still hold.
- Exact `split_pane` ratio and `min_size` values (D-12) are planner discretion as long as 64x22 positioned-render tests pass with both panels visible side-by-side.
- Whether the Navigation panel uses an explicit boxed border widget, `column` with a `border:` style, or a thin "panel" helper is planner discretion. The acceptance criterion is that the body visually presents as two side-by-side boxed panels matching the SCREENS.md sketch (minus Activity).

### Folded Todos
None.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Locked Phase Scope
- `.planning/phases/19-main-menu-dashboard/19-SPEC.md` — Locked Phase 19 requirements, boundaries, constraints, acceptance criteria, ambiguity report (0.19), and interview decisions.
- `.planning/ROADMAP.md` §Phase 19 — Milestone position, dependency on Phase 18, requirements `HOME-01`/`HOME-02`/`HOME-03`, and success criteria.
- `.planning/REQUIREMENTS.md` §Main Menu Dashboard — Requirement IDs `HOME-01`, `HOME-02`, `HOME-03`.
- `SCREENS.md` §Main Menu (lines 255-304) — Visual target sketch, glyph set, panel layout. Phase 19 adopts the visual shape but explicitly REJECTS the SCREENS.md "selection list with selected_index" implementation path because the SPEC bans a destination cursor.
- `SCREENS.md` §Design Principles (lines 71-96) and §Chosen Direction (lines 41-69) — Classic Modern BBS rhythm and Unicode-as-semantics guidance that Phase 19 must respect.

### Dependency Contracts
- `.planning/phases/16-unicode-width-foundation/16-CONTEXT.md` — `Foglet.TUI.TextWidth` width-helper contract used for column alignment, glyph cell-width, and oneliner clipping.
- `.planning/phases/17-theme-and-mode-metadata/17-CONTEXT.md` — `:bbs` mode metadata for Main Menu and theme-slot contract (`success`/`info`/`badge`/etc.) used for glyph styling.
- `.planning/phases/18-chrome-v2/18-CONTEXT.md` — `Chrome.ScreenFrame` composition boundary, grouped `Chrome.CommandBar` contract, and the `[{64,22},{80,24},{132,50}]` size-contract triple.

### Existing Code Touch Points
- `lib/foglet_bbs/tui/screens/main_menu.ex` — Current `MainMenu` screen module to refactor.
- `lib/foglet_bbs/tui/screens/shell_visibility.ex` — `account_visible?/1`, `moderation_visible?/1`, `sysop_visible?/1`, `invites_visible?/2` predicates that gate role-based body destinations.
- `lib/foglet_bbs/authorization.ex` — `:hide_oneliner` policy in `@mod_site_actions` (line 58) and `@mod_board_actions` (line 72), used to gate the command-bar `H` action.
- `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex` — Single screen-facing chrome composition entry point (`render/4`).
- `lib/foglet_bbs/tui/widgets/chrome/command_bar.ex` — Grouped command-bar widget; `normalize_groups/1` accepts `[%{label, commands: [%{key, label, priority}]}]` or legacy `[{key, label}]` lists.
- `lib/foglet_bbs/tui/widgets/chrome/normalizer.ex` — Legacy compatibility adapter that promotes flat key lists into grouped commands.
- `lib/foglet_bbs/tui/text_width.ex` — `slice_to_width/2`, measurement, padding, and width-safe alignment helpers.
- `lib/foglet_bbs/tui/theme.ex` — Theme slot contract; theme routing for glyphs, panel borders, and key labels must use slots, never hardcoded color atoms.
- `lib/foglet_bbs/tui/widgets/list/list_row.ex` — Existing row pattern reference for selection markers and theme routing if a row primitive is introduced or reused.

### Test Anchors
- `test/foglet_bbs/tui/screens/main_menu_test.exs` — Existing role-visibility, hotkey, Enter-no-match, and oneliner test cases to extend with the destinations-vs-actions split, command-bar dedup, and `H` role gating.
- `test/foglet_bbs/tui/layout_smoke_test.exs` — Existing positioned-render harness using `Raxol.UI.Layout.Engine.apply_layout/2`; Main Menu currently has an 80x24 render check at lines 318-378 and Phase 19 must add a 3-size positioned-render block.
- `test/foglet_bbs/tui/text_width_test.exs` — Width fixtures (combining marks, CJK) reusable for long-Unicode oneliner clipping coverage.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Foglet.TUI.Screens.MainMenu` — Stateless screen with destination hotkeys, oneliner row tracking, and a `split_pane`-driven side-by-side body. Phase 19 refactors but does not rewrite it.
- `Foglet.TUI.Widgets.Chrome.ScreenFrame.render/4` — Single screen-facing chrome boundary; Phase 19 keeps using it. Already wires theme, breadcrumb, status, and the grouped command bar.
- `Foglet.TUI.Widgets.Chrome.CommandBar` — Accepts grouped commands or legacy flat key lists (via `Normalizer`); already drops empty groups via `Enum.reject(&(&1.commands == []))`. Phase 19 just passes a different group set.
- `Foglet.TUI.Screens.ShellVisibility` — Role-gating predicates already centralize `account_visible?`/`moderation_visible?`/`sysop_visible?`. Phase 19 destinations and command-bar actions both consult these.
- `Foglet.TUI.TextWidth.slice_to_width/2` — Already used by Main Menu for oneliner clipping; reusable for right-aligned key column padding.
- `Foglet.Authorization` — `:hide_oneliner` is wired and tested; Phase 19 only piggybacks on it for command-bar visibility of `H`.
- `Raxol.UI.Layout.Engine.apply_layout/2` (via `test/foglet_bbs/tui/layout_smoke_test.exs`) — Positioned-render harness Phase 18 already uses for size contracts.

### Established Patterns
- TUI screen render functions stay pure over already-loaded state; data flows from `state.recent_oneliners`, `state.current_user`, `state.session_context`, and `state.terminal_size`. Phase 19 must NOT introduce new context calls or schedule new commands.
- Widget styling routes through `Foglet.TUI.Theme` slots; no hardcoded color atoms.
- Width-sensitive layout uses `TextWidth` rather than `String.length/1` or grapheme counts.
- Tests mirror `lib/` paths under `test/foglet_bbs/tui/`; size contracts live inside `layout_smoke_test.exs` per Phase 18 precedent.
- Role gating uses `ShellVisibility` predicates for visibility and `Bodyguard.permit?/permit/4` for actions; visibility is never authorization (Pitfall 3 from `MainMenu` moduledoc).
- Stateless screens avoid `screen_state[:main_menu]` for destination state — Phase 19 SPEC requirement 2 keeps this invariant.

### Integration Points
- `MainMenu.render/1` keeps calling `ScreenFrame.render(state, "Main Menu", content, keys)`. Body `content` becomes a boxed `Navigation`-and-`Oneliners` `split_pane`; `keys` becomes the actions-only grouped command list.
- `MainMenu.handle_key/2` keeps the existing direct hotkey clauses for `B/C/A/M/S/O/H/Q/Up/Down`. The `Enter` clause continues returning `:no_match`. Phase 19 should not add or remove handler clauses except where role visibility tests reveal latent bugs.
- `App` routing for `:main_menu` is unchanged; mode metadata from Phase 17 already declares `:bbs`.

</code_context>

<specifics>
## Specific Ideas

- "Reference SCREENS.md for what the Main Menu should look like" — adopt the boxed Navigation panel + glyph + right-aligned key visual from SCREENS.md §Main Menu lines 264-281.
- "SCREENS.md should show you what we're aiming for (minus the activity box)" — drop the SCREENS.md Activity panel entirely; do not introduce unread/board-count/session-count widgets.
- "The destination list is for destinations, not actions" — strict body/command-bar split: B/C/A/M/S/Q in body, O/H/↑↓ in command bar.
- "H is for mods and sysops only, so make sure that's enforced" — lock the role-gating test for the `H` command-bar atom.
- Q (Logout) lives in the body Navigation panel matching the SCREENS.md sketch, even though it is a session-control action. Treat the Navigation panel as "every top-level keystroke a Home user can issue to leave Home", not strictly "screen transitions only".
- The Navigation `↑/↓ Select` hint shows only when `recent_oneliners` is non-empty so empty-state Main Menu does not advertise a no-op.

</specifics>

<deferred>
## Deferred Ideas

- Activity panel with unread counts, pinned-thread updates, active-session counts, or moderation queue counts — `SCREENS.md` describes this but Phase 19 explicitly excludes it. Belongs to a future phase that adds the underlying context queries (and only after the queries are cheap, per `SCREENS.md` line 304).
- Destination cursor + Enter-to-open destination behavior — explicitly rejected by Phase 19 SPEC requirement 2; not deferred to a near-term phase, but could be revisited in a v2 milestone if the product direction shifts.
- Operator console primitives (`Display.Badge`, `Display.KvGrid`, etc.) — Phase 24 territory. Phase 19 does not introduce them.
- Larger-terminal inspector panes for Home — `UI-02` v2 territory.
- Theme palette retuning to improve glyph contrast on real SSH terminals — `UI-03` v2 territory; Phase 19 uses the slots Phase 17 already shipped.

### Reviewed Todos (not folded)
None — no matching todos for this phase.

</deferred>

---

*Phase: 19-main-menu-dashboard*
*Context gathered: 2026-04-25*
