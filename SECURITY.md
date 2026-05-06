# Security Policy

Foglet BBS is currently beta software. Security reports are welcome, especially
around authentication, SSH access, authorization boundaries, moderation tools,
door games, secrets handling, and deployment hardening.

## Supported Versions

Security fixes are prioritized for the current public beta release and the
`main` branch. Older unreleased tags or historical development snapshots are not
supported.

## Reporting a Vulnerability

Please do not open a public issue for vulnerabilities, suspected credential
exposure, authentication bypasses, authorization bypasses, or bugs that could
put operators or callers at risk.

Email reports to:

```text
security@foglet.io
```

Include as much of the following as you can:

- affected commit, branch, release, or deployment shape
- clear reproduction steps
- expected behavior and actual behavior
- impact assessment, including what data or capability may be exposed
- whether the issue is already public or actively exploitable
- any logs, screenshots, terminal captures, or proof-of-concept code that help
  explain the issue without exposing real secrets

Please avoid sending real passwords, private keys, session tokens, database
URLs, SMTP credentials, or other live secrets. If a secret is involved, describe
the class of secret and where it was exposed.

## What To Report

Examples of security-sensitive issues include:

- authentication bypasses for password or SSH public-key login
- authorization bypasses in sysop, moderator, board, thread, post, invite, or
  runtime configuration workflows
- leaks of private account data, email addresses, reset tokens, verification
  codes, invite codes, SSH key material, database URLs, or SMTP credentials
- unsafe handling of SSH host keys
- terminal/TUI behavior that could trick callers into entering secrets in the
  wrong place
- door game sandbox escapes, unsafe environment inheritance, dropfile/context
  leaks, process cleanup failures, or execution of untrusted paths
- production configuration defaults that could expose a public deployment
- denial-of-service issues against SSH sessions, board servers, or other OTP
  processes

For normal bugs, feature requests, documentation fixes, and non-sensitive
quality issues, please open a GitHub issue instead.

## Project Security Expectations

Foglet keeps production secrets in environment variables or deployment-platform
secret stores, not in the DB-backed runtime configuration table.

Development fixtures are not production credentials. Seed users, local
passwords, local `.env.local` files, and development SSH host keys must not be
used for a public instance.

Before release, maintainers run the project quality gate:

```bash
rtk mix precommit
```

That includes compile warnings-as-errors, formatting, Credo, Sobelow, Dialyzer,
and related checks. Security reports may still identify issues beyond what
static tooling can catch.

## Coordinated Disclosure

Please give maintainers a reasonable opportunity to investigate and fix a
reported vulnerability before public disclosure. If you have a disclosure
timeline in mind, include it in your report so expectations are clear from the
start.
