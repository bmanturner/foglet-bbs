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
docker compose up -d postgres
mix setup
mix phx.server
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
mix test
```

Before opening a PR, run the full finish line:

```bash
mix precommit
```

`precommit` compiles with warnings as errors, checks formatting, runs Credo,
Sobelow, Dialyzer, and other project checks. Please fix failures before asking
for review.

For TUI work, include render or harness evidence when useful:

```bash
mix foglet.tui.render main_menu
mix foglet.tui.render board_list --width 132 --height 50
npm run ssh:harness -- --user sysop --password 'seedpassword123!'
```

The seed password is a local development fixture only. Do not use seed data or
development host keys in production.

## Pull Request Expectations

Open a PR only after there is an issue for the work. Keep GitHub-facing metadata clean and keep private coordination in Paperclip or the issue thread, not in branch names or commit/PR text.

Before pushing or opening a PR, you can run the same metadata guard locally:

```bash
mix foglet.github_hygiene \
  --branch "$(git branch --show-current)" \
  --commit-subject "$(git log -1 --format=%s)" \
  --pr-title "ci: add metadata hygiene workflow" \
  --pr-body "Short summary without private tracker IDs"
```

Rules enforced by CI:

- branch names must not include Paperclip identifiers like `FOG-123`
- commit subjects must use Conventional Commit style and must not include Paperclip identifiers
- PR titles must use Conventional Commit style and must not include Paperclip identifiers
- PR descriptions must not include Paperclip identifiers unless you intentionally pass `--allow-paperclip-ids-in-pr-body` for an explicit exception

In the PR description, include:

- a short summary of the change
- tests or checks run
- screenshots, text renders, or harness notes for meaningful TUI changes
- any known limitations or follow-up work

## Security

Please do not open public issues for vulnerabilities or suspected sensitive
exposure. Email security reports to:

```text
security@foglet.io
```

Include enough detail to reproduce the issue, affected versions or commits if
known, and whether you believe the issue is actively exploitable.
