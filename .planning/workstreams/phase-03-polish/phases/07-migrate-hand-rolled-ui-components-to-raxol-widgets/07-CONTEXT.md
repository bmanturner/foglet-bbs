# Phase 7: Migrate hand-rolled UI components to Raxol widgets — Context

**Gathered:** 2026-04-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Replace custom widget implementations with Raxol primitives where a built-in equivalent exists and overlap is high. All migrations are gated on theming support — if the Raxol primitive can accept `Foglet.TUI.Theme` colors, migrate fully; if not, use a thin adapter that delegates positioning/layout to Raxol while keeping our color rendering.

This phase is strictly mechanical: replace redundant implementations without changing visible behavior (except StatusBar losing reverse-video, which is an accepted regression).

</domain>

<decisions>
## Implementation Decisions

### Migration scope

- **D-01:** **In scope** — five surfaces to migrate: Modal, SelectionList (base), SelectionList (full / scrollable), PostReader scroll windowing, StatusBar.
- **D-02:** **Kept hand-rolled** — MarkdownBody (custom accent-color mapping worth preserving over MarkdownRenderer), Verify code buffer ([ABC___] 6-char mask display is a deliberate UX choice; text_input can't reproduce it without a custom renderer).
- **D-03:** **Not changed** — KeyBar (no Raxol equivalent), ScreenFrame (composite layout, genuinely custom), PostCard (domain-specific with caching), Compose translate_key plumbing (glue code, not a widget).

### Theming gate — applies to every migration in this phase

- **D-04:** Before planning any migration, researcher reads `docs/raxol/cookbook/THEMING.md` to determine whether each Raxol target component accepts `Foglet.TUI.Theme`-derived colors (e.g., hex `fg:`, `bg:`, `style:` props).
  - **Full replacement:** If Raxol component supports theme injection → delete our module, update callers to use Raxol directly with theme colors passed through.
  - **Thin adapter:** If Raxol component does NOT support theme injection → keep our `Foglet.TUI.Widgets.*` module as a thin facade; delegate overlay/positioning/layout to Raxol, but retain our color rendering logic (which reads `theme.*` slots).
- **D-05:** The theming gate applies to all five in-scope targets: Modal (`modal/1` + Modal), SelectionList base (`list/1`), SelectionList full (`Input.SelectList`), PostReader windowing (`Display.Viewport`), StatusBar (`Display.StatusBar`).

### Modal → modal/1 + Modal component

- **D-06:** Current types `:info`, `:error`, `:warning`, `:confirm` must map to Raxol's Modal API. Researcher verifies the `type:`, `title:`, `content:`, `buttons:` API shape.
- **D-07:** If full replacement: `app.ex`'s `render_modal_overlay/2` and all `{:show_modal, spec}` dispatch sites are updated to use Raxol's modal API. `lib/foglet_bbs/tui/widgets/modal.ex` is deleted.
- **D-08:** If thin adapter: `Widgets.Modal.render/2` accepts `(modal_spec, theme)` and calls through to Raxol for overlay framing; `app.ex` passes `state.session_context.theme` as second arg.

### SelectionList → list/1 and/or Input.SelectList

- **D-09:** Evaluate each use site in a single pass. Board list and thread list are the two consumers; researcher checks which tier fits each.
  - `list/1` for straightforward item selection with built-in highlight.
  - `Input.SelectList` where scroll + keyboard nav are needed.
- **D-10:** `List.ListRow`'s metadata variant (title + right-aligned `@handle · N posts · Xh ago` with truncation) is genuinely custom and is NOT replaced. Only the base selection-highlight rendering is redundant.
- **D-11:** If full replacement: `Widgets.List.SelectionList` and the base rendering concern in `Widgets.List.ListRow` are deleted; callers updated in the same plan.

### PostReader scroll windowing → Display.Viewport

- **D-12:** Current manual scroll: `scroll_offset` + `max_lines` slice in `MarkdownBody` and manual offset tracking in `post_reader.ex`. `Display.Viewport` replaces this with `scroll_by`, `scroll_to`, and visible-height config.
- **D-13:** If full replacement: `post_reader.ex`'s manual offset tracking is removed; `render_cache` keyed on `{post.id, width}` is preserved (unrelated to scroll). `screen_state[:post_reader][:scroll_offset]` field is removed.

### StatusBar → Display.StatusBar

- **D-14:** Current implementation: reverse-video bar (`theme.status_bar.bg` + `theme.status_bar.fg`), left side `"Foglet BBS — {title}"`, right side `"@{handle}"` or `"guest"`.
- **D-15:** **Accepted regression:** If migrated, the reverse-video styling is dropped. Raxol's `Display.StatusBar` layout handles item placement; theming support determines whether our hex colors survive.
- **D-16:** If Raxol's `Display.StatusBar` does NOT support theme injection, keep `Widgets.Chrome.StatusBar` hand-rolled (reverse-video IS the BBS aesthetic — losing both layout AND colors is not acceptable).

### Caller updates

- **D-17:** Every module deletion is paired with caller updates in the same plan. No orphan `alias` statements, no dangling references, no transition aliases. All callers land in a clean state in the same commit wave.

### Claude's Discretion

- **Thin adapter API shape:** If any target requires a thin adapter, planner decides the exact function signature (e.g., whether to pass `%Theme{}` or the full `state`, consistent with how `SizeGate.render/1` and `ScreenFrame.render/4` accept state vs. explicit params).
- **Plan breakdown:** Planner decides whether each migration target gets its own plan or whether related targets (e.g., SelectionList base + full) are bundled into one.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Theming — CRITICAL FIRST READ
- `docs/raxol/cookbook/THEMING.md` — Determines full replacement vs thin adapter for every migration target. Read before researching any individual component.

### Workstream Requirements and Roadmap
- `.planning/workstreams/phase-03-polish/REQUIREMENTS.md` — Locked decisions table (function-form only, ThemeManager rejected)
- `.planning/workstreams/phase-03-polish/ROADMAP.md` — Phase 7 depends on Phase 6; success criteria TBD (defined during planning from this CONTEXT)

### Raxol DSL Constraint
- `memory/feedback_raxol_modern_dsl.md` — CRITICAL: function-form only. Block-macro DSL (`column/row/box do...end`). No `use Raxol.UI.Components.Base.Component`, no legacy function-form.

### Prior Phase Context
- `.planning/workstreams/phase-03-polish/phases/01-widget-foundation-theme-screen-chrome/01-CONTEXT.md` — Theme slot definitions (D-01..D-12), widget namespace decisions, function-form API patterns (ScreenFrame.render/4, SelectionList.render/3, etc.)

### Current implementations to migrate or verify
- `lib/foglet_bbs/tui/widgets/modal.ex` — Custom modal (to be migrated)
- `lib/foglet_bbs/tui/widgets/list/selection_list.ex` — Custom SelectionList (to be migrated)
- `lib/foglet_bbs/tui/widgets/list/list_row.ex` — ListRow base (migrate) + metadata variant (keep)
- `lib/foglet_bbs/tui/widgets/chrome/status_bar.ex` — Custom StatusBar (to be migrated, with conditions per D-16)
- `lib/foglet_bbs/tui/widgets/post/markdown_body.ex` — Keep hand-rolled (do NOT migrate)
- `lib/foglet_bbs/tui/screens/post_reader.ex` — Scroll windowing to be replaced by Display.Viewport
- `lib/foglet_bbs/tui/screens/verify.ex` — Keep hand-rolled (do NOT migrate)
- `lib/foglet_bbs/tui/app.ex` — modal overlay dispatch and caller of Widgets.Modal (needs updating)

</canonical_refs>

<code_context>
## Existing Code Insights

### Components kept hand-rolled (do not touch)
- `Foglet.TUI.Widgets.Post.MarkdownBody` — custom parse + theme-accent render pipeline; scroll windowing is inline but MarkdownRenderer loses accent colors. Hand-rolled wins.
- `Foglet.TUI.Widgets.Compose` — already theme-aware, stays in flat namespace; no migration needed.
- `Foglet.TUI.Widgets.Chrome.KeyBar` — no Raxol equivalent.
- `Foglet.TUI.Widgets.Chrome.ScreenFrame` — composite layout wrapper; no equivalent.
- `Foglet.TUI.Widgets.Post.PostCard` — domain-specific with `render_cache` keyed on `{post.id, width}`; not a general widget pattern.
- `lib/foglet_bbs/tui/screens/verify.ex` — 6-char code buffer with [ABC___] mask display; hand-rolled intentionally.

### Migration targets and their callers
- `Widgets.Modal` → callers: `lib/foglet_bbs/tui/app.ex` (`render_modal_overlay/2`, `{:show_modal, spec}` dispatch)
- `Widgets.List.SelectionList` → callers: `board_list.ex`, `thread_list.ex`, `new_thread.ex`
- `Widgets.Chrome.StatusBar` → callers: `Widgets.Chrome.ScreenFrame` (via `Chrome.StatusBar`)
- PostReader scroll windowing → inline in `post_reader.ex` (`screen_state[:post_reader][:scroll_offset]`) and `markdown_body.ex`

### Established patterns
- Function signature convention: `SizeGate.render/1` accepts full `state` and extracts theme internally; `ScreenFrame.render/4` accepts explicit args. Thin adapters should follow whichever pattern is already used by the module's callers.
- `Foglet.TUI.Theme` slots: `border`, `primary`, `dim`, `accent`, `title`, `error`, `warning`, `selected`, `unselected`, `status_bar`. All color references route through these.
- `render_cache` in PostReader is unrelated to scroll and must be preserved through the Viewport migration.

</code_context>

<specifics>
## Specific Ideas

- **Theming gate is a research output, not a planning assumption.** The researcher reads `docs/raxol/cookbook/THEMING.md` and returns a per-component verdict (full replacement / thin adapter) before the planner commits to any approach. Do not plan a "full replacement" without this verification.
- **StatusBar reverse-video is an accepted regression** — user consciously chose to drop it if migrating to `Display.StatusBar`. But D-16 says: if `Display.StatusBar` can't accept our hex colors either, keep hand-rolled (dropping both the reverse-video AND the theme colors is not acceptable).
- **ListRow metadata is genuinely custom** — `@handle · N posts · Xh ago` with right-alignment and truncation. This stays regardless of what SelectionList base does.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 07-migrate-hand-rolled-ui-components-to-raxol-widgets*
*Context gathered: 2026-04-20*
