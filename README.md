# Foglet BBS

Foglet is an SSH-first bulletin board system built with Elixir, Phoenix,
Postgres, and a terminal UI served over SSH. The product experience is the
terminal BBS: accounts, boards, threads, posts, oneliners, subscriptions,
moderation, and sysop workflows all live there.

Phoenix is operational infrastructure for the endpoint, PubSub, telemetry,
LiveDashboard, mail delivery plumbing, and future structured clients. It is not
a user-facing browser workflow for v1.2 pre-alpha.

## Status

Foglet is pre-alpha software. The current v1.2 work is gap closure: making
offered SSH/TUI flows honest and operational before broader launch work.

## Operator Notes

Foglet is SSH-first; Phoenix is operational infrastructure and not a
user-facing browser workflow.

### Delivery Modes

Foglet stores the active delivery mode in runtime configuration as
`delivery_mode`.

#### Email mode

Email mode uses `delivery_mode=email` for transactional delivery. In this mode,
registration verification, password reset, and account-status notices may be
delivered through the configured mail adapter.

SMTP host, port, username, password, and adapter settings belong in
environment/runtime config, not DB-backed runtime config. Keep those secrets in
`config/runtime.exs` inputs or deployment environment variables.

#### no-email mode

no-email mode uses `delivery_mode=no_email` and requires explicit operator
retrieval workflows. No email is sent in this mode. Operators retrieve reset tokens or verification codes through break-glass Mix tasks, then communicate them through an out-of-band process they control.

### Break-Glass Tasks

Run Mix tasks from the application release or source checkout with the same
database and runtime environment used by the running node.

```bash
mix foglet.user.reset_password HANDLE
mix foglet.user.verification_code HANDLE
mix foglet.user.status HANDLE --actor SYSOP --status active
mix foglet.board_subscriptions list --user HANDLE
```

`mix foglet.user.reset_password HANDLE` generates a raw reset token for operator-assisted SSH reset handling. The task does not send email and does not create a browser reset URL.

`mix foglet.user.verification_code HANDLE` generates a verification code for
no-email operation. In Email mode, use the normal Login or Verify resend flow
instead.

`mix foglet.user.status HANDLE --actor SYSOP --status active` changes user
status through the same Accounts authorization boundary as TUI workflows. Valid
statuses are `active`, `rejected`, and `suspended`.

`mix foglet.board_subscriptions list --user HANDLE` lists a user's board
subscription directory. The same task also supports `subscribe` and
`unsubscribe` actions with `--board BOARD_SLUG`; required-subscription and
archived-board rules still route through `Foglet.Boards`.

### Known Launch Blockers

The Phase 14 reset-URL blocker is closed by Phase 15 when the reset task,
tests, and operator notes use raw reset tokens instead of browser URLs. See
`.planning/phases/14-launch-hygiene-and-operator-notes/14-BLOCKERS.md` for the
current blocker log and audit notes.

### Launch Caveats

Each item in this list is not a v1.2 pre-alpha capability: browser admin, webhook notifications, email digests, delivery retry queues, outbound delivery logs, and full case-management moderation. Foglet should not be operated as though those workflows exist yet.

There is no end-user web UI; it is not a v1.2 pre-alpha capability. Browser-facing Phoenix surfaces are operational infrastructure only.

### Nested Docs

The root README is the canonical pre-alpha operator guide. The nested docs may
contain future-oriented or internal design material, so treat them as design
context unless this README or the current planning artifacts say a workflow is
supported for v1.2 pre-alpha.

## Development

Use `rtk` as the local command prefix in this repository:

```bash
rtk mix test
rtk mix precommit
```

The project finish line is `rtk mix precommit`, which runs compile checks,
formatting, Credo, Sobelow, and Dialyzer.

## License

Copyright 2026 Brendan Turner

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

  http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
