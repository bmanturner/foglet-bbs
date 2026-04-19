---
phase: 03-ssh-server-tui
verified: 2026-04-19T18:30:00Z
status: human_needed
score: 14/14
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
re_verification:
  previous_status: human_needed
  previous_score: 9/9
  gaps_closed: []
  plan07_truths_added: 5
  new_score: 14/14
  regressions: []
human_verification:
  - test: "Connect to SSH daemon on port 2222 with a fresh client"
    expected: "Host key generated and persisted in priv/ssh/; TUI renders the Login screen; subsequent connections reuse the same host key (client does not see host-key-changed warning)"
    why_human: "Requires live SSH daemon and filesystem state across two connections — cannot verify host key generation/persistence without actually starting the daemon"
  - test: "Authenticate with an SSH public key (ssh -i ~/.ssh/id_rsa localhost -p 2222)"
    expected: "PubkeyStash receives the offered key; CLIHandler pops it and resolves the associated user; TUI shows the correct user handle in StatusBar"
    why_human: "Requires live SSH connection and a registered user with a stored public key — cannot verify the stash-pop-lookup chain without runtime state"
  - test: "Resize the terminal window during an active SSH session"
    expected: "TUI redraws to fit new dimensions; content no longer wraps or gets clipped at the old width; Raxol Rendering Engine dimensions updated"
    why_human: "Event.new(:resize,...) routing through Raxol Dispatcher.handle_resize_event/2 can only be confirmed by observing the re-render — grep confirms the code path but not that the Rendering Engine actually receives and processes {:update_size,...}"
  - test: "Complete registration flow: connect → Login → R → Register screen → fill handle/email/password → verify email code → login"
    expected: "Each registration step renders without KeyError; verification code accepted; user status changes from :pending to :active; subsequent login succeeds and shows main menu"
    why_human: "End-to-end flow spanning multiple screens, DB state changes, and email code generation — requires live SMTP or test mailer and actual DB writes"
  - test: "Browse boards, open a thread, read posts, then press Q"
    expected: "boards_loaded/threads_loaded/posts_loaded async results all populate their respective screens (not stuck on 'Loading...'); Q on PostReader triggers flush_read_pointers which writes read pointers to the DB"
    why_human: "command_result re-dispatcher code path and DB flush are verified by unit tests, but the full chain (SSH keypress → Raxol → app.ex → Command.task → boards_loaded → BoardList renders) requires a live session to confirm end-to-end"
  - test: "Dismiss pending-account modal and confirm return to Login landing menu"
    expected: "After logging in with a :pending user account, the modal shows a wrapped message (no line >50 chars), key hint reads '[Enter] OK' only (no 'Esc'), and pressing Enter returns to the [L]/[R]/[Q] login menu — not the login form"
    why_human: "screen_state: %{} clearing is verified by unit test, but confirming the visual result (modal body fits 80 cols, dismiss actually routes back to landing menu) requires a live session"
  - test: "NewThread composer: Tab on body field cycles between Edit and Preview mode; Preview shows formatted Markdown"
    expected: "With body focused, Tab shows formatted post preview (bold/italic/underline rendered, not raw **text** or ANSI escapes); Tab again returns to the editable body; Tab on title field advances focus, not mode"
    why_human: "render_markdown_tuples/1 and Markdown.render/1 are unit-tested, but the visual rendering in the Raxol TUI (styled text actually appears styled) requires a live SSH session to confirm"
---

# Phase 03: SSH Server + TUI Verification Report (Re-verification after Plan 07)

**Phase Goal:** Users can SSH into the BBS, authenticate, browse boards and threads, read posts, compose replies, and have their read position tracked — the core BBS loop is functional
**Verified:** 2026-04-19T18:30:00Z
**Status:** human_needed
**Re-verification:** Yes — after Plan 07 gap closure (5 UAT gaps: KeyBar pinning, StatusBar divider, pending modal, NewThread preview mode, Markdown tuple rendering)

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | SSH daemon starts on configured port with host key and public key auth | VERIFIED (override) | `lib/foglet_bbs/ssh/supervisor.ex`: `no_auth_needed: true`, `key_cb: {Foglet.SSH.KeyCB, [...]}` in `daemon_opts/1`; host key dir via `ensure_system_dir!`; `config/config.exs` `:ssh_port, 2222` |
| 2 | One session per user enforced — new connection replaces old | VERIFIED | `lib/foglet_bbs/sessions/supervisor.ex`: `start_session/1` sends `:replaced_by_new_session`, monitors old PID, waits for DOWN before promoting new session |
| 3 | Login screen authenticates with username + password | VERIFIED | `lib/foglet_bbs/tui/screens/login.ex` line 275: `submit_login/1` calls `Accounts.authenticate_by_password/2`; pending/suspended clauses both set `modal: modal, screen_state: %{}` (lines 301, 305) |
| 4 | Registration wizard collects required fields and creates pending user | VERIFIED | `lib/foglet_bbs/tui/screens/register.ex`: `handle_wizard_event/2` state machine; `register_pending_user` call; invite_code step for invite_only mode |
| 5 | Email verification screen accepts 6-digit code and activates user | VERIFIED | `lib/foglet_bbs/tui/screens/verify.ex`: `@max_attempts 5`, `@code_length 6`, `cooldown_until`; `verify_email_code` call |
| 6 | Five BBS screens render and respond to keys: MainMenu, BoardList, ThreadList, PostReader, PostComposer | VERIFIED | All 5 screen files exist with substantive render/1 and handle_key/2; `screen_module_for/1` in app.ex maps all 5; domain-adapter pattern |
| 7 | Post composer enforces max_post_length, supports Tab/Ctrl+S/Ctrl+C, shows quote preview | VERIFIED | `lib/foglet_bbs/tui/screens/post_composer.ex`: `@default_max_post_length 8192`; `ctrl_s`/`ctrl_c`/tab handlers; `render_markdown_tuples` for preview branch |
| 8 | KeyBar is pinned to terminal bottom in all 9 screens via `justify_content: :space_between`; no `spacer(flex: 1)` remains | VERIFIED | `grep "justify_content: :space_between" lib/foglet_bbs/tui/screens/*.ex` returns 10 matches (new_thread.ex has 2 render functions); `grep "spacer(flex" lib/foglet_bbs/tui/screens/*.ex` returns 0 matches |
| 9 | StatusBar divider is present on Main Menu immediately after StatusBar.render | VERIFIED | `lib/foglet_bbs/tui/screens/main_menu.ex` lines 23-24: `StatusBar.render(...)` immediately followed by `divider()` |
| 10 | Pending/suspended modal wraps message at 50 chars; key hint reads '[Enter] OK' only; dismissing returns to Login landing menu | VERIFIED | `lib/foglet_bbs/tui/widgets/modal.ex`: `@wrap_width 50`, `word_wrap/2`, `key_hint_for(_) -> "[Enter] OK"`; `login.ex` both modal clauses include `screen_state: %{}`; Tests A-E pass |
| 11 | NewThread composer supports Tab to toggle edit/preview when focused on body field | VERIFIED | `lib/foglet_bbs/tui/screens/new_thread.ex` line 316-325: `handle_compose_key` Tab clause: `if ss.focused == :body -> toggle mode; else -> advance focus`; `mode: :edit` in `init_screen_state/1` line 53; Tests 8-10 pass |
| 12 | Markdown.render/1 returns `[{String.t(), style_atom}]` tuples (not ANSI strings) | VERIFIED | `lib/foglet_bbs/markdown.ex` line 55: `@spec render(String.t()) :: rendered()`; spot-check: `render("**hello**")` → `[{"hello", :bold}, {"\n", :plain}]`; ANSI injection returns only `:plain` tuples |
| 13 | PostComposer and PostReader display formatted Markdown via render_markdown_tuples/1 | VERIFIED | `post_composer.ex` line 52: `:preview` branch calls `render_markdown_tuples(render_preview(state, draft))`; `post_reader.ex` line 187: `render_post_items/4` calls `render_markdown_tuples(markdown_mod.render(body))` |
| 14 | Modal intercept, async data loading, and SSH resize all function correctly | VERIFIED | `app.ex`: modal intercept guard, `command_result` re-dispatcher; `cli_handler.ex` line 163: `Event.new(:resize,...)`; 409 tests, 0 failures |

**Score:** 14/14 truths verified (3 with override for intentional architectural deviations)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/foglet_bbs/ssh/supervisor.ex` | SSH daemon opts, host key dir | VERIFIED | `daemon_opts/1` with `no_auth_needed`, `key_cb`, `ssh_cli`; `ensure_system_dir!` |
| `lib/foglet_bbs/ssh/key_cb.ex` | `:ssh_server_key_api` behaviour | VERIFIED (override) | Option A: always returns `true`, stashes pubkey in `Foglet.SSH.PubkeyStash` |
| `lib/foglet_bbs/ssh/cli_handler.ex` | Custom CLIHandler wiring Raxol TUI | VERIFIED (override) | Calls `Raxol.Core.Runtime.Lifecycle.start_link(Foglet.TUI.App, ...)`; `Event.new(:resize,...)` for window_change |
| `lib/foglet_bbs/sessions/session.ex` | GenServer with replacement protocol | VERIFIED | `handle_info(:replaced_by_new_session, ...)` → graceful stop |
| `lib/foglet_bbs/sessions/supervisor.ex` | DynamicSupervisor with replace logic | VERIFIED | `start_session/1`, `terminate_session/1`, `lookup_session/1`; monitor-and-wait replacement |
| `lib/foglet_bbs/tui/app.ex` | Raxol TEA application | VERIFIED | `use Raxol.Core.Runtime.Application`; modal intercept; command_result re-dispatcher; screen_module_for/1 maps 9 screens |
| `lib/foglet_bbs/tui/screens/login.ex` | Login with modal clear on pending/suspended | VERIFIED | `submit_login/1` pending/suspended clauses both set `screen_state: %{}` alongside `modal:` (lines 301, 305) |
| `lib/foglet_bbs/tui/screens/register.ex` | Registration wizard | VERIFIED | `handle_wizard_event/2` state machine; `justify_content: :space_between` layout |
| `lib/foglet_bbs/tui/screens/verify.ex` | Email verification screen | VERIFIED | `@max_attempts 5`; `@code_length 6`; `justify_content: :space_between` layout |
| `lib/foglet_bbs/tui/screens/main_menu.ex` | Main menu with StatusBar divider | VERIFIED | `divider()` immediately after `StatusBar.render(...)`; `justify_content: :space_between` layout |
| `lib/foglet_bbs/tui/screens/board_list.ex` | Board list with async load | VERIFIED | `load_boards/1`; `justify_content: :space_between` layout |
| `lib/foglet_bbs/tui/screens/thread_list.ex` | Thread list with sticky sort | VERIFIED | `load_threads/2`; sticky-first sort; `justify_content: :space_between` layout |
| `lib/foglet_bbs/tui/screens/post_reader.ex` | Post reader with read pointer flush + Markdown rendering | VERIFIED | `flush_read_pointers/2`; `render_markdown_tuples/1`; `justify_content: :space_between` layout |
| `lib/foglet_bbs/tui/screens/post_composer.ex` | Post composer with preview + Markdown rendering | VERIFIED | `render_markdown_tuples(render_preview(state, draft))`; `@default_max_post_length 8192`; `justify_content: :space_between` layout |
| `lib/foglet_bbs/tui/screens/new_thread.ex` | NewThread with mode toggle and preview | VERIFIED | `mode: :edit` in `init_screen_state/1`; Tab toggles mode on body; `render_markdown_tuples/1`; `compose_tab_hint/1` |
| `lib/foglet_bbs/tui/widgets/key_bar.ex` | KeyBar widget | VERIFIED | Exists and used in all 9 screens |
| `lib/foglet_bbs/tui/widgets/status_bar.ex` | StatusBar widget | VERIFIED | Renders title + handle + location |
| `lib/foglet_bbs/tui/widgets/modal.ex` | Modal widget with word-wrap | VERIFIED | `@wrap_width 50`; `word_wrap/2`; `key_hint_for(_) -> "[Enter] OK"`; wrapped lines from `Enum.map` |
| `lib/foglet_bbs/markdown.ex` | Markdown.render/1 returns tuple list | VERIFIED | `@spec render(String.t()) :: [{String.t(), style_atom()}]`; marker-based two-pass pipeline; `strip_ansi/1` before MDEx parse |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `ssh/supervisor.ex daemon_opts` | Raxol TUI app launched | `ssh_cli: {Foglet.SSH.CLIHandler, []}` | VERIFIED (override) | Custom CLIHandler calls `Raxol.Core.Runtime.Lifecycle.start_link(Foglet.TUI.App, ...)` |
| `login.ex pending/suspended clauses` | `state.modal` set AND `screen_state: %{}` | both keys in same map update | VERIFIED | Lines 301, 305 in login.ex: `%{state | modal: modal, screen_state: %{}}` |
| `modal.ex render/1` | column of wrapped text/2 lines | `word_wrap(@wrap_width)` then `Enum.map` | VERIFIED | Lines 47-48 in modal.ex |
| `markdown.ex render/1` | `[{string, style_atom}]` list | marker-based two-pass parser | VERIFIED | Spot-check: `render("**hello**")` → `[{"hello", :bold}, {"\n", :plain}]` |
| `post_composer.ex :preview branch` | `render_markdown_tuples/1` | `render_markdown_tuples(render_preview(state, draft))` | VERIFIED | Line 52 in post_composer.ex |
| `post_reader.ex render_post_items/4` | `render_markdown_tuples/1` | `render_markdown_tuples(markdown_mod.render(body))` | VERIFIED | Line 187 in post_reader.ex |
| `new_thread.ex Tab on :body` | mode toggle (:edit ↔ :preview) | `if ss.focused == :body -> new_mode` | VERIFIED | Lines 316-325 in new_thread.ex |
| `new_thread.ex Tab on :title` | focus advance (not mode toggle) | `else -> new_focus` | VERIFIED | Lines 321-323 in new_thread.ex |
| `post_reader.ex Q key` | DB read pointer flush | `{:flush_read_pointers, ctx}` command | VERIFIED | `flush_read_pointers/2` calls `advance_board_read_pointer` and `advance_read_pointer` |
| `post_composer.ex Ctrl+S` | new post created | `Foglet.Posts.create_post/3` via domain adapter | VERIFIED | `do_submit/2` calls `posts_mod.create_post` |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `board_list.ex` | `ss.boards` | `boards_mod.list_subscribed_boards(user)` via `{:boards_loaded, boards}` async | Yes — real DB query | FLOWING |
| `thread_list.ex` | `ss.threads` | `threads_mod.list_threads(board_id)` via `{:threads_loaded, threads}` async | Yes — real DB query | FLOWING |
| `post_reader.ex` | `ss.posts` | `posts_mod.list_posts(thread_id)` via `{:posts_loaded, posts}` async | Yes — real DB query | FLOWING |
| `post_composer.ex` | `ss.body_input_state` | `MultiLineInput` state; user keystrokes | Yes — user input | FLOWING |
| `post_composer.ex` preview | `render_preview(state, draft)` | `Markdown.render(draft)` → `[{text, style}]` tuples | Yes — parsed from real user input | FLOWING |
| `post_reader.ex` | `render_post_items/4` body | `markdown_mod.render(body)` → `[{text, style}]` tuples | Yes — from post.body in DB | FLOWING |
| `new_thread.ex` preview | `render_preview_text(state, value)` | `Markdown.render(draft)` → `[{text, style}]` tuples | Yes — parsed from user's draft text | FLOWING |
| `login.ex` | form handle/password | `ss.form` updated by `handle_form_key` | Yes — user input | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Full test suite passes | `mix test` | 1 property, 409 tests, 0 failures | PASS |
| No `spacer(flex` in screen files | `grep "spacer(flex" lib/foglet_bbs/tui/screens/*.ex` | 0 matches | PASS |
| 9 screens use justify_content: :space_between | `grep "justify_content: :space_between" lib/foglet_bbs/tui/screens/*.ex` | 10 matches (new_thread.ex has 2 render fns) | PASS |
| main_menu.ex has divider after StatusBar | file read lines 23-24 | `StatusBar.render(...)` then `divider()` | PASS |
| modal.ex @wrap_width 50 and word_wrap/2 | file read | `@wrap_width 50`, `word_wrap/2` at line 72 | PASS |
| modal.ex key_hint_for/1 returns "[Enter] OK" | file read line 68 | `defp key_hint_for(_), do: "[Enter] OK"` | PASS |
| login.ex pending clause clears screen_state | file read line 301 | `%{state \| modal: modal, screen_state: %{}}` | PASS |
| login.ex suspended clause clears screen_state | file read line 305 | `%{state \| modal: modal, screen_state: %{}}` | PASS |
| Markdown.render/1 returns tuple list (bold) | `mix run -e 'IO.inspect(Foglet.Markdown.render("**hello**"))'` | `[{"hello", :bold}, {"\n", :plain}]` | PASS |
| Markdown.render/1 returns tuple list (italic) | `mix run -e 'IO.inspect(Foglet.Markdown.render("*hi*"))'` | `[{"hi", :italic}, {"\n", :plain}]` | PASS |
| ANSI injection defense (T-2-03) | `mix run -e 'IO.inspect(Foglet.Markdown.render("\e[1mx\e[0m"))'` | `[{"x", :plain}, {"\n", :plain}]` — no :bold | PASS |
| Heading returns :underline tuple | `mix run -e 'IO.inspect(Foglet.Markdown.render("# Title"))'` | `[{"TITLE", :underline}, {"\n", :plain}]` | PASS |
| new_thread.ex has `mode: :edit` in init_screen_state | file read line 53 | `mode: :edit` present | PASS |
| new_thread.ex Tab on body toggles mode | test new_thread_test.exs Tests 8-10 | All pass in 409 test run | PASS |
| render_markdown_tuples/1 in PostComposer | `grep "render_markdown_tuples" lib/foglet_bbs/tui/screens/post_composer.ex` | Line 52, 305 | PASS |
| render_markdown_tuples/1 in PostReader | `grep "render_markdown_tuples" lib/foglet_bbs/tui/screens/post_reader.ex` | Line 187, 204 | PASS |
| render_markdown_tuples/1 in NewThread | `grep "render_markdown_tuples" lib/foglet_bbs/tui/screens/new_thread.ex` | Line 127, 226 | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| SSH-01 | 03-02 | OTP SSH daemon starts on configured port with host key | SATISFIED | `ssh/supervisor.ex` daemon_opts; `config/config.exs` :ssh_port 2222; host key dir in `ensure_system_dir!` |
| SSH-02 | 03-02, 03-03 | User can log in with username and password via TUI | SATISFIED | `login.ex submit_login/1` calls `Accounts.authenticate_by_password/2`; status-aware branching |
| SSH-03 | 03-02 | SSH public key offered by client is stashed for user lookup | SATISFIED (override) | Option A: `key_cb.ex` stash + `cli_handler.ex` pop; `Accounts.get_user_by_public_key/1` called in CLIHandler |
| SSH-04 | 03-03, 03-05 | Registration flow collects required fields without crashing | SATISFIED | `register.ex` wizard; `login.ex maybe_register/1` with full 5-key init; register_test.exs passes |
| SSH-05 | 03-06 | One active session per user; reconnecting replaces old session | SATISFIED | Modal intercept guard; command_result re-dispatcher; 6 tests in app_test.exs |
| SSH-06 | 03-06 | Terminal resize updates Raxol Rendering Engine dimensions | SATISFIED (code path) | `Event.new(:resize,...)` in cli_handler.ex; routing through Raxol Dispatcher confirmed; runtime behavior needs human test |
| SSH-07 | 03-04, 03-05, 03-07 | All 9 TUI screens render with correct layout; all UAT gaps closed | SATISFIED | All screens use `justify_content: :space_between`; `spacer(flex:` = 0; divider on main menu; modal word-wrap; NewThread preview mode; Markdown tuple rendering; 239 TUI tests pass |
| SSH-08 | 03-04, 03-07 | Navigation menu-driven with single-key shortcuts; Markdown preview works | SATISFIED | PostComposer `@default_max_post_length 8192`; Ctrl+S/C/Tab; `render_markdown_tuples/1` in all 3 screens; NewThread Tab toggles mode |
| SSH-09 | 03-04 | Read pointers flushed to DB on PostReader exit | SATISFIED (code path) | `flush_read_pointers/2` in post_reader.ex; `{:flush_read_pointers, ctx}` command on Q; runtime DB write needs human test |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `lib/foglet_bbs/tui/screens/new_thread.ex` | 434 | `"Thread creation coming soon — Phase 2 not yet wired."` | Info | Intentional fallback guarded by `function_exported?(threads_mod, :create_thread, 3)`; Phase 2 dependency; acceptable |

No blocker anti-patterns found. The "coming soon" message in `new_thread.ex` is a documented Phase 2 dependency, not a stub for Phase 3 work.

### Human Verification Required

#### 1. SSH Daemon Host Key Persistence

**Test:** Start the application with `mix phx.server` (or `iex -S mix`), then connect twice with `ssh -p 2222 localhost`. Disconnect between connections.
**Expected:** First connection generates a host key in `priv/ssh/`; second connection reuses the same key (SSH client does not warn about host key change). TUI Login screen appears on both connections.
**Why human:** Host key generation and filesystem persistence require a live daemon. `priv/ssh/.gitkeep` confirms the directory structure is set up, but the actual key generation path through `ensure_system_dir!` and OTP `:ssh.daemon/2` can only be verified by observing runtime behavior.

#### 2. SSH Public Key Authentication Chain

**Test:** Register a user, add their SSH public key to the database, then connect with `ssh -i ~/.ssh/test_key -p 2222 localhost`.
**Expected:** `PubkeyStash` receives the offered key during SSH handshake; CLIHandler pops the stash entry and calls `Accounts.get_user_by_public_key/1`; the resolved user is set as `current_user` in TUI state; StatusBar shows the correct handle.
**Why human:** The stash-pop-lookup chain spans the SSH handshake and process startup boundary. Unit tests cover each piece independently; the integration path requires a live SSH connection with a registered user.

#### 3. Terminal Resize Rendering Update

**Test:** Connect via SSH, then resize the terminal window (drag corner or `stty cols 120 rows 40`).
**Expected:** TUI redraws immediately to fill new dimensions. Content previously hidden by narrower width becomes visible.
**Why human:** `Event.new(:resize,...)` routing through `Raxol.Dispatcher.handle_resize_event/2` sends `{:update_size,...}` to the Rendering Engine. The code path is verified (line 163 in cli_handler.ex), but confirming that the Rendering Engine actually re-layouts requires observing the visual result in a live terminal.

#### 4. End-to-End Registration + Verification + Login Flow

**Test:** Connect via SSH → Login screen → press R → fill handle, email, password through registration wizard → receive verification email → enter 6-digit code on Verify screen → log in with new credentials.
**Expected:** Each wizard step renders without KeyError; code accepted within 5 attempts; user status transitions from `:pending` to `:active`; subsequent login reaches Main Menu and shows the new handle in StatusBar.
**Why human:** This flow requires a live SMTP/mailer configuration for code delivery, actual DB writes through the full Ecto stack, and multi-screen navigation that cannot be simulated by unit tests alone.

#### 5. Board Browsing and Read Pointer Flush

**Test:** Log in as an existing user → press B from Main Menu → browse to a board → open a thread → read posts → press Q.
**Expected:** Board List populates (not stuck on "Loading..."), confirming `command_result` re-dispatcher works end-to-end; Thread List and Post Reader also populate; pressing Q writes read pointers to the DB (verify with a DB query: `SELECT * FROM user_thread_reads WHERE user_id = X`).
**Why human:** The `command_result` re-dispatcher is covered by unit tests (4 tests in app_test.exs), but confirming the full async chain works in a live session requires manual observation. The DB flush similarly needs a live session to confirm `advance_read_pointer` calls actually commit.

#### 6. Pending-Account Modal Dismiss Returns to Landing Menu

**Test:** Connect via SSH and attempt to log in with a :pending account. Observe the modal. Press Enter.
**Expected:** Modal message is word-wrapped (no line wider than ~50 chars), key hint shows "[Enter] OK" only (no "Esc" advertised separately), and pressing Enter returns to the `[L] Login  [R] Register  [Q] Quit` landing menu — not the login form or Register screen.
**Why human:** `screen_state: %{}` clearing is verified by unit test (Test D), but confirming the visual layout (modal fits within 80-col terminal without overflow) and the navigation result (landing menu appears) requires a live SSH session.

#### 7. NewThread Edit/Preview Mode Toggle

**Test:** Log in → Main Menu → press C → pick a board → type a body with some `**bold**` text → press Tab on the body field.
**Expected:** Screen switches to a preview showing formatted output (bold text rendered bold, not as `**text**`). Press Tab again — screen returns to editable body. Press Tab while cursor is on the title field — focus advances to body, mode does not change.
**Why human:** `render_markdown_tuples/1` and `Markdown.render/1` are unit-tested, but whether Raxol actually renders the styled text visually (versus ignoring the style keyword) requires a live session to confirm.

---

## Architectural Deviations (Overrides Applied)

Three plan-level key-links deviate from their must_have specifications. All three are intentional, documented in plan summaries, and covered by updated tests.

### Deviation 1: KeyCB Option A (is_auth_key/3 always returns true)

Plan 03-02 required `is_auth_key/3` to call `Accounts.get_user_by_public_key/1` during the SSH handshake. The actual implementation uses "Option A": `is_auth_key/3` always returns `true` and stores the offered pubkey in `Foglet.SSH.PubkeyStash` (ETS). `Foglet.SSH.CLIHandler` retrieves the stashed key post-auth and calls `Accounts.get_user_by_public_key/1` there. The security outcome is equivalent. Documented in 03-02-SUMMARY.md.

### Deviation 2: Custom CLIHandler

Plan 03-02 required `ssh_cli: {Raxol.SSH.CLIHandler, [app_module: Foglet.TUI.App]}`. The actual implementation uses `{Foglet.SSH.CLIHandler, []}`, a custom handler that internally calls `Raxol.Core.Runtime.Lifecycle.start_link(Foglet.TUI.App, ...)`. Functional outcome is identical. Documented in 03-02-SUMMARY.md.

### Deviation 3: pwdfun removed

Plan 03-02 required a `pwdfun` callback for SSH-level password authentication. The actual implementation removes it — `no_auth_needed: true` means all SSH connections are accepted at the transport level, and credential verification moves entirely to the TUI Login screen. SSH-02 (username/password login) is still delivered via `Accounts.authenticate_by_password/2` called from `login.ex`. Documented in 03-02-SUMMARY.md.

---

_Verified: 2026-04-19T18:30:00Z_
_Verifier: Claude (gsd-verifier)_
