# Voice and tone

Foglet should sound like a small place run by a person: direct, calm, and a little warm. The words should help someone use the BBS without explaining the implementation underneath it.

## Audience

- Visitors deciding whether to look around.
- Members reading, posting, and maintaining their account.
- Sysops configuring a self-hosted BBS.
- Contributors adding terminal UI flows, operator tasks, and docs.

## Product promises

- SSH-first: the terminal is the main door, not a fallback.
- Human-scale: prefer plain labels and short prompts over platform jargon.
- Old-network feeling: familiar BBS ideas are welcome when they make the place feel personal; nostalgia should not excuse confusing UI.
- Explicit permissions: if someone cannot do something, say what is allowed and what to do next.

## Vocabulary

Use these terms consistently:

| Prefer | Avoid | Notes |
|---|---|---|
| BBS | app, platform, social network | BBS is the product surface. |
| board | channel, category page | Category is an organizing concept; board is where people read and post. |
| thread | topic, issue | Threads contain posts. |
| post / reply | message when referring to persisted board content | Message numbers are a data-model term; do not expose them unless useful. |
| sysop | admin, site owner | Use admin only when matching a library/API concept. |
| guest | anonymous user, nil user | Guest is a deliberate read-only mode, not a failed login state. |
| door game | external game, plugin | Door game is the BBS term. |

## Error and denial style

Good denial copy is specific without blaming the user.

- Say what happened: "Guests can read boards but cannot post."
- Say what to do next when there is a useful action: "Log in to reply."
- Do not reveal internal checks, schema names, atoms, stack traces, or config keys.
- Do not imply the user did something wrong when the system is enforcing policy.

Examples:

| Context | Use | Avoid |
|---|---|---|
| Guest tries to post | Guests can read boards, but posting needs a member account. Log in to reply. | Permission denied: current_user is nil. |
| Guest tries a door game | Door games are for logged-in members. Log in to play. | Guests are not authorized to launch doors. |
| Feature disabled by sysop | Guest browsing is closed on this BBS. Log in to continue. | guest_mode_enabled=false. |
| Validation problem | That title is too long. Try 60 characters or fewer. | Invalid field max_thread_title_length. |

## Confirmation pattern

Use confirmations for destructive or hard-to-undo actions. Keep them short:

1. Name the action.
2. Name the consequence.
3. Offer a clear cancel path.

Example: "Delete this draft? It will be gone for this session. Y deletes, Esc keeps it."

## Guest Mode copy source

Guest Mode is read-only browsing for visitors who are not logged in. It should feel invited, not second-class. Copy should make the contract clear: guests can look around; members can post, chat, manage accounts, and play door games.

Proposed terminal copy:

| Surface | Copy |
|---|---|
| Login menu option | `[G] Visit as guest` |
| Login hint when enabled | `Look around without an account. Guests can read public boards only.` |
| Login hint when disabled | `Guest browsing is closed on this BBS. Log in or register to continue.` |
| Guest read-only status hint | `Guest mode: read-only` |
| Main Menu guest hint | `You are visiting as a guest. Read public boards, or log in to post and play.` |
| New thread/reply denial | `Guests can read boards, but posting needs a member account. Log in to continue.` |
| Oneliner denial | `Guests can read oneliners, but posting one needs a member account.` |
| Chat send denial | `Guests can read chat where it is open, but sending messages needs a member account.` |
| Door games denial | `Door games are for logged-in members. Log in to play.` |
| Account/preferences hidden-state hint if surfaced | `Account settings are available after login.` |

Length notes:

- Menu labels should fit comfortably in 80 columns.
- Modal body copy should be one or two short sentences.
- Prefer "member account" over "authenticated user" in user-facing UI.

## Contributor copy checklist

Before merging a user-facing flow, check:

- Every new label, prompt, empty state, denial, and confirmation has been read in the terminal context where it appears.
- Copy explains the user outcome, not the implementation detail.
- Guest behavior is explicit: can guests read it, write to it, launch it, or see it at all?
- Mutations have backend authorization; hidden UI is not treated as security.
- Denials give a next step when there is one.
- New docs do not expose secrets, local-only review artifacts, or internal Paperclip/agent process notes.
