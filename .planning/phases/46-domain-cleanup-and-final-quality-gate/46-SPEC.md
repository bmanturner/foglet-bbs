# Phase 46: Domain Cleanup And Final Quality Gate — Specification

**Created:** 2026-04-29
**Ambiguity score:** 0.11 (gate: ≤ 0.20)
**Requirements:** 4 locked

## Goal

Maintainers can close v2.1 with the remaining tech-debt audit items resolved: the misleading `Foglet.Boards.Supervisor.boot_board_servers/0` stub is gone, `Foglet.Boards.Server`'s direct `Repo.transaction/1` use is documented as intentional, the `.dialyzer_ignore.exs` baseline is reduced to its irreducible-noise core with inline rationale, and `.planning/codebase/CONCERNS.md` carries an inline `Disposition:` line on every concern entry that maps it to fixed / intentionally retained / covered.

## Background

v2.1 was scoped to address every item in `.planning/codebase/CONCERNS.md` through implementation, documentation as intentional retention, or explicit verification coverage. Phases 41–45 implemented the bulk of the changes (TUI contract cleanup, App decomposition, large-screen split, PostReader/content-query hardening, SSH/session runtime hardening including the previously-flagged `PubkeyStash` TTL/sweep at `lib/foglet_bbs/ssh/pubkey_stash.ex:21,109`). What remains:

- **DOM-01.** `lib/foglet_bbs/boards/supervisor.ex:41-46` defines a no-op `boot_board_servers/0` stub whose moduledoc still says "Plan 03 implements the real query." The real implementation lives at `lib/foglet_bbs/boards.ex:39-46` and is what `FogletBbs.Application.start/2` actually calls. The stub is misleading and unused.
- **DOM-02.** `Foglet.Boards.Server` (`lib/foglet_bbs/boards/server.ex:154,196`) uses `|> Repo.transaction()` directly with `Ecto.Multi`, while every other context (`Foglet.Accounts`, `Foglet.Posts`, `Foglet.Threads`, `Foglet.Oneliners`, `Foglet.Boards`) uses `Repo.transact/1`. The handle_call clauses at `server.ex:86-93,102-108` rely on Multi's named step labels (`:post`, `:thread_update`) for success-side extraction — Multi step naming is load-bearing, the error 4-tuple is not. The divergence is intentional but undocumented.
- **QUAL-01.** `.dialyzer_ignore.exs` carries 28 entries: 5 `:unknown_type` (Ecto schema `t/0` false positives), 1 `:call_without_opaque` on `boards/server.ex` (the audit-flagged real hint), 20 `:contract_supertype` (specs broader than success-typing on screen and widget modules), and 2 `:no_match` patterns on `account/prefs_form.ex` and `account/profile_form.ex` (intentional defensive fallbacks). The file's header comment commits to "fail precommit on NEW warnings while letting the existing noise coexist," but no entry carries a per-line rationale and the audit-called real hint is unfixed.
- **QUAL-03.** `.planning/codebase/CONCERNS.md` (Tech Debt, Known Bugs, Security, Performance Bottlenecks, Under-tested Zones) has no per-item disposition. Some items (e.g., SSH `PubkeyStash` TTL) are already fixed but `CONCERNS.md` still describes them as open. Without a disposition register the milestone-close gate has no objective signal.

## Requirements

1. **DOM-01 — Remove misleading boot stub.** The no-op `boot_board_servers/0` in `Foglet.Boards.Supervisor` is deleted; the real implementation at `Foglet.Boards.boot_board_servers/0` remains the single boot source of truth.
   - Current: `lib/foglet_bbs/boards/supervisor.ex:41-46` defines a stub that returns `:ok` and is never called by `FogletBbs.Application.start/2`.
   - Target: The function (and its leading `@doc`) is removed from `Foglet.Boards.Supervisor`. `FogletBbs.Application.start/2` continues to call `Foglet.Boards.boot_board_servers/0`. No supervisor-module call site is broken.
   - Acceptance: `grep -n "def boot_board_servers" lib/foglet_bbs/boards/supervisor.ex` returns no matches. `rtk mix precommit` and `rtk mix test` are green. A test (existing or added) that exercises application startup still passes.

2. **DOM-02 — Document the Multi-vs-transact divergence.** `Foglet.Boards.Server`'s direct `Repo.transaction/1 + Multi` usage is kept and explained inline so future maintainers understand the choice.
   - Current: `lib/foglet_bbs/boards/server.ex:154,196` ends both `run_post_insert_multi/5` and `run_thread_create_multi/4` with `|> Repo.transaction()`. No comment or moduledoc explains why this diverges from the project-wide `Repo.transact/1` convention.
   - Target: A moduledoc paragraph (and/or function-level comment near `:154` and `:196`) explains that the `handle_call` clauses at `server.ex:86-93,102-108` extract results by Multi step name (`:post`, `:thread_update`), and that converting to `Repo.transact/1` would require manually building the result map at every call site without changing observed behavior. The note explicitly states this is an intentional, locked deviation from the `Repo.transact/1` convention used elsewhere.
   - Acceptance: A reviewer reading `lib/foglet_bbs/boards/server.ex` from top to bottom encounters an explicit rationale for the Multi usage before reaching `Repo.transaction()`. `rtk mix precommit` is green.

3. **QUAL-01 — Aggressive Dialyzer baseline reduction.** Every entry in `.dialyzer_ignore.exs` is either fixed (warning no longer emitted) or carries an inline rationale that explicitly reclassifies it as irreducible noise.
   - Current: 28 ignore entries with no per-entry rationale; the audit-called `boards/server.ex :call_without_opaque` real hint is unfixed.
   - Target:
     - The `boards/server.ex :call_without_opaque` entry is fixed (spec narrowed or call-site tightened) and removed from the ignore file.
     - Every `:contract_supertype` entry where the spec can be narrowed to match success-typing is fixed and removed; entries that resist narrowing remain only with a per-entry comment naming the resisting reason (e.g., "Raxol element() opaque" / "Ecto Changeset.t/0 supertype").
     - All `:unknown_type` entries (Ecto schema `t/0`) carry a single shared comment block stating they are Ecto-schema false positives.
     - The two `:no_match` patterns on `account/prefs_form.ex` and `account/profile_form.ex` carry comments explaining the defensive intent.
     - The header comment is updated to reflect the post-cleanup invariant: every kept entry has a stated reason.
   - Acceptance: `rtk mix dialyzer` is green. `wc -l .dialyzer_ignore.exs` is strictly smaller than before this phase. Every remaining ignore-list entry has a comment within 5 lines above it (or shares a comment block) explaining why it is kept. `boards/server.ex :call_without_opaque` is no longer present.

4. **QUAL-03 — Inline disposition register on CONCERNS.md.** Every concern entry in `.planning/codebase/CONCERNS.md` has a `**Disposition:**` line classifying it as `Fixed`, `Intentionally retained`, or `Covered`, with a brief pointer to the evidence.
   - Current: `.planning/codebase/CONCERNS.md` describes concerns as of v2.0 close (2026-04-29) with no per-item status. Items that have since been addressed (e.g., SSH `PubkeyStash` TTL/sweep) still read as open.
   - Target: Every `### …` heading inside Tech Debt, Known Bugs, Security Considerations, Performance Bottlenecks, and Under-tested Zones gets a `**Disposition:**` line with one of three values:
     - `Fixed in Phase NN` — names the phase and a one-line summary or file pointer.
     - `Intentionally retained` — names the rationale and, if relevant, a backlog pointer.
     - `Covered by …` — names the test, doc, or verification artifact that establishes coverage.
     The file's intro paragraph is updated to note the v2.1 close pass and that every section now carries a disposition. Items the audit pass identifies as still actively open MUST be flagged explicitly so the milestone gate can refuse to pass.
   - Acceptance: For every line in `CONCERNS.md` matching `^### `, a `**Disposition:**` line exists within the same section before the next `### ` or `## ` heading. No section is left unannotated. The intro paragraph references the v2.1 close pass.

## Boundaries

**In scope:**
- Deletion of `Foglet.Boards.Supervisor.boot_board_servers/0` and any stub-only doc reference.
- Inline documentation in `Foglet.Boards.Server` explaining the Multi-vs-`Repo.transact/1` choice.
- Aggressive narrowing of `.dialyzer_ignore.exs`: fix `:call_without_opaque`, narrow `:contract_supertype` specs where possible, annotate everything that remains.
- Inline `**Disposition:**` annotations on every entry in `.planning/codebase/CONCERNS.md`.
- A 46-SUMMARY.md (produced by execute-phase) that links to the disposition pass and confirms `rtk mix precommit` clean.

**Out of scope:**
- **Implementing deferred performance bottlenecks** — `Foglet.Posts.list_posts/1` cursor pagination and `PostReader` `render_cache` width-LRU. Reason: deferred at v2.1 kickoff; will be classified `Intentionally retained` with a backlog pointer in QUAL-03.
- **Additional security hardening beyond what is already shipped** — guest→user audit-row logging, etc. Reason: SSH TTL/sweep already shipped in Phase 45; remaining recommendations are advisory and out of v2.1 scope.
- **Adding test coverage to "Under-tested Zones"** beyond what is already in place. Reason: those items will be classified `Intentionally retained` or `Covered` based on the audit walk; net-new test work is a future milestone.
- **Tooling / mix tasks for audit enforcement** (e.g., a `mix foglet.audit.concerns` checker). Reason: the manual annotation pass + `rtk mix precommit` is the v2.1 gate; tooling is over-engineering for a one-shot close.
- **Restructuring `Foglet.Boards.Server` GenServer reply paths** (would be required to convert to `Repo.transact/1`). Reason: DOM-02 was decided as "document and keep Multi"; the GenServer surface is locked.
- **Updates to v2.0/earlier phase documents.** Reason: phase artifacts are point-in-time records.

## Constraints

- `rtk mix precommit` (compile-with-warnings-as-errors, formatter, Credo, Sobelow, Dialyzer) MUST pass after every committed change in this phase.
- `rtk mix test` MUST remain green; the v2.0 baseline (1 property + 2161 tests, 0 failures) cannot regress.
- `Foglet.Boards.Server`'s observable behavior (success-side `{:ok, post}` / `{:ok, %{thread: …, post: …}}` and error-side `{:error, reason}`) MUST be unchanged.
- The `.dialyzer_ignore.exs` line count after this phase MUST be strictly smaller than before. (Number-of-entries reduction is the falsifiable signal; exact target depends on how many `:contract_supertype` specs resist narrowing.)
- `.planning/codebase/CONCERNS.md` content order and section structure MUST be preserved; only `**Disposition:**` annotations and the intro-paragraph note are additions. No deletion of original concern text.

## Acceptance Criteria

- [ ] `grep -rn "def boot_board_servers" lib/foglet_bbs/boards/supervisor.ex` returns no matches.
- [ ] `lib/foglet_bbs/boards/server.ex` contains a moduledoc or inline comment explaining why `Repo.transaction/1` + `Ecto.Multi` is used instead of `Repo.transact/1`, with reference to the Multi step names that the `handle_call` clauses depend on.
- [ ] `.dialyzer_ignore.exs` no longer contains `{"lib/foglet_bbs/boards/server.ex", :call_without_opaque}`.
- [ ] `.dialyzer_ignore.exs` total entry count is strictly smaller than 28.
- [ ] Every remaining entry in `.dialyzer_ignore.exs` has either an inline comment or shared comment-block above it explaining why the warning is kept.
- [ ] Every `### ` heading inside `.planning/codebase/CONCERNS.md` is followed (within its own section) by a `**Disposition:**` line valued `Fixed in Phase NN`, `Intentionally retained`, or `Covered by …`.
- [ ] `.planning/codebase/CONCERNS.md` intro paragraph references the v2.1 close pass and asserts every section now carries a disposition.
- [ ] `rtk mix precommit` exits 0.
- [ ] `rtk mix test` exits 0 with zero failures and the v2.0 baseline test count or higher.

## Ambiguity Report

| Dimension          | Score | Min  | Status | Notes                                                                 |
|--------------------|-------|------|--------|-----------------------------------------------------------------------|
| Goal Clarity       | 0.92  | 0.75 | ✓      | Each requirement has a concrete file/symbol target.                  |
| Boundary Clarity   | 0.90  | 0.70 | ✓      | Tech-Debt-only confirmed; deferred items explicitly listed.          |
| Constraint Clarity | 0.85  | 0.65 | ✓      | Precommit + test green; behavior parity for Boards.Server.            |
| Acceptance Criteria| 0.88  | 0.70 | ✓      | 9 pass/fail criteria with grep/exit-code checks.                      |
| **Ambiguity**      | 0.11  | ≤0.20| ✓      |                                                                       |

## Interview Log

| Round | Perspective              | Question summary                                              | Decision locked                                                                                       |
|-------|--------------------------|---------------------------------------------------------------|-------------------------------------------------------------------------------------------------------|
| 1     | Researcher + Boundary    | DOM-02 resolution: convert to `Repo.transact/1` or document?  | Document and keep Multi; rationale = handle_call clauses depend on Multi step names for success path. |
| 1     | Boundary Keeper          | QUAL-03 artifact location?                                    | Inline `**Disposition:**` annotations directly inside `.planning/codebase/CONCERNS.md`.               |
| 1     | Boundary Keeper          | CONCERNS.md scope of active fixes?                            | Tech Debt only (DOM-01, DOM-02, QUAL-01). Security / Perf / Under-tested classified, not implemented. |
| 1     | Researcher (clarifier)   | Was SSH `PubkeyStash` TTL addressed in v2.1?                  | Yes — Phase 45 shipped `pubkey_stash.ex:109` `sweep/2` + TTL constants. CONCERNS.md is stale.        |
| 2     | Boundary Keeper          | QUAL-01 dialyzer scope: fix what?                             | Aggressive reduction — fix `:call_without_opaque`; narrow `:contract_supertype` where possible; annotate the rest. |
| 2     | Boundary Keeper          | Milestone close gate definition?                              | `rtk mix precommit` clean + every CONCERNS.md section annotated with Disposition.                     |

---

*Phase: 46-domain-cleanup-and-final-quality-gate*
*Spec created: 2026-04-29*
*Next step: /gsd-discuss-phase 46 — implementation decisions (which `:contract_supertype` specs to narrow, doc-comment placement in `boards/server.ex`, CONCERNS.md walk order)*
