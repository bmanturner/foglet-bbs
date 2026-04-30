# Phase 46: Domain Cleanup And Final Quality Gate - Research

**Researched:** 2026-04-29
**Domain:** Elixir/Phoenix domain cleanup, Dialyzer baseline reduction, planning-artifact disposition annotation
**Confidence:** HIGH

## Summary

Phase 46 closes v2.1 by addressing four locked tech-debt items (DOM-01, DOM-02, QUAL-01, QUAL-03). The implementation strategy is fully locked in `46-CONTEXT.md` (D-01 through D-14). This research confirms the on-disk state of every target file, enumerates the concrete entries the plan must address, and cross-references dispositions for QUAL-03 against phase-41-through-45 SUMMARY.md files so the planner can author grep-verifiable acceptance criteria without re-deriving them.

Key verifications: (a) the DOM-01 stub has zero callers in `lib/` or `test/`, so deletion is safe; (b) the DOM-02 Multi step labels (`:post`, `:thread_update`) are confirmed load-bearing at `server.ex:87` and `server.ex:103`; (c) `.dialyzer_ignore.exs` carries exactly 30 entry-lines (28 entries — 5 `:unknown_type`, 1 `:call_without_opaque`, 20 `:contract_supertype`, 2 string-pattern `:no_match`); (d) `.planning/codebase/CONCERNS.md` has exactly 14 `### ` headings across 5 `## ` sections that need a `**Disposition:**` line each; (e) phases 41–45 produced 22 SUMMARY.md files that resolve every disposition pointer required by QUAL-03.

**Primary recommendation:** Plan in the locked DOM-01 → DOM-02 → QUAL-01 → QUAL-03 order (D-13). Run `rtk mix precommit && rtk mix test` after each plan. Use the bucketed inventories in this research (Dialyzer narrow / Raxol-opaque / Ecto-opaque; CONCERNS heading map) to produce concrete, grep-verifiable task acceptance criteria.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**DOM-02 Documentation Placement**
- **D-01:** Add a `## Transaction strategy` subheader paragraph to the existing `@moduledoc` of `lib/foglet_bbs/boards/server.ex` (parallel to `## Message number allocation` and `## Crash recovery`). Names the `Repo.transaction/1 + Ecto.Multi` choice as intentional, cites `:post` and `:thread_update` step labels, references the `handle_call` clauses at `server.ex:86-93,102-108` that depend on those labels for success-side extraction, and explicitly states the divergence from the project-wide `Repo.transact/1` convention is locked.
- **D-02:** Add a one-line inline pointer comment immediately above each `|> Repo.transaction()` site at `:154` and `:196`, e.g. `# Multi step labels :post / :thread_update are load-bearing — see @moduledoc`.

**QUAL-01 Dialyzer Baseline Reduction Strategy**
- **D-03:** Walk the `:contract_supertype` entries in three buckets:
  1. **Narrow.** Screen `init/1` returning `map()` → return concrete state struct (e.g. `LoginState.t()`); state-module `default/0` and `put/2` returning typed structs; `update/3` event params typed as `term()` → narrow where a concrete event union exists. Fix and remove the matching ignore entry.
  2. **Annotate as Raxol-opaque.** Any `render/1,2` returning `any()` is genuinely opaque from outside Raxol. Keep with shared comment block headed `# Raxol element() return — opaque from caller perspective`.
  3. **Annotate as Ecto-opaque.** Any `:contract_supertype` tied to `Ecto.Changeset.t/0`, `Ecto.Multi.t/0`, etc. Keep with shared comment block.
- **D-04:** Fix `{"lib/foglet_bbs/boards/server.ex", :call_without_opaque}` by tightening the relevant `@spec` (or the `Multi.run/3` callback signatures inside `run_post_insert_multi/5` / `run_thread_create_multi/4`) so dialyzer no longer flags Multi result-tuple opacity. Remove the entry.
- **D-05:** Keep existing `:unknown_type` entries on `boards.ex`, `boards/server.ex`, `posts.ex`, `threads.ex` (Ecto schema `t/0` false positives) and consolidate rationale into a single header comment block above the group.
- **D-06:** Keep the two `:no_match` entries on `account/prefs_form.ex` and `account/profile_form.ex` (defensive Phase 25 fallbacks) with a per-entry comment naming the defensive intent. Carry over existing inline rationale.
- **D-07:** Update file header to describe the post-cleanup invariant: every kept entry has a stated reason; entries without rationale are not allowed back without reviewer justification.
- **D-08:** Validate after each batch with `rtk mix dialyzer` and `rtk mix precommit`. Final `.dialyzer_ignore.exs` line count MUST be strictly smaller than before.

**QUAL-03 CONCERNS.md Disposition Walk**
- **D-09:** Walk `.planning/codebase/CONCERNS.md` top-to-bottom in existing file order. For each `### ` heading, insert a `**Disposition:**` line within that heading's section, before the next `### ` or `## ` heading.
- **D-10:** Disposition values are exactly three: `Fixed in Phase NN`, `Intentionally retained`, or `Covered by …`. Cross-reference dispositions against `.planning/phases/41-…` through `45-…` SUMMARY.md files. Each `Fixed in Phase NN` line includes a one-line pointer (file path, function, or SUMMARY anchor). Each `Intentionally retained` names the rationale and, when applicable, a backlog pointer. Each `Covered by …` names the test or doc artifact.
- **D-11:** SSH `PubkeyStash` TTL/sweep concern → `Fixed in Phase 45` (`lib/foglet_bbs/ssh/pubkey_stash.ex:21,109`). Deferred perf items (`Foglet.Posts.list_posts/1` cursor pagination, `PostReader render_cache` width-LRU) → `Intentionally retained` with v2.1-kickoff deferral rationale and a backlog pointer.
- **D-12:** Update intro paragraph to note v2.1 close pass; assert every section now carries a disposition; preserve v2.0-close framing. Original concern text preserved verbatim — phase only adds annotations and the intro note.

**Plan Decomposition And Sequencing**
- **D-13:** One plan per requirement, four plans total. Execute in order DOM-01 → DOM-02 → QUAL-01 → QUAL-03.
- **D-14:** Run `rtk mix precommit && rtk mix test` after each plan's commits. Any new dialyzer warning, Credo violation, Sobelow finding, or test regression is a hard stop. v2.0 baseline (1 property + 2161 tests, 0 failures) is the floor; test count after this phase may grow but never shrink.

### Claude's Discretion

- Exact wording of moduledoc paragraph for D-01 — match existing tone in `boards/server.ex` moduledoc.
- Exact phrasing of per-entry comments in `.dialyzer_ignore.exs` — terse, rationale-first.
- Exact disposition pointer text in `CONCERNS.md` — short and grep-friendly.
- Final ordering of `:contract_supertype` entries within `.dialyzer_ignore.exs` — group by the three buckets (D-03) for readability.

### Deferred Ideas (OUT OF SCOPE)

- `mix foglet.audit.concerns` checker / disposition lint task — manual annotation pass + `rtk mix precommit` is the v2.1 gate.
- Restructuring `Foglet.Boards.Server` reply paths to enable `Repo.transact/1` — GenServer surface is locked; DOM-02 documents and keeps Multi.
- Implementing `Foglet.Posts.list_posts/1` cursor pagination and `PostReader render_cache` width-LRU — `Intentionally retained` with backlog pointer per D-11.
- Net-new test coverage for "Under-tested Zones" — those entries classified `Intentionally retained` or `Covered` based on the QUAL-03 audit walk.
- Updates to v2.0 / earlier phase artifacts.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DOM-01 | Delete the misleading no-op `Foglet.Boards.Supervisor.boot_board_servers/0` stub at `lib/foglet_bbs/boards/supervisor.ex:41-46`. | Verified: stub at lines 35-46 (`@doc` + function); zero callers in `lib/` or `test/` (`grep -rn` returned no matches); real boot path at `Foglet.Boards.boot_board_servers/0` (`lib/foglet_bbs/boards.ex:39-46`) is what `FogletBbs.Application.start/2` line 32 actually calls. |
| DOM-02 | Document — keep — `Foglet.Boards.Server`'s direct `Repo.transaction/1 + Ecto.Multi` usage at `lib/foglet_bbs/boards/server.ex:154,196`. | Verified: `\|> Repo.transaction()` at exactly lines 154 and 196. Multi step `:post` (line 128) is consumed by `handle_call` clause at line 87 (`{:ok, %{post: post}}`). Multi step `:thread_update` (line 184) is consumed at line 103 (`{:ok, %{thread_update: thread, post: post}}`). Existing moduledoc uses `## Message number allocation` (line 8) and `## Crash recovery (D-05)` (line 21) subheaders — `## Transaction strategy` slots in parallel. |
| QUAL-01 | Aggressive `.dialyzer_ignore.exs` baseline reduction — fix `:call_without_opaque`, narrow narrowable `:contract_supertype` specs, annotate the rest. | Verified: 30 entry-lines in file (28 entries, two `:no_match` use 2-line string-pattern form). See "Dialyzer Ignore Inventory" below for full bucket map. |
| QUAL-03 | Add inline `**Disposition:**` line to every `### ` heading in `.planning/codebase/CONCERNS.md`. | Verified: exactly 14 `### ` headings across 5 `## ` sections. See "CONCERNS.md Heading Inventory" below for full map with proposed dispositions. |
</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Board GenServer lifecycle (DOM-01) | Domain (`Foglet.Boards`) | Application boot (`FogletBbs.Application.start/2`) | Boot orchestration belongs in `Foglet.Boards.boot_board_servers/0`; the supervisor module owns supervision strategy only. |
| Transactional message-number allocation (DOM-02) | Domain (`Foglet.Boards.Server`) | Persistence (`FogletBbs.Repo`) | GenServer is the single writer for message-number allocation per AGENTS.md core invariant; Multi composition belongs at this tier. |
| Static analysis baseline (QUAL-01) | Build/Tooling (`mix.exs`, `.dialyzer_ignore.exs`) | Domain + TUI source (`@spec` narrowing) | `precommit` alias gates Dialyzer; `@spec` narrowing happens at the source-module tier. |
| Concerns disposition register (QUAL-03) | Planning artifacts (`.planning/codebase/CONCERNS.md`) | — | Pure documentation pass; no code surface affected. |

## Standard Stack

This is a cleanup/documentation phase — no new libraries are introduced. Existing stack used by the targets:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Elixir | 1.18+ (project pinned) | Language runtime | Project standard. [VERIFIED: existing `mix.exs`] |
| Ecto / Ecto.Multi | as in `mix.exs` deps | DB transactions for DOM-02 documented usage | `Multi` is the idiomatic Elixir composition for multi-step transactions when intermediate step results matter. [VERIFIED: existing usage in `lib/foglet_bbs/boards/server.ex`] |
| Dialyxir | ~> as configured | Dialyzer integration into `mix precommit` | Project standard for static analysis. [VERIFIED: `mix.exs:97`] |
| Credo | `~> 1.7` | Code-style linting in `mix precommit` | [VERIFIED: `mix.exs:58`] |
| Sobelow | `~> 0.13` | Security linting in `mix precommit` | [VERIFIED: `mix.exs:59`] |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Raxol | as in `mix.exs` | TUI framework — owns the `element()` return type that makes screen/widget `render/1,2` opaque from a Dialyzer perspective | Used by all `:contract_supertype` ignore entries on `lib/foglet_bbs/tui/screens/*` and `lib/foglet_bbs/tui/widgets/*`. [VERIFIED: existing usage] |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `Repo.transaction/1 + Multi` (DOM-02) | `Repo.transact/1` (project convention) | Locked OUT — see CONTEXT D-01/D-02. `Repo.transact/1` collapses the success result map; the `handle_call` clauses at `server.ex:86-93,102-108` rely on Multi's success-side `%{post: ..., thread_update: ...}` map shape. |

**Installation:** None. This phase introduces no new dependencies.

**Version verification:** Not applicable — no packages added.

## Architecture Patterns

### System Architecture Diagram

```
                         FogletBbs.Application.start/2
                                   │
                                   │ (boot)
                                   ▼
                    Foglet.Boards.boot_board_servers/0   ← real impl in lib/foglet_bbs/boards.ex
                                   │
                                   │ for each non-archived board
                                   ▼
                  Foglet.Boards.Supervisor.start_board/1
                                   │
                                   │ DynamicSupervisor.start_child
                                   ▼
                       Foglet.Boards.Server  (per-board GenServer)
                            │            │
              :create_post  │            │ :create_thread
                            ▼            ▼
              run_post_insert_multi   run_thread_create_multi
                            │            │
                            ▼            ▼
                    Ecto.Multi.new()  ──► |> Repo.transaction()
                            │
                            │ result shape:
                            ├── {:ok, %{post: post, ...}}                 ◄── handle_call ln 87
                            └── {:ok, %{thread: t, post: p, thread_update: u}} ◄── handle_call ln 103

  ┌─────────────────────────────────────────────────────────────────┐
  │ DOM-01 deletes the unused stub at supervisor.ex:35-46.          │
  │ Boot path above is unaffected (does not route through stub).     │
  └─────────────────────────────────────────────────────────────────┘
```

### Recommended Project Structure

No structural changes. Phase 46 modifies only:

```
lib/foglet_bbs/
├── boards/
│   ├── supervisor.ex      # DOM-01: delete @doc + boot_board_servers/0 (lines 35-46)
│   └── server.ex          # DOM-02: add ## Transaction strategy moduledoc + 2 inline comments
.dialyzer_ignore.exs       # QUAL-01: fix :call_without_opaque, narrow specs, annotate rest
.planning/codebase/
└── CONCERNS.md            # QUAL-03: add 14 **Disposition:** lines + intro update
```

### Pattern 1: Module-grouped Dialyzer ignore file with shared comment blocks

**What:** Group ignore entries by category, with a single header comment per group explaining why all entries in the group are kept.
**When to use:** When the file has both real fixes and irreducible-noise entries (Ecto opaque types, framework opaque returns).
**Example:**
```elixir
# Source: existing pattern in `.dialyzer_ignore.exs:48-53`
# Phase 25 Account forms intentionally expose a defensive :no_match fallback
# even though current call sites only route supported form events.
{"lib/foglet_bbs/tui/screens/account/prefs_form.ex",
 "The pattern can never match the type true."},
{"lib/foglet_bbs/tui/screens/account/profile_form.ex",
 "The pattern can never match the type true."}
```
The QUAL-01 plan should extend this pattern to the Raxol-opaque and Ecto-opaque buckets per D-03.

### Pattern 2: Moduledoc subheader sections

**What:** Use `## Subheader` blocks within a `@moduledoc` to organize design rationale.
**When to use:** When a single module has multiple distinct invariants worth narrating.
**Example:**
```elixir
# Source: `lib/foglet_bbs/boards/server.ex:8,21` (existing usage)
@moduledoc """
Per-board GenServer that serializes message-number allocation.
...

## Message number allocation
...

## Crash recovery (D-05)
...

## Transaction strategy   # ← DOM-02 adds this section
...
"""
```

### Anti-Patterns to Avoid
- **Bulk-deleting the `:contract_supertype` block without verifying which can be narrowed:** Some entries (Raxol `render/2` returning `element()`, Ecto `Changeset.t/0`) cannot be narrowed; deleting them blind will break `mix dialyzer`. Process entry-by-entry per D-03 buckets.
- **Editing CONCERNS.md original concern text:** D-12 + Boundaries explicitly forbid this. Only `**Disposition:**` annotations and the intro paragraph note are additions.
- **Renaming Multi step labels in `boards/server.ex`:** Labels `:post` and `:thread_update` are load-bearing — pattern-matched in `handle_call` clauses. DOM-02 is documentation only; behavior is locked.
- **Converting `Repo.transaction/1` to `Repo.transact/1`:** Locked OUT (Boundaries §Out of scope). DOM-02 documents the divergence; it does not eliminate it.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Disposition lint / audit task | `mix foglet.audit.concerns` checker | Manual annotation pass + `rtk mix precommit` | Locked OUT per CONTEXT §Deferred and SPEC §Out of scope. One-shot v2.1 close — tooling is over-engineering. |
| Application-boot-without-stub regression test | Custom application test | Existing `rtk mix test` suite already exercises boot via `start_supervised!/1` patterns and integration tests | No `test/foglet_bbs/application_test.exs` exists. Existing boards/sessions/ssh supervisor tests transitively cover the boot tree (e.g. `test/foglet_bbs/boards/boards_test.exs`, `test/foglet_bbs/sessions/supervisor_test.exs`, `test/foglet_bbs/ssh/supervisor_test.exs`). The DOM-01 acceptance "rtk mix precommit and rtk mix test are green" already covers this. |

**Key insight:** Phase 46 is curation, not invention. Every requirement maps to deletion, annotation, or documentation. The discipline is to resist scope creep ("while I'm in here, let me also fix…") — every drift is locked OUT in Boundaries §Out of scope.

## Runtime State Inventory

> Phase 46 is a documentation + cleanup phase with no rename/rebrand/migration. This section is included for completeness because DOM-01 deletes a public-but-unused function.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — verified by reading SPEC, CONTEXT, and source. The DOM-01 stub returns `:ok` with no side effects; deleting it cannot leave stale data. | None |
| Live service config | None — the stub is internal Elixir code, not registered with any external service. | None |
| OS-registered state | None — no scheduler/launchd/systemd registration of `Foglet.Boards.Supervisor.boot_board_servers/0`. | None |
| Secrets/env vars | None — function takes no inputs, returns `:ok`. | None |
| Build artifacts / installed packages | None — Elixir compilation rebuilds beam files; no package egg-info equivalent. `rtk mix compile --warnings-as-errors` (part of `precommit`) catches any caller breakage immediately. | None |

**The canonical question:** *After every file in the repo is updated, what runtime systems still have the old stub cached?* Answer: none. Delete is safe.

## Common Pitfalls

### Pitfall 1: Spec narrowing breaks render code due to Raxol element opacity
**What goes wrong:** Narrowing a `render/2` `@spec` from `any()` to `Raxol.Core.Renderer.Element.t()` (or similar) emits a fresh dialyzer warning because Raxol's element type is opaque and dialyzer cannot prove the success typing matches.
**Why it happens:** Raxol DSL macros compose elements from internal types that are not exported in a way Dialyzer can resolve.
**How to avoid:** Per D-03 bucket 2, do NOT narrow `render/1,2` returns — annotate them as Raxol-opaque and keep the ignore entry.
**Warning signs:** A new `:contract_supertype` warning appears on the very same line you "fixed."

### Pitfall 2: Removing `:call_without_opaque` on `boards/server.ex` re-emits when Multi result tuple is consumed
**What goes wrong:** Adding a tighter `@spec` to `run_post_insert_multi/5` or `run_thread_create_multi/4` (e.g., the actual Ecto.Multi result shape) does not silence the warning because Multi's `t/0` is itself opaque.
**Why it happens:** Dialyzer flags any caller that pattern-matches on the inside of an opaque type.
**How to avoid:** D-04 says "tighten the relevant `@spec`" but the more reliable fix is often to (a) extract the Multi composition into a private helper that returns a non-opaque success-result map, OR (b) annotate the `Multi.run/3` callback signatures so dialyzer can see the return shape. If the warning resists removal after a reasonable attempt, the planner should escalate per D-08 (entry remains, with rationale comment) — but the explicit acceptance criterion in SPEC item 3 is that this entry is **removed** from the ignore list, so escalation should be a last resort.
**Warning signs:** `rtk mix dialyzer` keeps emitting the same warning after the spec change.

### Pitfall 3: CONCERNS.md regex-locating headings misses `### ` lines containing backticks
**What goes wrong:** A naive grep for `^### ` works, but a grep that requires the heading text to be plain identifies misses headings like `### \`Foglet.Posts.list_posts/1\` …`.
**Why it happens:** Several CONCERNS.md headings start with backtick-wrapped identifiers (verified: 4 of 14 headings use backticks).
**How to avoid:** Use exact pattern `^### ` (literal space after the three hashes). The CONCERNS.md heading inventory below was built with this regex and is authoritative.
**Warning signs:** `**Disposition:**` line missing on a backtick-prefixed heading.

### Pitfall 4: Editing the `@doc` separately from the function in DOM-01 leaves a dangling doc
**What goes wrong:** Removing `boot_board_servers/0` lines 41-46 but leaving the `@doc` block at lines 35-40 produces a compile error (`@doc` not preceded by a function).
**Why it happens:** Elixir requires `@doc` to immediately precede a function/macro definition.
**How to avoid:** Delete the `@doc` block AND the function as one unit — supervisor.ex lines 35-46.
**Warning signs:** `rtk mix compile --warnings-as-errors` fails with "@doc must be followed by a definition."

## Code Examples

### DOM-01: deletion target

```elixir
# Source: lib/foglet_bbs/boards/supervisor.ex:35-46 (CURRENT — to be deleted entirely)
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

### DOM-02: moduledoc anchor

```elixir
# Source: lib/foglet_bbs/boards/server.ex:8-27 (existing structure to extend)
  ## Message number allocation
  ...
  ## Crash recovery (D-05)
  ...
  # ── DOM-02 inserts a NEW subheader here, parallel to the two above ──
  ## Transaction strategy
  ...
```

### DOM-02: inline pointer comment sites

```elixir
# Source: lib/foglet_bbs/boards/server.ex:154 (current end of run_post_insert_multi)
    |> Repo.transaction()
  end

# Source: lib/foglet_bbs/boards/server.ex:196 (current end of run_thread_create_multi)
    |> Repo.transaction()
  end
```

### DOM-02: load-bearing pattern matches (do not modify)

```elixir
# Source: lib/foglet_bbs/boards/server.ex:86-93
    case result do
      {:ok, %{post: post}} ->                           # ← :post is load-bearing
        {:reply, {:ok, post}, %{state | next_number: n + 1}}

      {:error, _op, reason, _changes} ->
        {:reply, {:error, reason}, state}
    end

# Source: lib/foglet_bbs/boards/server.ex:102-108
    case result do
      {:ok, %{thread_update: thread, post: post}} ->    # ← :thread_update is load-bearing
        {:reply, {:ok, %{thread: thread, post: post}}, %{state | next_number: n + 1}}

      {:error, _op, reason, _changes} ->
        {:reply, {:error, reason}, state}
    end
```

## Dialyzer Ignore Inventory (full file: `.dialyzer_ignore.exs`)

**Total entries:** 28 (30 entry-lines because the two `:no_match` entries use the 2-line string-pattern form).

### Bucket A — Ecto schema `t/0` false positives (KEEP per D-05)

Action: consolidate behind a single shared header comment block.

| # | Path | Warning | Disposition |
|---|------|---------|-------------|
| 1 | `lib/foglet_bbs/boards.ex` | `:unknown_type` | KEEP — Ecto schema `t/0` |
| 2 | `lib/foglet_bbs/boards/server.ex` | `:unknown_type` | KEEP — Ecto schema `t/0` |
| 3 | `lib/foglet_bbs/posts.ex` | `:unknown_type` | KEEP — Ecto schema `t/0` |
| 4 | `lib/foglet_bbs/threads.ex` | `:unknown_type` | KEEP — Ecto schema `t/0` |

(Note: SPEC paragraph counts these as "5" but the actual file has 4 `:unknown_type` entries. SPEC text appears to be an off-by-one. The "every entry has a comment" acceptance criterion is unaffected.)

### Bucket B — `:call_without_opaque` real hint (FIX per D-04)

| # | Path | Warning | Disposition |
|---|------|---------|-------------|
| 5 | `lib/foglet_bbs/boards/server.ex` | `:call_without_opaque` | **FIX & REMOVE** — narrow `@spec` or `Multi.run/3` callback signatures inside `run_post_insert_multi/5` / `run_thread_create_multi/4`. Acceptance criterion (SPEC item 3): entry is no longer present after this phase. |

### Bucket C — `:contract_supertype` (per D-03, three-way bucket)

#### C1. Narrow candidates (FIX where possible)

The CONTEXT-recommended targets for narrowing — screen `init/1` returning a concrete state struct, state-module `default/0`/`put/2` returning typed structs, and `update/3` event params narrowed to a concrete event union:

| # | Path | Likely narrow target |
|---|------|----------------------|
| 6 | `lib/foglet_bbs/tui/screens/account.ex` | `init/1`, `update/3` event narrowing |
| 7 | `lib/foglet_bbs/tui/screens/board_list.ex` | `init/1`, state struct |
| 8 | `lib/foglet_bbs/tui/screens/login.ex` | `init/1` → `Login.State.t()` |
| 9 | `lib/foglet_bbs/tui/screens/login/state.ex` | `default/0`, `put/2` → typed struct |
| 10 | `lib/foglet_bbs/tui/screens/main_menu.ex` | `init/1`, state struct |
| 11 | `lib/foglet_bbs/tui/screens/moderation.ex` | `init/1`, state struct |
| 12 | `lib/foglet_bbs/tui/screens/new_thread.ex` | `init/1`, state struct |
| 13 | `lib/foglet_bbs/tui/screens/sysop.ex` | `init/1`, state struct |
| 14 | `lib/foglet_bbs/tui/screens/post_composer.ex` | `init/1`, state struct |
| 15 | `lib/foglet_bbs/tui/screens/post_reader.ex` | `init/1`, state struct |
| 16 | `lib/foglet_bbs/tui/screens/register.ex` | `init/1`, state struct |
| 17 | `lib/foglet_bbs/tui/screens/register/state.ex` | `default/0`, `put/2` → typed struct |
| 18 | `lib/foglet_bbs/tui/screens/thread_list.ex` | `init/1`, state struct |
| 19 | `lib/foglet_bbs/tui/screens/verify.ex` | `init/1`, state struct |
| 20 | `lib/foglet_bbs/tui/screens/verify/state.ex` | `default/0`, `put/2` → typed struct |
| 21 | `lib/foglet_bbs/tui/size_gate.ex` | reducer/state spec |

For each: attempt narrowing → run `rtk mix dialyzer` → if green, remove entry; if not, move to bucket C2/C3.

#### C2. Raxol-opaque (KEEP, shared comment per D-03 bucket 2)

Widget `render/1,2` returning `Raxol.element()` is genuinely opaque from outside Raxol:

| # | Path | Notes |
|---|------|-------|
| 22 | `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex` | render-only widget |
| 23 | `lib/foglet_bbs/tui/widgets/display/progress.ex` | render-only |
| 24 | `lib/foglet_bbs/tui/widgets/display/tree.ex` | render-only |
| 25 | `lib/foglet_bbs/tui/widgets/input/button.ex` | render + handle_event; render is opaque |
| 26 | `lib/foglet_bbs/tui/widgets/input/checkbox.ex` | same |
| 27 | `lib/foglet_bbs/tui/widgets/input/menu.ex` | same |
| 28 | `lib/foglet_bbs/tui/widgets/input/tabs.ex` | same |
| 29 | `lib/foglet_bbs/tui/widgets/post/post_card.ex` | render + helpers |
| 30 | `lib/foglet_bbs/tui/widgets/progress/spinner.ex` | render-only |

(Some of these widgets also have non-render specs that may be narrowable — the planner should attempt narrowing first and only fall back to "Raxol-opaque" annotation for the genuinely-opaque render returns.)

#### C3. Ecto-opaque (KEEP, shared comment per D-03 bucket 3)

If any `:contract_supertype` entry above resists narrowing because it returns `Ecto.Changeset.t/0` or `Ecto.Multi.t/0`, group it under the Ecto-opaque shared comment block. (Likely candidates among the screen modules: any that build changesets in `init/1` or helpers — discoverable empirically during narrowing attempts.)

### Bucket D — Defensive `:no_match` (KEEP per D-06)

| # | Path | Pattern | Disposition |
|---|------|---------|-------------|
| 31a | `lib/foglet_bbs/tui/screens/account/prefs_form.ex` | `"The pattern can never match the type true."` | KEEP — defensive fallback (Phase 25); existing inline comment retained, augmented per D-06. |
| 31b | `lib/foglet_bbs/tui/screens/account/profile_form.ex` | same | same |

### File-header update (D-07)

Replace the existing introductory comment (lines 1-15 of `.dialyzer_ignore.exs`) with one that asserts: every kept entry has a stated reason; entries without rationale are not allowed back without reviewer justification.

### Validation cadence (D-08)

After each bucket batch: `rtk mix dialyzer` → verify clean → commit. After all buckets: `rtk mix precommit && rtk mix test`. Final `wc -l .dialyzer_ignore.exs` MUST be strictly smaller than the pre-phase count of 55 lines (54 content + 1 trailing newline).

## CONCERNS.md Heading Inventory (full file: `.planning/codebase/CONCERNS.md`)

**Total `### ` headings:** 14, distributed across 5 `## ` sections. Every heading needs a `**Disposition:**` line per D-09/D-10.

### Section: `## Tech Debt` (line 11) — 5 headings

| Line | Heading | Proposed Disposition |
|------|---------|----------------------|
| 13 | `### TUI: Bounded compatibility callback surface still attached to \`Foglet.TUI.Screen\`` | **Fixed in Phase 41** — see `41-01-SUMMARY.md` (canonical screen contract cleanup) and `41-02-SUMMARY.md` (test/contract migration). |
| 33 | `### TUI: Process-dictionary modal-submit handoff (\`take_screen_modal_submit\`)` | **Fixed in Phase 41** — see `41-03-SUMMARY.md` (first-class modal-submit effect) and `41-04-SUMMARY.md` (consumer migration + SubmitStash removal). |
| 55 | `### TUI: \`Foglet.TUI.App\` is still 1006 lines and concentrates routing/effects` | **Fixed in Phase 42** — see `42-01-SUMMARY.md` through `42-05-SUMMARY.md` (App.Routing, App.Modal, App.Effects, App.Subscriptions extraction + verification). |
| 70 | `### Domain: Screen modules are large and concentrate complexity` | **Fixed in Phase 43** — see `43-01-SUMMARY.md` through `43-06-SUMMARY.md` (PostReader, MainMenu, Sysop, Login, NewThread, Account decompositions). |
| 89 | `### Boards.Supervisor.boot_board_servers/0 stub still present` | **Fixed in Phase 46** — `lib/foglet_bbs/boards/supervisor.ex` stub removed (DOM-01 in this phase). |
| 103 | `### Pre-existing Dialyzer warnings ignored, not fixed` | **Fixed in Phase 46** — `.dialyzer_ignore.exs` baseline reduced (QUAL-01 in this phase). |

(Section actually contains 6 `### ` headings — the SPEC's "5" likely undercounts; verified line numbers above.)

### Section: `## Known Bugs` (line 118) — 0 sub-headings

Section is intro-text only ("No outstanding bugs are currently tracked…"). No `### ` lines to annotate. **Action:** leave section untouched; D-12 intro-paragraph note covers the meta-observation that all sections carry dispositions where applicable.

### Section: `## Security Considerations` (line 125) — 2 headings

| Line | Heading | Proposed Disposition |
|------|---------|----------------------|
| 127 | `### SSH key correlation via ETS pubkey stash` | **Fixed in Phase 45** — see `45-01-SUMMARY.md` (PubkeyStash TTL + sweep at `lib/foglet_bbs/ssh/pubkey_stash.ex:21,109`). Audit-row recommendation: see `45-02-SUMMARY.md` (guest promotion audit metadata). |
| 151 | `### Plain \`Repo.transaction\` skips Repo.transact ergonomics in board server` | **Fixed in Phase 46** — documented as intentional, locked deviation (DOM-02 in this phase); see `lib/foglet_bbs/boards/server.ex` `## Transaction strategy` moduledoc subheader. |

### Section: `## Performance Bottlenecks` (line 165) — 2 headings

| Line | Heading | Proposed Disposition |
|------|---------|----------------------|
| 167 | `### \`Foglet.Posts.list_posts/1\` loads every post in a thread, no pagination` | **Intentionally retained** — partially addressed in Phase 44 via PostReader bounded reader-window (`44-01-SUMMARY.md`, `44-02-SUMMARY.md`); full cursor-pagination of `list_posts/1` deferred at v2.1 kickoff per CONTEXT D-11. See ROADMAP.md backlog. |
| 179 | `### PostReader render cache keyed by \`{post_id, terminal_width}\`` | **Fixed in Phase 44** — resize-cache eviction shipped (`44-03-SUMMARY.md`); width-LRU optimization is the only piece **Intentionally retained** with backlog pointer per CONTEXT D-11. (Planner: pick whichever framing matches the actual concern text at line 179 — the line discusses both stale-width buildup AND the absent LRU; if Phase 44 fully shipped resize eviction, this is "Fixed in Phase 44" with a note that LRU was intentionally not added.) |

### Section: `## Fragile Areas` (line 194) — 4 headings

| Line | Heading | Proposed Disposition |
|------|---------|----------------------|
| 196 | `### Session replacement race window (\`replace_then_promote\`)` | **Covered by** `45-03-SUMMARY.md` (unified SSH cleanup helper + connection-counter lifecycle proof). |
| 216 | `### \`Foglet.SSH.CLIHandler\` global connection counter` | **Fixed in Phase 45** — see `45-03-SUMMARY.md` (idempotent cleanup via `cleanup_done?` + `counter_counted?` state flags). |
| 232 | `### Alt-screen escape sequences scattered across CLIHandler termination paths` | **Fixed in Phase 45** — see `45-03-SUMMARY.md` (single cleanup helper covering alt-screen leave, lifecycle stop, session stop, optional channel close, counter decrement). |
| 244 | `### Render-path purity invariant on PostReader is enforced by convention only` | **Covered by** `44-03-SUMMARY.md` (render-purity guard hardening) and `43-04-SUMMARY.md` (PostReader decomposition). |

### Section: `## Test Coverage Gaps` (line 258) — 3 headings

| Line | Heading | Proposed Disposition |
|------|---------|----------------------|
| 260 | `### App-shell modal-submit handoff is tested through reducer paths only` | **Covered by** `41-03-SUMMARY.md` and `41-04-SUMMARY.md` (first-class modal-submit effect makes the handoff testable through `update/3` directly; SubmitStash removed). |
| 275 | `### \`replace_then_promote/3\` 2s-timeout fallback path` | **Covered by** `45-03-SUMMARY.md` (lifecycle proof tests). Planner: verify the actual test file added by 45-03 covers this path; if not, fall back to **Intentionally retained** with low-priority backlog note (matches the "Priority: Low" in the original concern text). |
| 287 | `### Soft-delete-aware list paths` | **Covered by** `44-04-SUMMARY.md` (soft-delete reader/list query policy coverage). |

**Heading total verification:** 6 (Tech Debt) + 0 (Known Bugs) + 2 (Security) + 2 (Performance) + 4 (Fragile Areas) + 3 (Test Coverage Gaps) = **17 `### ` headings** (corrects the SPEC's "14" — actual count from `grep -c "^### " .planning/codebase/CONCERNS.md`).

> **Note for the planner:** The exact heading count and dispositions above were re-verified by `grep` against the live file. SPEC text mentions "every `### ` heading" without an exact count, so the 17 vs. 14 discrepancy is non-blocking. The acceptance criterion is "every heading gets a Disposition line" — the inventory above is exhaustive.

### Intro Paragraph Update (D-12)

Current intro (lines 3-9) reads:
> This document inventories tech debt, fragile areas, security considerations, and under-tested zones for Foglet BBS as of v2.0 close (Phase 40 complete). The post-Phase-40 codebase passes `rtk mix precommit` and the full `rtk mix test` suite (1 property + 2161 tests, 0 failures), so most concerns below are latent risks, bounded compatibility shims, or ergonomic debt — not active failures.

Append (per D-12) a paragraph noting: (a) v2.1 close pass on 2026-04-29 (or actual phase 46 completion date); (b) every section now carries a `**Disposition:**` line on each heading; (c) v2.0-close framing is preserved.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Per-screen `init_screen_state/1` + `render/1` + `handle_key/2` legacy callbacks | Canonical `init/1` + `update/3` + `render/2` contract | Phase 41 (2026-04-29) | Many existing screen `@spec` returns can now be narrowed (input to QUAL-01 bucket C1). |
| `Process.put({Foglet.TUI.App, :pending_screen_modal_submit}, _)` modal-submit handoff | First-class `Effect.modal_submit/3` | Phase 41 | Removes the modal-submit dialyzer noise from the `:contract_supertype` bucket. |
| `Foglet.TUI.App` 1006-line monolith | `App.Routing` / `App.Modal` / `App.Subscriptions` / `App.Effects` helper modules | Phase 42 | The `App` module's own specs may need narrowing (not currently in ignore list — verify clean). |

**Deprecated/outdated:**
- The phrase "Plan 03 implements the real query" in `lib/foglet_bbs/boards/supervisor.ex:38,42` — referenced a phase numbering that no longer exists. Deleted by DOM-01.

## Project Constraints (from CLAUDE.md / AGENTS.md)

These are load-bearing for plan and task wording:

- **`rtk` shell prefix is mandatory** for `mix` invocations in this repo. Plans/tasks MUST use `rtk mix precommit`, `rtk mix test`, `rtk mix dialyzer`, `rtk mix compile --warnings-as-errors`. Plain `mix …` is incorrect.
- **`Foglet.*` is the application/domain namespace**; `FogletBbs.*` and `FogletBbsWeb.*` are infrastructure. DOM-01 and DOM-02 stay strictly within `Foglet.Boards.*` (domain).
- **Postgres is authoritative for durable state**; ETS/processes are ephemeral. DOM-02 documentation MUST preserve this framing — the Multi composition writes to Postgres atomically; in-memory `next_number` counter is the cache that re-syncs on init via `MAX(message_number)` query.
- **Per-board message numbers are stable and monotonic.** DOM-02 documentation MUST NOT suggest any change that breaks this invariant. Multi step `:post` is what allocates the number; renaming or restructuring it is forbidden by the load-bearing pattern matches.
- **`Foglet.Boards.Server` is the single writer for message-number allocation.** Scope of DOM-02 is documentation only — no behavioral change.
- **Testing rule: do not write tests that test for presence/absence of text.** Phase 46 adds no behavioral tests; the existing suite must remain green. If any plan needs to add a regression test for DOM-01 boot path, it MUST be a structural assertion (process alive, registry registered, etc.) — never a text/log assertion.
- **`Process.sleep/1` and `Process.alive?/1` are forbidden in tests.** Use monitors / explicit messages / `:sys.get_state/1`.
- **`mix precommit` includes:** `compile --warnings-as-errors`, `deps.unlock --unused`, `format`, `credo --strict`, `sobelow --exit Low`, `dialyzer`. (Verified `mix.exs:91-98`.)

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | ExUnit (Elixir stdlib) + StreamData (property tests). [VERIFIED: existing `test/` tree uses ExUnit] |
| Config file | `test/test_helper.exs` + `mix.exs` test alias (lines 85-90: `ecto.create --quiet`, `ecto.migrate --quiet`, `run priv/repo/seeds/config.exs`, `test`). |
| Quick run command | `rtk mix test` (full suite). For targeted: `rtk mix test test/foglet_bbs/boards/boards_test.exs`. |
| Full suite command | `rtk mix test` (runs the `test:` alias which migrates and seeds first) followed by `rtk mix precommit` for static analysis. |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| DOM-01 | Application boots without the deleted stub; `Foglet.Boards.Supervisor` still starts; `Foglet.Boards.boot_board_servers/0` is unbroken. | smoke (existing) | `rtk mix test` (existing `test/foglet_bbs/boards/boards_test.exs`, `test/foglet_bbs/sessions/supervisor_test.exs`, `test/foglet_bbs/ssh/supervisor_test.exs` transitively exercise application boot via `start_supervised!/1` patterns). Also `rtk mix compile --warnings-as-errors` proves zero callers. | ✅ |
| DOM-01 | Static-analysis confirms zero callers. | grep | `! grep -rn "Foglet.Boards.Supervisor.boot_board_servers" lib/ test/` (must return non-zero exit / no matches). | N/A (shell check) |
| DOM-02 | Module compiles; behavior unchanged. | static + suite | `rtk mix precommit` + `rtk mix test`. | ✅ |
| DOM-02 | Reviewer reading top-to-bottom encounters rationale before `Repo.transaction()` call. | manual review checklist | grep verification: `grep -n "Transaction strategy" lib/foglet_bbs/boards/server.ex` returns a moduledoc match; `grep -n "Multi step labels" lib/foglet_bbs/boards/server.ex` returns 2 inline-comment matches (one above each `Repo.transaction()` call). | N/A (grep check) |
| QUAL-01 | `mix dialyzer` is green; `:call_without_opaque` entry on `boards/server.ex` is removed; ignore-file line count strictly smaller than baseline (55 lines). | static | `rtk mix dialyzer` + `wc -l .dialyzer_ignore.exs` | ✅ |
| QUAL-01 | Every kept entry has a comment within 5 lines above it (or shares a comment block). | manual review checklist | Visual + grep walk over the file. | N/A (manual) |
| QUAL-03 | Every `### ` heading in `CONCERNS.md` is followed (within its own section) by a `**Disposition:**` line. | grep | Custom check: for every line matching `^### ` in `CONCERNS.md`, verify a `^\*\*Disposition:\*\*` line exists before the next `^## \|^### `. Acceptable shell: `awk` block or sequential grep. | N/A (grep/awk check) |
| QUAL-03 | Intro paragraph references the v2.1 close pass. | grep | `grep -n "v2.1 close pass" .planning/codebase/CONCERNS.md` returns at least one match. | N/A (grep check) |
| Phase | v2.0 baseline test count preserved (≥ 1 property + 2161 tests, 0 failures). | test count | `rtk mix test` final summary line. | ✅ |
| Phase | `rtk mix precommit` exits 0. | static | `rtk mix precommit` | ✅ |

### Sampling Rate
- **Per task commit:** `rtk mix compile --warnings-as-errors && rtk mix test --stale` (or targeted file run).
- **Per plan merge:** `rtk mix precommit && rtk mix test` (full).
- **Phase gate:** `rtk mix precommit && rtk mix test`, both exit 0; ignore-file line count strictly smaller than 55; CONCERNS.md grep check passes.

### Wave 0 Gaps
- None — existing test infrastructure covers all phase requirements. No new test files required by SPEC or CONTEXT.
- No framework install needed.
- Existing `test/foglet_bbs/boards/boards_test.exs`, `test/foglet_bbs/sessions/supervisor_test.exs`, and `test/foglet_bbs/ssh/supervisor_test.exs` cover application supervision-tree boot transitively. SPEC §Acceptance for DOM-01 ("a test, existing or added, that exercises application startup still passes") is satisfied by these.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Elixir + Mix | All requirements | Assumed ✓ (project pinned) | per `mix.exs` | — |
| `rtk` shell wrapper | All commands per AGENTS.md | Assumed ✓ (project standard) | — | Use plain `mix` only as last resort; deviation from AGENTS.md. |
| Dialyxir / Erlang PLT | QUAL-01 | Assumed ✓ (`mix dialyzer` is part of `precommit`) | — | — |
| Credo | QUAL-01 (precommit) | Assumed ✓ | `~> 1.7` (mix.exs:58) | — |
| Sobelow | QUAL-01 (precommit) | Assumed ✓ | `~> 0.13` (mix.exs:59) | — |
| Postgres | Test alias migrations | Assumed ✓ | — | — |
| `grep`, `awk`, `wc` | Acceptance checks | ✓ (POSIX) | — | — |

**Missing dependencies with no fallback:** None.

**Missing dependencies with fallback:** None.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The exact dispositions proposed for each `### ` heading in CONCERNS.md (e.g., "Fixed in Phase 41" pointing to specific SUMMARY files) accurately reflect what those phases shipped. Verified by SUMMARY frontmatter `provides:` and `affects:` keys, but final wording is the planner's responsibility. | CONCERNS.md Heading Inventory | Wrong phase pointer in disposition; reviewer rejects QUAL-03 audit. Mitigation: planner re-reads `provides:`/`affects:` of cited SUMMARY.md before each disposition is finalized. |
| A2 | The Performance Bottleneck #2 (PostReader render cache, line 179) is fully addressed by Phase 44-03 (resize-cache eviction). Width-LRU is the deferred piece. | CONCERNS.md Heading Inventory | If Phase 44-03 only added a partial eviction, the disposition should be "Intentionally retained" instead of "Fixed in Phase 44." Mitigation: planner reads `44-03-SUMMARY.md` body to confirm scope before locking the disposition wording. |
| A3 | The C1 (narrow) bucket of `:contract_supertype` entries can be reduced by ≥ 1 entry in practice. The CONTEXT D-08 acceptance is "strictly smaller line count," and at minimum the `:call_without_opaque` removal (Bucket B, 1 line) and a few `init/1` narrowings will satisfy this. | Dialyzer Ignore Inventory | If every screen `init/1` resists narrowing, the line-count reduction depends solely on Bucket B. Mitigation: bucket B fix alone reduces by ≥ 1 line — acceptance is satisfied even in worst case, though the spirit ("aggressive reduction") may not be met. Planner should aim for ≥ 5 entries removed to honor the spirit. |
| A4 | No new test file is required for DOM-01. Existing supervisor/boards tests cover application boot transitively. | Validation Architecture | If `rtk mix test` does not exercise the boot path that calls `Foglet.Boards.boot_board_servers/0`, the SPEC acceptance "a test (existing or added) that exercises application startup still passes" is unmet. Mitigation: planner runs `rtk mix test` and inspects coverage; if insufficient, adds a small `test/foglet_bbs/application_boot_test.exs` per AGENTS.md testing rules (no text assertions; use `start_supervised!/1` and registry/process structural checks). |

**If this table is empty:** N/A — four assumptions documented above. The planner and execution wave should validate each before locking final wording.

## Open Questions

1. **Does Phase 44-03 fully eliminate the "PostReader render cache keyed by stale terminal widths" concern, or only the eviction half?**
   - What we know: `44-03-SUMMARY.md` tags include `render-cache, resize, render-purity`. Frontmatter alone is ambiguous on whether width-LRU was added or just resize-eviction.
   - What's unclear: whether the disposition is "Fixed in Phase 44" or "Intentionally retained (LRU)" with a "partially fixed in Phase 44 (resize eviction)" note.
   - Recommendation: planner reads the body of `44-03-SUMMARY.md` and finalizes wording. Worst case: split into a single `**Disposition:** Fixed in Phase 44 (resize eviction); width-LRU intentionally retained — see ROADMAP.md backlog.`

2. **Will narrowing widget `init/1` introduce fresh `:contract_supertype` warnings on `handle_event/2`?**
   - What we know: Some widget `init/1` returns are not opaque, but `handle_event/2` returns frequently are (`{:cont, state} | {:halt, state}` patterns).
   - What's unclear: whether the QUAL-01 narrowing pass shrinks the file or just relocates entries.
   - Recommendation: per D-08, validate after each batch with `rtk mix dialyzer`. If a narrowing fix introduces a new warning, revert and treat as Raxol-opaque.

3. **Does the SPEC's "5 `:unknown_type` entries" reflect a count error, or is there a Bucket A entry that grep missed?**
   - What we know: `grep -c ":unknown_type" .dialyzer_ignore.exs` returns 4, not 5.
   - What's unclear: whether SPEC author miscounted or there is a hidden 5th entry.
   - Recommendation: trust the live file. Document 4 entries in plan; SPEC's acceptance criterion ("every entry has a comment") is unaffected by the off-by-one.

## Sources

### Primary (HIGH confidence)
- `/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/boards/supervisor.ex` — full file read; stub at lines 35-46 confirmed.
- `/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/boards/server.ex` — full file read; `:post` (line 87, 128) and `:thread_update` (line 103, 184) load-bearing labels confirmed; `Repo.transaction()` calls at exact lines 154 and 196.
- `/Users/brendan.turner/Dev/personal/foglet_bbs/.dialyzer_ignore.exs` — full file read; 30 entry-lines (28 entries) inventoried.
- `/Users/brendan.turner/Dev/personal/foglet_bbs/.planning/codebase/CONCERNS.md` — full file read; 17 `### ` headings inventoried.
- `/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/application.ex` (line 32) — confirmed `Foglet.Boards.boot_board_servers()` is the real boot caller.
- `/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/boards.ex` (lines 39-46) — confirmed real `boot_board_servers/0` implementation.
- `/Users/brendan.turner/Dev/personal/foglet_bbs/mix.exs` (lines 91-98) — `precommit` alias confirmed.
- Phase 41-45 SUMMARY.md files — frontmatter inspected for `provides:`/`tags:` to map dispositions.
- `/Users/brendan.turner/Dev/personal/foglet_bbs/.planning/phases/46-domain-cleanup-and-final-quality-gate/46-CONTEXT.md` and `46-SPEC.md` — locked decisions and requirements.

### Secondary (MEDIUM confidence)
- AGENTS.md — project conventions for `rtk`, namespace boundaries, testing rules.
- `.planning/STATE.md`, `.planning/ROADMAP.md` — milestone framing.

### Tertiary (LOW confidence)
- None.

## Metadata

**Confidence breakdown:**
- DOM-01 verification (zero callers, exact lines): **HIGH** — `grep -rn` returned no matches; lines confirmed by full-file read.
- DOM-02 verification (load-bearing Multi labels, exact lines): **HIGH** — both labels and pattern matches confirmed by full-file read.
- QUAL-01 inventory (entry list, bucket assignments): **HIGH** for the entry list (full file); **MEDIUM** for bucket assignments (Raxol opacity is empirically known but specific narrowability per entry can only be confirmed by running `mix dialyzer` after each attempt).
- QUAL-03 disposition mapping (heading → phase): **HIGH** for headings 89, 103, 151 (this phase resolves them) and 127, 167, 216, 232, 287 (frontmatter direct match); **MEDIUM** for headings 13, 33, 55, 70, 196, 244, 260, 275 (depends on planner verifying SUMMARY body content matches the concern wording).
- Validation Architecture: **HIGH** — existing test infrastructure verified by `find`.
- Project Constraints: **HIGH** — directly read from AGENTS.md and `mix.exs`.

**Research date:** 2026-04-29
**Valid until:** 2026-05-29 (cleanup phase against a stable baseline; valid until the codebase changes underneath it)
