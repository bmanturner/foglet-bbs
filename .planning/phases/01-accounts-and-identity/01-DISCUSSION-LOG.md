# Phase 1: Accounts & Identity - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-18
**Phase:** 01-accounts-and-identity
**Areas discussed:** Email verification & password reset, Mix task UX, phx.gen.auth adoption, Registration mode

---

## Email verification & password reset without mailer

| Option | Description | Selected |
|--------|-------------|----------|
| Token-generation only | Generate + store token in user_tokens. No email in Phase 1 — token URL returned via Mix task output. Swoosh wires in Phase 10. | ✓ |
| Add Swoosh now for these two flows | Re-enable Swoosh early for verification + reset emails. More setup in Phase 1. | |
| Defer both to Phase 10 | Skip IDNT-02 and IDNT-08 entirely in Phase 1. Land in Phase 10. | |

**User's choice:** Token-generation only

---

**Sysop-created account verification**

| Option | Description | Selected |
|--------|-------------|----------|
| Auto-confirmed (Recommended) | Sysop-created accounts have `confirmed_at` set at creation. Sysop is vouching. | ✓ |
| Require verification same as self-signup | Even sysop-created accounts need email confirmation. | |

**User's choice:** Auto-confirmed

---

**Password reset entrypoint in Phase 1**

| Option | Description | Selected |
|--------|-------------|----------|
| Sysop Mix task only | `mix foglet.user.reset_password --handle bman` generates token, prints URL. | ✓ |
| Function exists, no entrypoint yet | Context function written + tested but no user-facing entrypoint in Phase 1. | |
| Skip — only sysop can force-set a password | Reset flow is fully a Phase 10 concern. | |

**User's choice:** Sysop Mix task only

---

## Mix task UX for foglet.user.create / promote

| Option | Description | Selected |
|--------|-------------|----------|
| CLI flags | `mix foglet.user.create --handle bman --email bman@example.com --password ...` — fully scriptable. | ✓ |
| Interactive prompts | Task asks for fields one by one. Friendly but breaks in CI. | |
| Flags with interactive fallback | Flags when provided; interactive prompts for missing required fields. | |

**User's choice:** CLI flags

---

**`mix foglet.user.promote` interface**

| Option | Description | Selected |
|--------|-------------|----------|
| Positional handle + `--role` flag | `mix foglet.user.promote bman --role sysop` | ✓ |
| All flags | `mix foglet.user.promote --handle bman --role sysop` | |
| Subcommand style | `mix foglet.user.promote bman sysop` (two positional args) | |

**User's choice:** Positional handle + `--role` flag

---

**`mix foglet.user.reset_password` interface**

| Option | Description | Selected |
|--------|-------------|----------|
| Positional handle (`mix foglet.user.reset_password bman`) | Prints token URL to stdout. | ✓ |
| Flag style (`--handle bman`) | Consistent with create style. | |

**User's choice:** Positional handle

---

## phx.gen.auth adoption strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Hand-roll against DATA_MODEL.md | Write Accounts context from scratch following DATA_MODEL.md. No generated code to fight. | ✓ |
| Generate phx.gen.auth, strip web layer | Run `mix phx.gen.auth`, delete web parts. May conflict with DATA_MODEL.md shape. | |
| Use phx.gen.auth as reference only | Don't generate — use phx.gen.auth source as inspiration, implement manually. | |

**User's choice:** Hand-roll against DATA_MODEL.md

---

**Foglet.Schema macro placement**

| Option | Description | Selected |
|--------|-------------|----------|
| Dedicated module from the start | `lib/foglet_bbs/schema.ex` — every schema uses it from day one. | ✓ |
| Inline for now, extract later | Put macro boilerplate in first schema; extract when there are 2+ schemas. | |

**User's choice:** Dedicated module from the start

---

## Registration mode default

| Option | Description | Selected |
|--------|-------------|----------|
| sysop_approved | No account approved until sysop acts. Safe default for community BBS. | ✓ |
| open | Anyone who reaches SSH can register. Public BBS default. | |
| invite_only | Registrations require invite codes. Most controlled; needs invite infrastructure. | |

**User's choice:** sysop_approved

---

**Configuration table scope in Phase 1**

| Option | Description | Selected |
|--------|-------------|----------|
| Config table + typed accessor (Recommended) | Create table + `Foglet.Config` with ETS cache + seed defaults. Enforcement in Phase 3. | ✓ |
| Skip config table in Phase 1 | Add configuration table in Phase 3 when it's actually enforced. | |

**User's choice:** Config table + typed accessor

---

## Claude's Discretion

- Token expiry durations
- Handle validation length bounds
- ETS table name for config cache
- Mix task error message copy

## Deferred Ideas

- Email delivery — Phase 10
- SSH key management UI — Phase 3
- Registration mode enforcement — Phase 3
- Invite code infrastructure — backlog
- User self-service password reset — Phase 10
