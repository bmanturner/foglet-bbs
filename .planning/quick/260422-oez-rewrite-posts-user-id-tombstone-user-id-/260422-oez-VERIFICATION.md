---
status: passed
quick_id: 260422-oez
date: 2026-04-22
commit: 72eb560
---

# Quick Task 260422-oez Verification

## Must-Haves

- PASS: `Accounts.delete_user/1` rewrites `posts.user_id` to `Foglet.Accounts.tombstone_user_id/0`.
- PASS: The rewrite relies on the existing foreign key, so matching posts fail deletion if the tombstone seed row is missing.
- PASS: `Posts.list_posts/1` returns soft-deleted posts.
- PASS: `Posts.list_posts/1` still filters by `thread_id`, orders by `inserted_at` ascending, and preloads `:user`.

## Evidence

- Added `test "rewrites authored posts to the tombstone user"` in `test/foglet_bbs/accounts/accounts_test.exs`.
- Updated the post deletion list test in `test/foglet_bbs/posts/posts_test.exs` to assert soft-deleted posts remain visible and still preload the author.
- `mix precommit` completed successfully.

## Result

Verified.
