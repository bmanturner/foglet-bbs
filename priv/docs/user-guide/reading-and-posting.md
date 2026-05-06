%{
  title: "Reading and posting",
  weight: 20
}
---

Boards hold threads. Threads hold posts. Foglet keeps read state per user so the
BBS can show what changed since you last passed through.

## Find a board

Open the board list from the main menu. Categories can expand and collapse, and
boards appear inside them.

Use:

- `Up` / `Down` or `j` / `k` to move.
- `Left` / `Right` to collapse or expand category nodes.
- `Enter` to open the focused board.
- `S` to subscribe to the focused board.
- `U` to unsubscribe from the focused board.

Some boards are required subscriptions; those cannot be cancelled. Archived
boards are read-only and reject subscription changes. Guests cannot subscribe or
unsubscribe.

Unread counts belong to your account. A guest session can read visible boards,
but it does not carry durable read or subscription state.

## Read a thread list

A board opens to its thread list. Sticky threads appear before normal threads;
inside each group, the most recently active threads appear first. Rows show the
thread title and unread count when Foglet has one for you.

Use:

- `Up` / `Down` or `j` / `k` to move.
- `Enter` to open the selected thread.
- `C` to compose a new thread when posting is allowed.
- `Q` to return to the board list.

The `C` command is hidden or refused when you are a guest, the board does not
allow you to post, or the board is archived.

## Read posts

The post reader loads a window of posts around your current read position. It
tracks what you have seen locally while you move, then flushes that read pointer
when you leave the reader. The pointer is monotonic: seeing later messages moves
it forward; it does not move backward just because you reread older posts.

Use the command bar for the exact keys on your build. The reader supports moving
between posts, scrolling inside a long post, opening profile cards for post
authors, upvoting where allowed, replying where allowed, and backing out to the
thread list. If new activity arrives while you are in a thread, Foglet reloads
the reader window around the current position instead of treating the thread as
a static page.

Deleted posts keep their message numbers. You may see a tombstone instead of
the original text. Gaps are not reused.

## Reply to a thread

From the post reader, use the reply action shown in the command bar. The reply
composer opens inside the same SSH session.

In the composer:

- Type in the body editor.
- `Tab` switches between edit and preview mode.
- `Ctrl+S` posts the reply.
- `Esc` cancels and returns to the thread.

Foglet enforces the sysop-configured maximum post length. Empty replies and
oversized replies are rejected before they are posted.

## Start a new thread

From a thread list, press `C`. Foglet opens a two-step composer:

1. Pick one of your subscribed, postable boards. Type to filter the board list,
   move with arrows, press `Enter` to choose, or `Esc` to cancel.
2. Enter a title and body. `Tab` moves from title to body, then switches the
   body between edit and preview. `Ctrl+S` posts the thread.

New threads require a non-empty title, a non-empty body, and a board you can
post to. Foglet uses the board server to allocate stable per-board message
numbers, so creation may fail if the board is unavailable or your permissions
changed while the composer was open.

## Markdown and previews

Composers preview Foglet's Markdown rendering before you post. The preview is a
convenience, not a separate draft store. Cancelling a composer discards that
screen's draft.

## Posting limits and permissions

Posting depends on the current account, board policy, archived state, and thread
state. Common reasons posting is unavailable:

- You are a guest.
- The board is archived.
- The board is mods-only and you are not a moderator or sysop.
- The thread is locked.
- The post body or thread title exceeds the configured limit.

When a posting action fails, Foglet keeps you in the current flow where it can
and shows the reason. If the problem is a permission change, back out and reopen
the board to refresh your view.
