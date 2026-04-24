# Phase 11: posting-policy-enforcement - Context

**Gathered:** 2026-04-24 (assumptions mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Thread and reply creation must reject disallowed submissions before board-server writes whenever the board `postable_by` policy or thread `locked` state blocks the current user. Successful submissions must still route through `Foglet.Boards.Server` so per-board message-number allocation remains authoritative. This phase covers POST-01 through POST-04: board posting policy for new threads, board posting policy for replies, locked-thread reply prevention with scoped moderator/sysop bypass, side-effect-free rejection, and clear SSH/TUI rejection copy. It does not add new posting-policy enum values, a board-moderator membership model, browser workflows, subscription/readable-by enforcement, edit/delete rules, spam controls, or broader moderation case management.
</domain>

<decisions>
## Implementation Decisions

### Context Gate Placement
- **D-01:** Put posting-policy checks in `Foglet.Threads.create_thread/3` and `Foglet.Posts.create_reply/4`, before successful writes delegate to `Foglet.Boards.Server`.
- **D-02:** Put locked-thread reply checks in `Foglet.Posts.create_reply/4`, before calling `Foglet.Boards.Server.create_post/4`.
- **D-03:** Preserve `Foglet.Boards.Server` as the only path for successful thread/root-post and reply persistence so message-number allocation, thread counters, and user post counts stay centralized.

### Actor And Policy Source
- **D-04:** Keep the current user-id-based public create APIs for this phase: `Foglet.Threads.create_thread(board_id, user_id, attrs)` and `Foglet.Posts.create_reply(thread_id, board_id, user_id, attrs)`.
- **D-05:** Load the persisted user, board, and thread records inside the owning contexts to evaluate active account status, role, `boards.postable_by`, and `threads.locked`.
- **D-06:** Treat only active, non-deleted users as posters. Pending, suspended, deleted, missing, or unknown users fail before board-server writes.
- **D-07:** Enforce the locked policy matrix from the SPEC: `:members` allows active users, mods, and sysops; `:mods_only` allows active mods and sysops; `:sysop_only` allows active sysops only.

### Locked Thread Bypass
- **D-08:** Locked-thread bypass uses the existing authorization scope model: sysops bypass directly, and moderators bypass when their scopes include `:site` or matching `{:board, board_id}`.
- **D-09:** Use the existing stable scope-shape conventions and helpers where relevant; do not introduce a new board-moderator data model in this phase.
- **D-10:** Unlocked threads still follow the board posting-policy matrix; lock bypass only affects the locked-thread gate, not `postable_by`.

### Structured Errors And TUI Copy
- **D-11:** Contexts should return structured domain errors for posting-policy denial and locked-thread denial so callers do not parse text.
- **D-12:** Locked-thread denial copy in terminal flows must render exactly `This thread is locked`.
- **D-13:** New-thread submission should keep the user in the composing flow and show posting-policy denial through the existing visible error path.
- **D-14:** Reply submission must stop collapsing all create failures to `Failed to create post.` and instead render clear policy/locked-thread errors without navigating as if the reply succeeded.

### the agent's Discretion
- Exact internal helper names and return tuple shapes, provided they are structured, testable, and distinguish posting-policy denial from locked-thread denial.
- Exact posting-policy denial wording, provided it is clear terminal copy and distinct from locked-thread denial.
- Exact query shape for loading board/thread/user records, provided rejection happens before board-server calls and tests prove no side effects.
- Exact test organization between context, board-server invariant, and TUI screen tests, provided POST-01 through POST-04 acceptance criteria are covered.

### Folded Todos
None.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Locked Phase Requirements
- `.planning/phases/11-posting-policy-enforcement/11-SPEC.md` - Locked requirements, boundaries, constraints, acceptance criteria, and policy/lock behavior for POST-01 through POST-04.
- `.planning/ROADMAP.md` - Phase 11 roadmap goal, dependency on Phase 10, success criteria, and milestone boundary.
- `.planning/REQUIREMENTS.md` - POST-01 through POST-04 traceability.
- `.planning/PROJECT.md` - SSH-first product direction, v1.2 pre-alpha gap closure goal, and domain/context boundary constraints.
- `.planning/STATE.md` - Current milestone position and recent decisions affecting Phase 11.

### Prior Phase Decisions
- `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-CONTEXT.md` - Prior pattern for centralizing user-visible behavior in domain contexts and keeping TUI copy honest.
- `.planning/phases/10-user-status-administration/10-CONTEXT.md` - Prior pattern for actor-aware context APIs, structured results, and terminal/break-glass callers consuming context decisions.

### Codebase Maps And Domain Docs
- `docs/DATA_MODEL.md` - Board `postable_by`, thread `locked`, post/thread persistence, and message-number invariants.
- `.planning/codebase/ARCHITECTURE.md` - SSH/TUI/domain layering, context boundaries, PubSub, and board-server coordination.
- `.planning/codebase/CONVENTIONS.md` - Context API, changeset, authorization, module, docs, and precommit conventions.
- `.planning/codebase/TESTING.md` - ExUnit organization, board-server sandbox patterns, TUI screen tests, and process-test constraints.
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Foglet.Threads.create_thread/3` is already the public context boundary for thread creation and currently delegates directly to `Foglet.Boards.Server.create_thread/3`.
- `Foglet.Posts.create_reply/4` is already the public context boundary for reply creation and currently delegates directly to `Foglet.Boards.Server.create_post/4`.
- `Foglet.Boards.Server` owns per-board message-number allocation, thread/root-post insertion, reply insertion, thread counter bumps, and user `post_count` bumps.
- `Foglet.Boards.Board` already defines `postable_by` as `:members`, `:mods_only`, or `:sysop_only`.
- `Foglet.Threads.Thread` already defines `locked` and lock changesets.
- `Foglet.Authorization.scopes_for/2` already returns stable `:site` and `{:board, board_id}`-compatible scope shapes; current active mods and sysops are site-scoped.
- `Foglet.TUI.Screens.NewThread` already formats context errors into visible compose-state error text.
- `Foglet.TUI.Screens.PostComposer` already handles reply submission but currently maps all reply failures to a generic error modal.

### Established Patterns
- Domain mutations live in `Foglet.*` contexts; TUI screens render, dispatch, and present context results.
- UI hiding or disabled actions are advisory only; context mutations are the real enforcement boundary.
- Successful posting writes route through the board server; direct Repo insertion would violate the message-number invariant.
- Tests that interact with board servers use supervised board processes and SQL sandbox allowance rather than sleeps.
- TUI screen tests use fake domain modules to assert terminal copy and navigation behavior without full SSH sessions.

### Integration Points
- Add policy/active-user preflight helpers in `Foglet.Threads` and `Foglet.Posts` or a tightly scoped shared domain helper if duplication becomes meaningful.
- Update `Foglet.Posts.create_reply/4` to load/check thread lock and board policy before calling the board server.
- Update `Foglet.Threads.create_thread/3` to load/check board policy and active user before calling the board server.
- Update `Foglet.TUI.Screens.NewThread` and tests for posting-policy denial copy.
- Update `Foglet.TUI.Screens.PostComposer` and tests for locked-thread and posting-policy denial copy.
- Add focused context and invariant tests under `test/foglet_bbs/threads`, `test/foglet_bbs/posts`, and possibly `test/foglet_bbs/boards` to prove no rows, counters, or message numbers change on rejection.
</code_context>

<specifics>
## Specific Ideas

No external product reference was provided. The accepted direction is conservative and codebase-native: enforce at context boundaries, keep successful writes routed through the board server, use existing authorization scope shapes for moderator lock bypass, and make terminal rejection copy clear.
</specifics>

<deferred>
## Deferred Ideas

- New `postable_by` enum values or richer board posting policies.
- Board-moderator membership data model.
- Browser posting or browser administration workflows.
- Subscription/readable-by enforcement for posting.
- Editing, deleting, rate limits, spam prevention, content filters, or max-post-length changes.
- Moderation case management, audit timelines, sanctions, appeals, or broader thread-management UI.

### Reviewed Todos (not folded)
None.
</deferred>

---

*Phase: 11-posting-policy-enforcement*
*Context gathered: 2026-04-24*
