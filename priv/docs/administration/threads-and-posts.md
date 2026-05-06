%{
  title: "Threads and posts",
  weight: 40
}
---

This page explains Foglet's thread and post model for operators and moderators. Use it when you need to understand locked/sticky state, soft deletion, read pointers, upvotes, and message numbers.

## Threads

A thread belongs to one board and has:

- title
- creator
- first post
- locked flag
- sticky flag
- soft-delete timestamp
- post count
- last-post timestamp

Thread lists put sticky threads first, then sort by recent activity. Deleted threads are filtered out of normal active lists.

## Posts

A post belongs to a thread and board, and has a per-board message number. Posts store the current body, edit metadata, soft-delete timestamp, optional deletion reason, upvote count, edit count, and last-edited timestamp.

Replies use the same post table as first posts. A reply may point at another post through `reply_to`.

## Stable message numbers

Message numbers are per board, stable, and user-visible. Foglet treats them like old-network message numbers: gaps are allowed because history happened there.

Important invariants:

- Thread and reply creation route through the board server.
- The board server is the single writer for message-number allocation.
- Soft-deleted posts keep their numbers.
- Moving a thread updates the post board reference but does not rewrite the historical message numbers.

Do not repair gaps with SQL. A missing number usually means a deleted or moved thing, not a broken sequence.

## Locked and sticky threads

Moderators and sysops can lock, unlock, sticky, and unsticky threads through the domain actions available to the TUI.

| State | Effect |
| --- | --- |
| locked | New replies are rejected. Existing posts remain readable. |
| sticky | The thread is pinned above non-sticky threads in the board's thread list. |

Locking is not deletion. Sticky is not priority moderation; it is just ordering.

## Moving threads

Moving a thread changes its board. Foglet also updates the denormalized board field on posts so board-scoped queries remain correct.

The existing message numbers remain historical. A moved thread may therefore carry numbers that were allocated by its original board.

## Soft deletion

Threads and posts are soft-deleted. Normal read queries filter deleted rows out, but the rows remain so counts, audit trails, foreign keys, and message-number history do not collapse.

Post deletion accepts an optional reason. Moderator deletion should use a reason when possible; self-delete paths may leave it blank.

Account deletion is different: authored posts are rewritten to the tombstone user rather than hard-deleted.

## Edits and upvotes

Edits are append-only history rows. Foglet stores the previous body for each edit so the sequence can be reconstructed.

Upvotes are one per user per post. Toggling an upvote inserts or removes that row and reconciles the post's denormalized upvote count.

## Read pointers

Foglet stores two kinds of read state:

- board read pointers: last read message number per user and board
- thread read pointers: last read post per user and thread

Read pointers are monotonic persisted state. UI-local scrolling is separate from persisted read state.
