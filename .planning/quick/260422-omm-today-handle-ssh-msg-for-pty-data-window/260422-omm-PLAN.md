---
phase: quick-260422-omm
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - test/foglet_bbs/ssh/cli_handler_test.exs
  - lib/foglet_bbs/ssh/cli_handler.ex
  - .planning/quick/260422-omm-today-handle-ssh-msg-for-pty-data-window/260422-omm-SUMMARY.md
  - .planning/quick/260422-omm-today-handle-ssh-msg-for-pty-data-window/260422-omm-VERIFICATION.md
  - .planning/STATE.md
autonomous: true
requirements:
  - "Add CLIHandler handle_ssh_msg coverage for :pty, :data, :window_change, :eof, :closed, alt-screen LEAVE, CRLF normalization, and lifecycle EXIT crash handling"
status: ready
mode: quick-full
must_haves:
  truths:
    - "A real in-process :ssh daemon/client test exercises CLIHandler PTY and shell startup, and fails specifically if request replies are missing."
    - "Raw SSH channel output proves alternate-screen ENTER on PTY startup, alternate-screen LEAVE on EOF/close paths, and CRLF-normalized terminal output."
    - "Direct callback tests cover :data, :window_change, :closed, and handle_msg({:EXIT, ...}) with lifecycle/session effects asserted."
    - "Coverage is split by behavior so failures identify the specific SSH channel path: :pty, :data, :window_change, :eof, :closed, CRLF, alt-screen LEAVE, or lifecycle EXIT."
    - "Production changes are limited to the smallest fix required by the new tests, especially :ssh_connection.reply_request/4 for PTY/shell if the real harness exposes it."
  artifacts:
    - path: "test/foglet_bbs/ssh/cli_handler_test.exs"
      provides: "Behavior-split SSH CLIHandler tests using real daemon/client and direct callbacks"
    - path: "lib/foglet_bbs/ssh/cli_handler.ex"
      provides: "Production SSH channel handler; only changed if PTY/shell request replies are required"
      contains: "handle_ssh_msg"
    - path: ".planning/quick/260422-omm-today-handle-ssh-msg-for-pty-data-window/260422-omm-CONTEXT.md"
      provides: "Locked user decisions"
    - path: ".planning/quick/260422-omm-today-handle-ssh-msg-for-pty-data-window/260422-omm-RESEARCH.md"
      provides: "SSH harness research and coverage split"
  key_links:
    - from: "test/foglet_bbs/ssh/cli_handler_test.exs"
      to: "lib/foglet_bbs/ssh/supervisor.ex"
      via: "Foglet.SSH.Supervisor.daemon_opts/1 used to start test daemon"
      pattern: "daemon_opts"
    - from: "test/foglet_bbs/ssh/cli_handler_test.exs"
      to: "lib/foglet_bbs/ssh/daemon_owner.ex"
      via: "Foglet.SSH.DaemonOwner started on port 0 with temporary host keys"
      pattern: "DaemonOwner"
    - from: "test/foglet_bbs/ssh/cli_handler_test.exs"
      to: "lib/foglet_bbs/ssh/cli_handler.ex"
      via: "Real harness reads raw {:ssh_cm, conn, {:data, channel_id, 0, bytes}} emitted by CLIHandler"
      pattern: "handle_ssh_msg"
    - from: "test/foglet_bbs/ssh/cli_handler_test.exs"
      to: "lib/foglet_bbs/ssh/cli_handler.ex"
      via: "PTY/shell tests exercise existing want_reply callback parameters and require reply_request/4 only if the real client exposes the missing-reply defect"
      pattern: "want_reply"
---

# Quick Task 260422-omm: Plan

## Goal

Add focused tests for `Foglet.SSH.CLIHandler` SSH channel message handling, using a real in-process Erlang SSH daemon/client where feasible and direct callback tests where the client API cannot deterministically produce or observe the event.

Locked decisions covered: real in-process `:ssh` daemon/client harness where feasible; split coverage by behavior; assert raw terminal bytes and lifecycle/session effects where practical.

## Source Audit

- GOAL: Add tests for `handle_ssh_msg/2` paths `:pty`, `:data`, `:window_change`, `:eof`, `:closed`, alt-screen LEAVE, CRLF normalization, and `handle_msg({:EXIT, ...})` crash handling. Covered by Tasks 1-3.
- CONTEXT: Use real daemon/client harness where feasible. Covered by Task 1.
- CONTEXT: Direct callback tests acceptable only for behavior not reliably observable through real client. Covered by Task 2.
- CONTEXT: Split coverage by behavior. Covered by Task 3's test organization requirement.
- CONTEXT: Assert raw terminal bytes and lifecycle/session effects where practical. Covered by Tasks 1 and 2.
- RESEARCH: Account for likely missing `:ssh_connection.reply_request/4` in PTY/shell handlers. Covered by Task 1.
- RESEARCH: Use deterministic synchronization and `start_supervised!/1`; avoid `Process.sleep/1`. Covered by Tasks 1 and 2.
- RESEARCH: Keep production changes minimal; no new dependencies. Covered by all tasks.

<tasks>

<task type="auto">
  <name>Task 1: Build real SSH harness tests for PTY, shell startup, CRLF, EOF, and alt-screen bytes</name>
  <files>test/foglet_bbs/ssh/cli_handler_test.exs, lib/foglet_bbs/ssh/cli_handler.ex</files>
  <action>
Convert `Foglet.SSH.CLIHandlerTest` to `use FogletBbs.DataCase, async: false` because the SSH daemon, CLIHandler counter ETS table, and RateLimiter are VM-global and the real SSH channel process may touch session state outside the test process. Keep the existing pubkey/context tests.

Add helpers inside `test/foglet_bbs/ssh/cli_handler_test.exs`: `tmp_host_key_dir!/0` creates a unique `System.tmp_dir!()` directory, runs `System.cmd("ssh-keygen", ["-t", "ed25519", "-f", Path.join(dir, "ssh_host_ed25519_key"), "-N", ""])`, and cleans up with `on_exit/1`; `start_test_daemon!/0` calls `Foglet.SSH.CLIHandler.init_counter()`, starts `Foglet.SSH.RateLimiter` with `start_supervised!/1`, starts `Foglet.SSH.DaemonOwner` on port `0` with `Foglet.SSH.Supervisor.daemon_opts(host_dir)`, reads `%{daemon_ref: daemon_ref}` via `:sys.get_state/1`, and discovers the selected port via `:ssh.daemon_info/1`; `connect_client!/1` connects to `~c"127.0.0.1"` with `:ssh.connect/4`, `user: ~c"test"`, `user_interaction: false`, `silently_accept_hosts: true`, and `save_accepted_host: false`; `open_shell!/1` opens a session channel, calls `:ssh_connection.ptty_alloc(conn, channel_id, [term: ~c"xterm-256color", width: 80, height: 24, pty_opts: []], 5_000)`, then `:ssh_connection.shell(conn, channel_id)`; `collect_channel_bytes/3` recursively receives `{:ssh_cm, conn, {:data, channel_id, 0, data}}` until a predicate matches or a bounded timeout expires.

Add separate tests: PTY/shell startup asserts `ptty_alloc/4` returns `:success`, `shell/2` returns `:ok`, and collected bytes include alternate-screen ENTER `"\e[?1049h"`; CRLF normalization asserts collected initial terminal bytes contain `"\r\n"` and do not match `~r/(?<!\r)\n/`; EOF alt-screen LEAVE sends `:ssh_connection.send_eof(conn, channel_id)` and asserts collected bytes include `"\e[?1049l"`.

If `ptty_alloc/4` or `shell/2` fails or times out because the server ignored `want_reply`, make the smallest production fix in `lib/foglet_bbs/ssh/cli_handler.ex`: bind `want_reply` in the existing `:pty` and `:shell` clauses and call `:ssh_connection.reply_request(connection_ref, want_reply, :success, channel_id)` after successful handling. Do not otherwise redesign channel startup.
  </action>
  <verify>
    <automated>mix test test/foglet_bbs/ssh/cli_handler_test.exs</automated>
  </verify>
  <done>Real `:ssh.daemon` + `:ssh.connect` tests pass and assert raw SSH channel bytes for PTY startup, CRLF normalization, and EOF alt-screen LEAVE. Any production edit is limited to PTY/shell request replies required by the real harness.</done>
</task>

<task type="auto">
  <name>Task 2: Add direct callback tests for data dispatch, window changes, closed cleanup, and lifecycle EXIT</name>
  <files>test/foglet_bbs/ssh/cli_handler_test.exs</files>
  <action>
Add direct callback tests where the Erlang client API cannot deterministically generate or expose the exact server callback path. Use small test-owned processes rather than nested fake modules.

For `:data`, start a lightweight process in the test that responds to `GenServer.call(pid, :get_full_state)` with `%{dispatcher_pid: dispatcher_pid}`. Call `Foglet.SSH.CLIHandler.handle_ssh_msg({:ssh_cm, make_ref(), {:data, 1, 0, input_bytes}}, state)` with `state.lifecycle_pid` set to that process. Assert the dispatcher receives `:"$gen_cast", {:dispatch, event}` messages produced by `Raxol.SSH.IOAdapter.parse_input/1`.

For `:window_change`, start a real guest session with `Foglet.Sessions.Supervisor.start_guest_session/0`, use the same fake lifecycle full-state responder, call the `{:window_change, channel_id, width, height, 0, 0}` callback, assert returned state has `width` and `height`, assert a resize dispatch is sent, then synchronize with `_ = :sys.get_state(session_pid)` and assert `Foglet.Sessions.Session.get_state(session_pid).terminal_size == {width, height}`.

For `:closed`, start a real guest session, monitor it, call the `{:closed, channel_id}` callback with `connection_ref: nil`, assert `{:stop, channel_id, returned_state}`, and assert the session process exits using a monitor and `assert_receive {:DOWN, ref, :process, session_pid, _}`.

For `handle_msg({:EXIT, lifecycle_pid, reason}, state)`, call with matching `lifecycle_pid` and `connection_ref: nil`; assert it returns `{:stop, channel_id_or_zero, state}` without raising. Include a separate assertion that non-matching `{:EXIT, other_pid, reason}` returns `{:ok, state}`.

Keep tests behavior-split: do not combine `:data`, `:window_change`, `:closed`, and `{:EXIT, ...}` into one broad test.
  </action>
  <verify>
    <automated>mix test test/foglet_bbs/ssh/cli_handler_test.exs</automated>
  </verify>
  <done>Direct callback coverage proves data dispatch, resize dispatch plus session terminal-size update, closed-session cleanup, and lifecycle crash handling without relying on sleeps or fake SSH protocol simulation.</done>
</task>

<task type="auto">
  <name>Task 3: Final validation and quick-task artifacts</name>
  <files>test/foglet_bbs/ssh/cli_handler_test.exs, lib/foglet_bbs/ssh/cli_handler.ex, .planning/quick/260422-omm-today-handle-ssh-msg-for-pty-data-window/260422-omm-SUMMARY.md, .planning/quick/260422-omm-today-handle-ssh-msg-for-pty-data-window/260422-omm-VERIFICATION.md, .planning/STATE.md</files>
  <action>Run the focused SSH handler test file first. Then run `mix precommit` and fix any formatting, warning, Credo, Sobelow, or Dialyzer issues it reports. Write a concise quick-task summary and verification artifact recording the tests added, whether `reply_request/4` production changes were required, and the exact validation commands. Update `.planning/STATE.md` quick task table only after validation passes.</action>
  <verify>
    <automated>mix precommit</automated>
  </verify>
  <done>Focused tests and `mix precommit` pass; summary/verification artifacts record raw terminal-byte assertions, lifecycle/session assertions, and any minimal production fix.</done>
</task>

</tasks>

## Plan Check

Coverage: PASS. The plan covers `:pty`, `:data`, `:window_change`, `:eof`, `:closed`, alt-screen LEAVE, CRLF normalization, and `handle_msg({:EXIT, ...})`.

Locked decisions: PASS. Real daemon/client coverage is required where feasible; direct callbacks are limited to paths the Erlang client cannot reliably expose.

Scope: PASS. One test file is primary, with `CLIHandler` production edits allowed only for the likely PTY/shell request-reply defect.

Validation: PASS. Each task has files, action, verify, and done fields; frontmatter includes `must_haves` truths, artifacts, and key links.
