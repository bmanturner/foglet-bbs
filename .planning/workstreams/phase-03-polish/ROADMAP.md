# Roadmap: Foglet BBS — Phase 03 Polish (v1.0.1)

## Overview

v1.0.1 is a polish/hardening pass on the SSH + Raxol TUI delivered in the main workstream's Phase 03. Scope is strictly **fix what shipped** — zero new domain features, zero new runtime deps. The six phases below derive from seven natural delivery boundaries in the research, with the P0 seeds step folded into Phase 1 (seed fixtures were largely handled by commit `9578faf` and any remaining tweaks belong with the widget foundation work).

**Strict dependency chain:** Phase 1 → Phase 2 → Phase 3. Phases 4, 5, and 6 are independent after Phase 1 lands, and may ship in any order once their prerequisites are met.

**Reshape note vs research proposal:** The research proposed a P0 "Seeds & fixtures" phase. That work landed in commit `9578faf add thread seed; fix threads not showing`; any residual fixture audit (valid `message_number`, non-nil `last_post_at`) rides in Phase 1 as a precondition of the widget foundation — a standalone phase would add ceremony without scope. Every other phase boundary from the research is preserved.

## Phases

**Phase Numbering:**
- Integer phases (1–6): Planned polish work for v1.0.1
- Decimal phases (e.g., 2.1): Reserved for urgent insertions if surfaced mid-milestone

- [x] **Phase 1: Widget foundation + theme + screen chrome** - Reusable function-form widget layer, per-session theme struct, and consistent screen chrome land before any correctness work (completed 2026-04-19)
- [x] **Phase 2: Markdown rendering correctness** - Posts render as styled terminal output instead of raw markdown; wrapping is stable across terminal widths (completed 2026-04-20)
- [x] **Phase 3: Read-pointer correctness + thread-row enrichment** - Board unread counts decrement monotonically and reach zero; thread rows show creator, last-activity time-ago, and post count (completed 2026-04-20)
- [ ] **Phase 4: Composer & thread creation end-to-end** - `[C]` from thread list creates a new thread; `[R]` from post reader creates a reply; the broken crash-on-compose branch is removed
- [ ] **Phase 5: Terminal size gate** - Terminals below the agreed minimum dimensions show a "too small" message; resizing back restores the prior screen with state intact (threshold decided during Phase 5 discussion)
- [ ] **Phase 6: Email verification toggle + resend** - Sysop can disable email verification via config; verify screen exposes a working resend affordance with cooldown feedback

## Phase Details

### Phase 1: Widget foundation + theme + screen chrome
**Goal**: A user sees consistent chrome (bordered frame, status bar with their handle, divider, content, key bar) on every screen, with one consistent color palette.
**Depends on**: Nothing (first phase; all downstream phases depend on this)
**Requirements**: WIDGET-01, WIDGET-02, THEME-01, FRAME-01, FRAME-02, LIST-04
**Success Criteria** (what must be TRUE):
  1. Every screen the user visits (login, register, verify, main menu, board list, thread list, post reader, post composer, new thread) shows a bordered frame with a status bar on top, a divider, content, and a key bar at the bottom
  2. The status bar consistently shows the page title and — when authenticated — the user's handle
  3. The same color palette (border, primary text, dim text, accent, error, warning) is applied across every screen; no green-on-green or un-themed border remains
  4. Board list, thread list, and new-thread board-picker navigate identically with `j`/`k`/Enter via one shared `SelectionList` widget
**Plans**: TBD
**UI hint**: yes

### Phase 2: Markdown rendering correctness
**Goal**: A user reading the seeded General threads sees formatted terminal output — bold, italic, headers, code, lists, quotes, links — instead of raw `**asterisks**` and visible `\n` artifacts.
**Depends on**: Phase 1 (consumes `Post.MarkdownBody` widget and theme)
**Requirements**: RENDER-01, RENDER-02
**Success Criteria** (what must be TRUE):
  1. A user opening a seeded thread in the General board sees headers, bold, italic, fenced code, inline code, blockquotes, and lists rendered as styled terminal output
  2. Markdown links render with visible URL text; no broken wrapping or visible `\n` separator artifacts appear in the rendered output
  3. Resizing the terminal while a post is open re-flows the post without SGR-reset leaks or stuck styling from the prior width
**Plans**: 3 (02-01 MarkdownBody widget, 02-02 PostCard widget, 02-03 PostReader integration)
**UI hint**: yes

### Phase 3: Read-pointer correctness + thread-row enrichment
**Goal**: A user who reads every thread in a board sees the unread count drop to zero and stay there; thread rows show who started the thread, how recent it is, and how many posts it has.
**Depends on**: Phase 1, Phase 2
**Requirements**: LIST-01, LIST-02, LIST-03
**Success Criteria** (what must be TRUE):
  1. After reading every post in a board, the board-list unread count reaches zero and does not drift backward when the user re-reads older threads
  2. Returning to the board list from a thread always shows refreshed unread counts (no stale cache after a read-pointer advance)
  3. Each thread-list row displays the creator handle, total post count, and last-activity time in short form (`30s`, `5m`, `2h`, `3d`, `2w`, `6mo`, `2y`)
**Plans**: 4 (03-01 Boards GREATEST fix, 03-02 Threads.list_threads/2 unread annotation, 03-03 ListRow.render_with_metadata, 03-04 ThreadList+PostReader+App integration)
**UI hint**: yes

### Phase 4: Composer & thread creation end-to-end
**Goal**: A user can create a new thread from the thread-list view and reply from the post-reader view without the app crashing.
**Depends on**: Phase 1
**Requirements**: COMPOSE-01, COMPOSE-02, COMPOSE-03
**Success Criteria** (what must be TRUE):
  1. Pressing `[C]` from the thread list opens a new-thread composer with title and body fields; submitting returns the user to the thread list with the new thread visible at the top
  2. Pressing `[R]` from the post reader opens a reply composer; submitting returns the user to the thread with the new post visible
  3. No key press from the thread list leads to a crash or to an empty composer screen with no title field
**Plans**: TBD
**UI hint**: yes

### Phase 5: Terminal size gate
**Goal**: A user whose terminal is smaller than the agreed minimum sees a clear "terminal too small" message instead of garbled UI; resizing back restores the prior screen unchanged.
**Depends on**: Phase 1 (Phase 5 decision D-04 moves the gate from `ScreenFrame` to `App.view/1`, but still relies on Phase 1 chrome geometry for the 64×22 code-level threshold)
**Requirements**: FRAME-03
**Resolved decision:** Minimum terminal dimensions are 60×20 user-facing / 64×22 code-level (strict inequality). See `phases/05-terminal-size-gate/05-CONTEXT.md` D-01..D-13.
**Success Criteria** (what must be TRUE):
  1. Resizing the terminal below the agreed minimum replaces screen content with a clear "terminal too small" message showing current and required dimensions
  2. Resizing back above the threshold restores the exact prior screen — selected row, composer draft, scroll position — with no state loss
  3. Alt-screen takeover survives resize events without border fragments or stuck frame redraws
**Plans**: 2 plans
- [ ] 05-01-PLAN.md — SizeGate module + App.view/1 cond branch (creates the visible gate)
- [ ] 05-02-PLAN.md — Same-size guard + key-swallow guard + MultiLineInput preservation regression test (locks in state safety)
**UI hint**: yes

### Phase 6: Email verification toggle + resend
**Goal**: A sysop can flip email verification off site-wide via config; a user on the verify screen can resend their code with visible cooldown feedback.
**Depends on**: Phase 1 (consumes theme for resend feedback styling)
**Requirements**: VERIFY-01, VERIFY-02
**Success Criteria** (what must be TRUE):
  1. With `require_email_verification = true` (default), new registrations go through the verify flow and unconfirmed users are routed to the verify screen on login
  2. With `require_email_verification = false`, new registrations skip the verify step and existing `confirmed_at: nil` users gain access on their next login
  3. On the verify screen, the user sees a visible "Resend code" key hint; pressing it resends the code and, if still in cooldown, shows cooldown feedback instead of silently succeeding or spamming the DB
**Plans**: TBD
**UI hint**: yes

## Progress

**Execution Order:**
Phase 1 is a hard prerequisite for every other phase. Phase 2 precedes Phase 3 (the read-pointer UAT requires readable posts). Phases 4, 5, and 6 are independent once Phase 1 (and Phase 2 for UAT readability) has landed.

Recommended order: 1 → 2 → 3 → 4 → 5 → 6.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Widget foundation + theme + screen chrome | 4/4 | Complete | 2026-04-19 |
| 2. Markdown rendering correctness | 0/3 | Complete    | 2026-04-20 |
| 3. Read-pointer correctness + thread-row enrichment | 4/4 | Complete | 2026-04-20 |
| 4. Composer & thread creation end-to-end | 0/TBD | Not started | - |
| 5. Terminal size gate | 0/2 | Planned | - |
| 6. Email verification toggle + resend | 0/TBD | Not started | - |
