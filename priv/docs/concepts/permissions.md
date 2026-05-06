%{
  title: "Permissions",
  weight: 30
}
---

Foglet permissions are actor-aware and scope-aware. The short version: callers
can read what a board allows them to read, active members can post where board
policy allows it, moderators can moderate, and sysops can operate the whole
site.

This page explains the current implemented model. It does not promise per-board
moderator assignment or browser admin workflows.

## Roles

Foglet has three account roles:

- `user`: a normal member account.
- `mod`: a moderator account.
- `sysop`: the site operator account.

Guests are not a role in the user table. A guest is an unauthenticated caller or
nil actor. Guest access depends on board and site policy, and guests cannot pass
operator authorization checks.

## Account statuses

Role is not enough. The account must also be allowed to act.

- `active` users can use the permissions their role grants.
- `pending` users are waiting for sysop approval and cannot pass guarded
  operator actions.
- `rejected` users remain in the database but cannot act.
- `suspended` users cannot pass guarded operator actions.
- Deleted users are denied by authorization helpers.

Posting checks also require an active, non-deleted user.

## Board reading policy

Boards carry a `readable_by` policy:

- `public`: readable to guests and members, unless another state such as archive
  handling removes the board from the current surface.
- `members`: readable to signed-in members.

Context fetch helpers such as readable thread and post fetches use board
visibility before returning records. That prevents a caller from using a direct
thread or post lookup to bypass board visibility.

## Board posting policy

Boards carry a `postable_by` policy:

- `members`: active users, moderators, and sysops may post.
- `mods_only`: moderators and sysops may post.
- `sysop_only`: only sysops may post.

Guests cannot post. Pending, rejected, suspended, and deleted users cannot post.

Locked threads add one more gate. Moderators and sysops can bypass a thread lock
when their authorization scope allows the lock action. Normal users cannot reply
to a locked thread.

## Operator authorization

`Foglet.Authorization` implements the Bodyguard policy used by domain contexts.
The contexts are the trust boundary: UI affordances may hide controls, but the
mutation still has to pass authorization at the context layer.

Supported scopes are:

- `:site`, for site-wide operations.
- `{:board, board_id}`, for board-scoped moderation operations.

Sysops are allowed to perform all known guarded actions at any scope.

Moderators can perform moderation actions at site scope and board scope in the
current implementation. The current scope helper returns `[:site]` for mods; a
future per-board moderator table would have to preserve the public helper shape
while narrowing scopes.

Regular users have one special authorization path: they may pass the coarse
`:generate_invite` check at site scope. Runtime configuration still decides
whether member invite generation is enabled and whether caps allow another
invite. Passing the authorization gate does not guarantee invite creation.

Unknown actions, guests, deleted users, pending users, rejected users, and
suspended users are denied.

## Guarded actions

The current guarded action set covers:

- Thread moderation: lock, unlock, sticky, unsticky, move, delete.
- Post moderation: delete post and edit post as moderator.
- Oneliner moderation: hide oneliner.
- Board administration: create, update, and archive boards.
- Category administration: create, update, and archive categories.
- Site configuration: edit config.
- User administration: manage user status.
- Invites: generate and revoke invite.
- Email operations: send test email.

If an action is not in the known set, Foglet denies it by default and logs a
warning. Deny-by-default is intentional.

## Visibility is not authorization

A disabled menu item is not a permission check. It is only the interface being
polite. The context function that changes data must still call the authorization
policy before side effects.

That rule matters when Foglet has multiple surfaces. SSH/TUI, Mix tasks, and
future structured clients should all rely on the same context rules instead of
copying permission logic into each interface.

## Subscriptions are not permissions

Board subscriptions affect what a user follows and what shows as unread. They do
not grant read or post permission by themselves.

A required subscription means the user cannot normally unsubscribe. It does not
make a private board public, and it does not let a user post on a board whose
posting policy excludes them.

## Operational caveats

- Do not promote users casually. `sysop` is full-site authority.
- Treat invite generation policy as both permission and configuration: the role
  gate and runtime config both matter.
- If a caller reports that a board disappeared, check board archive state and
  `readable_by` before looking for data loss.
- If posting fails, check account status, board `postable_by`, and thread lock
  state in that order.
