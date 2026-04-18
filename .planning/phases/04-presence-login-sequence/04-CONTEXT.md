# Phase 4: Presence & Login Sequence - Context

**Gathered:** 2026-04-18
**Status:** Ready for planning

<domain>
## Phase Boundary

Add Phoenix Presence tracking (who's online, live updates), the login sequence (ANSI banner →
news of the day → last callers → main menu), last-caller logging with opt-out, CP437-to-Unicode
translation for `.ANS` art files, a temporary sysop screen for banner/news editing, and the
infrastructure stub for user theme preferences.

This phase does NOT include: chat (Phase 5), notifications (Phase 6), full sysop admin menu (Phase 8),
theme picker UI or actual theme variants (Phase 9+).

</domain>

<decisions>
## Implementation Decisions

### Login Sequence Pacing (PRSNC-02)

- **D-01:** Login sequence is: ANSI banner → news of the day → last callers → main menu.
  **Every step waits for a keypress** before advancing. No auto-advance timers anywhere in the sequence.
- **D-02:** User-configurable skip — add a `preferences.skip_login_sequence` boolean field on the
  `users` table (or in the `preferences` JSONB column). Defaults to `false` (full sequence shown).
  When `true`, login goes straight to main menu. The user can toggle this from their profile settings.
- **D-03:** "Skip login sequence" preference is user-managed. No sysop override needed in Phase 4.

### Online List Display (PRSNC-01)

- **D-04:** Online list shows **handles only** — no location or idle status.
  Handle color indicates role: default color for regular users, a distinct color for mods,
  a distinct color for sysops. Exact color values are Claude's discretion; keep within the
  green-on-black default theme palette (e.g., bright green for sysop, yellow for mod, dim green
  for regular).
- **D-05:** Main menu shows the first N users that fit, with a key shortcut to expand to a full
  **scrollable online-users screen** (pageable list). The count is always visible (e.g.,
  `[W] Who's online (12)`). The scrollable screen allows navigating the full list.
- **D-06:** Live updates via **PubSub in-place** — Phoenix Presence diff events (`join`/`leave`)
  arrive via PubSub subscription in the Raxol app. Only the online-list section of the main menu
  model is updated and re-rendered. No full-screen refresh.

### Last Callers (PRSNC-04)

- **D-07:** `last_callers` row is written on **disconnect** — `connected_at` from Session start,
  `disconnected_at` from Session terminate. The `visible` flag is snapshotted from
  `users.show_in_last_callers` at connection time (DATA_MODEL.md §10 design).
- **D-08:** Login sequence shows the last callers list from
  `SELECT ... FROM last_callers WHERE visible = true ORDER BY connected_at DESC LIMIT N`.
  N is Claude's discretion (e.g., 20). Retention policy via `last_callers.retention_days` config key.

### CP437 Translation (PRSNC-05)

- **D-09:** `Foglet.CP437` module translates a full 256-code-point CP437 binary to a Unicode string.
  Owned as a pure function: `Foglet.CP437.to_unicode/1`. The full mapping is the canonical IBM CP437
  table. Characters with no Unicode equivalent map to the Unicode replacement character (U+FFFD).
- **D-10:** ANSI escape sequences embedded in `.ANS` files pass through untouched — CP437 translation
  applies only to printable code points, not to ESC sequences. Translation is applied at render time
  (not stored).

### Theme Stubs (PRSNC-06)

- **D-11:** Infrastructure only — no theme picker UI in Phase 4.
  Wire: (a) `themes.available` config key (seeded with `["default"]`); (b) `users.theme` field
  (already in DATA_MODEL.md §1 as `:string, default: "default"`); (c) load theme from `users.theme`
  into the Session state slot at login. TUI still renders green-on-black in Phase 4. Theme picker
  and actual alternative themes are Phase 9+ scope.

### Sysop Banner/News Editor (PRSNC-03)

- **D-12:** Banner editing: sysop provides a **filesystem path** to an `.ANS` or `.txt` file.
  The system reads the file contents and stores them in `login_banner.body` config key via
  `Foglet.Config`. No in-TUI text editor for banner content. The path is typed into a simple
  input field in the sysop screen.
- **D-13:** News bulletins: **add/remove titled bulletins**. Each bulletin has `title` + `body`,
  stored as the `news.bulletins` config key (array of maps per DATA_MODEL.md §11). Sysop can add
  a new bulletin (title + body input), delete an existing one by selection, or view the list.
  Edit-in-place is Claude's discretion.
- **D-14:** Sysop editor access: a **temporary standalone sysop screen** accessible from the main
  menu via a role-gated key (e.g., `[Y] Sysop`). Only visible to users with `sysop` role. Phase 8
  replaces this with the full admin menu — this screen is intentionally minimal (banner path, news
  CRUD only).

### Claude's Discretion

- Count of last callers displayed in login sequence (e.g., 20)
- Exact role colors within the green-on-black theme palette
- Number of users shown on main menu before the "Who's online (N)" expand key
- Retention policy cleanup job schedule for `last_callers` (Oban worker vs. on-read trim)
- Bulletin body format (plain text vs. Markdown — Phase 2 `Foglet.Markdown.render/1` available)
- Edit-in-place for existing bulletins (or delete + re-add)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Architecture

- `docs/ARCHITECTURE.md` §2 — Supervision tree; `Foglet.Presence` placement (line 66)
- `docs/ARCHITECTURE.md` §3 — Connection lifecycle §3 step 4: "Session runs login sequence: banner, news of the day, last callers, then main menu"
- `docs/ARCHITECTURE.md` §4 — Session layer; session state includes theme and terminal size
- `docs/ARCHITECTURE.md` §6 — Ephemeral state; Presence is CRDT-merged across nodes

### Data Model

- `docs/DATA_MODEL.md` §1 — `users` schema: `theme`, `show_in_last_callers` fields
- `docs/DATA_MODEL.md` §10 — `last_callers` schema, migration notes, `visible` snapshot semantics
- `docs/DATA_MODEL.md` §11 — `configuration` schema; `login_banner.body`, `news.bulletins`, `themes.available`, `last_callers.retention_days` config keys

### Requirements

- `.planning/REQUIREMENTS.md` PRSNC-01 through PRSNC-06 — acceptance criteria for this phase
- `.planning/ROADMAP.md` §Phase 4 — success criteria (5 items) and dependencies

### Prior Phases

- `.planning/phases/01-accounts-and-identity/01-CONTEXT.md` — Foglet.Config ETS cache; configuration table; user schema fields
- `.planning/phases/03-ssh-server-tui/03-CONTEXT.md` — Raxol TUI architecture, Session GenServer state, PubSub subscription pattern, D-18 (green-on-black theme hardcoded in Phase 3)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- `lib/foglet_bbs/config.ex` — `Foglet.Config.get!/1` ETS-backed accessor; `login_banner.body`, `news.bulletins`, `themes.available` keys read here
- `lib/foglet_bbs/tui/app.ex` — Raxol app; receives PubSub events; online-list state lives in model
- `lib/foglet_bbs/tui/widgets/modal.ex` — modal widget from Phase 3 (reuse for sysop confirmation prompts)
- `lib/foglet_bbs/accounts.ex` — `Foglet.Accounts.get_user!/1`; `users.show_in_last_callers` read here

### Established Patterns

- PubSub subscription pattern: Raxol app subscribes via `Phoenix.PubSub.subscribe/2` in `init/1`; events arrive in `update/2`
- Session GenServer holds session-scoped preferences; updated at login from `users.theme`
- `mix precommit` quality gate (format + Credo strict + test)
- Single-key shortcuts with key bar at bottom of each screen (D-19 from Phase 3)

### Integration Points

- `Foglet.Sessions.Session` — `on_mount` / `on_disconnect` hooks needed to write `last_callers` row and update Presence
- `Phoenix.Presence` — track via `Foglet.Presence` module; diff events broadcast to all subscribers
- `Foglet.Config` — banner and news stored here; sysop screen writes via `Foglet.Config.put!/2`

</code_context>

<specifics>
## Specific Ideas

- Role color convention: sysop = bright green (bold), mod = yellow, user = dim green — within the existing green-on-black palette, not clashing
- Pageable online list: `[W] Who's online (12)` on main menu; pressing `W` opens a full scrollable screen; same Raxol pattern as board list
- Login sequence keypress: each step shows a subtle `[any key to continue]` or `[ENTER]` prompt at the bottom — matches classic BBS expectations
- CP437 module: pure function, no process, no state — just a large lookup map or binary match

</specifics>

<deferred>
## Deferred Ideas

- Theme picker UI and actual alternative theme variants — Phase 9+ scope
- Full sysop admin menu (board CRUD, user management, etc.) — Phase 8 scope; Phase 4 sysop screen is a temporary slice
- In-TUI banner text editor (for sysops who want to compose banners without an external editor) — not planned; filesystem path model is the intended pattern
- Idle time display in online list (how long since last keypress) — not in Phase 4 scope

</deferred>

---

*Phase: 04-presence-login-sequence*
*Context gathered: 2026-04-18*
