---
status: ready
must_haves:
  truths:
    - Accounts.delete_user/1 rewrites posts.user_id to Foglet.Accounts.tombstone_user_id/0.
    - The rewrite fails through normal database constraints if the tombstone seed row is missing.
    - Posts.list_posts/1 returns soft-deleted posts.
    - Posts.list_posts/1 still filters by thread_id, orders by inserted_at ascending, and preloads :user.
  artifacts:
    - lib/foglet_bbs/accounts.ex
    - lib/foglet_bbs/posts.ex
    - test/foglet_bbs/accounts/accounts_test.exs
    - test/foglet_bbs/posts/posts_test.exs
  key_links:
    - .planning/quick/260422-oez-rewrite-posts-user-id-tombstone-user-id-/260422-oez-CONTEXT.md
    - .planning/quick/260422-oez-rewrite-posts-user-id-tombstone-user-id-/260422-oez-RESEARCH.md
---

# Quick Task 260422-oez: Plan

## Goal

When a user is deleted, authored posts should be anonymized to the seeded tombstone user, and thread post listing should preserve soft-deleted posts so readers keep message-number context.

## Tasks

### 1. Rewrite post authorship during account deletion

**files:** `lib/foglet_bbs/accounts.ex`, `test/foglet_bbs/accounts/accounts_test.exs`

**action:** Add a transaction step in `Accounts.delete_user/1` that updates all `Foglet.Posts.Post` rows from the deleted user's id to `tombstone_user_id/0`. Add a test that inserts the tombstone user, creates a post authored by a user, deletes that user, and asserts the post now points to the tombstone user and preloads handle `[deleted]`.

**verify:** `mix test test/foglet_bbs/accounts/accounts_test.exs`

**done:** Post rows authored by deleted users no longer point at the anonymized user row.

### 2. Return deleted posts from list_posts/1

**files:** `lib/foglet_bbs/posts.ex`, `test/foglet_bbs/posts/posts_test.exs`

**action:** Remove the `is_nil(p.deleted_at)` predicate from `Posts.list_posts/1` and update the existing deletion test to assert soft-deleted posts remain in the returned list.

**verify:** `mix test test/foglet_bbs/posts/posts_test.exs`

**done:** Thread post listing preserves deleted posts while still ordering and preloading normally.

### 3. Validate and record completion

**files:** `.planning/quick/260422-oez-rewrite-posts-user-id-tombstone-user-id-/260422-oez-SUMMARY.md`, `.planning/quick/260422-oez-rewrite-posts-user-id-tombstone-user-id-/260422-oez-VERIFICATION.md`, `.planning/STATE.md`

**action:** Run focused tests and `mix precommit`; write summary/verification artifacts and update the quick task table.

**verify:** `mix precommit`

**done:** Quick task artifacts record tests, verification status, and final commit.

## Plan Check

Coverage: PASS. The plan covers both requested behavior changes and the user decisions from discussion.

Scope: PASS. Two production files and two focused test files are sufficient.

Risk: PASS. The DB foreign key supplies the requested failure mode when the tombstone row is missing and affected posts exist.
