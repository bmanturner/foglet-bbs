# Phase 0: Cross-cutting extractions (prelude) — Pattern Map

**Mapped:** 2026-04-21
**Files analyzed:** 16 (2 new, 2 new test, 12 migration targets)
**Analogs found:** 16 / 16

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `lib/foglet_bbs/tui/theme.ex` | module-extend | request-response (pure fn) | self — sibling `default/0` and `resolve/1` | exact |
| `test/foglet_bbs/tui/theme_test.exs` | test (create new) | unit | `test/foglet_bbs/tui/screens/board_list_test.exs` | role-match |
| `lib/foglet_bbs/tui/screens/domain.ex` | new module | request-response (pure fn) | `lib/foglet_bbs/tui/theme.ex` (registry/lookup style) | role-match |
| `test/foglet_bbs/tui/screens/domain_test.exs` | test (create new) | unit | `test/foglet_bbs/tui/screens/board_list_test.exs` | role-match |
| `lib/foglet_bbs/tui/screens/login.ex` | screen migrate | request-response | self — theme line :36 is the canonical example | exact |
| `lib/foglet_bbs/tui/screens/register.ex` | screen migrate | request-response | `login.ex:36` pattern | exact |
| `lib/foglet_bbs/tui/screens/verify.ex` | screen migrate | request-response | `login.ex:36` pattern | exact |
| `lib/foglet_bbs/tui/screens/main_menu.ex` | screen migrate | request-response | `login.ex:36` pattern | exact |
| `lib/foglet_bbs/tui/screens/board_list.ex` | screen migrate (theme + domain) | request-response | `login.ex:36` + `board_list.ex:113` | exact |
| `lib/foglet_bbs/tui/screens/thread_list.ex` | screen migrate (theme + domain) | request-response | `login.ex:36` + `thread_list.ex:132` | exact |
| `lib/foglet_bbs/tui/screens/new_thread.ex` | screen migrate (2 theme + 1 domain) | request-response | `login.ex:36` pattern × 2 | exact |
| `lib/foglet_bbs/tui/screens/post_reader.ex` | screen migrate (2 theme + 4 domain) | request-response | `login.ex:36` + multi-domain pattern | exact |
| `lib/foglet_bbs/tui/screens/post_composer.ex` | screen migrate (theme + domain) | request-response | `login.ex:36` pattern | exact |
| `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex` | chrome migrate | request-response | `screen_frame.ex:34` (self) | exact |
| `lib/foglet_bbs/tui/widgets/chrome/size_gate.ex` | chrome migrate (Kernel.\|\| variant) | request-response | `size_gate.ex:67-70` (self) | exact |
| `lib/foglet_bbs/tui/app.ex` | app migrate (modal overlay only) | request-response | `app.ex:170` (self) | exact |

---

## Pattern Assignments

---

### File 1: `lib/foglet_bbs/tui/theme.ex`
**Role:** module-extend (add `from_state/1`)
**Plan:** 00-01
**Closest analog:** self — `default/0` at lines 227–229, `resolve/1` at lines 231–248

**Pattern to mirror:** Insert `from_state/1` between `default/0` and `resolve/1`. Match the single-line `@doc` / `@spec` / one-expression `def` style of `default/0`. Use a `case` instead of bare `|| ` to correctly handle a `nil` `session_context` (avoids the gotcha where `nil |> Map.get(:theme)` crashes).

### Before (current code — insertion point context)

```elixir
# lib/foglet_bbs/tui/theme.ex:227-233
@doc "Default theme (`:gray`) for v1.0.1."
@spec default() :: t()
def default, do: resolve(:gray)

@doc "Returns a flat `%Foglet.TUI.Theme{}` snapshot for the given id."
@spec resolve(atom()) :: t()
def resolve(id) when is_atom(id) do
```

### After (target code — new function inserted between default/0 and resolve/1)

```elixir
@doc "Default theme (`:gray`) for v1.0.1."
@spec default() :: t()
def default, do: resolve(:gray)

@doc """
Extracts the active theme from the Raxol app state.

Reads `state.session_context.theme`, which is a `%Foglet.TUI.Theme{}`
set by `Foglet.Sessions.Session` at login. Falls back to `default/0`
when `session_context` is absent or does not contain a `:theme` key.

Call this at the top of every `render/1` and render helper that needs
color slots. Do NOT call `default/0` directly from screen code.
"""
@spec from_state(map()) :: t()
def from_state(state) do
  case Map.get(state, :session_context) do
    nil -> default()
    ctx -> Map.get(ctx, :theme) || default()
  end
end

@doc "Returns a flat `%Foglet.TUI.Theme{}` snapshot for the given id."
@spec resolve(atom()) :: t()
def resolve(id) when is_atom(id) do
```

### Pattern notes

- The `case` form is necessary: `(nil || %{}) |> Map.get(:theme) || default()` would also work, but `case` is more readable and avoids the Elixir block-rebinding gotcha if the body were ever expanded.
- `Map.get(ctx, :theme) || default()` correctly handles both `nil` and missing-key cases because `Map.get/2` returns `nil` for a missing key, and `nil || default()` evaluates to `default()`.
- No new alias is required; `default/0` is already in scope within the same module.
- Place the new function between `default/0` and `resolve/1` so the public API section reads: `register_all/0` → `ids/0` → `default/0` → `from_state/1` → `resolve/1`.

---

### File 2: `test/foglet_bbs/tui/theme_test.exs`
**Role:** test (create new file)
**Plan:** 00-01
**Closest analog:** `test/foglet_bbs/tui/screens/board_list_test.exs` (async: true, Map.from_struct pattern, inline setup)

**Pattern to mirror:** `use ExUnit.Case, async: true`, `alias` at top, `describe` per function, explicit inline state construction (no shared factory). No `setup` block needed since `Theme.from_state/1` accepts plain maps — fixtures are inline in each test body.

### Before (current code)

```elixir
# FILE DOES NOT EXIST — create fresh
```

### After (target code)

```elixir
defmodule Foglet.TUI.ThemeTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Theme

  describe "default/0" do
    test "returns a %Theme{} struct" do
      assert %Theme{} = Theme.default()
    end
  end

  describe "from_state/1" do
    test "returns the theme struct from state.session_context.theme" do
      theme = %Theme{primary: %{fg: "#ff0000"}}
      state = %{session_context: %{theme: theme}}
      assert Theme.from_state(state) == theme
    end

    test "returns Theme.default() when session_context key is absent" do
      assert Theme.from_state(%{}) == Theme.default()
    end

    test "returns Theme.default() when session_context is nil" do
      assert Theme.from_state(%{session_context: nil}) == Theme.default()
    end

    test "returns Theme.default() when :theme key is absent from session_context" do
      assert Theme.from_state(%{session_context: %{}}) == Theme.default()
    end

    test "returns Theme.default() when :theme value is nil" do
      assert Theme.from_state(%{session_context: %{theme: nil}}) == Theme.default()
    end
  end
end
```

### Pattern notes

- `use ExUnit.Case, async: true` — all TUI unit tests in this project are async-safe. Theme is a pure module with no process state.
- No `setup` block needed: `from_state/1` takes a plain map; each test constructs its own inline state.
- `describe "default/0"` block is included so the file is not a one-function stub — the `default/0` smoke test also ensures `resolve/1` boots cleanly in a test context (the `static_slots/1` fallback path).
- Do NOT use `%Foglet.TUI.App{}` struct + `Map.from_struct/1` here — the helper accepts any map, and struct construction adds noise.

---

### File 3: `lib/foglet_bbs/tui/screens/domain.ex`
**Role:** new module
**Plan:** 00-02
**Closest analog:** `lib/foglet_bbs/tui/theme.ex` — moduledoc style, `@type`/`@spec` surface, single-responsibility lookup

**Pattern to mirror:** moduledoc with numbered responsibilities list + key reference table + footer function name. `@type` for the return type. `@spec` on the public function. Single `def get/2` with a `case` over `Map.get(ctx, :domain)` guarded by allowed keys. No `defstruct`, no `alias` needed.

### Before (current code)

```elixir
# FILE DOES NOT EXIST — create fresh
```

### After (target code)

```elixir
defmodule Foglet.TUI.Screens.Domain do
  @moduledoc """
  Domain-module lookup helper for Foglet BBS TUI screens.

  One responsibility:

  1. **Lookup** — Given a `session_context` map and a domain key atom,
     returns the configured domain module or `{:error, :not_configured}`
     when the key is absent or the domain is not set up.

  Supported keys (locked in AUDIT-02):
    :boards, :threads, :posts, :markdown

  Callers provide `state.session_context` (the narrower input).
  Each call site is responsible for its own default-module fallback
  via an explicit `{:error, :not_configured}` branch. This keeps
  defaults visible and test-injectable at the call site.

  See `Foglet.TUI.Screens.BoardList`, `ThreadList`, `PostReader`,
  `PostComposer`, `NewThread` for call-site examples.
  """

  @supported_keys [:boards, :threads, :posts, :markdown]

  @type domain_key :: :boards | :threads | :posts | :markdown
  @type result :: {:ok, module()} | {:error, :not_configured}

  @doc """
  Returns `{:ok, module}` when `ctx` contains a domain module configured
  for `key`, or `{:error, :not_configured}` otherwise.

  `key` must be one of #{inspect(@supported_keys)}. Unknown keys always
  return `{:error, :not_configured}` — no raise.
  """
  @spec get(map(), domain_key()) :: result()
  def get(ctx, key) when key in @supported_keys do
    case get_in(ctx, [:domain, key]) do
      nil -> {:error, :not_configured}
      mod -> {:ok, mod}
    end
  end

  def get(_ctx, _key), do: {:error, :not_configured}
end
```

### Pattern notes

- Moduledoc style mirrors `theme.ex`: one-sentence purpose, numbered responsibilities list (just one here), key reference, footer with call-site pointers.
- Two-clause `get/2`: first clause pattern-matches `key in @supported_keys` (guards allowed keys); catch-all returns `{:error, :not_configured}` for unknown keys. This is cleaner than a nested `case` and lets the compiler emit a warning if a new key is added to `@supported_keys` without updating the clause.
- `get_in(ctx, [:domain, key])` returns `nil` for both "`:domain` key absent" and "specific key absent" — both map to `{:error, :not_configured}`. No separate clause needed.
- Do NOT add `Code.ensure_loaded/1` — per D-02, configured modules are trusted.
- No `alias` needed in this file — the module is self-contained.
- Never nest multiple modules in the same file (CLAUDE.md gotcha).

---

### File 4: `test/foglet_bbs/tui/screens/domain_test.exs`
**Role:** test (create new file)
**Plan:** 00-02
**Closest analog:** `test/foglet_bbs/tui/screens/board_list_test.exs` (async: true, inline module stubs, describe per function)

**Pattern to mirror:** `use ExUnit.Case, async: true`, `alias` at top, `describe "get/2"` block, inline module atoms as stubs (no `defmodule` stubs needed — Elixir allows passing any atom as a module reference since `Domain.get/2` does no `Code.ensure_loaded/1`).

### Before (current code)

```elixir
# FILE DOES NOT EXIST — create fresh
```

### After (target code)

```elixir
defmodule Foglet.TUI.Screens.DomainTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Screens.Domain

  describe "get/2" do
    test "returns {:ok, module} when key is configured" do
      ctx = %{domain: %{boards: SomeBoardsMod}}
      assert Domain.get(ctx, :boards) == {:ok, SomeBoardsMod}
    end

    test "returns {:ok, module} for all four supported keys" do
      ctx = %{domain: %{boards: ModB, threads: ModT, posts: ModP, markdown: ModM}}
      assert Domain.get(ctx, :boards) == {:ok, ModB}
      assert Domain.get(ctx, :threads) == {:ok, ModT}
      assert Domain.get(ctx, :posts) == {:ok, ModP}
      assert Domain.get(ctx, :markdown) == {:ok, ModM}
    end

    test "returns {:error, :not_configured} when ctx is an empty map" do
      assert Domain.get(%{}, :boards) == {:error, :not_configured}
    end

    test "returns {:error, :not_configured} when :domain key is absent" do
      assert Domain.get(%{other: :data}, :boards) == {:error, :not_configured}
    end

    test "returns {:error, :not_configured} when the specific key is absent from :domain" do
      ctx = %{domain: %{threads: ModT}}
      assert Domain.get(ctx, :boards) == {:error, :not_configured}
    end

    test "returns {:error, :not_configured} for unknown keys" do
      ctx = %{domain: %{unknown_key: SomeMod}}
      assert Domain.get(ctx, :unknown_key) == {:error, :not_configured}
    end
  end
end
```

### Pattern notes

- Bare module atoms (`SomeBoardsMod`, `ModB`, etc.) are valid Elixir module references. Since `Domain.get/2` performs no `Code.ensure_loaded/1`, these atoms do not need to refer to real modules. This avoids the need for inline `defmodule` stubs.
- `describe "get/2"` mirrors the project convention of one `describe` block per public function.
- No `setup` block needed — all state is inline per test.
- The `test/foglet_bbs/tui/screens/` directory already exists; no directory creation needed.

---

## Files 5–16: 00-03-PLAN Migration Targets

The migration pattern for all 14 in-scope theme sites is identical (one-line replacement). Domain sites each require a `case` expansion. Shared replacement rules are shown once in the Shared Patterns section below; per-file sections record only the exact before/after at each site.

---

### File 5: `lib/foglet_bbs/tui/screens/login.ex`
**Role:** screen migrate (1 theme site)
**Plan:** 00-03
**Theme site:** T-01 at line 36
**Alias check:** `alias Foglet.TUI.Theme` already present at line 22 — no alias change needed.

#### Before (line 36)

```elixir
theme = (Map.get(state, :session_context) || %{}) |> Map.get(:theme) || Theme.default()
```

#### After (line 36)

```elixir
theme = Theme.from_state(state)
```

### Pattern notes

- Single-line replacement. Diff touches exactly one line.
- No other changes to `login.ex` in this plan.

---

### File 6: `lib/foglet_bbs/tui/screens/register.ex`
**Role:** screen migrate (1 theme site)
**Plan:** 00-03
**Theme site:** T-02 at line 30
**Alias check:** Must confirm `alias Foglet.TUI.Theme` is present in `register.ex` before committing.

#### Before (line 30)

```elixir
theme = (Map.get(state, :session_context) || %{}) |> Map.get(:theme) || Theme.default()
```

#### After (line 30)

```elixir
theme = Theme.from_state(state)
```

### Pattern notes

- Single-line replacement at line 30 only.
- The `credo:disable-for-next-line` at line 199 is 169 lines away and must NOT be touched.
- Diff for `register.ex` must show exactly one changed line.

---

### File 7: `lib/foglet_bbs/tui/screens/verify.ex`
**Role:** screen migrate (1 theme site)
**Plan:** 00-03
**Theme site:** T-03 at line 41

#### Before (line 41)

```elixir
theme = (Map.get(state, :session_context) || %{}) |> Map.get(:theme) || Theme.default()
```

#### After (line 41)

```elixir
theme = Theme.from_state(state)
```

### Pattern notes

- Single-line replacement. Confirm `alias Foglet.TUI.Theme` is present.

---

### File 8: `lib/foglet_bbs/tui/screens/main_menu.ex`
**Role:** screen migrate (1 theme site)
**Plan:** 00-03
**Theme site:** T-04 at line 18

#### Before (line 18)

```elixir
theme = (Map.get(state, :session_context) || %{}) |> Map.get(:theme) || Theme.default()
```

#### After (line 18)

```elixir
theme = Theme.from_state(state)
```

### Pattern notes

- Single-line replacement. Confirm `alias Foglet.TUI.Theme` is present.

---

### File 9: `lib/foglet_bbs/tui/screens/board_list.ex`
**Role:** screen migrate (1 theme site T-05 + 1 domain site D-01)
**Plan:** 00-03
**Theme site:** T-05 at line 18
**Domain site:** D-01 at lines 111–114 (inside `defp domain_module/2`)

#### Theme — Before (line 18)

```elixir
theme = (Map.get(state, :session_context) || %{}) |> Map.get(:theme) || Theme.default()
```

#### Theme — After (line 18)

```elixir
theme = Theme.from_state(state)
```

#### Domain — Before (lines 111–114)

```elixir
defp domain_module(state, :boards) do
  ctx = Map.get(state, :session_context) || %{}
  get_in(ctx, [:domain, :boards]) || Foglet.Boards
end
```

#### Domain — After (lines 111–117)

```elixir
defp domain_module(state, :boards) do
  ctx = Map.get(state, :session_context) || %{}
  case Screens.Domain.get(ctx, :boards) do
    {:ok, mod} -> mod
    {:error, :not_configured} -> Foglet.Boards
  end
end
```

### Pattern notes

- Add `alias Foglet.TUI.Screens.Domain, as: Screens.Domain` — or simply `alias Foglet.TUI.Screens` and call `Screens.Domain.get/2`. Verify which alias form is used consistently in board_list.ex already. If no `Foglet.TUI.Screens` alias exists, add `alias Foglet.TUI.Screens.Domain` and call `Domain.get/2`.
- The `defp domain_module/2` function signature and its caller at line 88 (`boards_mod = domain_module(state, :boards)`) are preserved exactly — do NOT refactor the helper away.
- Domain migration adds 3 lines to `domain_module/2`. Acceptable per AUDIT-13(a) exception.

---

### File 10: `lib/foglet_bbs/tui/screens/thread_list.ex`
**Role:** screen migrate (1 theme site T-06 + 1 domain site D-02)
**Plan:** 00-03
**Theme site:** T-06 at line 20
**Domain site:** D-02 at lines 131–133 (inside `def load_threads/2`)

#### Theme — Before (line 20)

```elixir
theme = (Map.get(state, :session_context) || %{}) |> Map.get(:theme) || Theme.default()
```

#### Theme — After (line 20)

```elixir
theme = Theme.from_state(state)
```

#### Domain — Before (lines 131–133)

```elixir
ctx = Map.get(state, :session_context) || %{}
threads_mod = get_in(ctx, [:domain, :threads]) || Foglet.Threads
```

#### Domain — After (lines 131–136)

```elixir
ctx = Map.get(state, :session_context) || %{}
threads_mod =
  case Domain.get(ctx, :threads) do
    {:ok, mod} -> mod
    {:error, :not_configured} -> Foglet.Threads
  end
```

### Pattern notes

- Add `alias Foglet.TUI.Screens.Domain` to `thread_list.ex`'s alias block.
- `load_threads/2` has a `cond` block after line 133 that uses `function_exported?(threads_mod, ...)`. The `threads_mod` variable must be resolved BEFORE the cond. The migration preserves this — the `case` replaces only the `get_in` line; `ctx` extraction stays on the line above. Do NOT move `threads_mod` inside the cond.
- The `function_exported?/3` + `Code.ensure_loaded/1` guard (THREADS-02) is a Phase-6 fix and must NOT be touched here.

---

### File 11: `lib/foglet_bbs/tui/screens/new_thread.ex`
**Role:** screen migrate (2 theme sites T-10/T-11 + 1 domain site D-03)
**Plan:** 00-03
**Theme sites:** T-10 at line 80 (`defp render_board_step/2`), T-11 at line 115 (`defp render_compose_step/2`)
**Domain site:** D-03 at lines 410–413 (`defp threads_module/1`)

#### Theme T-10 — Before (line 80)

```elixir
theme = (Map.get(state, :session_context) || %{}) |> Map.get(:theme) || Theme.default()
```

#### Theme T-10 — After (line 80)

```elixir
theme = Theme.from_state(state)
```

#### Theme T-11 — Before (line 115)

```elixir
theme = (Map.get(state, :session_context) || %{}) |> Map.get(:theme) || Theme.default()
```

#### Theme T-11 — After (line 115)

```elixir
theme = Theme.from_state(state)
```

#### Domain D-03 — Before (lines 410–413)

```elixir
defp threads_module(state) do
  ctx = Map.get(state, :session_context) || %{}
  get_in(ctx, [:domain, :threads]) || Foglet.Threads
end
```

#### Domain D-03 — After (lines 410–416)

```elixir
defp threads_module(state) do
  ctx = Map.get(state, :session_context) || %{}
  case Domain.get(ctx, :threads) do
    {:ok, mod} -> mod
    {:error, :not_configured} -> Foglet.Threads
  end
end
```

### Pattern notes

- Two independent theme replacements: T-10 and T-11 are in different `defp` functions. Emit two separate edit operations; do not conflate them.
- Add `alias Foglet.TUI.Screens.Domain` to `new_thread.ex`'s alias block.

---

### File 12: `lib/foglet_bbs/tui/screens/post_reader.ex`
**Role:** screen migrate (2 theme sites T-07/T-08 + 4 domain sites D-04/D-05/D-06/D-07)
**Plan:** 00-03

#### Theme T-07 — Before (line 34)

```elixir
theme = (Map.get(state, :session_context) || %{}) |> Map.get(:theme) || Theme.default()
```

#### Theme T-07 — After (line 34)

```elixir
theme = Theme.from_state(state)
```

#### Theme T-08 — Before (lines 328–330, inside `defp warm_viewport/4`)

```elixir
theme =
  (Map.get(state, :session_context) || %{}) |> Map.get(:theme) ||
    Foglet.TUI.Theme.default()
```

#### Theme T-08 — After (single line replacing lines 328–330)

```elixir
theme = Theme.from_state(state)
```

#### Domain D-04 — Before (lines 160–162, inside `def load_posts/2`)

```elixir
ctx = Map.get(state, :session_context) || %{}
posts_mod = get_in(ctx, [:domain, :posts]) || Foglet.Posts
```

#### Domain D-04 — After (lines 160–165)

```elixir
ctx = Map.get(state, :session_context) || %{}
posts_mod =
  case Domain.get(ctx, :posts) do
    {:ok, mod} -> mod
    {:error, :not_configured} -> Foglet.Posts
  end
```

#### Domain D-05 + D-06 — Before (lines 199–202, inside `def flush_read_pointers/2`)

```elixir
sc = Map.get(state, :session_context) || %{}
boards_mod = get_in(sc, [:domain, :boards]) || Foglet.Boards
threads_mod = get_in(sc, [:domain, :threads]) || Foglet.Threads
```

#### Domain D-05 + D-06 — After (lines 199–210)

```elixir
sc = Map.get(state, :session_context) || %{}
boards_mod =
  case Domain.get(sc, :boards) do
    {:ok, mod} -> mod
    {:error, :not_configured} -> Foglet.Boards
  end
threads_mod =
  case Domain.get(sc, :threads) do
    {:ok, mod} -> mod
    {:error, :not_configured} -> Foglet.Threads
  end
```

#### Domain D-07 — Before (lines 285–286, inside `defp parse_body/2`)

```elixir
sc = Map.get(state, :session_context) || %{}
markdown_mod = get_in(sc, [:domain, :markdown]) || Foglet.Markdown
```

#### Domain D-07 — After (lines 285–290)

```elixir
sc = Map.get(state, :session_context) || %{}
markdown_mod =
  case Domain.get(sc, :markdown) do
    {:ok, mod} -> mod
    {:error, :not_configured} -> Foglet.Markdown
  end
```

### Pattern notes

- T-08 is a 3-line span (328–330). The diff MUST replace all three lines with the single replacement line. Do not leave a dangling `||` on line 329 or 330.
- T-08 uses the fully-qualified `Foglet.TUI.Theme.default()`. The replacement uses the aliased form `Theme.from_state(state)` — valid since `post_reader.ex` already has `alias Foglet.TUI.Theme`.
- D-07: after migrating line 286, the `_ = Code.ensure_loaded(markdown_mod)` call on the following line is preserved verbatim — do NOT touch it.
- D-05 + D-06 are two adjacent lines in `flush_read_pointers/2`. Each gets its own `case`. They are not duplicates — they look up different keys.
- Add `alias Foglet.TUI.Screens.Domain` to `post_reader.ex`'s alias block.
- This file has the highest change density: 6 edit operations total (2 theme + 4 domain). Emit them as separate targeted edits.

---

### File 13: `lib/foglet_bbs/tui/screens/post_composer.ex`
**Role:** screen migrate (1 theme site T-09 + 1 domain site D-08)
**Plan:** 00-03
**Theme site:** T-09 at line 38
**Domain site:** D-08 at lines 285–286 (`defp submit_reply/4`)

#### Theme — Before (line 38)

```elixir
theme = (Map.get(state, :session_context) || %{}) |> Map.get(:theme) || Theme.default()
```

#### Theme — After (line 38)

```elixir
theme = Theme.from_state(state)
```

#### Domain — Before (lines 285–286)

```elixir
sc = Map.get(state, :session_context) || %{}
posts_mod = get_in(sc, [:domain, :posts]) || Foglet.Posts
```

#### Domain — After (lines 285–290)

```elixir
sc = Map.get(state, :session_context) || %{}
posts_mod =
  case Domain.get(sc, :posts) do
    {:ok, mod} -> mod
    {:error, :not_configured} -> Foglet.Posts
  end
```

### Pattern notes

- Add `alias Foglet.TUI.Screens.Domain` to `post_composer.ex`'s alias block.

---

### File 14: `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex`
**Role:** chrome widget migrate (1 theme site T-12)
**Plan:** 00-03
**Theme site:** T-12 at line 34
**Alias check:** Must confirm `alias Foglet.TUI.Theme` is present in `screen_frame.ex`.

#### Before (line 34)

```elixir
theme = (Map.get(state, :session_context) || %{}) |> Map.get(:theme) || Theme.default()
```

#### After (line 34)

```elixir
theme = Theme.from_state(state)
```

### Pattern notes

- Non-screen file, permitted by D-10.
- Single-line replacement. No domain migration in this file.

---

### File 15: `lib/foglet_bbs/tui/widgets/chrome/size_gate.ex`
**Role:** chrome widget migrate (1 theme site T-15, `Kernel.||` variant)
**Plan:** 00-03
**Theme site:** T-15 at lines 67–70
**Alias check:** Confirm `alias Foglet.TUI.Theme` is present (line 1–20 range shows it indirectly via moduledoc; verify before editing).

#### Before (lines 67–70, `Kernel.||` 4-line form)

```elixir
theme =
  (Map.get(state, :session_context) || %{})
  |> Map.get(:theme)
  |> Kernel.||(Theme.default())
```

#### After (single line replacing lines 67–70)

```elixir
theme = Theme.from_state(state)
```

### Pattern notes

- This is syntactically distinct from the bare `||` form used in all other files. The diff must replace all four lines (67–70) with the single replacement. Do not leave stray `|> Map.get(:theme)` or `|> Kernel.||` lines.
- Semantically identical to the standard form — `Kernel.||(Theme.default())` is just explicit pipe-compatible `||`.
- Non-screen file, permitted by D-10.

---

### File 16: `lib/foglet_bbs/tui/app.ex`
**Role:** app migrate (1 theme site T-14, modal overlay only)
**Plan:** 00-03
**Theme site:** T-14 at line 170 (`defp render_modal_overlay/2`)
**Alias check:** Confirm `alias Foglet.TUI.Theme` is present in `app.ex`.

#### Before (line 170)

```elixir
theme = (Map.get(state, :session_context) || %{}) |> Map.get(:theme) || Theme.default()
```

#### After (line 170)

```elixir
theme = Theme.from_state(state)
```

### Pattern notes

- ONLY this one line in `app.ex` is in scope for 00-03. The 6 domain lookup sites in `app.ex` (`do_update/2` clauses at lines 373, 390, 412, 436, 473, 474) are explicitly OUT of scope per D-10 and the RESEARCH.md Section 2 landmine note. Do NOT touch them.
- Single-line replacement. Diff for `app.ex` must show exactly one changed line.

---

## Shared Patterns

### Standard Theme Replacement (applies to T-01 through T-12 and T-14)

**Source:** `lib/foglet_bbs/tui/screens/login.ex:36` (canonical reference, CONTEXT.md canonical_refs)
**Apply to:** All 12 single-line theme sites

```elixir
# BEFORE (all 12 sites — same pattern):
theme = (Map.get(state, :session_context) || %{}) |> Map.get(:theme) || Theme.default()

# AFTER:
theme = Theme.from_state(state)
```

Prerequisite: `alias Foglet.TUI.Theme` must be present in the file's alias block. All 12 files already have this alias (they reference `Theme.default()` in the before-form).

---

### Kernel.|| Variant Theme Replacement (applies to T-15 only)

**Source:** `lib/foglet_bbs/tui/size_gate.ex:67-70`
**Apply to:** `size_gate.ex` only

```elixir
# BEFORE (4 lines):
theme =
  (Map.get(state, :session_context) || %{})
  |> Map.get(:theme)
  |> Kernel.||(Theme.default())

# AFTER (1 line):
theme = Theme.from_state(state)
```

---

### Multiline Theme Replacement (applies to T-08 only)

**Source:** `lib/foglet_bbs/tui/screens/post_reader.ex:328-330`
**Apply to:** `post_reader.ex` `warm_viewport/4` only

```elixir
# BEFORE (3 lines, note fully-qualified fallback):
theme =
  (Map.get(state, :session_context) || %{}) |> Map.get(:theme) ||
    Foglet.TUI.Theme.default()

# AFTER (1 line, uses aliased form):
theme = Theme.from_state(state)
```

---

### Domain Replacement (case expansion pattern)

**Source:** CONTEXT.md D-06, RESEARCH.md Section 2 per-site snippets
**Apply to:** All 8 domain sites (D-01 through D-08)

```elixir
# BEFORE (1 line):
some_mod = get_in(ctx_or_sc, [:domain, :key]) || Foglet.Default

# AFTER (4 lines):
some_mod =
  case Domain.get(ctx_or_sc, :key) do
    {:ok, mod} -> mod
    {:error, :not_configured} -> Foglet.Default
  end
```

Required alias addition (one per file that has a domain site):
```elixir
alias Foglet.TUI.Screens.Domain
```

Files needing this alias added: `board_list.ex`, `thread_list.ex`, `new_thread.ex`, `post_reader.ex`, `post_composer.ex`.

---

### Test File Convention

**Source:** `test/foglet_bbs/tui/screens/board_list_test.exs:1-28` (confirmed canonical)

```elixir
defmodule Foglet.TUI.Screens.SomeModuleTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Screens.SomeModule

  # Inline test doubles at top of file (not in a separate factory)
  defmodule FakeBoards do
    def some_callback(_args), do: :result
  end

  # setup block returns plain map — use Map.from_struct() when starting
  # from %Foglet.TUI.App{}, or plain %{} for pure-function helpers
  setup do
    state = %{session_context: %{domain: %{boards: FakeBoards}}}
    %{state: state}
  end

  describe "function_name/arity" do
    test "description of behavior", %{state: state} do
      assert SomeModule.function_name(state) == expected
    end
  end
end
```

Key rules:
- `async: true` — all TUI tests are async-safe.
- Inline module stubs (no ExMachina, no shared factory file).
- One `describe` block per public function.
- State built inline or in `setup` — no implicit shared state.

---

## No Analog Found

All 16 files have analogs. No entry needed in this section.

---

## Out-of-Scope Reminders (for planner)

- `lib/foglet_bbs/tui/widgets/chrome/status_bar.ex` — has an identical theme extraction chain at line 37 (T-13). Excluded per D-10. Do NOT migrate in Phase 0.
- `lib/foglet_bbs/tui/app.ex` domain sites at lines 373, 390, 412, 436, 473, 474 — excluded per D-10 and RESEARCH.md Section 2 landmine. Do NOT migrate in Phase 0.
- `@default_terminal_size` attribute extraction — deferred to Phases 5–9 per CONTEXT.md deferred section.

---

## Metadata

**Analog search scope:** `lib/foglet_bbs/tui/`, `test/foglet_bbs/tui/`
**Files read for pattern extraction:** `theme.ex`, `size_gate.ex` (lines 1–15, 60–80), `screen_frame.ex` (lines 28–42), `app.ex` (lines 164–172), `login.ex` (lines 1–45), `board_list_test.exs`, `login_test.exs`
**Pattern extraction date:** 2026-04-21

---

## PATTERN MAPPING COMPLETE
