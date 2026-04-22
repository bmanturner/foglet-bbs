# Quick Research: Convert `Threads.list_threads/2` to structs + fold in `preload_created_by/1`

**Researched:** 2026-04-22
**Scope:** Targeted refactor research — return-type promotion, caller updates, dialyzer spec corrections.
**Confidence:** HIGH — all findings verified against repo source.

---

## Current State of `list_threads`

### `list_threads/1` (single-arity, board-only)

```elixir
@spec list_threads(String.t()) :: [Thread.t()]
def list_threads(board_id)
```

Returns raw `%Foglet.Threads.Thread{}` structs, `:created_by` preloaded via `Repo.preload`.
[VERIFIED: lib/foglet_bbs/threads.ex:41-49]

### `list_threads/2` (with user_id — the primary target)

```elixir
@spec list_threads(String.t(), String.t() | nil) :: [map()]
def list_threads(board_id, nil)      # delegates to /1, annotates with annotate_no_user/1
def list_threads(board_id, user_id)  # runs a custom SELECT ... query, calls preload_created_by/1
```

The `user_id` clause builds a bare `select:` map (not an Ecto struct), then calls the private
`preload_created_by/1` to batch-load users and `Map.put/3` `:created_by` onto each row.
The `nil` clause calls `annotate_no_user/1` which does `Map.from_struct/1 |> Map.put(:has_unread, false)`.

**Return type is currently `[map()]`** — an anonymous map with keys:
`id, title, board_id, sticky, locked, post_count, first_post_id, last_post_at, deleted_at,
inserted_at, created_by_id, has_unread, created_by`.

No struct exists yet for this shape. [VERIFIED: lib/foglet_bbs/threads.ex:71-124]

---

## What the Refactor Should Produce

Replace the anonymous map return with a named struct, e.g. `%Foglet.Threads.ThreadEntry{}`,
defined in a new file `lib/foglet_bbs/threads/thread_entry.ex`. The struct carries exactly the
fields the SQL select already projects plus `:has_unread` and `:created_by`.

**Proposed struct fields:**

| Field | Type | Source |
|-------|------|--------|
| `id` | `String.t()` | `t.id` |
| `title` | `String.t()` | `t.title` |
| `board_id` | `String.t()` | `t.board_id` |
| `sticky` | `boolean()` | `t.sticky` |
| `locked` | `boolean()` | `t.locked` |
| `post_count` | `non_neg_integer()` | `t.post_count` |
| `first_post_id` | `String.t() \| nil` | `t.first_post_id` |
| `last_post_at` | `DateTime.t() \| nil` | `t.last_post_at` |
| `deleted_at` | `DateTime.t() \| nil` | `t.deleted_at` |
| `inserted_at` | `DateTime.t()` | `t.inserted_at` |
| `created_by_id` | `String.t() \| nil` | `t.created_by_id` |
| `has_unread` | `boolean()` | computed / injected |
| `created_by` | `Foglet.Accounts.User.t() \| nil` | batch-loaded |

[ASSUMED] Naming: `ThreadEntry` is a reasonable candidate name to distinguish from `Thread` (the
Ecto schema). No existing struct for this shape was found in the repo.

---

## `preload_created_by/1` — Existing Private Function

```elixir
defp preload_created_by(rows) do
  created_by_ids = rows |> Enum.map(& &1.created_by_id) |> Enum.filter(& &1) |> Enum.uniq()
  users = ... Repo.all(from u in User, where: u.id in ^created_by_ids, select: {u.id, u}) |> Map.new()
  Enum.map(rows, fn row -> Map.put(row, :created_by, Map.get(users, row.created_by_id)) end)
end
```

Currently uses `Map.put/3` because rows are plain maps. After the refactor rows will be
`%ThreadEntry{}` structs, so `Map.put/3` must change to `%{row | created_by: ...}` struct
update syntax. The batch-query logic itself does not need to change.
[VERIFIED: lib/foglet_bbs/threads.ex:107-124]

---

## Callers That Need Updating

### 1. `Foglet.Threads` — internal

- `list_threads/2` body: change `select:` map literal to build a `%ThreadEntry{}` directly
  (or build it after the query). [VERIFIED: lib/foglet_bbs/threads.ex:85-105]
- `annotate_no_user/1`: currently calls `Map.from_struct/1 |> Map.put(:has_unread, false)`.
  Should build a `%ThreadEntry{}` from the `%Thread{}` fields instead. [VERIFIED: lib/foglet_bbs/threads.ex:126-130]
- `preload_created_by/1`: change `Map.put/3` to struct update `%{row | created_by: ...}`.
- `@spec list_threads(String.t(), String.t() | nil) :: [map()]` becomes `:: [ThreadEntry.t()]`.

### 2. `Foglet.TUI.Screens.ThreadList`

`render_thread_row/4` and all helpers use `Map.get(thread, :field, default)` — these work on
both maps and structs. However, `annotate_fallback/1` in `dispatch_thread_load/3` builds a plain
map via `Map.from_struct/1`. After the refactor the fallback should return `%ThreadEntry{}`.

`handle_key` Enter clause: `current_thread: thread` sets the selected thread from the list onto
`state.current_thread`. Downstream `PostReader` accesses `state.current_thread.id` and
`state.current_thread.title` via dot-access — these will continue to work on a struct.

Specific locations:
- `annotate_fallback/1` (line 178): builds plain map — update to build `%ThreadEntry{}`.
- `dispatch_thread_load/3` (lines 163-176): no change needed to the dispatch logic itself.
[VERIFIED: lib/foglet_bbs/tui/screens/thread_list.ex:163-184]

### 3. `Foglet.TUI.App`

`load_threads_for_user/3` (lines 646-666): the `/1` fallback branch does
`Map.from_struct/1 |> Map.put(:has_unread, false)` on `%Thread{}` structs — should build
`%ThreadEntry{}` instead. The `/2` branch delegates to `threads_mod.list_threads/2` and
trusts the return type; once `list_threads/2` returns `[ThreadEntry.t()]` no code change is
needed in the App for the 2-arity path. The 1-arity fallback path DOES need updating.
[VERIFIED: lib/foglet_bbs/tui/app.ex:646-666]

`@type t` for `App`: `current_thread: map() | nil` — after this refactor `current_thread` could
be typed more precisely as `ThreadEntry.t() | nil`, but that is optional for this task.
[VERIFIED: lib/foglet_bbs/tui/app.ex:49]

### 4. Tests

**`test/foglet_bbs/threads/threads_test.exs`**
Tests use `%{has_unread: ...}` pattern matching and `t.has_unread`, `t.title`, `t.created_by`
dot-access. All of these work on structs too — no test changes required unless dialyzer or
pattern matching on `%{...}` vs `%ThreadEntry{...}` is made strict. The test at line 269 asserts
`%Foglet.Accounts.User{handle: "mallory"} = t.created_by` — still valid. Recommend adding one
assertion that the return type is `%ThreadEntry{}`. [VERIFIED: test/foglet_bbs/threads/threads_test.exs]

**`test/foglet_bbs/tui/screens/thread_list_test.exs`**
Fake domain adapters return plain maps — these are used for TUI rendering tests only, so the
fakes do not need to be updated unless struct pattern-matching is added to `ThreadList` code.
Current `render_thread_row` uses only `Map.get(thread, :field, default)`, which works on both.
[VERIFIED: test/foglet_bbs/tui/screens/thread_list_test.exs:1-117]

---

## The `has_unread` Merge

Currently, `has_unread` is injected in two places:
1. **`list_threads/2` with `user_id`**: computed by the SQL `select:` expression (`not is_nil(t.last_post_at) and t.last_post_at > coalesce(...)`) and placed in the anonymous map directly.
2. **`list_threads/2` with `nil`**: `annotate_no_user/1` calls `Map.put(map, :has_unread, false)`.

After the refactor:
- The `select:` map literal becomes a `%ThreadEntry{}` constructor — `has_unread:` is a field, not a computed merge. Dialyzer will enforce the type.
- `annotate_no_user/1` builds a `%ThreadEntry{}` from `%Thread{}` fields with `has_unread: false`.

No separate "merge step" is needed — the struct constructor absorbs both injection sites.
[VERIFIED: lib/foglet_bbs/threads.ex:78-130]

---

## Struct File Location and Pattern

Established precedent (PostReader.State, NewThread.State, PostComposer.State):
- One struct per file.
- No module nesting.
- File lives under the module's directory: `lib/foglet_bbs/threads/thread_entry.ex`.
- Module name: `Foglet.Threads.ThreadEntry`.
- Provide `@type t :: %__MODULE__{...}` and a constructor if opts-based construction is needed
  (for this struct a plain `defstruct` is sufficient; no `new/1` constructor is required unless
  there is complex default logic).
[VERIFIED: lib/foglet_bbs/tui/screens/post_reader/state.ex; CLAUDE.md]

---

## Dialyzer / Type Spec Changes

| Location | Current spec | New spec |
|----------|-------------|----------|
| `Foglet.Threads.list_threads/2` | `[map()]` | `[ThreadEntry.t()]` |
| `Foglet.Threads.annotate_no_user/1` | implicit `map()` | `ThreadEntry.t()` |
| `Foglet.Threads.preload_created_by/1` | implicit `[map()]` | `[ThreadEntry.t()]` |

`App.@type t current_thread: map() | nil` — updating to `ThreadEntry.t() | nil` is optional
but recommended. [VERIFIED: lib/foglet_bbs/tui/app.ex:49]

---

## Common Pitfalls

### Pitfall 1: Ecto `select:` cannot return a non-Ecto struct directly

`from ... select: %ThreadEntry{...}` will fail at runtime because Ecto only knows how to
materialize its own schema structs from `select:`. The fix: keep the `select:` as a plain map,
then convert the results list with `Enum.map(&struct(ThreadEntry, &1))` (or a dedicated
`ThreadEntry.from_row/1` function) before calling `preload_created_by/1`.
[VERIFIED: Ecto documentation pattern — Ecto schema `select` only returns schema structs or
plain maps; raw `%SomeStruct{...}` in select: is not supported for non-schema modules]
[ASSUMED: confirmed by Ecto docs behavior, not re-verified in this session via Context7]

Preferred approach: keep the existing `select:` map unchanged, run `preload_created_by/1` on
the raw maps, then convert to structs in one final pass — or convert to struct inside
`preload_created_by/1` as its last step.

### Pitfall 2: Structs don't implement Access

Both `ThreadList` and `App` currently use `Map.get(thread, :field, default)` which works on
structs. But if any test or call site uses `thread[:field]` or `get_in(thread, [:field])`, it
will crash. Quick audit shows only `Map.get` is used — but verify with `grep -rn "thread\[" lib/`.
[VERIFIED: CLAUDE.md — "Structs don't implement Access"; grep scan shows no bracket access on
thread values in lib/]

### Pitfall 3: `annotate_no_user/1` uses `Map.from_struct/1`

Current code strips the `%Thread{}` to a plain map then adds `:has_unread`. After the refactor,
this must not use `Map.from_struct/1` blindly — it must select only the fields that `ThreadEntry`
declares (omitting Ecto internal fields like `__meta__`, `:board`, `:posts`, `:first_post`).
Build `%ThreadEntry{}` explicitly from `%Thread{}` field values.
[VERIFIED: lib/foglet_bbs/threads.ex:126-130; lib/foglet_bbs/threads/thread.ex]

---

## Surgical Change List

1. **New file `lib/foglet_bbs/threads/thread_entry.ex`** — define `%Foglet.Threads.ThreadEntry{}` with the 13 fields listed above plus `@type t`.
2. **`lib/foglet_bbs/threads.ex`**:
   - `alias Foglet.Threads.ThreadEntry`
   - Update `@spec list_threads/2` to `:: [ThreadEntry.t()]`
   - Keep `select:` map in `list_threads/2` user_id clause unchanged; after `Repo.all` convert to structs then call `preload_created_by/1`
   - Update `preload_created_by/1`: replace `Map.put(row, :created_by, ...)` with `%{row | created_by: ...}` (struct update)
   - Rewrite `annotate_no_user/1`: build `%ThreadEntry{...}` from `%Thread{}` fields explicitly
3. **`lib/foglet_bbs/tui/screens/thread_list.ex`**:
   - Update `annotate_fallback/1` (two clauses) to build `%ThreadEntry{}` instead of a plain map
4. **`lib/foglet_bbs/tui/app.ex`**:
   - Update the `%Foglet.Threads.Thread{}` fallback branch in `load_threads_for_user/3` to build `%ThreadEntry{}` instead of `Map.from_struct/1 |> Map.put`
   - (Optional) tighten `current_thread: map() | nil` to `ThreadEntry.t() | nil` in `@type t`
5. **Tests**: Add a `%ThreadEntry{}` shape assertion in `threads_test.exs`; TUI tests need no changes unless struct pattern matching is added.

---

## Validation

| Command | Purpose |
|---------|---------|
| `mix test test/foglet_bbs/threads/threads_test.exs` | Threads context contract |
| `mix test test/foglet_bbs/tui/screens/thread_list_test.exs` | ThreadList rendering + dispatch |
| `mix test test/foglet_bbs/tui/app_test.exs` | App load_threads path |
| `mix precommit` | Full suite + dialyzer + credo + sobelow |

---

## Assumptions Log

| # | Claim | Risk if Wrong |
|---|-------|---------------|
| A1 | `ThreadEntry` is a suitable name (no existing name in codebase) | Low — verified no existing struct; name is a convention choice |
| A2 | Ecto `select:` cannot materialize non-schema structs — conversion must happen post-query | Medium — if wrong, could use `select: %ThreadEntry{...}` directly, but this is well-established Ecto behavior |

---

## Sources

- `lib/foglet_bbs/threads.ex` — current `list_threads/1`, `list_threads/2`, `preload_created_by/1`, `annotate_no_user/1`
- `lib/foglet_bbs/threads/thread.ex` — `Thread` schema fields
- `lib/foglet_bbs/tui/screens/thread_list.ex` — `dispatch_thread_load/3`, `annotate_fallback/1`, `render_thread_row/4`
- `lib/foglet_bbs/tui/app.ex` — `load_threads_for_user/3`, `@type t`
- `lib/foglet_bbs/tui/screens/post_reader/state.ex` — struct file precedent
- `test/foglet_bbs/threads/threads_test.exs` — existing test assertions on return shape
- `test/foglet_bbs/tui/screens/thread_list_test.exs` — fake adapters and TUI tests
- `.planning/quick/260422-hfc-create-state-structs-for-newthread-and-p/260422-hfc-RESEARCH.md` — struct migration pattern precedent
- `CLAUDE.md` — "Structs don't implement Access" gotcha, no-nesting rule, `mix precommit` requirement
