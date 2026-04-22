# Quick Task 260422-oez: Research

**Task:** Rewrite `posts.user_id` to tombstone user on user deletion and include deleted posts in `Posts.list_posts/1`.
**Date:** 2026-04-22

## Findings

### Existing implementation

- `Foglet.Accounts.delete_user/1` currently runs inside `Repo.transact/1`, deletes `user_tokens`, deletes `ssh_keys`, then applies `User.deletion_changeset/1`.
- `Foglet.Accounts.tombstone_user_id/0` returns the fixed UUID `00000000-0000-0000-0000-000000000001`.
- `priv/repo/seeds.exs` inserts the tombstone user with handle `[deleted]`.
- `Foglet.Posts.Post` has `belongs_to :user, Foglet.Accounts.User`; the DB column `posts.user_id` is non-null and has a foreign key.
- `Foglet.Posts.list_posts/1` preloads `:user`, but filters `is_nil(p.deleted_at)`.

### Best approach

- Add a `Repo.update_all/3` step inside the existing `delete_user/1` transaction:
  - Target `Foglet.Posts.Post` rows where `p.user_id == ^user.id`.
  - Set `user_id: tombstone_user_id()`.
  - Run before `User.deletion_changeset/1` so returned posts point at the tombstone account immediately.
- Do not pre-check tombstone existence. The user explicitly wants failure if seeds were not run; the posts foreign key will enforce that when matching posts are rewritten.
- Update `Posts.list_posts/1` to remove only the `deleted_at` predicate while preserving thread filtering, ordering, and preloading.

### Pitfalls

- `AccountsTest` is currently `async: true`; tests that start board servers and use the DB sandbox need `async: false` or explicit sandbox access. Use a test in an already non-async post context for `list_posts/1`, and either make the account test module non-async or avoid server processes in that module.
- The tombstone seed row may not exist in the test sandbox by default. Tests that expect successful rewriting should insert the tombstone row explicitly using `Repo.insert!`.
- Programmatically-set fields should not be added to `cast/3`; post author rewrite should use `update_all`, not a changeset that casts `user_id`.

## Recommendation

Implement directly in `Foglet.Accounts.delete_user/1` and `Foglet.Posts.list_posts/1`, with targeted tests in:

- `test/foglet_bbs/accounts/accounts_test.exs`
- `test/foglet_bbs/posts/posts_test.exs`

## RESEARCH COMPLETE

Output: `.planning/quick/260422-oez-rewrite-posts-user-id-tombstone-user-id-/260422-oez-RESEARCH.md`
