# Roadmap: Foglet BBS

## Overview

Foglet BBS is built in dependency order: identity first, then the domain data model, then the SSH/TUI interface that makes it usable, then the social layer that makes it compelling. Each phase leaves the system in a deployable state. The 14 phases map directly to the project's milestone structure — the dependency graph drives the ordering, not an artificial template.

## Phases

**Phase Numbering:**
- Integer phases (1–14): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Accounts & Identity** - Users and authentication exist; sysop can manage accounts from the command line (completed 2026-04-22)
- [ ] **Phase 2: Domain Core** - Boards, threads, and posts exist with full read/unread tracking
- [ ] **Phase 3: SSH Server & TUI** - Users can SSH in, browse boards, and post replies
- [ ] **Phase 4: Presence & Login Sequence** - Connecting feels like arriving somewhere — banner, news, who's online
- [ ] **Phase 5: Chat** - Two users can hold a real-time conversation in the lobby or a board room
- [ ] **Phase 6: DMs, Mentions & Notifications** - Users can message each other and get notified of activity directed at them
- [ ] **Phase 7: Moderation** - Mods can enforce community standards; sanctions take effect immediately
- [ ] **Phase 8: Sysop Administration In-TUI** - Sysop can run the entire BBS from inside their SSH session
- [ ] **Phase 9: Search, Upvotes & Social Polish** - Content is discoverable; social surface features complete the single-user experience
- [ ] **Phase 10: Email Notifications** - Opt-in email digests extend reach outside the terminal
- [ ] **Phase 11: Observability & Operations** - Sysop can operate and monitor the BBS confidently in production
- [ ] **Phase 12: Public Release Prep** - A stranger can install and run Foglet without asking the author
- [ ] **Phase 13: Go CLI Client** - The BBS is accessible via a native Go CLI with full feature parity
- [ ] **Phase 14: Door Games** - There is a reason to come back besides reading posts

## Phase Details

### Phase 1: Accounts & Identity
**Goal**: Users can exist in the system and sysops can create and manage accounts from the command line
**Depends on**: Nothing (M0 scaffold is complete)
**Requirements**: IDNT-01, IDNT-02, IDNT-03, IDNT-04, IDNT-05, IDNT-06, IDNT-07, IDNT-08
**Success Criteria** (what must be TRUE):
  1. A sysop can run `mix foglet.user.create` and create a working account with a unique, case-insensitive handle
  2. A sysop can run `mix foglet.user.promote` and assign a user the mod or sysop role
  3. A user account can be deleted and all posts rewritten to a tombstone user with no PII remaining
  4. A user can reset their password through the password reset flow
  5. SSH public keys can be registered to a user account (schema and storage layer, used in Phase 3)
**Plans**: 4 plans
Plans:
- [x] 01-01-PLAN.md — Foglet.Schema macro, 5 migrations (citext+enum, users, ssh_keys, user_tokens, configuration), Argon2 test config, Wave-0 test scaffolding
- [x] 01-02-PLAN.md — User + SSHKey + UserToken schemas with changesets; schema-level tests for IDNT-01, IDNT-02, IDNT-03, IDNT-04, IDNT-08
- [x] 01-03-PLAN.md — Foglet.Accounts context, Foglet.Config ETS cache, Application supervision wiring, tombstone + default config seeds
- [x] 01-04-PLAN.md — Mix tasks: foglet.user.create, foglet.user.promote, foglet.user.reset_password (IDNT-05, IDNT-06, IDNT-08)

### Phase 2: Domain Core
**Goal**: The BBS data model is complete — boards, threads, and posts exist with full read/unread tracking and concurrent message-number safety
**Depends on**: Phase 1
**Requirements**: BOARD-01, BOARD-02, BOARD-03, BOARD-04, BOARD-05, BOARD-06, BOARD-07, BOARD-08, BOARD-09, BOARD-10, BOARD-11, BOARD-12
**Success Criteria** (what must be TRUE):
  1. A user can create a thread and reply to it; edit history is preserved in `post_edits`
  2. Per-board message numbers are monotonically sequential under concurrent inserts (property test passes)
  3. Unread counts per user per board and per thread are queryable and accurate after reading
  4. Posts render Markdown to a terminal-friendly representation
  5. Threads can be soft-deleted, locked, stickied, and moved between boards without breaking message-number continuity
**Plans**: TBD

### Phase 3: SSH Server & TUI
**Goal**: Users can SSH into the BBS, authenticate, browse boards and threads, read posts, compose replies, and have their read position tracked — the core BBS loop is functional
**Depends on**: Phase 2
**Requirements**: SSH-01, SSH-02, SSH-03, SSH-04, SSH-05, SSH-06, SSH-07, SSH-08, SSH-09
**Success Criteria** (what must be TRUE):
  1. A user can SSH in with a password and reach the main menu; the host key survives a server restart
  2. A user can SSH in with a registered public key (no password prompt)
  3. A new visitor can register an account through the SSH guest flow without prior credentials
  4. If a user connects while already online, the old session is terminated with a notification and the new session continues
  5. A user can navigate boards, open threads, read posts, and compose a reply entirely via single-key menu navigation
  6. The TUI adapts its layout when the terminal is resized
**Plans**: 6 plans
Plans:
- [x] 03-01-PLAN.md — Raxol dep + Accounts.verify_email_code/register_pending_user + users.status migration + Wave-0 test stubs
- [x] 03-02-PLAN.md — Foglet.Sessions (Registry+Supervisor+Session with one-session-per-user replacement) + Foglet.SSH (Supervisor wraps :ssh.daemon/2 + KeyCB ssh_server_key_api) + application wiring
- [x] 03-03-PLAN.md — Foglet.TUI.App Raxol application + Login/Register/Verify screens (guest flow with registration-mode gating, invite codes, email verify code entry with 5-attempt cooldown)
- [x] 03-04-PLAN.md — BBS screens: MainMenu, BoardList, ThreadList, PostReader (with read-pointer flush SSH-09), PostComposer (Markdown/preview, Ctrl+S/Ctrl+C, max_post_length)
- [x] 03-05-PLAN.md — Gap closure: KeyBar spacer in all screens, remove duplicate title in main_menu, fix register_wizard init (registration crash blocker)
- [x] 03-06-PLAN.md — Gap closure: modal intercept guard in App key dispatch, command_result re-dispatcher (board loading), SSH resize event type fix
**UI hint**: yes

### Phase 4: Presence & Login Sequence
**Goal**: Connecting to the BBS feels like arriving somewhere — users see the ANSI banner, today's news, who's been online, and who is online right now
**Depends on**: Phase 3
**Requirements**: PRSNC-01, PRSNC-02, PRSNC-03, PRSNC-04, PRSNC-05, PRSNC-06
**Success Criteria** (what must be TRUE):
  1. Logging in shows the ANSI banner, then news bulletins, then the last-callers list in sequence
  2. The main menu shows who is currently online and updates live as users connect and disconnect
  3. A user can opt out of appearing in the last-callers list
  4. A sysop can edit the login banner and news bulletins from inside the TUI
  5. Classic `.ANS` CP437 art files render correctly in Unicode terminals
**Plans**: TBD
**UI hint**: yes

### Phase 5: Chat
**Goal**: Two users can hold a real-time synchronous conversation in the global lobby or in a per-board chat room
**Depends on**: Phase 4
**Requirements**: CHAT-01, CHAT-02, CHAT-03, CHAT-04, CHAT-05, CHAT-06
**Success Criteria** (what must be TRUE):
  1. A user can open the global chat lobby and exchange messages with another user in real time
  2. A user can join a per-board chat room; the room is created on demand and destroyed when empty
  3. Joining a room shows recent message scrollback from bounded persistent history
  4. The chat screen displays a roster pane alongside the message pane; roster updates live as users enter and leave
  5. A user can whisper to another user and leave a room using `/commands`
**Plans**: TBD
**UI hint**: yes

### Phase 6: DMs, Mentions & Notifications
**Goal**: Users can send direct messages to each other and receive real-time in-BBS notifications when mentioned, replied to, or sent a DM
**Depends on**: Phase 5
**Requirements**: SOCL-01, SOCL-02, SOCL-03, SOCL-04, SOCL-05
**Success Criteria** (what must be TRUE):
  1. A user can compose and send a DM to any other user; the recipient can read it from the main menu
  2. An `@handle` mention in a post or chat message triggers an in-BBS notification to the mentioned user
  3. A user receives a real-time notification (while online) when replied to, mentioned, or sent a DM
  4. The notification inbox shows an unread badge on the main menu and clears when the inbox is visited
**Plans**: TBD
**UI hint**: yes

### Phase 7: Moderation
**Goal**: Moderators can see reports, issue sanctions, and take editorial actions on content; sanctions take effect immediately across all paths
**Depends on**: Phase 6
**Requirements**: MODR-01, MODR-02, MODR-03, MODR-04, MODR-05, MODR-06, MODR-07, MODR-08
**Success Criteria** (what must be TRUE):
  1. A user can report a post or user from the TUI; the report appears in the mod queue
  2. A mod can warn, mute, temp-ban, or permanently ban a user; the sanction is enforced immediately in posting, chat, and DM paths
  3. A mod can delete a post, lock a thread, sticky a thread, or move a thread to another board
  4. All mod actions are written to the `mod_actions` audit log and visible to all mods
  5. New users are subject to configurable posting rate limits backed by ETS
**Plans**: TBD
**UI hint**: yes

### Phase 8: Sysop Administration In-TUI
**Goal**: A sysop can run the entire BBS — board structure, user accounts, runtime configuration, and announcements — without leaving their SSH session
**Depends on**: Phase 7
**Requirements**: SYSOP-01, SYSOP-02, SYSOP-03, SYSOP-04, SYSOP-05, SYSOP-06
**Success Criteria** (what must be TRUE):
  1. A sysop sees a role-gated sysop menu inside the TUI that non-sysops cannot access
  2. A sysop can create, edit, and delete categories and boards from inside the TUI
  3. A sysop can promote or demote a user and view account details from inside the TUI
  4. A sysop can change runtime configuration (backed by the `configuration` table) without redeploying
  5. A sysop can send a site-wide announcement that appears immediately in all active sessions
  6. Phoenix LiveDashboard is accessible at a sysop-only endpoint for production monitoring
**Plans**: TBD
**UI hint**: yes

### Phase 9: Search, Upvotes & Social Polish
**Goal**: Content is discoverable via full-text search; upvotes, oneliners, and user profiles complete the social surface of the BBS
**Depends on**: Phase 8
**Requirements**: SRCH-01, SRCH-02, SRCH-03, SOCL-06, SOCL-07, SOCL-08, SOCL-09, SOCL-10
**Success Criteria** (what must be TRUE):
  1. A user can search posts with full-text search scoped to a board or by author; results appear in a TUI search screen
  2. A user can upvote a post; the upvote count updates and toggles correctly
  3. A user can view another user's profile (handle, location, tagline, join date, post count, recent activity)
  4. A user can edit their own location and tagline from the profile screen
  5. Oneliners appear on the main menu; a user can post a new oneliner and see recent ones
**Plans**: TBD
**UI hint**: yes

### Phase 10: Email Notifications
**Goal**: Users who want to hear from the BBS outside the terminal can opt into email digests; sysops can disable email entirely
**Depends on**: Phase 9
**Requirements**: EMAIL-01, EMAIL-02, EMAIL-03, EMAIL-04, EMAIL-05
**Success Criteria** (what must be TRUE):
  1. A new user receives an email verification link on signup (Swoosh SMTP)
  2. A user can opt into daily or weekly email digests and receive them on schedule via Oban
  3. A user can unsubscribe from digests; the unsubscribe link works without being logged in
  4. A sysop can disable all outbound email via an environment variable without code changes
**Plans**: TBD

### Phase 11: Observability & Operations
**Goal**: A sysop can operate the BBS confidently in production — with metrics, error tracking, archival mode, and data export
**Depends on**: Phase 10
**Requirements**: OPS-01, OPS-02, OPS-03, OPS-04, OPS-05
**Success Criteria** (what must be TRUE):
  1. Telemetry events are emitted across domain modules and visible in LiveDashboard
  2. Sentry error reporting activates when `SENTRY_DSN` is set; no errors surface when the var is absent
  3. Running `mix foglet.archive` switches the instance to read-only mode; the login banner reflects this and posting is disabled
  4. A user can download their own posts and DMs as a data export from the TUI
  5. A sysop can export any user's data to fulfill an account-deletion request
**Plans**: TBD

### Phase 12: Public Release Prep
**Goal**: A stranger can install Foglet, stand up a BBS, and contribute to the project without asking the author
**Depends on**: Phase 11
**Requirements**: REL-01, REL-02, REL-03, REL-04, REL-05
**Success Criteria** (what must be TRUE):
  1. A license file is committed and the repository is public
  2. `docs/SYSOP.md` contains enough information to install, configure, and operate Foglet from scratch
  3. `docs/DEV.md` covers contributor onboarding; `CONTRIBUTING.md` and `CODE_OF_CONDUCT.md` are present
  4. The project has a version tagging scheme and a populated changelog
**Plans**: TBD

### Phase 13: Go CLI Client
**Goal**: The BBS is fully accessible via a native Go CLI client with feature parity to the SSH TUI, distributed as prebuilt binaries
**Depends on**: Phase 12
**Requirements**: CLI-01, CLI-02, CLI-03, CLI-04
**Success Criteria** (what must be TRUE):
  1. A user can authenticate the Go CLI against Foglet via Phoenix Channels token flow
  2. The Go CLI supports boards, threads, posts, chat, DMs, and notifications — all features available in the SSH TUI
  3. The client negotiates terminal capabilities (true color, unicode width) on connect and adapts its rendering
  4. Prebuilt binaries are available for each target platform via the project's release distribution
**Plans**: TBD

### Phase 14: Door Games
**Goal**: There is a reason to come back to the BBS besides reading posts — at least one playable game with persistent state and a leaderboard
**Depends on**: Phase 13
**Requirements**: GAME-01, GAME-02, GAME-03, GAME-04
**Success Criteria** (what must be TRUE):
  1. A user can launch a door game from the main menu; it takes over the screen and returns to the main menu on exit
  2. At least one complete game is playable (daily trivia, word puzzle, or Hunt-the-Wumpus clone)
  3. A user's game progress and scores persist across sessions
  4. The leaderboard is visible from the user's profile
**Plans**: TBD
**UI hint**: yes

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → ... → 14

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Accounts & Identity | 4/4 | Complete    | 2026-04-22 |
| 2. Domain Core | 4/4 | Complete | 2026-04-18 |
| 3. SSH Server & TUI | 4/6 | Gap closure in progress | 2026-04-18 |
| 4. Presence & Login Sequence | 0/TBD | Not started | - |
| 5. Chat | 0/TBD | Not started | - |
| 6. DMs, Mentions & Notifications | 0/TBD | Not started | - |
| 7. Moderation | 0/TBD | Not started | - |
| 8. Sysop Administration In-TUI | 0/TBD | Not started | - |
| 9. Search, Upvotes & Social Polish | 0/TBD | Not started | - |
| 10. Email Notifications | 0/TBD | Not started | - |
| 11. Observability & Operations | 0/TBD | Not started | - |
| 12. Public Release Prep | 0/TBD | Not started | - |
| 13. Go CLI Client | 0/TBD | Not started | - |
| 14. Door Games | 0/TBD | Not started | - |
