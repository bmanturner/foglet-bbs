# Requirements — v1.0.1 Phase 03 Polish

**Workstream:** `phase-03-polish`
**Parent milestone:** v1.0 (Foglet BBS — Milestones 1–14)
**Scope posture:** Harden what Phase 03 shipped. No new domain features.
**Research:** `.planning/workstreams/phase-03-polish/research/SUMMARY.md` (HIGH confidence, zero new deps)
**Folded seeds:** SEED-002 (`.planning/seeds/SEED-002-email-verification-ux.md`)

## Locked Decisions

| Decision | Choice | Source |
|----------|--------|--------|
| Retroactive bypass when `require_email_verification` flips to false | **Existing `confirmed_at: nil` users gain access on next login** | Matches "toggle off = don't care anymore"; no migration needed |
| Widget style | **Function-form only** (no `use Raxol.UI.Components.Base.Component`) | Raxol modern block-macro DSL; `memory/feedback_raxol_modern_dsl.md` |
| Pre-rendering markdown at post-save | **Rejected** — render at view time with per-screen memoization | Terminal width varies per session |
| Raxol `ThemeManager` | **Rejected** for v1.0.1 — use `Foglet.TUI.Theme` struct | GenServer couples to rejected Raxol components |

## Open Decisions (deferred to phase discussion)

| Decision | Status | Deferred to |
|----------|--------|-------------|
| Minimum terminal dimensions (research: 60×20 floor vs 80×24 comfort) | **Open** | Phase 5 discuss/plan |

## v1.0.1 Requirements

### RENDER — Markdown posts display correctly

- [ ] **RENDER-01**: Markdown posts (headers, bold, italic, lists, fenced code, inline code, blockquotes, links) render as formatted terminal output in the PostReader screen; verified against the seeded threads in the General board.
- [ ] **RENDER-02**: Markdown rendering handles terminal width changes without SGR-reset leaks, broken wrapping, or visible `\n` separator artifacts.

### FRAME — Consistent screen chrome across every screen

- [ ] **FRAME-01**: A reusable `ScreenFrame` widget wraps every screen (outer bordered box → column → StatusBar → divider → content → KeyBar); every screen in `lib/foglet_bbs/tui/screens/` renders through it.
- [ ] **FRAME-02**: A reusable `StatusBar` widget is the first content row inside `ScreenFrame`, showing page title and logged-in user handle (handle shown only when authenticated).
- [ ] **FRAME-03**: Below an agreed minimum terminal dimension (determined during Phase 5 discussion), the ScreenFrame renders a "terminal too small" message in place of screen content; resizing back above the threshold restores the prior screen state without reset.

### THEME — Consistent visual treatment

- [ ] **THEME-01**: A `Foglet.TUI.Theme` struct resolved once per session (in `CLIHandler.build_context/3`) is consistently applied to the border box, status bar, key bar, and content text across every screen. No hardcoded `fg: :green` / per-screen ad-hoc colors remain.

### LIST — Correct unread tracking + richer thread rows

- [ ] **LIST-01**: Board list unread count decrements monotonically; reaches zero after the user has read every post in a board; does not drift backward when re-reading older threads.
- [ ] **LIST-02**: Board list refreshes its data on every return from a child screen (no stale cache behavior).
- [ ] **LIST-03**: Thread list rows display creator handle, post count, and last-activity time ago in short form (`30s`, `5m`, `2h`, `3d`, `2w`, `6mo`, `2y`).
- [ ] **LIST-04**: A shared `SelectionList` widget backs board-list, thread-list, and any new-thread list flows; each list supplies a `row_renderer` prop.

### COMPOSE — Thread creation and reply actually work

- [x] **COMPOSE-01**: Pressing `[C]` from the thread list view routes to a NewThread flow with title + body fields (uses existing `new_thread.ex`); submit creates the thread and returns the user to the thread list with the new thread visible at the top.
- [x] **COMPOSE-02**: Pressing `[R]` from PostReader opens a reply composer; submit creates the post and returns the user to the thread with the new post visible.
- [x] **COMPOSE-03**: The broken `current_thread: nil → :post_composer` branch in `thread_list.ex` that causes the crash-on-compose is removed.

### VERIFY — Email verification toggle + resend

- [ ] **VERIFY-01**: A sysop-settable `Foglet.Config` key `require_email_verification` (default `true`) is checked during registration and login; when `false`, new registrations skip the verification step and existing `confirmed_at: nil` users gain access on next login. See Locked Decisions for retroactive policy.
- [ ] **VERIFY-02**: The Verify screen shows a visible "Resend code" affordance (key hint) wired to the existing `{:resend}` event, respecting cooldown with visible feedback to the user.

### WIDGET — Foundation layer under everything above

- [ ] **WIDGET-01**: A `Foglet.TUI.Widgets.*` namespace exposes function-form widgets backing the items above: `Chrome.ScreenFrame`, `Chrome.StatusBar`, `List.SelectionList`, `List.ListRow`, `Post.MarkdownBody`, `Post.PostCard`. All use Raxol's modern block-macro DSL. No legacy function-form, no `use Raxol.UI.Components.Base.Component`.
- [ ] **WIDGET-02**: A `Foglet.TimeAgo` stdlib module provides the short-form relative-time formatter used by LIST-03. No new dependencies.

---

## Future Requirements (Deferred)

- Full Raxol `ThemeManager` integration with runtime theme switching — deferred to Milestone 4 ("theme stub")
- Live unread-count PubSub refresh (while a user is on BoardList, updates when other users post) — deferred to Milestone 4 (Presence)
- Live user-count / clock / session-time in status bar — deferred to Milestone 4
- Sysop in-TUI toggle screen for `require_email_verification` — Milestone 8 (`Sysop Administration In-TUI`); v1.0.1 sets via `mix foglet.config.set` or `Foglet.Config.put!/3`
- Syntax highlighting inside fenced code blocks — deferred (Makeup integration)
- OSC-8 clickable hyperlinks — deferred (inconsistent terminal support)
- GFM tables in posts, footnotes, task lists — deferred (unrenderable at narrow widths)
- Pre-rendered markdown at post-save (`posts.body_rendered` column) — deferred (session-width-dependent)
- Actual SMTP email delivery for verification/resend — Milestone 10 (Swoosh re-enable)
- Webhook notification delivery (SEED-001) — Phase 10 or integrations milestone

## Out of Scope

- Any new domain feature (these belong to Milestones 4–14)
- Any `PROJECT.md` product-identity changes (polish doesn't change what Foglet is)
- `Timex` / `ex_cldr_dates_times` — explicitly rejected; custom `Foglet.TimeAgo` instead
- Storing markdown render output to the database — stays at view time
- Reworking the SSH alt-screen / resize pipeline beyond the too-small gate — prior commits already hardened it

## Traceability

| REQ | Phase |
|-----|-------|
| RENDER-01 | Phase 2 |
| RENDER-02 | Phase 2 |
| FRAME-01 | Phase 1 |
| FRAME-02 | Phase 1 |
| FRAME-03 | Phase 5 |
| THEME-01 | Phase 1 |
| LIST-01 | Phase 3 |
| LIST-02 | Phase 3 |
| LIST-03 | Phase 3 |
| LIST-04 | Phase 1 |
| COMPOSE-01 | Phase 4 |
| COMPOSE-02 | Phase 4 |
| COMPOSE-03 | Phase 4 |
| VERIFY-01 | Phase 6 |
| VERIFY-02 | Phase 6 |
| WIDGET-01 | Phase 1 |
| WIDGET-02 | Phase 1 |

**Total: 17 requirements across 7 categories.**
