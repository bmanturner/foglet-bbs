# Phase 21: board-directory-facelift - Discussion Log (Assumptions Mode)

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in 21-CONTEXT.md — this log preserves the analysis.

**Date:** 2026-04-25
**Phase:** 21-board-directory-facelift
**Mode:** assumptions
**Areas analyzed:** BoardTree API, RichRow state-cluster shape, Details strip + time humanization, last_post_at query, Test placement + subscription feedback

## Methodology

The phase had a fully locked 21-SPEC.md (ambiguity 0.127, 6 requirements). Per assumptions-mode workflow, the analyzer was scoped to surface implementation assumptions ONLY — not to re-discuss WHAT to build. The user subsequently overrode SPEC requirement 4 (details strip removed) and SPEC requirement 2 (subscription column converted to glyph-only) during the discussion. CONTEXT.md carries the canonical row contract; SPEC.md remains as historical record.

## Assumptions Presented

### BoardTree API Surface

| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| BoardTree mirrors Display.Tree's stateful facade (init/handle_event/render); internally owns a Display.Tree struct for cursor/expand state and walks RaxolTree.visible_nodes/1 itself | Likely | `lib/foglet_bbs/tui/widgets/display/tree.ex:50-93`, `lib/foglet_bbs/tui/screens/board_list.ex:127,187,235` |

Alternatives considered: stateless BoardTree consuming pre-built Display.Tree snapshots; BoardTree owning its own MapSet-based collapse state.

### RichRow State-Cluster Shape

| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| RichRow `:state_cluster` carries read-state only (`[:unread]` / `[]`); subscription word renders as text outside the cluster (originally as title prefix or left-meta) | Unclear | Phase 20 D-02/D-03 in `.planning/phases/20-rich-rows-and-thread-flow/20-CONTEXT.md`; RichRow not yet shipped (verified `ls lib/foglet_bbs/tui/widgets/list/`) |

Alternatives considered: cluster-carries-both atoms `[:unread, :subscribed]`; new `:left_meta` slot in RichRow API (out of scope per SPEC.md:76).

### Details Strip and Time Humanization (initially)

| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Details strip renders inline inside `BoardList.render_board_content/3` as a themed text/1 row; uses `Foglet.TimeAgo.format/1` wrapped to append " ago" and handle nil → "no posts yet" | Likely | `lib/foglet_bbs/time_ago.ex:22-29`, `lib/foglet_bbs/tui/widgets/post/post_card.ex:163-198` |

Alternatives considered: strip as `BoardTree.details_strip/2`; extend `Foglet.TimeAgo` with `format_long/1`.

### last_post_at Query Strategy

| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Single-pass LEFT JOIN aggregation query keyed by board.id, called once per `board_directory_for/1` invocation; structurally identical to existing `unread_counts/1` precedent; computed actor-independently | Confident | `lib/foglet_bbs/boards.ex:511-526` (precedent), `lib/foglet_bbs/threads/thread.ex:9,11` (schema), `21-SPEC.md:91` (no N+1 constraint) |

Alternatives considered: folded multi-aggregate mega-query; virtual schema field on Board with preload (rejected — schema change out of scope).

### Test Placement and Subscription Feedback

| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Tests follow Phase 20 D-11 precedent (NEW board_tree_test.exs, EXTEND board_list_test.exs / layout_smoke_test.exs / boards_test.exs) | Confident | sibling test files verified at `test/foglet_bbs/tui/widgets/list/`, `test/foglet_bbs/boards/boards_test.exs:464` |
| Subscription feedback stays as top-of-tree flash via existing `maybe_feedback/2`; strings preserved verbatim | Likely | `lib/foglet_bbs/tui/screens/board_list.ex:144,158,165,252-256`, `21-SPEC.md:80` (mechanism may evolve OR stay) |

Alternatives considered (feedback only): move feedback into details strip; inline row-level icon flash (requires RichRow API change).

## Corrections Made

### Details Strip — Removed (User Direction)

- **Original assumption:** Details strip renders inline inside `BoardList.render_board_content/3` below the tree, showing focused board's `name • state • unread • last post age` or category's `name • N boards • M unread total`.
- **User correction:** "Get rid of the details strip and show the age on each board row."
- **Reason:** User preference for per-row affordance over a single focused-row strip; reduces visual hierarchy and surfaces age data continuously rather than only on focus.
- **Resolution:** SPEC requirement 4 removed by CONTEXT override. Per-row age column added (D-04, D-06). Width math re-verified at 64x22 with short age form (`12m`/`2h`/`3d`/`—`); long form rejected (would push name below 20-cell minimum).
- **Knock-on choices (clarified via follow-up question):**
  - Age format → short (`12m`/`2h`/`3d`/`—`) using existing `Foglet.TimeAgo.format/1` exactly; em-dash for nil.
  - Category info → dropped entirely (no summary text on category rows).
  - SPEC handling → override in CONTEXT.md (faster than amending SPEC inline).

### Subscription Column — Glyph-Only (User Direction)

- **Original assumption:** Subscription column carries text (`✓ required` / `✓ subscribed` / `+ subscribe`).
- **User correction:** "Instead of subscribed, subscribe, and required, just use icons. lock unicode for required, checkmark unicode for subscribed, and plus sign for subscribe."
- **Reason:** User preference for glyph-dense terminal aesthetic over text-heavy column labels.
- **Resolution:** SPEC requirement 2 substantially modified by CONTEXT override. New mapping locked in D-04, D-10b, D-11:
  - `⚿` (U+26BF Squared Key) — required
  - `✓` (U+2713 Check Mark) — subscribed
  - `+` (U+002B Plus Sign) — available to subscribe
- **Constraint surfaced:** No 1-cell BMP padlock glyph exists. Lock emoji `🔒` (U+1F512) is 2-cell and would break Phase 20's fixed-width cluster contract. `⚿` is the closest 1-cell BMP "locked / mandatory" glyph and is also recommended by Phase 20 for its locked-thread atom; cross-screen overlap ("you can't change this state") is intentional.
- **Implementation impact:** D-02 simplified — subscription glyph is now a 2-cell prefix on `RichRow :title` (e.g. `"⚿ announcements"`). Width budget at 64x22 jumps from 24 → 36 cells of name budget (well above the 20-cell minimum).

## External Research

None performed. The codebase contained every precedent needed (Display.Tree facade pattern, sibling list-widget test shapes, `unread_counts/1` aggregation pattern, `Foglet.TimeAgo.format/1` consumer precedent in PostCard, layout-smoke-triple convention).

## Outstanding Coordination Item

**Phase 20 RichRow has not yet shipped** (`lib/foglet_bbs/tui/widgets/list/rich_row.ex` does not exist). Phase 21 plans against `20-CONTEXT.md` D-01/D-02 (the locked Phase 20 contract). When `RichRow` lands, the Phase 21 planner re-validates D-02 (title-prefix approach) against the actual signature before plan 21-01 begins. If RichRow's title-truncation behavior diverges from "right-truncate with `…`", D-02's title-prefix approach must be re-examined.
