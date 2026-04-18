# Phase 3: SSH Server & TUI - Context

**Gathered:** 2026-04-18
**Status:** Ready for planning

<domain>
## Phase Boundary

Build the complete SSH access path and interactive TUI — the `:ssh` daemon (via Erlang's `:ssh`
application), authentication (password + pubkey + guest registration), session management
(`Foglet.Sessions`), and all TUI screens: login-or-register, main menu, board list, thread list,
post reader, and post composer. Read pointers advance as user reads.

This phase does NOT include: Phoenix Presence / online list (Phase 4), login banner / news sequence
(Phase 4), chat (Phase 5), DMs/notifications (Phase 6), or sysop TUI admin menus (Phase 8).

</domain>

<decisions>
## Implementation Decisions

### Registration Mode (SSH-04)

- **D-01:** All three registration modes are supported: `open` (anyone can register), `invite_only`
  (requires a valid invite code), and `sysop_approved` (account is created in pending state; sysop
  must approve before login is allowed). Mode is configurable at runtime.
- **D-02:** Default registration mode: `open` (lowest barrier for new sysops setting up a BBS).
- **D-03:** Registration mode stored in the runtime `configuration` table (keyed as
  `registration_mode`), read via `Foglet.Config` ETS cache. No redeploy required to change.
- **D-04:** Invite code generation: configurable setting (`invite_code_generators`), default
  `sysop_only`. Options: `sysop_only`, `mods`, `any_user`. Phase 3 implements sysop-only generation
  as the first-class path; the config key is wired but broader grant levels are later.
- **D-05:** Sysop-approved mode: Phase 3 persists accounts with `status: :pending` and blocks login
  until approved. The approval queue UI lives in Phase 8 (sysop admin TUI). Phase 10 sends the
  approval email notification. Phase 3 just persists the state and blocks login gracefully.
- **D-06:** When registration is disabled by the sysop, the `[R] Register` option is hidden from
  the login-or-register menu entirely. User only sees the login path.
- **D-07:** In sysop-approved mode, after completing registration the user is disconnected with
  a message: "Your account is pending sysop approval." Email notification is deferred to Phase 10.

### Email Verification (IDNT-02)

- **D-08:** Verification uses a **short alphanumeric code** (e.g. `XK7P2Q`), NOT a URL-based link.
  This fits the terminal-native identity — users type the code directly into the BBS session.
- **D-09:** Code-based verification **replaces** the URL token approach from Phase 1. The
  `user_tokens` table is repurposed to store these codes (context/sent_to fields remain; the
  `token` column holds the code value; the `token_type` is `email_verify`).
- **D-10:** Code expiry: 15 minutes. Max attempts: 5 before a cooldown. Rate limiting enforced
  at the Session level.
- **D-11:** In development: verification code is logged to the console (`Logger.info`). In
  production: the code is emailed (Phase 10 wires the mailer). The Session verification screen
  works identically in both environments — it just polls the DB for confirmation.
- **D-12:** The verification screen holds the SSH session open. After registration, the user
  sees a code-entry prompt and stays connected. Session advances to the main menu on successful
  verification.

### TUI Framework

- **D-13:** TUI framework: **Raxol v2.4.0**. Add `{:raxol, "~> 2.4.0"}` to `mix.exs` in Phase 3.
- **D-14:** SSH integration: We run our own `:ssh.daemon/1` (maintaining full control over host
  keys, auth callbacks, and the `Foglet.SSH.Supervisor`). Raxol's `CLIHandler` is plugged in as
  the `ssh_cli` option of the daemon call. Raxol handles all TUI rendering over the raw SSH I/O.
- **D-15:** Single Raxol application (`Foglet.TUI.App`) for the entire BBS experience.
  Mental model: `app.ex` is the conductor, `screens/*` are the scores, `widgets/*` are the
  instruments, `doors/*` are guest performers who take over the stage and return.
  `process_component/2` is used sparingly — only for genuinely independent sub-experiences
  (chat rooms, door games). Not for screens.
- **D-16:** State architecture:
  - **Domain state** → Postgres (Ecto queries from domain modules)
  - **Session-scoped identity/policy** → `Foglet.Sessions.Session` GenServer (user_id, handle,
    role, terminal size, rate-limit refs, grace window state)
  - **UI state** → Raxol model (`Foglet.TUI.App` model struct)
  - At session start: SSH daemon authenticates, starts or adopts a `Session` process, which starts
    the Raxol app via `Raxol.Core.RuntimeApplication` passing initial context. `init/1` populates
    the model from this context.
  - System events (board activity, notifications) arrive via PubSub subscriptions held by the
    Raxol app.
  - Session pings the Raxol app for heartbeat / `last_seen_at` updates (things only the Session
    knows about the underlying connection).
- **D-17:** File layout:
  ```
  lib/foglet_bbs/tui/
    app.ex             # Foglet.TUI.App — Raxol application entry point
    screens/           # One module per screen (login, main_menu, board_list, etc.)
    widgets/           # Reusable widget components (modal, status_bar, key_bar, etc.)
    doors/             # Future: independent sub-experiences (chat, games)
  ```
- **D-18:** Theming: Hardcode a single default theme in Phase 3 — classic green-on-black BBS look.
  Phase 4 adds `PRSNC-06` theme stubs. Full multi-theme support is a later milestone.
- **D-19:** Keyboard navigation: single-key shortcuts everywhere throughout the TUI (consistent
  with SSH-08). A key bar at the bottom of each screen shows available shortcuts for that view.
- **D-20:** Error/confirmation UX: Modal widget for errors and confirmations (e.g., "Discard
  draft?", "Auth failed"). The modal widget lives in `tui/widgets/modal.ex`.
- **D-21:** TUI testing in Phase 3: Unit test Raxol `update/2` and `view/1` functions directly.
  No real SSH harness or end-to-end session tests in Phase 3. ARCHITECTURE.md §12 describes
  the E2E SSH harness as a future goal.

### Guest Registration Flow (SSH-04)

- **D-22:** Guest entry: unauthenticated SSH connections immediately show a login-or-register
  menu: `[L] Login  [R] Register  [Q] Quit`. When registration is disabled (D-06), only
  `[L] Login  [Q] Quit` is shown.
- **D-23:** Registration wizard sequence:
  - `open` and `sysop_approved` modes: handle → email → password → verify code
  - `invite_only` mode: invite code → handle → email → password → verify code
  Invite code validation happens before the rest of the wizard so invalid codes abort early.
- **D-24:** SSH keys are NOT collected during registration. Deferred to in-TUI key management
  after first login (IDNT-04, Phase 3 scope for key storage only).

### Session Management (SSH-05)

- **D-25:** One session per user enforced via `Foglet.Sessions.Supervisor`. Reconnecting user
  replaces old session; old session receives a notification message then terminates.
  (Already locked in ARCHITECTURE.md and PROJECT.md — captured here for planner reference.)

### Post Composer UX (SSH-07)

- **D-26:** Composer uses Raxol's built-in multi-line scrollable text input widget. No external
  editor spawning, no line-by-line BBS-style entry.
- **D-27:** Composer screen layout (full-screen):
  - Header: thread title + "Replying to: @handle"
  - Quote context: first ~5 lines of the reply-to post shown dimmed above the text area
    (when replying; omitted for new threads)
  - Body: scrollable Raxol text area widget
  - Key bar: `[Ctrl+S] Send  [Ctrl+C] Cancel  [Tab] Preview`
- **D-28:** Tab toggles between raw Markdown edit mode and rendered ANSI preview mode in the
  same composer screen.
- **D-29:** Submit key: `Ctrl+S` sends the post.
- **D-30:** Cancel: `Ctrl+C` cancels immediately with no confirmation prompt (BBS-traditional).
- **D-31:** Maximum post length: configurable via runtime config (`max_post_length`), default
  8192 characters.

### Claude's Discretion

- SSH host key storage: `priv/ssh/` directory, persisted across deploys (per ARCHITECTURE.md §7).
  Key generation on first boot if not present.
- Session reconnect grace window: ARCHITECTURE.md §4 mentions a short grace window.
  Implement with a reasonable default (e.g., 30 seconds) without user configuration in Phase 3.
- Read pointer advance: advance board and thread read pointers as the user pages through posts
  (on each page-down / next-post key), flushing to Postgres on screen transition.
- Board list view: show subscribed boards with unread counts. Unread count queries from Phase 2.
- Thread list: show threads in a board, newest-activity-first, with unread post counts.
- Post reader: page through posts with prev/next keys. Display ANSI-rendered Markdown.
- Navigation between screens: handled via Raxol model `current_screen` routing inside `app.ex`.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Architecture

- `docs/ARCHITECTURE.md` §2 — Supervision tree (target shape; SSH.Supervisor placement)
- `docs/ARCHITECTURE.md` §3 — SSH connection lifecycle (auth → Session start → TUI loop)
- `docs/ARCHITECTURE.md` §4 — Session layer (state, PubSub, one-session rule)
- `docs/ARCHITECTURE.md` §7 — SSH layer specifics (host key, PTY, ANSI art, terminal size)
- `docs/ARCHITECTURE.md` §9 — Account creation flow (SSH guest flow, two paths)
- `docs/ARCHITECTURE.md` §12 — Testing strategy (E2E SSH harness as future goal)

### Requirements

- `.planning/REQUIREMENTS.md` SSH-01 through SSH-09 — acceptance criteria for this phase
- `.planning/ROADMAP.md` §Phase 3 — success criteria (6 items) and dependencies

### Prior Phases

- `.planning/phases/01-accounts-and-identity/01-CONTEXT.md` — user_tokens schema,
  Foglet.Accounts context interface, Foglet.Config ETS cache
- `.planning/phases/02-domain-core/02-CONTEXT.md` — domain APIs Phase 3 consumes
  (list_boards, list_threads, create_post, Markdown.render, unread_counts)

### Raxol Framework

- `https://github.com/DROOdotFOO/raxol` — Raxol v2.4.0 source and documentation.
  Key areas: CLIHandler (ssh_cli integration), Raxol.Core.RuntimeApplication (app startup),
  process_component/2 (isolated sub-processes), built-in widget primitives.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- `lib/foglet_bbs/accounts.ex` — `Foglet.Accounts`: `get_user_by_email/1`,
  `verify_password/2`, `create_user/1`. SSH daemon's auth callbacks use these.
- `lib/foglet_bbs/accounts/ssh_key.ex` — `Foglet.Accounts.SSHKey` schema. Pubkey auth
  matches incoming keys against rows here.
- `lib/foglet_bbs/config.ex` — `Foglet.Config` ETS cache. Registration mode and
  max_post_length read from here at runtime.
- `lib/foglet_bbs/schema.ex` — `Foglet.Schema` macro (UUID v7, utc_datetime_usec). All new
  schemas use `use Foglet.Schema`.
- `lib/foglet_bbs/application.ex` — OTP supervision tree. `Foglet.SSH.Supervisor` and
  `Foglet.Sessions.Supervisor` are added here.
- `lib/foglet_bbs/repo.ex` — `Foglet.Repo` for all DB operations.

### Established Patterns

- All schemas: `use Foglet.Schema` (UUID v7, utc_datetime_usec)
- Tests mirror lib: `test/foglet_bbs/tui/`, `test/foglet_bbs/sessions/`
- `mix precommit` is the quality gate (format + Credo strict + test)
- DynamicSupervisor + named child spec pattern (Boards.Supervisor from Phase 2)

### Integration Points

- Phase 3 consumes (from Phase 2): `Foglet.Boards.list_boards/0`,
  `Foglet.Threads.list_threads/1`, `Foglet.Posts.create_post/2`,
  `Foglet.Posts.create_reply/3`, `Foglet.Markdown.render/1`, `Foglet.Boards.unread_counts/1`
- Phase 4 will consume: `Foglet.Sessions.Session` for Presence tracking and online list
- The `user_tokens` table from Phase 1 is repurposed for alphanumeric email verification
  codes (D-09). `token_type = :email_verify`, `token` column holds the code string.

</code_context>

<specifics>
## Specific Ideas

- Raxol mental model for this BBS: "app.ex is the conductor. screens/* are the scores.
  widgets/* are the instruments. doors/* are guest performers who come on stage, do their
  thing, and leave." — verbatim from user.
- State flow articulated by user: "Domain state lives in Postgres. Session-scoped identity
  and policy lives in Session GenServer. UI State lives in Raxol model. At session start SSH
  daemon auths a user and starts or adopts a Foglet.Sessions.Session process for that user.
  The Session process then starts a Raxol app, passing initial context into
  Raxol.Core.RuntimeApplication, and Raxol app's init/1 populates the model from this
  context. UI interactions happen inside the Raxol model, Domain actions go through domain
  modules directly, System events reach the Raxol app via its own PubSub subscriptions. The
  Session needs to reach the Raxol app for things only the session knows about such as
  heartbeat / last seen at pings."

</specifics>

<deferred>
## Deferred Ideas

- Browse-as-guest (read-only access without an account) — not in Phase 3 requirements scope
- SSH key collection during registration — deferred to in-TUI key management after login (IDNT-04)
- Full multi-theme support — Phase 4 adds stubs (PRSNC-06); full themes are a later milestone
- E2E SSH harness for integration testing — noted in ARCHITECTURE.md §12; not Phase 3 scope
- Sysop approval queue UI — Phase 8 scope; Phase 3 only persists pending state
- Email notification on approval (sysop-approved mode) — Phase 10 scope (mailer wired there)
- Invite code generation by mods or any user — config key wired, full grant levels are later

</deferred>

---

*Phase: 03-ssh-server-tui*
*Context gathered: 2026-04-18*
