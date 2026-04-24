---
phase: 11-posting-policy-enforcement
verified: 2026-04-24T20:43:48Z
status: human_needed
score: 4/4 must-haves verified
overrides_applied: 0
human_verification:
  - test: "Exercise rejected new-thread and reply submissions in the SSH/TUI."
    expected: "Posting-policy denial shows `You are not allowed to post on this board.`, locked reply denial shows exactly `This thread is locked`, and the user remains in the composer instead of navigating as success."
    why_human: "Automated screen-state tests verify exact copy and navigation state, but final terminal presentation and end-to-end interaction are user-visible TUI behavior."
---

# Phase 11: Posting Policy Enforcement Verification Report

**Phase Goal:** Users can only create threads and replies when board policy and thread state permit the action.
**Verified:** 2026-04-24T20:43:48Z
**Status:** human_needed
**Re-verification:** No - initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | User can create a thread only when the board's `postable_by` policy permits their role. | VERIFIED | `Foglet.Threads.create_thread/3` loads persisted user and board through `safe_get/2`, calls `PostingPolicy.can_post?/2`, returns `{:error, :posting_not_allowed}` before `Boards.Server.create_thread/3` on denial, and tests cover `:members`, `:mods_only`, `:sysop_only`, inactive/deleted/missing/unknown/malformed users. |
| 2 | User can reply only when the board's `postable_by` policy permits their role and the thread is not locked. | VERIFIED | `Foglet.Posts.create_reply/4` loads user/board/thread through `safe_get/2`, enforces `PostingPolicy.can_post?/2`, rejects thread/board mismatch, rejects locked threads unless `PostingPolicy.can_bypass_thread_lock?/2` passes, and only then calls `Boards.Server.create_post/4`. Tests cover reply matrix, lock denial, mod/sysop bypass, board-policy precedence, malformed IDs, and mismatch. |
| 3 | Rejected thread or reply attempts do not allocate board message numbers or persist posts. | VERIFIED | Thread tests assert unchanged thread/post counts, persisted `boards.next_message_number`, and board-server `next_number`. Reply tests assert unchanged post count, thread `post_count`, thread `last_post_at`, user `post_count`, persisted board counter, and board-server `next_number`. |
| 4 | User sees a clear terminal error when submission is rejected by posting policy or locked-thread state. | VERIFIED | `NewThread.format_error/1` and `PostComposer.format_error/1` map `:posting_not_allowed` to `You are not allowed to post on this board.` and `:thread_locked` to `This thread is locked`. TUI tests assert composer state is preserved and success navigation is not taken. Human terminal presentation check remains. |

**Score:** 4/4 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
| -------- | -------- | ------ | ------- |
| `lib/foglet_bbs/posting_policy.ex` | Shared active-poster, board `postable_by`, and locked-thread bypass predicates | VERIFIED | Defines `can_post?/2`, `can_bypass_thread_lock?/2`, and role matrix for `:members`, `:mods_only`, `:sysop_only`. Uses `Authorization.scopes_for(user, :lock_thread)`. |
| `lib/foglet_bbs/threads.ex` | Thread creation preflight before board-server delegation | VERIFIED | `create_thread/3` uses `safe_get/2`, `PostingPolicy.can_post?/2`, and delegates to `Boards.Server.create_thread/3` only on pass. |
| `lib/foglet_bbs/posts.ex` | Reply policy and lock preflight before board-server delegation | VERIFIED | `create_reply/4` checks posting policy, thread/board match, and lock bypass before `Boards.Server.create_post/4`. |
| `lib/foglet_bbs/tui/screens/new_thread.ex` | Structured thread-create error formatting | VERIFIED | Formats `:posting_not_allowed` and `:thread_locked`; failed submission keeps `:new_thread` state. |
| `lib/foglet_bbs/tui/screens/post_composer.ex` | Structured reply-create error formatting | VERIFIED | Preserves structured `{:error, reason}` values, formats policy/lock errors, and keeps success path issuing `{:load_posts, thread.id, jump_last: true}`. |
| Phase 11 tests | Regression coverage for POST-01 through POST-04 | VERIFIED | Targeted Phase 11 test command passed with 113 tests, 0 failures. |

### Key Link Verification

| From | To | Via | Status | Details |
| ---- | -- | --- | ------ | ------- |
| `lib/foglet_bbs/threads.ex` | `lib/foglet_bbs/posting_policy.ex` | `PostingPolicy.can_post?/2` | WIRED | Manual grep found call at `threads.ex:48`; alias imports `Foglet.PostingPolicy`. |
| `lib/foglet_bbs/threads.ex` | `Foglet.Boards.Server.create_thread/3` | Policy pass branch | WIRED | Manual grep found `Boards.Server.create_thread(board_id, user_id, attrs)` at `threads.ex:49`, under the `can_post?` true branch. |
| `lib/foglet_bbs/posts.ex` | `Foglet.Authorization.scopes_for/2` | `PostingPolicy.can_bypass_thread_lock?/2` | WIRED | `PostingPolicy` calls `Authorization.scopes_for(user, :lock_thread)`; `Posts.create_reply/4` calls `can_bypass_thread_lock?/2` only after board policy passes. |
| `lib/foglet_bbs/posts.ex` | `Foglet.Boards.Server.create_post/4` | Policy and lock pass branch | WIRED | Manual grep found `Boards.Server.create_post(board_id, thread_id, user_id, attrs)` at `posts.ex:61`, after all guards. |
| `lib/foglet_bbs/tui/screens/new_thread.ex` | `Foglet.Threads.create_thread/3` | `format_error(:posting_not_allowed)` | WIRED | `do_create_thread/5` calls the domain module and formats `{:error, reason}` into screen-local error copy. |
| `lib/foglet_bbs/tui/screens/post_composer.ex` | `Foglet.Posts.create_reply/4` | `format_error(:thread_locked)` | WIRED | `submit_reply/4` preserves structured error reason and uses `format_error(reason)` for modal copy. |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
| -------- | ------------- | ------ | ------------------ | ------ |
| `Foglet.Threads.create_thread/3` | `user`, `board` | `safe_get(User, user_id)`, `safe_get(Board, board_id)` | Yes - persisted records via `Repo.get/2`; malformed IDs cast to nil | FLOWING |
| `Foglet.Posts.create_reply/4` | `user`, `board`, `thread` | `safe_get/2` for all caller-supplied IDs | Yes - persisted records via `Repo.get/2`; mismatch/missing/malformed rejected | FLOWING |
| `NewThread` error copy | `ss.error` | Domain `{:error, reason}` from `create_thread/3` | Yes - structured reason is formatted and stored in screen state | FLOWING |
| `PostComposer` error copy | `modal.message` | Domain `{:error, reason}` from `create_reply/4` | Yes - structured reason is preserved through `format_error/1` | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| Phase 11 targeted tests | `rtk mix test test/foglet_bbs/threads/threads_test.exs test/foglet_bbs/posts/posts_test.exs test/foglet_bbs/tui/screens/new_thread_test.exs test/foglet_bbs/tui/screens/post_composer_test.exs` | `113 tests, 0 failures` | PASS |
| Artifact verification | `rtk gsd-sdk query verify.artifacts` for plans 11-01, 11-02, 11-03 | All 10 planned artifacts passed existence/substance checks | PASS |
| Key link SDK check | `rtk gsd-sdk query verify.key-links` for plans 11-01, 11-02, 11-03 | SDK reported false negatives because patterns did not match alias/private-clause source text; manual greps verified links | PASS_WITH_NOTES |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
| ----------- | ----------- | ----------- | ------ | -------- |
| POST-01 | 11-01 | User can create a thread only when the board's `postable_by` policy permits their role. | SATISFIED | `Threads.create_thread/3` policy preflight plus POST-01 role matrix and denial tests. |
| POST-02 | 11-02 | User can reply to a thread only when the board's `postable_by` policy permits their role. | SATISFIED | `Posts.create_reply/4` board-policy gate plus POST-02 reply matrix tests. |
| POST-03 | 11-02 | User cannot reply to a locked thread through normal context or TUI posting paths. | SATISFIED | `Posts.create_reply/4` returns `{:error, :thread_locked}` for normal users; bypass is scoped to mod/sysop via `Authorization.scopes_for/2` and remains subordinate to board policy. |
| POST-04 | 11-03 | User sees a clear terminal error when thread or reply submission is rejected by posting policy or thread lock state. | SATISFIED | TUI formatters and tests verify exact policy and lock copy and non-success navigation state; human terminal presentation check remains. |

No orphaned Phase 11 requirements found. REQUIREMENTS.md maps POST-01 through POST-04 to Phase 11, and all four are claimed by plan frontmatter.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| `lib/foglet_bbs/tui/screens/new_thread.ex` | 210 | Placeholder text in input configuration | INFO | Legitimate UI placeholder for composing a post, not a stub. |
| `lib/foglet_bbs/tui/screens/new_thread.ex` | 161-163 | `empty_line_placeholder` option | INFO | Existing render behavior documented by prior plan, not a stub. |
| `lib/foglet_bbs/threads.ex` | 145 | Empty list check | INFO | Normal branch for no users to preload, not hardcoded output. |

### Human Verification Required

#### 1. SSH/TUI Rejection Copy

**Test:** In the terminal UI, attempt a denied new-thread submission, a denied reply submission, and a locked-thread reply as a regular user.
**Expected:** Policy denials show `You are not allowed to post on this board.`, locked-thread denial shows exactly `This thread is locked`, and the user remains in the relevant composer.
**Why human:** Automated tests verify state and copy, but final terminal presentation and interaction flow are user-visible behavior.

### Gaps Summary

No automated verification gaps were found. The phase goal is implemented at the domain boundaries, board-server allocation remains guarded by context preflights, structured errors are presented by TUI screens, and targeted tests pass. Remaining status is `human_needed` for final SSH/TUI presentation confirmation.

---

_Verified: 2026-04-24T20:43:48Z_
_Verifier: Claude (gsd-verifier)_
