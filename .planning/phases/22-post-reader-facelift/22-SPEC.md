# Phase 22: Post Reader Facelift - Specification

**Created:** 2026-04-25
**Ambiguity score:** 0.13 (gate: <= 0.20)
**Requirements:** 6 locked

## Goal

`PostReader` changes from split plain metadata lines plus loose viewport body rows into a Classic Modern BBS reader where every displayed post has a compact metadata header, stable message number, readable gutter/card body treatment, and 64x22-safe thread progress while preserving existing navigation, viewport, cache, reply, back, and read-pointer behavior.

## Background

Phase 22 is part of the v1.3 SSH-first TUI facelift. `SCREENS.md` defines the target `PostReader` shape: a compact row with `Post 3 of 12`, stable message number, author, and age; a left-gutter body treatment; and a progress indicator such as `Posts 3/12`.

Current `Foglet.TUI.Screens.PostReader` already loads thread posts, keeps `%PostReader.State{}` in `state.screen_state[:post_reader]`, owns scroll through `Raxol.UI.Components.Display.Viewport`, warms markdown render tuples in a `{post.id, width}` cache, advances local read position on post navigation, flushes read pointers on exit, and routes reply/back transitions. It renders `Post X of N`, `PostCard.author_line/1`, a divider, and `PostCard.render_body_lines/4` body rows, but the visible reader still feels like loose text rather than a message-oriented BBS post unit. `Foglet.TUI.Widgets.Post.PostCard` and `Post.MarkdownBody` already exist and preserve markdown rendering behavior, but `PostReader` currently assembles its own non-scrolling header and does not show stable message number or reader progress.

## Requirements

1. **Compact metadata header**: Each displayed post renders one compact metadata header containing post position, stable per-board message number, author handle, and age.
   - Current: `PostReader` renders `Post X of N` and a separate `By @handle - age` style author line; stable `message_number` is not prominent in the reader header.
   - Target: The currently selected post exposes `Post X of N`, `#message_number`, `@handle`, and short age in a compact header row or equivalent compact header block.
   - Acceptance: A focused render test with a post containing `message_number: 42`, `user.handle: "mina"`, and timestamp text finds `Post 1 of 1`, `#42`, `@mina`, and an age token in the rendered tree.

2. **64x22 body gutter**: At the 64x22 minimum terminal size, post bodies render with a clear left gutter treatment while preserving maximum practical body width.
   - Current: Body rows from `PostCard.render_body_lines/4` are passed directly into the viewport without a visible gutter/card separator.
   - Target: The minimum-size reader displays markdown body content with a left gutter marker such as `|` or `│` that distinguishes message body from chrome/header without requiring a full box frame.
   - Acceptance: A 64x22 render test finds the body text and at least one gutter marker on body rows, with all positioned text remaining inside the viewport bounds.

3. **Post unit reuse**: Header, body, and optional footer treatment are produced through the shared post display unit boundary rather than a new pile of screen-local loose text formatting.
   - Current: `PostCard` exists and owns post card/body helpers, but `PostReader` manually assembles header lines and divider around `PostCard.render_body_lines/4`.
   - Target: `PostReader` uses `Foglet.TUI.Widgets.Post.PostCard` directly or an equivalent shared post unit/helper under `Foglet.TUI.Widgets.Post` for the reader's post header/body/footer shape.
   - Acceptance: Source inspection or tests show the reader delegates post visual assembly to `Foglet.TUI.Widgets.Post.*`; no new screen-local markdown rendering pipeline is introduced in `PostReader`.

4. **Thread progress**: Longer threads always show a compact, 64x22-safe progress indicator for the selected post.
   - Current: Progress is implicit in `Post X of N`; there is no separate reader progress surface or richer long-thread affordance.
   - Target: The reader always shows compact text progress such as `Posts 3/12`; wider terminals may additionally show a segmented visual indicator, but the compact text remains the required baseline.
   - Acceptance: Render tests for a 12-post thread at 64x22 and 80x24 find `Posts 3/12` or equivalent selected/total text while preserving the selected body content.

5. **Behavior preservation**: The facelift does not change PostReader navigation, scroll ownership, reply/back transitions, render-cache semantics, or read-pointer flushing.
   - Current: Tests cover next/previous/space/page navigation, j/k viewport scroll, reply transition to `:post_composer`, Q back transition to `:thread_list`, `{post.id, width}` render-cache keys, and read-pointer flushing on leave.
   - Target: Those behaviors continue to pass after the visual facelift, with `Viewport` still owning within-post scroll state and `PostReader.State` remaining the screen-local state shape.
   - Acceptance: Existing `test/foglet_bbs/tui/screens/post_reader_test.exs` behavior tests continue to pass, and any new visual tests do not assert changes to key handling or context side effects.

6. **Size-contract coverage**: The facelift is verified at the milestone's canonical terminal sizes.
   - Current: Layout smoke coverage includes a `PostReader` render sanity path, but the Phase 22-specific header/gutter/progress contract is not locked at 64x22, 80x24, and a wide/tall size.
   - Target: Focused or smoke tests assert the new post reader treatment at 64x22 minimum, 80x24 compact target, and at least one wide/tall terminal size without overlapping text or out-of-bounds positioned elements.
   - Acceptance: Automated tests cover the new header, gutter, and compact progress at the canonical size triple and fail if text overflows the terminal bounds.

## Boundaries

**In scope:**
- `PostReader` visual contract for selected post header, stable message number, author, age, body gutter/card treatment, and compact progress.
- Reuse or adjustment of `Foglet.TUI.Widgets.Post.PostCard` or a sibling `Foglet.TUI.Widgets.Post` post unit so reader post assembly is shared.
- Preservation of existing markdown rendering behavior through `Post.MarkdownBody`.
- Preservation of `Viewport` ownership for within-post scrolling.
- Focused tests and layout-smoke coverage for 64x22, 80x24, and at least one wide/tall terminal size.

**Out of scope:**
- Composer facelift, preview mode, counters, or editor-frame treatment - Phase 23 owns new-thread and reply composition.
- Thread list rich rows or focused-thread details - Phase 20 owns thread browsing.
- Board directory rows, board details, or board subscription presentation - Phase 21 owns board browsing.
- New post query semantics, message-number allocation, or read-pointer domain behavior - this phase is a reader presentation facelift, not a persistence change.
- New browser workflows - Foglet remains SSH-first for this milestone.
- Full markdown styling redesign beyond preserving existing markdown rendering and making it readable inside the reader treatment - broad markdown styling can be handled separately if needed.

## Constraints

- The hard minimum terminal size is 64x22; 80x24 is the compact design target; wider terminals may progressively add richer visual indicators.
- Colors and styles must route through `Foglet.TUI.Theme`; no new hardcoded terminal color atoms in facelifted reader widgets.
- Unicode glyphs are allowed where existing v1.3 width handling supports them, but tests must verify width-safe layout at the canonical terminal sizes.
- `PostReader` must keep domain work in contexts and presentation work in TUI screen/widgets; no domain mutation may be introduced as a visual shortcut.
- `Viewport` remains the owner of within-post scroll state; render helpers remain pure over already-loaded state.

## Acceptance Criteria

- [ ] Rendered selected-post header includes post position, stable `#message_number`, author handle, and age.
- [ ] At 64x22, the selected post body renders with a visible left gutter treatment and remains within terminal bounds.
- [ ] `PostReader` delegates post visual assembly to `Foglet.TUI.Widgets.Post.PostCard` or an equivalent shared `Foglet.TUI.Widgets.Post` unit.
- [ ] Longer-thread render tests show compact progress text such as `Posts 3/12` at 64x22 and 80x24.
- [ ] Existing next/previous/space/page, j/k scroll, reply, Q back, cache, and read-pointer flush behavior remains covered and passing.
- [ ] Phase 22 visual contracts are covered at 64x22, 80x24, and at least one wide/tall terminal size.
- [ ] `rtk mix precommit` passes after implementation.

## Ambiguity Report

| Dimension          | Score | Min   | Status | Notes |
|--------------------|-------|-------|--------|-------|
| Goal Clarity       | 0.91  | 0.75  | met    | SCREENS.md target plus reader-specific goal locked. |
| Boundary Clarity   | 0.86  | 0.70  | met    | Composer changes and adjacent screen facelifts explicitly excluded. |
| Constraint Clarity | 0.82  | 0.65  | met    | 64x22, theme routing, viewport ownership, markdown preservation, and SSH-first constraints locked. |
| Acceptance Criteria| 0.84  | 0.70  | met    | Pass/fail checks cover header, gutter, progress, behavior preservation, and size contracts. |
| **Ambiguity**      | 0.13  | <=0.20| met    | Ready for discuss-phase. |

Status: met = dimension meets minimum; below minimum = planner treats as assumption.

## Interview Log

| Round | Perspective | Question summary | Decision locked |
|-------|-------------|------------------|-----------------|
| 1 | Researcher | What user-visible change matters most: header, body treatment, or progress? | Follow `SCREENS.md`; all three are important, with best judgement for the overhaul. |
| 1 | Researcher | What body shape is required at 64x22? | Require a left gutter at the minimum size; full framed card treatment is not mandatory at 64x22. |
| 1 | Researcher | What progress indicator is required for longer threads? | Always require compact text progress; richer bars are optional wider-terminal enhancement. |
| 2 | Boundary Keeper | Which existing behavior is non-negotiable? | Preserve all navigation/read state: next/previous, scroll, reply, back, viewport ownership, cache behavior, and read-pointer flushing. |
| 2 | Boundary Keeper | Which adjacent improvement is explicitly excluded? | Composer visual changes stay out of Phase 22 and remain Phase 23 scope. |

---

*Phase: 22-post-reader-facelift*
*Spec created: 2026-04-25*
*Next step: $gsd-discuss-phase 22 - implementation decisions (how to build what's specified above)*
