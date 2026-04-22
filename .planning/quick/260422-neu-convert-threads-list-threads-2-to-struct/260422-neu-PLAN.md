---
phase: quick-260422-neu
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - lib/foglet_bbs/threads/thread_entry.ex
  - lib/foglet_bbs/threads.ex
  - lib/foglet_bbs/tui/screens/thread_list.ex
  - lib/foglet_bbs/tui/app.ex
  - test/foglet_bbs/threads/threads_test.exs
autonomous: true
requirements: [LIST-03]

must_haves:
  truths:
    - "`Foglet.Threads.list_threads/2` returns `[ThreadEntry.t()]`, not `[map()]`"
    - "`mix dialyzer` passes without spec violations on `list_threads/2`, `annotate_no_user/1`, and `preload_created_by/1`"
    - "Thread rows rendered by `ThreadList` and loaded by `TUI.App` are `%ThreadEntry{}` structs throughout"
    - "`mix precommit` passes (compile, format, credo --strict, sobelow, dialyzer)"
  artifacts:
    - path: "lib/foglet_bbs/threads/thread_entry.ex"
      provides: "`%Foglet.Threads.ThreadEntry{}` struct with 13 fields and `@type t`"
      exports: ["ThreadEntry"]
    - path: "lib/foglet_bbs/threads.ex"
      provides: "Updated `list_threads/2` spec, `annotate_no_user/1`, `preload_created_by/1`"
      contains: "ThreadEntry.t()"
    - path: "lib/foglet_bbs/tui/screens/thread_list.ex"
      provides: "`annotate_fallback/1` builds `%ThreadEntry{}`"
    - path: "lib/foglet_bbs/tui/app.ex"
      provides: "`load_threads_for_user/3` fallback branch builds `%ThreadEntry{}`"
  key_links:
    - from: "lib/foglet_bbs/threads.ex:list_threads/2"
      to: "Foglet.Threads.ThreadEntry"
      via: "Enum.map(&struct(ThreadEntry, &1)) post-Repo.all"
      pattern: "struct(ThreadEntry"
    - from: "lib/foglet_bbs/threads.ex:preload_created_by/1"
      to: "%ThreadEntry{}"
      via: "struct update syntax %{row | created_by: ...}"
      pattern: "row | created_by:"
    - from: "lib/foglet_bbs/tui/screens/thread_list.ex:annotate_fallback/1"
      to: "Foglet.Threads.ThreadEntry"
      via: "%ThreadEntry{} constructor from %Thread{} fields"
      pattern: "%ThreadEntry{"
    - from: "lib/foglet_bbs/tui/app.ex:load_threads_for_user/3"
      to: "Foglet.Threads.ThreadEntry"
      via: "%ThreadEntry{} constructor from %Thread{} fields"
      pattern: "%ThreadEntry{"
---

<objective>
Promote the anonymous map returned by `Foglet.Threads.list_threads/2` to a named
`%Foglet.Threads.ThreadEntry{}` struct. Fold the manual `preload_created_by/1` and
`annotate_no_user/1` helpers into the new struct path. Update every call site that
builds the interim plain-map shape to produce a `%ThreadEntry{}` instead.

Purpose: Eliminates the `[map()]` return type from the public API, gives dialyzer
full visibility into the thread-list shape, and makes the codebase consistent
(all domain-boundary types are named structs).

Output: New `lib/foglet_bbs/threads/thread_entry.ex`; updated `threads.ex`,
`thread_list.ex`, `app.ex`; one additional assertion in `threads_test.exs`.
</objective>

<execution_context>
@/Users/brendan.turner/Dev/personal/foglet_bbs/.claude/get-shit-done/workflows/execute-plan.md
@/Users/brendan.turner/Dev/personal/foglet_bbs/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@/Users/brendan.turner/Dev/personal/foglet_bbs/.planning/STATE.md
@/Users/brendan.turner/Dev/personal/foglet_bbs/CLAUDE.md

<interfaces>
<!-- Key types and contracts the executor needs. Extracted from codebase. -->

From lib/foglet_bbs/threads/thread.ex (Ecto schema fields relevant to ThreadEntry):
  id, title, board_id, sticky, locked, post_count, first_post_id,
  last_post_at, deleted_at, inserted_at, created_by_id
  (Associations :board, :created_by, :posts, :first_post are NOT ThreadEntry fields)

From lib/foglet_bbs/threads.ex — current list_threads/2 select map shape:
  %{
    id: t.id, title: t.title, board_id: t.board_id, sticky: t.sticky,
    locked: t.locked, post_count: t.post_count, first_post_id: t.first_post_id,
    last_post_at: t.last_post_at, deleted_at: t.deleted_at,
    inserted_at: t.inserted_at, created_by_id: t.created_by_id,
    has_unread: <boolean expression>
  }
  -- `:created_by` is added by `preload_created_by/1` after Repo.all

From lib/foglet_bbs/tui/screens/thread_list.ex — annotate_fallback/1 (lines 178-184):
  defp annotate_fallback(%Foglet.Threads.Thread{} = t) do
    t |> Map.from_struct() |> Map.put(:has_unread, false)
  end
  defp annotate_fallback(t) when is_map(t), do: Map.put_new(t, :has_unread, false)

From lib/foglet_bbs/tui/app.ex — load_threads_for_user/3 fallback branch (lines 651-661):
  %Foglet.Threads.Thread{} ->
    t |> Map.from_struct() |> Map.put(:has_unread, false)
  %{} ->
    Map.put_new(t, :has_unread, false)
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Define `%Foglet.Threads.ThreadEntry{}` struct</name>
  <files>lib/foglet_bbs/threads/thread_entry.ex</files>
  <action>
Create `lib/foglet_bbs/threads/thread_entry.ex` following the established one-struct-per-file,
no-module-nesting pattern (same as `lib/foglet_bbs/tui/screens/post_reader/state.ex`).

Module: `Foglet.Threads.ThreadEntry`

Define `defstruct` with these 13 fields (all defaulting to `nil`):
  `id, title, board_id, sticky, locked, post_count, first_post_id,
   last_post_at, deleted_at, inserted_at, created_by_id, has_unread, created_by`

Provide a `@type t` typespec:
  ```elixir
  @type t :: %__MODULE__{
    id: String.t() | nil,
    title: String.t() | nil,
    board_id: String.t() | nil,
    sticky: boolean() | nil,
    locked: boolean() | nil,
    post_count: non_neg_integer() | nil,
    first_post_id: String.t() | nil,
    last_post_at: DateTime.t() | nil,
    deleted_at: DateTime.t() | nil,
    inserted_at: DateTime.t() | nil,
    created_by_id: String.t() | nil,
    has_unread: boolean() | nil,
    created_by: Foglet.Accounts.User.t() | nil
  }
  ```

No constructor function needed. No `@moduledoc false` — write a brief `@moduledoc` describing
this as a read-model projection of a thread row with `has_unread` annotation and
`created_by` preloaded.
  </action>
  <verify>
    <automated>mix compile --warnings-as-errors 2>&1 | grep -E "thread_entry|ThreadEntry|error:|warning:" | head -20</automated>
  </verify>
  <done>`%Foglet.Threads.ThreadEntry{}` struct compiles cleanly; `@type t` is present with all 13 fields.</done>
</task>

<task type="auto">
  <name>Task 2: Update `Foglet.Threads` — spec, builder, preload, annotate</name>
  <files>lib/foglet_bbs/threads.ex</files>
  <action>
Add `alias Foglet.Threads.ThreadEntry` alongside the existing `Thread` alias at line 15.

**`@spec list_threads/2`** (line 71): Change return from `[map()]` to `[ThreadEntry.t()]`.
Also update the `@doc` to say "returns `[ThreadEntry.t()]`" instead of "list of maps".

**`list_threads/2` user_id clause** (lines 78-105):
Keep the existing `select:` map literal unchanged — Ecto cannot materialize non-schema
structs in `select:`, so keep the bare map. After `Repo.all()`, convert rows to
`%ThreadEntry{}` structs using `Enum.map(&struct(ThreadEntry, &1))` BEFORE calling
`preload_created_by/1`. The resulting pipeline becomes:

  ```elixir
  query
  |> Repo.all()
  |> Enum.map(&struct(ThreadEntry, &1))
  |> preload_created_by()
  ```

**`preload_created_by/1`** (lines 107-124):
Rows are now `%ThreadEntry{}` structs, not plain maps. Change the final `Map.put/3`
call to struct update syntax:

  ```elixir
  Enum.map(rows, fn row ->
    %{row | created_by: Map.get(users, row.created_by_id)}
  end)
  ```

The batch user-query logic above it does not change.

**`annotate_no_user/1`** (lines 126-130):
Replace the `Map.from_struct/1 |> Map.put` pattern with an explicit `%ThreadEntry{}`
constructor that selects only the fields ThreadEntry declares (do NOT use `Map.from_struct`
which would include Ecto internal keys like `__meta__`, `:board`, `:posts`):

  ```elixir
  defp annotate_no_user(%Thread{} = t) do
    %ThreadEntry{
      id: t.id,
      title: t.title,
      board_id: t.board_id,
      sticky: t.sticky,
      locked: t.locked,
      post_count: t.post_count,
      first_post_id: t.first_post_id,
      last_post_at: t.last_post_at,
      deleted_at: t.deleted_at,
      inserted_at: t.inserted_at,
      created_by_id: t.created_by_id,
      has_unread: false,
      created_by: t.created_by
    }
  end
  ```

Note: `list_threads/1` (the single-arity board-only version, lines 42-49) is NOT changed —
it continues to return `[Thread.t()]` and its spec remains untouched.
  </action>
  <verify>
    <automated>mix test test/foglet_bbs/threads/threads_test.exs 2>&1 | tail -20</automated>
  </verify>
  <done>All existing threads tests pass; `list_threads/2` returns `[ThreadEntry.t()]` with correct `has_unread` and `created_by` values.</done>
</task>

<task type="auto">
  <name>Task 3: Update call sites in `ThreadList`, `App`, and threads test</name>
  <files>
    lib/foglet_bbs/tui/screens/thread_list.ex,
    lib/foglet_bbs/tui/app.ex,
    test/foglet_bbs/threads/threads_test.exs
  </files>
  <action>
**`lib/foglet_bbs/tui/screens/thread_list.ex` — `annotate_fallback/1` (lines 178-184):**

Replace both clauses with a struct-building version. Add
`alias Foglet.Threads.ThreadEntry` near the top of the module (alongside existing aliases).
Then update `annotate_fallback/1`:

  ```elixir
  defp annotate_fallback(%Foglet.Threads.Thread{} = t) do
    %ThreadEntry{
      id: t.id,
      title: t.title,
      board_id: t.board_id,
      sticky: t.sticky,
      locked: t.locked,
      post_count: t.post_count,
      first_post_id: t.first_post_id,
      last_post_at: t.last_post_at,
      deleted_at: t.deleted_at,
      inserted_at: t.inserted_at,
      created_by_id: t.created_by_id,
      has_unread: false,
      created_by: t.created_by
    }
  end

  defp annotate_fallback(%{} = t) do
    struct(ThreadEntry, Map.put_new(t, :has_unread, false))
  end
  ```

The `render_thread_row/4` helpers use `Map.get(thread, :field, default)` — these work on
structs and do NOT need changes.

**`lib/foglet_bbs/tui/app.ex` — `load_threads_for_user/3` fallback branch (lines 651-661):**

Add `alias Foglet.Threads.ThreadEntry` near the top of the module. Replace the
`%Foglet.Threads.Thread{}` case branch:

  ```elixir
  %Foglet.Threads.Thread{} ->
    %ThreadEntry{
      id: t.id,
      title: t.title,
      board_id: t.board_id,
      sticky: t.sticky,
      locked: t.locked,
      post_count: t.post_count,
      first_post_id: t.first_post_id,
      last_post_at: t.last_post_at,
      deleted_at: t.deleted_at,
      inserted_at: t.inserted_at,
      created_by_id: t.created_by_id,
      has_unread: false,
      created_by: t.created_by
    }
  ```

Keep the `%{} ->` fallback clause as-is (it handles already-converted maps from test doubles):

  ```elixir
  %{} ->
    Map.put_new(t, :has_unread, false)
  ```

Optionally tighten `@type t` at line 49: change `current_thread: map() | nil` to
`current_thread: ThreadEntry.t() | nil` if the alias is being added to the module anyway.

**`test/foglet_bbs/threads/threads_test.exs`:**

In the test that asserts on `list_threads/2` return values (around line 269 where
`%Foglet.Accounts.User{handle: "mallory"} = t.created_by` is verified), add a struct-shape
assertion immediately before or after the field assertions:

  ```elixir
  assert %Foglet.Threads.ThreadEntry{} = t
  ```

This single line is sufficient to assert the return type is now a `ThreadEntry` struct.

**Final step:** Run `mix precommit` and fix any warnings, credo issues, or dialyzer
violations that emerge. Common issues to watch for:
- Unused alias warnings if ThreadEntry was already imported transitively
- Credo `alias` ordering (keep aliases alphabetical within each alias group)
  </action>
  <verify>
    <automated>mix test test/foglet_bbs/threads/threads_test.exs test/foglet_bbs/tui/screens/thread_list_test.exs test/foglet_bbs/tui/app_test.exs 2>&1 | tail -30 && mix precommit 2>&1 | tail -40</automated>
  </verify>
  <done>All three test files pass; `mix precommit` exits 0 with no warnings or credo violations.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| DB → `list_threads/2` | Ecto materializes raw maps from the `select:` query; struct conversion happens in application code |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-neu-01 | Information Disclosure | `ThreadEntry.created_by` | accept | Field only populated from batch-loaded `Foglet.Accounts.User` records already scoped to thread authors; no new data surface exposed |
| T-neu-02 | Tampering | `struct(ThreadEntry, raw_map)` conversion | accept | Raw map comes exclusively from `Repo.all` with a fixed `select:` projection; no user-supplied keys can reach the struct constructor |
</threat_model>

<verification>
1. `mix test test/foglet_bbs/threads/threads_test.exs` — threads context contract, including new `%ThreadEntry{}` shape assertion
2. `mix test test/foglet_bbs/tui/screens/thread_list_test.exs` — ThreadList rendering and dispatch unchanged
3. `mix test test/foglet_bbs/tui/app_test.exs` — App load_threads paths
4. `mix precommit` — compile (warnings-as-errors), format, credo --strict, sobelow, dialyzer
</verification>

<success_criteria>
- `lib/foglet_bbs/threads/thread_entry.ex` exists with `%Foglet.Threads.ThreadEntry{}` struct and `@type t`
- `Foglet.Threads.list_threads/2` spec reads `:: [ThreadEntry.t()]`
- `preload_created_by/1` uses `%{row | created_by: ...}` struct update syntax
- `annotate_no_user/1` builds `%ThreadEntry{}` explicitly from `%Thread{}` fields
- `ThreadList.annotate_fallback/1` builds `%ThreadEntry{}` for the `%Thread{}` clause
- `App.load_threads_for_user/3` fallback builds `%ThreadEntry{}` for the `%Thread{}` clause
- `threads_test.exs` has at least one `assert %ThreadEntry{} = t` assertion
- `mix precommit` exits 0
</success_criteria>

<output>
After completion, create `.planning/quick/260422-neu-convert-threads-list-threads-2-to-struct/260422-neu-SUMMARY.md`
using the summary template at `/Users/brendan.turner/Dev/personal/foglet_bbs/.claude/get-shit-done/templates/summary.md`.
</output>
