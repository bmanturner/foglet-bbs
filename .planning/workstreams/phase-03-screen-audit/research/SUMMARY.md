# Research Summary — phase-03-screen-audit

**Workstream:** `phase-03-screen-audit` (v1.0.2)
**Scope:** Retrospective audit of 9 TUI screens (login, register, verify, main_menu, board_list, thread_list, post_reader, post_composer, new_thread)
**Researched:** 2026-04-21
**Confidence:** HIGH — all four researchers grounded findings in `file:line` anchors from a first-hand read of the 9 screens, the widget library, and the `phase-03-polish` decision log.

---

## Headline finding

This is a **restraint workstream**, not an ambition workstream. The widget library, theme, and chrome shipped by `phase-03-polish` have already been adopted almost everywhere they should be. The remaining delta is small and tightly constrained: **one candidate styling win (Login → `Input.TextInput`, gated on a UX-parity test), four cross-cutting DRY extractions (theme, terminal-size default, verify-state default, domain-module resolution), and a handful of correctness niggles** (one unguarded `function_exported?/3`, five screens that call `Config.get/get!` on the render path, and four suspected-dead public domain hooks).

Everything else the audit produces should be **deletions, not additions** — every screen must leave equal or lower line count and equal or lower visible row count, because Milestones 4/5/6/9 are about to claim the whitespace that exists today. The audit's dominant risk is not sloppy execution; it is diligent over-execution (Pitfalls 1, 10, 11, 13, 14).

## Stack additions

**None.** Per STACK.md (HIGH confidence): `mix precommit` (`compile --warnings-as-errors` + `format` + `credo --strict` + `sobelow` + `dialyzer`) plus the catalog smoke test and D-18 per-widget theme-hygiene tests already cover every correctness and styling invariant this audit enforces. Recode / Boundary / snapshot-testing libraries / custom Credo checks were all evaluated and rejected with specific rationale. `mix.exs` requires no changes.

---

## Audit rubric — Per-Phase Definition of Done

Every one of the 9 per-screen phases must satisfy this single checklist before `/gsd-verify-work`. Items are grep-gates and behavioral assertions, not "feels clean." Consolidates FEATURES §A/§B table-stakes + ARCHITECTURE §7 + PITFALLS §"Looks Done But Isn't."

### Grep gates (must return zero on the screen file)

1. `rg ':red|:green|:cyan|:yellow|:blue|:magenta|:white|:black' …/<screen>.ex` — no named color atoms (D-07/D-09).
2. `rg '"#[0-9a-fA-F]{6}"' …/<screen>.ex` — no hex literals.
3. `rg '\\e\[|\\x1b' …/<screen>.ex` — no raw ANSI.
4. `rg '%\{.*theme.*\|' …/<screen>.ex` — no theme-struct mutation (Pitfall 2).
5. `rg 'box style.*border' …/<screen>.ex` — no nested-border inside ScreenFrame (Pitfall 5).
6. `rg 'IO\.(write|puts|inspect)' …/<screen>.ex` — no direct terminal writes.
7. `rg '\{80, 24\}' …/<screen>.ex` — no inlined terminal-size defaults (resolved by `@default_terminal_size` per screen).
8. `rg '\(Map\.get\(state, :session_context\) \|\| %\{\}\) \|> Map\.get\(:theme\)' …/<screen>.ex` — no inlined theme extraction.
9. `rg 'get_in\(ctx, \[:domain' …/<screen>.ex` — no inlined domain-module lookup.

### Behavioral assertions

10. `handle_key/2` clause source order preserved (Pitfall 6). `post_composer` and `new_thread`: preserve or add the load-bearing `# NOTE: source order` comment.
11. `render/1` is pure read — no `put_in`, no `%{state | …}`, no `Map.put(state.screen_state, …)` under any `defp render_*` (Pitfall 7; `post_reader.ex:77-82` precedent).
12. `handle_key/2` never inspects `state.modal` — modals dispatch through `App.global_key_handler/2` (Pitfall 9). Any `%{state | modal: modal}` write paired with a `screen_state: %{}` reset keeps the reset.
13. Every widget invocation passes `theme: theme` as an explicit keyword arg (Pitfall 3). D-14 widget state is hoisted to `state.screen_state[:<screen>]` (Pitfall 4); D-16 widgets never appear in `screen_state`.
14. `ScreenFrame.render/4` wraps the screen; `StatusBar` and `KeyBar` are reached only through it (B-TS-01, B-TS-02). Modals use the `%{type:, message:}` shape (B-TS-03).
15. **Line-count delta ≤ 0** AND **visible row count delta ≤ 0** (audit does not grow screens).

### Scope fence

16. Phase diff touches exactly ONE screen file (+ its test file). If the diff also touches `app.ex`, `size_gate.ex`, `chrome/*.ex`, `theme.ex`, or another screen, the phase has drifted and must split (Pitfall 1). Phase 0 is the only exception.
17. No new shared modules under `lib/foglet_bbs/tui/screens/` or `lib/foglet_bbs/tui/` beyond the two Phase-0 extractions (Pitfall 13).

### CI

18. `mix precommit` green end-to-end — not just `mix test test/foglet_bbs/tui/screens/<screen>_test.exs` (Pitfall 15).
19. No new `@dialyzer` / `# credo:disable` suppressions (A-ANTI-05). Exception: `register.ex`'s existing `apply/3` suppression for the not-yet-defined `consume_invite_code` is preserved verbatim.

---

## Recommended phase ordering

**Reconciliation:** FEATURES hinted smallest-to-largest; ARCHITECTURE proposed Phase-0 prelude → Login precedent → parallelizable tail; PITFALLS said either order is defensible.

**Decision: adopt ARCHITECTURE's ordering, with one explicit flag for the roadmapper on Phase 0.**

### Phase 0 — Cross-cutting extractions (prelude)

Two tiny helpers, one commit per helper, one test each. Only shared-module changes the audit is permitted.

- `Foglet.TUI.Theme.from_state/1` — replaces the 9 inlined theme chains. Touches 9 screens + `screen_frame.ex` + `size_gate.ex` + `app.ex` modal overlay.
- `Foglet.TUI.Screens.Domain.get/2` — replaces 7 inlined `get_in(ctx, [:domain, :<key>])` patterns across `board_list.ex`, `thread_list.ex`, `post_reader.ex` (×3 sites), `post_composer.ex`, `new_thread.ex`. Keys: `:boards | :threads | :posts | :markdown`.

**Flag for roadmapper:** spawn Phase 0 as its own phase OR fold into the top half of Phase 1. Either is defensible. **Recommendation: spawn as its own phase** so subsequent phases are pure per-screen diffs that consume the helpers — maximizes the single-file scope-fence. The user's "9 phases, restart numbering at 1" may imply fold-into-Phase-1; requires user confirmation.

### Phases 1-9 (per screen)

| # | Screen | Rationale | Parallel-safe? |
|---|---|---|---|
| 1 | `Login` | Signature-win candidate (`Input.TextInput` adoption). Sets TextInput integration pattern for 2, 7. | No — precedent-setter |
| 2 | `Register` | Applies Phase-1 TextInput pattern to wizard steps | Yes, with Phase 3 |
| 3 | `Verify` | Explicitly does NOT adopt TextInput (07 D-02); documents exception in moduledoc | Yes, with Phase 2 |
| 4 | `MainMenu` | 58 LoC, theme-swap + sparseness discipline test | Yes, with 5, 6 |
| 5 | `BoardList` | Helper swaps + dead-code audit of `load_boards/1` | Yes, with 4, 6 |
| 6 | `ThreadList` | Helper swaps + fix `function_exported?/3` at :136,:140 + verify `:created_by` preload | Yes, with 4, 5 |
| 7 | `NewThread` | Helper swaps + cleanest composer shape; preserve source-order comment at :307-314 | Yes, with Phase 8 |
| 8 | `PostComposer` | Helper swaps + add missing source-order comment above :82-110 | Yes, with Phase 7 |
| 9 | `PostReader` | Largest (425 LoC), most intertwined; leave for last | Must be last |

**Critical path under parallelism:** `0 → 1 → (2+3) → (4+5+6) → (7+8) → 9` = 6 serial blocks instead of 10.

---

## Cross-cutting helpers — land or defer?

FEATURES flagged four exits (X-01..X-04); ARCHITECTURE proposed two concrete extractions; PITFALLS §A-ANTI-03 said "don't refactor non-screen files." **Decision: land TWO helpers, defer the other two.**

| Helper | Files affected | Decision | Where |
|---|---|---|---|
| `Theme.from_state/1` (9 inlined chains) | 9 screens + chrome + size_gate + app modal | **LAND** in Phase 0 | `lib/foglet_bbs/tui/theme.ex` |
| `Screens.Domain.get/2` (7 inlined chains) | 5 screens | **LAND** in Phase 0 | New `lib/foglet_bbs/tui/screens/domain.ex` |
| `{80, 24}` default (13+ inline occurrences) | 6 screens | **DEFER shared extraction; use per-screen `@default_terminal_size`** | Module attribute on each screen |
| `default_verify_state/0` (7 copies in verify.ex) | `verify.ex` only | **LAND, file-scoped** in Phase 3 | Private helper in `verify.ex` |

**Rationale for restraint on the `{80, 24}` case:** 13 occurrences of a single constant value across 6 files is not a good shared module yet — a per-file `@default_terminal_size` attribute is the right granularity. Bumping for testing stays a one-line change; no coupling benefit. Pitfall 13 anti-hoist applies.

Grep gates #7 and #9 in the rubric reach zero after Phase 0 + Phase 3.

---

## Correctness findings surfaced by audit — NOT polish

Three correctness concerns. Each belongs to its phase by file, but the **roadmapper must flag them as correctness work** so they don't get collapsed into decorative rewrites or deferred.

### C-1: `function_exported?/3` without `Code.ensure_loaded/1`

- **Where:** `thread_list.ex:136, 140` — `function_exported?(threads_mod, :list_threads, 2)` / `(…, 1)`.
- **Why it matters:** Without `Code.ensure_loaded/1` first, returns `false` for unloaded modules — silently picks `annotate_fallback/1` even when the 2-arity version exists. Tests not exercising the 2-arity path won't catch it.
- **Contrast:** `post_reader.ex:292` does this correctly. `register.ex:196` uses a compile-time-linked module so likely fine; verify.
- **Owner:** Phase 6 (ThreadList).

### C-2: `Config.get/get!` called in the render path on 5 screens

- **Where:** `login.ex:140-147` (`registration_mode/1`), `register.ex` (same pattern), `post_composer.ex:341-351` (`safe_config_get/2`), `new_thread.ex:119, 427-434` (`max_thread_title_length/0`). (`verify.ex` calls on resend only — not render path; exempt.)
- **Why it matters:** 5 screens × 1-2 calls/render × ~30 renders/session ≈ 200 DB hits/session unless `Foglet.Config` caches.
- **Action:** **Before requirements lock**, verify whether `Foglet.Config` caches (inspect source; look for `:persistent_term` / ETS). If yes — document in each phase's CONTEXT. If no — this is a pre-audit gap closure that must land before Phases 1, 2, 7, 8.
- **Owner:** Phases 1, 2, 3, 7, 8.

### C-3: Dead or suspected-dead public domain hooks

- **Where:** `ThreadList.load_threads/2` (:128-147), `BoardList.load_boards/1` (:86-91), `PostReader.load_posts/2` (:158-181), `PostReader.flush_read_pointers/2` (:197-209).
- **Why it matters:** `app.ex:369-422, 430-468` implements its own task closures and does NOT call these screen hooks. Either tests use them (legitimate test surface — add `@doc false` + comment) or they're dead (delete).
- **Action:** `rg -w <function_name>` across `test/` and `lib/` for each. Result determines `@doc false` vs delete.
- **Owner:** Phases 5, 6, 9.

---

## Inherited decisions — keep hand-rolled

**Precedent citations so each phase doesn't re-litigate.** Locked by `phase-03-polish` or by PITFALLS §11 widget-adoption gate.

| Hand-rolled site | Location | Why kept | Precedent |
|---|---|---|---|
| 6-char `[ABC___]` verify buffer | `verify.ex:55, 138-147` | TextInput can't mask/render without custom renderer; nested border (Pitfall 5) | 07 D-02 |
| Handle + password `█` cursor + `*` mask | `login.ex:196-226` | **Signature-win candidate — see below; gated on UX-parity fixture** | — |
| Single-line wizard `█` cursor | `register.ex:43-48` | Contingent on Phase 1 swap decision | 07 D-02 precedent |
| Title input `█` cursor | `new_thread.ex:124-128` | Contingent on Phase 1 swap decision | 07 D-02 |
| `[L]/[R]/[Q]` letter-shortcut menus | `login.ex:169-178`, `main_menu.ex:20-26` | SelectionList is wrong (no j/k/selected state); Button is click-affordance; plain `text/2` is the idiom | ARCHITECTURE §4.2 |
| `StatusBar` + `KeyBar` + `ScreenFrame` chrome | all 9 screens | Chrome is Phase-01 locked | 01-CONTEXT |
| `PostCard` + `MarkdownBody` + `Viewport` pipeline | `post_reader.ex` | Viewport is already the Phase-7 swap | 07 D-12/D-13 |
| `MultiLineInput` in composer body | `post_composer.ex`, `new_thread.ex` | Phase-5 D-14 canonical; re-entry guards load-bearing (Pitfall 7) | 05 D-13 |
| `@menu_keys` + `@menu_items` 2-duplication | `main_menu.ex:9-13, 28-32` | Load-bearing — render and KeyBar have different format needs | PITFALLS main_menu landmine |
| Two-pass thread sort (sticky + recency, nil-last tuple trick) | `thread_list.ex:159-179` | Naive `desc` + nil would crash/misorder | PITFALLS thread_list landmine |
| `apply(Foglet.Accounts, :consume_invite_code, …)` + `function_exported?` guard | `register.ex:195-209` | Consumer module may not exist yet; direct call emits warning | Existing `credo:disable` is the contract |
| `Enum.map_join(", ")` for changeset errors | `register.ex:282-284` + others | Per-site clearer than an error module at 9-screen scale | A-ANTI-08 |
| `domain_module/2` adapters per consuming screen | All screens using domain modules | Test-injection seam (`session_context.domain[:x]` override) | ARCHITECTURE §5.4 |
| `@log_verify_codes` compile-env guard + paired stub/real | `login.ex:30, 339-346`, `register.ex:25, 286-293` | Compile-env branching IS the feature | Defer per A-ANTI-08 |
| j/k/↑/↓ nav duplicated 3× | `board_list.ex:51-54`, `thread_list.ex:77-80`, `new_thread.ex:201-204` | 3 copies of 4 lines is below the hoist bar | Pitfall 13 |

---

## Protected layout map — per-screen reserved regions and anti-affordances

Merged ARCHITECTURE §10 (R1-R7) + PITFALLS §10 anti-affordances. Cite directly in the requirements doc and each phase's CONTEXT.

### Reserved regions

| Screen | Region | Location | Reserved for (milestone) |
|---|---|---|---|
| `main_menu` | R1 — below welcome through KeyBar | :20-26 + below | M4 last-callers + news banner, M6 notification badge, M9 oneliners |
| `board_list` | R2 — left/right row gutters | :42-46 | M4 presence-count, M6 mention/DM badges |
| `thread_list` | R3 — row middle (title ↔ metadata) | :54-68 | M5 chat-room indicator, M6 mention highlight, M7 mod tags |
| `post_reader` | R4 — header strip | :69-72 | Nothing — already at max density |
| `post_reader` | R5 — footer (body ↔ KeyBar) | :84-86 | M6 reply-tree + mention highlights, M9 upvote counter |
| `post_composer` | R6 — below char counter | :64-67 | M6 @handle autocomplete hint |
| `new_thread` | R6 — below char counter | composer pane | M6 @handle autocomplete hint |
| `login` / `register` / `verify` | R7 — below error line | error region + below | Minimal forever — gateways; M10 email may claim space |

### Anti-affordances (auditor MUST NOT add)

1. Decorative `box style: %{border: ...}` inside ScreenFrame (Pitfall 5).
2. `Display.Table` for 2-3 rows — use SelectionList/ListRow (B-ANTI-03).
3. `Input.Tabs` where one logical mode OR a Tab keybind already affords it.
4. `Input.Button` in place of `text/2` without click/focus interactivity.
5. `Input.Checkbox` / `Input.RadioGroup` / `Input.Menu` — no current use cases.
6. `Progress.Spinner` / `Display.Progress` for "visual interest" — spinner must target a real in-progress op.
7. `Display.Tree` for two-level board→thread nav.
8. `SmartList` replacing `SelectionList` at current scale.
9. ASCII banners / decorative dividers / session-info panels / "connected as @handle" lines on `main_menu` — M4 owns banner.
10. Sidebars / two-pane splits — M5 chat owns this idiom.
11. `column style: %{gap: 1}` where `gap: 0` was pre-audit.
12. KeyBar hint text changes "while I'm in here" — breaks muscle memory, UI-SPEC locked.
13. Any `box style: %{border: ...}` inside a screen's content tree — workstream-wide grep must return zero.

### The hard rule

**The audit adds NO new lines of screen content.** Allowed content changes: (a) widget swaps that reduce hand-rolled LoC, (b) normalizing loading/empty-state phrasing (no row-count delta), (c) normalizing theme slot names (no row-count delta). Anything that adds a visible element triggers a roadmap discussion.

---

## Signature win — Login adopts `Input.TextInput`

**Consensus of ARCHITECTURE + FEATURES:** swapping Login's hand-rolled handle + password inputs to `Widgets.Input.TextInput` is the single biggest styling win. Login is 347 lines today; projected post-swap ~150. The swap deletes `format_input_line/3`, `input_fg/2`, `focus_style/1`, `mask_password/1`, `drop_last_grapheme/1`, `append_to_focused/2`, and the whole `handle_form_key/2` family (`login.ex:76-124`).

**Reconciliation with PITFALLS §11:** PITFALLS argues the swap may regress visually — TextInput doesn't reproduce `█` cursor; it wraps in its own `box` that may fight ScreenFrame; state must hoist to `screen_state[:login]`, forcing `:focused_field` dispatch refactor. Legitimate concerns, not a veto.

**How Phase 1 resolves — the 4-question gate (Pitfall 11), applied during planning not coding:**

1. Does `Input.TextInput` accept `%Theme{}` via `theme:`? YES (`text_input.ex:93` `Keyword.fetch!`).
2. Does it reproduce the visible behavior — cursor shape, masking, focus bolding? **Open.** Phase 1's planning must produce a side-by-side render fixture and make the call. Options: extend TextInput with a `█`-block cursor style (widens Phase 1 scope) OR accept a non-block cursor visually.
3. Does it avoid a nested border? **Open** — `text_input.ex:97` wraps in its own `box`. Planning must confirm `padding: 0` + no visible border is sufficient, or set `border: :none` on the widget's inner box.
4. Does the swap reduce LoC? Projected yes (~150 vs 347).

**The signature-win is conditional on planning answering (2) and (3) affirmatively.** If either is "no," Phase 1 **keeps hand-rolled** (as Verify does via 07 D-02) and the workstream's biggest win shrinks to the four helper extractions. Still a meaningful audit, just less visual. Phases 2 and 7 inherit Phase 1's decision.

---

## Open questions for the requirements step

1. **Is Phase 0 a distinct phase or the opening half of Phase 1?** User said "9 phases total, restart numbering at 1" — implies fold. ARCHITECTURE argued for standalone prelude. If "~9 phases, nine per-screen," Phase 0 is separate (10 total). **Recommend: ask the user.**

2. **Does `Foglet.Config` cache its gets?** If yes, the "no `Config.get/get!` in render path" rubric line is aesthetic; if no, it's a correctness fix likely requiring a pre-audit gap closure before Phases 1, 2, 7, 8. A 10-minute source inspection answers this; do it before requirements lock.

3. **Does Phase 1's TextInput swap meet the 4-question gate (§Signature win)?** Cannot be answered until Phase 1 planning produces the side-by-side fixture. Default if unclear: **keep hand-rolled**. Requirements should surface this as a Phase-1 planning decision point, not pre-commit.

4. **Are the 4 suspected-dead public domain hooks (C-3) actually dead?** A single `rg -w` pass answers. Result determines `@doc false` vs delete for Phases 5, 6, 9.

5. **Shared-constant vs per-screen attribute for `{80, 24}`?** This synthesis picked per-screen `@default_terminal_size`. If requirements prefers a shared constant alongside `SizeGate.floor_*`, it's a trivial ~20-line extraction. Confirm the per-screen stance.

6. **How aggressive should loading/empty-state normalization be?** Zero-risk win but touches every list-bearing screen. Recommend yes, in each respective phase, documented in rubric item "normalize loading/empty-state phrasing (no row-count delta)."

---

## Confidence Assessment

| Area | Confidence | Notes |
|---|---|---|
| Stack | HIGH | `mix.exs` + precommit config + phase-03-polish precedent all converge on "add nothing." |
| Audit rubric | HIGH | Every check anchored in file:line references from first-hand reads. |
| Architecture | HIGH | Specific app.ex dispatch lines + per-screen state shape anchors + widget contract line numbers cited throughout. |
| Pitfalls | HIGH | 15 pitfalls + 9 screen-specific landmines with recovery costs and phase-to-pitfall mapping. Load-bearing comments at `post_composer.ex:82-110` and `new_thread.ex:307-314` called out by exact line. |

**Overall: HIGH.** Gaps are the 6 open questions above.
