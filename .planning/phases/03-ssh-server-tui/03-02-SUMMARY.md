---
plan: 03-02
phase: 03-ssh-server-tui
status: complete
completed_at: 2026-04-18
---

# Plan 03-02 Summary: Sessions Layer + SSH Daemon

## What Was Built

Added the OTP backbone for Phase 3: the Sessions layer (Registry + DynamicSupervisor + Session GenServer with one-session-per-user replacement) and the SSH daemon layer (Supervisor wrapping :ssh.daemon/2 with KeyCB, pwdfun, Raxol CLIHandler). All 29 Wave-0 stubs for sessions and SSH replaced with green assertions.

## Key Deliverables

### Sessions Layer

- `Foglet.Sessions.Registry` — OTP Registry (`keys: :unique`) added to `FogletBbs.Application` supervision tree
- `Foglet.Sessions.Session` — per-user GenServer with `restart: :temporary` registered via `via_tuple/1`; state: `user_id, handle, role, terminal_size, connected_at, last_seen_at, tui_pid`; replacement protocol via `handle_info(:replaced_by_new_session)` → `{:stop, :normal}`
- `Foglet.Sessions.Supervisor` — DynamicSupervisor with `start_session/1` (replacement-safe), `terminate_session/1`, `lookup_session/1`; `replace/2` uses `Process.monitor` + `receive after 2_000` fallback; `start_or_adopt/1` handles concurrent race (TOCTOU-safe)

### SSH Daemon Layer

- `Foglet.SSH.KeyCB` — implements `@behaviour :ssh_server_key_api`; `host_key/2` delegates to `:ssh_file.host_key/2`; `is_auth_key/3` converts charlist via `List.to_string/1` (Pitfall 2), encodes public key via `:ssh_file.encode/2` with `:openssh_key` atom (OTP 28 confirmed), delegates fingerprint lookup to `Foglet.Accounts.get_user_by_public_key/1`
- `Foglet.SSH.Supervisor` — `use Supervisor`; `init/1` calls `assert_safe_otp_version!/0` (CVE-2025-32433 guard, Pitfall 7), `ensure_system_dir!/0` (creates `priv/ssh/`), `:ssh.daemon(port, daemon_opts)`; `daemon_opts/1` exposed for tests
- `daemon_opts/1` literal content:
  ```elixir
  [
    system_dir: String.to_charlist(system_dir),
    no_auth_needed: true,
    pwdfun: &__MODULE__.pwdfun/4,
    key_cb: {Foglet.SSH.KeyCB, [system_dir: String.to_charlist(system_dir)]},
    ssh_cli: {Raxol.SSH.CLIHandler, [app_module: Foglet.TUI.App]},
    max_sessions: 500,
    parallel_login: true
  ]
  ```
- `pwdfun/4` handles both password auth (`authenticate_by_password/2`, only accepts `status: :active`) and `:pubkey` form (confirms handle exists and is not deleted)

### Application Wiring

- `FogletBbs.Application` refactored into `base_children/0` + `ssh_children/0`; SSH daemon conditional on `Application.get_env(:foglet_bbs, :start_ssh_daemon, true)`
- Boot order: Repo → PubSub → BoardRegistry → Boards.Supervisor → Sessions.Registry → Sessions.Supervisor → Endpoint → (SSH.Supervisor if enabled)

### Configuration

- `config/config.exs` — `:ssh_port, 2222` and `:start_ssh_daemon, true`
- `config/test.exs` — `:start_ssh_daemon, false` (daemon never binds port in tests)
- `config/runtime.exs` — `FOGLET_SSH_PORT` env var override
- `.gitignore` — `priv/ssh/*` / `!priv/ssh/.gitkeep` pattern
- `priv/ssh/.gitkeep` created

## Test Results

- **17 SSH tests** green (key_cb: 6, supervisor daemon_opts: 5, supervisor pwdfun: 4, config: 2)
- **12 Sessions tests** green (session: 6, supervisor: 6)
- **178 total tests + 1 property passing**, 0 failures, 63 excluded (TUI Wave-0 stubs)

## OTP Version Guard

Running on OTP 28 / ERTS 16.x. The ERTS major-version heuristic (`>= 14`) maps to `@min_otp_version` ("27.3.3"), so the comparison passes. Confirmed by `Logger.debug("OTP version check passed...")` firing in dev.

## `:ssh_file.encode/2` Atom Confirmed

`:openssh_key` is the correct atom on OTP 28. `:public_key` raises `ArgumentError`. The round-trip `decode → encode(:openssh_key) → compute_fingerprint` produces an identical fingerprint to the original key text (trailing comment is stripped by encode but fingerprint is unaffected).

## Static Ed25519 Test Key

Used the existing `FogletBbs.AccountsFixtures.default_ssh_public_key/0` fixture key (`ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGk+NU...`). No need for `ssh-keygen` — `:ssh_file.decode/2` parses it cleanly on OTP 28. No dynamic key generation required.

## Deviations

- **`restart: :temporary` on Session** — not explicitly stated in plan but required: without it, `DynamicSupervisor` would restart a `:permanent` child on any exit (including `:normal`), causing the registry entry to re-appear after `terminate_child`. Setting `use GenServer, restart: :temporary` fixes this.
- **`start_or_adopt/1` helper** — added to `Foglet.Sessions.Supervisor.replace/2` to handle the concurrent-replacement race: if the second `start_child` after waiting for DOWN returns `{:already_started, pid}`, that pid is adopted rather than treating it as an error.
- **Registry drain in supervisor test** — after `terminate_session`, `_ = :sys.get_state(Foglet.Sessions.Registry)` added before the `lookup_session` assertion to drain the Registry's mailbox, preventing flaky assertions due to asynchronous Registry unregistration.
- **Concurrent test drain loop** — replaced `Process.sleep(100)` with a `Process.monitor` drain loop over all returned pids to wait for intermediate replaced sessions to die before asserting one survivor. The `Process.sleep(100)` was insufficient and caused ~30% flakiness across 50 runs.

## Self-Check: PASSED

- `grep '@behaviour :ssh_server_key_api' lib/foglet_bbs/ssh/key_cb.ex` — matches
- `grep 'no_auth_needed: true' lib/foglet_bbs/ssh/supervisor.ex` — matches
- `grep 'Raxol.SSH.CLIHandler' lib/foglet_bbs/ssh/supervisor.ex` — matches
- `grep ':ssh.daemon(' lib/foglet_bbs/ssh/supervisor.ex` — matches
- `grep 'List.to_string(user)' lib/foglet_bbs/ssh/key_cb.ex` — matches
- `grep 'Foglet.Sessions.Registry' lib/foglet_bbs/application.ex` — matches
- `grep 'Foglet.Sessions.Supervisor' lib/foglet_bbs/application.ex` — matches
- `grep 'ssh_children' lib/foglet_bbs/application.ex` — matches
- `grep 'start_ssh_daemon, false' config/test.exs` — matches
- `grep 'FOGLET_SSH_PORT' config/runtime.exs` — matches
- `grep 'priv/ssh' .gitignore` — matches
- `[[ -f priv/ssh/.gitkeep ]]` — exits 0
- `mix test test/foglet_bbs/ssh/` — 17 tests, 0 failures
- `mix test test/foglet_bbs/sessions/` — 12 tests, 0 failures (stable across 50 runs)
- `mix test` — 178 tests + 1 property, 0 failures
- `mix precommit` — exits 0
