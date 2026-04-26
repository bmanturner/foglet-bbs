# Phase 26: layout-width-foundations - Context

**Gathered:** 2026-04-26 (assumptions mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 26 establishes Foglet's TUI layout and width foundation for the v1.4 stabilization milestone. It fixes tab-row width artifacts, constrains Moderation and Boards primary content at the 64x22 minimum terminal, makes Sysop Invites and Moderation LOG tables responsive enough for compact terminals, adds `Foglet.TUI.TextWidth.wrap/2`, and preserves post markdown paragraph breaks. Adjacent interaction/form/auth/composer behavior remains in later v1.4 phases.
</domain>

<decisions>
## Implementation Decisions

### Shared Width Primitives
- **D-01:** Fix width behavior in shared primitives first: `Foglet.TUI.TextWidth`, `Foglet.TUI.Widgets.Input.Tabs`, `Foglet.TUI.Widgets.Display.Table`/`ConsoleTable`, `Foglet.TUI.Widgets.List.BoardTree`, and `Foglet.TUI.Widgets.Post.MarkdownBody`.
- **D-02:** Keep screen changes thin. Screens should pass available dimensions or user context into shared widgets/helpers instead of growing one-off screen-local renderers.

### Viewport Fit
- **D-03:** At 64x22, primary content wins. Moderation LOG/USERS/BOARDS tables and the Boards category+board list must stay in-frame and usable even if secondary summaries, detail strips, helper text, or inspector-style output must be collapsed, elided, paginated, or omitted.
- **D-04:** Prefer internal widget/page/window behavior for overlarge Moderation tables and Boards tree rows. Selection and navigation state should remain owned by the existing table/tree widget state where possible.

### Responsive Tables
- **D-05:** Move table compactness toward responsive column behavior and cell-boundary ellipsis in `Display.Table`/`ConsoleTable` rather than pre-truncating fixed character counts inside screen state builders.
- **D-06:** Sysop INVITES and Moderation LOG should preserve visibly separated columns at compact widths. Planning may choose exact ratios, but the behavior contract is locked: separated columns, available-width use, and no overlapping/concatenated values.

### Timestamp Formatting
- **D-07:** Moderation LOG timestamps should use the current user's preferred timezone, following the existing chrome clock fallback shape: validate the IANA timezone, use it when valid, and deterministically fall back to `Etc/UTC`.
- **D-08:** Timezone formatting is a TUI presentation concern for this phase. Do not push timezone-specific LOG display formatting into moderation persistence.

### Markdown Paragraph Rendering
- **D-09:** Preserve paragraph breaks in `MarkdownBody` display grouping: two consecutive newlines render exactly one blank visible line, longer blank runs clamp to one blank visible line, and soft line breaks stay visible as line breaks.
- **D-10:** Do not move paragraph display behavior into `Foglet.Markdown` or `PostReader`. `PostReader` should continue delegating shared post body rendering to `MarkdownBody`.

### Text Wrapping
- **D-11:** Implement `Foglet.TUI.TextWidth.wrap/2` as a visual helper alongside existing display width primitives. It must wrap by terminal display width, preserve grapheme clusters, prefer word boundaries, and split no-space blobs only when necessary.

### the agent's Discretion
- Exact column ratios, page sizes, viewport heights, and compact-summary cutoffs are left to planning/implementation as long as the SPEC acceptance criteria pass.
- Whether a given overlarge area uses scrolling, pagination, or windowed rendering is left to planning/implementation, constrained by existing widget patterns and SSH verification outcomes.

### Folded Todos
None.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase Definition
- `.planning/phases/26-layout-width-foundations/26-SPEC.md` - Locked requirements, boundaries, constraints, acceptance criteria, and interview decisions for Phase 26.
- `.planning/ROADMAP.md` - v1.4 phase sequencing, Phase 26 success criteria, and dependencies.
- `.planning/PROJECT.md` - SSH/TUI-first product boundary, v1.4 milestone scope, and terminal-size constraints.

### TUI Widget Contracts
- `docs/raxol/getting-started/WIDGET_GALLERY.md` - Raxol layout, table, tree, and viewport primitive reference.
- `lib/foglet_bbs/tui/widgets/README.md` - Foglet widget catalog, theme-routing requirements, and stateful/stateless widget contracts.
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `lib/foglet_bbs/tui/text_width.ex` - Existing display-width, split, slice, truncate, and padding helpers. Add `wrap/2` here and mirror coverage in `test/foglet_bbs/tui/text_width_test.exs`.
- `lib/foglet_bbs/tui/widgets/input/tabs.ex` - Shared tab renderer used by Account, Moderation, and Sysop. Fix tab-row width artifacts here instead of per screen.
- `lib/foglet_bbs/tui/widgets/display/table.ex` and `lib/foglet_bbs/tui/widgets/display/console_table.ex` - Shared table stack for operator-console tables. Best place to centralize responsive widths, ellipsis, and page/window behavior.
- `lib/foglet_bbs/tui/widgets/list/board_tree.ex` / `lib/foglet_bbs/tui/widgets/display/tree.ex` - Existing board tree and tree wrapper already own expansion/cursor state; extend or wrap their visible rows for 64x22 fit.
- `lib/foglet_bbs/tui/widgets/post/markdown_body.ex` - Shared markdown body renderer. Its `group_by_newline/1` currently rejects newline groups and is the targeted paragraph-break fix point.
- `lib/foglet_bbs/tui/widgets/chrome/clock_formatter.ex` - Existing timezone validation/fallback precedent for user-preferred display time.

### Established Patterns
- TUI render functions are pure over loaded state and receive `theme` explicitly.
- Screen modules should delegate display primitives to widgets and keep screen-local code focused on routing, dimensions, and state ownership.
- Operator-console tables use `ConsoleTable` as the facade over `Display.Table`; selection stays in table widget state where available.
- PostReader delegates markdown body rendering to shared post widgets and preserves render-helper purity.
- 64x22 is the hard minimum; 80x24 is the compact verification target; wider terminals may add detail panels or inspectors.

### Integration Points
- Account, Moderation, and Sysop screens call `Tabs.render/2`.
- Moderation LOG/USERS/BOARDS bodies in `lib/foglet_bbs/tui/screens/moderation.ex` currently render summary columns above `ConsoleTable.render/2`.
- Moderation LOG rows are built in `Foglet.TUI.Screens.Moderation.State.build_log_table/1`, where fixed pre-truncation and UTC-like calendar dates currently live.
- Sysop INVITES uses the shared `Foglet.TUI.Screens.Shared.InvitesState.build_table/2` and `InvitesSurface.render/2`.
- Boards screen renders `BoardTree.render/2`, a spacer line, a compact details strip, and a wide inspector from `lib/foglet_bbs/tui/screens/board_list.ex`.
- Post reader consumes `MarkdownBody.render_tuples_as_lines/4` through the existing viewport/render-cache path.
</code_context>

<specifics>
## Specific Ideas

No external product references were provided. The confirmed direction is to stay conservative and codebase-native: repair the shared TUI foundation so later v1.4 phases can rely on stable terminal-fit behavior.
</specifics>

<deferred>
## Deferred Ideas

None - analysis stayed within phase scope.

### Reviewed Todos (not folded)
None.
</deferred>

---

*Phase: 26-layout-width-foundations*
*Context gathered: 2026-04-26*
