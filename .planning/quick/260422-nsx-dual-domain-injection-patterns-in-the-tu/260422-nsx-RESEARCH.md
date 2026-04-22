# Quick Task 260422-nsx: Dual Domain-Injection Pattern Research

**Researched:** 2026-04-22
**Domain:** `Foglet.TUI.App` / `Foglet.TUI.Screens.Domain`
**Confidence:** HIGH (all findings verified directly from source)

---

## Summary

The "dual domain-injection" pattern refers to the **inline domain-module extraction** style used
inside five `do_update` clauses in `lib/foglet_bbs/tui/app.ex`. Each clause manually extracts
`session_context`, calls `get_in(ctx, [:domain, :key])`, and falls back to the real module — the
same logic that `Domain.get/2` already encapsulates. Screen modules (`BoardList`, `ThreadList`,
`PostReader`, `PostComposer`, `NewThread`) have already been migrated to call `Domain.get/2`
through private helpers. The `app.ex` I/O-dispatch clauses were explicitly deferred (see the
comment at line 366) and are the sole remaining migration target.

The scope is **5 do_update clauses** (6 extraction lines), not ~30. All 33 `defp do_update`
clauses live in `app.ex`; 28 do not touch domain at all.

**Primary recommendation:** Replace each `get_in(ctx/sc, [:domain, :key]) || FallbackMod`
block with a `domain_module/2` private helper that calls `Domain.get/2` — matching the pattern
already established in the screen modules.

---

## 1. What "Dual Domain-Injection" Means Here

The name captures two simultaneous injection paths for the domain module:

| Path | Code | Problem |
|------|------|---------|
| Old (app.ex) | `get_in(ctx, [:domain, :boards]) \|\| Foglet.Boards` | Bypasses `Domain.get/2`, duplicates nil-handling and fallback logic inline |
| New (screens) | `Domain.get(ctx, :key)` + `{:ok, m} -> m / {:error, _} -> Fallback` | Single canonical lookup, testable via `session_context` injection |

Both paths reach the same data (`state.session_context[:domain][key]`), but the old path was
written before `Domain.get/2` existed and was intentionally left for a later cleanup pass.

---

## 2. `Domain.get/2` Contract

**Source:** `lib/foglet_bbs/tui/screens/domain.ex` [VERIFIED: source]

```elixir
@supported_keys [:boards, :threads, :posts, :markdown]
@spec get(map(), domain_key()) :: {:ok, module()} | {:error, :not_configured}

def get(ctx, key) when key in @supported_keys do
  case get_in(ctx, [:domain, key]) do
    mod when is_atom(mod) and not is_nil(mod) -> {:ok, mod}
    _ -> {:error, :not_configured}
  end
end

def get(_ctx, _key), do: {:error, :not_configured}
```

Key contract details:
- Takes the **session_context map directly** — not `state`, not the full `[:domain]` submap.
- Unknown keys always return `{:error, :not_configured}` (no raise, no crash).
- The `is_atom(mod) and not is_nil(mod)` guard is stricter than the old `|| Fallback` approach:
  the old code would also fall through on `false` or `0`; `Domain.get/2` only accepts real atoms.

---

## 3. The Five Affected Clauses

All located in `lib/foglet_bbs/tui/app.ex`: [VERIFIED: source grep]

| Clause | Line | Keys Extracted | Variable Name for ctx |
|--------|------|---------------|----------------------|
| `{:load_boards}` | 364 | `:boards` | `ctx` |
| `{:load_boards_for_new_thread}` | 385 | `:boards` | `ctx` |
| `{:load_threads, board_id}` | 411 | `:threads` | `ctx` |
| `{:load_posts, thread_id, opts}` | 435 | `:posts` | `ctx` |
| `{:flush_read_pointers, ctx}` | 495 | `:boards`, `:threads` | `sc` (note: `ctx` is taken by the message arg) |

The `{:flush_read_pointers, ctx}` clause is the only one where the session_context local is
named `sc` rather than `ctx` — because the clause head uses `ctx` for the flush-data bag
argument. This naming collision must be preserved post-migration.

---

## 4. Current vs. Target Pattern

### Current (inline, in app.ex)

```elixir
defp do_update({:load_boards}, state) do
  user = state.current_user
  ctx = Map.get(state, :session_context) || %{}
  boards_mod = get_in(ctx, [:domain, :boards]) || Foglet.Boards

  task = Foglet.TUI.Command.task(:load_boards, fn ->
    {:boards_loaded, boards_mod.list_subscribed_boards(user)}
  end)
  {state, [task]}
end
```

### Target (using Domain.get/2, matching screen pattern)

The screen modules use a private helper that takes `state`:

```elixir
# From board_list.ex (already migrated) — [VERIFIED: source]
defp domain_module(state, :boards) do
  ctx = Map.get(state, :session_context) || %{}
  case Domain.get(ctx, :boards) do
    {:ok, mod} -> mod
    {:error, :not_configured} -> Foglet.Boards
  end
end
```

Applied to `app.ex`:

```elixir
defp do_update({:load_boards}, state) do
  user = state.current_user
  boards_mod = domain_module(state, :boards)

  task = Foglet.TUI.Command.task(:load_boards, fn ->
    {:boards_loaded, boards_mod.list_subscribed_boards(user)}
  end)
  {state, [task]}
end
```

The closure still captures only `boards_mod` (the atom) rather than `state`, preserving the
comment's stated intent at line 365-368.

---

## 5. Already-Migrated Examples (Reference Implementations)

These are the canonical call-site patterns to copy: [VERIFIED: source]

| Module | Helper name | Keys |
|--------|-------------|------|
| `Screens.BoardList` | `domain_module(state, :boards)` | `:boards` |
| `Screens.NewThread` | `threads_module(state)` | `:threads` |
| `Screens.ThreadList` | `resolve_threads_module(ctx)` | `:threads` |
| `Screens.PostReader` | inline `case Domain.get(ctx, :posts)` | `:posts`, `:boards`, `:threads`, `:markdown` |
| `Screens.PostComposer` | inline `case Domain.get(sc, :posts)` | `:posts` |

The naming varies across screens (some take `state`, some take the pre-extracted `ctx`). For
`app.ex`, a single private helper `domain_module(state, key)` taking `state` is the cleanest
approach — it mirrors `board_list.ex` exactly and avoids a second local variable at each call
site. `alias Foglet.TUI.Screens.Domain` is needed at the top of `app.ex`.

---

## 6. Pitfalls and Gotchas

### P1: `:flush_read_pointers` naming collision
The clause `defp do_update({:flush_read_pointers, ctx}, state)` binds `ctx` to the flush-data
bag, not to `session_context`. The session_context local is already named `sc`. After migration,
the helper call must pass `state` (not `ctx` or `sc`) so the helper can safely extract
`state.session_context`. No logic change — just naming discipline.

### P2: The old comment at line 366 must be removed
Lines 365-368 document the *deliberate decision not to use Domain.get/2*. After migration that
comment becomes misleading. The new comment (if any) should simply note the closure captures the
module atom for efficiency.

### P3: `Domain.get/2` doesn't accept `nil`
`Map.get(state, :session_context) || %{}` is still needed before calling `Domain.get/2` because
`session_context` could theoretically be nil in tests that construct bare state structs. The
screen helpers all preserve this guard — follow the same pattern in `app.ex`.

### P4: Alias is not yet present in app.ex
`Foglet.TUI.Screens.Domain` is not aliased in `app.ex`. The `alias` line must be added to the
module's alias block alongside the existing `alias Foglet.TUI.Screens`.

### P5: The scope is 5 clauses, not ~30
The task description said "~30 do_update clauses" — that is the total count of `defp do_update`
definitions. Only 5 of them do domain extraction. The remaining 28 clauses need no changes.

### P6: `precommit` will catch regressions
`mix precommit` runs `dialyzer`, which will flag a bad `Domain.get/2` invocation (wrong arity,
wrong key atom) at the type level. Run after each clause migration.

---

## 7. Structural Change Summary

For each of the 5 clauses:

1. Remove the `ctx = Map.get(state, :session_context) || %{}` line (if only used for domain).
2. Remove the `_mod = get_in(ctx, [:domain, :key]) || FallbackMod` line.
3. Replace with `_mod = domain_module(state, :key)`.
4. In `:flush_read_pointers`, `sc` is still needed because the clause must read two keys —
   one call per key, or inline both `domain_module(state, :boards)` and
   `domain_module(state, :threads)`.

Add once at the module level:
- `alias Foglet.TUI.Screens.Domain`
- Private helper:
  ```elixir
  defp domain_module(state, key) do
    ctx = Map.get(state, :session_context) || %{}
    case Domain.get(ctx, key) do
      {:ok, mod} -> mod
      {:error, :not_configured} -> default_domain_module(key)
    end
  end

  defp default_domain_module(:boards), do: Foglet.Boards
  defp default_domain_module(:threads), do: Foglet.Threads
  defp default_domain_module(:posts), do: Foglet.Posts
  defp default_domain_module(:markdown), do: Foglet.Markdown
  ```

  Alternatively, a single-arity helper per key (mirroring BoardList) is also acceptable — the
  choice is Claude's discretion.

---

## Sources

- `lib/foglet_bbs/tui/app.ex` — all `defp do_update` clauses, lines 250-641
- `lib/foglet_bbs/tui/screens/domain.ex` — `Domain.get/2` contract
- `lib/foglet_bbs/tui/screens/board_list.ex` — `domain_module/2` reference implementation
- `lib/foglet_bbs/tui/screens/new_thread.ex` — `threads_module/1` reference implementation
- `lib/foglet_bbs/tui/screens/thread_list.ex` — `resolve_threads_module/1` reference implementation
- `lib/foglet_bbs/tui/screens/post_reader.ex` — multi-key inline pattern reference
- `lib/foglet_bbs/tui/screens/post_composer.ex` — inline pattern reference
