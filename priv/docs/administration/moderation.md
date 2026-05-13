%{
  title: "Moderation",
  weight: 50
}
---

> **Warning: narrow moderation surface**
>
> Foglet now has a TUI report queue, but it is not a full case-management
> system. Sanctions, warnings, mutes, bans, public audit browsing, and bulk
> tools are not complete operator workflows in the current release.

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
| Create report | Lets a signed-in caller report a supported user, post, thread, or oneliner target. |
| Review report queue | Lets mods and sysops list open reports visible to their scope. |
| Resolve or dismiss report | Closes an open report with moderator notes. |
| User status changes | Sysops can approve, reject, suspend, and reactivate users. |

The data model also includes audit-oriented moderation action and sanction tables. Do not assume every table has a complete public TUI workflow in the current release.

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

Moderation action/report/sanction tables are designed as append-heavy records. Public operator docs should treat warnings, mutes, temporary bans, and permanent bans as not yet supported unless the current release exposes them.

## Not currently promised

Do not promise these as available moderation features unless you verify them in the running release:

- automated sanctions
- warning/mute/ban workflows
- public audit-log browsing
- bulk moderation tools

If callers need one of those, track it as future work rather than documenting it as current behavior.
