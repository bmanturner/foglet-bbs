# Phase 3: Read-pointer correctness + thread-row enrichment — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-19
**Phase:** 03-read-pointer-correctness-thread-row-enrichment
**Areas discussed:** Thread row layout, Read-on-entry behavior, Board refresh timing

---

## Thread row layout

| Option | Description | Selected |
|--------|-------------|----------|
| Single line, right-aligned metadata | Title left, metadata right-aligned in a fixed column. Title truncated with … if it crowds the metadata. | ✓ |
| Two-line row | Line 1: title. Line 2: dimmed @handle · N posts · Xh ago. More room for titles, double screen space. | |
| Single line, metadata inline after title | Title then space then metadata. Position shifts with each title length — harder to scan. | |

**User's choice:** Single line, right-aligned metadata  
**Notes:** Metadata field is variable-width (not fixed column) — expands/contracts with content, title adapts.

---

## Metadata columns

| Option | Description | Selected |
|--------|-------------|----------|
| @handle · N posts · Xh ago | All three pieces. | ✓ |
| @handle · Xh ago (no post count) | Simpler, post count visible on open. | |
| N posts · Xh ago (no handle) | Activity stats only. | |

**User's choice:** All three (`@handle · N posts · Xh ago`), but metadata field is variable depending on N and handle length  
**Notes:** Width is content-driven, not fixed.

---

## Overflow strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Truncate title, preserve full metadata | Title gets … to make room. Metadata always fully visible. | ✓ |
| Truncate metadata, preserve full title | Thread title shown in full; metadata trimmed if needed. | |
| Claude decides | Whatever fits best at the given terminal width. | |

**User's choice:** Truncate title, always preserve full metadata

---

## Unread indicator on thread rows

| Option | Description | Selected |
|--------|-------------|----------|
| Keep numeric unread count | Show "(N unread)" alongside metadata. | |
| Drop unread count entirely | Clean row with creator + count + time only. | |
| Visual distinction without count | Some marker for unread threads, no number. | ✓ |

**User's choice:** Visual distinction — not a numeric unread count, but something to distinguish unread threads  
**Notes:** User wanted to convey "has unread" without cluttering with a number.

---

## Unread visual treatment

| Option | Description | Selected |
|--------|-------------|----------|
| Bold title when unread | Unread threads show title in bold; read threads normal weight. | ✓ |
| Prefix marker (• or *) | Bullet before title. Takes 2 chars of title space. | |
| Accent color on unread title | Theme.accent (amber/orange) color. | |

**User's choice:** Bold title when there are unread posts

---

## Read-on-entry behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Mark first post as read on entry | Opening a thread counts as seeing post 1. Pointer advances even without j/k. | ✓ |
| Only advance when user navigates | Current behavior. Requires j/k to advance pointer. | |
| Mark ALL posts read on entry | Too aggressive. | |

**User's choice:** Mark the first post as read on entry (initialize read_position on `load_posts`)  
**Notes:** "Mark first post as seen on entry" — if you saw it, you read it.

---

## Board refresh timing

| Option | Description | Selected |
|--------|-------------|----------|
| Immediate on Q + after flush | Dispatch load_boards on Q keypress AND again after flush completes. | ✓ |
| Only after flush (accurate, slight delay) | Board shows stale data for ~100ms then corrects. | |
| Only on Q press (immediate, may lag) | Refreshes on navigation but not after flush. | |

**User's choice:** Immediate refresh on Q press + refresh again after flush completes  
**Notes:** Two-phase design is intentional UX — prevents stale landing, corrects after flush.

---

## Claude's Discretion

- `GREATEST` fix in `advance_board_read_pointer/3` upsert — monotonicity guarantee
- Thread unread detection strategy (add user_id to list_threads, separate query, or compare timestamps)
- `Foglet.TimeAgo` format (already specified in REQUIREMENTS.md)
- Row renderer implementation inside `List.ListRow` / `List.SelectionList`

## Deferred Ideas

None — discussion stayed within phase scope.
