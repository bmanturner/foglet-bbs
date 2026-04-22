# Quick Task 260422-oez: Rewrite posts.user_id to tombstone_user_id on user deletion and include deleted posts - Context

**Gathered:** 2026-04-22
**Status:** Ready for research

<domain>
## Task Boundary

Rewrite `posts.user_id` to `Foglet.Accounts.tombstone_user_id/0` when deleting a user, and stop filtering soft-deleted posts out of `Foglet.Posts.list_posts/1`.

</domain>

<decisions>
## Implementation Decisions

### Tombstone user handling
- `Accounts.delete_user/1` should fail if the tombstone user seed row is missing.
- The deletion flow should not silently create the tombstone user. Seeds remain authoritative.

### Rewrite scope
- Only rewrite `posts.user_id` in this quick task.
- Do not expand into direct messages or other future authored-content tables.

### Deleted posts in post listing
- `Posts.list_posts/1` should return all posts in the thread regardless of `deleted_at`.
- Normal retrieval/rendering should apply. Because `list_posts/1` preloads `:user`, rewritten posts should load the tombstone user and expose handle `[deleted]` through the existing UI path.

</decisions>

<specifics>
## Specific Ideas

- Preserve the existing `Repo.transact/1` deletion transaction so token/key cleanup, post rewrite, and user anonymization are atomic.
- Add tests proving post authorship is rewritten and soft-deleted posts are returned by `list_posts/1`.

</specifics>

<canonical_refs>
## Canonical References

- `docs/DATA_MODEL.md` account deletion flow says posts authored by a deleted user are rewritten to the tombstone user.
- `.planning/codebase/CONCERNS.md` calls out the missing post rewrite and hidden soft-deleted posts as known concerns.
- `AGENTS.md` requires `mix precommit` after changes.

</canonical_refs>
