# Phase 20: Rich Rows and Thread Flow — Specification

**Created:** 2026-04-25
**Ambiguity score:** 0.13 (gate: ≤ 0.20)
**Requirements:** 6 locked

## Goal

`ThreadList` rows scan visually by thread state — a leading state-glyph cluster (unread/read, sticky, locked) replaces the `[S] ` text prefix, the focused row is unambiguously distinguishable, the existing `@handle · N posts · age` metadata is preserved, and a new `Foglet.TUI.Widgets.List.RichRow` primitive lands as the source rendering for these rows so later phases (BoardList in Phase 21, operator screens in Phase 25) can adopt the same surface in their own phase work.

## Background

`Foglet.TUI.Screens.ThreadList` currently renders rows through `Foglet.TUI.Widgets.List.ListRow.render_with_metadata/6`. Sticky threads receive a `[S] ` text prefix in front of the title, locked threads are not visualized at all (the `:locked` field on `Foglet.Threads.ThreadEntry` exists but is not rendered), and unread is communicated only by a bold title plus dim metadata via `theme.primary.fg + :bold`. Selection is shown as a leading `> ` marker with reverse-color row styling. Metadata reads `@handle · N posts · time-ago` separated by `·` middle-dots. Width math is already display-width safe after Phase 16; theme slots (Phase 17) include `success`, `info`, `accent`, `selected`, etc.; Chrome V2 (Phase 18) wraps the screen.

There is no `RichRow` widget. SCREENS.md proposes one as a shared primitive with leading state glyphs, primary text, right metadata, optional subtitle, selection rendering, and theme routing — and lists it as primary leverage for the v1.3 facelift. Phase 20 introduces this primitive and migrates `ThreadList` to it. Phase 20 also locks the visual semantics for thread state: `◆` unread (filled diamond), `◇` (or omitted) read (open diamond), `●` sticky (filled circle), plus a glyph for locked. (SCREENS.md proposes `●` for unread; this milestone deliberately substitutes `◆` for unread and `●` for sticky — the diamond family carries read/unread; the filled circle carries sticky/pinned. CONTEXT.md D-05 and the Phase 20 plans already encode this mapping.) Phase 19 (Main Menu Dashboard) is in flight on a parallel track and does not touch `ThreadList`.

This phase is not a `ListRow` rewrite or a sweeping migration. `ListRow.render/3` and `ListRow.render_with_metadata/6` continue to exist for `NewThread` (board picker), `BoardList`, `Sysop` boards/users, `Account` SSH keys, and the shared invites surface. Each of those screens adopts `RichRow` (or its successor) inside its own roadmap phase.

## Requirements

1. **`RichRow` primitive lands**: A new `Foglet.TUI.Widgets.List.RichRow` widget renders rows with a leading state-glyph cluster, primary text, right-aligned metadata, selection rendering, and theme-routed styling.
   - Current: No `RichRow` module exists; `ListRow.render_with_metadata/6` is the only metadata-aware row renderer and offers no leading state cluster.
   - Target: `Foglet.TUI.Widgets.List.RichRow` exists, is documented, has a stable public API for the four inputs above, and is theme-routed through `Foglet.TUI.Theme` slots only (no hardcoded color atoms).
   - Acceptance: A focused unit test renders `RichRow` with each combination of (selected/unselected) × (with/without state glyphs) × (with/without metadata) and asserts the produced view has the expected glyph cells, primary text, metadata, and theme-slot styling. No call to `Foglet.TUI.Widgets.List.RichRow` in `lib/` references a hardcoded color outside `Foglet.TUI.Theme`.

2. **Thread row state glyphs**: `ThreadList` rows render unread/read, sticky, and locked state via semantic glyphs in a leading cluster, replacing the existing `[S] ` text prefix.
   - Current: Sticky shows as `[S] ` text prefix; locked is invisible; unread is title-bold only.
   - Target: Each row begins with a fixed-width, multi-cell state cluster with **independent slots** for read/unread, sticky, and locked. The unread slot shows `◆` (filled diamond) when `has_unread`, `◇` (open diamond) when read, or visual whitespace if read state is rendered as whitespace. The sticky slot shows `●` (filled circle) when `sticky`, otherwise visual whitespace. The locked slot shows a single-cell locked glyph when `locked`, otherwise visual whitespace. **Sticky and read/unread are orthogonal**: a sticky+unread thread renders both glyphs (e.g. `◆ ● title…`), a sticky+read thread renders both (`◇ ● title…` or whitespace + `●`), a non-sticky+unread thread renders only the unread glyph in slot 0 with the sticky slot padded as whitespace. Read+normal+unlocked rows show the entire cluster as visual whitespace of the same width so columns stay aligned. The `[S] ` text prefix is removed from `ThreadList` rendering.
   - Acceptance: A focused render test asserts that (a) an unread thread row contains `◆` in the leading cluster, (b) a sticky thread row contains `●`, (c) a locked thread row contains the locked glyph, (d) a sticky+unread row contains BOTH `◆` AND `●` in the leading cluster, (e) a read+non-sticky+unlocked thread row's leading cluster pads to the same display-width as a fully-glyphed cluster, and (f) no row in any state contains the literal string `"[S] "`.

3. **Thread metadata preserved**: `ThreadList` rows continue to show `@handle · N posts · age` right-aligned with `·` (middle-dot) separators.
   - Current: `ThreadList.thread_metadata/1` formats `"@#{handle} · #{count} #{post_word} · #{time_segment}"` and renders right-aligned through `ListRow.render_with_metadata/6`.
   - Target: Same metadata string format, same right-alignment contract, now rendered through `RichRow` instead of `ListRow.render_with_metadata/6`.
   - Acceptance: A focused render test asserts the metadata string and `·` separators are unchanged for at least one read row, one unread row, and one sticky row, and that metadata is right-aligned within the row's display-width budget.

4. **Selection clarity**: The focused thread row is visually distinguishable from non-focused rows in a way that does not depend solely on the `> ` marker.
   - Current: Selected rows render with `> ` marker plus `theme.selected.fg`/`theme.selected.bg` styling; non-selected rows render with `  ` and `theme.unselected.fg`.
   - Target: The focused row remains unambiguously distinguishable. The treatment may keep the `> ` marker, replace it (e.g. `▌`), or augment it, provided the focused row passes the acceptance test below.
   - Acceptance: A focused render test asserts that the focused row's view has at least one styling property (foreground, background, or `:bold` style) that no non-focused row in the same render shares. The test passes for both an unread+focused row and a read+focused row.

5. **64x22 priority contract**: At a 64x22 terminal, the leading state cluster and the right metadata always render fully; the title is the only segment allowed to truncate.
   - Current: `ListRow.render_with_metadata/6` already protects metadata at any width by truncating the title with `…`, with a 20-cell minimum title attempt before below-minimum fallback.
   - Target: `RichRow` preserves the same priority: state cluster width is fixed; metadata is rendered in full; title truncates with `…` when needed. The 20-cell minimum title attempt is preserved.
   - Acceptance: A focused render test renders a thread with a long title at 64-cell content width and asserts (a) the state cluster is fully present, (b) the full metadata string is present, (c) the title contains `…`, and (d) total row display-width does not exceed 64 cells.

6. **`RichRow` reusable beyond `ThreadList`**: `RichRow` exposes a public API surface that does not assume `ThreadList`-specific data and is documented for reuse by later phases.
   - Current: No `RichRow` module exists; `ListRow.render_with_metadata/6` carries `ThreadList`-shaped assumptions in its signature (e.g. `unread?` flag).
   - Target: `Foglet.TUI.Widgets.List.RichRow` accepts state input as a generic state-cluster shape (e.g. a list/struct of state atoms or glyph cells) rather than a `unread?` boolean alone, so future callers (Phase 21 `BoardList`, Phase 25 operator surfaces) can express `subscribed`, `category`, `required`, etc. without modifying the widget's API. A module-level `@moduledoc` documents the contract.
   - Acceptance: A focused unit test instantiates `RichRow` with a non-thread state shape (e.g. `[:subscribed, :required]` or equivalent) and renders the expected glyph cluster without referencing `Foglet.Threads`. The `@moduledoc` exists and lists the supported inputs.

## Boundaries

**In scope:**
- New `Foglet.TUI.Widgets.List.RichRow` widget under `lib/foglet_bbs/tui/widgets/list/`.
- Migration of `Foglet.TUI.Screens.ThreadList` row rendering from `ListRow.render_with_metadata/6` to `RichRow`.
- Visual treatments for unread/read, sticky, and locked thread states inside `RichRow`'s state cluster.
- Removal of the `[S] ` text prefix from `ThreadList`.
- Selection rendering treatment for `RichRow` that satisfies the selection-clarity acceptance test.
- Preservation of the existing `@handle · N posts · age` metadata format with `·` separators.
- Size-contract render coverage at 64x22, 80x24, and at least one wider terminal size.
- `@moduledoc` documentation of the `RichRow` public API for later-phase adopters.

**Out of scope:**
- Migration of any other caller of `ListRow.render/3` or `ListRow.render_with_metadata/6` — Phase 21 (`BoardList`), Phase 25 (`Sysop` boards/users, `Account` SSH keys, shared invites), and any other adoption work belongs to those phases.
- A separate "focused-thread details" strip below the `ThreadList`. THREADS-02 is satisfied by selection clarity (Requirement 4) rather than a per-selection details panel.
- Wide-terminal inspector pane for thread details. SCREENS.md treats inspectors as later phase enhancement; v1.3 progressive enhancement may be added in a later phase.
- ASCII-only fallback glyph set. Per SCREENS.md, "everyday UI should be native UTF-8"; Phase 20 ships a single Unicode glyph set across all themes.
- Row striping (alternating background). SCREENS.md flags it as optional; Phase 20 leaves it out to avoid visual noise and theme-coupling complexity.
- Removing or rewriting `ListRow.render/3` or `ListRow.render_with_metadata/6`. They keep their current contracts and current callers.
- Changes to `ThreadList` keyboard handling, navigation flow, or load orchestration. Open/Compose/Back keys, Up/Down selection, and `load_threads` orchestration remain as today.
- Changes to `Foglet.Threads`, `Foglet.Threads.ThreadEntry`, or any persistence/context layer. The phase consumes the existing `:has_unread`, `:sticky`, `:locked` fields without touching them.

## Constraints

- Foglet remains SSH-first/TUI-first. No browser workflow is introduced.
- All rendering must continue to flow through `Foglet.TUI.Widgets.Chrome.ScreenFrame.render/4` and theme-routed primitives. No hardcoded color atoms in `RichRow` or `ThreadList` row paths.
- All width math must use `Foglet.TUI.TextWidth` helpers (display width, truncation, padding). Byte-length, grapheme-count, and `String.length/1` are not allowed for layout decisions.
- Glyph rendering uses a single Unicode set across all themes. No per-theme ASCII fallback in this phase.
- The state cluster's display width is fixed and identical across all (read/unread, sticky/non-sticky, locked/unlocked) combinations so columns stay aligned.
- `RichRow` adheres to the `Foglet.TUI.Theme` slot vocabulary already established by Phase 17 (no new slots are introduced for Phase 20).
- The 20-cell minimum title attempt established by `ListRow.render_with_metadata/6` is preserved in `RichRow`.
- No new database query, schema field, or context API is introduced. The phase consumes existing `ThreadEntry` fields only.

## Acceptance Criteria

- [ ] `Foglet.TUI.Widgets.List.RichRow` module exists at `lib/foglet_bbs/tui/widgets/list/rich_row.ex` with a public render entry point and module documentation.
- [ ] `Foglet.TUI.Screens.ThreadList` renders rows through `RichRow`. No call to `ListRow.render_with_metadata/` remains in `ThreadList`.
- [ ] No row in any rendered state contains the literal string `"[S] "`.
- [ ] An unread thread row contains `◆` (filled diamond) in the leading cluster.
- [ ] A sticky thread row contains `●` (filled circle) in the leading cluster.
- [ ] A locked thread row contains the locked glyph in the leading cluster.
- [ ] A sticky+unread thread row contains BOTH `◆` AND `●` in the leading cluster (independent slots).
- [ ] A read+non-sticky+unlocked thread row's leading cluster pads to the same display-width as a fully-glyphed cluster (column alignment preserved).
- [ ] At 64-cell content width with a long title, the title truncates with `…` while the full state cluster and full metadata both render without truncation.
- [ ] The focused row's view has at least one styling property (foreground, background, or `:bold` style) that no non-focused row in the same render shares.
- [ ] Metadata for `ThreadList` rows continues to read `@handle · N posts · age` with `·` separators for one-post and many-post cases.
- [ ] `RichRow` accepts a generic state-cluster shape (not a `unread?` boolean alone) and renders correctly when instantiated with a non-`ThreadList` state input.
- [ ] No `RichRow` or `ThreadList` row code path references a hardcoded color outside `Foglet.TUI.Theme`.
- [ ] No new database query, schema field, or context function is added in this phase.
- [ ] Size-contract render tests cover 64x22, 80x24, and at least one wider terminal size.

## Ambiguity Report

| Dimension          | Score | Min   | Status | Notes                                                                       |
|--------------------|-------|-------|--------|-----------------------------------------------------------------------------|
| Goal Clarity       | 0.88  | 0.75  | met    | Glyphs (`◆` unread, `●` sticky, `◇` read) + selection clarity locked; no separate details strip. |
| Boundary Clarity   | 0.92  | 0.70  | met    | `[S]` removal, striping out of scope, ListRow stays for other callers.      |
| Constraint Clarity | 0.85  | 0.65  | met    | Single Unicode set, fixed-width cluster, 64x22 priority contract locked.    |
| Acceptance Criteria| 0.80  | 0.70  | met    | Pass/fail tests cover RichRow, glyphs, metadata, selection, 64x22 contract. |
| **Ambiguity**      | 0.13  | ≤0.20 | met    | Gate passed.                                                                |

Status: met = meets minimum, below = planner treats as assumption

## Interview Log

| Round | Perspective     | Question summary                                                              | Decision locked                                                                                                |
|-------|-----------------|-------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------|
| 1     | Researcher      | What is the primary user-visible delta?                                       | State glyphs + clear selection indicator. No separate focused-thread details strip.                            |
| 1     | Researcher      | Which thread states must be glyph-coded?                                      | Unread/read, sticky, locked.                                                                                   |
| 1     | Researcher      | How does `RichRow` relate to `ListRow`?                                       | New widget alongside `ListRow`; later phases own their own migrations.                                         |
| 2     | Boundary        | Is THREADS-02 satisfied by selection clarity or a details strip?              | Selection clarity only. SPEC reframes THREADS-02's acceptance.                                                 |
| 2     | Simplifier      | Which RICHROW-01 features are required vs deferrable in this phase?          | State glyphs, primary text, metadata, selection, theme routing required. Subtitle/details slot deferred.       |
| 2     | Constraint      | What is the ASCII/fallback policy for the new state glyphs?                  | Single Unicode set, no ASCII fallback.                                                                         |
| 3     | Boundary Keeper | Does the `[S] ` text prefix stay or get removed once `RichRow` ships?         | Removed entirely.                                                                                              |
| 3     | Boundary Keeper | Is row striping in scope?                                                     | Out of scope.                                                                                                  |
| 3     | Constraint      | Priority at 64x22 between state cluster, metadata, and title?                | Cluster + metadata always fit; title truncates first. 20-cell minimum title attempt preserved.                 |

---

*Phase: 20-rich-rows-and-thread-flow*
*Spec created: 2026-04-25*
*Next step: /gsd-discuss-phase 20 — implementation decisions (glyph choices, selection treatment, RichRow API surface details)*
