---
status: complete
quick_id: 260422-oez
date: 2026-04-22
commit: 72eb560
---

# Quick Task 260422-oez Summary

## Completed

- Added `Accounts.delete_user/1` post-author rewrite from the deleted user's id to `Accounts.tombstone_user_id/0`.
- Kept tombstone ownership seed-driven: when matching posts exist and the tombstone user row is absent, the database foreign key fails the deletion transaction.
- Changed `Posts.list_posts/1` to return all posts in a thread, including soft-deleted posts, while preserving insertion ordering and `:user` preload.
- Added tests for tombstone rewrite and soft-deleted post visibility.

## Verification

- `mix test test/foglet_bbs/accounts/accounts_test.exs` passed.
- `mix test test/foglet_bbs/posts/posts_test.exs` passed.
- `mix precommit` passed.

## Code Commit

- `72eb560` - `fix(posts): tombstone deleted user authors`
