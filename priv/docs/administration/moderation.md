%{
  title: "Moderation",
  weight: 50
}
---

> **Warning: tentative moderation plan**
>
> This page currently mixes implemented domain capabilities with planned or
> partially wired moderation workflows. Treat it as a design/reference note, not
> as a promise of available operator UI. In the current release, the Moderation
> TUI is largely read-only: report queues, sanctions, warnings, mutes, bans,
> public audit browsing, bulk tools, and several content-action workflows are
> not fully implemented or exposed end-to-end yet.

This page describes Foglet's current moderation surface. It covers what exists now and names what should not be promised yet.

## Moderation scope

Sysops can perform every guarded action at site scope. Mods can perform the current moderator actions at site or board scope, except site configuration edits.

Normal users do not get moderation powers. Pending, rejected, suspended, and deleted accounts are rejected before role-specific permission checks.

## Current actions

The implemented moderation surface centers on message-area maintenance:

| Action | What it does |
| --- | --- |
| Lock thread | Prevents new replies while leaving the thread readable. |
| Unlock thread | Allows replies again, subject to board posting policy. |
| Sticky thread | Pins a thread above normal threads in the board list. |
| Unsticky thread | Returns a thread to normal list ordering. |
| Move thread | Moves a thread to another board and updates post board references. |
| Delete post | Soft-deletes a post and may store a reason. |
| Delete thread | Soft-deletes a thread. |
| Hide oneliner | Hides a one-line wall entry while preserving moderation context. |
| User status changes | Sysops can approve, reject, suspend, and reactivate users. |

The data model also includes audit-oriented moderation tables for reports, actions, and sanctions. Do not assume every table has a complete public TUI workflow in the current release.

## What moderators can see and do

Moderators can see archived boards where the directory exposes moderator visibility. They can act on board-scoped content through guarded context functions. The TUI may hide unavailable actions, but hidden UI is not authorization; the domain action still checks policy.

## What sysops can do

Sysops can do all moderator actions and also administer users, categories, boards, site settings, and test email delivery.

Sysop user-status transitions are deliberately narrow:

- pending -> active
- pending -> rejected
- active -> suspended
- suspended -> active

Sysops cannot use the status screen to change deleted users, reject active users, or unsuspend rejected users.

## Audit and retention notes

Foglet preserves history by default:

- deleted posts and threads are soft-deleted
- deleted accounts are anonymized, not purged
- message numbers are not reused
- oneliners are hidden, not erased, where moderation uses the hide path

Moderation action/report/sanction tables are designed as append-heavy records. Public operator docs should treat full report queues, warnings, mutes, temporary bans, and permanent bans as not yet supported unless the current release exposes them.

## Not currently promised

Do not promise these as available moderation features unless you verify them in the running release:

- user reports from the TUI
- a complete moderation queue
- automated sanctions
- warning/mute/ban workflows
- public audit-log browsing
- bulk moderation tools

If callers need one of those, track it as future work rather than documenting it as current behavior.
