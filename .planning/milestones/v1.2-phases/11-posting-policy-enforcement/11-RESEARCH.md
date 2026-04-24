# Phase 11: Posting Policy Enforcement - Research

**Researched:** 2026-04-24  
**Domain:** Elixir/Phoenix domain-policy enforcement for SSH/TUI posting flows  
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
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

### Claude's Discretion
- Exact internal helper names and return tuple shapes, provided they are structured, testable, and distinguish posting-policy denial from locked-thread denial.
- Exact posting-policy denial wording, provided it is clear terminal copy and distinct from locked-thread denial.
- Exact query shape for loading board/thread/user records, provided rejection happens before board-server calls and tests prove no side effects.
- Exact test organization between context, board-server invariant, and TUI screen tests, provided POST-01 through POST-04 acceptance criteria are covered.

### Deferred Ideas (OUT OF SCOPE)
- New `postable_by` enum values or richer board posting policies.
- Board-moderator membership data model.
- Browser posting or browser administration workflows.
- Subscription/readable-by enforcement for posting.
- Editing, deleting, rate limits, spam prevention, content filters, or max-post-length changes.
- Moderation case management, audit timelines, sanctions, appeals, or broader thread-management UI.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| POST-01 | User can create a thread only when the board's `postable_by` policy permits their role. | Enforce a preflight gate in `Foglet.Threads.create_thread/3` before `Foglet.Boards.Server.create_thread/3`. [VERIFIED: `.planning/phases/11-posting-policy-enforcement/11-CONTEXT.md`, `lib/foglet_bbs/threads.ex`] |
| POST-02 | User can reply to a thread only when the board's `postable_by` policy permits their role. | Enforce the same role-policy matrix in `Foglet.Posts.create_reply/4` before `Foglet.Boards.Server.create_post/4`. [VERIFIED: `.planning/phases/11-posting-policy-enforcement/11-CONTEXT.md`, `lib/foglet_bbs/posts.ex`] |
| POST-03 | User cannot reply to a locked thread through normal context or TUI posting paths. | Add a locked-thread gate in `Foglet.Posts.create_reply/4`, with sysop/moderator-scope bypass only. [VERIFIED: `.planning/phases/11-posting-policy-enforcement/11-SPEC.md`, `lib/foglet_bbs/authorization.ex`] |
| POST-04 | User sees a clear terminal error when thread or reply submission is rejected by posting policy or thread lock state. | Map structured context errors to terminal copy in `NewThread` and `PostComposer`; locked copy must be exactly `This thread is locked`. [VERIFIED: `.planning/phases/11-posting-policy-enforcement/11-CONTEXT.md`, `lib/foglet_bbs/tui/screens/new_thread.ex`, `lib/foglet_bbs/tui/screens/post_composer.ex`] |
</phase_requirements>

## Summary

Phase 11 should be implemented as domain-context preflight enforcement, not as a new library, schema migration, browser workflow, or TUI-only guard. [VERIFIED: `11-CONTEXT.md`, `CLAUDE.md`] The established architecture is: TUI submits through context APIs, contexts load persisted user/board/thread records, contexts reject before any board-server call, and successful writes continue through `Foglet.Boards.Server` so per-board message numbers remain centralized. [VERIFIED: `CLAUDE.md`, `.planning/codebase/ARCHITECTURE.md`, `lib/foglet_bbs/boards/server.ex`]

The primary hidden risk is side effects from calling the board server too early. [VERIFIED: `lib/foglet_bbs/boards/server.ex`] `Boards.Server` increments `boards.next_message_number`, inserts posts, updates thread counters, and increments user `post_count` inside an `Ecto.Multi`; validation failures roll back, but policy denials should never enter that allocation path. [VERIFIED: `lib/foglet_bbs/boards/server.ex`, `.planning/phases/11-posting-policy-enforcement/11-SPEC.md`]

**Primary recommendation:** Add small, shared policy helpers in Foglet domain code, call them from `Threads.create_thread/3` and `Posts.create_reply/4` before board-server delegation, return structured atoms such as `{:error, :posting_not_allowed}` and `{:error, :thread_locked}`, and update TUI formatting/tests around those exact errors. [VERIFIED: `11-CONTEXT.md`, `lib/foglet_bbs/tui/screens/new_thread.ex`, `lib/foglet_bbs/tui/screens/post_composer.ex`]

## Project Constraints (from CLAUDE.md)

- Foglet is SSH-first; do not add end-user browser workflows. [VERIFIED: `CLAUDE.md`]
- Keep domain workflows in `Foglet.*` contexts, not controllers, SSH callbacks, or TUI render functions. [VERIFIED: `CLAUDE.md`]
- Postgres is authoritative for durable state; ETS and processes are reconstructable. [VERIFIED: `CLAUDE.md`]
- Thread and post creation must route through `Foglet.Boards.Server`; the board server is the single writer for message-number allocation. [VERIFIED: `CLAUDE.md`]
- Use `Foglet.Boards.scope_for/1`, `Foglet.Threads.scope_for/1`, and `Foglet.Posts.scope_for/1` for stable authorization scope shapes. [VERIFIED: `CLAUDE.md`, `lib/foglet_bbs/threads.ex`, `lib/foglet_bbs/posts.ex`]
- Use `Bodyguard.permit/4` before domain side effects for authorization; `permit?/4` is only advisory UI rendering. [VERIFIED: `CLAUDE.md`, `lib/foglet_bbs/authorization.ex`]
- For TUI flows, global navigation belongs in `Foglet.TUI.App`, screen-local behavior belongs in screens, data/mutations belong in contexts, and reusable display belongs in widgets. [VERIFIED: `CLAUDE.md`]
- Tests should use `start_supervised!/1` for processes and avoid `Process.sleep/1`; synchronize with monitors, explicit messages, or `:sys.get_state/1`. [VERIFIED: `CLAUDE.md`, `.planning/codebase/TESTING.md`]
- Run `rtk mix precommit` when implementation is complete. [VERIFIED: `CLAUDE.md`]

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|--------------|----------------|-----------|
| Board posting policy decision | API / Backend domain context | Database / Storage | `postable_by` is persisted on `boards`, and context APIs are the trust boundary. [VERIFIED: `docs/DATA_MODEL.md`, `CLAUDE.md`] |
| Active poster eligibility | API / Backend domain context | Database / Storage | User `role`, `status`, and `deleted_at` must be loaded from Postgres before posting side effects. [VERIFIED: `lib/foglet_bbs/accounts/user.ex`, `11-CONTEXT.md`] |
| Locked-thread reply decision | API / Backend domain context | Database / Storage | Thread lock state is persisted on `threads`, and reply creation is the mutation boundary. [VERIFIED: `docs/DATA_MODEL.md`, `lib/foglet_bbs/posts.ex`] |
| Moderator/sysop lock bypass | API / Backend authorization/domain | Database / Storage | Existing `Foglet.Authorization.scopes_for/2` returns `:site` for active mods/sysops and `[]` for inactive actors. [VERIFIED: `lib/foglet_bbs/authorization.ex`] |
| Message-number allocation | Board Server Layer | Database / Storage | `Foglet.Boards.Server` serializes allocation and persists `next_message_number` during successful writes. [VERIFIED: `lib/foglet_bbs/boards/server.ex`, `.planning/codebase/ARCHITECTURE.md`] |
| Terminal rejection copy | TUI Layer | API / Backend domain errors | TUI screens should format structured context errors; they must not own authorization. [VERIFIED: `CLAUDE.md`, `lib/foglet_bbs/tui/screens/new_thread.ex`, `lib/foglet_bbs/tui/screens/post_composer.ex`] |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Elixir / OTP | Elixir 1.19.5, OTP 28 | Runtime, contexts, GenServers, ExUnit. | Installed project runtime. [VERIFIED: `elixir --version`] |
| Phoenix | 1.8.5 | Application infrastructure, PubSub, LiveDashboard. | Already locked; not an end-user posting surface. [VERIFIED: `mix.lock`, `CLAUDE.md`] |
| Ecto / Ecto SQL | 3.13.5 | Schemas, queries, transactions, `Ecto.Multi`, sandbox tests. | Existing persistence stack; Hex metadata confirms locked version. [VERIFIED: `mix.lock`, `rtk mix hex.info ecto_sql`, `deps/ecto/lib/ecto.ex`] |
| Postgrex / Postgres | Postgrex 0.21.1, local psql 14.20 | Durable Postgres access. | Existing authoritative datastore. [VERIFIED: `mix.lock`, `psql --version`, `CLAUDE.md`] |
| Bodyguard | 2.4.3 | Existing authorization policy behavior and scope helpers. | Existing policy library; Hex metadata confirms locked version. [VERIFIED: `mix.lock`, `rtk mix hex.info bodyguard`, `lib/foglet_bbs/authorization.ex`] |
| Raxol | vendored + locked deps | Terminal UI lifecycle and widgets. | Existing SSH/TUI rendering stack; no browser UI needed. [VERIFIED: `vendor/raxol`, `mix.lock`, `CLAUDE.md`] |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| ExUnit | bundled with Elixir 1.19.5 | Context, TUI, and board-server invariant tests. | Use for all POST-01 through POST-04 tests. [VERIFIED: `mix --version`, `.planning/codebase/TESTING.md`] |
| Ecto SQL Sandbox | Ecto SQL 3.13.5 | DB isolation and Board Server DB access in tests. | Use `Sandbox.allow/3` when tests drive a board server process. [VERIFIED: `test/support/data_case.ex`, `test/foglet_bbs/posts/posts_test.exs`] |
| StreamData | 1.3.0 | Existing property test dependency. | No new property tests required unless expanding board-server invariants. [VERIFIED: `mix.lock`, `.planning/codebase/TESTING.md`] |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Context preflight helpers | Bodyguard action expansion for `:create_thread` / `:create_reply` | Not recommended for this phase because decisions lock current user-id APIs and require loading board/thread/user inside contexts; Bodyguard can still support scope checks for locked bypass. [VERIFIED: `11-CONTEXT.md`, `lib/foglet_bbs/authorization.ex`] |
| Structured atom errors | Text errors from contexts | Not recommended because D-11 says callers must not parse text. [VERIFIED: `11-CONTEXT.md`] |
| Board-server enforcement | Reject inside `Foglet.Boards.Server` | Not recommended as the primary gate because D-01/D-02 require rejection before successful writes delegate to board server. [VERIFIED: `11-CONTEXT.md`] |

**Installation:**
```bash
# No new packages. Use existing locked deps.
rtk mix deps.get
```

**Version verification:** `rtk mix hex.info ecto_sql` verified locked Ecto SQL 3.13.5, and `rtk mix hex.info bodyguard` verified locked Bodyguard 2.4.3. [VERIFIED: Hex metadata commands]

## Architecture Patterns

### System Architecture Diagram

```text
SSH terminal input
  -> TUI screen submit (NewThread / PostComposer)
  -> Foglet.Threads.create_thread/3 or Foglet.Posts.create_reply/4
  -> load persisted User + Board (+ Thread for replies)
  -> active-user gate
       denied -> {:error, :posting_not_allowed} -> TUI visible error
       allowed -> board postable_by role-policy gate
            denied -> {:error, :posting_not_allowed} -> TUI visible error
            allowed -> reply only: locked-thread gate
                 locked + no bypass -> {:error, :thread_locked} -> "This thread is locked"
                 unlocked or bypass -> Foglet.Boards.Server.create_thread/create_post
                      -> Ecto.Multi allocates message number and persists counters
                      -> {:ok, post/thread} -> TUI navigates/reloads
```

This flow keeps rejection before board-server allocation and keeps successful persistence centralized in `Foglet.Boards.Server`. [VERIFIED: `11-SPEC.md`, `lib/foglet_bbs/boards/server.ex`]

### Recommended Project Structure

```text
lib/foglet_bbs/
├── posting_policy.ex        # optional small shared helper for role/lock predicates
├── threads.ex               # create_thread/3 preflight, then board server delegation
├── posts.ex                 # create_reply/4 preflight, then board server delegation
└── tui/screens/
    ├── new_thread.ex        # format structured thread-create errors
    └── post_composer.ex     # format structured reply-create errors

test/foglet_bbs/
├── threads/threads_test.exs # POST-01 thread policy and no-side-effect tests
├── posts/posts_test.exs     # POST-02/03 reply policy, lock, counters
└── tui/screens/
    ├── new_thread_test.exs
    └── post_composer_test.exs
```

Use a shared helper only if it avoids duplicated role-policy logic between `Threads` and `Posts`; keep the public mutation APIs in the existing contexts. [VERIFIED: `11-CONTEXT.md`, `lib/foglet_bbs/threads.ex`, `lib/foglet_bbs/posts.ex`]

### Pattern 1: Context Preflight Before Side Effects

**What:** Load persisted user/board/thread data, return structured errors for denials, and call `Foglet.Boards.Server` only after all gates pass. [VERIFIED: `11-CONTEXT.md`]  
**When to use:** `Threads.create_thread/3` and `Posts.create_reply/4`. [VERIFIED: `lib/foglet_bbs/threads.ex`, `lib/foglet_bbs/posts.ex`]

```elixir
# Source: local pattern from lib/foglet_bbs/threads.ex and lib/foglet_bbs/posts.ex
def create_thread(board_id, user_id, attrs) do
  with {:ok, user, board} <- load_posting_context(board_id, user_id),
       :ok <- ensure_can_post(user, board) do
    Foglet.Boards.Server.create_thread(board_id, user_id, attrs)
  end
end
```

### Pattern 2: Scope-Based Locked-Thread Bypass

**What:** Treat `:site` or `{:board, board_id}` from `Foglet.Authorization.scopes_for/2` as sufficient for locked-thread reply bypass. [VERIFIED: `11-CONTEXT.md`, `lib/foglet_bbs/authorization.ex`]  
**When to use:** Only for the `thread.locked` reply gate; do not let lock bypass override `board.postable_by`. [VERIFIED: `11-CONTEXT.md`]

```elixir
# Source: local scope shape in lib/foglet_bbs/authorization.ex
defp can_bypass_thread_lock?(user, board_id) do
  scopes = Foglet.Authorization.scopes_for(user, :lock_thread)
  :site in scopes or {:board, board_id} in scopes
end
```

### Pattern 3: TUI Error Formatting From Structured Domain Errors

**What:** Convert structured context errors to terminal copy at the UI boundary. [VERIFIED: `11-CONTEXT.md`, `lib/foglet_bbs/tui/screens/new_thread.ex`]  
**When to use:** `NewThread` and `PostComposer` submission failure branches. [VERIFIED: `lib/foglet_bbs/tui/screens/new_thread.ex`, `lib/foglet_bbs/tui/screens/post_composer.ex`]

```elixir
# Source: local TUI error formatting pattern in NewThread.format_error/1
defp format_error(:thread_locked), do: "This thread is locked"
defp format_error(:posting_not_allowed), do: "You are not allowed to post on this board."
defp format_error(%Ecto.Changeset{} = cs), do: changeset_message(cs)
defp format_error(reason) when is_binary(reason), do: reason
defp format_error(reason), do: inspect(reason)
```

### Anti-Patterns to Avoid

- **TUI-only enforcement:** Hidden or disabled UI is advisory only; contexts must reject. [VERIFIED: `CLAUDE.md`]
- **Calling `Boards.Server` before policy gates:** Any denied attempt that enters the board server risks allocator/counter behavior outside the intended trust boundary. [VERIFIED: `11-SPEC.md`, `lib/foglet_bbs/boards/server.ex`]
- **Direct Repo inserts for successful posts:** Direct insert bypasses per-board message number serialization. [VERIFIED: `CLAUDE.md`, `lib/foglet_bbs/boards/server.ex`]
- **Text parsing in callers:** D-11 requires structured domain errors. [VERIFIED: `11-CONTEXT.md`]
- **New moderator membership model:** D-09 explicitly excludes it for this phase. [VERIFIED: `11-CONTEXT.md`]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Message-number allocation | Custom counters in contexts or TUI | `Foglet.Boards.Server` | Existing single-writer GenServer owns sequence and transaction behavior. [VERIFIED: `lib/foglet_bbs/boards/server.ex`] |
| Durable atomic posting writes | Manual multi-step writes without transaction | Existing board-server `Ecto.Multi` | It already coordinates board counter, post/thread insert, thread counters, and user count. [VERIFIED: `lib/foglet_bbs/boards/server.ex`] |
| Authorization scope derivation | Duplicated role/scope logic in screens | `Foglet.Authorization.scopes_for/2` | Existing helper encodes active/deleted/pending/suspended handling and scope shapes. [VERIFIED: `lib/foglet_bbs/authorization.ex`] |
| Changeset validation | Ad hoc body/title validation in contexts | Existing schema changesets in `Thread` and `Post` | Changesets already own data-shape validation. [VERIFIED: `CLAUDE.md`, `lib/foglet_bbs/boards/server.ex`] |
| TUI domain access | SSH callback or render-function writes | Existing context APIs via screens/App commands | Project boundary says domain workflows stay in contexts. [VERIFIED: `CLAUDE.md`] |

**Key insight:** The phase is not about inventing posting infrastructure; it is about moving policy rejection to the correct pre-side-effect boundary while preserving the existing allocator and transaction design. [VERIFIED: `11-SPEC.md`, `.planning/codebase/ARCHITECTURE.md`]

## Common Pitfalls

### Pitfall 1: Denial Happens After Allocation
**What goes wrong:** Policy-denied submissions still call `Boards.Server`, which can enter the `Ecto.Multi` allocation path. [VERIFIED: `lib/foglet_bbs/boards/server.ex`]  
**Why it happens:** Existing `create_thread/3` and `create_reply/4` delegate directly to the board server. [VERIFIED: `lib/foglet_bbs/threads.ex`, `lib/foglet_bbs/posts.ex`]  
**How to avoid:** Load and check user/board/thread before delegation. [VERIFIED: `11-CONTEXT.md`]  
**Warning signs:** Tests assert only returned errors, not unchanged `boards.next_message_number`, post rows, thread counters, and user `post_count`. [VERIFIED: `11-SPEC.md`]

### Pitfall 2: Lock Bypass Accidentally Bypasses Board Policy
**What goes wrong:** A moderator/sysop can reply to a locked thread even when `postable_by` should deny them. [VERIFIED: `11-CONTEXT.md`]  
**Why it happens:** Lock bypass and board posting policy are separate gates. [VERIFIED: `11-CONTEXT.md`]  
**How to avoid:** Always run `postable_by` policy first or independently; lock bypass only resolves `thread.locked`. [VERIFIED: `11-CONTEXT.md`]  
**Warning signs:** Tests cover locked threads but not `:sysop_only` / `:mods_only` policy interactions. [VERIFIED: `11-SPEC.md`]

### Pitfall 3: Inactive Users Treated Like Members
**What goes wrong:** Pending, suspended, deleted, missing, or unknown users can post on `:members` boards. [VERIFIED: `11-CONTEXT.md`]  
**Why it happens:** The public APIs receive `user_id`, not a loaded actor struct. [VERIFIED: `11-CONTEXT.md`, `lib/foglet_bbs/threads.ex`]  
**How to avoid:** Load the user and require `status == :active` and `deleted_at == nil`. [VERIFIED: `lib/foglet_bbs/accounts/user.ex`, `11-CONTEXT.md`]  
**Warning signs:** Tests only create default active users via fixtures. [VERIFIED: `test/support/boards_fixtures.ex`]

### Pitfall 4: Generic Reply Error Copy
**What goes wrong:** `PostComposer` maps all create failures to `Failed to create post.` [VERIFIED: `lib/foglet_bbs/tui/screens/post_composer.ex`]  
**Why it happens:** Existing failure branch discards the reason. [VERIFIED: `lib/foglet_bbs/tui/screens/post_composer.ex`]  
**How to avoid:** Preserve structured reason and map `:thread_locked` to exactly `This thread is locked`. [VERIFIED: `11-CONTEXT.md`]  
**Warning signs:** Existing test asserts the old generic copy and must be updated. [VERIFIED: `test/foglet_bbs/tui/screens/post_composer_test.exs`]

### Pitfall 5: Board Server Sandbox Access Missing in Tests
**What goes wrong:** Tests that drive real board servers fail due to SQL sandbox ownership. [VERIFIED: `.planning/codebase/TESTING.md`, `test/foglet_bbs/posts/posts_test.exs`]  
**Why it happens:** Board server is a separate process from the test process. [VERIFIED: `test/foglet_bbs/posts/posts_test.exs`]  
**How to avoid:** Lookup the board server pid in `Foglet.BoardRegistry` and call `Sandbox.allow(Repo, self(), pid)`. [VERIFIED: `test/foglet_bbs/posts/posts_test.exs`]  
**Warning signs:** Context tests use real posting APIs but omit `allow_board_server!`. [VERIFIED: `test/foglet_bbs/threads/threads_test.exs`]

## Code Examples

Verified patterns from local sources:

### Existing Board Server Delegation Point

```elixir
# Source: lib/foglet_bbs/posts.ex
def create_reply(thread_id, board_id, user_id, attrs) do
  Foglet.Boards.Server.create_post(board_id, thread_id, user_id, attrs)
end
```

Use this as the call that happens only after preflight gates pass. [VERIFIED: `lib/foglet_bbs/posts.ex`]

### Existing Transactional Insert Shape

```elixir
# Source: lib/foglet_bbs/boards/server.ex
Multi.new()
|> Multi.run(:bump_board_counter, fn repo, _ ->
  {1, _} = repo.update_all(from(b in Board, where: b.id == ^board_id), inc: [next_message_number: 1])
  {:ok, message_number}
end)
|> Multi.insert(:post, fn _ ->
  %Post{message_number: message_number, board_id: board_id, thread_id: thread_id, user_id: user_id}
  |> Post.creation_changeset(attrs)
end)
|> Repo.transaction()
```

This is why denials must happen before board-server entry. [VERIFIED: `lib/foglet_bbs/boards/server.ex`]

### Existing Test Sandbox Pattern

```elixir
# Source: test/foglet_bbs/posts/posts_test.exs
defp allow_board_server!(board_id) do
  [{pid, _}] = Registry.lookup(Foglet.BoardRegistry, board_id)
  Sandbox.allow(Repo, self(), pid)
  pid
end
```

Use this for context tests that drive real board servers. [VERIFIED: `test/foglet_bbs/posts/posts_test.exs`]

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Trust UI controls to prevent forbidden posting | Server-side/domain-context preflight before side effects | Locked by Phase 11 context on 2026-04-24 | Prevents terminal, SSH, task, or future API callers from bypassing policy. [VERIFIED: `11-CONTEXT.md`, `CLAUDE.md`] |
| Direct context delegation to board server | Context checks policy first, then delegates success only | Phase 11 target | Rejected attempts are side-effect free. [VERIFIED: `11-SPEC.md`] |
| Generic reply failure copy | Structured error-to-copy mapping | Phase 11 target | Terminal users get clear policy/lock errors. [VERIFIED: `11-CONTEXT.md`] |

**Deprecated/outdated:**
- Reply failure copy `Failed to create post.` for all create errors is outdated for POST-04. [VERIFIED: `lib/foglet_bbs/tui/screens/post_composer.ex`, `11-SPEC.md`]
- Treating `:members` as merely "has a user_id" is insufficient; only active, non-deleted users qualify. [VERIFIED: `11-CONTEXT.md`, `lib/foglet_bbs/accounts/user.ex`]

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `{:error, :posting_not_allowed}` and `{:error, :thread_locked}` are acceptable exact internal tuple shapes. [ASSUMED] | Summary / Architecture Patterns | Planner may choose a different structured shape; keep tests aligned with final implementation. |
| A2 | A small `Foglet.PostingPolicy` helper is acceptable if duplication between `Threads` and `Posts` becomes meaningful. [ASSUMED] | Recommended Project Structure | If maintainers prefer private helpers only, planner should keep logic inside contexts. |

## Open Questions

1. **Should the posting-policy denial copy be exact?**
   - What we know: Locked-thread copy must be exactly `This thread is locked`. [VERIFIED: `11-CONTEXT.md`]
   - What's unclear: Posting-policy denial wording is at the agent's discretion if clear and distinct. [VERIFIED: `11-CONTEXT.md`]
   - Recommendation: Use `You are not allowed to post on this board.` and assert it in TUI tests. [ASSUMED]

2. **Should narrow board-scoped moderator tests be included now?**
   - What we know: Current `scopes_for/2` returns `:site` for active mods and sysops. [VERIFIED: `lib/foglet_bbs/authorization.ex`]
   - What's unclear: There is no current board-moderator data model for a negative board-scope case. [VERIFIED: `11-CONTEXT.md`, `lib/foglet_bbs/authorization.ex`]
   - Recommendation: Unit-test the bypass predicate with injected/constructed scopes only if the helper supports it; otherwise document that current mods are site-scoped. [ASSUMED]

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| Elixir | Compile/test implementation | ✓ | 1.19.5 | — |
| Erlang/OTP | Runtime and tests | ✓ | OTP 28 / ERTS 16.3.1 | — |
| Mix | Test/precommit commands | ✓ | 1.19.5 | — |
| PostgreSQL client | Local DB inspection/test support | ✓ | psql 14.20 | Docker/Postgres service if local DB unavailable. [ASSUMED] |
| Hex package metadata | Version verification | ✓ after escalation | Ecto SQL 3.13.5, Bodyguard 2.4.3 | `mix.lock` if offline. [VERIFIED: `rtk mix hex.info ...`, `mix.lock`] |

**Missing dependencies with no fallback:** None found. [VERIFIED: environment probes]

**Missing dependencies with fallback:** None found for planning. [VERIFIED: environment probes]

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | ExUnit bundled with Elixir 1.19.5. [VERIFIED: `mix --version`] |
| Config file | `test/test_helper.exs` starts ExUnit and SQL sandbox manual mode. [VERIFIED: `.planning/codebase/TESTING.md`, `test/support/data_case.ex`] |
| Quick run command | `rtk mix test test/foglet_bbs/threads/threads_test.exs test/foglet_bbs/posts/posts_test.exs test/foglet_bbs/tui/screens/new_thread_test.exs test/foglet_bbs/tui/screens/post_composer_test.exs` |
| Full suite command | `rtk mix precommit` |

### Phase Requirements -> Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| POST-01 | Thread creation respects board `postable_by` for active user/mod/sysop matrix. | context | `rtk mix test test/foglet_bbs/threads/threads_test.exs` | ✅ |
| POST-02 | Reply creation respects board `postable_by` for active user/mod/sysop matrix. | context | `rtk mix test test/foglet_bbs/posts/posts_test.exs` | ✅ |
| POST-03 | Locked thread rejects normal users and permits scoped mods/sysops. | context | `rtk mix test test/foglet_bbs/posts/posts_test.exs` | ✅ |
| POST-04 | TUI renders clear posting-policy and locked-thread errors without success navigation. | screen/unit | `rtk mix test test/foglet_bbs/tui/screens/new_thread_test.exs test/foglet_bbs/tui/screens/post_composer_test.exs` | ✅ |

### Sampling Rate
- **Per task commit:** Run the narrow command for changed context or TUI files. [VERIFIED: `.planning/codebase/TESTING.md`]
- **Per wave merge:** Run the combined Phase 11 quick command. [ASSUMED]
- **Phase gate:** Run `rtk mix precommit`. [VERIFIED: `CLAUDE.md`, `.planning/codebase/CONVENTIONS.md`]

### Wave 0 Gaps
- [ ] Add POST-01 policy matrix and no-side-effect assertions to `test/foglet_bbs/threads/threads_test.exs`. [VERIFIED: current tests do not cover POST-01 policy matrix]
- [ ] Add POST-02/POST-03 policy, lock, and counter/no-side-effect assertions to `test/foglet_bbs/posts/posts_test.exs`. [VERIFIED: current tests cover happy path but not POST gates]
- [ ] Update `test/foglet_bbs/tui/screens/post_composer_test.exs` to replace the old generic error expectation. [VERIFIED: existing test asserts `Failed to create post.`]
- [ ] Add/extend `test/foglet_bbs/tui/screens/new_thread_test.exs` for posting-policy denial copy. [VERIFIED: existing NewThread has injectable fake context]

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|------------------|
| V2 Authentication | Yes | Require persisted active user before posting; missing/inactive users fail. [VERIFIED: `11-CONTEXT.md`, `lib/foglet_bbs/accounts/user.ex`] |
| V3 Session Management | Indirect | Do not rely on session/TUI identity alone; reload user in context from `user_id`. [VERIFIED: `11-CONTEXT.md`] |
| V4 Access Control | Yes | Enforce board policy and lock bypass in domain contexts before side effects. [VERIFIED: `CLAUDE.md`, `11-CONTEXT.md`] |
| V5 Input Validation | Yes | Keep title/body validation in Ecto changesets and board-server insert flow. [VERIFIED: `lib/foglet_bbs/boards/server.ex`] |
| V6 Cryptography | No | Phase does not modify cryptographic primitives. [VERIFIED: `11-SPEC.md`] |

### Known Threat Patterns for Foglet Posting

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Privilege bypass by direct context call | Elevation of Privilege | Domain-context preflight gates before board-server delegation. [VERIFIED: `CLAUDE.md`, `11-SPEC.md`] |
| Inactive account posting | Elevation of Privilege | Reload user and require active/non-deleted status. [VERIFIED: `11-CONTEXT.md`, `lib/foglet_bbs/accounts/user.ex`] |
| Locked-thread bypass by normal user | Tampering | Check `thread.locked` and allow only scoped mod/sysop bypass. [VERIFIED: `11-SPEC.md`, `lib/foglet_bbs/authorization.ex`] |
| Side-effectful rejection | Tampering | Assert no post/thread rows, no counter changes, and no message-number changes on denial. [VERIFIED: `11-SPEC.md`] |
| Error-copy ambiguity | Repudiation / UX integrity | Structured errors mapped to clear terminal messages. [VERIFIED: `11-CONTEXT.md`] |

## Sources

### Primary (HIGH confidence)
- `.planning/phases/11-posting-policy-enforcement/11-CONTEXT.md` - locked implementation decisions, boundaries, structured error requirements.
- `.planning/phases/11-posting-policy-enforcement/11-SPEC.md` - requirements, acceptance criteria, policy matrix, side-effect constraints.
- `CLAUDE.md` - project architecture, context, authorization, TUI, and testing constraints.
- `docs/DATA_MODEL.md` - board `postable_by`, thread `locked`, message-number invariants.
- `.planning/codebase/ARCHITECTURE.md` - SSH/TUI/domain/board-server data flow.
- `.planning/codebase/TESTING.md` - ExUnit, sandbox, board-server test patterns.
- `lib/foglet_bbs/threads.ex`, `lib/foglet_bbs/posts.ex`, `lib/foglet_bbs/boards/server.ex`, `lib/foglet_bbs/authorization.ex`, `lib/foglet_bbs/accounts/user.ex` - current implementation.
- `mix.lock`, `rtk mix hex.info ecto_sql`, `rtk mix hex.info bodyguard` - dependency versions.

### Secondary (MEDIUM confidence)
- Local dependency source under `deps/ecto`, `deps/ecto_sql`, and `deps/bodyguard` - API behavior available in checked-out deps.

### Tertiary (LOW confidence)
- None.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - verified from `mix.lock`, installed runtime commands, and Hex metadata.
- Architecture: HIGH - phase decisions and project docs lock context/board-server/TUI boundaries.
- Pitfalls: HIGH - derived from current code paths and acceptance criteria.

**Research date:** 2026-04-24  
**Valid until:** 2026-05-24 for local architecture; re-check Hex metadata if dependency versions change.
