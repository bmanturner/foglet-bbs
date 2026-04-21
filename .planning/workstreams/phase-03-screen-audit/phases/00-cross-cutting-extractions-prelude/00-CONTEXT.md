# Phase 0: Cross-cutting extractions (prelude) — Context

**Gathered:** 2026-04-21
**Status:** Ready for planning
**Workstream:** phase-03-screen-audit

<domain>
## Phase Boundary

Phase 0 ships two tiny, single-purpose helpers that every subsequent phase in the `phase-03-screen-audit` workstream will consume, and migrates 11 existing call sites to use them:

- `Foglet.TUI.Theme.from_state/1` — replaces the inlined `(Map.get(state, :session_context) || %{}) |> Map.get(:theme) || Theme.default()` chain duplicated across 9 screens, `chrome/screen_frame.ex`, `size_gate.ex`, and `app.ex` modal overlay.
- `Foglet.TUI.Screens.Domain` (new module) with `get/2` — replaces the inlined `get_in(ctx, [:domain, :<key>]) || Foglet.<Default>` pattern in 5 screens (7 call sites total).

**In scope:**
- Create the two helper modules + per-function tests.
- Migrate all 11 call sites to use the helpers.
- Verify grep gates #8 and #9 return zero across `lib/foglet_bbs/tui/screens/*.ex` + chrome + size_gate + app.ex.
- `mix precommit` green end-to-end.

**Out of scope:**
- Any per-screen idiomatic or styling audit (Phases 1–9 own that).
- `@default_terminal_size` module attribute introduction (grep gate #7 is per-screen, not Phase 0).
- Any new shared module beyond these two (`AUDIT-14`).
- Any behavioral change visible end-to-end — SSH session must render identically pre- and post-Phase-0 at default terminal size (roadmap success criterion #5).

**Phase 0 is AUDIT-13 exception (a)** — it touches every screen once for the extractions. Phase 2 (exception b) and Phase 3 (exception c) have their own documented exceptions for wizard-state migration; Phases 1, 4–9 remain strictly one-screen-per-phase.

**Cross-reference to post-Phase-0 amendments:** REQUIREMENTS.md was amended during this discuss-phase (2026-04-21) to add AUDIT-18 (canonical section order), AUDIT-19 (`init_screen_state/1` adoption), REGISTER-06, VERIFY-05, MENU-05, and READER-07. None of these affect Phase 0's scope — Phase 0 ships the two helpers and migrates call sites only. But downstream phases will consume the canonical layout rubric once in force.

</domain>

<decisions>
## Implementation Decisions

### Helper API shapes (locked by REQUIREMENTS.md; not re-litigated)

- **D-01:** `Foglet.TUI.Theme.from_state/1`
  - Accepts the full Raxol state map (the same `state` passed to `render/1` / `handle_key/2`).
  - **Returns `%Foglet.TUI.Theme{}` unconditionally.** On missing `session_context` OR missing `:theme` key, falls back to `Foglet.TUI.Theme.default/0` (which today returns `resolve(:gray)`). This preserves the observable behavior of every current inlined chain exactly.
  - No `{:ok, _} | :error` wrapper — the default fallback was the research recommendation and matches existing call-site semantics.
  - No `from_state!/1` variant — the `default/0` fallback removes the need to raise.

- **D-02:** `Foglet.TUI.Screens.Domain.get/2`
  - New module lives at `lib/foglet_bbs/tui/screens/domain.ex` (module `Foglet.TUI.Screens.Domain`) — not in `app.ex`, not a sibling of `Theme`. Matches research recommendation and the `lib/foglet_bbs/tui/screens/` directory layout.
  - Accepts either the full state or the `session_context` map (take the narrower input — `session_context` — and let callers pass `state.session_context` explicitly; prevents accidental coupling to the whole state shape).
  - **Returns `{:ok, module} | {:error, :not_configured}`** per `REQUIREMENTS.md AUDIT-02`. This is a behavior CHANGE from today's `|| Foglet.Default` pattern — callers migrate to a short pattern-match and the "real default module" becomes an explicit branch at each call site (or a small per-site default helper), rather than a hidden `||` fallback.
  - Supported keys: `:boards | :threads | :posts | :markdown` (locked). Unknown keys return `{:error, :not_configured}` (no raise, no custom error atom).
  - No `Code.ensure_loaded/1` at lookup time — configured modules are trusted. `thread_list.ex`'s `function_exported?/3` + `Code.ensure_loaded/1` pattern is a Phase-6 correctness fix, not a Phase-0 concern.

### Plan granularity (locked by this discussion)

- **D-03:** Phase 0 is split into **three plans**, each an atomic commit with a green `mix precommit`:
  - **00-01-PLAN** — Add `Foglet.TUI.Theme.from_state/1` + its tests (happy path, missing `session_context`, missing `:theme` key). No call-site migration yet; the new function exists alongside the inlined chains.
  - **00-02-PLAN** — Add `Foglet.TUI.Screens.Domain` module + `get/2` + its tests (happy path, missing `session_context`, missing `:domain` key, unknown key returns `{:error, :not_configured}`). No call-site migration yet.
  - **00-03-PLAN** — Migrate all 11 call sites (9 screens + `screen_frame.ex` + `size_gate.ex` + `app.ex` modal overlay). Verify grep gates #8 and #9 return zero. `mix precommit` green.
- **D-04:** Authoring order is **standard** — implementation first, then tests. Matches the prior `phase-03-polish` D-18 test style (tests live in `test/foglet_bbs/tui/...` mirroring the lib path and exercise happy + fallback + theme-hygiene assertions). No TDD red-green-refactor loop required for two-function modules where the shape is already known.

### Migration call-site inventory (locked by research SUMMARY)

- **D-05:** The 11 call sites targeted by 00-03-PLAN are:
  - **Theme extraction (9 sites + 2 non-screen sites = 11 for `from_state/1`):** every screen in `lib/foglet_bbs/tui/screens/*.ex`, `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex`, `lib/foglet_bbs/tui/widgets/chrome/size_gate.ex`, and `lib/foglet_bbs/tui/app.ex` modal overlay. Plus in-screen extra extractions where the pattern repeats inside the same file (`post_reader.ex` line 329).
  - **Domain-module lookup (7 sites for `Screens.Domain.get/2`):** `board_list.ex:113`, `thread_list.ex:132`, `new_thread.ex:412`, `post_reader.ex:161` (and two more in `post_reader.ex`), `post_composer.ex` (per research), plus any other `get_in(ctx, [:domain, …])` the plan-phase researcher surfaces.
  - The plan researcher is expected to **re-verify the inventory** with `rg` during 00-03 planning. Any site the researcher finds that isn't on this list gets added; any site on this list that doesn't exist gets removed.

### Default-module handling at call sites (inherent to D-02)

- **D-06:** Because `get/2` returns `{:ok, module} | {:error, :not_configured}` and existing call sites today use `|| Foglet.<DefaultModule>`, the migration at each site introduces a small pattern-match:
  ```elixir
  # Before
  boards_mod = get_in(ctx, [:domain, :boards]) || Foglet.Boards

  # After (minimal)
  boards_mod =
    case Screens.Domain.get(ctx, :boards) do
      {:ok, mod} -> mod
      {:error, :not_configured} -> Foglet.Boards
    end
  ```
  The plan-phase researcher MAY propose a tiny per-screen helper (e.g. `boards_mod/1`) if the pattern-match is invoked in >1 site within a single screen — but NOT a cross-screen helper (would violate `AUDIT-14`, already one exception granted for `Screens.Domain` itself).

### Regression verification (default — locked by research + user answer)

- **D-07:** Post-migration verification relies on the **per-phase rubric** (`AUDIT-05` grep gates #8/#9) applied at the end of 00-03-PLAN and again at the start of every subsequent phase. No separate compile-time gate, ExUnit grep assertion, or pre-commit hook is added. If a later phase reintroduces an inlined pattern, the per-phase rubric catches it at that phase's verification step.

### Behavioral invariant (locked by roadmap success criterion)

- **D-08:** The Phase 0 prelude is a **zero-user-visible-change** refactor. An SSH session at any terminal size rendering any screen MUST render byte-for-byte identically pre- and post-Phase-0 (modulo test-injection paths that are themselves exercised by the tests). The prelude exists solely so Phases 1–9 can run within a strict single-file scope fence.

### Claude's Discretion

- Exact moduledoc prose for the two new helpers — follow the existing `Foglet.TUI.Theme` moduledoc style (purpose sentence, responsibilities list, slot/key reference, final footer with file references).
- Test file names and locations follow the project convention (`test/foglet_bbs/tui/theme_test.exs` already exists; add `describe "from_state/1"` block there rather than a new file. Create `test/foglet_bbs/tui/screens/domain_test.exs` for the new module).
- Exact `@type` / `@spec` surface on the new module — infer from context (`state :: map()`, key atom literal type, return type `{:ok, module()} | {:error, :not_configured}`).
- Whether to deprecate or document-only the pre-migration inlined pattern during 00-01 and 00-02 (no deprecation shim — just don't advertise a second way to do it).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Workstream planning

- `.planning/workstreams/phase-03-screen-audit/REQUIREMENTS.md` — AUDIT-01..04 define Phase 0 scope; AUDIT-05..20 rubric is checked at Phase 0 completion.
- `.planning/workstreams/phase-03-screen-audit/ROADMAP.md` §Phase 0 — 5 success criteria verbatim.
- `.planning/workstreams/phase-03-screen-audit/research/SUMMARY.md` — Cross-cutting helpers section locks the two helpers; Headline finding frames this as a restraint workstream.
- `.planning/workstreams/phase-03-screen-audit/research/ARCHITECTURE.md` §3, §4, §9 — canonical screen shape, screen-widget boundary, phase ordering.

### Project-level

- `.planning/PROJECT.md` — Core value and reserved-region context (Milestones 4/5/6/9) for the behavioral invariant D-08.
- `CLAUDE.md` — Elixir gotchas (block-expressions rebinding, struct Access, OTP child specs), Mix precommit expectations, Ecto preload guidance.
- `docs/ARCHITECTURE.md` — App / screen / widget / Theme architecture.
- `docs/raxol/README.md` + `docs/raxol/adr/` — Raxol theming contract; `docs/raxol/cookbook/THEMING.md` for theme-slot routing.

### Existing code to read before planning

- `lib/foglet_bbs/tui/theme.ex` — `Theme.default/0` exists at `:228-229` and is the fallback target for `from_state/1`.
- `lib/foglet_bbs/tui/screens/login.ex:36` — canonical inlined theme extraction site.
- `lib/foglet_bbs/tui/screens/board_list.ex:113` — canonical inlined domain-module lookup site.
- `lib/foglet_bbs/tui/screens/post_reader.ex:161, 285, 329` — multi-site screen with three separate inlined chains.
- `lib/foglet_bbs/tui/app.ex` — modal overlay call site for Theme extraction.
- `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex` + `size_gate.ex` — non-screen call sites for Theme extraction.
- `test/foglet_bbs/tui/theme_test.exs` — existing test file to extend with `from_state/1` describe block.

### Decision precedents inherited

- `phase-03-polish` `07-CONTEXT.md` (Raxol migration) D-07/D-09/D-13/D-14/D-16/D-18 — widget theming contract.
- `phase-03-polish` `08-VALIDATION.md` — D-18 test style for theme hygiene and smoke render, applied in 00-01-PLAN and 00-02-PLAN tests.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable assets

- **`Foglet.TUI.Theme.default/0`** (`lib/foglet_bbs/tui/theme.ex:228-229`) — already returns `resolve(:gray)`. `from_state/1` uses this as its fallback; no new fallback function needed.
- **`Foglet.TUI.Theme.resolve/1`** (`:232-233`) — also already public; `from_state/1` does not need to expand beyond `default/0`.
- **Existing test infrastructure** — `test/foglet_bbs/tui/` mirrors `lib/foglet_bbs/tui/`; add helper tests in the same mirror.

### Established patterns

- **Function-form widget + theme routing** (D-13): widgets accept `theme:` as an explicit keyword arg. The two helpers enable *screens* to resolve the theme/module cleanly before passing to widgets — consistent with the existing contract.
- **Moduledoc style in `theme.ex`** — numbered responsibilities list, slot reference, footer with boot/resolve function names. Reuse for both new helpers' moduledocs.
- **ETS-cached `Foglet.Config`** (`lib/foglet_bbs/config.ex`) — not directly related to Phase 0, but the inherited decision that render-path `Config.get` is safe means Phase 0 does not need to optimize any read path.

### Integration points

- **Screen state shape:** every screen exposes `render/1` receiving the full Raxol state. `from_state/1` takes this shape directly; `Screens.Domain.get/2` takes `state.session_context` (narrower — prevents coupling).
- **`App` modal overlay:** `lib/foglet_bbs/tui/app.ex` has its own theme extraction chain at a known line; this is the one non-screen, non-chrome caller of `from_state/1` in Phase 0.
- **`ScreenFrame` + `SizeGate`:** chrome widgets that also extract theme from state. Their migration to `from_state/1` is part of 00-03-PLAN (bundled with the screens; Phase 0's scope-fence exception is what permits it).

</code_context>

<specifics>
## Specific Ideas

- **Three atomic plans, each green on commit.** 00-01 Theme helper + tests; 00-02 Domain module + tests; 00-03 Migration. If any plan fails, the prior is still a reversible landing zone.
- **"Existing default fallback stays at the call site"** (D-06). We do NOT hide `Foglet.Boards`/`Foglet.Threads`/`Foglet.Posts`/`Foglet.Markdown` inside `Screens.Domain.get/2`. The helper is a lookup; the default is caller business. This preserves the test-injection seam (`session_context.domain[:boards]` overrides) while making "not configured" an explicit branch.
- **Zero user-visible change** (D-08). If Phase 0 lands and the user SSHes in and notices anything different, that is a rollback-grade bug.
- **Test mirror convention** — theme tests extend `test/foglet_bbs/tui/theme_test.exs`; domain tests live in a new `test/foglet_bbs/tui/screens/domain_test.exs`.

</specifics>

<deferred>
## Deferred Ideas

- **Compile-time/CI grep gate for inlined patterns** — deferred; per-phase rubric catches regressions at each verification step. Would be worth reopening if Phases 1–9 surface multiple re-introductions of the inlined patterns.
- **Per-screen default-module helper** (e.g. `boards_mod/1` inside `board_list.ex`) — only if the screen uses the module in ≥ 2 call sites. Plan-phase researcher decides case-by-case; not a workstream-wide convention.
- **`{80, 24}` terminal-size extraction** — explicitly OUT of Phase 0 scope (grep gate #7 is resolved per-screen in Phases 5/6/7/8/9 via `@default_terminal_size` attributes).
- **`Foglet.TUI.Constants` shared module** — FUT-01; requires >1 shared constant to justify; not earned yet.
- **`Foglet.TUI.Screens` behaviour** with `init_screen_state/1` / `render/1` / `handle_key/2` callbacks — FUT-02; implicit conformance is clearer at 9 screens.
- **Deprecation shim for the pre-migration inlined pattern** — explicitly NOT added. No second way to do it is advertised; the migration in 00-03 is mechanical and atomic.

</deferred>

---

*Phase: 00-cross-cutting-extractions-prelude*
*Context gathered: 2026-04-21*
