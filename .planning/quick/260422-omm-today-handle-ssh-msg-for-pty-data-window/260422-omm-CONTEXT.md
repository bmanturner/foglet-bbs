# Quick Task 260422-omm: SSH CLIHandler integration coverage - Context

**Gathered:** 2026-04-22
**Status:** Ready for research and planning

<domain>
## Task Boundary

Add tests for currently untested `Foglet.SSH.CLIHandler` SSH channel behavior:

- `handle_ssh_msg/2` for `:pty`, `:data`, `:window_change`, `:eof`, and `:closed`
- alt-screen LEAVE sequence emission
- CRLF output normalization
- `handle_msg({:EXIT, ...}, state)` lifecycle crash handling

The likely implementation path is spawning an in-process Erlang `:ssh` daemon and connecting with a real `:ssh` client from tests.

The GSD initializer reported `roadmap_exists: false` because this repo has `docs/ROADMAP.md` rather than `.planning/ROADMAP.md`. Existing quick-task artifacts are present under `.planning/quick/`, so this task proceeds under the repo's current planning layout.

</domain>

<decisions>
## Implementation Decisions

### Test Level
- Use a real in-process `:ssh.daemon` + `:ssh.connect` harness where feasible. Direct callback tests with fakes are acceptable only for behavior that cannot be observed reliably through the real client.

### Coverage Shape
- Split coverage by behavior so failures point at the specific channel path: `:pty`, `:data`, `:window_change`, `:eof`, `:closed`, `{:EXIT, ...}`, CRLF normalization, and alt-screen restoration.

### Assertions
- Assert both externally visible terminal bytes and internal lifecycle/session effects where practical. Prefer raw SSH channel output for terminal protocol behavior and process/session state for lifecycle behavior.

### Agent Discretion
- Keep production changes minimal. This is primarily a test coverage task; production code should change only if the new tests expose an actual defect or if tiny test seams are necessary.
- Prefer deterministic synchronization (`monitor` / `assert_receive` / `:sys.get_state`) over sleeps.
- Use `start_supervised!/1` for test-owned processes.

</decisions>

<specifics>
## Specific Ideas

- `config/test.exs` disables automatic SSH daemon startup but explicitly notes tests can start SSH supervision with test-specific options.
- `Foglet.SSH.Supervisor.daemon_opts/1` exposes daemon options and wires `ssh_cli: {Foglet.SSH.CLIHandler, []}`.
- `Foglet.SSH.DaemonOwner` validates the host key directory before starting `:ssh.daemon/2`.
- Existing `test/foglet_bbs/ssh/cli_handler_test.exs` currently documents that full SSH channel event handling is out of scope; this task should replace that gap with real coverage.

</specifics>

<canonical_refs>
## Canonical References

- `docs/ARCHITECTURE.md` section 7: SSH layer expectations.
- `.planning/codebase/CONCERNS.md` entry noting missing `CLIHandler` channel-event coverage.
- `lib/foglet_bbs/ssh/cli_handler.ex`
- `test/foglet_bbs/ssh/cli_handler_test.exs`

</canonical_refs>
