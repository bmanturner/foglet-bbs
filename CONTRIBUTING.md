<!-- generated-by: gsd-doc-writer -->
# Contributing to Foglet BBS

Thanks for your interest in contributing. This document is the entry point
for external contributors opening pull requests against Foglet BBS.

## Project Status

The product surface is
intentionally narrow and the architecture is still consolidating. Before
opening a PR for anything beyond a small fix, please **open an issue or
discussion first** so we can confirm the change fits the current direction.
Major changes landed without prior discussion are likely to be sent back for
scoping.

## Code of Conduct

<!-- VERIFY: no CODE_OF_CONDUCT.md is present in the repository root as of this writing. If one is added, link it here. -->

Be respectful, assume good faith, and keep discussion focused on the work.

## License

Foglet BBS is distributed under the **Apache License 2.0** (see
[`LICENSE.md`](LICENSE.md)). By submitting a contribution you agree that your
work is licensed under the same terms.

## Before You Start

Read these in order:

1. [`README.md`](README.md) — project orientation, requirements, and quick start.
2. [`AGENTS.md`](AGENTS.md) — **canonical project conventions**: namespace
   boundaries, persistence rules, authorization scopes, SSH/TUI ownership,
   and the workflow checklist for domain mutations, TUI flows, runtime
   config, and migrations. Read this before any non-trivial change.
3. [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — system overview,
   supervision tree, and the explicit out-of-scope list.
4. [`docs/DATA_MODEL.md`](docs/DATA_MODEL.md) — required reading before
   touching schemas, migrations, associations, or persistence invariants.

For local setup, see [`docs/GETTING-STARTED.md`](docs/GETTING-STARTED.md).
For day-to-day development workflow, see
[`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md).

## Out of Scope

Per [`docs/ARCHITECTURE.md` §16](docs/ARCHITECTURE.md), the following are
explicitly out of scope and PRs implementing them will not be accepted
without a prior architecture decision:

- Web UI for end users (Phoenix is operational infrastructure only)
- Federation (ActivityPub, FidoNet bridges, etc.)
- File upload areas
- Mobile app
- Paid features, monetization, marketplace
- Voice or video

If you believe one of these should come back on the table, open a discussion
issue first — do not start with code.

## Respect Domain Boundaries

`Foglet.*` is the application/domain namespace; `FogletBbs.*` and
`FogletBbsWeb.*` are Phoenix infrastructure. When in doubt, see `AGENTS.md`.

Concretely:

- **Domain workflows belong in context modules** (`Foglet.Accounts`,
  `Foglet.Boards`, `Foglet.Threads`, `Foglet.Posts`, `Foglet.Config`,
  `Foglet.Authorization`, `Foglet.Sessions.*`).
- **Do not** put domain workflows in Phoenix controllers, in
  `Foglet.SSH.CLIHandler`, or inside TUI render functions.
- Per-board message-number allocation **must** route through
  `Foglet.Boards.Server` — it is the single writer.
- Authorization belongs in `Foglet.Authorization`. Hidden or disabled UI is
  never a substitute for a `Bodyguard.permit/4` check on the mutation path.
- Use `Foglet.Config` typed accessors for runtime configuration; do not
  scatter raw string keys.

## Tests

New domain code needs **context-level tests** under the mirrored path
`test/foglet_bbs/{namespace}/`. The existing layout is:

```
test/foglet_bbs/{accounts,authorization,boards,config,moderation,
                 oneliners,posts,sessions,ssh,threads,tui}/
```

For details on the testing approach (process synchronization without
`Process.sleep/1`, `start_supervised!/1` patterns, etc.), see
[`docs/TESTING.md`](docs/TESTING.md) and the testing guidance in
[`AGENTS.md`](AGENTS.md).

## Finish Line — Required Before Opening a PR

```bash
rtk mix precommit
```

This **must** pass cleanly before you open the PR. `precommit` runs:

- `compile --warnings-as-errors`
- `deps.unlock --unused`
- `format`
- `credo --strict`
- `sobelow --exit Low`
- `dialyzer`

A `pre-commit` git hook also runs `mix precommit` locally (configured via
`mix setup`). Do not bypass it with `--no-verify`.

CI runs the test suite via `.github/workflows/ci.yml`; ensure
`rtk mix test` passes locally as well.

## Commit and PR Conventions

The repository uses a **loose, scope-prefixed** commit style — for example:

```
feat(26-07): add content-aware table width allocation
fix(breadcrumb): remove tab name and Boards from tabbed-screen breadcrumbs
docs(27): add code review fix report
test(27): complete UAT - 1 passed, 1 issue
```

Please match this tone — short, lowercase, scope-prefixed where it adds
clarity — but no strict conventional-commits validation is enforced. Keep
each commit focused on one logical change. Squash noise commits before
opening the PR.

For the PR itself:

- Use a clear, terse title in the same scope-prefixed style.
- Describe **what** changed, **why**, and which contexts/screens it touches.
- Note any schema migrations, runtime config keys, or invariants affected.
- Confirm `rtk mix precommit` passed.
- Link the issue or discussion that motivated the change, if any.

<!-- VERIFY: the repository does not currently provide .github/PULL_REQUEST_TEMPLATE.md. If one is added, that template supersedes the checklist above. -->

## Reporting Issues and Where to Discuss

<!-- VERIFY: the repository does not currently provide .github/ISSUE_TEMPLATE/, a SUPPORT.md, or a published GitHub Discussions surface. Confirm with the maintainer before relying on a specific channel. -->

Open a GitHub issue on the repository for bugs, scoping questions, or
proposals. Include:

- What you expected to happen.
- What actually happened.
- Steps to reproduce (SSH session transcript or reduced test case if
  possible).
- Elixir/OTP versions and OS.
- Relevant log output.

For larger proposals, open the issue **before** writing code so scope and
direction can be agreed up front.

## Thank You

Foglet is small and opinionated by design. Contributions that respect the
domain boundaries, keep Phoenix as infrastructure, and route through the
documented contexts are very welcome.
