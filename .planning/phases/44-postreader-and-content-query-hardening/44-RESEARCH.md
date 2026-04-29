# Phase 44: PostReader And Content Query Hardening - Research

**Researched:** 2026-04-29
**Domain:** Elixir/Phoenix TUI screen state, Ecto bounded queries, soft-delete query invariants
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

## Implementation Decisions

### Bounded PostReader Loading
- **D-01:** Add a context-owned bounded post query for PostReader instead of
  making the screen slice a full `list_posts/1` result locally. The query
  boundary should be cursor/window based, preload `:user`, preserve
  tombstone-capable reader/history rows, and return navigation metadata such as
  direction and whether previous/next windows exist.
- **D-02:** Keep `Foglet.Posts.list_posts/1` tombstone-capable for the existing
  reader/history contract unless planning identifies a clearer name split such
  as keeping `list_posts/1` as history and adding an explicitly bounded reader
  variant. Do not make list/summary hiding depend on PostReader filtering.

### PostReader State Shape
- **D-03:** Keep `%Foglet.TUI.Screens.PostReader.State{}.posts` as the active
  bounded window for compatibility with existing render, pending-read,
  reply-navigation, and viewport helpers. Add explicit navigation/window
  metadata alongside it rather than replacing `posts` with an unrelated
  collection abstraction.
- **D-04:** The acceptance proof for the 1000-post target must verify both the
  domain call contract and state shape: the fake posts domain should observe
  bounded window/page requests, and `%PostReader.State{}.posts` must never
  contain all 1000 posts.

### Reader Navigation
- **D-05:** Preserve current reader key semantics: `n`, `space`, and
  `page_down` advance one post; `p` and `page_up` move one post backward; `j`
  and `k` scroll inside the selected post.
- **D-06:** Crossing the active window boundary should request the adjacent
  bounded window and land on the correct boundary post, preserving pending read
  pointer seeding for the post the user actually reaches.
- **D-07:** `load_intent: :jump_last` should request the newest bounded window
  from the domain and select the newest available post without first loading
  the full thread.
- **D-08:** Matching `:thread_activity` reloads must use the bounded loading
  contract and preserve the current reader position as well as practical,
  rather than resetting through a full-list reload.

### Resize Cache Eviction
- **D-09:** Evict stale-width `render_cache` entries in reducer/state plumbing
  when warming at the current terminal width. Render paths must remain
  read-only and must not mutate `%PostReader.State{}`.
- **D-10:** Keep the cache keyed by `{post_id, terminal_width}` unless planning
  proves a narrower key is simpler and still preserves correct wrapping. The
  required outcome is that active state contains no stale-width cache keys
  after resize-driven warming.

### Render-Purity Guard
- **D-11:** Preserve or strengthen the automated source/static guard that
  rejects state-write operations inside PostReader render helpers.
- **D-12:** If Phase 43 has already moved PostReader rendering into
  `Foglet.TUI.Screens.PostReader.Render`, move or expand the guard so it covers
  the active render boundary there. If render helpers still live in
  `post_reader.ex`, keep the guard focused on that file.

### Soft-Delete Query Policy
- **D-13:** Treat reader/history queries as tombstone-capable: soft-deleted
  posts remain available to PostReader so historical message numbers and gaps
  remain visible.
- **D-14:** Add explicit list/summary coverage or a shared helper proving that
  soft-deleted content is excluded from user-visible list surfaces that should
  hide it, especially `Threads.list_threads/1`, `Threads.list_threads/2`, board
  directory unread/last-post summaries, and existing `QueryHelpers.not_deleted/1`
  paths.
- **D-15:** Prefer `Foglet.QueryHelpers` or context-owned query helpers over new
  ad hoc `is_nil(deleted_at)` predicates in screens.

### the agent's Discretion
- Downstream agents may choose exact function names, option names, window size,
  cursor metadata shape, and test fake module names, provided the behavior is
  explicit, grep-friendly, and structurally tested.
- Downstream agents may choose whether bounded loading is implemented as
  `list_posts_window/2`, `list_posts_after/3`, `list_posts_before/3`, or a
  single option-driven reader function, as long as PostReader does not perform
  full-list loading for the large-thread path.
- Downstream agents may decide whether the render-purity guard remains a
  source-level ExUnit check or becomes a stronger shared/static helper.

### Deferred Ideas (OUT OF SCOPE)

## Deferred Ideas

None - analysis stayed within phase scope.

### Reviewed Todos (not folded)
No matching todos were found for this phase.
</user_constraints>

## Summary

Phase 44 should stay inside the existing Elixir/Phoenix/Raxol stack and add no new runtime dependency. [VERIFIED: `mix.exs`, `mix deps`] The standard implementation is a context-owned Ecto query that returns a bounded reader window plus metadata, while the TUI screen stores only that active window in `%PostReader.State{}.posts`. [VERIFIED: `.planning/phases/44-postreader-and-content-query-hardening/44-CONTEXT.md`, `lib/foglet_bbs/tui/screens/post_reader/state.ex`]

The main unknown that matters is not pagination mechanics; it is boundary discipline. [VERIFIED: `lib/foglet_bbs/tui/SCREEN_CONTRACT.md`] Query semantics belong in `Foglet.Posts`, render/cache mutation belongs in PostReader reducer/state plumbing, and list/summary soft-delete guarantees belong in `Foglet.QueryHelpers` or context tests, not in screens. [VERIFIED: `AGENTS.md`, `lib/foglet_bbs/query_helpers.ex`, `lib/foglet_bbs/posts.ex`, `lib/foglet_bbs/threads.ex`, `lib/foglet_bbs/boards.ex`]

**Primary recommendation:** Implement `Foglet.Posts.list_reader_window/2` with a message-number cursor, use it from PostReader load/navigation/thread-activity paths, evict stale render-cache widths inside warming helpers, and add structural ExUnit tests for 1000-post bounded state plus soft-delete list/summary exclusion. [VERIFIED: local code audit] [CITED: https://hexdocs.pm/ecto/3.13.1/Ecto.Query.html] [CITED: https://www.postgresql.org/docs/15/queries-limit.html]

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| POST-01 | User can read very large threads without PostReader requiring every post in the thread to be loaded eagerly. | Use context-owned bounded Ecto query and assert fake domain never sees legacy full-list call. [VERIFIED: `44-SPEC.md`, `post_reader.ex`] |
| POST-02 | User can resize the terminal during PostReader sessions without stale-width render-cache entries accumulating for the life of the screen. | Evict non-current widths from `render_cache` in `warm_cache/4` or a helper called by `warm_selected_post/2`. [VERIFIED: `post_reader.ex`, `post_reader_test.exs`] |
| POST-03 | Maintainer has automated protection for the PostReader render-path purity invariant so render helpers do not mutate state. | Preserve and broaden the existing source-level guard to the active render file/module. [VERIFIED: `post_reader_test.exs`] |
| POST-04 | Maintainer has automated coverage or a shared query helper that prevents soft-deleted posts from reappearing in list paths. | Test `Threads.list_threads/1,2`, `Boards.unread_count(s)`, and board directory summaries around deleted rows; prefer `QueryHelpers.not_deleted/1`. [VERIFIED: `threads.ex`, `boards.ex`, `query_helpers.ex`] |
</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|--------------|----------------|-----------|
| Bounded post retrieval | API / Backend | Database / Storage | `Foglet.Posts` owns post queries and can express cursor predicates in Ecto; Postgres executes ordering/limit. [VERIFIED: `AGENTS.md`, `posts.ex`] |
| Reader navigation state | Browser / Client equivalent: TUI screen | API / Backend | PostReader owns selected index/window metadata, but asks `Foglet.Posts` for adjacent windows. [VERIFIED: `SCREEN_CONTRACT.md`, `post_reader.ex`] |
| Render cache eviction | Browser / Client equivalent: TUI screen | — | `render_cache` is screen-local state and must be reconstructable. [VERIFIED: `post_reader/state.ex`, `AGENTS.md`] |
| Render-purity enforcement | Test / CI | TUI screen | Existing ExUnit static guard protects render helpers from state writes. [VERIFIED: `post_reader_test.exs`] |
| Soft-delete list policy | API / Backend | Database / Storage | Context queries and shared helpers own deleted-row visibility, not screens. [VERIFIED: `AGENTS.md`, `DATA_MODEL.md`, `query_helpers.ex`] |

## Project Constraints (from AGENTS.md)

- Use `rtk` as the shell command prefix in this repo. [VERIFIED: `AGENTS.md`]
- Foglet is SSH-first; do not add end-user browser workflows for this phase. [VERIFIED: `AGENTS.md`, `.planning/REQUIREMENTS.md`]
- Domain workflows belong in `Foglet.*` contexts, not TUI render functions. [VERIFIED: `AGENTS.md`]
- Postgres is authoritative for durable state; ETS/process state must be reconstructable. [VERIFIED: `AGENTS.md`]
- Thread and post creation must keep using `Foglet.Boards.Server` for message-number allocation. [VERIFIED: `AGENTS.md`, `DATA_MODEL.md`]
- Soft-deleted posts keep message numbers; do not fill gaps. [VERIFIED: `AGENTS.md`, `DATA_MODEL.md`]
- Use `Foglet.QueryHelpers` or context-owned helpers rather than duplicated predicates. [VERIFIED: `AGENTS.md`, `query_helpers.ex`]
- Render functions must be pure over already-loaded state and use existing widgets/theme routing if touched. [VERIFIED: `AGENTS.md`, `SCREEN_CONTRACT.md`, `widgets/README.md`]
- Tests must avoid pure UI text-presence assertions, `Process.sleep/1`, and `Process.alive?/1`; use `start_supervised!/1` for processes. [VERIFIED: `AGENTS.md`, `.planning/codebase/TESTING.md`]
- Run `rtk mix precommit` after code changes. [VERIFIED: `AGENTS.md`]

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Elixir / OTP | Elixir 1.19.5, OTP 28 | Language/runtime and ExUnit | Installed runtime and project test runner. [VERIFIED: `rtk elixir --version`, `mix.exs`] |
| Phoenix | 1.8.5 | App infrastructure, PubSub, runtime shell support | Existing infrastructure; no browser workflow added. [VERIFIED: `mix.lock`, `rtk mix hex.info phoenix`] |
| Ecto / Ecto SQL | 3.13.5 | Context queries, `limit`, `where`, `order_by`, preloads | Ecto is the repo's query DSL and supports composable bounded queries. [VERIFIED: `mix.lock`, `rtk mix hex.info ecto`, `rtk mix hex.info ecto_sql`] [CITED: https://hexdocs.pm/ecto/3.13.1/Ecto.Query.html] |
| Postgrex / PostgreSQL | Postgrex 0.22.0, local psql 14.20 | Database adapter and durable query execution | Existing Postgres-backed persistence. [VERIFIED: `mix.lock`, `rtk mix hex.info postgrex`, `rtk psql --version`] |
| Raxol | 2.4.0 path dependency | TUI rendering and `Viewport` | Current TUI toolkit; `Viewport.update/2` already owns scroll bounds. [VERIFIED: `vendor/raxol/mix.exs`, `vendor/raxol/lib/raxol/ui/components/display/viewport.ex`] |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| ExUnit | bundled with Elixir 1.19.5 | Reducer, domain, and static-source tests | Use for structural assertions, fake domains, and render-purity guard. [VERIFIED: `mix.exs`, `test/foglet_bbs/tui/screens/post_reader_test.exs`] [CITED: https://hexdocs.pm/ex_unit/ExUnit.Assertions.html] |
| StreamData | 1.3.0 | Property-style generated data | Optional only if a compact generated soft-delete/window invariant test is clearer than fixtures. [VERIFIED: `mix.lock`, `rtk mix hex.info stream_data`] |
| Mdex / Foglet.Markdown | Mdex locked 0.12.1, latest 0.12.2 observed | Markdown rendering behind `Foglet.Markdown` | Do not change for this phase; PostReader should keep using domain override/fake markdown in tests. [VERIFIED: `mix.lock`, `rtk mix hex.info mdex`, `post_reader_test.exs`] |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Context-owned Ecto window query | Slice `list_posts/1` in PostReader | Fails POST-01 because the screen still receives all rows. [VERIFIED: `44-SPEC.md`] |
| Message-number cursor | Offset pagination | PostgreSQL documents that skipped `OFFSET` rows still have to be computed, and unstable ordering creates inconsistent subsets without a unique `ORDER BY`. [CITED: https://www.postgresql.org/docs/15/queries-limit.html] |
| Shared query helper/tests | Screen-local `deleted_at` filtering | Violates context boundary and risks inconsistent soft-delete behavior. [VERIFIED: `AGENTS.md`, `query_helpers.ex`] |

**Installation:**
```bash
# No new packages. Use existing deps:
rtk mix deps.get
```

**Version verification:** Package versions above were checked with `rtk mix deps`, `mix.lock`, and `rtk mix hex.info` where Hex packages exist. [VERIFIED: shell commands]

## Architecture Patterns

### System Architecture Diagram

```text
Route enter / thread activity / n,p navigation
        |
        v
PostReader.update/3 reducer
        |
        | emits Effect.task(:load_posts_window, :post_reader, fun)
        v
Foglet.TUI.App effect interpreter
        |
        v
Foglet.Posts.list_reader_window(thread_id, cursor/options)
        |
        | Ecto query: where thread_id + cursor, order by message_number, limit, preload :user
        v
PostgreSQL posts table
        |
        v
%ReaderWindow{posts, first_cursor, last_cursor, has_previous?, has_next?, direction}
        |
        v
PostReader task_result reducer
        |
        | updates active window, selected_post_index, pending read pointer, render cache for current width
        v
Pure PostReader.render/2 + Raxol Viewport
```

### Recommended Project Structure

```text
lib/foglet_bbs/
├── posts.ex                         # Bounded reader/history query API
├── query_helpers.ex                 # Shared soft-delete predicates
└── tui/screens/
    ├── post_reader.ex               # Reducer, effects, cache warming, render if Phase 43 has not split it
    └── post_reader/state.ex         # Window metadata fields alongside active posts window

test/foglet_bbs/
├── posts/posts_test.exs             # Reader-window query contract
├── threads/threads_test.exs         # list_threads deleted-row protection
├── boards/boards_test.exs           # unread and directory summary protection
└── tui/screens/post_reader_test.exs # fake-domain bounded-state/navigation/cache/purity tests
```

### Pattern 1: Context-Owned Reader Window

**What:** Add a posts context function that returns a bounded window and metadata; keep `list_posts/1` tombstone-capable for history unless implementation chooses a clearer name split. [VERIFIED: `44-CONTEXT.md`]

**When to use:** Every PostReader route entry, jump-last entry, adjacent-window crossing, and matching `:thread_activity` reload. [VERIFIED: `44-CONTEXT.md`, `post_reader.ex`]

**Example:**
```elixir
# Source: Ecto.Query docs + Foglet.Posts existing list_posts/1 pattern.
def list_reader_window(thread_id, opts \\ []) do
  limit = Keyword.get(opts, :limit, 50)
  cursor = Keyword.get(opts, :after_message_number)

  query =
    from p in Post,
      where: p.thread_id == ^thread_id,
      where: is_nil(^cursor) or p.message_number > ^cursor,
      order_by: [asc: p.message_number],
      limit: ^(limit + 1),
      preload: [:user]

  rows = Repo.all(query)
  {posts, extra} = Enum.split(rows, limit)

  %{
    posts: posts,
    has_next?: extra != [],
    first_cursor: posts |> List.first() |> cursor_for(),
    last_cursor: posts |> List.last() |> cursor_for()
  }
end
```

### Pattern 2: Reducer-Only Cache Mutation

**What:** Keep `render_cache` writes in `warm_cache/4`, `warm_selected_post/2`, or a sibling state helper, and prune keys whose width does not equal the current terminal width before/while inserting the current key. [VERIFIED: `post_reader.ex`]

**When to use:** After load task results, local post navigation, scroll warming, and resize-driven warming. [VERIFIED: `post_reader.ex`, `44-SPEC.md`]

**Example:**
```elixir
# Source: current PostReader warm_cache/4 shape.
defp cache_for_current_width(render_cache, width) do
  render_cache
  |> Enum.reject(fn {{_post_id, cached_width}, _tuples} -> cached_width != width end)
  |> Map.new()
end

defp warm_cache(ss, state, post, width) do
  key = {post.id, width}
  cache = cache_for_current_width(ss.render_cache, width)

  if Map.has_key?(cache, key) do
    %{ss | render_cache: cache}
  else
    %{ss | render_cache: Map.put(cache, key, parse_body(state, post))}
  end
end
```

### Pattern 3: Structural Fake-Domain Proof

**What:** Use a fake posts module that records or fails on the old unbounded `list_posts/1` path and returns fixed-size windows for the new API. [VERIFIED: `post_reader_test.exs`, `44-SPEC.md`]

**When to use:** POST-01 and navigation boundary tests. [VERIFIED: `44-SPEC.md`]

**Example:**
```elixir
# Source: existing PostReader fake-domain override pattern.
defmodule FakeWindowedPosts do
  def list_posts(_thread_id), do: raise("unbounded list_posts/1 is forbidden")

  def list_reader_window("t1000", opts) do
    send(self(), {:reader_window_requested, opts})
    # Return at most @window_size rows plus metadata here.
  end
end
```

### Anti-Patterns to Avoid

- **Screen slicing:** Do not call `list_posts/1` and keep only part of it in `%State{}.posts`; this hides eager loading instead of removing it. [VERIFIED: `44-SPEC.md`]
- **Offset as primary navigation:** Do not use large-offset page math for reader traversal; use message-number cursor predicates with stable ordering. [CITED: https://www.postgresql.org/docs/15/queries-limit.html]
- **Render-time warming:** Do not write to `render_cache` from `render_*` helpers. [VERIFIED: `post_reader.ex`, `post_reader_test.exs`]
- **UI soft-delete filtering:** Do not make PostReader or list screens decide deleted-row visibility. [VERIFIED: `AGENTS.md`, `query_helpers.ex`]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Bounded SQL retrieval | Custom in-memory pagination over a full list | Ecto `where` + `order_by` + `limit` query in `Foglet.Posts` | Ecto already composes query predicates and preloads. [CITED: https://hexdocs.pm/ecto/3.13.1/Ecto.Query.html] |
| Stable post order | Timestamp-only cursor or list index cursor | `message_number` cursor scoped to thread/board | Message numbers are stable and preserve soft-delete gaps. [VERIFIED: `DATA_MODEL.md`, `AGENTS.md`] |
| Viewport scroll math | Custom scroll clamp | `Raxol.UI.Components.Display.Viewport.update/2` | Existing component clamps `scroll_top` when children/height change. [VERIFIED: `vendor/raxol/lib/raxol/ui/components/display/viewport.ex`] |
| Markdown rendering cache | New markdown parser/cache service | Existing `Foglet.Markdown` and screen-local `render_cache` | Tests already use markdown domain overrides and cache keys. [VERIFIED: `post_reader.ex`, `post_reader_test.exs`] |
| Soft-delete predicates | Repeated `is_nil(deleted_at)` in screens | `Foglet.QueryHelpers.not_deleted/1` or context-owned helpers | Shared helper keeps list semantics consistent. [VERIFIED: `query_helpers.ex`, `AGENTS.md`] |

**Key insight:** The hard part is preserving Foglet's existing contracts while bounding memory, not adding infrastructure. [VERIFIED: `44-CONTEXT.md`, local code audit]

## Common Pitfalls

### Pitfall 1: Bounded State But Unbounded Query
**What goes wrong:** The reducer stores a window but the task still calls `list_posts/1`. [VERIFIED: `post_reader.ex`]
**Why it happens:** The fake-domain test only checks `%State{}.posts` length and not the domain call. [VERIFIED: `44-SPEC.md`]
**How to avoid:** Make the fake posts module raise on `list_posts/1` and assert window-call messages. [VERIFIED: existing domain override pattern in `post_reader_test.exs`]
**Warning signs:** `Effect.task(:load_posts, ...)` still wraps `posts_mod.list_posts(thread_id)`. [VERIFIED: `post_reader.ex`]

### Pitfall 2: Losing Jump-Last Semantics
**What goes wrong:** `load_intent: :jump_last` lands on the first page or requires a full list to find the final row. [VERIFIED: `selected_index_after_load/2` in `post_reader.ex`]
**Why it happens:** The current implementation selects `length(posts) - 1` after full load. [VERIFIED: `post_reader.ex`]
**How to avoid:** Add a `direction: :last` or `around: :newest` query mode that orders descending/limits, then normalizes returned posts to reader order and selects the newest row. [CITED: https://hexdocs.pm/ecto/3.13.1/Ecto.Query.html]
**Warning signs:** Tests use `FakePosts.list_posts/1` for jump-last. [VERIFIED: `post_reader_test.exs`]

### Pitfall 3: Thread Activity Resets Position
**What goes wrong:** A new post PubSub event reloads the first window and moves the reader away from the current post. [VERIFIED: current `:thread_activity` reload path in `post_reader.ex`]
**Why it happens:** Reload currently has no cursor/current-position input. [VERIFIED: `post_reader.ex`]
**How to avoid:** On activity, request a window anchored around the current selected post or current window cursor, then restore selected post by id/message_number when possible. [VERIFIED: `44-CONTEXT.md`]
**Warning signs:** Task result handling always uses `selected_index_after_load/2`. [VERIFIED: `post_reader.ex`]

### Pitfall 4: Cache Eviction In Render
**What goes wrong:** Stale widths disappear, but `render_*` mutates state and breaks the screen contract. [VERIFIED: `SCREEN_CONTRACT.md`, `post_reader_test.exs`]
**Why it happens:** Resize is noticed during render via `context.terminal_size`. [VERIFIED: `post_reader.ex`]
**How to avoid:** Prune widths inside cache warming invoked by reducer paths; render may still fallback-parse but must not write. [VERIFIED: `post_reader.ex`]
**Warning signs:** Static guard exceptions are added for `%{state | ...}`, `Map.put`, or `put_in`. [VERIFIED: `post_reader_test.exs`]

### Pitfall 5: Soft-Delete Policy Drift
**What goes wrong:** Reader/history hides tombstones or list paths show deleted posts. [VERIFIED: `44-SPEC.md`, `posts_test.exs`, `boards.ex`, `threads.ex`]
**Why it happens:** `Posts.list_posts/1` intentionally includes tombstones while other contexts hide them, so a rename or helper change can invert one side. [VERIFIED: `44-CONTEXT.md`]
**How to avoid:** Name reader/history APIs explicitly and add tests for both sides of the split. [VERIFIED: `44-SPEC.md`]
**Warning signs:** New ad hoc `is_nil(p.deleted_at)` outside `QueryHelpers` or context-private helpers. [VERIFIED: `AGENTS.md`, `query_helpers.ex`]

## Code Examples

Verified patterns from official and local sources:

### Ecto Bounded Query With Preload
```elixir
# Source: https://hexdocs.pm/ecto/3.13.1/Ecto.Query.html
from p in Post,
  where: p.thread_id == ^thread_id and p.message_number > ^after_number,
  order_by: [asc: p.message_number],
  limit: ^limit,
  preload: [:user]
```

### PostReader Effect Boundary
```elixir
# Source: lib/foglet_bbs/tui/screens/post_reader.ex
effect =
  Effect.task(:load_posts_window, :post_reader, fn ->
    posts_mod.list_reader_window(thread_id, cursor: cursor, limit: limit)
  end)
```

### Source Guard Should Track Active Render Boundary
```elixir
# Source: test/foglet_bbs/tui/screens/post_reader_test.exs
forbidden_patterns = [~r/put_in\(/, ~r/%\{state \|/, ~r/Map\.put\(/]
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Load all posts and slice locally | Context-owned bounded cursor/window query | Phase 44 target | Avoids eager load and gives tests a domain-call contract. [VERIFIED: `44-SPEC.md`] |
| Offset pages for large lists | Cursor/keyset-style predicates over stable order columns | Established Postgres pagination practice; PostgreSQL docs warn large offsets still compute skipped rows | Use `message_number` cursor for reader traversal. [CITED: https://www.postgresql.org/docs/15/queries-limit.html] |
| Render helpers may rely on convention | Static/source guard rejects state writes in render boundary | Existing PostReader test | Keep or strengthen guard after render-module moves. [VERIFIED: `post_reader_test.exs`] |
| Scattered soft-delete predicates | Shared helper or context-owned query boundary | Existing `Foglet.QueryHelpers.not_deleted/1` | Planner should add coverage and reduce ad hoc predicates. [VERIFIED: `query_helpers.ex`] |

**Deprecated/outdated:**
- Treating `Repo.all(list_posts)` plus in-memory windowing as pagination is outdated for this phase because POST-01 specifically forbids eager screen loading. [VERIFIED: `44-SPEC.md`]
- Adding browser UI or LiveView flows is out of scope; Foglet remains SSH-first for this milestone. [VERIFIED: `.planning/REQUIREMENTS.md`, `AGENTS.md`]

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Window size can be chosen by downstream implementation. [ASSUMED] | Architecture Patterns | Tests may need adjustment if the user expects a fixed page size. |

## Open Questions

1. **Should the bounded result be a plain map or a named struct?**
   - What we know: Existing state uses structs and context APIs return structs/lists depending on domain. [VERIFIED: local code audit]
   - What's unclear: Phase context leaves exact metadata shape to downstream agents. [VERIFIED: `44-CONTEXT.md`]
   - Recommendation: Use a small `%Foglet.Posts.ReaderWindow{}` struct if Dialyzer clarity matters; otherwise a documented map is enough for the phase. [ASSUMED]

2. **Should `list_posts/1` be renamed to clarify tombstone semantics?**
   - What we know: Context allows retaining `list_posts/1` as tombstone-capable history. [VERIFIED: `44-CONTEXT.md`]
   - What's unclear: Whether a rename would create unnecessary churn. [ASSUMED]
   - Recommendation: Keep `list_posts/1` unchanged and add `list_reader_window/2`; document both as tombstone-capable. [VERIFIED: `44-CONTEXT.md`]

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| Elixir | Compile/test | Yes | 1.19.5 | None needed. [VERIFIED: `rtk elixir --version`] |
| Mix | Test/precommit | Yes | 1.19.5 | None needed. [VERIFIED: `rtk mix --version`] |
| PostgreSQL CLI | Domain tests | Yes | psql 14.20 | Repo test alias can create/migrate when server is running. [VERIFIED: `rtk psql --version`] |
| PostgreSQL server | DB-backed tests | No response on `/tmp:5432` during research | — | Planner should expect tests may need local DB started before `rtk mix test`. [VERIFIED: `rtk pg_isready`] |
| Hex registry access | Version checks | Yes | n/a | Used `rtk mix hex.info`. [VERIFIED: shell commands] |

**Missing dependencies with no fallback:**
- PostgreSQL server was not responding during research; DB-backed tests and `rtk mix precommit` will need a running local Postgres service. [VERIFIED: `rtk pg_isready`]

**Missing dependencies with fallback:**
- None identified. [VERIFIED: environment audit]

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | ExUnit bundled with Elixir 1.19.5; StreamData 1.3.0 available. [VERIFIED: `mix.exs`, `mix.lock`] |
| Config file | `test/test_helper.exs` plus `config/test.exs`. [VERIFIED: `.planning/codebase/TESTING.md`] |
| Quick run command | `rtk mix test test/foglet_bbs/tui/screens/post_reader_test.exs` |
| Full suite command | `rtk mix precommit` |

### Phase Requirements -> Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| POST-01 | 1000-post reader uses bounded domain window and bounded `%State{}.posts` | unit/reducer | `rtk mix test test/foglet_bbs/tui/screens/post_reader_test.exs` | Yes |
| POST-01 | Posts context returns bounded reader/history window with `:user` preload | domain | `rtk mix test test/foglet_bbs/posts/posts_test.exs` | Yes |
| POST-02 | Resize warming removes stale-width render-cache keys | unit/reducer | `rtk mix test test/foglet_bbs/tui/screens/post_reader_test.exs` | Yes |
| POST-03 | Render helper boundary rejects state writes | static/unit | `rtk mix test test/foglet_bbs/tui/screens/post_reader_test.exs` | Yes |
| POST-04 | Reader/history includes tombstones while list/summary hides them | domain | `rtk mix test test/foglet_bbs/posts/posts_test.exs test/foglet_bbs/threads/threads_test.exs test/foglet_bbs/boards/boards_test.exs` | Yes |

### Sampling Rate

- **Per task commit:** `rtk mix test test/foglet_bbs/tui/screens/post_reader_test.exs`
- **Per wave merge:** `rtk mix test test/foglet_bbs/posts/posts_test.exs test/foglet_bbs/threads/threads_test.exs test/foglet_bbs/boards/boards_test.exs test/foglet_bbs/tui/screens/post_reader_test.exs`
- **Phase gate:** `rtk mix precommit`

### Wave 0 Gaps

- [ ] Add fake-domain bounded-window tests to `test/foglet_bbs/tui/screens/post_reader_test.exs`. [VERIFIED: current tests lack bounded-window API]
- [ ] Add `Foglet.Posts` bounded reader-window domain tests. [VERIFIED: `posts_test.exs` currently covers tombstone list behavior but no bounded reader query]
- [ ] Add or extend `Threads`/`Boards` soft-delete list-summary tests for Phase 44's exact list paths. [VERIFIED: `threads_test.exs`, `boards_test.exs`]
- [ ] Update render-purity source guard if Phase 43 moved render helpers to `post_reader/render.ex`. [VERIFIED: `44-CONTEXT.md`, current `post_reader_test.exs` path]

## Sources

### Primary (HIGH confidence)
- Local project files: `AGENTS.md`, `.planning/REQUIREMENTS.md`, `.planning/STATE.md`, `44-CONTEXT.md`, `44-SPEC.md`, `.planning/codebase/CONCERNS.md`, `.planning/codebase/TESTING.md`.
- Local implementation files: `lib/foglet_bbs/posts.ex`, `threads.ex`, `boards.ex`, `query_helpers.ex`, `tui/SCREEN_CONTRACT.md`, `tui/screens/post_reader.ex`, `tui/screens/post_reader/state.ex`, `test/foglet_bbs/tui/screens/post_reader_test.exs`.
- Hex registry via `rtk mix hex.info`: `ecto`, `ecto_sql`, `phoenix`, `postgrex`, `mdex`, `stream_data`.
- Ecto.Query docs: https://hexdocs.pm/ecto/3.13.1/Ecto.Query.html
- PostgreSQL LIMIT/OFFSET docs: https://www.postgresql.org/docs/15/queries-limit.html
- ExUnit assertions docs: https://hexdocs.pm/ex_unit/ExUnit.Assertions.html

### Secondary (MEDIUM confidence)
- ExUnit callbacks docs for `start_supervised!/2`: https://hexdocs.pm/ex_unit/1.18.1/ExUnit.Callbacks.html

### Tertiary (LOW confidence)
- None used as authoritative guidance.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - verified from `mix.exs`, `mix.lock`, `mix deps`, and Hex registry commands.
- Architecture: HIGH - driven by locked Phase 44 context and current PostReader/context code.
- Pitfalls: HIGH - each pitfall maps to current code paths or explicit spec acceptance criteria.

**Research date:** 2026-04-29
**Valid until:** 2026-05-29 for local architecture; re-check Hex package versions if dependency changes are introduced.
