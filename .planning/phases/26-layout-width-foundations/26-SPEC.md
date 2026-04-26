# Phase 26: Layout & Width Foundations — Specification

**Created:** 2026-04-26
**Ambiguity score:** 0.13 (gate: ≤ 0.20)
**Requirements:** 7 locked

## Goal

Foglet's TUI rendering foundations fit the 64×22 minimum terminal without tab, table, screen-body, or post-markdown overflow artifacts while providing a reusable grapheme-aware wrapping helper for downstream screens.

## Background

Phase 26 opens the v1.4 stabilization milestone, driven by human SSH/TUI verification issues from the v1.3 facelift. The current codebase already has `Foglet.TUI.TextWidth.display_width/1`, `split_at/2`, `slice_to_width/2`, `truncate/2`, and padding helpers, but no reusable `wrap/2` helper. `Foglet.TUI.Widgets.Input.Tabs.render/2` renders a bordered tab strip without a width-aware cap, and affected tabbed screens delegate their rows directly into the screen body. `Foglet.TUI.Widgets.Display.ConsoleTable` wraps `Display.Table` with fixed/default column widths; Moderation LOG currently pre-truncates fields to fixed character counts and formats dates as UTC-like calendar dates rather than user-preferred timezone timestamps. `Foglet.TUI.Screens.BoardList` renders its board tree plus detail lines as a plain column, so large category/board sets are not constrained to an internal viewport at the 64×22 minimum. `Foglet.TUI.Widgets.Post.MarkdownBody` groups markdown by newline separators but drops empty groups, so paragraph breaks are collapsed instead of rendering one blank visible line.

## Requirements

1. **Tab row width clamp**: The shared Tabs widget must render without trailing border-glyph artifacts to the right of the rightmost tab on all tabbed screens at supported terminal widths.
   - Current: `Tabs.render/2` renders a bordered row with no explicit max-width contract, and v1.4 verification found trailing border-glyph artifacts globally.
   - Target: Account, Moderation, and Sysop tab rows fit the available frame width; the right edge terminates cleanly at the frame vertical border with no extra tab-border glyphs after the rightmost tab.
   - Acceptance: A 64×22 SSH check of Account, Moderation, and Sysop shows no trailing tab-row border artifact, and the rightmost tab-row column aligns with the screen frame's vertical border.

2. **Moderation viewport fit**: Moderation LOG, USERS, and BOARDS tabs must keep their primary table content usable within the 64×22 terminal.
   - Current: Moderation tab bodies render summary grids and tables as plain columns, and verification found LOG, USERS, and BOARDS content overflowing above the top edge at the minimum size.
   - Target: The active tab header and primary LOG/USERS/BOARDS table region remain visible and usable inside the frame at 64×22; oversized rows are handled by internal scrolling, pagination, elision, or collapsed non-primary content.
   - Acceptance: A 64×22 SSH check can enter Moderation LOG, USERS, and BOARDS and read/navigate the primary table area without rows drawing above the frame or below the command bar.

3. **Boards screen viewport fit**: The Boards screen must keep the category+board list usable within the 64×22 terminal.
   - Current: `BoardList.render/1` emits the board tree and auxiliary detail lines in a plain column; large directories can overflow the screen frame.
   - Target: The selectable category+board tree is constrained to the available body region at 64×22, with excess categories/boards reachable by scrolling or equivalent internal navigation. Existing secondary detail/helper output may be collapsed, elided, or omitted only as needed to preserve the primary list.
   - Acceptance: A 64×22 SSH check with enough categories/boards to exceed the visible body keeps selection/navigation inside the frame and shows no list rows above the top border or below the command bar.

4. **Sysop invites responsive columns**: The Sysop INVITES table must use visibly separated responsive columns for Code, Status, Created, and Used by.
   - Current: Shared invite rendering delegates to `ConsoleTable`; column sizing is fixed/default and can collapse fields together at compact widths.
   - Target: At supported widths, the INVITES table allocates proportional, separated columns using `Display.Table`/`ConsoleTable` auto-width semantics or an equivalent behavior contract; Code, Status, Created, and Used by remain visually distinct.
   - Acceptance: An 80×24 SSH check of Sysop INVITES with representative available, consumed, and revoked rows shows four separated columns with no overlapping or concatenated values.

5. **Moderation LOG responsive table**: The Moderation LOG table must consume available width, elide long text with `…`, and format timestamps in the current user's preferred timezone.
   - Current: `Moderation.State.build_log_table/1` pre-truncates fixed fields and formats `inserted_at` as `YYYY-MM-DD`, independent of user timezone.
   - Target: LOG rows use the available table width up to the terminal limit, long message/reason/body fields elide at cell boundaries with `…`, and timestamp display uses the current user's preferred timezone with a deterministic fallback when absent or invalid.
   - Acceptance: An 80×24 SSH check with a long moderation message shows the LOG table filling the available body width, an ellipsis on the long field rather than mid-word clipping, and a timestamp matching the user's configured timezone.

6. **Reusable width-aware wrap helper**: `Foglet.TUI.TextWidth.wrap/2` must provide grapheme-cluster-aware visual wrapping for downstream TUI consumers.
   - Current: `TextWidth` exposes display width, split, slice, truncate, and padding helpers but no wrap helper; wrapping logic exists ad hoc in places such as modal text.
   - Target: `TextWidth.wrap/2` wraps on word boundaries when possible, splits no-space blobs by display width when necessary, preserves grapheme clusters, and never returns a line whose terminal display width exceeds the requested width.
   - Acceptance: Unit tests cover ASCII word wrapping, `あ`, combining `é`, ZWJ emoji, and a no-space `ssh-rsa`-shaped blob, asserting every returned line is within the requested display width.

7. **Post markdown blank lines**: Shared post body rendering must preserve paragraph breaks without over-expanding blank runs.
   - Current: `MarkdownBody.group_by_newline/1` rejects newline groups, so `First\n\nSecond` renders as two adjacent lines with no blank visible separator.
   - Target: In post body display, two consecutive newlines render as exactly one blank visible line, three or more consecutive newlines clamp to one blank visible line, and soft line breaks render as line breaks.
   - Acceptance: A post reader SSH check of a body containing soft breaks, two-newline paragraph breaks, and three-or-more-newline runs shows soft breaks as line breaks and exactly one blank visible line between paragraphs.

## Boundaries

**In scope:**
- Fixing shared tab-row width rendering so existing tabbed screens do not produce right-edge artifacts.
- Constraining Moderation LOG, USERS, and BOARDS primary table content to the screen body at 64×22.
- Constraining Boards category+board list content to the screen body at 64×22.
- Responsive table behavior for Sysop INVITES and Moderation LOG.
- User-preferred timezone timestamp rendering for Moderation LOG.
- Adding `Foglet.TUI.TextWidth.wrap/2` with grapheme-aware tests.
- Preserving post body markdown paragraph breaks in the shared post rendering path used by the post reader.
- Automated unit/render tests where they directly prove primitive behavior, plus human SSH verification notes for terminal-fit behavior.

**Out of scope:**
- Boards category Enter toggling — Phase 33 owns `BOARD-01` interaction behavior.
- Composer visual soft-wrap — Phase 33 owns `POST-02`; this phase only provides the reusable helper.
- TextInput cursor movement — Phase 27 owns `CURSOR-01`.
- Breadcrumb changes — Phase 27 owns `BREAD-01`.
- Modal.Form focus, footer, submit-state, or Esc behavior — Phase 28 owns FORM requirements.
- Sysop tab auto-load, failure-state lifecycle, Site editability, Users action gating, and Invites row actions — Phase 29 owns SYSOP requirements.
- Exact final column ratios for responsive tables — this spec locks behavior and pass/fail outcomes; implementation planning chooses ratios.
- New browser workflows or web UI — v1.4 remains SSH/TUI-first.

## Constraints

- 64×22 remains the hard minimum terminal size; 80×24 remains the compact verification target.
- Primary screen content must not draw outside the screen frame. For the user-selected "Best Effort" fit rule, non-primary existing summary/detail/helper output may be collapsed, elided, paginated, or omitted if needed to keep the primary list/table usable.
- Table fixes must route through existing Foglet TUI widget patterns (`Display.Table`, `ConsoleTable`, `TextWidth`, and theme-routed rendering) rather than hardcoded screen-local string tables where practical.
- `TextWidth.wrap/2` is a visual wrapping helper; it must not own markdown paragraph parsing or mutate submitted composer/post content.
- Human SSH checks are the primary evidence for terminal-fit acceptance; automated tests should still cover deterministic helper and render contracts.

## Acceptance Criteria

- [ ] At 64×22 SSH, Account, Moderation, and Sysop tab rows render with no trailing border-glyph artifacts to the right of the rightmost tab.
- [ ] At 64×22 SSH, Moderation LOG, USERS, and BOARDS keep their primary table content inside the screen frame and usable.
- [ ] At 64×22 SSH, Boards keeps the category+board list inside the screen frame and usable with an overlarge directory.
- [ ] At 80×24 SSH, Sysop INVITES renders visibly separated Code, Status, Created, and Used by columns.
- [ ] At 80×24 SSH, Moderation LOG consumes available width, elides long message/body/reason text with `…`, and renders timestamps in the user's preferred timezone.
- [ ] `Foglet.TUI.TextWidth.wrap/2` exists and passes grapheme-aware tests for ASCII, `あ`, combining `é`, ZWJ emoji, and a no-space `ssh-rsa`-shaped blob.
- [ ] Post reader display renders two consecutive newlines as one blank visible line, clamps three-or-more consecutive newlines to one blank visible line, and renders soft breaks as line breaks.
- [ ] `mix precommit` passes after implementation.

## Ambiguity Report

| Dimension          | Score | Min   | Status | Notes |
|--------------------|-------|-------|--------|-------|
| Goal Clarity       | 0.92  | 0.75  | ✓      | Seven roadmap requirements are locked to concrete terminal/rendering outcomes. |
| Boundary Clarity   | 0.88  | 0.70  | ✓      | Interaction, composer, cursor, breadcrumb, form, and sysop lifecycle work explicitly excluded. |
| Constraint Clarity | 0.78  | 0.65  | ✓      | 64×22/80×24 targets, SSH evidence, primary-content rule, and wrap-helper limits are specified. |
| Acceptance Criteria| 0.82  | 0.70  | ✓      | Acceptance is pass/fail, with SSH checks for viewport behavior and tests for deterministic primitives. |
| **Ambiguity**      | 0.13  | ≤0.20 | ✓      | Gate passed. |

Status: ✓ = met minimum, ⚠ = below minimum (planner treats as assumption)

## Interview Log

| Round | Perspective | Question summary | Decision locked |
|-------|-------------|------------------|-----------------|
| 1 | Researcher | Should Phase 26 keep all seven mapped requirements together? | Keep LAYOUT-01..06 and POST-01 together as one foundation phase. |
| 1 | Researcher | What counts as viewport fit at 64×22? | Use a Best Effort fit rule: primary content must stay usable in-frame. |
| 1 | Researcher | What evidence should verify fit? | Human SSH verification is the primary evidence for terminal-fit behavior. |
| 2 | Simplifier | What responsive table detail should be locked now? | Lock behavior contract, not exact ratios: separated columns, available-width use, ellipsis, and timezone formatting. |
| 2 | Simplifier | What is the `TextWidth.wrap/2` minimum contract? | Word-boundary wrapping when possible, no-space blob splitting, grapheme preservation, and max-width enforcement. |
| 2 | Simplifier | May secondary detail/helper output change for 64×22 fit? | Do not create product commitments for secondary output; existing non-primary output may change only to preserve primary content. |
| 3 | Boundary Keeper | Which adjacent work is excluded? | Exclude board Enter toggling, composer wrapping, form focus, cursor, breadcrumb, and sysop tab lifecycle work. |
| 3 | Boundary Keeper | What timezone behavior is locked? | Moderation LOG timestamps use the current user's preferred timezone with deterministic fallback. |
| 3 | Boundary Keeper | How should POST-01 be scoped? | Lock shared post body/post reader paragraph display; exclude composer/editor wrapping. |

---

*Phase: 26-layout-width-foundations*
*Spec created: 2026-04-26*
*Next step: $gsd-discuss-phase 26 — implementation decisions (how to build what's specified above)*
