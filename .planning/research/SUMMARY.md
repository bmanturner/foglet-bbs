# Project Research Summary

**Project:** Foglet BBS v1.4 Post-Facelift Polish & Bug Fixes
**Domain:** Brownfield TUI bug-fix milestone — Elixir/Phoenix + vendored Raxol over SSH
**Researched:** 2026-04-26
**Confidence:** HIGH

## Executive Summary

- **No new dependencies are required for v1.4.** All ~37 ISSUES.md defects are fixable inside existing TUI widget/screen code with one small SSH-side protocol addition (bracketed paste). The roadmap should not budget a "stack work" phase. (`STACK.md` §TL;DR, §"Add: No new runtime dependencies are warranted for v1.4.")
- **Three structural root causes account for ~70% of the bug list.** ROOT-A is a width-math primitive shared by tab-row trailing glyphs, the Oneliners `||||` artifact, and the cramped Invites/LOG tables. ROOT-B is form event routing (Modal.Form focus + Esc/Enter wiring + cursor follow). ROOT-C is screen-frame layout + Sysop load-on-mount lifecycle. Fix the root once and downstream symptoms collapse together. (`FEATURES.md` §"Feature Dependencies", `ARCHITECTURE.md` §"Cross-fix Ordering Constraints")
- **One legitimate domain-boundary change**, not a feature: the no-email password reset token-consume entry point (Login #4) crosses into `Foglet.Accounts` for `verify_reset_token/1` + `reset_password_with_token/3` (atomic single-use inside `Repo.transact/1`). Every other ISSUES.md item is TUI-only. (`ARCHITECTURE.md` §D, `PITFALLS.md` R2)
- **Two ISSUES.md items already RESOLVED pre-milestone** must not be re-spec'd: Boards #3 (board-select freeze) and Main Menu #3 (Up/Down arrows inert). Both confirmed in `PROJECT.md` Current Milestone "Already resolved" subsection. (`FEATURES.md` CAT-MAINMENU-ARROWS, CAT-BOARDS-FREEZE)
- **Recommended phasing is 8 phases.** Layout primitives first (P1) so visual verification is reliable, cursor + breadcrumbs in parallel (P2), then form interaction (P3), then Sysop load lifecycle + tab bodies (P4), Account workflow (P5), auth flow + no-email reset (P6), Main Menu chrome polish (P7), composer wrap + markdown newlines + Boards Enter (P8).

## Key Findings

### Recommended Stack

No new dependencies. v1.4 is configuration/wiring/code fixes against the existing v1.3 stack. (`STACK.md` §TL;DR)

**Existing stack (locked, do not re-research):**
- **Elixir 1.19.5 / Erlang/OTP 28.3.1 / Phoenix 1.8.5** — runtime baseline.
- **Vendored Raxol** — already provides `MultiLineInput` with `:word` wrap, `Display.Table` with `column_widths: :auto`, `Display.Tree` with expand/collapse, `Modal`, `Tabs`, `Input.SelectList` with `enable_search`. The bugs are integration/configuration in Foglet code, not Raxol gaps.
- **MDEx ~> 0.2** — supports `[render: [hardbreaks: true]]` for Globally #2.
- **Timex 3.7 + Tzdata 1.1.3** (transitive) — `Tzdata.zone_list/0` already available for Account #6 timezone picker datasource.
- **`:ssh` (Erlang built-in)** — bracketed paste is a ~80 LOC ANSI-protocol addition in `Foglet.SSH.CLIHandler`, not a library.

**Five candidate dependencies were considered and rejected** (`STACK.md` §"Add" table): no new csv/table-layout, no `tz`/`tz_extra`, no `nimble_options`, no Erlang bracketed-paste lib, no `earmark`. Each has a justification recorded.

### Expected Features

v1.4 ships **expected behaviors of polish primitives**, not new product features. SEED-001 (webhooks) and SEED-002 (verification UX) remain dormant. (`FEATURES.md` §"Anti-Features Summary")

**Must have (table stakes, all from ISSUES.md):**
- Layout fits 64×22 minimum across every touched screen, no overflow, no trailing-glyph artifacts. (`FEATURES.md` CAT-MOD-LAYOUT-OVERFLOW, CAT-BOARDS-LAYOUT-OVERFLOW, CAT-GLOBAL-TAB-GLYPHS)
- Forms behave as advertised: Tab/Shift+Tab moves focus, Esc cancels, Enter submits to a single inline confirmation, focus is single-owner, cursor follows the typed character. (`FEATURES.md` CAT-FORM-FOCUS, CAT-FORM-KEYBINDS, CAT-AUTH-CURSOR)
- Sysop tabs auto-load on tab switch (no "press any key"), and BOARDS/LIMITS/SYSTEM/USERS render data or an honest error state with `[R] Retry`. (`FEATURES.md` CAT-SYSOP-LOAD-ON-MOUNT, CAT-SYSOP-TAB-LOADS)
- Profile submit persists across screen exit/re-entry; preferences fields are reachable and selectable; SSH key paste accepts a multi-line OpenSSH key as a single value. (`FEATURES.md` CAT-ACCOUNT-PROFILE-PERSIST, CAT-ACCOUNT-PREFERENCES-OPTIONS, CAT-ACCOUNT-SSHKEYS-PASTE)
- Forgot-password validates email locally, renders cleanly at 64×22, and provides an honest no-email reset path with a token-consume screen. (`FEATURES.md` CAT-AUTH-VALIDATION, CAT-AUTH-RESET-RENDER, CAT-AUTH-NO-EMAIL)
- Markdown preserves paragraph breaks (max 1 blank line); composer soft-wraps long lines. (`FEATURES.md` CAT-MARKDOWN-NEWLINES, CAT-COMPOSER-WORDWRAP)
- Boards-screen Enter on a category expands/collapses (Boards #2). Boards #3 freeze is RESOLVED pre-milestone.

**Should have (cheap differentiators worth doing):**
- Type-ahead narrowing in timezone selector (`SelectList` with `enable_search: true`). (`FEATURES.md` CAT-ACCOUNT-TIMEZONE)
- Color-coded invite-status badges via existing `Display.Badge`. (`FEATURES.md` CAT-SYSOP-INVITES-TABLE)
- Sysop command bar consistency: every tabbed screen advertises `1-N Jump`. (`FEATURES.md` CAT-SYSOP-COMMANDBAR-CONSISTENCY)

**Defer (do not pull into v1.4):**
- Operator-side reveal of unconsumed reset tokens in Sysop › Users.
- Per-user persisted Boards expand/collapse state.
- Background prefetch of next/prev Sysop tab.
- Hard-wrap-on-submit in composer; tight-mode markdown soft-break-as-space sysop config.
- Drag-paste detection fallback for clients without bracketed-paste support.

**Anti-features (cross-cutting "do not build"):**
No browser-based reset, no horizontal scrolling on tables, no auto-save on blur, no toast/dismissable modals, no hardcoded color literals (`IO.ANSI.cyan/0`, raw escape strings), no widget-internal focus state, no new authorization scope shapes beyond `:site` and `{:board, board_id}`. (`FEATURES.md` §"Anti-Features Summary", `PITFALLS.md` W2, A2)

### Architecture Approach

The v1.4 work is **mostly modify, with a few small new components**. (`ARCHITECTURE.md` §"New Components vs Modified Components — Summary")

**Touch points by category:**
1. **Layout/widget primitives:** `widgets/input/tabs.ex` (trailing glyph), `widgets/display/table.ex` + `console_table.ex` (Invites cramping, LOG truncation), `widgets/list/board_tree.ex` (Boards overflow), `widgets/post/markdown_body.ex` (newline collapse), `widgets/compose.ex` + a new `TextWidth.wrap/2` (composer wrap).
2. **Form interaction:** `widgets/modal/form.ex` (Up/Down inter-field movement, `:backtab`, optional footer), `widgets/input/text_input.ex` (cursor follows insertion point, mirroring the technique already in `widgets/compose.ex:130-148`), `widgets/chrome/breadcrumb_bar.ex` (Register/Verify/login sub-state segments).
3. **Screen-level:** Sysop screen auto-loads tab data on `{:tab_changed, idx}` instead of on next keystroke; per-tab submodules (`boards_view.ex`, `limits_form.ex`, `system_snapshot.ex`, `users_view.ex`) get defensive `init/1`. Account `profile_form.ex` + `prefs_form.ex` + `state.ex` get correct submit-state machine and persistence-after-re-entry. Login screen gets reset-validation, reset-message word-wrap, and a new `:reset_consume` sub-state.
4. **Domain (only one):** `Foglet.Accounts.consume_password_reset_token/2` (or two-step `verify_reset_token/1` + `reset_password_with_token/3` per `PITFALLS.md` R2). `lib/foglet_bbs/config/schema.ex` field descriptions get user-facing copy (Sysop #4).
5. **SSH boundary:** `Foglet.SSH.CLIHandler` emits `\e[?2004h` on PTY up, `\e[?2004l` on close, and unwraps `\e[200~…\e[201~` into a synthetic `:paste` event before delegating to `Raxol.SSH.IOAdapter.parse_input/1`. ~80 LOC, no vendored Raxol fork. (`STACK.md` §"Bracketed-Paste Implementation Sketch")

### Critical Pitfalls

Top items from `PITFALLS.md` that gate phase definition:

1. **L1/L5 Width-math bypass** — Polish PRs reach for `String.length`, `String.slice`, `String.pad_trailing`, or `byte_size` because they're "obvious" fixes. Those count graphemes, not display cells. Every layout fix must route through `Foglet.TUI.TextWidth`. Add a grep-test in widgets/screens directories.
2. **L2 64×22 regression** — v1.3 added 64×22/80×24/132×50 smoke for composers but not for Moderation/Boards/Invites surfaces. Every layout fix in P1 must add snapshot tests at both 64×22 and 80×24.
3. **F1/F4 Focus divergence** — Account #8 ("type anything, the timezone field is selected") is a single-source-of-truth bug. Parent `state.focused_field` must be the only truth; widgets take `focused?` as an explicit prop and never store internal focus state when used inside a form.
4. **F3/F7 Submit double-fire and silent persistence failure** — Form state needs an explicit `submit_state :: :idle | :submitting | :saved | {:error, _}` enum; only `:idle` accepts Enter; submit handlers must pattern-match on all three result shapes (no fallthrough `_`). Persistence must be verified by integration test (save → leave → re-enter → assert values).
5. **T1/T4/T5 Sysop tab loading** — Move to on-tab-switch lifecycle hook in `screens/sysop.ex` mirroring existing `maybe_load_invites_on_entry/2`. Distinguish `:not_loaded | :loading | {:loaded, data} | {:error, reason}` so `{:error, :forbidden}` doesn't render as a blank panel.
6. **R2 Token consume race** — Two-call boundary: `verify_reset_token/1` does NOT consume, `reset_password_with_token/3` consumes inside `Repo.transact/1`. Test concurrent consume → exactly one wins.
7. **W1 Shared `InvitesSurface` regression** — Account, Moderation, and Sysop all consume the same `lib/foglet_bbs/tui/screens/shared/invites_*.ex`. Any change here needs a cross-surface matrix test.
8. **A1/A3 Authorization shortcuts** — Hidden/disabled UI is never authorization (`AGENTS.md`); every Sysop tab load command must `Bodyguard.permit/4` against `Foglet.Authorization` with `:site` scope. Don't loosen a changeset to paper over a missing form widget.

## Implications for Roadmap

The build order is driven by three structural dependencies (`ARCHITECTURE.md` §"Suggested Phase Build Order", `FEATURES.md` §"Critical Ordering Constraints"):

A. Layout fixes block visual verification of every form/interaction fix.
B. Focus-routing fixes block Account/Sysop edit verification.
C. Sysop tab auto-load fix blocks Sysop tab body fixes.

### Recommended Phase Grouping (8 phases)

**Phase 1 — Foundation (Layout + width-math primitive)**
**Rationale:** Every screen renders through `Tabs`, `Display.Table`, `ConsoleTable`, `MarkdownBody`, `BoardTree`, and `Compose`. Land widget-layer fixes first so manual + snapshot verification is reliable for every later phase. ROOT-A here.
**Delivers:** Tab-row trailing-glyph fix (`tabs.ex` owns `x0..x_end-1`, frame owns `x_end`). Invites-table column allocation via `column_widths: :auto` + per-column hints. Moderation LOG/USERS/BOARDS overflow + responsive widths. Boards screen overflow clamping. `Foglet.TUI.TextWidth.wrap/2` helper. Markdown blank-line preservation in `markdown_body.ex group_by_newline/1`.
**Addresses:** Globally #1, Globally #2, Sysop #12, Moderation #1, Moderation #2, Boards #1.
**Avoids:** L1, L2, L3, L4, W1.

**Phase 2 — TextInput cursor + breadcrumbs (parallel-safe with P1)**
**Rationale:** Both are widget-layer fixes touched by every form-having screen, but neither blocks P1. Land cursor before any form fix so "is my keystroke landing?" is verifiable. Breadcrumb fix unblocks the no-email reset sub-state in P6.
**Delivers:** `widgets/input/text_input.ex` cursor injected at `cursor_pos` (mirror `widgets/compose.ex:130-148`). `widgets/chrome/breadcrumb_bar.ex` clauses for `:register`, `:verify`, and login `:sub` (`:menu`/`:login_form`/`:reset_request`/new `:reset_consume`).
**Addresses:** Login #1, Login #3.
**Avoids:** F6, R1.

**Phase 3 — Modal.Form interaction (ROOT-B)**
**Rationale:** Account #4, #5, #7, #8 plus Sysop #3, #5, #11 all stem from the same form event-routing surface. Fix the routing primitive once.
**Delivers:** Up/Down inter-field focus movement on text fields (preserve enum-cycling for `:enum`). `:backtab` accepted alongside `{tab, shift: true}` and `:shift_tab`. Optional footer (`opts[:footer]` defaulting `false`). Submit-state enum + idempotency for Enter. Esc precedence documented in `Foglet.TUI.App` doc.
**Addresses:** Account #1, #2, #4, #5, #7, #8; Sysop #3, #5, #11.
**Avoids:** F1, F2, F3, F4, F7.
**Depends on:** P1 for stable visual verification.

**Phase 4 — Sysop load lifecycle + tab bodies (ROOT-C)**
**Rationale:** Auto-load on tab switch must land before per-tab body fixes — you can't verify USERS keys until USERS loads. Existing `maybe_load_invites_on_entry/2` is the pattern to mirror.
**Delivers:** `screens/sysop.ex` calls each new tab's submodule `init/1` on `{:tab_changed, idx}`. Defensive `init/1` in `boards_view.ex`, `limits_form.ex`, `system_snapshot.ex`, `users_view.ex`. Tagged enum render `:not_loaded | :loading | {:loaded, data} | {:error, reason}`. SiteForm draft-echo + `:escape` reset + submit feedback + `Schema` description copy fix. UsersView keybinds reconciled and gated by user status. `Bodyguard.permit/4` on each load command.
**Addresses:** Sysop #1, #2, #4, #6, #7, #8, #9, #10, #11, #13.
**Avoids:** T1, T2, T3, T4, T5, A1.
**Depends on:** P1 (table widgets), P3 (form widget patterns).

**Phase 5 — Account workflow (Profile persistence + SSH key paste + timezone selector)**
**Rationale:** Profile persistence-after-re-entry is the visible payoff of P3's submit-state machine; SSH key paste is the only ISSUES.md item that crosses the SSH↔TUI boundary.
**Delivers:** Verify `Accounts.update_profile/2` returns updated user; integration test save → leave → re-enter → values persist. SSH key paste: prefer **bracketed paste in `Foglet.SSH.CLIHandler`** (~80 LOC) emitting `:paste` event; fallback for older clients is converting `:public_key` to a `:textarea` field type. Account Esc disposition (product decision needed). Account timezone selector via `SelectList` with `enable_search: true` against `Tzdata.zone_list/0`.
**Addresses:** Account #3, #6, #9.
**Avoids:** F5, F7, A3.
**Depends on:** P3 (form patterns), P2 (cursor for verification).

**Phase 6 — Auth flow (validation + reset render + no-email consume)**
**Rationale:** Largest "new component" pocket and the only v1.4 work that crosses a domain boundary. Sequence after the established form/cursor/breadcrumb foundations are stable.
**Delivers:** Forgot-password local email validation (reuse `User.validate_email/1` regex). Reset-message word-wrap via `TextWidth.wrap/2`. Honest delivery-mode branching: `:no_email` UX copy names the operator path. New `:reset_consume` sub-state in `screens/login.ex`. New `Foglet.Accounts.verify_reset_token/1` (non-consuming) + `reset_password_with_token/3` (consumes inside `Repo.transact/1`). Token never appears in chrome/breadcrumb/status.
**Addresses:** Login #2, Login #4 (cropping + no-email + token-consume entry).
**Avoids:** R1, R2, R3, R4.
**Depends on:** P1 (`TextWidth.wrap`), P2 (breadcrumb segment for `:reset_consume`).

**Phase 7 — Main Menu chrome polish**
**Rationale:** Independent surface; schedule near the end so test churn around `main_menu_test.exs` happens once. Note: Main Menu #3 is **RESOLVED pre-milestone** and must not be re-spec'd.
**Delivers:** Box border with embedded title for Navigation/Oneliners. Oneliners glyph artifact resolution (likely a side-effect of moving title to border, possibly shares ROOT-A width-math). `nav_row/3` split into `[text(prefix, primary.fg), text(key, accent.fg)]` inside a `row`. Indent corrections. Theme routing through `Foglet.TUI.Theme` slots only.
**Addresses:** Main Menu #1, #2, #4, #5, #6, #7. (Main Menu #3 = RESOLVED, do not include.)
**Avoids:** W2.

**Phase 8 — Composer word-wrap + Boards Enter-on-category**
**Rationale:** Both are independent post-foundation fixes. Composer wrap consumes `TextWidth.wrap/2` from P1. Boards Enter is single-screen.
**Delivers:** `widgets/compose.ex render_input/4` runs each line through `TextWidth.wrap/2`. Update three `MultiLineInput.init/1` call sites from `wrap: :none` to `wrap: :word`; pass updated `width:` on resize. `screens/board_list.ex` Enter handler inspects focused entry's `:kind`; on `:category` toggles via `BoardTree.handle_event` `:right`/`:left` semantic.
**Addresses:** Globally #3, Boards #2. (Boards #3 = RESOLVED, do not include.)
**Avoids:** L5, A4.

### Phase Ordering Rationale

- **P1 before P3/P4/P5:** Layout primitives stabilize the canvas; form bugs are partly perception-bugs caused by misaligned tables and missing cursors.
- **P2 parallel with P1:** TextInput cursor is widget-layer; breadcrumbs is chrome-layer; neither shares files with P1 layout fixes.
- **P3 before P4 form bodies and P5 Account workflow:** Modal.Form is the shared substrate. Without inter-field Up/Down, Preferences UX still doesn't work.
- **P4 internal serialization:** Auto-load fix first, then per-tab-body fixes.
- **P5 after P3 + P2:** Account profile persistence depends on submit-state-machine; SSH key paste verification depends on cursor.
- **P6 last among auth work:** Largest new-component pocket; needs P1's wrap helper and P2's breadcrumb wiring.
- **P7 + P8 anywhere after P1:** Independent surfaces; group at the end to consolidate test churn.

### Research Flags

Phases likely needing deeper research during planning:
- **P5 (SSH key paste):** Verify whether `Raxol.Terminal.ANSI.InputParser` is in the vendored tree (`ARCHITECTURE.md` confidence note: LOW). The `CLIHandler`-side unwrap path is implementable regardless. Recommend a small spike at phase open.
- **P4 (Sysop submodule failure modes):** `ARCHITECTURE.md` MEDIUM confidence on whether BOARDS/LIMITS/SYSTEM tabs fail because of silent init crashes or auth denials returning blank. Phase open should read those four files first.
- **P5 (Account profile persistence):** Root-cause of "values gone on re-enter" is MEDIUM-confidence — could be `seed_from_user` or `Accounts.update_profile/2` return shape. Phase open writes the integration test first.

Phases with standard patterns (no `/gsd-research-phase` needed):
- **P1, P2, P7, P8** — well-understood widget/render fixes against documented Raxol primitives.
- **P3** — Modal.Form already audited in `ARCHITECTURE.md` §B with line numbers; fix is mechanical.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | `STACK.md` cross-checked `mix.exs`/`mix.lock` and verified each rejected candidate. |
| Features | HIGH | `FEATURES.md` is grounded directly in ISSUES.md; existing widget catalog confirms primitives exist. |
| Architecture | HIGH on directly-verified locations; MEDIUM on Sysop submodule init failure modes and the exact Account profile persistence root cause. |
| Pitfalls | HIGH | `PITFALLS.md` grounded in `AGENTS.md`, `ISSUES.md`, the actual `lib/foglet_bbs/tui/**` layout, and v1.3 close-out notes. |

**Overall confidence:** HIGH for phasing and most fix locations; MEDIUM on three specific items flagged above.

### Gaps to Address

- **Sysop tab failure mode confirmation (P4):** Read `boards_view.ex`/`limits_form.ex`/`system_snapshot.ex`/`users_view.ex` at phase open before designing the defensive `init/1` shape.
- **Account profile persistence root cause (P5):** Write integration test first; don't speculate.
- **Bracketed paste implementation surface (P5):** Confirm CLIHandler unwrap can live before `IOAdapter.parse_input/1` delegation without forking vendored Raxol.
- **Esc UX disposition (P5):** Product decision needed — pop a "changes discarded" toast on Esc, or drop the misleading `[Esc] Cancel` hint.
- **Markdown soft-break-as-line-break vs. as-space:** Confirm with product owner before P8 lands.

## Resolved Pre-Milestone (struck from scope)

These two ISSUES.md items were resolved between filing and milestone start (per `PROJECT.md` Current Milestone "Already resolved" subsection) and **must not be included in the roadmap**:

- **Boards Screen #3** — selecting a board freezes the screen. Resolved.
- **Main Menu Screen #3** — Up/Down arrows inert on navigation. Resolved.

## Sources

### Primary (HIGH confidence)
- `.planning/research/STACK.md` — dependency verdicts, bracketed-paste implementation sketch, per-issue stack mapping.
- `.planning/research/FEATURES.md` — per-category table-stakes/differentiator/anti-feature matrix, fix-ordering dependency graph.
- `.planning/research/ARCHITECTURE.md` — per-category integration map with file paths and line numbers, modify-vs-new component summary, suggested 10-phase build order.
- `.planning/research/PITFALLS.md` — phase-mapped pitfalls (L/F/T/R/W/A series), looks-done-but-isn't checklist.
- `ISSUES.md` — the 37 v1.4 bugs.
- `.planning/PROJECT.md` — current milestone scope and the "Already resolved" subsection that defines what's struck.
- `AGENTS.md` — boundaries, authorization model, scope shapes, testing finish line.

### Secondary (MEDIUM confidence)
- `docs/raxol/getting-started/WIDGET_GALLERY.md` — confirmed primitives.
- Source files referenced by `ARCHITECTURE.md` with line numbers (verified): `widgets/input/tabs.ex:90-105`, `widgets/modal/form.ex:101-153`, `screens/sysop.ex:113-146`, `screens/login.ex:144-154`, `widgets/post/markdown_body.ex group_by_newline/1`, `widgets/chrome/breadcrumb_bar.ex:66-82`, `widgets/input/text_input.ex:117-124`, `widgets/compose.ex:130-148`.

### Tertiary (LOW confidence — needs validation at phase open)
- `Raxol.Terminal.ANSI.InputParser` location in vendored tree (P5 spike).
- Sysop submodule `init/1` failure modes (P4 spike).
- Account profile persistence root cause (P5 integration test).

---
*Research synthesis completed: 2026-04-26 — v1.4 Post-Facelift Polish & Bug Fixes*
*Ready for roadmap: yes*
