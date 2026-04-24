# Phase 11: Posting Policy Enforcement - Specification

**Created:** 2026-04-24
**Ambiguity score:** 0.17 (gate: <= 0.20)
**Requirements:** 5 locked

## Goal

Thread and reply creation are rejected before board-server writes whenever the board `postable_by` policy or the thread `locked` state disallows the current user.

## Background

Foglet already stores board posting policy in `Foglet.Boards.Board.postable_by` with values `:members`, `:mods_only`, and `:sysop_only`, and stores thread lock state in `Foglet.Threads.Thread.locked`. The Sysop board-management surface can edit `postable_by`, and thread moderation can lock or unlock threads. However, `Foglet.Threads.create_thread/3` currently delegates directly to `Foglet.Boards.Server.create_thread/3`, and `Foglet.Posts.create_reply/4` delegates directly to `Foglet.Boards.Server.create_post/4`.

The board server is the single writer for message-number allocation and increments `boards.next_message_number` inside the same transaction that inserts the post. Because posting policy and locked-thread checks do not currently happen before this call path, a forbidden create can reach the allocator. The terminal UI has submission paths in `Foglet.TUI.Screens.NewThread` and `Foglet.TUI.Screens.PostComposer`; they can surface errors, but reply failures currently collapse to generic "Failed to create post." copy.

## Requirements

1. **Thread policy gate**: A user can create a thread only when the target board's `postable_by` policy permits that user's role.
   - Current: `Foglet.Threads.create_thread/3` accepts `board_id`, `user_id`, and attrs, then immediately calls `Foglet.Boards.Server.create_thread/3` without checking `postable_by`.
   - Target: Thread creation checks the persisted board policy and the posting user's role before calling the board server; `:members` permits active users, mods, and sysops, `:mods_only` permits mods and sysops, and `:sysop_only` permits sysops only.
   - Acceptance: Focused context tests prove allowed roles can create threads for each policy, disallowed roles receive a structured error, no thread/post rows are persisted for disallowed attempts, and `boards.next_message_number` is unchanged after rejection.

2. **Reply policy gate**: A user can reply only when the target board's `postable_by` policy permits that user's role.
   - Current: `Foglet.Posts.create_reply/4` accepts `thread_id`, `board_id`, `user_id`, and attrs, then immediately calls `Foglet.Boards.Server.create_post/4` without checking `postable_by`.
   - Target: Reply creation checks the persisted board policy and posting user's role before calling the board server.
   - Acceptance: Focused context tests prove allowed roles can reply for each policy, disallowed roles receive a structured error, no reply row is persisted for disallowed attempts, the parent thread counters are unchanged, the posting user's `post_count` is unchanged, and `boards.next_message_number` is unchanged after rejection.

3. **Locked-thread reply gate**: A locked thread rejects normal reply creation regardless of board posting policy.
   - Current: `Foglet.Threads.lock_thread/1` can set `locked: true`, but `Foglet.Posts.create_reply/4` does not inspect the thread lock before creating a reply.
   - Target: Reply creation rejects locked threads before the board server is called; unlocked threads continue to follow the board posting policy.
   - Acceptance: Context tests prove locked-thread replies fail for users, mods, and sysops through the normal reply API, no reply row is persisted, no message number is allocated, and unlocking the thread restores normal policy-based reply behavior.

4. **Rejected writes are side-effect free**: Policy and lock rejections happen before message-number allocation and before durable posting side effects.
   - Current: Board-server transactions increment `boards.next_message_number` before inserting a post; validation failures inside the transaction roll back, but policy failures are not guaranteed to be preflighted.
   - Target: All forbidden thread and reply attempts return before `Foglet.Boards.Server.create_thread/3` or `Foglet.Boards.Server.create_post/4` is invoked.
   - Acceptance: Tests with existing and empty boards prove rejected attempts do not change `boards.next_message_number`, do not advance the board server's in-memory next number, do not create posts or threads, and do not update thread/user counters.

5. **Terminal rejection copy**: Terminal users receive clear posting-policy or locked-thread errors when thread or reply submission is rejected.
   - Current: New-thread submission renders the returned error through existing formatting, but reply submission renders all errors as "Failed to create post."
   - Target: New-thread and reply submission paths show a clear terminal error that distinguishes board posting policy rejection from locked-thread rejection.
   - Acceptance: TUI tests prove rejected new-thread and reply submissions keep the user in the composing flow or show an error modal without navigating as if the post succeeded, and the visible copy identifies either insufficient posting permission or locked-thread state.

## Boundaries

**In scope:**
- Enforce `boards.postable_by` for normal thread creation.
- Enforce `boards.postable_by` for normal reply creation.
- Enforce `threads.locked` for normal reply creation.
- Ensure denied thread and reply attempts do not allocate board message numbers or persist posting side effects.
- Return structured domain errors suitable for TUI presentation.
- Show clear terminal error copy for posting-policy and locked-thread rejections.
- Add focused context, board-server invariant, and TUI tests for POST-01 through POST-04.

**Out of scope:**
- Changing the existing `postable_by` enum values - the data model already defines the v1 policy set.
- Adding per-board moderator membership semantics beyond user roles - this phase uses role-based `:user`, `:mod`, and `:sysop` behavior already present in the application.
- Browser posting workflows or browser admin - Foglet remains SSH-first/TUI-first for this milestone.
- Moderation case management, audit timelines, sanctions, appeals, or broader thread-management UI - this phase is only about create/reply enforcement.
- Editing or deleting existing posts - POST-01 through POST-04 cover thread/reply creation only.
- Subscription or readable-by enforcement - board subscription management and access assumptions are separate milestone work.
- Rate limits, spam prevention, content moderation filters, or max-post-length changes - those are adjacent posting rules, not this phase's policy gap.

## Constraints

- Thread and reply creation must continue to route successful writes through `Foglet.Boards.Server`; direct Repo insertion must not bypass the board-server message-number invariant.
- Rejection checks must run before the board server allocates or persists a message number.
- Domain behavior belongs in `Foglet.*` contexts, not TUI render functions or SSH callbacks.
- Actor-triggered side effects must keep using context boundaries; UI hiding or disabling cannot be treated as authorization.
- Existing `Foglet.Boards.scope_for/1`, `Foglet.Threads.scope_for/1`, and `Foglet.Posts.scope_for/1` scope-shape conventions must remain intact.
- Tests must avoid `Process.sleep/1`; use persisted state, explicit calls, or board-server state synchronization where needed.
- Terminal copy must stay SSH/TUI native and must not introduce browser workflows.

## Acceptance Criteria

- [ ] A regular active user can create a thread on a `:members` board.
- [ ] A regular active user cannot create a thread on `:mods_only` or `:sysop_only` boards.
- [ ] A mod can create a thread on `:members` and `:mods_only` boards, but not `:sysop_only` boards.
- [ ] A sysop can create a thread on all three posting policies.
- [ ] Reply creation follows the same role-policy matrix as thread creation.
- [ ] Locked-thread replies fail through the normal context reply API.
- [ ] Rejected thread attempts persist no thread or post rows.
- [ ] Rejected reply attempts persist no reply row and do not change thread counters.
- [ ] Rejected thread and reply attempts do not change `boards.next_message_number`.
- [ ] Rejected reply attempts do not change the posting user's `post_count`.
- [ ] TUI new-thread rejection copy clearly identifies posting-policy denial.
- [ ] TUI reply rejection copy clearly identifies posting-policy denial or locked-thread state.
- [ ] Successful allowed submissions still route through `Foglet.Boards.Server` and keep per-board message numbers monotonic.

## Ambiguity Report

| Dimension           | Score | Min   | Status | Notes |
|---------------------|-------|-------|--------|-------|
| Goal Clarity        | 0.90  | 0.75  | met    | The outcome is explicit: deny disallowed thread/reply attempts before board-server writes. |
| Boundary Clarity    | 0.82  | 0.70  | met    | Policy enforcement, locked-thread replies, side-effect-free rejection, and excluded adjacent posting concerns are listed. |
| Constraint Clarity  | 0.76  | 0.65  | met    | Board-server allocation, context boundaries, SSH-first UI, and test constraints are locked. |
| Acceptance Criteria | 0.84  | 0.70  | met    | Criteria cover the role-policy matrix, lock behavior, side-effect invariants, TUI copy, and success-path preservation. |
| **Ambiguity**       | 0.17  | <=0.20| met    | Weighted clarity is 0.83. |

Status: met = dimension meets minimum, below = planner treats as assumption.

## Interview Log

| Round | Perspective | Question summary | Decision locked |
|-------|-------------|------------------|-----------------|
| 1 | Researcher | What exists today for posting policy and thread locks? | Board `postable_by` and thread `locked` state exist, but create paths delegate directly to the board server. |
| 1 | Researcher | What is the primary gap? | Denied submissions must be rejected before board-server allocation and persistence side effects. |
| 1 | Researcher + Simplifier | What is the smallest policy matrix? | Use existing roles only: members allow user/mod/sysop, mods_only allows mod/sysop, sysop_only allows sysop. |
| 1 | Boundary Keeper | What adjacent posting features are excluded? | No new enum values, board-moderator membership model, subscription enforcement, browser workflows, moderation case management, edit/delete rules, rate limits, or content filters. |
| 1 | Failure Analyst | What would make verification reject the work? | Any denied attempt that allocates a message number, persists a row, mutates counters, or shows generic terminal copy fails the spec. |

---

*Phase: 11-posting-policy-enforcement*
*Spec created: 2026-04-24*
*Next step: $gsd-discuss-phase 11 - implementation decisions (how to build what is specified above)*
