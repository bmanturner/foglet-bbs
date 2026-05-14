# BBS Mail privacy and retention copy

This note gives implementers the exact user-facing copy and doc policy for BBS
Mail direct-message screens. Use it when adding inbox, conversation, compose,
reply, report, delete-from-my-view, and sysop/moderation surfaces.

## Conversation/read screen notice

Place this notice at the top of every BBS Mail conversation/read screen, below
the screen title or conversation header and above the first message. Keep it
visible before any scrollable message history at every supported terminal size.

Preferred copy for 80 columns and wider:

```text
private to participants in normal screens; not encrypted at rest.
sysops may inspect mail for policy, reports, retention, and repair.
```

Narrow copy for constrained terminals:

```text
private here; not encrypted at rest.
sysops may inspect for policy, reports, retention, and repair.
```

Do not shorten this to "private" alone. The at-rest encryption warning and
operator-visibility warning are required parts of the notice.

## Placement by screen

- Conversation/read: show the full notice at the top of the message pane before
  chronological history. If the conversation header is sticky, the notice may be
  sticky too; otherwise it must be the first scroll position.
- Reply: keep the conversation/read notice visible above the history preview or
  compose box. If space only permits one policy line, use the narrow copy and
  keep the full copy one help keystroke away.
- Compose-new-message: show the same notice above the body editor before the
  user types. If the screen cannot fit both lines and the body editor, show the
  narrow first line and an inline hint: `policy: ctrl-p` or the established help
  command.
- Inbox and sent lists: no persistent notice is required, but the first empty
  state or help view for BBS Mail should say `BBS Mail is private to the named
  participants in normal screens, not encrypted at rest.`
- Report flow: do not promise secrecy. Use `report sends this conversation to
  the operators.`

## Destructive/action copy

Use these strings for common BBS Mail actions:

```text
[D]elete from my view / [esc] keep it

remove this message from your view only. the other participant keeps theirs.
```

```text
[R]eport / [esc] cancel

send this conversation to the operators for review.
```

```text
sent. the other node will see it when they check mail.
```

```text
no mail. the wire is quiet.
```

## Sysop/mod visibility policy

Document and implement against this policy unless a later ADR changes it:

- Direct messages are visible only to the two participants in normal member UI.
- Direct messages are stored in the database as application data. They are not
  encrypted at rest by the application.
- Sysops may inspect direct messages through operator tooling for abuse reports,
  moderation, legal/compliance handling, retention cleanup, and system repair.
- Moderators should not receive broad direct-message browsing by default. Give
  mods access only through a report/review workflow or explicit scoped operator
  permission.
- Report handling may expose the reported conversation, relevant surrounding
  messages, participant handles, timestamps, and message IDs to operators.
- Operator access should leave an audit trail when practical. Do not present
  audit logging as a shipped guarantee until implementation exists.

## Retention and deletion policy

- User deletion/anonymization rewrites direct messages authored by the deleted
  user to the tombstone user, removes unread direct messages addressed to the
  deleted user, and clears account/profile identity according to the account
  deletion flow in `docs/DATA_MODEL.md`.
- Delete-from-my-view is per participant. It hides a message from that
  participant's conversation history and does not remove it from the other
  participant's view.
- A message may be hard-deleted only after both participants have removed it
  from their views, or by an explicit operator retention/moderation process.
- Retention tooling may remove or anonymize direct-message data according to
  site policy. Until a configurable retention job ships, do not claim automatic
  expiry in user-facing copy.

## Public docs wording

Use this paragraph in user/sysop docs when BBS Mail ships:

> BBS Mail is a two-person message thread inside the BBS. Messages are private
> to the participants in normal screens, but Foglet does not encrypt them at
> rest. Sysops can inspect mail when they handle reports, enforce policy, run
> retention cleanup, or repair the system. Deleting a message removes it from
> your view; it does not erase the other participant's copy.

## Content risks

- Do not call BBS Mail "secure messaging" or "encrypted messaging".
- Do not promise that moderators can or cannot see mail unless the permission
  model in code matches the claim.
- Do not promise automatic direct-message retention expiry until the cleanup job
  and configuration exist.
- Do not say reports are anonymous unless the report implementation proves it.
