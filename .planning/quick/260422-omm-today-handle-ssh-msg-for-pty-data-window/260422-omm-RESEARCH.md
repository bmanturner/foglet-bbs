# Quick Task 260422-omm: SSH CLIHandler Integration Coverage - Research

**Researched:** 2026-04-22
**Domain:** Erlang `:ssh` channel integration tests for Phoenix/Elixir ExUnit
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

Use a real in-process `:ssh.daemon` + `:ssh.connect` harness where feasible. Direct callback tests with fakes are acceptable only for behavior that cannot be observed reliably through the real client.

Split coverage by behavior so failures point at the specific channel path: `:pty`, `:data`, `:window_change`, `:eof`, `:closed`, `{:EXIT, ...}`, CRLF normalization, and alt-screen restoration.

Assert both externally visible terminal bytes and internal lifecycle/session effects where practical. Prefer raw SSH channel output for terminal protocol behavior and process/session state for lifecycle behavior.

Keep production changes minimal. This is primarily a test coverage task; production code should change only if the new tests expose an actual defect or if tiny test seams are necessary.

Prefer deterministic synchronization (`monitor` / `assert_receive` / `:sys.get_state`) over sleeps.

Use `start_supervised!/1` for test-owned processes.

### Claude's Discretion

Choose the split between real SSH harness tests and direct callback tests based on observability and determinism.

### Deferred Ideas (OUT OF SCOPE)

Do not redesign SSH authentication or connection lifecycle beyond defects exposed by these tests.
</user_constraints>

## Summary

Use a hybrid test strategy: a real in-process Erlang SSH daemon/client for externally visible terminal protocol behavior, and direct callback tests for callback-only paths that Erlang's client API cannot generate or cannot observe deterministically. [VERIFIED: CONTEXT.md] [CITED: https://www.erlang.org/docs/28/apps/ssh/ssh_connection]

The real harness should start `Foglet.SSH.RateLimiter`, initialize `Foglet.SSH.CLIHandler`'s ETS counter, start `Foglet.SSH.DaemonOwner` on port `0` with a temporary host-key directory, discover the chosen port via `:ssh.daemon_info/1`, connect with `:ssh.connect/4`, open a session channel, allocate a PTY, and request a shell. [VERIFIED: lib/foglet_bbs/ssh/cli_handler.ex] [VERIFIED: lib/foglet_bbs/ssh/daemon_owner.ex] [CITED: https://www.erlang.org/doc/apps/ssh/ssh.html]

Primary recommendation: implement real SSH tests for `:pty`, EOF alt-screen LEAVE, CRLF normalization, and basic close behavior; implement direct callback tests for `:data` dispatch, `:window_change` session resize, `:closed` session cleanup, and `handle_msg({:EXIT, ...})`. [VERIFIED: lib/foglet_bbs/ssh/cli_handler.ex] [CITED: https://www.erlang.org/docs/28/apps/ssh/ssh_connection]

## Project Constraints (from CLAUDE.md)

- Run `mix precommit` after changes and fix pending issues. [VERIFIED: CLAUDE.md]
- Use `start_supervised!/1` for test-owned processes. [VERIFIED: CLAUDE.md]
- Avoid `Process.sleep/1` and `Process.alive?/1` in tests; synchronize with monitors, `assert_receive`, and `:sys.get_state/1`. [VERIFIED: CLAUDE.md]
- Do not add HTTP or date/time dependencies for this task. [VERIFIED: CLAUDE.md]
- Do not nest multiple modules in the same file; any test fake module should live in its own `test/support/...` file. [VERIFIED: CLAUDE.md]
- Run single test files with `mix test path/to/test.exs`; rerun failures with `mix test --failed`. [VERIFIED: CLAUDE.md]

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|--------------|----------------|-----------|
| SSH channel event handling | SSH server/channel process | TUI Lifecycle | `Foglet.SSH.CLIHandler` owns SSH callbacks and forwards terminal events to Raxol Lifecycle. [VERIFIED: lib/foglet_bbs/ssh/cli_handler.ex] |
| Terminal output bytes | SSH server/channel process | Raxol renderer | CLIHandler wraps the IO writer to normalize LF to CRLF and sends alt-screen LEAVE directly on disconnect. [VERIFIED: lib/foglet_bbs/ssh/cli_handler.ex] |
| Terminal resize state | SSH channel process | Session process | `:window_change` dispatches a resize event and updates `Sessions.Session` terminal size. [VERIFIED: lib/foglet_bbs/ssh/cli_handler.ex] |
| Test daemon lifecycle | ExUnit process | Erlang `:ssh` app | Tests should own daemon startup/shutdown with `start_supervised!/1` or `on_exit/1`. [VERIFIED: CLAUDE.md] [CITED: https://www.erlang.org/doc/apps/ssh/ssh.html] |

## Standard Stack

| Tool/Library | Version | Purpose | Source |
|--------------|---------|---------|--------|
| Erlang/OTP `:ssh` | OTP 28, ssh app docs v5.3.3-v5.5.2 | In-process daemon/client/channel API. | [VERIFIED: `elixir -v`] [CITED: https://www.erlang.org/docs/28/apps/ssh/ssh_connection] |
| Elixir ExUnit | Elixir 1.19.5 | Test framework. | [VERIFIED: `elixir -v`] |
| Raxol | 2.4.0 | TUI Lifecycle/rendering dependency used by CLIHandler. | [VERIFIED: mix.lock] |
| OpenSSH `ssh-keygen` | present at `/usr/bin/ssh-keygen` | Generate temporary daemon host keys for tests. | [VERIFIED: `command -v ssh-keygen`] [CITED: https://www.erlang.org/doc/apps/ssh/ssh_file.html] |

No new dependencies are needed. [VERIFIED: mix.exs] [VERIFIED: config/test.exs]

## Concrete Test Harness

Recommended setup per SSH integration test module:

```elixir
use FogletBbs.DataCase, async: false

setup do
  Foglet.SSH.CLIHandler.init_counter()

  host_dir = tmp_host_key_dir!()
  start_supervised!({Foglet.SSH.RateLimiter, clean_period: :timer.minutes(10)})

  daemon_opts = Foglet.SSH.Supervisor.daemon_opts(host_dir)
  daemon_pid = start_supervised!({Foglet.SSH.DaemonOwner, port: 0, daemon_opts: daemon_opts})

  %{daemon_ref: daemon_ref} = :sys.get_state(daemon_pid)
  {:ok, daemon_info} = :ssh.daemon_info(daemon_ref)
  {:port, port} = List.keyfind(daemon_info, :port, 0)

  {:ok, conn} =
    :ssh.connect(~c"127.0.0.1", port,
      [
        user: ~c"test",
        user_interaction: false,
        silently_accept_hosts: true,
        save_accepted_host: false
      ],
      5_000
    )

  on_exit(fn -> :ssh.close(conn) end)
  {:ok, conn: conn}
end
```

Source rationale: `:ssh.daemon/3` accepts port `0` and exposes the selected port through daemon info. [CITED: https://www.erlang.org/doc/apps/ssh/ssh.html] Client connections start no channel until `:ssh_connection.session_channel/2,4` is called. [CITED: https://www.erlang.org/doc/apps/ssh/ssh.html] Host key files are required in `system_dir`; Erlang docs list `ssh_host_ed25519_key` as a valid daemon host key file. [CITED: https://www.erlang.org/doc/apps/ssh/ssh_file.html]

Recommended channel open helper:

```elixir
{:ok, channel_id} = :ssh_connection.session_channel(conn, 5_000)

assert :success =
         :ssh_connection.ptty_alloc(
           conn,
           channel_id,
           [term: ~c"xterm-256color", width: 80, height: 24, pty_opts: []],
           5_000
         )

assert :ok = :ssh_connection.shell(conn, channel_id)
```

Source rationale: `ptty_alloc/4` sends a PTY request with `term`, `width`, `height`, and `pty_opts`; `shell/2` requests a shell; channel output arrives as `{:ssh_cm, conn, {:data, channel_id, 0, data}}`. [CITED: https://www.erlang.org/docs/28/apps/ssh/ssh_connection]

## Test Coverage Map

| Behavior | Best Test Style | Concrete Assertion |
|----------|-----------------|--------------------|
| `:pty` | Real SSH harness | `ptty_alloc/4` succeeds and initial output includes alt-screen ENTER `"\e[?1049h"`. [VERIFIED: lib/foglet_bbs/ssh/cli_handler.ex] |
| CRLF normalization | Real SSH harness | Captured initial terminal output contains `"\r\n"` and no bare `"\n"` with a regex such as `~r/(?<!\r)\n/`. [VERIFIED: lib/foglet_bbs/ssh/cli_handler.ex] |
| `:eof` alt-screen LEAVE | Real SSH harness | After `:ssh_connection.send_eof(conn, channel_id)`, captured data contains `"\e[?1049l"`. [VERIFIED: lib/foglet_bbs/ssh/cli_handler.ex] [CITED: https://www.erlang.org/docs/28/apps/ssh/ssh_connection] |
| `:data` | Direct callback with fake Lifecycle | Fake Lifecycle returns `%{dispatcher_pid: test_pid}` for `:get_full_state`; assert the test process receives `:"$gen_cast", {:dispatch, event}` after `handle_ssh_msg({:data, ...})`. [VERIFIED: lib/foglet_bbs/ssh/cli_handler.ex] |
| `:window_change` | Direct callback with fake Lifecycle plus real Session | Assert returned state width/height, dispatcher receives resize event, and `Sessions.Session.get_state(session_pid).terminal_size` eventually equals the new size. [VERIFIED: lib/foglet_bbs/ssh/cli_handler.ex] |
| `:closed` | Direct callback plus optional real SSH close smoke | Monitor a guest session pid, call `handle_ssh_msg({:closed, ...})`, assert `{:stop, channel_id, state}` and `:DOWN`. [VERIFIED: lib/foglet_bbs/ssh/cli_handler.ex] |
| `{:EXIT, lifecycle_pid, reason}` | Direct callback | Call `handle_msg/2` with matching `lifecycle_pid`; assert it returns `{:stop, channel_id, state}` without raising when connection/channel are nil. [VERIFIED: lib/foglet_bbs/ssh/cli_handler.ex] |

## Key Pitfalls

### Missing `reply_request/4` for PTY/Shell WantReply

What goes wrong: the real client may hang or return failure from `ptty_alloc/4` or `shell/2` if the server channel does not reply to requests that ask for a status. [CITED: https://www.erlang.org/docs/28/apps/ssh/ssh_connection]

Why it happens: OTP docs say `WantReply` requests expect `ssh_connection:reply_request/4`; current `CLIHandler` ignores `_want_reply` in both `:pty` and `:shell` handlers. [CITED: https://www.erlang.org/docs/28/apps/ssh/ssh_connection] [VERIFIED: lib/foglet_bbs/ssh/cli_handler.ex]

Recommendation: let the real harness expose this. If it fails, the minimal production fix is to reply `:success` in `:pty` and `:shell` handlers before/after successful handling. [ASSUMED]

### Host Keys

What goes wrong: daemon startup fails or first connection fails if `system_dir` exists but contains no valid host key. [VERIFIED: lib/foglet_bbs/ssh/daemon_owner.ex] [CITED: https://www.erlang.org/doc/apps/ssh/ssh_file.html]

Recommendation: create a temp directory per test and generate `ssh_host_ed25519_key` with `ssh-keygen -t ed25519 -f path -N ""`; clean it with `on_exit/1`. [VERIFIED: `command -v ssh-keygen`] [CITED: https://www.erlang.org/doc/apps/ssh/ssh_file.html]

### `no_auth_needed: true`

What goes wrong: tests may accidentally assume SSH-layer password/key authentication. Foglet accepts at the SSH protocol layer and resolves identity inside the TUI/session path. [VERIFIED: lib/foglet_bbs/ssh/supervisor.ex] [VERIFIED: .planning/codebase/CONCERNS.md]

Recommendation: connect as an anonymous test user with `user_interaction: false`, `silently_accept_hosts: true`, and no password. [CITED: https://www.erlang.org/doc/apps/ssh/ssh.html]

### Window Change API Gap

What goes wrong: Erlang `:ssh_connection` has `ptty_alloc/4`, but the docs state no API function generates `window_change_ch_msg()`. [CITED: https://www.erlang.org/docs/28/apps/ssh/ssh_connection]

Recommendation: test `:window_change` through direct `CLIHandler.handle_ssh_msg/2`, not through the real Erlang client. [VERIFIED: lib/foglet_bbs/ssh/cli_handler.ex]

### DB Sandbox Ownership

What goes wrong: SSH channel processes can run outside the test process; if they touch Repo while the test is `async: true`, sandbox ownership errors can occur. [VERIFIED: test/support/data_case.ex]

Recommendation: make `CLIHandlerTest` `async: false` so `DataCase` starts the SQL sandbox owner in shared mode. Guest SSH paths should still avoid DB where possible. [VERIFIED: test/support/data_case.ex] [VERIFIED: lib/foglet_bbs/ssh/cli_handler.ex]

### Global Names and ETS Tables

What goes wrong: `Foglet.SSH.DaemonOwner`, `Foglet.SSH.RateLimiter`, and `CLIHandler`'s named ETS counter are VM-global, so tests must not run concurrently. [VERIFIED: lib/foglet_bbs/ssh/daemon_owner.ex] [VERIFIED: lib/foglet_bbs/ssh/rate_limiter.ex] [VERIFIED: lib/foglet_bbs/ssh/cli_handler.ex]

Recommendation: use `async: false`, initialize the counter in per-test setup, and let ExUnit stop supervised children. [VERIFIED: CLAUDE.md]

## Production Seams

Avoid production seams initially. `Supervisor.daemon_opts/1`, `DaemonOwner`, direct public callbacks, and `start_supervised!/1` are enough to build the tests. [VERIFIED: lib/foglet_bbs/ssh/supervisor.ex] [VERIFIED: lib/foglet_bbs/ssh/daemon_owner.ex] [VERIFIED: lib/foglet_bbs/ssh/cli_handler.ex]

A small production change is justified only if the real harness exposes the missing `reply_request/4` issue for PTY or shell requests. [CITED: https://www.erlang.org/docs/28/apps/ssh/ssh_connection] [VERIFIED: lib/foglet_bbs/ssh/cli_handler.ex]

If a fake Lifecycle is needed, put it in a separate `test/support/...` file rather than nesting another module inside `cli_handler_test.exs`. [VERIFIED: CLAUDE.md]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| SSH protocol simulation | Fake `{:ssh_cm, ...}` for every path | Real `:ssh.daemon` + `:ssh.connect` for terminal-byte behavior | Exercises actual OTP channel wiring. [CITED: https://www.erlang.org/docs/28/apps/ssh/ssh_connection] |
| Terminal output timing | `Process.sleep/1` waits | `assert_receive`, recursive receive loops with bounded timeouts, monitors | Matches project test rules and avoids flaky waits. [VERIFIED: CLAUDE.md] |
| Host key parsing | Custom key files | `ssh-keygen` temporary `ssh_host_ed25519_key` | OTP docs explicitly support OpenSSH-compatible host key files. [CITED: https://www.erlang.org/doc/apps/ssh/ssh_file.html] |

## Validation Architecture

| Property | Value |
|----------|-------|
| Framework | ExUnit, Elixir 1.19.5. [VERIFIED: `elixir -v`] |
| Config | `test/test_helper.exs` starts ExUnit and sets SQL sandbox manual mode. [VERIFIED: test/test_helper.exs] |
| Target file | `test/foglet_bbs/ssh/cli_handler_test.exs`. [VERIFIED: test/foglet_bbs/ssh/cli_handler_test.exs] |
| Quick run | `mix test test/foglet_bbs/ssh/cli_handler_test.exs`. [VERIFIED: CLAUDE.md] |
| Rerun failures | `mix test --failed`. [VERIFIED: CLAUDE.md] |
| Phase gate | `mix precommit`. [VERIFIED: CLAUDE.md] |

Notes: `mix test --help` is not a valid option in this project environment; Mix reported "Unknown option". [VERIFIED: command output] A Codex sandbox run of Mix required escalation because Mix PubSub could not open a local TCP socket under sandbox restrictions. [VERIFIED: command output]

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| Erlang/OTP | SSH daemon/client tests | yes | OTP 28 / ERTS 16.3.1 | none needed. [VERIFIED: `elixir -v`] |
| Elixir | ExUnit tests | yes | 1.19.5 | none needed. [VERIFIED: `elixir -v`] |
| OpenSSH `ssh-keygen` | Temporary host keys | yes | present at `/usr/bin/ssh-keygen` | commit a test fixture key only if CI lacks `ssh-keygen`. [VERIFIED: `command -v ssh-keygen`] |
| OpenSSH `ssh` | Optional manual debugging only | yes | OpenSSH_10.2p1 | Erlang `:ssh.connect` is primary. [VERIFIED: `ssh -V`] |
| `nc` | Optional port/debug checks | yes | present at `/usr/bin/nc` | not needed for automated tests. [VERIFIED: `command -v nc`] |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Replying `:success` in PTY and shell handlers is the minimal production fix if real client requests fail. | Key Pitfalls / Production Seams | Planner may under-scope a production fix if OTP server-channel behavior auto-replies in this specific callback path. |

## Open Questions

1. Does OTP's `:ssh_server_channel` behavior auto-reply for `:pty` or `:shell` despite `ssh_connection` docs requiring `reply_request/4`? [CITED: https://www.erlang.org/docs/28/apps/ssh/ssh_connection]
   - What we know: docs require replies for `WantReply`; current handler does not call `reply_request/4`. [CITED: https://www.erlang.org/docs/28/apps/ssh/ssh_connection] [VERIFIED: lib/foglet_bbs/ssh/cli_handler.ex]
   - Recommendation: write the real `ptty_alloc/4` test first and treat failure as an implementation defect. [ASSUMED]

## Sources

### Primary

- `260422-omm-CONTEXT.md` - locked user decisions and scope. [VERIFIED]
- `CLAUDE.md` - project test and coding constraints. [VERIFIED]
- `lib/foglet_bbs/ssh/cli_handler.ex` - callback behavior under test. [VERIFIED]
- `lib/foglet_bbs/ssh/supervisor.ex` - daemon options and `no_auth_needed`. [VERIFIED]
- `lib/foglet_bbs/ssh/daemon_owner.ex` - daemon lifecycle and host key validation. [VERIFIED]
- `test/foglet_bbs/ssh/cli_handler_test.exs` - current coverage gap. [VERIFIED]
- `test/support/data_case.ex` and `test/test_helper.exs` - sandbox and ExUnit setup. [VERIFIED]
- Erlang OTP SSH docs: `ssh`, `ssh_connection`, `ssh_file`. [CITED: https://www.erlang.org/doc/apps/ssh/ssh.html] [CITED: https://www.erlang.org/docs/28/apps/ssh/ssh_connection] [CITED: https://www.erlang.org/doc/apps/ssh/ssh_file.html]

### Secondary

- `.planning/codebase/CONCERNS.md` - confirms SSH channel lifecycle coverage gap and `no_auth_needed` security note. [VERIFIED]
- `docs/ARCHITECTURE.md` section 7 - SSH layer expectations for host keys, PTY sizing, and window-change behavior. [VERIFIED]

## Metadata

**Confidence breakdown:**
- Harness: HIGH - confirmed against local code and OTP docs.
- Coverage split: HIGH - directly mapped to observability limits in OTP client API.
- Production seam guidance: MEDIUM - likely issue around `reply_request/4` needs confirmation by the first real harness test.

**Valid until:** 2026-05-22 for local project patterns; re-check OTP docs when upgrading Erlang/OTP.
