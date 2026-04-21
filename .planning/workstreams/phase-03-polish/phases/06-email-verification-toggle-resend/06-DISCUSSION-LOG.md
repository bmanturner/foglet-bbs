# Phase 6: Email verification toggle + resend — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in 06-CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-20
**Phase:** 06-email-verification-toggle-resend
**Workstream:** phase-03-polish (v1.0.1)
**Areas discussed:** Config key scope, Retroactive bypass placement, Accounts API shape, Resend cooldown model, Dev-mode code logging, Live-toggle behavior

---

## A — Config key scope

### A1. Which new config keys?

| Option | Description | Selected |
|--------|-------------|----------|
| Only require_email_verification | Single new key. Keep @max_attempts/@cooldown_seconds/@code_length as module attrs. | |
| Plus resend-cooldown | Two keys: require_email_verification + email_verify_resend_cooldown_seconds. | ✓ |
| All tunables | Four keys (adds max_attempts, cooldown_seconds, code_length). | |

**User's choice:** Plus resend-cooldown
**Notes:** Foreshadows the separate resend cooldown decision in Area C. Sysop can tune resend duration without code change.

---

## B — Retroactive bypass placement and register flow

### B1. Where does the require_email_verification check happen?

| Option | Description | Selected |
|--------|-------------|----------|
| login + register screen handlers | Inline config check at both sites. | |
| Accounts context functions | New Accounts API returning :main_menu or :verify. | ✓ |
| Both (belt and suspenders) | Check in both places. | |

**User's choice:** Accounts context functions
**Notes:** Business logic in the Accounts context, not TUI screens.

### B2. Accounts API shape

| Option | Description | Selected |
|--------|-------------|----------|
| post_login_screen(user) | Returns :main_menu or :verify. | ✓ |
| Two predicate functions | verification_required? + needs_verification?(user). | |
| Single verification_required?() | Screens compose logic themselves. | |

**User's choice:** post_login_screen(user)
**Notes:** Thinnest sensible API; reads naturally at call sites.

---

## C — Resend cooldown model

### C1. Relationship between resend and invalid-attempts cooldowns

| Option | Description | Selected |
|--------|-------------|----------|
| Two independent cooldowns | New resend_cooldown_until field, separate from cooldown_until. | ✓ |
| Shared cooldown, longer | Keep one cooldown_until field. | |
| Resend has no cooldown | Remove cooldown check from resend. | |

**User's choice:** Two independent cooldowns
**Notes:** Invalid attempts = anti-brute-force; resend = anti-spam. Different concerns, different durations.

---

## D — Dev-mode logging + edge cases

### D1. Logger.info verify-code behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Gate on config | Only log when require_email_verification=true AND Mix.env() != :prod. | ✓ |
| Keep unconditionally | Always log when codes are generated. | |
| Remove entirely | Delete the Logger.info lines. | |
| Gate on Mix.env only | Only log in :dev/:test, ignore config. | |

**User's choice:** Gate on config
**Notes:** When toggle is false, no code is generated anyway, so the effective behavior is "gate on Mix.env() != :prod within the code-generation path." Both interpretations converge.

### D2. Sysop flips toggle mid-session while user is on :verify

| Option | Description | Selected |
|--------|-------------|----------|
| Session continues as-is | Config affects only new login/register flows. | ✓ |
| Kick to main_menu on next render | Verify screen re-checks config, short-circuits. | |
| Kick to login | Log user out, force fresh session. | |

**User's choice:** Session continues as-is
**Notes:** Simplest and most defensive. User finishes their flow; config change applies to the next user through the door.

---

## Claude's Discretion

- Post-register welcome modal vs plain main_menu landing when toggle is false
- cooldown_modal/2 helper placement (verify.ex vs Compose)
- Foglet.Config.get! vs get + default for testability
- Integration test coverage depth

## Deferred Ideas

- SMTP email delivery (Milestone 10)
- Sysop in-TUI toggle screen (Milestone 8)
- Tunable max_attempts, cooldown_seconds, code_length
- Post-register welcome modal when toggle is false
- Live-toggle mid-session invalidation (explicitly rejected)
- Email delivery hook seam
- DB migration to retroactively confirm users (rejected by locked decision)
- Resend-specific max-attempts limit
