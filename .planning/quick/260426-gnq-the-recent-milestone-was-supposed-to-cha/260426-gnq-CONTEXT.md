# Quick Task 260426-gnq: Screen Border Chrome Placement - Context

**Gathered:** 2026-04-26
**Status:** Ready for planning

<domain>
## Task Boundary

Fix Chrome V2 screen-frame rendering so the breadcrumb/status text appears on the top border row and command keys appear on the bottom border row.

</domain>

<decisions>
## Implementation Decisions

### Border Placement
- Treat the user's inline border contract as canonical because no `SCREENS.md` file exists in the workspace.
- Top border target: `┌ Foglet ▸ Breadcrumb ─── @handle | time ┐`.
- Bottom border target: `└ Commands ───────────────────────────┘`.

### Scope
- Keep the public `ScreenFrame.render/4` API unchanged.
- Keep breadcrumb derivation centralized in `BreadcrumbBar`.
- Keep command normalization centralized in `CommandBar`/`Normalizer`.
- Do not change screen key handling, navigation, domain behavior, or SSH/browser surfaces.

</decisions>

<specifics>
## Specific Ideas

The old implementation used a Raxol bordered box with padding, placing `StatusBar` below the top border and `CommandBar` above the bottom border. The fix should make border rows explicit in `ScreenFrame` so text is part of those rows.

</specifics>

<canonical_refs>
## Canonical References

- `.planning/milestones/v1.3-phases/18-chrome-v2/18-SPEC.md`
- `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex`
- `lib/foglet_bbs/tui/widgets/chrome/breadcrumb_bar.ex`
- `lib/foglet_bbs/tui/widgets/chrome/command_bar.ex`

</canonical_refs>
