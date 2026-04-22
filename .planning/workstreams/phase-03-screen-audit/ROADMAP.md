# Roadmap: Foglet BBS — Phase-03 Screen Audit (v1.0.2)

## Overview

v1.0.2 is a **restraint workstream** — a retrospective audit of the 9 TUI screens shipped through `phase-03-polish`. Every phase removes, consolidates, or swaps; none adds. The audit's dominant risk is not sloppy execution but **diligent over-execution** — Milestones 4 (Presence), 5 (Chat), 6 (DMs/Notifications), and 9 (Search/Oneliners) are all about to claim the whitespace that exists today, so each phase must leave its screen at **equal or lower line count AND equal or lower visible row count** (`AUDIT-16`, enforced per phase).

**Structure:** 10 phases total. Phase 0 is a cross-cutting prelude that ships two shared helpers (`Foglet.TUI.Theme.from_state/1`, `Foglet.TUI.Screens.Domain.get/2`) every subsequent phase consumes. Phases 1–9 are one-per-screen audits, bound by the scope fence in `AUDIT-13` (phase diff touches exactly ONE screen file + its test). **Documented AUDIT-13 exceptions:** Phase 0 (cross-cutting extraction — touches all 9 screens + chrome + app), Phase 2 (Register wizard-state migration — may touch `app.ex:53-56, 354-361`), Phase 3 (Verify wizard-state migration — may touch `app.ex:74-75`).

**Critical path:** `0 → 1 → 2 → 3 → (4+5+6) → (7+8) → 9` — 7 serial blocks across 10 phases. Phase 1 (Login) must be serial because it sets the `Input.TextInput` adoption precedent that Phases 2 (Register) and 7 (NewThread) inherit. **Phases 2 and 3 are serialized** (previously parallel) because both modify `app.ex` wizard-dispatch paths during the top-level wizard-state migration — concurrent diffs would conflict, and Phase 3 also inherits any wizard-dispatch pattern established in Phase 2. Phase 9 (PostReader) is last because it is the largest screen (425 LoC) and benefits from the audit pattern being fully refined before it lands.

**No stack additions.** `mix precommit` (`compile --warnings-as-errors` + `format` + `credo --strict` + `sobelow` + `dialyzer`) plus the existing catalog smoke test and D-18 per-widget theme-hygiene tests already cover every correctness and styling invariant this audit enforces (STACK.md, HIGH confidence).

## Inherited Decisions

Locked at workstream creation — do not re-litigate per phase:

- **`Foglet.Config` render-path reads are safe.** The module caches via ETS read-through (`lib/foglet_bbs/config.ex`); the `Config.get/get!` call sites on 5 screens (Login, Register, PostComposer, NewThread + Verify resend) are not a pre-audit gap. Document in each phase's CONTEXT; no pre-audit closure.
- **`Input.TextInput` adoption in Login** (and consequently Register and NewThread) is **locked by user** with accepted visual drift from the `█`-block cursor. Phases 2 and 7 inherit Phase 1's integration pattern.
- **`Verify` keeps its hand-rolled 6-char buffer** (07 D-02 inheritance). TextInput cannot mask/render the 6-slot `[ABC___]` layout without a custom renderer and its inner `box` would conflict with the slot visualization.
- **Spinner adoption is evaluated per screen** against the anti-affordance rule (`AUDIT-10`). The spinner goes in ONLY where the op takes >1 render frame AND its completion is observable. No spinner decorates an instant operation.
- **Phrasing normalization is scoped to the audited screen's own file** (`AUDIT-11`) — no cross-screen sweep commit.
- Remaining locked decisions from REQUIREMENTS.md "Locked Decisions" section apply in full.

## Phases

**Phase Numbering:**
- Phase 0 — prelude (cross-cutting extractions, touches all 9 screens once)
- Phases 1–9 — per-screen audits (one screen each, scope fence `AUDIT-13`)
- Decimal phases (e.g., 2.1) — reserved for urgent insertions surfaced mid-workstream

- [ ] **Phase 0: Cross-cutting extractions (prelude)** — `Theme.from_state/1` + `Screens.Domain.get/2` helpers; grep gates #7/#8/#9 reach zero across all 9 screen files
- [ ] **Phase 1: Login** — Adopt `Input.TextInput` for handle + password; delete the hand-rolled form plumbing; `with`-chain the auth pipeline; sets TextInput precedent for Phases 2 + 7
- [x] **Phase 2: Register** ✓ 2026-04-21 — Apply Phase 1 TextInput pattern to the wizard single-line input; `with`-chain the registration pipeline; preserve the `apply/3` + `credo:disable` for `consume_invite_code` verbatim
- [ ] **Phase 3: Verify** — Keep the hand-rolled 6-char buffer (07 D-02); consolidate the 7 duplicated default-state map literals behind a file-local helper; preserve 5-attempt lockout semantics
- [ ] **Phase 4: MainMenu** — Phase-0 helper swap and sparseness discipline test; keep the `@menu_keys`/`@menu_items` duplication and letter-shortcut menu rows as inherited decisions
- [x] **Phase 5: BoardList** — Phase-0 helper swap; dead-code audit of `load_boards/1`; evaluate spinner for the async `load_boards` op (completed 2026-04-22)
- [x] **Phase 6: ThreadList** — Phase-0 helper swap; **correctness fix**: `Code.ensure_loaded/1` before `function_exported?/3` at `:136,:140`; verify `:created_by` preload; keep the two-pass sticky+recency sort (completed 2026-04-22)
- [x] **Phase 7: NewThread** ✓ 2026-04-22 — Phase-0 helper swap + `@default_terminal_size` attribute; adopt `Input.TextInput` for the title line (Phase 1 precedent); preserve the load-bearing `# NOTE: source order` comment at `:307-314`
- [ ] **Phase 8: PostComposer** — Phase-0 helper swap + `@default_terminal_size` attribute; `with`-chain the publish pipeline; **add** the missing `# NOTE: source order` comment above `:82-110`
- [ ] **Phase 9: PostReader** — Phase-0 helper swap (3 call sites — densest in the codebase); dead-code audit of `load_posts/2` and `flush_read_pointers/2`; render-path purity scrutiny (no `put_in`/`%{state | …}` inside any `defp render_*`)

## Phase Details

### Phase 0: Cross-cutting extractions (prelude)
**Goal**: Two tiny helpers land that every subsequent phase consumes, replacing the inlined theme and domain-module resolution patterns duplicated across all 9 screens.
**Depends on**: Nothing (first phase; Phases 1–9 depend on this)
**Requirements**: AUDIT-01, AUDIT-02, AUDIT-03, AUDIT-04
**Success Criteria** (what must be TRUE):
  1. `Foglet.TUI.Theme.from_state/1` exists, is called from all 9 screens + `screen_frame.ex` + `size_gate.ex` + `app.ex` modal overlay, and returns a `%Theme{}` with documented fallback when `session_context` is absent or `:theme` is missing.
  2. `Foglet.TUI.Screens.Domain.get/2` exists, is called from `board_list.ex`, `thread_list.ex`, `post_reader.ex` (×3), `post_composer.ex`, and `new_thread.ex`, supports keys `:boards | :threads | :posts | :markdown`, and returns `{:ok, module} | {:error, :not_configured}` so callers pattern-match instead of probing for `nil`.
  3. Both helpers ship with per-function tests exercising happy-path resolution, missing-`session_context` fallback, and missing-`:domain`-key fallback. `mix precommit` is green post-extraction.
  4. After Phase 0 lands, grep gates **#8** (`(Map.get(state, :session_context) \|\| %{}) \|> Map.get(:theme)`) and **#9** (`get_in(ctx, [:domain,`) return **zero** matches across `lib/foglet_bbs/tui/screens/*.ex`. Grep gate **#7** (`{80, 24}` inlined) is untouched by Phase 0 and is resolved per-screen in Phases 5/6/7/8/9 via `@default_terminal_size` attributes.
  5. No behavioural change to any screen is visible end-to-end: an SSH session renders identically pre- and post-Phase-0 at default terminal size.
**Plans**: 3 plans
  - [ ] 00-01-PLAN.md — Add `Foglet.TUI.Theme.from_state/1` + theme_test.exs (Wave 1)
  - [ ] 00-02-PLAN.md — Create `Foglet.TUI.Screens.Domain` module + domain_test.exs (Wave 1, parallel with 00-01)
  - [ ] 00-03-PLAN.md — Migrate 14 theme + 8 domain call sites across 12 files; verify grep gates #8/#9 zero (Wave 2)
**UI hint**: yes

### Phase 1: Login
**Goal**: A user logging in sees two themed input fields — handle and password — with working focus toggle, password masking, and authentication that preserves today's happy/error branches bit-for-bit; the screen drops from 347 LoC to ~150.
**Depends on**: Phase 0
**Requirements**: LOGIN-01, LOGIN-02, LOGIN-03, LOGIN-04, LOGIN-05, LOGIN-06
**Success Criteria** (what must be TRUE):
  1. A user logging in sees handle + password fields that accept input, toggle focus via Tab, mask the password with `*`, and authenticate successfully against the existing `Foglet.Accounts.authenticate_by_password/2` pipeline. The visual drift from the `█`-block cursor to whatever `Input.TextInput` renders is **accepted per user decision**.
  2. The screen file's line count is **strictly lower** than pre-Phase-1 (projected 347→~150) and its visible row count in the rendered screen is **less than or equal to** pre-Phase-1. `AUDIT-16` gate passes.
  3. The hand-rolled form plumbing — `format_input_line/3`, `input_fg/2`, `focus_style/1`, `mask_password/1`, `drop_last_grapheme/1`, `append_to_focused/2`, and the entire `handle_form_key/2` family at `:76-124` — is deleted. Login's focused-field state has migrated to `state.screen_state[:login]` with `:focused_field` + two TextInput sub-states per D-14; `init_screen_state/1` is present (it is missing today).
  4. The nested `case {:ok,_}|{:error,_}` authentication chain at `:267-308` has been rewritten as a `with` chain that preserves every happy/error branch exactly (modal payloads, `post_login_screen` dispatch, verify-code path).
  5. Rubric items `AUDIT-05..22` pass: grep gates return zero, canonical section order (AUDIT-18) satisfied with `init_screen_state/1` present (AUDIT-19), `handle_key/2` source order preserved, no spinner on instant ops, no protected-region fills, `mix precommit` green end-to-end.
**Plans**: 1 plan
  - [x] 01-01-PLAN.md — Adopt TextInput, flatten state shape, add init_screen_state/1, rewrite submit_login/1 as with chain, update tests (Wave 1)
**UI hint**: yes

### Phase 2: Register
**Goal**: A user registering walks through the wizard steps seeing a themed single-line input, with state migrated from the deprecated top-level `state.register_wizard` field into `state.screen_state[:register]`; the registration pipeline reads as a `with` chain without regressing any existing branch.
**Depends on**: Phase 0, Phase 1 (inherits TextInput integration pattern)
**Scope-fence exception:** AUDIT-13(b) — may modify `app.ex:53-56` (field declaration) and `app.ex:354-361` (wizard-dispatch) strictly for wizard-state migration.
**Requirements**: REGISTER-01, REGISTER-02, REGISTER-03, REGISTER-04, REGISTER-05, REGISTER-06
**Success Criteria** (what must be TRUE):
  1. A user completing the registration wizard (handle → email → password → confirm) submits each step through a themed `Input.TextInput`, with password-step masking preserved, and lands on the verify screen (or main menu, per `require_email_verification`) with no observable behavioural change versus today.
  2. The screen file's line count is **strictly lower** than pre-Phase-2, and its visible row count is **less than or equal to** pre-Phase-2. `AUDIT-16` passes.
  3. **Wizard-state migration complete:** `state.register_wizard` removed from the top-level App struct; `state.screen_state[:register]` is the canonical store; wizard-dispatch at `app.ex:354-361` (`:submit_step` / `:cancel_step`) routes through `state.screen_state[:register]`; `init_screen_state/1` is present on `register.ex` (AUDIT-19). Round-trip tests cover the full wizard flow (handle → email → password → confirm → submit) AND the cancel-during-step flow.
  4. The nested `case {:ok,_}|{:error,_}` chain at `:232-280` is rewritten as a `with` chain with all branches preserved. The existing `apply(Foglet.Accounts, :consume_invite_code, [code])` + `function_exported?/3` guard + `credo:disable` is preserved verbatim.
  5. Rubric items `AUDIT-05..22` pass (canonical section order AUDIT-18 satisfied; `init_screen_state/1` AUDIT-19 present); `mix precommit` green; no protected-region fill below the error line.
**Plans**: 3 plans
  - [x] 02-01-PLAN.md — Test harness rebuild: register_test.exs to screen_state shape (Wave 0)
  - [x] 02-02-PLAN.md — Structural refactor: TextInput adoption, wizard-state migration, with-chain (Wave 1)
  - [x] 02-03-PLAN.md — AUDIT-05..22 rubric sweep; Dialyzer extra_range fix; mix precommit green (Wave 2)
**UI hint**: yes

### Phase 3: Verify
**Goal**: A user entering their 6-character verification code sees the same `[ABC___]` slot visualization as today with the same 5-attempt lockout and dual-cooldown semantics, but the screen file no longer carries 7 copies of the default-state map literal and wizard state has migrated from the top-level `state.verify_state` field into `state.screen_state[:verify]`.
**Depends on**: Phase 0, Phase 2 (serialized — Phase 2 establishes the wizard-dispatch migration pattern; Phase 3 inherits it)
**Scope-fence exception:** AUDIT-13(c) — may modify `app.ex:74-75` (field declaration) and the Verify dispatch path strictly for wizard-state migration.
**Requirements**: VERIFY-01, VERIFY-02, VERIFY-03, VERIFY-04, VERIFY-05
**Success Criteria** (what must be TRUE):
  1. A user entering a 6-character code sees the `[ABC___]` slot visualization with cursor (unchanged from today); 5 failed attempts trigger the attempt-cooldown lockout exactly as verified in `phase-03-polish` Phase 03; the resend cooldown still prevents re-request spam with visible cooldown feedback.
  2. The `moduledoc` cites 07 D-02 to explain why the 6-char buffer is **kept hand-rolled** (TextInput cannot mask/render the 6-slot layout without a custom renderer; its inner `box` would conflict) — this is an inherited exception documented once, not re-litigated.
  3. A file-local private `default_verify_state/0` helper consolidates the 7 duplicated default-state map literals. The screen file's line count is **strictly lower** than pre-Phase-3 and its visible row count is **less than or equal to** pre-Phase-3.
  4. **Verify-state migration complete:** `state.verify_state` removed from the top-level App struct; `state.screen_state[:verify]` is the canonical store; `init_screen_state/1` is present on `verify.ex` (AUDIT-19). Round-trip tests cover the attempt-lockout flow and the resend-cooldown flow post-migration.
  5. Rubric items `AUDIT-05..22` pass (canonical section order AUDIT-18 satisfied; `init_screen_state/1` AUDIT-19 present); `mix precommit` green; no protected-region fill below the error line.
**Plans**: 3 plans
  - [x] 03-01-PLAN.md — Migrate Verify tests and layout smoke fixtures to `screen_state[:verify]` (Wave 0)
  - [x] 03-02-PLAN.md — Remove top-level `verify_state`; migrate Verify/Login/Register/App production ownership (Wave 1)
  - [x] 03-03-PLAN.md — Run AUDIT-05..22 closure, LoC gate, and `mix precommit` (Wave 2)
**UI hint**: yes

### Phase 4: MainMenu
**Goal**: A user on the main menu sees the same 4 content lines as today (welcome line + 3 menu rows) rendered through the Phase-0 helpers, with no new decoration that would claim the whitespace reserved for M4 last-callers/news, M6 notification badge, or M9 oneliners. The moduledoc documents the screen as intentionally stateless.
**Depends on**: Phase 0 (parallel-safe with Phases 5 and 6)
**Requirements**: MENU-01, MENU-02, MENU-03, MENU-04, MENU-05
**Success Criteria** (what must be TRUE):
  1. A user on the main menu sees exactly 4 content lines (welcome line, `[B]`, `[C]`, `[Q]` — unchanged from today); KeyBar hints are unchanged; no ASCII banner, session-info line, date/time stamp, or decorative divider is present.
  2. The screen file's visible row count is **less than or equal to** pre-Phase-4; the protected-region rule (REQUIREMENTS.md AUDIT-17 / Region 1) is enforced strictly. Any addition triggers roadmap discussion.
  3. `@menu_keys` + `@menu_items` duplication at `:9-13, 28-32` is **kept** as an inherited decision, documented in the moduledoc as load-bearing (render and KeyBar have different format needs). The `[L]/[R]/[Q]` letter-shortcut menu rows stay as plain `text/2` calls (SelectionList and Button are wrong primitives here).
  4. MainMenu's `@moduledoc` documents **"intentionally stateless — no `screen_state[:main_menu]` key"** (MENU-05) with a note that future contributors should NOT add a default hash reflexively. This is MainMenu's documented AUDIT-19 deviation.
  5. Rubric items `AUDIT-05..22` pass — with **special sparseness scrutiny** given MainMenu is 58 LoC and has the largest share of reserved layout regions; `mix precommit` green.
**Plans**: TBD
**UI hint**: yes

### Phase 5: BoardList
**Goal**: A user on the board list sees the same subscribed-boards view as today — rendered via `SelectionList` + `ListRow` (already correctly applied) — with helper swaps landed and the dead-code audit of `load_boards/1` resolved, leaving the row gutters empty for M4 presence counts and M6 badges.
**Depends on**: Phase 0 (parallel-safe with Phases 4 and 6)
**Requirements**: BOARDS-01, BOARDS-02, BOARDS-03, BOARDS-04, BOARDS-05
**Success Criteria** (what must be TRUE):
  1. A user on the board list sees their subscribed boards with per-board unread counts (unchanged from today); `j`/`k`/Enter navigation works identically; the "Loading…" text appears when `load_boards` is in flight and disappears when results arrive.
  2. The dead-code audit of `load_boards/1` at `:86-91` has been run (`rg -w load_boards test/ lib/`): result is either deleted if uncalled or annotated `@doc false` with an explanatory comment if called only by tests. The chosen resolution is documented in the phase SUMMARY.md.
  3. Spinner adoption for "Loading boards…" has been **evaluated** against `AUDIT-10` (adopt only if op takes >1 render frame AND completion is observable; never on an instant op). Decision logged per phase — default outcome: keep plain text unless observation shows spinner helps.
  4. `SelectionList` + `ListRow` usage is unchanged (research flagged as correctly applied); no row gutters are filled (REQUIREMENTS.md AUDIT-17 / Region 2 protected for M4/M6).
  5. Rubric items `AUDIT-05..22` pass (canonical section order AUDIT-18; `init_screen_state/1` AUDIT-19 present or intentional-stateless documented); `mix precommit` green; screen-file line count and visible row count are both **less than or equal to** pre-Phase-5.
**Plans**: TBD
**UI hint**: yes

### Phase 6: ThreadList
**Goal**: A user on the thread list sees creator handle, post count, and time-ago metadata on every row (unchanged from today), with the sticky-then-recency sort preserved and — critically — the `function_exported?/3` call at `:136,:140` now guarded by `Code.ensure_loaded/1` so the 2-arity `list_threads/2` path is no longer silently bypassed for unloaded modules.
**Depends on**: Phase 0 (parallel-safe with Phases 4 and 5)
**Requirements**: THREADS-01, THREADS-02, THREADS-03, THREADS-04, THREADS-05, THREADS-06, THREADS-07
**Success Criteria** (what must be TRUE):
  1. A user on the thread list of a 3-thread seeded board sees each row render with creator handle, post count, and time-ago (e.g. `@alice · 3 posts · 2h`); the sticky-then-recency sort still applies (sticky rows first in recency order, then non-sticky rows in recency order).
  2. `function_exported?(threads_mod, :list_threads, 2)` at `:136` and `(…, 1)` at `:140` are **preceded by `Code.ensure_loaded/1`**; a new test asserts that when a stub threads module defining `list_threads/2` is injected via `session_context.domain[:threads]`, the 2-arity path is selected (proves the correctness fix landed).
  3. `Threads.list_threads/2` preloads `:created_by` and a new test asserts `thread.created_by.handle` is present on returned rows — the ListRow render depends on it and today's coverage does not lock it in.
  4. The dead-code audit of `load_threads/2` at `:128-147` has been run; result (delete or `@doc false`) is documented in SUMMARY.md. The two-pass sticky+recency sort at `:159-179` is **kept** (naive `desc` + nil would crash/misorder — inherited decision). Spinner for "Loading…" evaluated per `AUDIT-10`.
  5. Rubric items `AUDIT-05..22` pass (canonical section order AUDIT-18; `init_screen_state/1` AUDIT-19 present or intentional-stateless documented); `mix precommit` green; screen-file line count and visible row count are both **less than or equal to** pre-Phase-6; row padding (REQUIREMENTS.md AUDIT-17 / Region 3) is not filled.
**Plans**: TBD
**UI hint**: yes

### Phase 7: NewThread
**Goal**: A user composing a new thread sees a themed `Input.TextInput` for the title line (replacing the hand-rolled `█`-cursor rendering) while the body composer continues to use `Compose` + `MultiLineInput` unchanged; the load-bearing source-order comment at `:307-314` is preserved through any reformatter touch.
**Depends on**: Phase 0, Phase 1 (inherits TextInput integration pattern; parallel-safe with Phase 8)
**Requirements**: NEWTHREAD-01, NEWTHREAD-02, NEWTHREAD-03, NEWTHREAD-04, NEWTHREAD-05
**Success Criteria** (what must be TRUE):
  1. A user composing a new thread enters the title via a themed `Input.TextInput` (replacing the hand-rolled title input at `:124-128`); body composition via `Compose` + `MultiLineInput` is unchanged; Ctrl+S publishes the thread via `Foglet.Threads.create_thread/3` and returns the user to the thread list with the new thread at the top.
  2. Theme extraction, domain-module lookup, and `{80, 24}` fallbacks route through Phase-0 helpers + a `@default_terminal_size` module attribute — grep gates #7/#8/#9 return zero on the screen file.
  3. The load-bearing `# NOTE: source order matters for handle_key/2 clauses — do not reorder` comment at `:307-314` is **preserved verbatim**. The body composer's `Compose` + `MultiLineInput` pipeline (Phase-5 D-13 inheritance; re-entry guards load-bearing) is unchanged.
  4. The screen file's line count is **strictly lower** than pre-Phase-7 and its visible row count is **less than or equal to** pre-Phase-7; the area below the char counter (REQUIREMENTS.md AUDIT-17 / Region 6) is not filled.
  5. Rubric items `AUDIT-05..22` pass (canonical section order AUDIT-18; `init_screen_state/1` AUDIT-19 present or intentional-stateless documented); `mix precommit` green.
**Plans**: TBD
**UI hint**: yes

### Phase 8: PostComposer
**Goal**: A user replying to a thread publishes through a `with`-chained submit pipeline (replacing the nested `case {:ok,_}|{:error,_}` chain at `:252-306`) with all modal-error branches preserved; the missing `# NOTE: source order` comment above `:82-110` is added to match the Phase 7 precedent.
**Depends on**: Phase 0 (parallel-safe with Phase 7)
**Requirements**: COMPOSER-01, COMPOSER-02, COMPOSER-03, COMPOSER-04, COMPOSER-05
**Success Criteria** (what must be TRUE):
  1. A user pressing `[R]` from the post reader, typing a reply, and submitting with Ctrl+S lands back on the thread with the new post visible; every existing modal-error branch (empty body, too-long body, domain-error payloads) is preserved bit-for-bit through the `with`-chain rewrite.
  2. Theme extraction, domain-module lookup, and `{80, 24}` fallbacks route through Phase-0 helpers + a `@default_terminal_size` module attribute — grep gates #7/#8/#9 return zero on the screen file.
  3. The `# NOTE: source order matters for handle_key/2 clauses — do not reorder` comment is **added** above `:82-110` (matching the Phase 7 `new_thread.ex:307-314` precedent; currently only `new_thread.ex` has it).
  4. `Compose` + `MultiLineInput` is unchanged (inherited); the screen file's line count is **less than or equal to** pre-Phase-8 and its visible row count is **less than or equal to** pre-Phase-8; the area below the char counter (REQUIREMENTS.md AUDIT-17 / Region 6) is not filled.
  5. Rubric items `AUDIT-05..22` pass (canonical section order AUDIT-18; `init_screen_state/1` AUDIT-19 present or intentional-stateless documented); `mix precommit` green.
**Plans**: TBD
**UI hint**: yes

### Phase 9: PostReader
**Goal**: A user reading a 3-post thread navigates posts with `j`/`k`/Space and sees every post render through the existing `PostCard` + `MarkdownBody` + `Viewport` pipeline (unchanged); the 3 inlined domain-module call sites collapse to Phase-0 helper calls (the densest concentration in the codebase); render-path purity is verified — no mutation inside any `defp render_*`.
**Depends on**: Phase 0 (must run last; no parallel partner — Phase 9 is the final block)
**Requirements**: READER-01, READER-02, READER-03, READER-04, READER-05, READER-06, READER-07
**Success Criteria** (what must be TRUE):
  1. A user navigating a seeded 3-post thread with `j`/`k`/Space/`q` sees each post render through the unchanged `PostCard` + `MarkdownBody` + `Viewport` pipeline; the render_cache (line-width keyed at `:77-82`) still warms on first render and hits on re-renders; read pointers still flush on screen exit.
  2. Theme extraction and domain-module lookup route through Phase-0 helpers at all 3 call sites on this screen (densest in the codebase) — grep gates #8 and #9 return zero on `post_reader.ex`.
  3. The dead-code audit of `load_posts/2` at `:158-181` and `flush_read_pointers/2` at `:197-209` has been run; result (delete or `@doc false`) is documented in SUMMARY.md. The `PostCard` + `MarkdownBody` + `Viewport` pipeline is **kept** as inherited (07 D-12/D-13); any change here exits audit scope.
  4. Render-path purity is scrutinized most carefully here: no `put_in`, no `%{state | …}`, no `Map.put(state.screen_state, …)` inside any `defp render_*` function. The existing `render_cache` warming pattern at `:77-82` is the only accepted mutation site and remains in a non-render helper.
  5. PostReader's `@moduledoc` documents the **load-absorb pattern** (READER-07) — `advance_post`/`scroll_post` returning `{:update, state, []}` when `state.posts == []` to absorb keys during loading (`:343-347, 379-383`). This is PostReader's documented AUDIT-18 deviation (render_cache plumbing in §9 instead of §8).
  6. Rubric items `AUDIT-05..22` pass (canonical section order AUDIT-18; `init_screen_state/1` AUDIT-19 present or intentional-stateless documented); `mix precommit` green; the header strip (REQUIREMENTS.md AUDIT-17 / Region 4) and footer (Region 5) are **not filled** — both are reserved for M6 reply-tree/mentions and M9 upvote. Line-count reduction here is expected to be smaller than other phases (PostReader is mostly already where we want it).
**Plans**: TBD
**UI hint**: yes

## Progress

**Execution Order:**
Phase 0 is a hard prerequisite for every other phase. Phase 1 is serial (precedent-setter for TextInput adoption). **Phases 2 and 3 are serialized** (previously parallel) — both modify `app.ex` wizard-dispatch paths during the top-level wizard-state migration, and Phase 3 inherits Phase 2's dispatch pattern. Phases 4, 5, and 6 may run in parallel once Phase 3 is done (Phase 4–6 depend only on Phase 0 structurally; wait for Phase 3 is only to sequence serial phases cleanly). Phases 7 and 8 may run in parallel once Phase 0 (and Phase 1 for Phase 7's TextInput inheritance) is done. Phase 9 must be last.

Critical path: `0 → 1 → 2 → 3 → (4+5+6) → (7+8) → 9` — 7 serial blocks across 10 phases.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 0. Cross-cutting extractions (prelude) | 0/3 | Planned | - |
| 1. Login | 0/1 | Planned | - |
| 2. Register | 3/3 | Complete | 2026-04-21 |
| 3. Verify | 0/3 | Planned | - |
| 4. MainMenu | 0/TBD | Not started | - |
| 5. BoardList | 1/1 | Complete    | 2026-04-22 |
| 6. ThreadList | 0/1 | Complete    | 2026-04-22 |
| 7. NewThread | 1/1 | Complete | 2026-04-22 |
| 8. PostComposer | 0/TBD | Not started | - |
| 9. PostReader | 0/TBD | Not started | - |
