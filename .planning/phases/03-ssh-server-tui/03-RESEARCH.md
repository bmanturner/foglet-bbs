# Phase 3: SSH Server & TUI - Research

**Researched:** 2026-04-18
**Domain:** Erlang :ssh daemon, Raxol v2.4.0 TUI, session management, OTP supervision
**Confidence:** HIGH (core stack verified against Hex registry, hexdocs, GitHub source, official Erlang docs)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** All three registration modes supported: `open`, `invite_only`, `sysop_approved`. Mode stored in runtime `configuration` table, read via `Foglet.Config` ETS cache.
- **D-02:** Default registration mode: `open`.
- **D-03:** Registration mode stored in `configuration` table keyed as `registration_mode`.
- **D-04:** Invite code generation default: `sysop_only`. Config key wired; broader grant levels are later.
- **D-05:** Sysop-approved mode persists accounts with `status: :pending`; blocks login. Approval UI is Phase 8.
- **D-06:** When registration is disabled, `[R] Register` is hidden from the login-or-register menu.
- **D-07:** Sysop-approved mode disconnects after registration with "Your account is pending sysop approval."
- **D-08:** Email verification uses a **short alphanumeric code** (e.g. `XK7P2Q`), NOT a URL token.
- **D-09:** Code-based verification replaces URL token approach from Phase 1. `user_tokens` table repurposed: `token_type = email_verify`, `token` column holds code string.
- **D-10:** Code expiry: 15 minutes. Max attempts: 5 before cooldown. Rate limiting at Session level.
- **D-11:** In dev: code logged via `Logger.info`. In prod: emailed (Phase 10). Session works identically in both.
- **D-12:** Verification screen holds SSH session open; advances to main menu on successful verification.
- **D-13:** TUI framework: **Raxol v2.4.0**. Add `{:raxol, "~> 2.4"}` to `mix.exs`.
- **D-14:** SSH integration: own `:ssh.daemon/2` call (maintaining full control over host keys, auth callbacks, and `Foglet.SSH.Supervisor`). Raxol's `CLIHandler` (`Raxol.SSH.CLIHandler`) plugged in as `ssh_cli` option.
- **D-15:** Single Raxol application (`Foglet.TUI.App`) for the entire BBS experience. `app.ex` is conductor, `screens/*` are scores, `widgets/*` are instruments, `doors/*` are guest performers.
- **D-16:** State architecture: domain state in Postgres, session-scoped identity/policy in `Foglet.Sessions.Session` GenServer, UI state in Raxol model.
- **D-17:** File layout: `lib/foglet_bbs/tui/app.ex`, `screens/`, `widgets/`, `doors/`.
- **D-18:** Hardcode single default theme: classic green-on-black BBS look.
- **D-19:** Keyboard navigation: single-key shortcuts everywhere. Key bar at bottom of each screen.
- **D-20:** Modal widget for errors and confirmations. Lives in `tui/widgets/modal.ex`.
- **D-21:** TUI testing: unit test Raxol `update/2` and `view/1` directly. No real SSH harness in Phase 3.
- **D-22:** Guest entry: unauthenticated SSH connections show login-or-register menu immediately.
- **D-23:** Registration wizard sequence varies by mode. Invite-only: invite code first, then handle/email/password/verify.
- **D-24:** SSH keys NOT collected during registration. Deferred to IDNT-04 in-TUI key management.
- **D-25:** One session per user via `Foglet.Sessions.Supervisor`. Reconnecting replaces old session with notification.
- **D-26:** Composer uses Raxol's built-in multi-line scrollable text input widget.
- **D-27:** Composer layout: header, quote context, scrollable text area, key bar.
- **D-28:** Tab toggles between Markdown edit and ANSI preview in same screen.
- **D-29:** Submit key: `Ctrl+S`.
- **D-30:** Cancel: `Ctrl+C` (no confirmation prompt).
- **D-31:** Maximum post length: configurable via runtime config (`max_post_length`), default 8192.

### Claude's Discretion

- SSH host key storage: `priv/ssh/` directory, persisted across deploys. Key generation on first boot if not present.
- Session reconnect grace window: 30-second default, no user configuration in Phase 3.
- Read pointer advance: advance board and thread read pointers on each page-down/next-post key; flush to Postgres on screen transition.
- Board list: show subscribed boards with unread counts.
- Thread list: show threads in a board, newest-activity-first, with unread post counts.
- Post reader: page through posts with prev/next keys. Display ANSI-rendered Markdown.
- Navigation between screens: via Raxol model `current_screen` routing inside `app.ex`.

### Deferred Ideas (OUT OF SCOPE)

- Browse-as-guest (read-only access without an account)
- SSH key collection during registration
- Full multi-theme support
- E2E SSH harness for integration testing
- Sysop approval queue UI (Phase 8)
- Email notification on approval (Phase 10)
- Invite code generation by mods or any user
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SSH-01 | Erlang :ssh daemon accepts connections; persistent host key survives deploys | Erlang ssh:daemon/2, host_key via ssh_server_key_api; `priv/ssh/` storage verified |
| SSH-02 | User can authenticate via SSH password (Argon2-checked against user store) | `pwdfun` option in ssh:daemon/2; delegates to Foglet.Accounts.authenticate_by_password/2 |
| SSH-03 | User can authenticate via SSH public key (matched against registered keys) | `key_cb` option + ssh_server_key_api; delegates to Foglet.Accounts.get_user_by_public_key/1 |
| SSH-04 | New users can register through an SSH guest flow (no_auth_needed path to guest screen) | `no_auth_needed` + custom `pwdfun` fallback; Raxol CLIHandler starts login screen for unauthenticated connections |
| SSH-05 | One active session per user; reconnecting replaces old session with notification | Registry + DynamicSupervisor; Foglet.Sessions.Supervisor enforces rule |
| SSH-06 | Terminal size via PTY/window-change; TUI adapts | Raxol.SSH.CLIHandler handles :pty and :window_change; passed through to Raxol model state |
| SSH-07 | TUI screens: login, main menu, board list, thread list, post reader, post composer | Raxol TEA: init/update/view callbacks; screens/* pattern |
| SSH-08 | Single-key shortcuts throughout | Raxol KeyboardShortcuts + handle_event; key bar widget |
| SSH-09 | Read pointers advance automatically as user reads | Board/thread pointer flush on screen transition; Phase 2 domain APIs |
</phase_requirements>

---

## Summary

Phase 3 builds the entire SSH entry path and TUI on top of two well-matched primitives: Erlang's built-in `:ssh` application (OTP 28, already in `extra_applications`) and Raxol v2.4.0 (the locked TUI framework). The architecture separates concerns cleanly: the `:ssh` daemon owns authentication, `Foglet.SSH.Supervisor` wraps the daemon process, `Foglet.Sessions.Supervisor` (DynamicSupervisor) enforces one-session-per-user, and the Raxol TEA application (`Foglet.TUI.App`) handles all UI state via `init/2 update/2 view/1` callbacks.

The key integration point is `Raxol.SSH.CLIHandler`, which implements Erlang's `ssh_server_channel` behavior. It is passed as `ssh_cli: {Raxol.SSH.CLIHandler, [app_module: Foglet.TUI.App]}` in the daemon options. This allows Foglet to control authentication (via `pwdfun` for passwords and `key_cb` for public keys) while Raxol owns TUI rendering. The `Foglet.SSH.Supervisor` does NOT use `Raxol.SSH.Server` — it calls `:ssh.daemon/2` directly with custom auth callbacks.

A critical security note: CVE-2025-32433 (CVSS 10, unauthenticated RCE via Erlang SSH, April 2025) is patched in OTP 27.3.3+. The project runs OTP 28.3.1 (ERTS 16.3.1), which is in the OTP 28 branch and postdates the patch window — confirmed safe.

**Primary recommendation:** Run a single `:ssh.daemon/2` call from `Foglet.SSH.Supervisor`, passing `pwdfun`, `key_cb`, `ssh_cli`, and `system_dir` (pointing to `priv/ssh/`). Use `Raxol.SSH.CLIHandler` as the `ssh_cli` module. Authentication decides user identity before handing off to `Foglet.Sessions.Supervisor`. The Raxol TEA application drives all screen rendering.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| SSH connection acceptance | SSH Daemon (`Foglet.SSH.Supervisor`) | — | :ssh.daemon/2 owns TCP bind and protocol negotiation |
| Password authentication | SSH Daemon (pwdfun callback) | `Foglet.Accounts` | pwdfun is the ssh daemon's hook; calls Accounts.authenticate_by_password/2 |
| Pubkey authentication | SSH Daemon (key_cb module) | `Foglet.Accounts.SSHKey` | ssh_server_key_api is the daemon's hook; calls Accounts.get_user_by_public_key/1 |
| Guest/unauthenticated path | SSH Daemon (no_auth_needed or pwdfun allows guest) | `Foglet.TUI.App` login screen | Daemon allows connection; TUI shows register flow |
| Host key persistence | SSH Daemon (`priv/ssh/` system_dir) | — | system_dir option persists keys across deploys |
| Session lifecycle / one-session rule | `Foglet.Sessions.Supervisor` | `Foglet.Sessions.Session` | DynamicSupervisor + Registry enforce uniqueness |
| Terminal size negotiation | `Raxol.SSH.CLIHandler` | `Foglet.Sessions.Session` | CLIHandler receives :pty and :window_change events; Session stores terminal dims |
| TUI rendering | `Foglet.TUI.App` (Raxol) | `Foglet.TUI.Screens.*` | Raxol TEA owns all view state and rendering |
| Screen navigation | `Foglet.TUI.App` model | `Foglet.TUI.Screens.*` | `current_screen` field in TUI model; screens are pure view functions |
| Domain data access | `Foglet.Boards`, `Foglet.Threads`, `Foglet.Posts` | Postgres | Phase 2 domain APIs called directly from TUI update/2 handler |
| Email verification codes | `Foglet.Accounts` + `user_tokens` table | `Foglet.Sessions.Session` | Token stored in DB; Session holds verification state and rate limits |
| Read pointer tracking | `Foglet.Boards` / `Foglet.Threads` (Phase 2 APIs) | `Foglet.TUI.App` model | TUI tracks current read position; flushes to DB on screen transition |
| Session PubSub subscriptions | `Foglet.TUI.App` (Raxol subscribe/1) | `Foglet.Sessions.Session` | TUI app subscribes to PubSub topics; Session pings app for heartbeat |

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `:ssh` (OTP built-in) | OTP 28.3.1 | SSH server daemon, protocol, channel management | Already in `extra_applications`; no additional dep |
| `:public_key` (OTP built-in) | OTP 28.3.1 | Key parsing, fingerprint computation for pubkey auth | Already in `extra_applications` |
| `raxol` | 2.4.0 | TUI framework (TEA: init/update/view), SSH channel handler, widgets | Locked in D-13; verified on Hex |
| `phoenix_pubsub` | via Phoenix (existing) | TUI app subscribes to board/user/session topics | Already in project deps |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `argon2_elixir` | 4.x (existing) | Password hash verification in pwdfun | SSH password auth delegate |
| `jason` | 1.x (existing) | JSON encode/decode for session state serialization | Config and preferences |
| `:crypto` (OTP built-in) | OTP 28.3.1 | Generating alphanumeric verification codes | Email verify code generation |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `:ssh.daemon/2` direct | `Raxol.SSH.Server` | Raxol.SSH.Server uses `no_auth_needed: true` internally — cannot plug in custom auth callbacks. Must use `:ssh.daemon/2` directly for Foglet's authenticated use case. |
| Custom ssh_cli module | `Raxol.SSH.CLIHandler` | Writing our own ssh_server_channel is 200+ lines of boilerplate with PTY handling. Use Raxol.SSH.CLIHandler as the ssh_cli module per D-14. |
| `esshd` hex package | `:ssh` directly | `esshd` is unmaintained (last commit 2022). OTP's built-in :ssh is the canonical choice. |

**Installation:**
```bash
# Add to mix.exs deps:
{:raxol, "~> 2.4"}
```
**Version verification:** Confirmed via `mix hex.search raxol` — version 2.4.0 is the latest stable release, published April 2026. [VERIFIED: Hex registry]

---

## Architecture Patterns

### System Architecture Diagram

```
SSH Client
    │
    │ TCP :2222
    ▼
:ssh.daemon/2
  ├─── pwdfun callback ──────────► Foglet.Accounts.authenticate_by_password/2
  ├─── key_cb module ────────────► Foglet.Accounts.get_user_by_public_key/1
  └─── ssh_cli: {Raxol.SSH.CLIHandler, [app_module: Foglet.TUI.App]}
              │
              │ spawn per connection
              ▼
    Raxol.SSH.CLIHandler (ssh_server_channel)
        │ :pty → terminal size
        │ :data → keystrokes
        │ :window_change → resize
        │
        ▼
    Raxol.SSH.Session (per-connection Lifecycle process)
        │
        │ on auth success: start or replace Session
        ▼
    Foglet.Sessions.Session (DynamicSupervisor child)
        │ holds: user_id, handle, role, terminal_size
        │ enforces: one-session-per-user (Registry by user_id)
        │
        │ starts Raxol app
        ▼
    Foglet.TUI.App (Raxol TEA application)
        │ model: current_screen, user context, local read pointer state
        │
        ├─── view/1 ──────────────► ANSI output ──► SSH channel ──► client terminal
        ├─── update/2 ────────────► domain calls (Boards, Threads, Posts)
        │                       └─► PubSub subscriptions (subscribe/1)
        └─── Screens: login, register, verify, main_menu, board_list,
                      thread_list, post_reader, post_composer
             Widgets: modal, status_bar, key_bar

Domain Events (PubSub topics):
    Phoenix.PubSub ──► Foglet.TUI.App.handle_message/2
```

### Recommended Project Structure
```
lib/foglet_bbs/
├── ssh/
│   ├── supervisor.ex          # Foglet.SSH.Supervisor — wraps :ssh.daemon/2
│   └── key_cb.ex              # Foglet.SSH.KeyCB — implements ssh_server_key_api
├── sessions/
│   ├── supervisor.ex          # Foglet.Sessions.Supervisor — DynamicSupervisor
│   └── session.ex             # Foglet.Sessions.Session — per-user GenServer
└── tui/
    ├── app.ex                 # Foglet.TUI.App — Raxol application entry point
    ├── screens/
    │   ├── login.ex           # Foglet.TUI.Screens.Login
    │   ├── register.ex        # Foglet.TUI.Screens.Register
    │   ├── verify.ex          # Foglet.TUI.Screens.Verify
    │   ├── main_menu.ex       # Foglet.TUI.Screens.MainMenu
    │   ├── board_list.ex      # Foglet.TUI.Screens.BoardList
    │   ├── thread_list.ex     # Foglet.TUI.Screens.ThreadList
    │   ├── post_reader.ex     # Foglet.TUI.Screens.PostReader
    │   └── post_composer.ex   # Foglet.TUI.Screens.PostComposer
    └── widgets/
        ├── modal.ex           # Foglet.TUI.Widgets.Modal
        ├── key_bar.ex         # Foglet.TUI.Widgets.KeyBar
        └── status_bar.ex      # Foglet.TUI.Widgets.StatusBar

priv/
└── ssh/
    └── (host keys — generated on first boot, gitignored)
```

### Pattern 1: Erlang :ssh Daemon with Custom Auth

**What:** Run `:ssh.daemon/2` with `pwdfun`, `key_cb`, and `ssh_cli` options instead of using `Raxol.SSH.Server` (which hardcodes `no_auth_needed: true`).

**When to use:** Required for Foglet — we need password auth, pubkey auth, and the guest registration path.

**Example:**
```elixir
# Source: https://www.erlang.org/doc/man/ssh.html
# lib/foglet_bbs/ssh/supervisor.ex

defmodule Foglet.SSH.Supervisor do
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    port = Application.get_env(:foglet_bbs, :ssh_port, 2222)
    host_keys_dir = Application.app_dir(:foglet_bbs, "priv/ssh")

    daemon_opts = [
      system_dir: String.to_charlist(host_keys_dir),
      # pwdfun_4: receives {user, password_or_:pubkey, peer_addr, state}
      # Return true to allow, false to deny, :disconnect to forcibly drop
      pwdfun: &Foglet.SSH.Supervisor.authenticate/4,
      # key_cb: module implementing ssh_server_key_api behavior
      key_cb: {Foglet.SSH.KeyCB, []},
      ssh_cli: {Raxol.SSH.CLIHandler, [app_module: Foglet.TUI.App]},
      max_sessions: 500
    ]

    {:ok, _daemon_pid} = :ssh.daemon(port, daemon_opts)

    # Supervisor watches sessions, not the daemon directly
    Supervisor.init([], strategy: :one_for_one)
  end

  # pwdfun_4 callback: allows password auth AND pubkey check-user
  def authenticate(user, :pubkey, _peer, state) do
    # pk_check_user: the :pubkey atom signals the daemon is
    # verifying the username associated with the key (already validated by key_cb)
    handle = List.to_string(user)
    case Foglet.Accounts.get_user_by_handle(handle) do
      %Foglet.Accounts.User{deleted_at: nil} -> {true, state}
      _ -> {false, state}
    end
  end

  def authenticate(user, password, _peer, state) do
    handle = List.to_string(user)
    pw = List.to_string(password)
    case Foglet.Accounts.authenticate_by_password(handle, pw) do
      {:ok, _user} -> {true, state}
      {:error, _} ->
        # Guest path: allow connection but mark as unauthenticated
        # TUI shows login-or-register screen for unrecognized users
        {false, state}
    end
  end
end
```

**Important note on guest path (SSH-04):** To allow unauthenticated connections for the guest registration flow, the `pwdfun` must return `true` for a special "guest" user, OR `no_auth_needed: true` can be added and the TUI login screen handles credential collection entirely. The CONTEXT.md (D-22) confirms unauthenticated SSH connections immediately show the login-or-register menu — this means the daemon must accept connections without valid credentials. Use `no_auth_needed: true` with the TUI owning authentication. [ASSUMED: exact strategy for combining `no_auth_needed` with authenticated sessions. Planner should resolve: either (a) `no_auth_needed: true` and TUI presents login form, or (b) two daemon instances on different ports, or (c) `pwdfun` returns true for any user and TUI gates access.]

### Pattern 2: ssh_server_key_api Implementation

**What:** Module implementing Erlang's `ssh_server_key_api` behavior for pubkey authentication.

**When to use:** For SSH-03 (pubkey auth). The `key_cb` daemon option points to this module.

**Example:**
```elixir
# Source: https://www.erlang.org/doc/man/ssh_server_key_api.html
# lib/foglet_bbs/ssh/key_cb.ex

defmodule Foglet.SSH.KeyCB do
  @behaviour :ssh_server_key_api

  @impl true
  def host_key(algorithm, opts) do
    # Load the server's host private key from priv/ssh/
    system_dir = Keyword.get(opts, :system_dir, ~c"priv/ssh")
    :ssh_file.host_key(algorithm, [{:system_dir, system_dir}])
  end

  @impl true
  def is_auth_key(public_key, user, _opts) do
    # Check if user's public key is registered in Foglet's DB
    handle = List.to_string(user)
    with %Foglet.Accounts.User{} = db_user <-
           Foglet.Accounts.get_user_by_handle(handle),
         {:ok, key_text} <- encode_public_key(public_key),
         {:ok, _user} <- Foglet.Accounts.get_user_by_public_key(key_text) do
      db_user.id != nil
    else
      _ -> false
    end
  end

  defp encode_public_key(public_key) do
    # Convert Erlang :public_key format to OpenSSH wire format for fingerprint matching
    try do
      encoded = :public_key.ssh_encode([{public_key, []}], :openssh_public_key)
      {:ok, encoded}
    rescue
      _ -> :error
    end
  end
end
```

### Pattern 3: Raxol TEA Application Structure

**What:** The Raxol TEA (The Elm Architecture) application with `use Raxol.Core.Runtime.Application`.

**When to use:** `Foglet.TUI.App` — the single entry point for all BBS screen logic.

**Example:**
```elixir
# Source: https://hexdocs.pm/raxol/2.4.0/Raxol.Core.Runtime.Application.html
# Source: Context7 /hydepwns/raxol

defmodule Foglet.TUI.App do
  use Raxol.Core.Runtime.Application
  import Raxol.View.Elements

  # TEA model struct
  defstruct [
    :current_screen,        # atom: :login | :register | :verify | :main_menu | ...
    :current_user,          # %User{} or nil for guests
    :session_context,       # map: role, terminal_size, rate_limit_state
    :board_list,            # cached board list for board_list screen
    :current_board,         # current board (for thread_list/post_reader)
    :current_thread,        # current thread
    :posts,                 # loaded posts for reader
    :read_position,         # local read pointer (flushed on screen transition)
    :modal,                 # %{message: _, type: _} | nil
    :composer_draft,        # draft text for post composer
    :register_wizard,       # wizard state for registration flow
    :verify_state           # verification attempt state
  ]

  @impl true
  def init(context) do
    # context contains: terminal dimensions, environment vars, startup args
    # session_context injected by Foglet.Sessions.Session before starting TUI
    session = Map.get(context, :session_context, %{})
    screen = if session[:user_id], do: :main_menu, else: :login
    state = %__MODULE__{
      current_screen: screen,
      current_user: session[:user],
      session_context: session
    }
    {state, []}
  end

  @impl true
  def update(message, state) do
    case message do
      {:navigate, screen} -> {%{state | current_screen: screen}, []}
      {:key, key_event}   -> handle_key(key_event, state)
      {:board_list_loaded, boards} -> {%{state | board_list: boards}, []}
      {:show_modal, msg}  -> {%{state | modal: %{message: msg}}, []}
      {:dismiss_modal}    -> {%{state | modal: nil}, []}
      _ -> {state, []}
    end
  end

  @impl true
  def view(state) do
    view do
      case state.current_screen do
        :login       -> Foglet.TUI.Screens.Login.render(state)
        :register    -> Foglet.TUI.Screens.Register.render(state)
        :verify      -> Foglet.TUI.Screens.Verify.render(state)
        :main_menu   -> Foglet.TUI.Screens.MainMenu.render(state)
        :board_list  -> Foglet.TUI.Screens.BoardList.render(state)
        :thread_list -> Foglet.TUI.Screens.ThreadList.render(state)
        :post_reader -> Foglet.TUI.Screens.PostReader.render(state)
        :post_composer -> Foglet.TUI.Screens.PostComposer.render(state)
      end
    end
  end

  @impl true
  def subscribe(_state) do
    # PubSub subscriptions for live updates (board activity, etc.)
    []
  end
end
```

### Pattern 4: Foglet.Sessions.Session GenServer

**What:** Per-user GenServer started by `Foglet.Sessions.Supervisor`. Enforces one-session-per-user via Registry.

**When to use:** Started on successful authentication. Replaces any existing session for the same user_id.

**Example:**
```elixir
# Source: ARCHITECTURE.md §4, CONTEXT.md D-25
# lib/foglet_bbs/sessions/session.ex

defmodule Foglet.Sessions.Session do
  use GenServer

  # Registry-based one-session-per-user enforcement
  def start_link(opts) do
    user_id = Keyword.fetch!(opts, :user_id)
    # Via Registry ensures only one process per user_id
    GenServer.start_link(__MODULE__, opts,
      name: {:via, Registry, {Foglet.Sessions.Registry, user_id}}
    )
  end

  @impl true
  def init(opts) do
    # If another session exists (during via registration race), it
    # is terminated by the Registry -- but we also need to notify it.
    state = %{
      user_id: opts[:user_id],
      handle: opts[:handle],
      role: opts[:role],
      terminal_size: opts[:terminal_size] || {80, 24},
      connected_at: DateTime.utc_now(),
      last_seen_at: DateTime.utc_now(),
      tui_pid: nil
    }
    {:ok, state}
  end
end
```

**One-session enforcement strategy:** When a new Session starts with an existing `user_id` in the Registry, the old session process must be found and terminated with a notification. Use `Registry.lookup/2` to find the old pid, send `{:replaced_by_new_session}`, then terminate it before registering the new one. [ASSUMED: exact replacement semantics — whether the old session self-terminates on receiving the message or the supervisor kills it. Planner should define the message protocol.]

### Pattern 5: Email Verification Code (D-08 through D-12)

**What:** Short alphanumeric code stored in `user_tokens` table. `token_type: "email_verify"`. Code = 6-char uppercase alphanumeric.

**When to use:** After registration wizard completes. Session holds open; user enters code at verification screen.

**Key design points:**
- The `user_tokens.token` field is currently `:binary` (stores SHA256 hash). For email verify codes, store the code directly as a short string — no hashing needed since codes are short-lived (15 min) and not a substitute for passwords. A migration adding a `token_type` column to `user_tokens` is needed (Phase 1 schema has no `token_type`; it uses `context` for this purpose — verify mapping).
- **IMPORTANT FINDING:** The Phase 1 `user_tokens` schema uses a `context` column (not `token_type`). D-09 says "token_type is email_verify" but the existing schema uses `context`. The planner should map D-09's `token_type` to the existing `context` column (set `context = "email_verify"`) and store the alphanumeric code in the `token` column as a binary (UTF-8 encoded string). No migration needed for the column structure; the table already supports this. [VERIFIED: `priv/repo/migrations/20260418000004_create_user_tokens.exs`]

```elixir
# Code generation: 6-char uppercase alphanumeric
defp generate_verify_code do
  :crypto.strong_rand_bytes(4)
  |> Base.encode32(padding: false)
  |> String.slice(0, 6)
  |> String.upcase()
end

# Store as UserToken with context = "email_verify"
# token column holds the code as raw binary (not SHA256 hash)
# sent_to = user.email
# expires: inserted_at + 15 minutes (check at verification time)
```

### Pattern 6: Raxol Multi-line Text Input (Composer)

**What:** Built-in `multi_line_input` widget for the post composer (D-26).

**When to use:** `Foglet.TUI.Screens.PostComposer` screen.

**Example:**
```elixir
# Source: Context7 /hydepwns/raxol — multi_line_input component
multi_line_input(
  value: state.composer_draft,
  placeholder: "Write your reply...",
  width: state.session_context.terminal_size |> elem(0),
  height: composer_body_height(state),
  wrap: :word,
  on_change: fn text -> send(self(), {:draft_changed, text}) end
)
```

### Anti-Patterns to Avoid

- **Using `Raxol.SSH.Server` for authenticated sessions:** `Raxol.SSH.Server` hardcodes `no_auth_needed: true`. Use `:ssh.daemon/2` directly with `pwdfun` and `key_cb` options, passing `Raxol.SSH.CLIHandler` as `ssh_cli`.
- **Separate module per screen as a Raxol sub-application:** `process_component/2` is for isolated crash-recovery sub-experiences (doors, games). Screen modules are pure view functions delegated from `app.ex view/1`. Do not `use Raxol.Core.Runtime.Application` in individual screen modules.
- **String.to_atom on SSH username:** SSH username arrives as a charlist from Erlang. Convert with `List.to_string/1`, not `String.to_atom/1` (CLAUDE.md — memory leak risk).
- **Map access syntax on Ecto structs:** Use `user.field`, not `user[:field]`. Applies to User, Session state structs.
- **Calling `confirm_user/1` for email verify code flow:** Phase 1's `confirm_user/1` exists for URL-token flow. Phase 3's code-based flow needs its own `verify_email_code/2` function in `Foglet.Accounts` that checks the code, respects the 15-minute expiry, and calls `confirm_user` internally.
- **Rebinding inside `if` for socket/state:** Follow CLAUDE.md pattern — `state = if condition, do: update_state(state), else: state`.
- **Nesting multiple modules in one file:** Each module (Supervisor, Session, KeyCB, each Screen, each Widget) lives in its own file.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| TUI rendering over SSH | Custom ANSI byte emitter + PTY handler | `Raxol.SSH.CLIHandler` as `ssh_cli`, Raxol TEA | PTY negotiation, window-change, ANSI cursor control, input parsing are complex. Raxol handles all of it |
| SSH channel protocol | Custom `ssh_server_channel` behavior impl | `Raxol.SSH.CLIHandler` | 200+ lines of boilerplate: channel open, data framing, close handling |
| Host key management | Custom key file reader/writer | `:ssh_file` module (OTP built-in) | `ssh_file.host_key/2` and `ssh_file.read_auth_keys/2` handle standard OpenSSH key file formats |
| Public key fingerprint | Custom SHA256 over key bytes | `Foglet.Accounts.SSHKey.compute_fingerprint/1` | Already implemented in Phase 1 |
| Multi-line text input | Custom scrollable editor | `Raxol.View.Elements.multi_line_input` | Cursor movement, selection, scroll, word-wrap already handled |
| Random code generation | Rolling own alphanumeric PRNG | `:crypto.strong_rand_bytes/1` + `Base.encode32/2` | CSPRNG-backed, no external dep |
| Session process registry | ETS lookup table | `Registry` (OTP built-in) | Built-in process registry with via-tuple pattern; handles concurrent registration safely |

**Key insight:** The split between `:ssh.daemon/2` (auth) and `Raxol.SSH.CLIHandler` (TUI channel) is the architecture's core insight. Everything "before the shell prompt" (keys, passwords, host keys) uses OTP builtins. Everything "after the shell prompt" (rendering, keyboard, resize) uses Raxol.

---

## Common Pitfalls

### Pitfall 1: CLIHandler vs SSH.Server Confusion

**What goes wrong:** Using `Raxol.SSH.Server` directly or calling `Raxol.SSH.serve/2` — this hardcodes `no_auth_needed: true`, giving every connection unauthenticated access.

**Why it happens:** `Raxol.SSH.Server` is the obvious entry point in Raxol docs for SSH serving. Its auth model is "let everyone in, TUI handles identity."

**How to avoid:** Run `:ssh.daemon/2` directly in `Foglet.SSH.Supervisor`. Pass `Raxol.SSH.CLIHandler` as `{ssh_cli, {Raxol.SSH.CLIHandler, [app_module: Foglet.TUI.App]}}`. Add `pwdfun` and `key_cb` for authentication. [VERIFIED: Raxol.SSH.Server source — `no_auth_needed: true`]

**Warning signs:** Every connection reaches the main menu without any credentials.

### Pitfall 2: Charlist vs Binary for SSH Username

**What goes wrong:** SSH username from Erlang is a charlist (`:erlang` type). Passing it directly to Elixir string functions or Ecto queries causes a type mismatch or silent empty-string bugs.

**Why it happens:** Erlang's :ssh passes `user` as `[104, 101, 108, 108, 111]` not `"hello"`.

**How to avoid:** Always `List.to_string(user)` before passing to `Foglet.Accounts` functions. Do this at the boundary in `pwdfun` and `key_cb.is_auth_key/3`.

**Warning signs:** `get_user_by_handle/1` always returns `nil` even for valid users.

### Pitfall 3: Host Key Not Persisting Across Deploys

**What goes wrong:** SSH clients get "host key changed" warning after every deploy. They must re-accept the host key or connections fail with `REMOTE HOST IDENTIFICATION HAS CHANGED`.

**Why it happens:** `system_dir` points to a tmp directory or a non-persistent volume. Host keys are regenerated on each daemon start.

**How to avoid:** Set `system_dir` to `Application.app_dir(:foglet_bbs, "priv/ssh")` — this is part of the OTP release and survives deploys as long as `priv/` is on a persistent volume. Commit the directory (but gitignore the key files themselves for security, or manage via secrets). Generate keys on first boot if not present using `:ssh_file` or `ssh-keygen`.

**Warning signs:** After restart, `~/.ssh/known_hosts` shows the BBS server's fingerprint changed.

### Pitfall 4: One-Session Race Condition

**What goes wrong:** Two near-simultaneous connections for the same user both pass auth before either has registered in the Registry. Both sessions start, violating the one-session guarantee.

**Why it happens:** Registry `via`-tuple registration is atomic per process start, but the "find old, notify, start new" pattern has a TOCTOU window if not structured correctly.

**How to avoid:** Use the Registry `via`-tuple in `GenServer.start_link` — the Registry itself handles the collision atomically. When a new Session starts with an existing name, `start_link` returns `{:error, {:already_started, old_pid}}`. The caller (Sessions.Supervisor) must then: (1) send the old pid a replacement notification, (2) call `GenServer.stop(old_pid)`, (3) retry `start_link`. Wrap in `DynamicSupervisor.start_child`.

**Warning signs:** Two Terminal windows both reach the main menu as the same user simultaneously.

### Pitfall 5: Raxol update/2 Return Arity

**What goes wrong:** Returning bare state from `update/2` causes a runtime crash. Raxol expects `{state, [commands]}`.

**Why it happens:** Elm-influenced API. The second element is a command list (effects). Always return `{state, []}` even when there are no side effects.

**Warning signs:** Crash in Raxol runtime with "bad return value from update/2".

### Pitfall 6: Email Verify Code Collision with Phase 1 Token Logic

**What goes wrong:** Using `UserToken.build_email_token/2` (which SHA256-hashes the token) for the short verification code path. The existing `verify_email_token_query/2` checks SHA256 hash + expiry window — it won't work with a plain alphanumeric code.

**Why it happens:** The existing `UserToken` module is designed for long, hashed tokens. D-09 repurposes the table but the code format is completely different.

**How to avoid:** Add a new `build_verify_code_token/1` function to `Foglet.Accounts.UserToken` (or `Foglet.Accounts`) that stores the code in plain binary (not hashed) with `context = "email_verify"`. Add a corresponding `verify_code/2` function that queries by plain code value + context + expiry (15 min) + `sent_to == user.email`. Do NOT reuse `verify_email_token_query/2`.

**Warning signs:** Code verification always fails even with correct code entry.

### Pitfall 7: CVE-2025-32433 in Older OTP Versions

**What goes wrong:** Unauthenticated RCE via Erlang's SSH daemon on OTP < 27.3.3 / < 26.2.5.11 / < 25.3.2.20.

**Why it happens:** The vulnerability allows sending SSH protocol messages before authentication, enabling pre-auth RCE.

**How to avoid:** Project uses OTP 28.3.1 (ERTS 16.3.1) — confirmed to postdate the patch window. CVE is fixed in OTP 28.x series. Add a runtime check in `Foglet.SSH.Supervisor.init/1` that asserts OTP version >= 27.3.3 and logs a warning if not, to protect future downgrade scenarios. [VERIFIED: OTP 28.3.1 is in the OTP 28 branch, newer than OTP 27.3.3 which is the fix boundary]

---

## Code Examples

Verified patterns from official sources:

### Erlang :ssh.daemon/2 with pwdfun_4
```elixir
# Source: https://www.erlang.org/doc/man/ssh.html
# pwdfun_4: (user, password_or_pubkey_atom, peer_addr, state) -> {bool, new_state}
:ssh.daemon(2222, [
  system_dir: ~c"/path/to/priv/ssh",
  pwdfun: fn user, password, _peer, state ->
    # user and password are charlists from Erlang
    {bool_result, state}
  end,
  key_cb: {MyKeyModule, []},
  ssh_cli: {Raxol.SSH.CLIHandler, [app_module: Foglet.TUI.App]}
])
```

### ssh_server_key_api Behavior
```elixir
# Source: https://www.erlang.org/doc/man/ssh_server_key_api.html
defmodule Foglet.SSH.KeyCB do
  @behaviour :ssh_server_key_api

  @impl true
  # Returns {:ok, private_key} | {:error, reason}
  def host_key(algorithm, opts), do: :ssh_file.host_key(algorithm, opts)

  @impl true
  # Returns boolean
  def is_auth_key(public_key, user, _opts) do
    handle = List.to_string(user)
    # ... match public_key against Foglet.Accounts
  end
end
```

### Raxol View.Elements DSL
```elixir
# Source: Context7 /hydepwns/raxol
import Raxol.View.Elements

view do
  panel title: "Main Menu", border: :single do
    box style: [flex_direction: :column] do
      text content: "[B] Boards", color: :green
      text content: "[Q] Quit",   color: :green
    end
    # Key bar at bottom
    Foglet.TUI.Widgets.KeyBar.render(%{keys: [{"B", "Boards"}, {"Q", "Quit"}]})
  end
end
```

### Raxol multi_line_input for Composer
```elixir
# Source: Context7 /hydepwns/raxol — multi_line_input component
multi_line_input(
  value: state.composer_draft || "",
  width: terminal_cols(state) - 4,
  height: composer_height(state),
  wrap: :word,
  on_change: fn new_text -> send(self(), {:draft_changed, new_text}) end
)
```

### Host Key Directory Bootstrap
```elixir
# priv/ssh/ must exist and have host keys on first boot
# In Foglet.SSH.Supervisor.init/1:
host_keys_dir = Application.app_dir(:foglet_bbs, "priv/ssh")
File.mkdir_p!(host_keys_dir)
# :ssh will auto-generate host keys in system_dir if none exist
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Third-party SSH libs (esshd, sshd_door) | OTP built-in `:ssh` directly | OTP improvements 2020+ | No extra deps; better maintained; official Erlang docs |
| Raxol 0.x (pre-release) | Raxol 2.4.0 (stable) | April 2026 | TEA API stable; SSH integration via CLIHandler confirmed; full widget set available |
| URL-based email verification | Short alphanumeric code (D-08/D-09) | Phase 3 decision | Terminal-native; user types code directly; no browser required |
| `phx.gen.auth` style tokens | Custom `UserToken` patterns | Phase 1 decision | Hand-rolled per CONTEXT 01 D-07; same table repurposed for verify codes |

**Deprecated/outdated:**
- `Raxol.SSH.Server.serve/2` for authenticated applications: use `:ssh.daemon/2` with `Raxol.SSH.CLIHandler` as `ssh_cli` instead.
- OTP versions < 27.3.3: CVE-2025-32433 unauthenticated RCE vulnerability. Never deploy on vulnerable OTP.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Guest registration path uses `no_auth_needed: true` on the daemon, and the TUI login screen is the first gating point (vs. a custom pwdfun that accepts all connections) | Pattern 1, Anti-patterns | If wrong: either unauthenticated connections can't start the TUI, or authenticated users bypass the session layer. Planner must resolve the exact guest-path strategy. |
| A2 | One-session enforcement: Registry `via` collision returns `{:error, {:already_started, old_pid}}` which caller handles by notifying and stopping the old session | Pattern 4 | If wrong: the replacement protocol breaks; could leave orphaned sessions or double-sessions |
| A3 | `priv/ssh/` is on a persistent volume in deployment (i.e., survives OTP releases) | Pattern 3 / Pitfall 3 | If wrong: host keys regenerate on deploy; every user gets MITM-like warning |
| A4 | `Raxol.SSH.CLIHandler`'s `init/1` receives `[app_module: Foglet.TUI.App]` as the opts arg and uses it to start the TEA lifecycle | Pattern 1 code example | If wrong: CLIHandler cannot find the app module; TUI never starts. Planner should verify CLIHandler's init/1 opts signature against source. |

---

## Open Questions

1. **Guest path / no_auth_needed strategy**
   - What we know: Unauthenticated SSH connections must reach the TUI login-or-register screen (D-22). `Raxol.SSH.CLIHandler` starts the TUI app. The daemon must accept the connection without requiring credentials.
   - What's unclear: Should `no_auth_needed: true` be set, making ALL connections unauthenticated (and the TUI handles identity)? Or should the daemon have two layers: `pwdfun` that accepts connections with "guest" as username, and the TUI then shows the login/register choice?
   - Recommendation: `no_auth_needed: true` is the cleanest approach for a BBS — the TUI is the authentication boundary. Session establishment and domain access are gated inside the TUI, not at the SSH daemon level. The `Foglet.Sessions.Session` only gets a real user_id after the TUI completes login. Planner should make this explicit.

2. **Session-to-TUI startup ordering**
   - What we know: CONTEXT.md D-16 says "The Session process then starts a Raxol app via `Raxol.Core.RuntimeApplication` passing initial context." CLIHandler starts a Lifecycle process (per hexdocs for Raxol.SSH.Session).
   - What's unclear: Does `Foglet.Sessions.Session` start the Raxol app as a child, or does `Raxol.SSH.CLIHandler` start the lifecycle automatically and the Session is created lazily from within the TUI?
   - Recommendation: Let `Raxol.SSH.CLIHandler` start the Raxol Lifecycle (it does this automatically). From within the TUI's `init/1` or `update/2`, communicate with `Foglet.Sessions.Session` (get or create). This avoids a circular start dependency.

3. **UserToken table for email verify codes**
   - What we know: `token` column is `:binary`, `context` column is `:string`. Phase 1 stores SHA256 hashes in `token`.
   - What's unclear: Storing plain alphanumeric code as binary vs. adding a separate column.
   - Recommendation: Store plain UTF-8 code as binary in `token` field with `context = "email_verify"`. The binary type accommodates arbitrary bytes. Querying by exact match is efficient. No migration needed for column structure — just new `Foglet.Accounts` functions.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Erlang :ssh (OTP) | SSH-01 through SSH-04 | ✓ | OTP 28.3.1 (ERTS 16.3.1) | — |
| Erlang :public_key (OTP) | SSH-03 pubkey auth | ✓ | OTP 28.3.1 | — |
| Erlang :crypto (OTP) | Verify code generation | ✓ | OTP 28.3.1 | — |
| raxol hex package | D-13, SSH-07 | Not yet installed | 2.4.0 available | — |
| PostgreSQL | Domain data (Phase 2 APIs) | ✓ | Existing (Phase 1/2) | — |
| Phoenix.PubSub | TUI subscriptions | ✓ | Existing in application.ex | — |
| Argon2 | Password auth in pwdfun | ✓ | 4.x (existing dep) | — |

**Missing dependencies with no fallback:**
- `raxol ~> 2.4` — must be added to `mix.exs` deps before Wave 1 tasks begin

**Missing dependencies with fallback:**
- None

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | ExUnit (built-in) |
| Config file | `test/test_helper.exs` (exists) |
| Quick run command | `mix test test/foglet_bbs/tui/ test/foglet_bbs/sessions/ --no-start` |
| Full suite command | `mix test` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SSH-01 | Host key loaded from priv/ssh/ at daemon start | unit | `mix test test/foglet_bbs/ssh/supervisor_test.exs -x` | ❌ Wave 0 |
| SSH-02 | authenticate_by_password/2 called from pwdfun | unit | `mix test test/foglet_bbs/ssh/key_cb_test.exs -x` | ❌ Wave 0 |
| SSH-03 | is_auth_key/3 returns true for registered key | unit | `mix test test/foglet_bbs/ssh/key_cb_test.exs -x` | ❌ Wave 0 |
| SSH-04 | Login-or-register screen shown when no user context | unit | `mix test test/foglet_bbs/tui/app_test.exs -x` | ❌ Wave 0 |
| SSH-05 | Second session for same user_id replaces old session | unit | `mix test test/foglet_bbs/sessions/session_test.exs -x` | ❌ Wave 0 |
| SSH-06 | Model terminal_size updated on :window_change | unit | `mix test test/foglet_bbs/tui/app_test.exs::test_resize -x` | ❌ Wave 0 |
| SSH-07 | Each screen renders without crash given model | unit | `mix test test/foglet_bbs/tui/ -x` | ❌ Wave 0 |
| SSH-08 | Key events dispatch correct update messages | unit | `mix test test/foglet_bbs/tui/app_test.exs -x` | ❌ Wave 0 |
| SSH-09 | Read pointer advances and flushes on screen transition | unit | `mix test test/foglet_bbs/tui/app_test.exs -x` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `mix test test/foglet_bbs/tui/ test/foglet_bbs/sessions/ test/foglet_bbs/ssh/ --no-start`
- **Per wave merge:** `mix test`
- **Phase gate:** Full suite green + `mix precommit` before `/gsd-verify-work`

### Wave 0 Gaps
- [ ] `test/foglet_bbs/ssh/supervisor_test.exs` — covers SSH-01 host key loading
- [ ] `test/foglet_bbs/ssh/key_cb_test.exs` — covers SSH-02, SSH-03 auth callbacks
- [ ] `test/foglet_bbs/sessions/session_test.exs` — covers SSH-05 one-session rule
- [ ] `test/foglet_bbs/sessions/supervisor_test.exs` — covers session lifecycle
- [ ] `test/foglet_bbs/tui/app_test.exs` — covers SSH-04, SSH-06, SSH-07, SSH-08, SSH-09
- [ ] `test/foglet_bbs/tui/screens/` directory — per-screen view tests

---

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | yes | Argon2 password verify (pwdfun), pubkey via ssh_server_key_api |
| V3 Session Management | yes | Registry-based unique session per user; grace window; last_seen_at |
| V4 Access Control | yes | Role check in Session state before domain operations |
| V5 Input Validation | yes | Charlist-to-binary conversion; max_post_length config; handle format validation (Phase 1) |
| V6 Cryptography | yes | :crypto.strong_rand_bytes for verify code; Argon2 for passwords (never hand-roll) |

### Known Threat Patterns for Erlang :ssh + Raxol TUI

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Pre-auth RCE (CVE-2025-32433) | Elevation of Privilege | OTP 28.3.1 — patched. Verify OTP version >= 27.3.3 at startup |
| SSH username enumeration via timing | Information Disclosure | `Argon2.no_user_verify()` called for unknown handles (already in Accounts.authenticate_by_password/2) |
| Host key MITM (key not persisted) | Spoofing | priv/ssh/ on persistent volume; key generated once and reused |
| Brute force password via SSH | Denial of Service | pwdfun_4 state-based delay (timer:sleep) on failure; D-10 rate limiting at Session level |
| Email verify code brute force | Tampering | D-10: max 5 attempts before cooldown; 15-minute expiry; enforced in Session |
| Atom table exhaustion via SSH username | Denial of Service | `List.to_string/1` not `String.to_atom/1` for username conversion (CLAUDE.md) |
| Oversized post body | Tampering/DoS | max_post_length enforced in composer (D-31) before domain call |
| Session hijack via reconnect | Spoofing | Session replacement requires auth to succeed first; old session notified before termination |

---

## Sources

### Primary (HIGH confidence)
- `/hydepwns/raxol` (Context7) — CLIHandler, multi_line_input, update/view callbacks, process_component
- `https://hexdocs.pm/raxol/2.4.0/` — Module listing, SSH.Server, Core.Runtime.Application callbacks
- `https://github.com/DROOdotFOO/raxol/blob/master/lib/raxol/ssh/server.ex` — Confirmed `no_auth_needed: true`, `ssh_cli: {Raxol.SSH.CLIHandler, [...]}`
- `https://github.com/DROOdotFOO/raxol/blob/master/lib/raxol/ssh/cli_handler.ex` — Confirmed `@behaviour :ssh_server_channel`
- `https://www.erlang.org/doc/man/ssh.html` — pwdfun_4, key_cb, ssh_cli options for ssh:daemon/2
- `https://www.erlang.org/doc/man/ssh_server_key_api.html` — host_key/2 and is_auth_key/3 callbacks
- `mix hex.search raxol` (local) — Confirmed raxol 2.4.0 current stable
- `/Users/bfturner/Dev/local/foglet-bbs/priv/repo/migrations/` — user_tokens schema verified (binary token, context string, no token_type column)
- `/Users/bfturner/Dev/local/foglet-bbs/lib/foglet_bbs/accounts.ex` — Existing `authenticate_by_password/2` and `get_user_by_public_key/1` signatures
- OTP 28.3.1 (ERTS 16.3.1) confirmed available via `elixir --version`

### Secondary (MEDIUM confidence)
- `https://hexdocs.pm/raxol/2.4.0/Raxol.SSH.Session.html` — Session spawned per connection, routes I/O through IOAdapter
- `https://hexdocs.pm/raxol/2.4.0/Raxol.SSH.Server.html` — Options: port, host_keys_dir, max_connections

### Tertiary (LOW confidence)
- Elixir Observer (`elixir-observer.com/packages/raxol`) — Version history cross-reference

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — Raxol 2.4.0 confirmed on Hex; OTP :ssh verified in mix.exs extra_applications; all Phase 1/2 deps verified in place
- Architecture: HIGH — CLIHandler behavior verified from source; pwdfun/key_cb Erlang API verified from official docs; existing accounts API verified from source
- Pitfalls: HIGH — CVE verified from NVD and multiple sources; charlist pitfall from Erlang docs; UserToken schema from actual migration file

**Research date:** 2026-04-18
**Valid until:** 2026-05-18 (Raxol 2.4.x minor bumps unlikely to break API; OTP stable)
