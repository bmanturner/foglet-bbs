# Phase 46: Domain Cleanup And Final Quality Gate — Pattern Map

**Mapped:** 2026-04-29
**Files modified:** 4 (no new files)
**Analogs found:** 4 / 4

## File Classification

This phase is curation / documentation only. Every target is **modified in place**; the pattern source is most often the file's own existing structure (heading style, comment block style, ordering). Where useful, a sibling file is named as the analog.

| Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---------------|------|-----------|----------------|---------------|
| `lib/foglet_bbs/boards/supervisor.ex` | supervisor (domain DynamicSupervisor) | request-response (start_child) | `lib/foglet_bbs/sessions/supervisor.ex` | role + shape match |
| `lib/foglet_bbs/boards/server.ex` | GenServer + moduledoc | event-driven (handle_call) | self — existing `## Message number allocation` / `## Crash recovery (D-05)` subheaders | self-analog |
| `.dialyzer_ignore.exs` | tooling baseline / config | build-time | self — existing `Phase 25 Account forms` block (lines 48-53) | self-analog |
| `.planning/codebase/CONCERNS.md` | planning artifact / disposition register | doc | self — section/heading layout already in file; SPEC §Requirement 4 locks the `**Disposition:**` line format (no prior on-disk usage in repo) | format locked by SPEC |

---

## Pattern Assignments

### `lib/foglet_bbs/boards/supervisor.ex` — DOM-01 deletion

**Current state to delete (lines 35-46):**
```elixir
  @doc """
  Boot all non-archived boards at application startup.
  Called from FogletBbs.Application.start/2 after the supervision tree is up.
  Full implementation is in Foglet.Boards context (Plan 03).
  This stub is replaced when Plan 03 creates Foglet.Boards.
  """
  def boot_board_servers do
    # Stub: no boards exist yet. Plan 03 implements the real query.
    # When Foglet.Boards context is implemented, Application.start/2
    # calls Foglet.Boards.boot_board_servers/0 (not this stub).
    :ok
  end
```

**Lines to keep unchanged (1-33):** module declaration, `@moduledoc`, `use DynamicSupervisor`, `start_link/1`, `init/1`, `start_board/1`. The closing `end` at line 47 stays.

**Analog — post-deletion shape** (`lib/foglet_bbs/sessions/supervisor.ex:1-30`):
```elixir
defmodule Foglet.Sessions.Supervisor do
  @moduledoc """
  DynamicSupervisor for Foglet.Sessions.Session processes.
  ...
  """

  use DynamicSupervisor

  require Logger

  @registry Foglet.Sessions.Registry
  @replacement_timeout_ms 2_000

  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
```

**Conventions to preserve:**
- Module docstring with `## D-XX` references where present.
- `use DynamicSupervisor` immediately after `@moduledoc`.
- `start_link/1` and `init/1` block, then `start_child`-shaped public functions (`start_board/1` here, `start_session/1` in the sessions analog).
- Pitfall 4 (research): delete `@doc` and the function body **as a single unit**. A dangling `@doc` without a following definition is a compile error.
- Trailing blank line and module `end` preserved.

---

### `lib/foglet_bbs/boards/server.ex` — DOM-02 moduledoc + inline comments

**Existing moduledoc structure to extend (lines 1-27):**
```elixir
defmodule Foglet.Boards.Server do
  @moduledoc """
  Per-board GenServer that serializes message-number allocation.

  One Server process per active board. Registered via `Foglet.BoardRegistry`
  so callers can look up the server by board_id without knowing the PID.

  ## Message number allocation

  Each Board Server holds the next available message number in its state.
  When a post is inserted (thread creation or reply), the Server:

    1. Runs an `Ecto.Multi` that atomically:
       ...

  ## Crash recovery (D-05)

  On init, the Server queries `MAX(message_number)` from the posts table
  and resumes from `MAX + 1`. ...
  """
```

**New `## Transaction strategy` subheader inserts as a third sibling block,** immediately before the closing `"""` at line 27. Maintain parallel structure: `## ` heading, blank line, prose paragraph(s), blank line.

**Conventions to preserve:**
- `## ` (level-2) subheader inside the moduledoc — same level as `## Message number allocation` and `## Crash recovery (D-05)`. Do NOT use `### ` or `# `.
- Subheader naming pattern: short noun-phrase. The two existing precedents are noun-phrases (`Message number allocation`, `Crash recovery`) — `Transaction strategy` matches.
- The existing `(D-05)` suffix on `Crash recovery` is a backreference to a prior CONTEXT decision; DOM-02 has **D-01/D-02** in CONTEXT but the SPEC does not require the suffix. Discretion (CONTEXT §Claude's Discretion): match tone but do not invent a fake D-suffix.
- Required content (per CONTEXT D-01): explicitly use the words "intentional" and "locked deviation from `Repo.transact/1`"; cite step labels `:post` and `:thread_update`; reference handle_call clauses at `server.ex:86-93,102-108`.
- Inline-code formatting follows the existing moduledoc style: `Foglet.BoardRegistry`, `Ecto.Multi`, `MAX(message_number)` are wrapped in single backticks.

**Inline pointer comment sites (D-02):**

Site 1 — `lib/foglet_bbs/boards/server.ex:154` (end of `run_post_insert_multi/5`):
```elixir
    |> Multi.run(:bump_user_post_count, fn repo, _ ->
      ...
      {:ok, :bumped}
    end)
    |> Repo.transaction()       # ← line 154 — insert pointer comment ABOVE this line
  end
```

Site 2 — `lib/foglet_bbs/boards/server.ex:196` (end of `run_thread_create_multi/4`):
```elixir
    |> Multi.run(:bump_user_post_count, fn repo, _ ->
      ...
      {:ok, :bumped}
    end)
    |> Repo.transaction()       # ← line 196 — insert pointer comment ABOVE this line
  end
```

**Comment style analog** — same file already uses single-`#` end-of-pipeline annotations and section dividers. Use a single-line `#` comment at the same indentation as `|> Repo.transaction()` (4 spaces from column 0). Suggested form (CONTEXT D-02):
```elixir
    # Multi step labels :post / :thread_update are load-bearing — see @moduledoc
    |> Repo.transaction()
```

**Conventions to preserve:**
- Multi step names `:post` (line 128) and `:thread_update` (line 184) MUST NOT be renamed — they are pattern-matched at `server.ex:87` and `server.ex:103`. (Anti-pattern from research.)
- `Multi.run/3` callback signatures inside `run_post_insert_multi/5` and `run_thread_create_multi/4` MAY be tightened in Plan 03 (QUAL-01 D-04) to fix the `:call_without_opaque` entry; that is a Plan 03 concern, not a Plan 02 concern.
- Indentation: 4 spaces (matches existing pipeline indent).

---

### `.dialyzer_ignore.exs` — QUAL-01 narrowing + annotation

**Existing self-analog comment block (lines 48-53):**
```elixir
  # Phase 25 Account forms intentionally expose a defensive :no_match fallback
  # even though current call sites only route supported form events.
  {"lib/foglet_bbs/tui/screens/account/prefs_form.ex",
   "The pattern can never match the type true."},
  {"lib/foglet_bbs/tui/screens/account/profile_form.ex",
   "The pattern can never match the type true."}
```

**Existing file-header comment to rewrite (lines 1-15):**
```elixir
# Baseline of pre-existing dialyzer warnings captured when `mix dialyzer` was
# first added to the precommit alias. Each entry is a {path, warning_type} pair
# that matches any warning of that type in that file.
#
# The goal is to fail precommit on NEW warnings while letting the existing
# noise coexist. When touching a file below, consider fixing its warnings and
# removing the ignore entry.
#
# Categories represented:
#   * :unknown_type          — Ecto-schema `t/0` types dialyzer can't resolve
#                              from `use Ecto.Schema`. Not a real bug.
#   * :call_without_opaque   — Ecto.Changeset / Ecto.Multi opaque-type
#                              false-positives.
#   * :contract_supertype    — `@spec` is broader than the success typing.
#                              Style warning, not a bug.
```

**Conventions to preserve:**
- Comment marker: single `#` at column 0 (no leading whitespace inside the file's outer scope, since the list literal starts at column 0). The Phase-25 block at lines 48-53 is **inside the list** with leading whitespace — that is the indented in-list pattern.
- Two distinct comment positions:
  1. **File header** (lines 1-15) — column-0 `#` comments above the list literal `[`.
  2. **In-list group header** (e.g. lines 48-49) — leading-whitespace `#` comments **inside** the list literal, immediately above the `{...}` entry tuples they annotate.
- Existing entry style: `{"path", :warning_type}` 2-tuples on a single line; the `:no_match` exceptions use 2-line tuples with a string-pattern matcher. Both forms remain valid.
- Trailing comma rules: every entry except the last has a trailing comma. When entries are removed (Bucket B fix; narrowed C1 entries), preserve the no-trailing-comma-on-last-element shape.
- Bucket grouping (CONTEXT D-03): produce one shared header comment per bucket, then the entries.
  - Bucket A — `:unknown_type` (KEEP, D-05): single header comment naming Ecto schema `t/0` false positives.
  - Bucket C2 — Raxol-opaque renders (KEEP, D-03 bucket 2): single header comment headed `# Raxol element() return — opaque from caller perspective`.
  - Bucket C3 — Ecto-opaque (KEEP, D-03 bucket 3): single header comment naming `Ecto.Changeset.t/0` / `Ecto.Multi.t/0` opacity.
  - Bucket D — defensive `:no_match` (KEEP, D-06): keep the existing Phase-25 comment verbatim per CONTEXT D-06 ("carry over the existing inline rationale; do not delete the comment that is already there").
- Final ordering (Claude's Discretion per CONTEXT): group by bucket for readability. Original alphabetical-by-path ordering inside the `:contract_supertype` block is **not** load-bearing; bucket order takes precedence.
- File header invariant (D-07): replace the existing `# The goal is to fail precommit on NEW warnings…` line with a stronger statement: every kept entry has a stated reason; entries without rationale are not allowed back without reviewer justification.
- Line-count gate (D-08, SPEC acceptance): final `wc -l .dialyzer_ignore.exs` must be **strictly smaller** than the pre-phase 55 lines. The Bucket-B fix alone (1 line removed) satisfies the floor; aim for ≥ 5 entries removed (Assumption A3).

---

### `.planning/codebase/CONCERNS.md` — QUAL-03 disposition lines

**Existing intro paragraph to extend (lines 1-9):**
```markdown
# Codebase Concerns

**Analysis Date:** 2026-04-29

This document inventories tech debt, fragile areas, security considerations, and
under-tested zones for Foglet BBS as of v2.0 close (Phase 40 complete). The
post-Phase-40 codebase passes `rtk mix precommit` and the full `rtk mix test`
suite (1 property + 2161 tests, 0 failures), so most concerns below are latent
risks, bounded compatibility shims, or ergonomic debt — not active failures.
```

**Existing `### ` heading example (line 13):**
```markdown
### TUI: Bounded compatibility callback surface still attached to `Foglet.TUI.Screen`

- Issue: `Foglet.TUI.Screen` still declares `render/1`, `handle_key/2`, ...
- Files: `lib/foglet_bbs/tui/screen.ex` (lines 19-36, ...
- Impact: ...
- Fix approach: ...
```

**Disposition line format — locked by SPEC §Requirement 4** (no on-disk precedent in `.planning/codebase/`):

The line is a single new bullet/paragraph inserted **inside the `### ` heading's section**, before the next `### ` or `## `. Use the format:

```markdown
- **Disposition:** Fixed in Phase NN — `lib/path/to/file.ex` `function/arity` (or `NN-XX-SUMMARY.md` anchor).
```

or

```markdown
- **Disposition:** Intentionally retained — <rationale>; see ROADMAP.md backlog.
```

or

```markdown
- **Disposition:** Covered by `NN-XX-SUMMARY.md` (or `test/foglet_bbs/path/_test.exs`).
```

**Conventions to preserve:**
- Heading style is unchanged: `### ` (literal three hashes + space). 4 of 17 headings start with backticked identifiers (Pitfall 3) — the regex `^### ` matches all of them.
- Original concern text (`- Issue:`, `- Files:`, `- Impact:`, `- Fix approach:`) is preserved **verbatim** (Boundaries §Out of scope, D-12, anti-pattern in research).
- Disposition value vocabulary is exactly three (D-10): `Fixed in Phase NN`, `Intentionally retained`, `Covered by …`. No other phrasing.
- Placement: insert the disposition line **after** the existing bullets in the heading's section, before the next `### ` or `## `. (D-09: "before the next `### ` or `## ` heading.") Treat it as a top-level bullet sibling of `- Issue:` etc.
- Bold + colon form `**Disposition:**` matches the existing inline-emphasis style on labels in the file (e.g. `**Analysis Date:**` in the intro).
- Section ordering walk (D-09): `## Tech Debt` → `## Known Bugs` → `## Security Considerations` → `## Performance Bottlenecks` → `## Fragile Areas` → `## Test Coverage Gaps` (file's actual structure per RESEARCH heading inventory; SPEC's "Under-tested Zones" maps to `## Test Coverage Gaps`).
- `## Known Bugs` has zero `### ` headings (intro-text only) — leave untouched (RESEARCH).
- Intro paragraph addition (D-12): append (do not replace) a sentence/paragraph noting the v2.1 close pass on 2026-04-29, asserting every section now carries a `**Disposition:**` line, and preserving the v2.0-close framing.

---

## Shared Patterns

### Single-source-of-truth doc references

**Source:** `lib/foglet_bbs/boards/server.ex` (existing moduledoc)
**Apply to:** DOM-02 inline comments at `:154` and `:196`.

The inline comments must point readers back to the moduledoc rather than duplicate the rationale. Pattern:
```elixir
    # Multi step labels :post / :thread_update are load-bearing — see @moduledoc
    |> Repo.transaction()
```
This avoids drift between the moduledoc paragraph and inline comments.

### Phase-pointer disposition format

**Source:** RESEARCH.md `## CONCERNS.md Heading Inventory` table — already enumerates correct phase pointers for each heading
**Apply to:** All 14+ disposition lines in QUAL-03.

Use the proposed pointers in RESEARCH.md as starting wording. Each `Fixed in Phase NN` includes either a file/function reference (`lib/foglet_bbs/ssh/pubkey_stash.ex:21,109`) or a SUMMARY anchor (`45-01-SUMMARY.md`). Each `Intentionally retained` includes a rationale phrase + `see ROADMAP.md backlog` where applicable. Each `Covered by …` names a SUMMARY.md or test file.

### `rtk` shell prefix on validation commands

**Source:** `AGENTS.md` (project-wide convention)
**Apply to:** All four plans' acceptance steps.

All `mix` invocations in plan acceptance criteria, task command lists, and SUMMARY.md verification steps MUST use `rtk mix …` form. Plain `mix …` is incorrect per CLAUDE.md / AGENTS.md.

---

## No Analog Found

| File | Role | Reason |
|------|------|--------|
| (none) | — | All four targets have either a sibling-file analog or self-analog (existing structure within the same file). The disposition-line format in CONCERNS.md is novel to the repo but is fully locked by SPEC §Requirement 4 + CONTEXT D-09/D-10, so the planner does not need to derive a format. |

---

## Metadata

**Analog search scope:**
- `lib/foglet_bbs/**/supervisor.ex` (Sessions, SSH, Boards) — for DOM-01 post-deletion shape.
- `lib/foglet_bbs/boards/server.ex` itself — for DOM-02 moduledoc structure and inline comment style.
- `.dialyzer_ignore.exs` itself — for QUAL-01 in-list comment block style (Phase-25 precedent).
- `.planning/codebase/*.md` — searched for prior `**Disposition:**` usage (none found; format locked by SPEC).

**Files scanned:** 4 modification targets + 2 supervisor analogs + grep across `.planning/codebase/`.

**Pattern extraction date:** 2026-04-29
