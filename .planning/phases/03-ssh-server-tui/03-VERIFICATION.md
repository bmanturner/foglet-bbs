---
phase: 03-ssh-server-tui
verified: 2026-04-19T16:30:00Z
status: human_needed
score: 9/9
overrides_applied: 3
overrides:
  - must_have: "SSH public key callback delegates to Accounts.get_user_by_public_key/1"
    reason: "Audit #7 chose Option A: is_auth_key/3 always returns true and stashes the offered pubkey in PubkeyStash (ETS) keyed by {peer_ip, peer_port}. CLIHandler retrieves the key post-auth and calls Accounts.get_user_by_public_key/1 there instead. Same security outcome — key-to-user lookup still happens — but at a different stage of the connection lifecycle. All key_cb tests updated to assert Option A behavior."
    accepted_by: "bfturner"
    accepted_at: "2026-04-19T00:00:00Z"
  - must_have: "SSH daemon configured with ssh_cli: {Raxol.SSH.CLIHandler, [app_module: Foglet.TUI.App]}"
    reason: "Custom Foglet.SSH.CLIHandler was built during Audit #7 to colocate PubkeyStash lookup with session startup. It internally calls Raxol.Core.Runtime.Lifecycle.start_link(Foglet.TUI.App, ...) so the Raxol TUI app is still launched. supervisor_test.exs verifies ssh_cli: {Foglet.SSH.CLIHandler, []}. Functional outcome (Raxol TUI launched per SSH connection) is unchanged."
    accepted_by: "bfturner"
    accepted_at: "2026-04-19T00:00:00Z"
  - must_have: "SSH daemon configured with pwdfun for password authentication challenge"
    reason: "no_auth_needed: true bypasses SSH-level password auth entirely; all credential checking moves to the TUI Login screen (Accounts.authenticate_by_password/2 called from login.ex submit_login/1). SSH-02 (user can log in with username/password) is still delivered — the authentication just happens in the application layer rather than in the SSH handshake. supervisor_test.exs asserts pwdfun is NOT in daemon_opts."
    accepted_by: "bfturner"
    accepted_at: "2026-04-19T00:00:00Z"
human_verification:
  - test: "Connect to SSH daemon on port 2222 with a fresh client"
    expected: "Host key generated and persisted in priv/ssh/; TUI renders the Login screen; subsequent connections reuse the same host key (client does not see host-key-changed warning)"
    why_human: "Requires live SSH daemon and filesystem state across two connections — cannot verify host key generation/persistence without actually starting the daemon"
  - test: "Authenticate with an SSH public key (ssh -i ~/.ssh/id_rsa localhost -p 2222)"
    expected: "PubkeyStash receives the offered key; CLIHandler pops it and resolves the associated user; TUI shows the correct user handle in StatusBar"
    why_human: "Requires live SSH connection and a registered user with a stored public key — cannot verify the stash-pop-lookup chain without runtime state"
  - test: "Resize the terminal window during an active SSH session"
    expected: "TUI redraws to fit new dimensions; content no longer wraps or gets clipped at the old width; Raxol Rendering Engine dimensions updated (not just state.terminal_size)"
    why_human: "Event.new(:resize,...) routing through Raxol Dispatcher.handle_resize_event/2 can only be confirmed by observing the re-render — grep confirms the code path but not that the Rendering Engine actually receives and processes {:update_size,...}"
  - test: "Complete registration flow: connect → Login → R → Register screen → fill handle/email/password → verify email code → login"
    expected: "Each registration step renders without KeyError; verification code accepted; user status changes from :pending to :active; subsequent login succeeds and shows main menu"
    why_human: "End-to-end flow spanning multiple screens, DB state changes, and email code generation — requires live SMTP or test mailer and actual DB writes"
  - test: "Browse boards, open a thread, read posts, then press Q"
    expected: "boards_loaded/threads_loaded/posts_loaded async results all populate their respective screens (not stuck on 'Loading...'); Q on PostReader triggers flush_read_pointers which writes read pointers to the DB"
    why_human: "command_result re-dispatcher code path and DB flush are verified by unit tests, but the full chain (SSH keypress → Raxol → app.ex → Command.task → boards_loaded → BoardList renders) requires a live session to confirm end-to-end"
---

# Phase 03: SSH Server + TUI Verification Report

**Phase Goal:** Build the SSH server, session layer, and Raxol-based TUI application for Foglet BBS — including authentication screens (login, register, verify), five BBS screens (main menu, board list, thread list, post reader, post composer), and gap closures for visual layout, registration crash, modal intercept, async data loading, and SSH resize.
**Verified:** 2026-04-19T16:30:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | SSH daemon starts on configured port with host key and public key auth | VERIFIED (override) | `lib/foglet_bbs/ssh/supervisor.ex`: `no_auth_needed: true`, `key_cb: {Foglet.SSH.KeyCB, [...]}` in `daemon_opts/1`; host key dir via `ensure_system_dir!`; `config/config.exs` `:ssh_port, 2222`; `config/runtime.exs` `FOGLET_SSH_PORT` env var |
| 2 | One session per user enforced — new connection replaces old | VERIFIED | `lib/foglet_bbs/sessions/session.ex`: `handle_info(:replaced_by_new_session, state)` → `{:stop, :normal, state}`; `lib/foglet_bbs/sessions/supervisor.ex`: `start_session/1` sends `:replaced_by_new_session`, monitors old PID, waits for DOWN before promoting new session |
| 3 | Login screen authenticates with username + password | VERIFIED | `lib/foglet_bbs/tui/screens/login.ex`: `submit_login/1` calls `Accounts.authenticate_by_password/2`; suspended/unverified/active status branching; `spacer(flex: 1)` before KeyBar |
| 4 | Registration wizard collects required fields and creates pending user | VERIFIED | `lib/foglet_bbs/tui/screens/register.ex`: `handle_wizard_event/2` state machine; `register_pending_user` call; invite_code step for invite_only mode; `lib/foglet_bbs/accounts.ex` `register_pending_user/1` at line 66 |
| 5 | Email verification screen accepts 6-digit code and activates user | VERIFIED | `lib/foglet_bbs/tui/screens/verify.ex`: `@max_attempts 5`, `@code_length 6`, `cooldown_until`; `verify_email_code` call; `lib/foglet_bbs/accounts.ex` `verify_email_code/2` at line 179; `UserToken.build_verify_code/1` at line 69 |
| 6 | Five BBS screens render and respond to keys: MainMenu, BoardList, ThreadList, PostReader, PostComposer | VERIFIED | All 5 screen files exist with substantive render/1 and handle_key/2; `screen_module_for/1` in app.ex maps all 5; domain-adapter pattern for Boards/Threads/Posts modules |
| 7 | Post composer enforces max_post_length, supports Tab/Ctrl+S/Ctrl+C, shows quote preview | VERIFIED | `lib/foglet_bbs/tui/screens/post_composer.ex`: `@default_max_post_length 8192`; `ctrl_s`/`ctrl_c`/tab handlers; `quote_preview/1` and "Replying to" in render; seeds.exs: `"max_post_length", 8192` |
| 8 | KeyBar pinned to terminal bottom in all 9 screens; no duplicate title in Main Menu | VERIFIED | All 9 screen files contain `spacer(flex: 1)` before `KeyBar.render`; main_menu.ex has no standalone `text(" Foglet BBS ", style: [:bold])`; grep confirms absence of duplicate title line |
| 9 | Modal intercept, async data loading, and SSH resize all function correctly | VERIFIED | `app.ex` line 304: `if state.modal != nil` guard before screen dispatch; line 520: `do_update({:command_result, inner}, state)` re-dispatcher; `cli_handler.ex` line 163: `Event.new(:resize, %{width: width, height: height})`; 401 tests, 0 failures |

**Score:** 9/9 truths verified (3 with override for intentional architectural deviations)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/foglet_bbs/ssh/supervisor.ex` | SSH daemon opts, host key dir | VERIFIED | `daemon_opts/1` with `no_auth_needed`, `key_cb`, `ssh_cli`; `ensure_system_dir!`; `assert_safe_otp_version!` |
| `lib/foglet_bbs/ssh/key_cb.ex` | `:ssh_server_key_api` behaviour | VERIFIED (override) | Option A: always returns `true`, stashes pubkey in `Foglet.SSH.PubkeyStash` |
| `lib/foglet_bbs/ssh/cli_handler.ex` | Custom CLIHandler wiring Raxol TUI | VERIFIED (override) | Calls `Raxol.Core.Runtime.Lifecycle.start_link(Foglet.TUI.App, ...)`; `Event.new(:resize,...)` for window_change |
| `lib/foglet_bbs/sessions/session.ex` | GenServer with replacement protocol | VERIFIED | `handle_info(:replaced_by_new_session, ...)` → graceful stop |
| `lib/foglet_bbs/sessions/supervisor.ex` | DynamicSupervisor with replace logic | VERIFIED | `start_session/1`, `terminate_session/1`, `lookup_session/1`; monitor-and-wait replacement |
| `lib/foglet_bbs/tui/app.ex` | Raxol TEA application | VERIFIED | `use Raxol.Core.Runtime.Application`; `init/1`, `update/2`, `view/1`; modal intercept; command_result re-dispatcher; screen_module_for/1 maps 9 screens |
| `lib/foglet_bbs/tui/screens/login.ex` | Login screen with register navigation | VERIFIED | `submit_login/1`; `maybe_register/1` with fully initialised wizard (5 keys); `first_step_for_mode/1` |
| `lib/foglet_bbs/tui/screens/register.ex` | Registration wizard | VERIFIED | `handle_wizard_event/2` state machine; invite_code step; `register_pending_user` call |
| `lib/foglet_bbs/tui/screens/verify.ex` | Email verification screen | VERIFIED | `@max_attempts 5`; `@code_length 6`; `verify_email_code` call; cooldown |
| `lib/foglet_bbs/tui/screens/main_menu.ex` | Main menu (no duplicate title) | VERIFIED | No standalone bold title line; `spacer(flex: 1)` before KeyBar |
| `lib/foglet_bbs/tui/screens/board_list.ex` | Board list with async load | VERIFIED | `load_boards/1`; `selected_index` in screen_state |
| `lib/foglet_bbs/tui/screens/thread_list.ex` | Thread list with sticky sort | VERIFIED | `load_threads/2`; sticky-first sort |
| `lib/foglet_bbs/tui/screens/post_reader.ex` | Post reader with read pointer flush | VERIFIED | `load_posts/2`; `flush_read_pointers/2`; `:flush_read_pointers` command on Q |
| `lib/foglet_bbs/tui/screens/post_composer.ex` | Post composer with length enforcement | VERIFIED | `@default_max_post_length 8192`; Ctrl+S/C/Tab; `quote_preview/1` |
| `lib/foglet_bbs/tui/widgets/key_bar.ex` | KeyBar widget | VERIFIED | Exists and used in all 9 screens |
| `lib/foglet_bbs/tui/widgets/status_bar.ex` | StatusBar widget | VERIFIED | Renders title + handle + location |
| `lib/foglet_bbs/tui/widgets/modal.ex` | Modal widget | VERIFIED | Exists; modal intercept guard in app.ex |
| `priv/repo/migrations/20260418010000_add_status_to_users.exs` | `users.status` column migration | VERIFIED | File exists |
| `priv/repo/seeds.exs` | Seeds with registration_mode, max_post_length | VERIFIED | `"registration_mode", "open"`; `"invite_code_generators", "sysop_only"`; `"max_post_length", 8192` |
| `config/config.exs` | SSH port configuration | VERIFIED | `:ssh_port, 2222`; `:start_ssh_daemon, true` |
| `config/test.exs` | SSH daemon disabled in test | VERIFIED | `:start_ssh_daemon, false` |
| `config/runtime.exs` | `FOGLET_SSH_PORT` env var | VERIFIED | Line 24 |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `ssh/supervisor.ex daemon_opts` | Raxol TUI app launched | `ssh_cli: {Foglet.SSH.CLIHandler, []}` | VERIFIED (override) | Custom CLIHandler calls `Raxol.Core.Runtime.Lifecycle.start_link(Foglet.TUI.App, ...)` |
| `ssh/key_cb.ex is_auth_key/3` | pubkey stored for CLIHandler | `Foglet.SSH.PubkeyStash` ETS table | VERIFIED (override) | Option A: stash-based; CLIHandler pops stash for user lookup |
| `login.ex maybe_register/1` | `register.ex render/1` | `state.register_wizard` with 5 keys | VERIFIED | `register_wizard: %{mode: mode, step: first_step_for_mode(mode), data: %{}, error: nil, current_input: ""}` confirmed in login.ex |
| `app.ex do_update({:key,...})` | `global_key_handler/2` | modal intercept guard `state.modal != nil` | VERIFIED | Line 304 in app.ex: `if state.modal != nil` before screen dispatch |
| `app.ex do_update({:command_result, inner})` | `do_update(inner, state)` | re-dispatch | VERIFIED | Line 520 in app.ex; covers boards_loaded/threads_loaded/posts_loaded/read_pointers_flushed |
| `cli_handler.ex :window_change` | Raxol `handle_resize_event/2` | `Event.new(:resize, %{width: w, height: h})` | VERIFIED | Line 163 in cli_handler.ex; type `:resize` is in Raxol `system_event?/1` allowlist |
| `post_reader.ex Q key` | DB read pointer flush | `{:flush_read_pointers, ctx}` command | VERIFIED | `flush_read_pointers/2` calls `advance_board_read_pointer` and `advance_read_pointer` |
| `post_composer.ex Ctrl+S` | new post created | `Foglet.Posts.create_post/3` via domain adapter | VERIFIED | `do_submit/2` calls `posts_mod.create_post` |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `board_list.ex` | `ss.boards` | `boards_mod.list_subscribed_boards(user)` via `{:boards_loaded, boards}` async | Yes — real DB query in Foglet.Boards | FLOWING (verified via command_result re-dispatcher + unit tests) |
| `thread_list.ex` | `ss.threads` | `threads_mod.list_threads(board_id)` via `{:threads_loaded, threads}` async | Yes — real DB query in Foglet.Threads | FLOWING |
| `post_reader.ex` | `ss.posts` | `posts_mod.list_posts(thread_id)` via `{:posts_loaded, posts}` async | Yes — real DB query in Foglet.Posts | FLOWING |
| `post_composer.ex` | `ss.body_input_state` | `MultiLineInput` state; user keystrokes via `handle_compose_key` | Yes — user input | FLOWING |
| `login.ex` | form handle/password | `ss.form` updated by `handle_form_key` | Yes — user input | FLOWING |

### Behavioral Spot-Checks

Step 7b: Spot-checks on runnable code.

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Test suite passes | `mix test` (run during verification) | 1 property, 401 tests, 0 failures | PASS |
| No pending/skip stubs | `grep -r "@tag :pending" test/` | 0 matches | PASS |
| No Wave-0 placeholder patterns | `grep -r "wave_0_stub\|:not_implemented" lib/` | 0 matches | PASS |
| modal intercept guard present | `grep "state.modal != nil" lib/foglet_bbs/tui/app.ex` | Line 304 match | PASS |
| command_result re-dispatcher present | `grep "command_result" lib/foglet_bbs/tui/app.ex` | Line 520 match | PASS |
| Event.new(:resize) in cli_handler | `grep "Event.new(:resize" lib/foglet_bbs/ssh/cli_handler.ex` | Line 163 match | PASS |
| spacer(flex: 1) in all 9 screens | grep across all screen files | All 9 contain `spacer(flex: 1)` before KeyBar | PASS |
| seeds have required config values | `grep "max_post_length\|registration_mode" priv/repo/seeds.exs` | Both present with correct values | PASS |
| SSH not started in test env | `grep "start_ssh_daemon" config/test.exs` | `false` | PASS |
| SSH runtime behavior (live session) | N/A — requires running daemon | Cannot test without live daemon | SKIP — see Human Verification |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| SSH-01 | 03-02 | OTP SSH daemon starts on configured port with host key | SATISFIED | `ssh/supervisor.ex` daemon_opts; `config/config.exs` :ssh_port 2222; host key dir in `ensure_system_dir!` |
| SSH-02 | 03-02, 03-03 | User can log in with username and password via TUI | SATISFIED | `login.ex submit_login/1` calls `Accounts.authenticate_by_password/2`; status-aware branching |
| SSH-03 | 03-02 | SSH public key offered by client is stashed for user lookup | SATISFIED (override) | Option A: `key_cb.ex` stash + `cli_handler.ex` pop; `Accounts.get_user_by_public_key/1` called in CLIHandler |
| SSH-04 | 03-03, 03-05 | Registration flow collects required fields without crashing | SATISFIED | `register.ex` wizard; `login.ex maybe_register/1` with full 5-key init; register_test.exs passes |
| SSH-05 | 03-06 | Modal dismiss and async data loading work correctly in app routing | SATISFIED | Modal intercept guard line 304; command_result re-dispatcher line 520; 6 new tests in app_test.exs |
| SSH-06 | 03-06 | Terminal resize updates Raxol Rendering Engine dimensions | SATISFIED (code path) | `Event.new(:resize,...)` in cli_handler.ex; routing through Raxol Dispatcher confirmed; runtime behavior needs human test |
| SSH-07 | 03-04, 03-05 | All 9 TUI screens render KeyBar at bottom, no UI regressions | SATISFIED | spacer(flex: 1) in all 9 screens; 207 screen tests pass; no duplicate title |
| SSH-08 | 03-04 | Post composer enforces max_post_length, supports compose UX | SATISFIED | `post_composer.ex` @default_max_post_length 8192; Ctrl+S/C/Tab; quote preview |
| SSH-09 | 03-04 | Read pointers flushed to DB on PostReader exit | SATISFIED (code path) | `flush_read_pointers/2` in post_reader.ex; `{:flush_read_pointers, ctx}` command on Q; `do_update({:flush_read_pointers, ctx}, state)` in app.ex; runtime DB write needs human test |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `lib/foglet_bbs/tui/screens/new_thread.ex` | 386 | `"Thread creation coming soon — Phase 2 not yet wired."` | Info | Intentional fallback for Phase 2 `create_thread/3` absence; `new_thread.ex` is a Phase 3 bonus screen; `function_exported?` guard prevents crash; acceptable for current phase scope |

No blocker anti-patterns found. The "coming soon" message in `new_thread.ex` is guarded by `function_exported?(threads_mod, :create_thread, 3)` and is a documented Phase 2 dependency, not a stub for Phase 3 work.

### Human Verification Required

#### 1. SSH Daemon Host Key Persistence

**Test:** Start the application with `mix phx.server` (or `iex -S mix`), then connect twice with `ssh -p 2222 localhost`. Disconnect between connections.
**Expected:** First connection generates a host key in `priv/ssh/`; second connection reuses the same key (SSH client does not warn about host key change). TUI Login screen appears on both connections.
**Why human:** Host key generation and filesystem persistence require a live daemon. `priv/ssh/.gitkeep` confirms the directory structure is set up, but the actual key generation path through `ensure_system_dir!` and OTP `:ssh.daemon/2` can only be verified by observing runtime behavior.

#### 2. SSH Public Key Authentication Chain

**Test:** Register a user, add their SSH public key to the database, then connect with `ssh -i ~/.ssh/test_key -p 2222 localhost`.
**Expected:** `PubkeyStash` receives the offered key during SSH handshake; CLIHandler pops the stash entry and calls `Accounts.get_user_by_public_key/1`; the resolved user is set as `current_user` in TUI state; StatusBar shows the correct handle.
**Why human:** The stash-pop-lookup chain (`KeyCB.is_auth_key/3` → `PubkeyStash` → `CLIHandler.init/1`) spans the SSH handshake and process startup boundary. Unit tests cover each piece independently; the integration path requires a live SSH connection with a registered user.

#### 3. Terminal Resize Rendering Update

**Test:** Connect via SSH, then resize the terminal window (drag corner or `stty cols 120 rows 40`).
**Expected:** TUI redraws immediately to fill new dimensions. Content previously hidden by narrower width becomes visible. No content wraps at the old terminal width.
**Why human:** `Event.new(:resize,...)` routing through `Raxol.Dispatcher.handle_resize_event/2` sends `{:update_size,...}` to the Rendering Engine. The code path is verified (line 163 in cli_handler.ex), but confirming that the Rendering Engine actually re-layouts requires observing the visual result in a live terminal.

#### 4. End-to-End Registration + Verification + Login Flow

**Test:** Connect via SSH → Login screen → press R → fill handle, email, password through registration wizard → receive verification email → enter 6-digit code on Verify screen → log in with new credentials.
**Expected:** Each wizard step renders without KeyError; code accepted within 5 attempts; user status transitions from `:pending` to `:active`; subsequent login reaches Main Menu and shows the new handle in StatusBar.
**Why human:** This flow requires a live SMTP/mailer configuration for code delivery, actual DB writes through the full Ecto stack, and multi-screen navigation that cannot be simulated by unit tests alone.

#### 5. Board Browsing and Read Pointer Flush

**Test:** Log in as an existing user → press B from Main Menu → browse to a board → open a thread → read posts → press Q.
**Expected:** Board List populates (not stuck on "Loading..."), confirming `command_result` re-dispatcher works end-to-end; Thread List and Post Reader also populate; pressing Q writes read pointers to the DB (verify with a DB query: `SELECT * FROM user_thread_reads WHERE user_id = X`).
**Why human:** The `command_result` re-dispatcher is covered by unit tests (4 tests in app_test.exs), but confirming that the full async chain (SSH keypress → Raxol runtime → `Command.task` → `boards_loaded` → `do_update` → BoardList renders) works in a live session requires manual observation. The DB flush similarly needs a live session to confirm the `advance_read_pointer` calls actually commit.

---

## Architectural Deviations (Overrides Applied)

Three plan-level key-links deviate from their must_have specifications. All three are intentional, documented in plan summaries, and covered by updated tests. They are accepted as overrides rather than gaps.

### Deviation 1: KeyCB Option A (is_auth_key/3 always returns true)

Plan 03-02 required `is_auth_key/3` to call `Accounts.get_user_by_public_key/1` during the SSH handshake. The actual implementation uses "Option A": `is_auth_key/3` always returns `true` and stores the offered pubkey in `Foglet.SSH.PubkeyStash` (ETS). `Foglet.SSH.CLIHandler` retrieves the stashed key post-auth and calls `Accounts.get_user_by_public_key/1` there. The security outcome is equivalent — the key-to-user lookup still occurs before any TUI state is established. Documented in 03-02-SUMMARY.md as "Audit #7 fix".

### Deviation 2: Custom CLIHandler

Plan 03-02 required `ssh_cli: {Raxol.SSH.CLIHandler, [app_module: Foglet.TUI.App]}`. The actual implementation uses `{Foglet.SSH.CLIHandler, []}`, a custom handler that internally calls `Raxol.Core.Runtime.Lifecycle.start_link(Foglet.TUI.App, ...)`. The functional outcome (one Raxol TUI app instance per SSH connection) is identical. Documented in 03-02-SUMMARY.md.

### Deviation 3: pwdfun removed

Plan 03-02 required a `pwdfun` callback for SSH-level password authentication. The actual implementation removes it — `no_auth_needed: true` means all SSH connections are accepted at the transport level, and credential verification moves entirely to the TUI Login screen. SSH-02 (username/password login) is still delivered via `Accounts.authenticate_by_password/2` called from `login.ex`. Documented in 03-02-SUMMARY.md. `supervisor_test.exs` explicitly asserts `pwdfun` is NOT in `daemon_opts`.

---

_Verified: 2026-04-19T16:30:00Z_
_Verifier: Claude (gsd-verifier)_
