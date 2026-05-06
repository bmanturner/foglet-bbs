%{
  title: "Board chat",
  weight: 10
}
---

Board chat is the live side-channel attached to a board. Threads and posts are
still the durable BBS record; chat is for quick presence, coordination, and the
small bits of static that do not need a message number.

Chat appears as a tab inside a board screen when that board has chat enabled.
Members can read and post there if they can read the board. Guests do not post
chat messages, and guest-readable access does not turn chat into anonymous
writing.

## What board chat is for

Use board chat when callers need a live room beside a board:

- quick coordination while reading the same board
- short replies that do not belong in the thread archive
- operator announcements during a live session
- presence: seeing who is currently in the board/chat surface

Use threads and posts when the information should survive as part of the board's
record. Chat messages do not receive per-board message numbers.

## Storage modes

Each board has three chat settings:

| Setting | Meaning |
|---|---|
| `chat_enabled` | Whether the board exposes the chat tab. |
| `chat_storage_mode` | `ephemeral` for in-memory TTL chat, or `permanent` for database-backed chat. |
| `chat_message_ttl_seconds` | Retention window for ephemeral chat messages. |

`ephemeral` is the default storage mode. Messages live in memory, expire after
the board's TTL, and disappear when the ephemeral chat room is stopped or the
application restarts. This is the right mode for chatter that should scatter.

`permanent` stores chat rows in Postgres. The current reader loads the most
recent 100 messages for the board, oldest first, then appends live messages from
PubSub. Permanent chat is durable, but it is still chat: use board threads for
canonical announcements, decisions, and material that should be searchable as
part of the BBS archive.

## Retention

For ephemeral chat, the board's TTL controls how long messages remain in the
in-memory buffer. The public operator tool accepts values from 60 seconds to
86400 seconds. The TUI board editor may present safer presets rather than asking
operators to type raw seconds.

For permanent chat, the TTL setting does not expire database rows. The current
TUI fetches a bounded recent-history window instead of the full table.

## Access and guest behavior

Chat uses the board's read policy for history visibility:

- A caller must be allowed to read the board to receive recent chat history.
- Guests receive no chat history for members-readable boards.
- Posting requires an authenticated user. Anonymous chat posting is not
  supported.
- Disabled chat returns no history and refuses new messages.

Board chat is not an authorization boundary by itself. It follows the board's
existing visibility rules and the posting path rejects guests before storage is
considered.

## Live behavior in the TUI

When the chat tab opens, Foglet loads recent history and subscribes the screen to
board chat updates. New messages are delivered live over PubSub. The same screen
also tracks board-screen presence so the sidebar can show who is around.

The chat layout adapts to terminal width:

| Width | Layout |
|---|---|
| 80 columns or wider | Transcript plus sidebar by default. |
| 60–79 columns | Sidebar starts collapsed; `Ctrl+B` toggles it. |
| Under 60 columns | Transcript only; the sidebar toggle is hidden. |

The screen keeps a local transcript buffer for display. That local buffer is not
the retention policy and is not a substitute for permanent storage.

## Operator commands

Use the board-chat Mix task when you need to inspect or adjust chat settings from
the host shell:

```bash
mix foglet.board_chat show --board general
mix foglet.board_chat enable --board general --actor sysop
mix foglet.board_chat disable --board general --actor sysop
mix foglet.board_chat set-mode --board general --mode ephemeral --actor sysop
mix foglet.board_chat set-mode --board general --mode permanent --actor sysop
mix foglet.board_chat set-ttl --board general --seconds 7200 --actor sysop
```

`show` is read-only and does not require an actor. Mutating commands require an
actor handle because they route through the same board update path as sysop UI
changes. The actor must be authorized to update boards.

The task refuses to mutate archived boards. It also short-circuits unchanged
settings with a no-change message instead of pretending work happened.

## Troubleshooting

### The chat tab is missing

Confirm the board has chat enabled:

```bash
mix foglet.board_chat show --board BOARD_SLUG
```

If `chat_enabled` is `false`, enable it with a sysop actor:

```bash
mix foglet.board_chat enable --board BOARD_SLUG --actor SYSOP_HANDLE
```

### Messages disappear

Check the storage mode. In `ephemeral` mode, messages expire after the board's
TTL and do not survive application restarts. Switch to `permanent` if the board
needs durable chat history:

```bash
mix foglet.board_chat set-mode --board BOARD_SLUG --mode permanent --actor SYSOP_HANDLE
```

### A guest cannot post

That is expected. Board chat does not support anonymous posting.

### A member cannot see chat history

Verify the member can read the board first. Chat history uses the same board read
policy. If the board is members-only, guests and unauthenticated sessions receive
no history.

### A command says the board is archived

Archived boards cannot be mutated by the board-chat task. Unarchive or replace
the board through the normal board administration path before changing chat
settings.
