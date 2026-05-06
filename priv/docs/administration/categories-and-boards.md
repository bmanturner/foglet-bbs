%{
  title: "Categories and boards",
  weight: 30
}
---

This page explains how sysops organize Foglet's public message areas. Categories are menu groups. Boards are the places where threads, posts, subscriptions, unread counts, and optional board chat live.

## Categories

A category has:

- name
- description
- display order
- archived flag

Categories are presentation groups. Archiving a category removes it from the normal active board directory. Mods and sysops may still see archived structure where the TUI exposes moderator/operator views.

In the sysop area, use the `BOARDS` tab. Press `N` to create a category or `E` while a category row is selected to edit it. Category edit fields are name, description, and display order.

## Boards

A board has:

- slug
- name
- description
- category
- display order
- readable policy
- postable policy
- archived flag
- default/required subscription flags
- optional board chat settings
- a persisted next message number

The board slug is command-friendly and must be unique. Current validation accepts lowercase letters, digits, underscores, and hyphens, up to 50 characters.

## Board permissions

| Field | Values | Effect |
| --- | --- | --- |
| `readable_by` | `public`, `members` | Public boards can be read by guests when guest mode allows it. Member boards require an active account. |
| `postable_by` | `members`, `mods_only`, `sysop_only` | Controls who may create threads or replies on the board. |

Posting also fails when the account is pending, rejected, suspended, or deleted. Archived boards reject subscribe/unsubscribe and posting flows that require an active board.

## Subscriptions

`default_subscription` means new/default subscription setup should subscribe users to the board.

`required_subscription` means users cannot unsubscribe. Required subscription is only valid when default subscription is also true; Foglet enforces this in validation and with a database check constraint.

When a board is changed to required subscription, existing users are subscribed to it.

Unread counts are subscription-aware. Foglet tracks a board read pointer per user and board, and only shows unread counts for subscribed boards in the directory model.

## Board chat

Some builds expose chat fields in the sysop board form:

| Field | Meaning |
| --- | --- |
| Chat | Adds a `CHAT` tab next to `THREADS` for the board. |
| Chat storage | `ephemeral` or `permanent`. |
| Chat retention | Retention window for ephemeral board chat messages. |

Chat settings belong to the board. They do not change the stable message-number sequence for threads and posts.

## Managing boards in the TUI

From the sysop area, open `BOARDS`.

| Key | Action |
| --- | --- |
| `n` | Create a board. |
| `N` | Create a category. |
| `e` | Edit the selected board. |
| `E` | Edit the selected category. |
| `D` | Archive the selected board or category after confirmation. |
| `Enter` or Space | Collapse or expand a category row. |

Board creation/editing currently exposes slug, name, description, category, postable policy, subscription flags, and chat settings. The underlying schema also has a readable policy; if your TUI does not expose it, treat readable-policy changes as an operator-tooling task for this release.

## Message numbers

Each board owns its own message-number sequence. Thread and post creation route through the board server, which allocates the next number and writes it through with the post transaction.

Do not renumber boards by hand. Soft-deleted posts keep their numbers, and moving a thread does not rewrite historical message numbers.
