---
phase: quick-260422-nsx
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - lib/foglet_bbs/tui/app.ex
autonomous: true
requirements: [quick-260422-nsx]

must_haves:
  truths:
    - "All 5 do_update clauses in app.ex resolve domain modules via Domain.get/2"
    - "No inline get_in(ctx, [:domain, key]) || FallbackMod expressions remain"
    - "The stale comment at lines 366-368 is removed"
    - "mix precommit passes with no new warnings or errors"
  artifacts:
    - path: "lib/foglet_bbs/tui/app.ex"
      provides: "Migrated do_update clauses + domain_module/2 helper"
      contains: "defp domain_module(state, key)"
  key_links:
    - from: "app.ex do_update clauses"
      to: "Foglet.TUI.Screens.Domain.get/2"
      via: "domain_module/2 private helper"
      pattern: "domain_module\\(state,"
---

<objective>
Migrate the 5 remaining inline domain-extraction blocks in `app.ex` to call `Domain.get/2`
through a new `domain_module/2` private helper, matching the pattern already established in
all screen modules.

Purpose: Eliminates the last instances of the legacy `get_in(ctx, [:domain, key]) || FallbackMod`
pattern in the codebase. After this task every domain-module lookup goes through the single
canonical path.

Output: Updated `lib/foglet_bbs/tui/app.ex` with alias, helper, and 5 migrated clauses.
</objective>

<execution_context>
@/Users/brendan.turner/Dev/personal/foglet_bbs/.claude/get-shit-done/workflows/execute-plan.md
@/Users/brendan.turner/Dev/personal/foglet_bbs/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@/Users/brendan.turner/Dev/personal/foglet_bbs/.planning/STATE.md

Reference implementation already in the codebase (do not re-implement, just mirror):

```elixir
# lib/foglet_bbs/tui/screens/board_list.ex — domain_module/2 reference
defp domain_module(state, :boards) do
  ctx = Map.get(state, :session_context) || %{}
  case Domain.get(ctx, :boards) do
    {:ok, mod} -> mod
    {:error, :not_configured} -> Foglet.Boards
  end
end
```

`Domain.get/2` contract (lib/foglet_bbs/tui/screens/domain.ex):
- Takes the **session_context map** directly (not state, not the :domain submap)
- Supported keys: `:boards`, `:threads`, `:posts`, `:markdown`
- Returns `{:ok, module()}` or `{:error, :not_configured}`
</context>

<tasks>

<task type="auto">
  <name>Task 1: Add alias + domain_module/2 helper to app.ex</name>
  <files>lib/foglet_bbs/tui/app.ex</files>
  <action>
Two changes to the module header / private-function area:

1. **Add alias** — in the existing alias block (lines 20-26), add:
   ```elixir
   alias Foglet.TUI.Screens.Domain
   ```
   Place it alphabetically: after `alias Foglet.TUI.PubSubForwarder`, before `alias Foglet.TUI.Screens`.

2. **Add private helpers** — insert after the last `defp do_update` clause (before any unrelated
   private functions, or near the bottom of the private section). Use the key-dispatch approach
   to keep each fallback explicit and dialyzer-happy:

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

No other changes in this task.
  </action>
  <verify>
    <automated>grep -n "alias Foglet.TUI.Screens.Domain\|defp domain_module\|defp default_domain_module" /Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/app.ex</automated>
  </verify>
  <done>
    Output shows alias on one line and both helper definitions present. `mix compile` (run after
    Task 2) confirms no compilation errors introduced by the helper alone.
  </done>
</task>

<task type="auto">
  <name>Task 2: Migrate 5 do_update clauses to domain_module/2</name>
  <files>lib/foglet_bbs/tui/app.ex</files>
  <action>
Replace the inline domain extraction in each of the 5 clauses below. For every clause:
- Remove the `ctx = Map.get(state, :session_context) || %{}` line **if it is used only for domain extraction** (keep it if it is also used for other purposes in the same clause).
- Remove the `_mod = get_in(ctx, [:domain, :key]) || FallbackMod` line.
- Replace with `_mod = domain_module(state, :key)`.

**Clause 1 — `{:load_boards}` (approx. line 364)**

Before:
```elixir
defp do_update({:load_boards}, state) do
  # Snapshot what we need inside the closure so we don't capture the whole state.
  # Intentionally not using Domain.get/2 — do_update closures snapshot the domain
  # module directly so the task closure captures only the atom, not the full state map.
  # Tracked for migration in a future phase.
  user = state.current_user
  ctx = Map.get(state, :session_context) || %{}
  boards_mod = get_in(ctx, [:domain, :boards]) || Foglet.Boards
```

After:
```elixir
defp do_update({:load_boards}, state) do
  # Snapshot the module atom before entering the closure so the task captures only
  # the atom, not the full state map.
  user = state.current_user
  boards_mod = domain_module(state, :boards)
```

(Remove the 3-line stale comment entirely — it documented the deliberate *non-use* of
Domain.get/2 which is now reversed.)

**Clause 2 — `{:load_boards_for_new_thread}` (approx. line 385)**

Before:
```elixir
defp do_update({:load_boards_for_new_thread}, state) do
  user = state.current_user
  ctx = Map.get(state, :session_context) || %{}
  boards_mod = get_in(ctx, [:domain, :boards]) || Foglet.Boards
```

After:
```elixir
defp do_update({:load_boards_for_new_thread}, state) do
  user = state.current_user
  boards_mod = domain_module(state, :boards)
```

**Clause 3 — `{:load_threads, board_id}` (approx. line 411)**

Before:
```elixir
defp do_update({:load_threads, board_id}, state) do
  ctx = Map.get(state, :session_context) || %{}
  threads_mod = get_in(ctx, [:domain, :threads]) || Foglet.Threads
  user_id = state.current_user && state.current_user.id
```

After:
```elixir
defp do_update({:load_threads, board_id}, state) do
  threads_mod = domain_module(state, :threads)
  user_id = state.current_user && state.current_user.id
```

**Clause 4 — `{:load_posts, thread_id, opts}` (approx. line 435)**

Before:
```elixir
defp do_update({:load_posts, thread_id, opts}, state) when is_list(opts) do
  ctx = Map.get(state, :session_context) || %{}
  posts_mod = get_in(ctx, [:domain, :posts]) || Foglet.Posts
```

After:
```elixir
defp do_update({:load_posts, thread_id, opts}, state) when is_list(opts) do
  posts_mod = domain_module(state, :posts)
```

**Clause 5 — `{:flush_read_pointers, ctx}` (approx. line 495)**

NAMING CAUTION: In this clause `ctx` is bound to the flush-data bag (the message argument),
NOT to session_context. The session_context local is `sc`. After migration, keep using `state`
as the argument to `domain_module/2` — NOT `ctx` or `sc`.

Before:
```elixir
defp do_update({:flush_read_pointers, ctx}, state) do
  # Flush runs off-process so it doesn't block the UI on the way out of a thread.
  sc = Map.get(state, :session_context) || %{}
  boards_mod = get_in(sc, [:domain, :boards]) || Foglet.Boards
  threads_mod = get_in(sc, [:domain, :threads]) || Foglet.Threads
  user_id = ctx[:user_id] || (state.current_user && state.current_user.id)
```

After:
```elixir
defp do_update({:flush_read_pointers, ctx}, state) do
  # Flush runs off-process so it doesn't block the UI on the way out of a thread.
  boards_mod = domain_module(state, :boards)
  threads_mod = domain_module(state, :threads)
  user_id = ctx[:user_id] || (state.current_user && state.current_user.id)
```

(The `sc` local is no longer needed after this change — remove it.)

After all 5 edits, run `mix precommit` and fix any issues it surfaces.
  </action>
  <verify>
    <automated>grep -c "get_in.*:domain" /Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/app.ex</automated>
  </verify>
  <done>
    The grep count is 0 (no remaining `get_in(_, [:domain, _])` expressions in app.ex).
    `mix precommit` exits 0 with no errors or new warnings.
  </done>
</task>

</tasks>

<verification>
```bash
# 1. No legacy domain-extraction lines remain
grep -n "get_in.*:domain" /Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/app.ex
# Expected: no output

# 2. Helper and alias present
grep -n "alias Foglet.TUI.Screens.Domain\|defp domain_module\|defp default_domain_module" /Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/app.ex

# 3. Full precommit
cd /Users/brendan.turner/Dev/personal/foglet_bbs && mix precommit
```
</verification>

<success_criteria>
- Zero occurrences of `get_in(_, [:domain, _])` in `app.ex`
- `domain_module/2` and `default_domain_module/1` private helpers present
- `alias Foglet.TUI.Screens.Domain` present in alias block
- Stale 3-line comment (lines 366-368) removed
- `mix precommit` exits 0
</success_criteria>

<output>
After completion, create `.planning/quick/260422-nsx-dual-domain-injection-patterns-in-the-tu/260422-nsx-SUMMARY.md` using the summary template.
</output>
