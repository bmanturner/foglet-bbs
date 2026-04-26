# Phase 20: rich-rows-and-thread-flow - Context

**Gathered:** 2026-04-25 (assumptions mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 20 introduces a new `Foglet.TUI.Widgets.List.RichRow` primitive under `lib/foglet_bbs/tui/widgets/list/` and migrates `Foglet.TUI.Screens.ThreadList` row rendering from `ListRow.render_with_metadata/6` to `RichRow`. Thread rows render unread/read, sticky, and locked state through a fixed-width leading state-glyph cluster, the `[S] ` text prefix is removed, the focused row is unambiguously distinguishable beyond the `> ` marker, and the existing `@handle · N posts · age` metadata format is preserved with `·` separators and right-alignment.

Phase 20 does NOT migrate any other caller of `ListRow.render/3` or `ListRow.render_with_metadata/6` (Phase 21 owns BoardList; Phase 25 owns Sysop boards/users, Account SSH keys, and the shared invites surface). It does NOT add a focused-thread details strip below the list (THREADS-02 is satisfied by selection clarity alone). It does NOT add wide-terminal inspector panes, ASCII fallback glyphs, row striping, or any change to `Foglet.Threads`, `ThreadEntry`, persistence, or `ThreadList` keyboard/navigation handling. No new database query, schema field, or context API is introduced.

</domain>

<decisions>
## Implementation Decisions

### RichRow Public API Surface

- **D-01:** `Foglet.TUI.Widgets.List.RichRow` exposes a single primary entry point `render/1` that accepts a keyword list. Required keys: `:title`, `:metadata`, `:state_cluster`, `:selected`, `:theme`. Optional: `:width` (default 80, matching `ListRow.render_with_metadata/6` at `lib/foglet_bbs/tui/widgets/list/list_row.ex:97`), `:focus_marker` (default `"▌ "`), `:emphasis` (replaces the boolean `unread?` arg from `ListRow.render_with_metadata/6`; e.g. `:bold` for unread).
- **D-02:** `:state_cluster` is a list of state atoms — e.g. `[]`, `[:unread]`, `[:sticky, :locked]` — not a `unread?` boolean and not raw glyph strings. `RichRow` itself owns the atom→glyph→theme-slot mapping. This keeps the public API stable across Phase 20 (`:unread`, `:sticky`, `:locked`), Phase 21 (`:subscribed`, `:category`, `:required`), and Phase 25 (operator surface states) without a signature bump. Unknown atoms render as visual whitespace of the cluster's fixed width.
- **D-03:** The cluster's total display width is a module attribute (e.g. `@cluster_width`) computed via `Foglet.TUI.TextWidth.display_width/1` so it stays identical across all (read/unread, sticky/non-sticky, locked/unlocked) combinations. Read+normal+unlocked rows pad to the same width as a fully-glyphed cluster, satisfying SPEC acceptance criterion (d) on the leading-cluster column-alignment contract.
- **D-04:** A module-level `@moduledoc` documents the public input contract, the supported state atoms (`:unread`, `:sticky`, `:locked` shipped in Phase 20; `:subscribed`, `:category`, `:required` reserved for Phase 21), and the size-contract priority (cluster + metadata always render fully; title truncates first; 20-cell minimum title attempt preserved). Moduledoc style follows `SelectionList`'s precedent at `lib/foglet_bbs/tui/widgets/list/selection_list.ex:1-22`.

### Glyph Choices and Theme-Slot Mapping

- **D-05:** Glyph mapping (locked at user direction):
  - `unread` → `◆` (U+25C6)
  - `read` → `◇` (U+25C7) or visual whitespace of the cluster's fixed width
  - `sticky` → `●` (U+25CF)
  - `locked` → planner discretion within single-cell glyphs; recommended `⚿` (U+26BF) or `⚑` (U+2691). `🔒` is **forbidden** — it renders as a 2-cell glyph on most terminals and breaks alignment.
- **D-06:** Theme-slot routing is mandatory (no hardcoded color atoms):
  - `unread` (`◆`) → `theme.accent.fg` plus `:bold` style — accent is the existing "look at me / warm highlight" slot per `lib/foglet_bbs/tui/theme.ex:106-115`.
  - `read` (`◇` or whitespace) → `theme.dim.fg` if rendered as a glyph; whitespace needs no styling.
  - `sticky` (`●`) → `theme.info.fg` or `theme.badge.fg` (planner discretion within these two slots; pick whichever has stronger contrast across all nine themes).
  - `locked` → `theme.warning.fg`.
- **D-07:** No per-theme ASCII fallback. Per SPEC constraint and SCREENS.md's "everyday UI should be native UTF-8" guidance, Phase 20 ships a single Unicode glyph set across all themes. If positioned-render tests reveal width breakage in any size contract, the response is to swap the offending atom for a different single-cell Unicode glyph, not to introduce ASCII branching.

### Selection Clarity (Focus Treatment)

- **D-08:** Focused rows render with `▌` (U+258C) as the leading focus marker, replacing the current `> ` marker. This makes `RichRow` visually consistent with Foglet's canonical selection treatment in `SelectionList` (`lib/foglet_bbs/tui/widgets/list/selection_list.ex:100`), `SmartList` (`@focused_marker` at `smart_list.ex:41`), `Tabs` (`tabs.ex:43`), and `Modal` (`modal.ex:82`). The `selection_list.ex` moduledoc names `▌` canonical at lines 19-20.
- **D-09:** Focused row styling combines `theme.selected.fg`, `theme.selected.bg`, and `:bold` style. Non-focused rows render with two leading spaces, `theme.unselected.fg`, and no `bg` slot. Every shipped theme defines `selected.bg` (`theme.ex:113`, `129`, `145`, `161`, `177`, `193`, `209`, `225`, `241`), so the SPEC requirement 4 acceptance test ("at least one styling property the focused row has and no non-focused row shares") passes via the `bg` slot alone, with the `:bold` style as additional contrast.
- **D-10:** Selection treatment is independent of state-cluster treatment. A focused unread row renders both the focus marker `▌` and the unread glyph `◆` (cluster appears after the focus marker). The `:bold` style stacks: unread emphasis (`:bold` on the title) plus selected emphasis (`:bold` on the row). SPEC requirement 4 explicitly allows the focused row treatment to keep, replace, or augment the `> ` marker — D-08 chooses replacement plus augmentation.

### Test Placement and Fixture Strategy

- **D-11:** Three test files are touched. NEW: `test/foglet_bbs/tui/widgets/list/rich_row_test.exs` for `RichRow`'s widget-level unit tests. EXTEND: `test/foglet_bbs/tui/screens/thread_list_test.exs` to assert glyph presence per state and absence of `"[S] "`. EXTEND: `test/foglet_bbs/tui/layout_smoke_test.exs` with a new ThreadList positioned-render block at the `[{64,22}, {80,24}, {132,50}]` triple Phase 18 standardized.
- **D-12:** `rich_row_test.exs` minimum coverage:
  - Selected × unselected × (with/without state glyphs) × (with/without metadata) — the eight-cell matrix from SPEC requirement 1 acceptance.
  - Non-`ThreadList` state input acceptance: instantiate with `[:subscribed, :required]` (or equivalent atoms reserved for Phase 21) and assert the cluster renders the expected glyph count without referencing `Foglet.Threads`. SPEC requirement 6 acceptance.
  - 64-cell long-title truncation: assert cluster fully present, full metadata string present, title contains `…`, total row display-width ≤ 64 cells.
  - Theme-routing audit: a grep-style assertion or test helper that catches hardcoded color atoms in the `RichRow` module or its render path. SPEC requirement 1 acceptance ("no call to `RichRow` references a hardcoded color outside `Foglet.TUI.Theme`").
- **D-13:** `thread_list_test.exs` additions extend the existing `"render/1 — thread row metadata (LIST-03)"` describe block (currently around line 221). Add assertions: (a) unread thread row contains `◆` in the leading cluster, (b) sticky thread row contains `●`, (c) locked thread row contains the chosen locked glyph, (d) read+non-sticky+unlocked row's leading cluster pads to the cluster width, (e) no row contains `"[S] "`, (f) metadata still reads `@handle · N posts · age` for one-post and many-post cases. Do NOT create a new screen-level test file.
- **D-14:** `layout_smoke_test.exs` adds a `describe "thread_list — size contract"` block at the standard 3-size triple Phase 18/19 use. Assertions per size: (a) cluster fully rendered, (b) metadata fully rendered, (c) title truncates with `…` only when row width forces it, (d) no two text elements share `{x, y}` coordinates such that they overlap. This mirrors the Phase 19 D-13/D-16 layout-smoke pattern at `test/foglet_bbs/tui/layout_smoke_test.exs`.
- **D-15:** Glyph and selection visual coverage stays code-only — no screenshot or terminal-recording fixture. Phase 18 and Phase 19 layout-smoke precedent uses positioned-render assertions; Phase 20 follows.

### Claude's Discretion

- Exact locked glyph choice within single-cell Unicode (`⚿`, `⚑`, or another sub-2-cell glyph). The recommendation is `⚿` because `⚑` collides with the Phase 19 Moderation glyph in MainMenu (`19-CONTEXT.md` D-08 line 41); reusing it on locked thread rows risks semantic confusion across screens.
- Whether sticky routes to `theme.info.fg` or `theme.badge.fg` — both are existing slots. Pick whichever has stronger contrast across all nine themes after a quick visual pass.
- Whether read state renders `◇` explicitly or pads to whitespace. SPEC line 28 explicitly allows either; whitespace simplifies the rendering path and avoids one more theme-slot decision.
- The exact `@cluster_width` value and the spacing strategy between cluster glyphs (single-space vs. zero-width). The constraint is that cluster width is fixed and column alignment holds across all state combinations.
- Whether `RichRow.render/1` returns a single Raxol element or a list of cells. Consistent with `ListRow.render_with_metadata/6` is fine; planner picks based on what `ScreenFrame.render/4` and the calling screen most naturally compose.
- Test fixture seed strategy for `rich_row_test.exs` (inline maps vs. helper fixtures). Sibling widget tests (`list_row_test.exs`, `selection_list_test.exs`, `smart_list_test.exs`) use inline maps; follow that.

### Folded Todos

None — `gsd-sdk query todo.match-phase 20` returned `todo_count: 0`.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Locked Phase Scope
- `.planning/phases/20-rich-rows-and-thread-flow/20-SPEC.md` — Locked Phase 20 requirements (1-6), boundaries, constraints, acceptance criteria, ambiguity report (0.13), and interview decisions.
- `.planning/ROADMAP.md` §Phase 20 — Milestone position, dependency on Phase 18, requirements `RICHROW-01`/`THREADS-01`/`THREADS-02`, success criteria.
- `.planning/REQUIREMENTS.md` — Requirement IDs `RICHROW-01`, `THREADS-01`, `THREADS-02`.
- `SCREENS.md` §Thread List (lines ~349-383) — Visual target sketch, glyph language for unread/sticky/locked, selection rendering, metadata format.
- `SCREENS.md` §RichRow primitive (lines ~638-640) — Reusable row contract guidance for Phase 20 / 21 / 25.
- `SCREENS.md` §Design Principles and §Chosen Direction — Classic Modern BBS rhythm and "everyday UI should be native UTF-8" guidance constraining Phase 20 to a single Unicode glyph set.

### Dependency Contracts
- `.planning/phases/16-unicode-width-foundation/16-CONTEXT.md` — `Foglet.TUI.TextWidth` width-helper contract used for cluster fixed-width math, metadata right-alignment, title truncation, and size-contract assertions.
- `.planning/phases/17-theme-and-mode-metadata/17-CONTEXT.md` — Theme-slot vocabulary (`accent`, `info`, `badge`, `warning`, `dim`, `selected`, `unselected`, etc.); ThreadList screen mode metadata (`:bbs`).
- `.planning/phases/18-chrome-v2/18-CONTEXT.md` — `Chrome.ScreenFrame` composition boundary (`ThreadList.render/1` keeps using it); `[{64,22},{80,24},{132,50}]` size-contract triple.
- `.planning/phases/19-main-menu-dashboard/19-CONTEXT.md` D-08, D-13, D-15-D-17 — Glyph / theme-slot precedent and the "extend existing test files; do not create new size-contract files" rule.

### Existing Code Touch Points
- `lib/foglet_bbs/tui/widgets/list/rich_row.ex` — **NEW** module to create.
- `lib/foglet_bbs/tui/widgets/list/list_row.ex` — Reference implementation; keeps `render/3` and `render_with_metadata/6` contracts intact for current callers (`NewThread`, `BoardList`, `Sysop` boards/users, `Account` SSH keys, shared invites).
- `lib/foglet_bbs/tui/widgets/list/selection_list.ex` — Sibling widget; canonical `▌` selection-marker precedent (lines 19-20 moduledoc, line 100 implementation).
- `lib/foglet_bbs/tui/widgets/list/smart_list.ex` — Sibling widget; `@focused_marker` precedent (line 41) and keyword-driven render pattern (lines 81-106).
- `lib/foglet_bbs/tui/screens/thread_list.ex` — Screen to migrate from `ListRow.render_with_metadata/6` to `RichRow`. Keep `handle_key/2`, `load_threads`, navigation flow untouched. Remove the `[S] ` prefix.
- `lib/foglet_bbs/tui/theme.ex` — Theme-slot vocabulary, lines 106-241 (per-theme `accent`, `info`, `badge`, `warning`, `dim`, `selected`, `unselected` definitions).
- `lib/foglet_bbs/tui/text_width.ex` — `display_width/1`, padding, slicing, truncation helpers; mandatory for cluster width math, metadata right-alignment, and title truncation.
- `lib/foglet_bbs/threads/thread_entry.ex` — `:has_unread`, `:sticky`, `:locked` field shapes consumed by `ThreadList`. **No changes** to this module in Phase 20.
- `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex` — `ScreenFrame.render/4` stays passive; `ThreadList.render/1` continues calling it.
- `lib/foglet_bbs/tui/widgets/input/tabs.ex` (line 43) and `lib/foglet_bbs/tui/widgets/modal.ex` (line 82) — Additional `▌` marker precedent across the widget stack.

### Test Anchors
- `test/foglet_bbs/tui/widgets/list/rich_row_test.exs` — **NEW** widget-level test file.
- `test/foglet_bbs/tui/widgets/list/list_row_test.exs` — Sibling test pattern reference.
- `test/foglet_bbs/tui/widgets/list/selection_list_test.exs` — Sibling test pattern reference.
- `test/foglet_bbs/tui/widgets/list/smart_list_test.exs` — Sibling test pattern reference (state input shapes, marker assertions).
- `test/foglet_bbs/tui/screens/thread_list_test.exs` — Existing screen tests to extend in the `LIST-03` describe block (~line 221) with glyph-presence and `[S]`-absence assertions.
- `test/foglet_bbs/tui/layout_smoke_test.exs` — Existing positioned-render harness using `Raxol.UI.Layout.Engine.apply_layout/2`; Phase 20 adds a new `thread_list — size contract` describe block at `[{64,22},{80,24},{132,50}]`.
- `test/foglet_bbs/tui/text_width_test.exs` — Width fixtures (combining marks, CJK) reusable for long-title truncation coverage if needed.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Foglet.TUI.Widgets.List.ListRow.render_with_metadata/6` — Current implementation for ThreadList rows; behaviorally close to RichRow's metadata + selection responsibilities. Phase 20 keeps it intact for non-ThreadList callers and uses it as a reference for cluster-aware extension.
- `Foglet.TUI.Widgets.List.SelectionList` and `SmartList` — Established keyword-driven render pattern, `▌` selection marker, and inline state-fixture test shape Phase 20 mirrors.
- `Foglet.TUI.TextWidth.display_width/1`, `slice_to_width/2`, `pad_to_width/2` — Width helpers Phase 20 uses for cluster fixed-width math and right-aligned metadata.
- `Foglet.TUI.Theme` slots `accent`, `info`, `badge`, `warning`, `dim`, `selected`, `unselected` — Already shipped across all nine themes in `theme.ex:106-241`. Phase 20 introduces no new slots.
- `Raxol.UI.Layout.Engine.apply_layout/2` (via `test/foglet_bbs/tui/layout_smoke_test.exs`) — Positioned-render harness Phase 18/19 already use; Phase 20 extends it.
- `Foglet.TUI.Screens.ThreadList.thread_metadata/1` — Existing `"@#{handle} · #{count} #{post_word} · #{time_segment}"` formatter; Phase 20 keeps this output unchanged and routes it into `RichRow` as the `:metadata` input.
- `Foglet.Threads.ThreadEntry` `:has_unread`, `:sticky`, `:locked` fields — Already populated by the existing thread-list query path. Phase 20 reads them; no schema/query changes.

### Established Patterns
- TUI render functions stay pure over already-loaded state. Phase 20 introduces no new context calls or commands.
- Widget styling routes through `Foglet.TUI.Theme` slots; no hardcoded color atoms anywhere in `lib/`.
- Width-sensitive layout uses `TextWidth` rather than `String.length/1` or grapheme counts.
- Tests mirror `lib/` paths under `test/foglet_bbs/tui/`.
- Sibling list widgets each have their own dedicated test file at `test/foglet_bbs/tui/widgets/list/<widget>_test.exs`.
- Size contracts live inside the shared `layout_smoke_test.exs` file at the `[{64,22},{80,24},{132,50}]` triple — Phase 18 set this and Phase 19 reinforced it (D-13, D-16, D-17 in `19-CONTEXT.md`).
- `▌` is the canonical selection marker across `SelectionList`, `SmartList`, `Tabs`, and `Modal`.

### Integration Points
- `Foglet.TUI.Screens.ThreadList.render/1` keeps calling `Chrome.ScreenFrame.render(state, breadcrumb, content, keys)`. Only the row construction inside `content` changes: `ListRow.render_with_metadata/6` is replaced by `RichRow.render/1` for each row.
- `ThreadList.handle_key/2` is unchanged. Open/Compose/Back keys, Up/Down selection, and `load_threads` orchestration stay as today (SPEC out-of-scope).
- `App` routing and Phase 17 `:bbs` mode metadata for ThreadList are unchanged.
- Phase 21 (`BoardList`) and Phase 25 (operator surfaces) will adopt `RichRow` in their own roadmap phases. Their adoption is not Phase 20 work, but Phase 20's API surface (D-01, D-02) is what they consume.

</code_context>

<specifics>
## Specific Ideas

- "I think `●` should be sticky, `◆` is unread, and `◇` is read" — locked into D-05. Theme-slot routing in D-06 still puts unread on `accent` (the warm/highlight slot) and sticky on `info`/`badge` (the structural-affordance slot); the swap is glyph-only, not slot-only.
- Locked glyph stays planner discretion within single-cell Unicode (D-05 recommends `⚿`; `⚑` is reserved by Phase 19 MainMenu Moderation per `19-CONTEXT.md` D-08, so reusing it would create cross-screen semantic confusion).
- `▌` selection marker matches Foglet's canonical convention across `SelectionList`, `SmartList`, `Tabs`, and `Modal` — D-08.
- Three test files: NEW `rich_row_test.exs` (widget unit tests), EXTEND `thread_list_test.exs` (glyph presence, `[S]` absence), EXTEND `layout_smoke_test.exs` (size contract) — D-11, follows Phase 19 precedent.

</specifics>

<deferred>
## Deferred Ideas

- Migration of `BoardList`, `Sysop` boards/users, `Account` SSH keys, and the shared invites surface to `RichRow` — Phase 21 and Phase 25 territory per ROADMAP.md.
- Focused-thread details strip below the list — explicitly out of scope per SPEC line 65; THREADS-02 is satisfied by selection clarity (Requirement 4) only.
- Wide-terminal inspector pane for thread details — SCREENS.md treats inspectors as later progressive enhancement; not Phase 20.
- ASCII-only fallback glyph set — SCREENS.md guidance is "everyday UI should be native UTF-8"; Phase 20 ships a single Unicode glyph set across all themes.
- Row striping (alternating background) — SCREENS.md flags as optional; Phase 20 leaves it out to avoid visual noise and theme-coupling complexity.
- Removing or rewriting `ListRow.render/3` or `ListRow.render_with_metadata/6` — they keep their current contracts and current callers. A future cleanup phase may consolidate after all callers migrate.
- Changes to `ThreadList` keyboard handling, navigation flow, or load orchestration — out of scope.
- Schema, query, or context API changes — out of scope.
- Theme palette retuning to improve glyph contrast on real SSH terminals — `UI-03` v2 territory; Phase 20 uses the slots Phase 17 already shipped.

### Reviewed Todos (not folded)
None — `todo_count: 0` for this phase.

</deferred>

---

*Phase: 20-rich-rows-and-thread-flow*
*Context gathered: 2026-04-25*
