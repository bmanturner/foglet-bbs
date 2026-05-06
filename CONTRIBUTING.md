# Contributing to Foglet BBS

Thanks for wanting to help with Foglet. This project is in beta: useful,
running, and actively shaped, but still early enough that coordination matters.

Foglet is SSH-first and TUI-first. Phoenix is infrastructure for the endpoint,
PubSub, telemetry, health checks, docs, and operational tooling; it is not a
browser forum product surface.

## Before Opening a PR

Please open an issue before every pull request. For non-trivial work, use the
issue to align on scope and direction before writing code. This keeps review
focused and avoids asking contributors to redo work after the fact.

Good first areas for contribution include:

- bugs
- terminal UI polish
- moderation features
- door games
- security hardening

If you are unsure where a change belongs, open an issue with the problem you
want to solve and the rough approach you are considering.

## Local Setup

Install the toolchain from `.tool-versions`, then prepare the app:

```bash
rtk docker compose up -d postgres
rtk mix setup
rtk mix phx.server
```

Then connect to the local SSH service:

```bash
ssh localhost -p 2222
```

For fuller setup notes, see:

- `README.md`
- `priv/docs/advanced/development.md`

## Project Boundaries

Keep domain workflows in `Foglet.*` contexts. Keep SSH lifecycle behavior in
`Foglet.SSH.*`, global TUI routing in `Foglet.TUI.App`, screen-local behavior in
screen modules, and reusable display in widgets.

## Quality Checks

Run focused tests while developing:

```bash
rtk mix test
```

Before opening a PR, run the full finish line:

```bash
rtk mix precommit
```

`precommit` compiles with warnings as errors, checks formatting, runs Credo,
Sobelow, Dialyzer, and other project checks. Please fix failures before asking
for review.

For TUI work, include render or harness evidence when useful:

```bash
rtk mix foglet.tui.render main_menu
rtk mix foglet.tui.render board_list --width 132 --height 50
rtk npm run ssh:harness -- --user sysop --password 'seedpassword123!'
```

The seed password is a local development fixture only. Do not use seed data or
development host keys in production.

## Pull Request Expectations

Open a PR only after there is an issue for the work. In the PR description,
include:

- the issue it addresses
- a short summary of the change
- tests or checks run
- screenshots, text renders, or harness notes for meaningful TUI changes
- any known limitations or follow-up work

There is no required commit-message format.

## Security

Please do not open public issues for vulnerabilities or suspected sensitive
exposure. Email security reports to:

```text
security@foglet.io
```

Include enough detail to reproduce the issue, affected versions or commits if
known, and whether you believe the issue is actively exploitable.
