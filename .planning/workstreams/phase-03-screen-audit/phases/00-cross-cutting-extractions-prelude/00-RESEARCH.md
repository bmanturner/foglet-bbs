# Phase 0: Cross-cutting extractions (prelude) — Research

**Researched:** 2026-04-21
**Domain:** Elixir TUI refactor — helper extraction and call-site migration
**Confidence:** HIGH (all findings grounded in `file:line` anchors from direct reads of the codebase)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01** `Theme.from_state/1` — accepts full Raxol state map, returns `%Theme{}` unconditionally, falls back to `Theme.default/0` (which returns `resolve(:gray)`). No `{:ok,_}|:error` wrapper. No `from_state!/1`.
- **D-02** `Screens.Domain.get/2` — new module at `lib/foglet_bbs/tui/screens/domain.ex` (module `Foglet.TUI.Screens.Domain`). Takes the `session_context` map (narrower input — caller passes `Map.get(state, :session_context) || %{}`). Returns `{:ok, module} | {:error, :not_configured}`. Supported keys: `:boards | :threads | :posts | :markdown`. Unknown keys return `{:error, :not_configured}`. No raise.
- **D-03** Three atomic plans: 00-01 (Theme helper + tests), 00-02 (Domain module + tests), 00-03 (migrate all call sites + verify grep gates). Each plan commits green on its own.
- **D-04** Implementation-first order (not TDD). Tests follow implementation within the same plan.
- **D-05** Migration inventory is the 11 call sites enumerated below — plan-phase researcher re-verifies with `rg`. (Actual count is higher — see Section 1 and 2 below.)
- **D-06** Default modules stay at call sites. `Domain.get/2` is a lookup; the fallback `|| Foglet.Boards` becomes an explicit `{:error, :not_configured}` branch at the caller. No cross-screen default hiding.
- **D-07** No compile-time grep gate or pre-commit hook added. Per-phase rubric (gates #8 and #9) catches regressions.
- **D-08** Zero user-visible change. SSH session renders byte-for-byte identically pre- and post-Phase-0.
- **D-09** Per-screen rubric (AUDIT-05..22) does NOT apply to the two helper modules. `AUDIT-18` canonical layout and `AUDIT-19` `init_screen_state/1` are both N/A to Phase 0 helpers.
- **D-10** 00-03-PLAN may touch `app.ex` modal overlay, `screen_frame.ex`, and `size_gate.ex` alongside the 9 screen files. This is the entirety of the AUDIT-13(a) exception.

### Claude's Discretion

- Exact moduledoc prose for the two new helpers — follow existing `Foglet.TUI.Theme` moduledoc style.
- Test file names/locations: extend `test/foglet_bbs/tui/theme_test.exs` (add `describe "from_state/1"` block) and create `test/foglet_bbs/tui/screens/domain_test.exs`.
- Exact `@type`/`@spec` surface for the new module.
- Whether to document-only (not deprecate) the pre-migration inlined pattern in 00-01 and 00-02.

### Deferred Ideas (OUT OF SCOPE)

- Compile-time/CI grep gate for inlined patterns.
- Per-screen default-module helper (e.g. `boards_mod/1`).
- `{80, 24}` terminal-size extraction (grep gate #7 is per-screen in Phases 5–9).
- `Foglet.TUI.Constants` shared module (FUT-01).
- `Foglet.TUI.Screens` behaviour (FUT-02).
- Deprecation shim for the pre-migration inlined pattern.

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| AUDIT-01 | `Theme.from_state/1` extracts inlined chains across 9 screens + screen_frame + size_gate + app.ex modal | Sections 1 and 7 document all 15 call sites with exact line numbers and replacement strings |
| AUDIT-02 | `Screens.Domain.get/2` extracts `get_in(ctx, [:domain, :key])` in board_list, thread_list, post_reader(×4), post_composer, new_thread | Section 2 documents all 8 screen-level call sites; app.ex sites are excluded per scope analysis |
| AUDIT-03 | Per-function tests: happy path, missing session_context, missing :theme / :domain key; `mix precommit` green | Section 4 (test layout) and Section 5 (precommit chain) cover this |
| AUDIT-04 | grep gates #8 and #9 return zero across screens after Phase 0 | Section 1 lists gate #8 pattern; Section 2 lists gate #9 pattern; Section 3 confirms verification commands |

</phase_requirements>

---

## Summary

Phase 0 is a mechanical extraction refactor. The two helpers have fully locked API shapes (D-01, D-02). The planner's job is to route the executor to the correct call sites with the correct before/after snippets — no API decisions remain open.

The key surprise from inventory verification: **the call-site count is higher than CONTEXT.md's "11" figure.** There are **15 theme extraction sites** (9 screens + new_thread has 2 + post_reader has 2 + screen_frame + size_gate + status_bar + app.ex) and **8 domain call sites across screen files** (board_list ×1, thread_list ×1, new_thread ×1, post_reader ×4, post_composer ×1). CONTEXT.md D-05 counted 11 total (combining both helpers); the corrected count is 15 theme + 8 screen domain = 23 sites to migrate. The `app.ex` domain lookups (6 additional sites) are **in app.ex's own do_update clauses**, not screen files — they are NOT covered by grep gate #9 which is scoped to `lib/foglet_bbs/tui/screens/*.ex`. See Section 2 landmine note.

`size_gate.ex` uses a syntactically distinct variant (`Kernel.||` instead of bare `||`) — the replacement is identical but the before-excerpt differs.

`status_bar.ex` has one theme extraction chain matching gate #8's pattern. It is NOT listed in CONTEXT.md D-05, but it IS a `lib/foglet_bbs/tui/widgets/chrome/` file. Gate #9 is scoped to `screens/*.ex`; gate #8 is also scoped to `screens/*.ex` in REQUIREMENTS.md AUDIT-05 item 8. The `status_bar.ex` site is therefore outside both grep gates but still lives in the TUI and has the inlined pattern. The planner should decide whether to include `status_bar.ex` in 00-03. Per D-10, only `app.ex`, `screen_frame.ex`, and `size_gate.ex` are listed as the non-screen sites. **Status_bar is NOT in scope per D-10** — do not touch it in 00-03.

**Primary recommendation:** Migrate exactly the 15 sites covered by D-10 (9 screens + screen_frame + size_gate + app.ex = 12 for theme, reduced to 11 distinct files because new_thread.ex and post_reader.ex each have 2 theme sites). For domain, migrate the 8 screen-level sites. Leave app.ex domain sites and status_bar.ex out of Phase 0 scope.

---

## Section 1 — `Theme.from_state/1` Migration Inventory (AUDIT-01, gate #8)

### Ripgrep results — exact pattern match

Command run:
```
rg -n --glob '!test/*' '\(Map\.get\(state, :session_context\) \|\| %\{\}\) \|> Map\.get\(:theme\)' lib/
```

**14 exact hits** (exact pattern) plus **1 `Kernel.||` variant** in `size_gate.ex`:

| # | File | Line | Context | In D-10 Scope? |
|---|------|------|---------|---------------|
| T-01 | `lib/foglet_bbs/tui/screens/login.ex` | 36 | `def render(state)` | YES — screen |
| T-02 | `lib/foglet_bbs/tui/screens/register.ex` | 30 | `def render(state)` | YES — screen |
| T-03 | `lib/foglet_bbs/tui/screens/verify.ex` | 41 | `def render(state)` | YES — screen |
| T-04 | `lib/foglet_bbs/tui/screens/main_menu.ex` | 18 | `def render(state)` | YES — screen |
| T-05 | `lib/foglet_bbs/tui/screens/board_list.ex` | 18 | `def render(state)` | YES — screen |
| T-06 | `lib/foglet_bbs/tui/screens/thread_list.ex` | 20 | `def render(state)` | YES — screen |
| T-07 | `lib/foglet_bbs/tui/screens/post_reader.ex` | 34 | `def render(state)` | YES — screen |
| T-08 | `lib/foglet_bbs/tui/screens/post_reader.ex` | 329 | `defp warm_viewport(ss, state, post, w)` — multiline form, fallback on next line | YES — screen |
| T-09 | `lib/foglet_bbs/tui/screens/post_composer.ex` | 38 | `def render(state)` | YES — screen |
| T-10 | `lib/foglet_bbs/tui/screens/new_thread.ex` | 80 | `defp render_board_step(state, ss)` | YES — screen |
| T-11 | `lib/foglet_bbs/tui/screens/new_thread.ex` | 115 | `defp render_compose_step(state, ss)` | YES — screen |
| T-12 | `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex` | 34 | `def render(state, title, content_element, key_list)` | YES — D-10 exception |
| T-13 | `lib/foglet_bbs/tui/widgets/chrome/status_bar.ex` | 37 | `def render(state, title)` | **NO — D-10 does NOT list status_bar** |
| T-14 | `lib/foglet_bbs/tui/app.ex` | 170 | `defp render_modal_overlay(modal, state)` | YES — D-10 exception |
| T-15 | `lib/foglet_bbs/tui/size_gate.ex` | 67–70 | `def render(state)` — uses `Kernel.||` variant | YES — D-10 exception |

**In-scope total for 00-03-PLAN:** 14 sites (T-01 through T-12, T-14, T-15). T-13 (`status_bar.ex`) is excluded per D-10.

### Per-site replacement details

All 14 in-scope sites use `state` as the variable name. No call site uses `ctx`, `session`, or any alias for the state map.

**Standard replacement for T-01 through T-12 and T-14 (single-line form):**
```elixir
# BEFORE (example from login.ex:36):
theme = (Map.get(state, :session_context) || %{}) |> Map.get(:theme) || Theme.default()

# AFTER:
theme = Theme.from_state(state)
```

**T-08 — post_reader.ex:329 — multiline form:**
```elixir
# BEFORE (post_reader.ex:328-330, inside defp warm_viewport/4):
theme =
  (Map.get(state, :session_context) || %{}) |> Map.get(:theme) ||
    Foglet.TUI.Theme.default()

# AFTER:
theme = Theme.from_state(state)
```
Note: `warm_viewport/4` uses `Foglet.TUI.Theme.default()` (fully-qualified) instead of the aliased `Theme.default()`. The replacement uses the aliased form since `post_reader.ex` already has `alias Foglet.TUI.Theme` at the top.

**T-15 — size_gate.ex:67–70 — `Kernel.||` variant:**
```elixir
# BEFORE (size_gate.ex:67-70):
theme =
  (Map.get(state, :session_context) || %{})
  |> Map.get(:theme)
  |> Kernel.||(Theme.default())

# AFTER:
theme = Theme.from_state(state)
```

### Grep gate #8 verification command (for 00-03-PLAN)
```
rg -n '\(Map\.get\(state, :session_context\) \|\| %\{\}\) \|> Map\.get\(:theme\)' \
  lib/foglet_bbs/tui/screens/ \
  lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex \
  lib/foglet_bbs/tui/widgets/chrome/size_gate.ex \
  lib/foglet_bbs/tui/app.ex
```
Expected: zero matches after migration.

**NOTE:** Gate #8 as written in REQUIREMENTS.md AUDIT-05 item 8 is scoped to `lib/foglet_bbs/tui/screens/*.ex`. After 00-03 completes, running the gate against `screens/*.ex` alone will return zero. The broader command above also covers the non-screen in-scope files (D-10).

---

## Section 2 — `Screens.Domain.get/2` Migration Inventory (AUDIT-02, gate #9)

### Ripgrep results

Command run:
```
rg -n 'get_in\(.*\[:domain,' lib/ --glob '!test/*'
```

**Full result set (22 hits across 5 files):**

```
lib/foglet_bbs/tui/app.ex:373    boards_mod = get_in(ctx, [:domain, :boards]) || Foglet.Boards
lib/foglet_bbs/tui/app.ex:390    boards_mod = get_in(ctx, [:domain, :boards]) || Foglet.Boards
lib/foglet_bbs/tui/app.ex:412    threads_mod = get_in(ctx, [:domain, :threads]) || Foglet.Threads
lib/foglet_bbs/tui/app.ex:436    posts_mod = get_in(ctx, [:domain, :posts]) || Foglet.Posts
lib/foglet_bbs/tui/app.ex:473    boards_mod = get_in(sc, [:domain, :boards]) || Foglet.Boards
lib/foglet_bbs/tui/app.ex:474    threads_mod = get_in(sc, [:domain, :threads]) || Foglet.Threads
lib/foglet_bbs/tui/screens/board_list.ex:113    get_in(ctx, [:domain, :boards]) || Foglet.Boards
lib/foglet_bbs/tui/screens/thread_list.ex:132   threads_mod = get_in(ctx, [:domain, :threads]) || Foglet.Threads
lib/foglet_bbs/tui/screens/new_thread.ex:412    get_in(ctx, [:domain, :threads]) || Foglet.Threads
lib/foglet_bbs/tui/screens/post_reader.ex:161   posts_mod = get_in(ctx, [:domain, :posts]) || Foglet.Posts
lib/foglet_bbs/tui/screens/post_reader.ex:200   boards_mod = get_in(sc, [:domain, :boards]) || Foglet.Boards
lib/foglet_bbs/tui/screens/post_reader.ex:201   threads_mod = get_in(sc, [:domain, :threads]) || Foglet.Threads
lib/foglet_bbs/tui/screens/post_reader.ex:286   markdown_mod = get_in(sc, [:domain, :markdown]) || Foglet.Markdown
lib/foglet_bbs/tui/screens/post_composer.ex:286 posts_mod = get_in(sc, [:domain, :posts]) || Foglet.Posts
```

### Scope split: screen-file sites vs. app.ex sites

**IMPORTANT LANDMINE:** REQUIREMENTS.md AUDIT-04 says grep gate #9 pattern is `get_in\(ctx, \[:domain` scoped to `lib/foglet_bbs/tui/screens/*.ex`. The 6 `app.ex` domain sites use `ctx` or `sc` as the variable name — they are in `app.ex`, NOT in `screens/*.ex`. Gate #9 will return zero even if `app.ex` sites are NOT migrated. CONTEXT.md D-10 does NOT list `app.ex` domain lookups as in-scope for 00-03 (only the modal overlay theme extraction is in scope for `app.ex`). **Do not migrate app.ex domain lookup sites in Phase 0.**

**In-scope screen-level domain sites (8 total):**

| # | File | Line | Function | ctx var | Key | Default |
|---|------|------|----------|---------|-----|---------|
| D-01 | `board_list.ex` | 113 | `defp domain_module/2` | `ctx` | `:boards` | `Foglet.Boards` |
| D-02 | `thread_list.ex` | 132 | `def load_threads/2` | `ctx` | `:threads` | `Foglet.Threads` |
| D-03 | `new_thread.ex` | 412 | `defp threads_module/1` | `ctx` | `:threads` | `Foglet.Threads` |
| D-04 | `post_reader.ex` | 161 | `def load_posts/2` | `ctx` | `:posts` | `Foglet.Posts` |
| D-05 | `post_reader.ex` | 200 | `def flush_read_pointers/2` | `sc` | `:boards` | `Foglet.Boards` |
| D-06 | `post_reader.ex` | 201 | `def flush_read_pointers/2` | `sc` | `:threads` | `Foglet.Threads` |
| D-07 | `post_reader.ex` | 286 | `defp parse_body/2` | `sc` | `:markdown` | `Foglet.Markdown` |
| D-08 | `post_composer.ex` | 286 | `defp submit_reply/4` | `sc` | `:posts` | `Foglet.Posts` |

**Total: 8 screen-level domain sites.** CONTEXT.md D-05 listed "7 call sites" — the actual count is 8 (post_reader has 4 sites, not 3 as in REQUIREMENTS.md AUDIT-02 which says "×3").

### Context variable names: `ctx` vs `sc`

All 8 sites first extract `session_context` into a local variable, then call `get_in/2` on that local. The local variable name varies:

- `ctx` used at D-01, D-02, D-03, D-04
- `sc` used at D-05, D-06, D-07, D-08

The `Screens.Domain.get/2` call replaces the `get_in(ctx_or_sc, [:domain, :key]) || Default` expression. The before-line that extracts `ctx` or `sc` from state is preserved (the helper takes `session_context`, so the extraction remains necessary).

### Per-site replacement snippets

**D-01 — board_list.ex:111-114 (inside `defp domain_module/2`):**
```elixir
# BEFORE:
defp domain_module(state, :boards) do
  ctx = Map.get(state, :session_context) || %{}
  get_in(ctx, [:domain, :boards]) || Foglet.Boards
end

# AFTER:
defp domain_module(state, :boards) do
  ctx = Map.get(state, :session_context) || %{}
  case Screens.Domain.get(ctx, :boards) do
    {:ok, mod} -> mod
    {:error, :not_configured} -> Foglet.Boards
  end
end
```
Requires adding `alias Foglet.TUI.Screens.Domain, as: Screens.Domain` (or just `alias Foglet.TUI.Screens`) to `board_list.ex`.

**D-02 — thread_list.ex:131-133 (inside `def load_threads/2`):**
```elixir
# BEFORE:
ctx = Map.get(state, :session_context) || %{}
threads_mod = get_in(ctx, [:domain, :threads]) || Foglet.Threads

# AFTER:
ctx = Map.get(state, :session_context) || %{}
threads_mod =
  case Screens.Domain.get(ctx, :threads) do
    {:ok, mod} -> mod
    {:error, :not_configured} -> Foglet.Threads
  end
```

**D-03 — new_thread.ex:410-413 (inside `defp threads_module/1`):**
```elixir
# BEFORE:
defp threads_module(state) do
  ctx = Map.get(state, :session_context) || %{}
  get_in(ctx, [:domain, :threads]) || Foglet.Threads
end

# AFTER:
defp threads_module(state) do
  ctx = Map.get(state, :session_context) || %{}
  case Screens.Domain.get(ctx, :threads) do
    {:ok, mod} -> mod
    {:error, :not_configured} -> Foglet.Threads
  end
end
```

**D-04 — post_reader.ex:160-162 (inside `def load_posts/2`):**
```elixir
# BEFORE:
ctx = Map.get(state, :session_context) || %{}
posts_mod = get_in(ctx, [:domain, :posts]) || Foglet.Posts

# AFTER:
ctx = Map.get(state, :session_context) || %{}
posts_mod =
  case Screens.Domain.get(ctx, :posts) do
    {:ok, mod} -> mod
    {:error, :not_configured} -> Foglet.Posts
  end
```

**D-05 and D-06 — post_reader.ex:199-202 (inside `def flush_read_pointers/2`, two adjacent lines):**
```elixir
# BEFORE:
sc = Map.get(state, :session_context) || %{}
boards_mod = get_in(sc, [:domain, :boards]) || Foglet.Boards
threads_mod = get_in(sc, [:domain, :threads]) || Foglet.Threads

# AFTER:
sc = Map.get(state, :session_context) || %{}
boards_mod =
  case Screens.Domain.get(sc, :boards) do
    {:ok, mod} -> mod
    {:error, :not_configured} -> Foglet.Boards
  end
threads_mod =
  case Screens.Domain.get(sc, :threads) do
    {:ok, mod} -> mod
    {:error, :not_configured} -> Foglet.Threads
  end
```
Note: These are two adjacent lines in the same function. Each gets its own `case`. No per-screen helper is needed here (D-06: only introduce a helper if the same module is needed >1 time within a single screen AND the helper reduces duplication — here each module is used once in the function, but the function itself is called once. The adjacency is not duplication; it is two distinct keys).

**D-07 — post_reader.ex:285-286 (inside `defp parse_body/2`):**
```elixir
# BEFORE:
sc = Map.get(state, :session_context) || %{}
markdown_mod = get_in(sc, [:domain, :markdown]) || Foglet.Markdown

# AFTER:
sc = Map.get(state, :session_context) || %{}
markdown_mod =
  case Screens.Domain.get(sc, :markdown) do
    {:ok, mod} -> mod
    {:error, :not_configured} -> Foglet.Markdown
  end
```

**D-08 — post_composer.ex:285-286 (inside `defp submit_reply/4`):**
```elixir
# BEFORE:
sc = Map.get(state, :session_context) || %{}
posts_mod = get_in(sc, [:domain, :posts]) || Foglet.Posts

# AFTER:
sc = Map.get(state, :session_context) || %{}
posts_mod =
  case Screens.Domain.get(sc, :posts) do
    {:ok, mod} -> mod
    {:error, :not_configured} -> Foglet.Posts
  end
```

### Grep gate #9 verification command (for 00-03-PLAN)
```
rg -n 'get_in\(.*\[:domain,' lib/foglet_bbs/tui/screens/
```
Expected: zero matches after migration. (This does NOT cover `app.ex` — that is intentional per scope analysis above.)

---

## Section 3 — `Theme.default/0` and `Theme` Struct

**Verified:** [VERIFIED: direct read of `lib/foglet_bbs/tui/theme.ex`]

### `Theme.default/0` — confirmed

```elixir
# lib/foglet_bbs/tui/theme.ex:227-229
@doc "Default theme (`:gray`) for v1.0.1."
@spec default() :: t()
def default, do: resolve(:gray)
```
`resolve(:gray)` populates all 10 slots from Raxol's registry (or falls back to `@gray_slots` if the registry is not yet populated). `from_state/1` calling `default/0` as its fallback preserves this behavior exactly.

### `%Foglet.TUI.Theme{}` struct shape

```elixir
@type t :: %__MODULE__{
        border: style_map(),
        primary: style_map(),
        dim: style_map(),
        accent: style_map(),
        title: style_map(),
        error: style_map(),
        warning: style_map(),
        selected: style_map(),
        unselected: style_map(),
        status_bar: style_map()
      }
```
Where `style_map() :: %{optional(:fg) => String.t(), optional(:bg) => String.t(), optional(:style) => [atom()]}`.

### Existing `from_*` constructors or aliases

None. `resolve/1` is the only constructor-style function. `default/0` is a convenience wrapper for `resolve(:gray)`. `from_state/1` will be the first `from_*` function.

### Moduledoc style to mimic

`Foglet.TUI.Theme`'s moduledoc uses:
1. One-sentence purpose
2. Numbered responsibilities list ("Two responsibilities:")
3. Slot reference list
4. Footer sentence with function names

Example for `from_state/1`'s moduledoc in `theme.ex`:
```elixir
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
```

For `Foglet.TUI.Screens.Domain`, the moduledoc style should mirror this: one-sentence purpose, responsibilities list, key reference (`:boards | :threads | :posts | :markdown`), footer with `get/2` function name.

---

## Section 4 — Test File Layout

**Verified:** [VERIFIED: glob of `test/foglet_bbs/tui/**/*.exs`]

### `test/foglet_bbs/tui/theme_test.exs` — DOES NOT EXIST

`test/foglet_bbs/tui/theme_test.exs` does **not exist** in the codebase. The 00-01-PLAN must **create** this file, not extend an existing one.

The correct mirror path for `lib/foglet_bbs/tui/theme.ex` is `test/foglet_bbs/tui/theme_test.exs`.

### `test/foglet_bbs/tui/screens/domain_test.exs` — new file

The path `test/foglet_bbs/tui/screens/domain_test.exs` mirrors `lib/foglet_bbs/tui/screens/domain.ex`. The `test/foglet_bbs/tui/screens/` directory already exists (confirmed by glob — all 9 screen test files live there).

### Existing test style — confirmed from `board_list_test.exs` and `app_test.exs`

```elixir
defmodule Foglet.TUI.Screens.BoardListTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Screens.BoardList

  defmodule FakeBoards do    # inline test-double at top of file
    def list_subscribed_boards(_user) do ... end
  end

  setup do
    state = %Foglet.TUI.App{...} |> Map.from_struct()
    %{state: state}
  end

  test "...", %{state: state} do ... end
end
```

Key conventions:
- `use ExUnit.Case, async: true` — all TUI tests are async-safe.
- Inline test doubles (modules defined inside the test file) — no separate factory or fixture file. No `ExMachina` or similar.
- `setup` block returns a map used in test `%{state: state}` pattern.
- State built from `%Foglet.TUI.App{}` struct, then `Map.from_struct/1` (tests work with plain maps, not the struct — avoids struct field exhaustiveness issues in older tests).
- No shared `test_helper.exs` theme fixture — each test injects its own `session_context: %{theme: theme}` inline.

### Test structure for 00-01-PLAN (`theme_test.exs`)

```elixir
defmodule Foglet.TUI.ThemeTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Theme

  describe "default/0" do
    # existing tests can go here if desired — or just from_state/1
  end

  describe "from_state/1" do
    test "returns the theme from state.session_context.theme" do
      theme = %Theme{primary: %{fg: "#ff0000"}}
      state = %{session_context: %{theme: theme}}
      assert Theme.from_state(state) == theme
    end

    test "returns Theme.default() when session_context is absent" do
      assert Theme.from_state(%{}) == Theme.default()
    end

    test "returns Theme.default() when session_context is nil" do
      assert Theme.from_state(%{session_context: nil}) == Theme.default()
    end

    test "returns Theme.default() when :theme key is missing from session_context" do
      assert Theme.from_state(%{session_context: %{}}) == Theme.default()
    end

    test "returns Theme.default() when :theme value is nil" do
      assert Theme.from_state(%{session_context: %{theme: nil}}) == Theme.default()
    end
  end
end
```

### Test structure for 00-02-PLAN (`screens/domain_test.exs`)

```elixir
defmodule Foglet.TUI.Screens.DomainTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Screens.Domain

  describe "get/2" do
    test "returns {:ok, module} when key is configured" do
      ctx = %{domain: %{boards: FakeBoards}}
      assert Domain.get(ctx, :boards) == {:ok, FakeBoards}
    end

    test "returns {:error, :not_configured} when session_context is empty" do
      assert Domain.get(%{}, :boards) == {:error, :not_configured}
    end

    test "returns {:error, :not_configured} when :domain key is absent" do
      assert Domain.get(%{other: :data}, :boards) == {:error, :not_configured}
    end

    test "returns {:error, :not_configured} when the specific key is absent" do
      ctx = %{domain: %{threads: FakeThreads}}
      assert Domain.get(ctx, :boards) == {:error, :not_configured}
    end

    test "returns {:error, :not_configured} for unknown keys" do
      ctx = %{domain: %{unknown: SomeMod}}
      assert Domain.get(ctx, :unknown) == {:error, :not_configured}
    end

    test "supports all four locked keys" do
      ctx = %{domain: %{boards: FB, threads: FT, posts: FP, markdown: FM}}
      assert Domain.get(ctx, :boards) == {:ok, FB}
      assert Domain.get(ctx, :threads) == {:ok, FT}
      assert Domain.get(ctx, :posts) == {:ok, FP}
      assert Domain.get(ctx, :markdown) == {:ok, FM}
    end
  end

  defmodule FakeBoards, do: nil
  defmodule FakeThreads, do: nil
  defmodule FakeBoards, do: nil
  # etc.
end
```
Note: The exact inline-module stubs can be simplified. The planner should define them outside the `describe` block or use module atoms directly (Elixir allows passing any atom as a "module" — the helper does no `Code.ensure_loaded/1`).

---

## Section 5 — `mix precommit` Dependencies and Landmines

### Exact `mix precommit` chain (confirmed from `mix.exs:80-87`)

```elixir
precommit: [
  "compile --warnings-as-errors",
  "deps.unlock --unused",
  "format",
  "credo --strict",
  "sobelow --exit Low",
  "dialyzer"
]
```

Note: CLAUDE.md says "compile-warnings-as-errors, format, credo, sobelow, dialyzer" but `mix.exs` also includes `deps.unlock --unused`. This is not a concern for Phase 0 (no new deps introduced), but the planner should know the full chain.

### Known suppressions to preserve verbatim

**Only one `credo:disable` suppression exists in TUI screens:**

`lib/foglet_bbs/tui/screens/register.ex:199`:
```elixir
# apply/3 is intentional here: Accounts.consume_invite_code/1 does not exist yet
# (Phase 8). Using apply avoids a compile-time undefined-function warning.
# credo:disable-for-next-line Credo.Check.Refactor.Apply
case apply(Foglet.Accounts, :consume_invite_code, [code]) do
```

This is a `credo:disable-for-next-line` (single-line scope). Phase 0's 00-03-PLAN does not touch `register.ex` logic — only the theme extraction line (:30) is migrated. The credo disable at :199 is preserved verbatim because 00-03 should only change the theme extraction line, nothing else in `register.ex`.

**No `@dialyzer` suppressions exist** in any TUI screen file or `app.ex`.

### Known-flaky tests or fragile test paths

No known-flaky tests were identified. The integration tests in `layout_smoke_test.exs` drive `render/1` through `Raxol.UI.Layout.Engine.apply_layout/2` for Login, MainMenu, BoardList, PostReader, PostComposer, NewThread, Register, Verify, and the modal overlay. These tests will exercise the post-migration `from_state/1` path and serve as an implicit invariant check — they pass today because the inlined chains produce the correct theme; they must pass after migration because `from_state/1` produces the same theme.

**Dialyzer:** The two new functions (`Theme.from_state/1` and `Screens.Domain.get/2`) must have proper `@spec` annotations. Dialyzer runs as part of `mix precommit`. Without specs, dialyzer will infer types but may produce warnings if the inferred types conflict with call sites.

---

## Section 6 — Validation Architecture (Nyquist)

`workflow.nyquist_validation` is `true` in `.planning/config.json` — this section is required.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | ExUnit (built into Elixir — no separate install required) |
| Config file | `test/test_helper.exs` (standard ExUnit boot) |
| Quick run — new theme tests | `mix test test/foglet_bbs/tui/theme_test.exs` |
| Quick run — new domain tests | `mix test test/foglet_bbs/tui/screens/domain_test.exs` |
| Full suite | `mix precommit` |
| Smoke integration | `mix test test/foglet_bbs/tui/layout_smoke_test.exs` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| AUDIT-01 | `Theme.from_state/1` happy path | unit | `mix test test/foglet_bbs/tui/theme_test.exs` | ❌ Wave 0 (create in 00-01) |
| AUDIT-01 | `Theme.from_state/1` missing session_context | unit | `mix test test/foglet_bbs/tui/theme_test.exs` | ❌ Wave 0 |
| AUDIT-01 | `Theme.from_state/1` missing :theme key | unit | `mix test test/foglet_bbs/tui/theme_test.exs` | ❌ Wave 0 |
| AUDIT-02 | `Domain.get/2` happy path, all 4 keys | unit | `mix test test/foglet_bbs/tui/screens/domain_test.exs` | ❌ Wave 0 (create in 00-02) |
| AUDIT-02 | `Domain.get/2` missing session_context | unit | `mix test test/foglet_bbs/tui/screens/domain_test.exs` | ❌ Wave 0 |
| AUDIT-02 | `Domain.get/2` missing :domain key | unit | `mix test test/foglet_bbs/tui/screens/domain_test.exs` | ❌ Wave 0 |
| AUDIT-02 | `Domain.get/2` unknown key → `{:error, :not_configured}` | unit | `mix test test/foglet_bbs/tui/screens/domain_test.exs` | ❌ Wave 0 |
| AUDIT-03 | `mix precommit` green after each plan commit | CI | `mix precommit` | N/A — run command |
| AUDIT-04 | grep gate #8 returns zero | grep | `rg ... lib/foglet_bbs/tui/screens/ ...` | N/A — shell command |
| AUDIT-04 | grep gate #9 returns zero | grep | `rg 'get_in.*\[:domain,' lib/foglet_bbs/tui/screens/` | N/A — shell command |

**Invariant preservation (D-08):** The layout smoke tests at `test/foglet_bbs/tui/layout_smoke_test.exs` exercise `render/1` through the full layout engine for all 9 screens plus the modal overlay. These tests pass today with the inlined chains; they must pass identically after 00-03 migrates to `Theme.from_state/1`. No new invariant test is needed — the smoke tests cover this implicitly.

### Sampling Rate

- **Per plan commit (00-01, 00-02, 00-03):** `mix precommit` (required — each plan must commit green)
- **Wave 0 (00-01 and 00-02, before 00-03):** no migration yet — just new functions alongside existing inlined chains
- **Phase gate:** `mix precommit` + grep gate #8 + grep gate #9 return zero

### Wave 0 Gaps (files that must be created before implementation)

- [ ] `test/foglet_bbs/tui/theme_test.exs` — created in 00-01-PLAN; covers `from_state/1` happy path + 4 fallback paths
- [ ] `test/foglet_bbs/tui/screens/domain_test.exs` — created in 00-02-PLAN; covers `get/2` happy path + 4 error paths
- [ ] `lib/foglet_bbs/tui/screens/domain.ex` — the new module itself, created in 00-02-PLAN

---

## Section 7 — Risks and Landmines

### 1. State variable name: always `state`, never `ctx` or `session`

For Theme.from_state/1 — all 14 in-scope sites pass the full Raxol state map, and the local variable is always named `state`. The replacement is always `theme = Theme.from_state(state)` verbatim. No site uses `ctx` or another alias for the state.

### 2. post_reader.ex:329 — multiline form and fully-qualified fallback

T-08 spans three lines (328–330) and uses the fully-qualified `Foglet.TUI.Theme.default()` instead of the aliased `Theme.default()`. The replacement is still one line: `theme = Theme.from_state(state)`. The planner must ensure the diff replaces all three lines (328–330), not just the `get_in` portion.

### 3. post_reader.ex has 4 domain call sites, not 3

REQUIREMENTS.md AUDIT-02 says "post_reader.ex (×3)." The actual count is **4** (lines 161, 200, 201, 286). Lines 200–201 are adjacent in `flush_read_pointers/2` (`:boards` and `:threads` extracted from the same `sc`). The planner must account for all 4 sites, including the adjacency in `flush_read_pointers/2`.

### 4. Domain sites in `app.ex` are NOT in Phase 0 scope

`app.ex` has **6 domain lookup sites** (lines 373, 390, 412, 436, 473, 474) in its `do_update/2` clauses. These are NOT in scope for 00-03-PLAN. CONTEXT.md D-10 permits `app.ex` to be touched only for the modal overlay theme extraction (T-14 above). Grep gate #9 is scoped to `lib/foglet_bbs/tui/screens/*.ex` — `app.ex` domain sites are invisible to the gate and do not need to be migrated for AUDIT-04 to pass.

### 5. `status_bar.ex` theme extraction is excluded from Phase 0

`lib/foglet_bbs/tui/widgets/chrome/status_bar.ex:37` has the identical inlined chain (T-13 above). It is NOT listed in D-10. Do not touch it in 00-03. Its inclusion is a future decision for a per-phase scope discussion, not a Phase 0 concern.

### 6. `size_gate.ex` uses `Kernel.||` — syntactically different but semantically identical

The `Kernel.||/2` piped form produces the same result as the bare `||` operator. The replacement `theme = Theme.from_state(state)` is correct for both forms. The before-excerpt in the plan must show the 4-line `Kernel.||` form (lines 67–70) to avoid the executor misidentifying the diff.

### 7. `new_thread.ex` has 2 theme sites in different `defp` functions

T-10 (line 80) is in `defp render_board_step/2`. T-11 (line 115) is in `defp render_compose_step/2`. These are two independent render helpers — each needs its own replacement. Neither calls the other. The planner should emit two separate edit operations, not one.

### 8. Domain call site wrapping: `case` expansion adds lines

The migration of `get_in(ctx, [:domain, :boards]) || Foglet.Boards` (1 line) to the `case` pattern (4 lines) increases the line count of the functions involved. Screens that have domain migrations will see a local line count increase in their domain-lookup functions. However, this is acceptable under D-06 (the default must remain visible at the call site). The per-screen AUDIT-16 line-delta check is a Phase 1–9 concern — Phase 0 is the documented AUDIT-13(a) exception and is not subject to the delta ≤ 0 size constraint.

### 9. `board_list.ex` domain site is inside a private helper function, not `render/1`

The inlined chain at `board_list.ex:111-114` is inside `defp domain_module(state, :boards)` — a single-arity private helper that wraps the lookup. After migration, `domain_module/2` becomes a thin wrapper around `Screens.Domain.get/2`. This is fine — the function's signature and callers do not change. The planner should NOT refactor `domain_module/2` away (it has a call site at `board_list.ex:88`: `boards_mod = domain_module(state, :boards)`).

### 10. `thread_list.ex` domain site is inside a `cond` branch; `Code.ensure_loaded/1` guard is separate

`load_threads/2` at `thread_list.ex:128-147` uses `function_exported?(threads_mod, :list_threads, 2)` and `function_exported?(threads_mod, :list_threads, 1)` in a `cond` block. The domain lookup at line 132 extracts `threads_mod` before the cond. After migration, `threads_mod` is still extracted before the cond — the `case Screens.Domain.get(ctx, :threads)` replaces the single-line `get_in`. The `function_exported?` guard pattern (the THREADS-02 Phase-6 correctness fix) is NOT touched in Phase 0.

### 11. `post_reader.ex:parse_body/2` already has `Code.ensure_loaded/1` on the markdown module

After migrating D-07 (`markdown_mod = get_in(sc, [:domain, :markdown]) || Foglet.Markdown`), the `_ = Code.ensure_loaded(markdown_mod)` call on the next line is unaffected. The planner's diff should only change the `markdown_mod` assignment, nothing else in `parse_body/2`.

### 12. Register.ex `credo:disable-for-next-line` at line 199 is not near the theme extraction at line 30

00-03 touches `register.ex` only to migrate line 30. Line 199 is 169 lines away. No risk of the diff touching it, but the planner should be explicit that the commit diff for `register.ex` is exactly one line changed (line 30).

### 13. `Domain.get/2` implementation must NOT call `Code.ensure_loaded/1`

Per D-02, configured modules are trusted. The `Code.ensure_loaded/1` pattern in `post_reader.ex:parse_body/2` is a per-call-site concern already in the existing code — it is NOT added to `Domain.get/2`. The helper is a pure map lookup.

---

## Section 8 — Architecture Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Theme extraction helper | Frontend Server (TUI App) | — | Pure function reading app state; no external dependency |
| Domain module lookup helper | Frontend Server (TUI App) | — | Pure map lookup over session_context; no DB access |
| Call-site migration | Frontend Server (TUI App) | — | All sites are inside TUI screen/widget `render/1` or handler functions |

---

## Standard Stack

No new dependencies. All work uses existing Elixir stdlib (`Map.get/2`, pattern matching, `case`) and the existing `Foglet.TUI.Theme` module.

| Item | Version | Purpose |
|------|---------|---------|
| ExUnit | Built-in | Test framework for new unit tests |
| `Foglet.TUI.Theme` | Existing | `default/0` and `resolve/1` — consumed by `from_state/1` |
| `mix precommit` | Existing alias | compile + format + credo + sobelow + dialyzer gate |

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead |
|---------|-------------|-------------|
| Theme nil-safe extraction | Custom guard or `with` chain | `Theme.from_state/1` (what Phase 0 is building) |
| Domain module resolution | Custom `Module.concat/1` or `Application.get_env` | `Screens.Domain.get/2` + explicit `{:error, :not_configured}` branch |
| Module existence check | `Code.ensure_loaded/1` inside Domain.get | Not in scope — D-02 explicitly excludes it |

---

## Assumptions Log

All claims in this research were verified or cited from direct file reads — no training-only assumptions.

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `status_bar.ex` domain site is excluded from D-10 scope | Section 1 / Section 7 | LOW — D-10 is explicitly enumerated; status_bar is not listed |
| A2 | App.ex domain sites are outside grep gate #9 scope | Section 2 / Section 7 | LOW — REQUIREMENTS.md AUDIT-05 item 9 says "lib/foglet_bbs/tui/screens/*.ex" |
| A3 | post_reader.ex flush_read_pointers is not called through App.update/2 dispatch but directly in post_reader.ex itself | Section 2 | LOW — read of post_reader.ex confirms the function is called by app.ex via `{:flush_read_pointers, ctx}` command, not by post_reader.ex itself; but the domain sites at lines 200-201 ARE in the screen file |

---

## Open Questions

1. **Should `status_bar.ex:37` be migrated in 00-03?**
   - What we know: It has the identical inlined pattern. D-10 does not list it. The grep gate applies to `screens/*.ex` not `widgets/chrome/*.ex`.
   - What's unclear: Whether leaving `status_bar.ex` un-migrated creates future confusion (inconsistency across chrome widgets — `screen_frame.ex` migrated, `status_bar.ex` not).
   - Recommendation: Follow D-10 strictly — exclude `status_bar.ex` from Phase 0. A future workstream discussion can re-examine. Do not expand scope mid-phase.

2. **Should `app.ex` domain lookup sites (lines 373, 390, 412, 436, 473, 474) be migrated in a future phase?**
   - These are in `app.ex` do_update clauses, not in screen files. Grep gate #9 will not catch them.
   - Recommendation: Defer to a future workstream amendment. Phase 0's job is the screen-level sites. Document this as a known exclusion.

---

## Sources

### Primary (HIGH confidence — verified by direct file read)

- `lib/foglet_bbs/tui/theme.ex` — confirmed `default/0`, `resolve/1`, struct shape, moduledoc style
- `lib/foglet_bbs/tui/screens/login.ex` — T-01 theme site at :36
- `lib/foglet_bbs/tui/screens/register.ex` — T-02 at :30, credo disable at :199
- `lib/foglet_bbs/tui/screens/verify.ex` — T-03 at :41
- `lib/foglet_bbs/tui/screens/main_menu.ex` — T-04 at :18
- `lib/foglet_bbs/tui/screens/board_list.ex` — T-05 at :18, D-01 at :113
- `lib/foglet_bbs/tui/screens/thread_list.ex` — T-06 at :20, D-02 at :132
- `lib/foglet_bbs/tui/screens/post_reader.ex` — T-07 at :34, T-08 at :329, D-04 at :161, D-05/:06 at :200-201, D-07 at :286
- `lib/foglet_bbs/tui/screens/post_composer.ex` — T-09 at :38, D-08 at :286
- `lib/foglet_bbs/tui/screens/new_thread.ex` — T-10 at :80, T-11 at :115, D-03 at :412
- `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex` — T-12 at :34
- `lib/foglet_bbs/tui/widgets/chrome/status_bar.ex` — T-13 at :37 (excluded from scope)
- `lib/foglet_bbs/tui/app.ex` — T-14 at :170, app.ex domain sites at :373/:390/:412/:436/:473/:474
- `lib/foglet_bbs/tui/size_gate.ex` — T-15 at :67-70 (Kernel.|| variant)
- `mix.exs:80-87` — confirmed full `precommit` alias chain
- `test/foglet_bbs/tui/app_test.exs`, `test/foglet_bbs/tui/screens/board_list_test.exs` — confirmed test style (async: true, inline modules, Map.from_struct)
- `test/foglet_bbs/tui/layout_smoke_test.exs` — confirmed cross-screen integration coverage
- `.planning/config.json` — confirmed `nyquist_validation: true`
- `00-CONTEXT.md` — all locked decisions D-01 through D-10

---

## RESEARCH COMPLETE
