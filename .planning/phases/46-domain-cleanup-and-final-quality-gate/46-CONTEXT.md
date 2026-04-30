# Phase 46: Domain Cleanup And Final Quality Gate - Context

**Gathered:** 2026-04-29 (assumptions mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 46 closes v2.1 by resolving the four remaining tech-debt items locked in
`46-SPEC.md`:

- **DOM-01.** Delete the misleading no-op `Foglet.Boards.Supervisor.boot_board_servers/0`
  stub at `lib/foglet_bbs/boards/supervisor.ex:41-46`. The real boot path stays at
  `Foglet.Boards.boot_board_servers/0`.
- **DOM-02.** Document — keep — `Foglet.Boards.Server`'s direct
  `Repo.transaction/1 + Ecto.Multi` usage at `lib/foglet_bbs/boards/server.ex:154,196`
  as an intentional, locked deviation from the project-wide `Repo.transact/1`
  convention. Multi step names (`:post`, `:thread_update`) are load-bearing for
  the `handle_call` clauses at `:86-93,:102-108`.
- **QUAL-01.** Aggressive `.dialyzer_ignore.exs` baseline reduction: fix the
  audit-flagged `boards/server.ex :call_without_opaque`, narrow every
  `:contract_supertype` spec that can be narrowed, annotate the rest with
  per-entry rationale, and update the file header.
- **QUAL-03.** Add an inline `**Disposition:**` line to every `### ` heading in
  `.planning/codebase/CONCERNS.md` (Tech Debt → Known Bugs → Security → Performance
  → Under-tested Zones), classified as `Fixed in Phase NN`, `Intentionally retained`,
  or `Covered by …`. Update the intro paragraph to reference the v2.1 close pass.

Out of scope (locked deferrals from SPEC §Boundaries): implementing deferred
perf bottlenecks (`list_posts/1` cursor, `PostReader render_cache` width-LRU),
new security hardening beyond what shipped in 41–45, net-new test coverage for
"Under-tested Zones", any audit-enforcement tooling, restructuring
`Foglet.Boards.Server` reply paths, and editing v2.0/earlier phase artifacts.
</domain>

<decisions>
## Implementation Decisions

### DOM-02 Documentation Placement

- **D-01:** Add a `## Transaction strategy` subheader paragraph to the existing
  `@moduledoc` of `lib/foglet_bbs/boards/server.ex` (which already uses
  `## Message number allocation` and `## Crash recovery` subheaders). The
  paragraph names the `Repo.transaction/1 + Ecto.Multi` choice as intentional,
  cites the `:post` and `:thread_update` step labels, references the
  `handle_call` clauses at `server.ex:86-93,102-108` that depend on those
  labels for success-side extraction, and explicitly states the divergence
  from the project-wide `Repo.transact/1` convention is locked.
- **D-02:** Add a one-line inline pointer comment immediately above each
  `|> Repo.transaction()` site at `:154` and `:196`, e.g.
  `# Multi step labels :post / :thread_update are load-bearing — see @moduledoc`.
  This satisfies the SPEC requirement that a top-to-bottom reader encounters
  the rationale before the call without duplicating the full explanation.

### QUAL-01 Dialyzer Baseline Reduction Strategy

- **D-03:** Walk the `:contract_supertype` entries in three buckets and act
  per bucket:
  1. **Narrow.** Screen `init/1` returning `map()` → return the concrete state
     struct (e.g. `LoginState.t()`); state-module `default/0` and `put/2`
     returning typed structs; `update/3` event params typed as `term()` →
     narrow where a concrete event union exists. Fix and remove the matching
     ignore entry.
  2. **Annotate as Raxol-opaque.** Any `render/1,2` returning `any()` is
     genuinely opaque from outside Raxol. Keep these entries with a single
     shared comment block headed
     `# Raxol element() return — opaque from caller perspective`.
  3. **Annotate as Ecto-opaque.** Any `:contract_supertype` tied to
     `Ecto.Changeset.t/0`, `Ecto.Multi.t/0`, or similar. Keep with a shared
     comment block.
- **D-04:** Fix `{"lib/foglet_bbs/boards/server.ex", :call_without_opaque}`
  by tightening the relevant `@spec` (or the `Multi.run/3` callback signatures
  inside `run_post_insert_multi/5` / `run_thread_create_multi/4`) so dialyzer
  no longer flags Multi result-tuple opacity. Remove the entry from
  `.dialyzer_ignore.exs`.
- **D-05:** Keep the existing `:unknown_type` entries on `boards.ex`,
  `boards/server.ex`, `posts.ex`, `threads.ex` (Ecto schema `t/0` false
  positives) and consolidate their rationale into a single header comment
  block above the group.
- **D-06:** Keep the two `:no_match` entries on
  `account/prefs_form.ex` and `account/profile_form.ex` (defensive Phase 25
  fallbacks) with a per-entry comment naming the defensive intent. Carry
  over the existing inline rationale; do not delete the comment that is
  already there.
- **D-07:** Update the file header comment to describe the post-cleanup
  invariant: every kept entry has a stated reason, and entries without
  rationale are not allowed back without reviewer justification.
- **D-08:** Validate after each batch with `rtk mix dialyzer` and
  `rtk mix precommit`. The line count of `.dialyzer_ignore.exs` after this
  phase MUST be strictly smaller than before. Exact end-state count depends
  on how many `:contract_supertype` specs resist narrowing — not pre-locked.

### QUAL-03 CONCERNS.md Disposition Walk

- **D-09:** Walk `.planning/codebase/CONCERNS.md` top-to-bottom in existing
  file order (Tech Debt → Known Bugs → Security Considerations →
  Performance Bottlenecks → Under-tested Zones). For each `### ` heading,
  insert a `**Disposition:**` line within that heading's section, before
  the next `### ` or `## ` heading.
- **D-10:** Disposition values are exactly three: `Fixed in Phase NN`,
  `Intentionally retained`, or `Covered by …`. Cross-reference dispositions
  against `.planning/phases/41-…` through `45-…` SUMMARY.md files to assign
  correct phase pointers. Each `Fixed in Phase NN` line includes a one-line
  pointer (file path, function, or SUMMARY anchor). Each `Intentionally
  retained` line names the rationale and, when applicable, a backlog
  pointer (`see ROADMAP.md backlog`). Each `Covered by …` line names the
  test or doc artifact.
- **D-11:** SSH `PubkeyStash` TTL/sweep concern → `Fixed in Phase 45`
  (`lib/foglet_bbs/ssh/pubkey_stash.ex:21,109`, sweep + TTL constants).
  Deferred perf items (`Foglet.Posts.list_posts/1` cursor pagination,
  `PostReader render_cache` width-LRU) → `Intentionally retained` with
  the v2.1-kickoff deferral rationale and a backlog pointer.
- **D-12:** Update the file's intro paragraph to note the v2.1 close pass,
  state that every section now carries a disposition, and preserve the
  existing v2.0-close framing. Original concern text is preserved verbatim;
  this phase only adds annotations and the intro note.

### Plan Decomposition And Sequencing

- **D-13:** One plan per requirement, four plans total. Execute in order
  DOM-01 → DOM-02 → QUAL-01 → QUAL-03. Rationale: DOM-01 is the smallest
  isolated delete; DOM-02 is doc-only with no behavior change; QUAL-01 is
  the highest-risk requirement (touches 24+ specs across screens and
  widgets, gated by dialyzer); QUAL-03 is the capstone audit and benefits
  from QUAL-01 already being resolved so dialyzer-related dispositions
  in CONCERNS.md are accurate.
- **D-14:** Run `rtk mix precommit && rtk mix test` after each plan's
  commits, not only at phase end. Any new dialyzer warning, Credo
  violation, Sobelow finding, or test regression is a hard stop. The v2.0
  baseline (1 property + 2161 tests, 0 failures) is the floor; the test
  count after this phase is allowed to grow but never shrink.

### Claude's Discretion

- Exact wording of moduledoc paragraph for D-01 — match existing tone in
  `boards/server.ex` moduledoc.
- Exact phrasing of per-entry comments in `.dialyzer_ignore.exs` — terse,
  rationale-first.
- Exact disposition pointer text in `CONCERNS.md` — short and grep-friendly.
- Final ordering of `:contract_supertype` entries within
  `.dialyzer_ignore.exs` — group by the three buckets (D-03) for
  readability.

### Folded Todos

None — `gsd-sdk query todo.match-phase 46` returned zero matches.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

- `.planning/phases/46-domain-cleanup-and-final-quality-gate/46-SPEC.md` — locked requirements, boundaries, constraints, and acceptance criteria for this phase.
- `.planning/codebase/CONCERNS.md` — the file QUAL-03 annotates inline.
- `.planning/codebase/CONVENTIONS.md` — project-wide `Repo.transact/1` convention that DOM-02 documents the divergence from.
- `.planning/codebase/ARCHITECTURE.md` — domain boundary map for `Foglet.Boards.*`.
- `lib/foglet_bbs/boards/supervisor.ex` (DOM-01 target).
- `lib/foglet_bbs/boards/server.ex` (DOM-02 target — moduledoc + `:154`/`:196`).
- `lib/foglet_bbs/boards.ex` (`boot_board_servers/0` real implementation; DOM-01 must not break this caller).
- `lib/foglet_bbs/application.ex` (`FogletBbs.Application.start/2` — boot caller).
- `.dialyzer_ignore.exs` (QUAL-01 target).
- `mix.exs` (precommit alias definition — Sobelow + Dialyzer wiring).
- `.planning/phases/41-tui-contract-and-modal-effects/41-SUMMARY.md` through `45-ssh-and-session-runtime-hardening/45-SUMMARY.md` — disposition cross-reference for QUAL-03.
- `AGENTS.md` — domain boundary rules and `rtk` shell wrapper requirement.
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- `Foglet.Boards.Server` `@moduledoc` already uses `##` subheaders for design
  rationale (`## Message number allocation`, `## Crash recovery (D-05)`). The
  DOM-02 explanation slots in as a third subheader.
- `.dialyzer_ignore.exs` already supports per-entry comments and string-pattern
  match form (used by the two `account/*_form.ex :no_match` entries). The
  bucketed-comment-block pattern is already established.
- `.planning/codebase/CONCERNS.md` uses consistent `## Section` / `### Item`
  headings across all five sections — a single regex (`^### `) reliably
  enumerates targets for the QUAL-03 walk.
- Phase 41–45 SUMMARY.md files exist and provide the disposition pointers
  QUAL-03 needs (e.g., Phase 45 SUMMARY for `PubkeyStash`).

### Established Patterns

- Project convention: domain contexts use `Repo.transact/1` (Foglet.Accounts,
  Foglet.Posts, Foglet.Threads, Foglet.Oneliners, Foglet.Boards). DOM-02 is
  the explicit, intentional exception — and that exception is what is being
  documented, not removed.
- Boot pattern: `FogletBbs.Application.start/2` calls
  `Foglet.Boards.boot_board_servers/0` at the application boundary; the
  per-board GenServer registers via `Foglet.BoardRegistry`. The
  `Foglet.Boards.Supervisor.boot_board_servers/0` stub is a leftover and
  has zero callers.
- TUI screen `@spec` shape: `init(Context.t()) :: map()`,
  `update(term(), map(), Context.t()) :: {map(), [Effect.t()]}`,
  `render(map(), Context.t()) :: any()`. The `map()` return is usually
  narrowable to a state-module `t/0`; `any()` from `render` typically is not.
- Widget `@spec` shape: `init/1`, `handle_event/2`, `render/2`, with
  Raxol-opaque return types in `render`. Same narrowing rule applies.

### Integration Points

- DOM-01 boundary: `FogletBbs.Application.start/2` boot ordering. The phase
  must verify the application supervision tree still boots after the stub
  is removed.
- DOM-02 boundary: the `handle_call` clauses at `server.ex:86-93,102-108`
  pattern-match on `{:ok, %{post: post}}` and
  `{:ok, %{thread: thread, post: post, thread_update: updated_thread}}`
  for success-side extraction. These pattern matches are the load-bearing
  reason Multi step names cannot change.
- QUAL-01 boundary: the precommit alias in `mix.exs` runs Dialyzer with the
  ignore file. Every batch must pass `rtk mix dialyzer` before commit.
- QUAL-03 boundary: `.planning/codebase/CONCERNS.md` is the single source
  of truth for the milestone-close gate. Other planning artifacts read it
  but do not write back.
</code_context>

<specifics>
## Specific Ideas

- DOM-02 moduledoc paragraph should explicitly mention the words "intentional"
  and "locked deviation from `Repo.transact/1`" so a future grep
  (`grep -rn "Repo.transact" lib/`) plus a quick read makes the rationale
  obvious.
- The `## Transaction strategy` subheader keeps the moduledoc structure
  parallel to `## Message number allocation` and `## Crash recovery`.
- For QUAL-01, prefer narrowing screen `init/1` to a concrete state struct
  even when the screen does not currently expose a `t/0` — adding a typed
  `@type t :: %__MODULE__{…}` (or pulling from the sibling `state.ex`) is
  cheap and shrinks the ignore file in a single move.
- For QUAL-03, deferred perf items must include a backlog pointer — the
  milestone-close gate needs to be able to refuse to pass on items that are
  retained without an exit plan.
</specifics>

<deferred>
## Deferred Ideas

- `mix foglet.audit.concerns` checker / disposition lint task — out of scope
  per SPEC §Out of scope. Manual annotation pass + `rtk mix precommit` is
  the v2.1 gate.
- Restructuring `Foglet.Boards.Server` reply paths to enable
  `Repo.transact/1` — out of scope per SPEC §Out of scope. The GenServer
  surface is locked; DOM-02 documents and keeps Multi.
- Implementing `Foglet.Posts.list_posts/1` cursor pagination and
  `PostReader render_cache` width-LRU — `Intentionally retained` in
  `CONCERNS.md` with a backlog pointer per D-11.
- Net-new test coverage for "Under-tested Zones" — those entries are
  classified `Intentionally retained` or `Covered` based on the QUAL-03
  audit walk; new test work is a future milestone.
- Updates to v2.0 / earlier phase artifacts — out of scope per SPEC; phase
  artifacts are point-in-time records.

### Reviewed Todos (not folded)

None — no todos matched phase 46.
</deferred>
