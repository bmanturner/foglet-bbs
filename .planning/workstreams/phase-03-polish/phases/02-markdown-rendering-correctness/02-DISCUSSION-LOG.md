# Phase 2: Markdown rendering correctness — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-19
**Phase:** 02 — Markdown rendering correctness
**Areas discussed:** MarkdownBody widget contract, Newline-to-layout mapping, Long-post vertical behavior, Wrapping strategy for RENDER-02

---

## MarkdownBody widget contract

| Option | Description | Selected |
|--------|-------------|----------|
| Option A: MarkdownBody owns full pipeline | `Post.MarkdownBody.render(%{body: string, width: int, theme: theme})`. Memoization keyed on `{body, width}` lives inside widget. | |
| Option B: PostReader renders, widget lays out | PostReader calls `Foglet.Markdown.render/1`, passes tuples to `Post.MarkdownBody`. | |
| Option C: PostCard wraps everything | `PostCard.render(%{post: post, width: int, theme: theme})` handles author header + MarkdownBody. One widget per post. | ✓ |

**User's choice:** Option C — PostCard wraps everything
**Notes:** "Let the planner decide after researching. Preference for PostCard." User confirmed PostCard as the integration unit.

---

## Newline-to-layout mapping

| Option | Description | Selected |
|--------|-------------|----------|
| Option A: Filter → spacer | Keep Foglet.Markdown output as-is. MarkdownBody filters `{"\n", :plain}` tuples and replaces with `spacer()`. | |
| Option B: Group tuples into lines | MarkdownBody groups tuples between newline markers into line-groups, emits one styled `text/2` per physical line. | |
| Option C: Fix Markdown to return list-of-lines | Change `Foglet.Markdown.render/1` contract to return `[[{text, style}]]` (lines as outer list). | |

**User's choice:** Deferred — "Let the planner decide after researching."
**Notes:** All three options left open for the planner to evaluate. Constraint noted: must eliminate visible `\n` artifacts without breaking existing `Foglet.Markdown` tests.

---

## Long-post vertical behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Clip — let Raxol/terminal handle it | No within-post scroll. Raxol renders full column, terminal clips at bottom. | |
| Add j/k within-post scroll | PostReader tracks `scroll_offset` in `screen_state`. MarkdownBody renders a window of lines. | ✓ |

**User's choice:** Add j/k within-post scroll
**Notes:** Long seeded posts in General board would be unreadable without scroll. j/k chosen for keys; scroll resets to top on N/P post navigation.

Follow-up questions answered:
- **Scroll keys:** j/k only (no Space/b page-scroll)
- **Scroll position on N/P navigation:** Reset to top (predictable, recommended option selected)

---

## Wrapping strategy for RENDER-02

| Option | Description | Selected |
|--------|-------------|----------|
| Trust Raxol layout | Emit `text/2` nodes without manual wrapping. Raxol's Flexbox handles word-wrap at terminal boundary. | |
| Pre-wrap at width in MarkdownBody | Split long lines at `width` chars before emitting `text/2`. Unicode-aware required. | |
| Pre-wrap only for code blocks | Trust Raxol for prose; manually wrap code block lines at width-4. | |

**User's choice:** Deferred — "Let planner verify Raxol layout can be trusted and then decide."
**Notes:** Planner must empirically verify Raxol `text/2` word-wrap behavior before choosing. Code blocks flagged as most likely overflow candidates.

---

## Claude's Discretion

- Newline layout strategy (A/B/C) — planner chooses after research
- Wrapping strategy — planner verifies Raxol behavior then decides
- Whether PostCard or MarkdownBody calls `Foglet.Markdown.render/1` internally
- Memoization: planner decides cache location (`PostCard` vs `PostReader`)
- Bold style mapping: `theme.accent` vs `theme.primary` with `[:bold]`

## Deferred Ideas

None.
