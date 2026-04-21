---
plan: 01-03
title: List widgets + Post stubs + TimeAgo
status: complete
completed: 2026-04-19
commit: 7813941
---

# Summary — Plan 01-03: List widgets + Post stubs + TimeAgo

## What was done

**SelectionList** (`lib/foglet_bbs/tui/widgets/list/selection_list.ex`):
Stateless renderer. `render(items, selected_index, row_renderer_fn)` — calls
`row_renderer_fn.({item, idx, selected_bool})` for each item, wraps in a `column`.

**ListRow** (`lib/foglet_bbs/tui/widgets/list/list_row.ex`):
`render(label, selected, theme)` — shows `"> label"` (selected) or `"  label"` (unselected)
with `theme.selected.*` or `theme.unselected.*` styling.

**PostCard stub** (`lib/foglet_bbs/tui/widgets/post/post_card.ex`):
Phase 2 deliverable — `render/3` raises immediately. Type contract locked.

**MarkdownBody stub** (`lib/foglet_bbs/tui/widgets/post/markdown_body.ex`):
Phase 2 deliverable — `render/3` raises immediately. Type contract locked.

**TimeAgo** (`lib/foglet_bbs/time_ago.ex`):
stdlib-only relative time formatter. `format(%DateTime{})` returns compact strings:
`"45s"`, `"7m"`, `"3h"`, `"2d"`, `"1w"`, `"6mo"`, `"2y"`. No external deps.
