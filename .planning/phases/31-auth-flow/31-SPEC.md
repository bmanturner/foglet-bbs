# Phase 31: Auth Flow - Specification

**Created:** 2026-04-27
**Ambiguity score:** 0.14 (gate: <= 0.20)
**Requirements:** 6 locked

## Goal

Forgot Password becomes an email-validated, enumeration-safe SSH/TUI flow that honestly supports both email delivery and operator-assisted raw-token reset consumption without leaking reset tokens in chrome.

## Background

The Accounts layer already supports terminal-native reset delivery through `Foglet.Accounts.Verification.request_password_reset_delivery/1`, operator raw-token generation through `generate_reset_token_for_operator/1`, and password updates through `reset_user_password/2`. Current reset delivery is handle-or-email, returns a generic result in email mode, and returns `{:error, :unavailable}` in `:no_email` mode without creating token rows. The Login screen currently has only `:menu`, `:login_form`, and `:reset_request` sub-states; `:reset_request` is visible only when delivery mode is `"email"`, displays static unwrapped success/unavailable copy, and has no raw-token consume form. Phase 27 already mapped the `:reset_consume` breadcrumb shape, but it intentionally did not implement token entry, Accounts behavior, or delivery copy.

## Requirements

1. **Forgot Password entry**: Login exposes a Forgot Password entry in both email and no-email delivery modes.
   - Current: `Foglet.TUI.Screens.Login` inserts the Forgot Password menu key only when `Foglet.Config.delivery_mode/0` returns `"email"`; in `"no_email"` mode the reset request path is unreachable from the menu.
   - Target: Forgot Password is reachable from the Login menu regardless of delivery mode, and entering it initializes the reset request sub-state.
   - Acceptance: Login menu tests cover both `"email"` and `"no_email"` delivery modes and assert Forgot Password is present and opens `screen_state[:login].sub == :reset_request` in both modes.

2. **Email-only local validation**: Forgot Password validates the reset request as an email address before invoking Accounts reset delivery.
   - Current: The reset request field is labeled "Handle or email" and submits any string to `Verification.request_password_reset_delivery/1`.
   - Target: The field is email-only. Invalid local shapes such as missing `@`, missing domain, whitespace-only input, and missing dotted domain produce an inline validation error beneath the field and do not call the Accounts reset delivery path.
   - Acceptance: TUI tests assert invalid email-shaped inputs display an inline error, leave the user on `:reset_request`, and create no `reset_password` token rows; valid email-shaped input proceeds to the delivery-mode behavior for that email.

3. **Enumeration-safe reset request behavior**: Valid email-shaped reset requests preserve generic outward results while producing the correct token side effects.
   - Current: `Verification.request_password_reset_delivery/1` is generic in email mode but accepts handles and emails; existing TUI coverage mainly asserts generic copy for unknown identifiers.
   - Target: In email delivery mode, a valid active user's email creates exactly one `reset_password` token and returns the same outward TUI success state as a valid unknown, deleted, pending, suspended, or rejected email, which creates no token. Tests focus on durable behavior and token side effects, not copy-only assertions.
   - Acceptance: Accounts/TUI tests assert an active valid email creates a token row, valid unknown and inactive/deleted emails create no token rows, and all valid email-shaped submissions return the same TUI sub-state/message category without revealing whether an account exists.

4. **Wrapped reset confirmation and no-email honesty**: Reset request confirmation copy wraps at 64x22 and honestly describes no-email operator assistance.
   - Current: Reset request success/unavailable messages render as single `text/2` nodes and can truncate at compact terminal widths; `"no_email"` mode currently reports email reset unavailable instead of showing a supported operator-assisted path.
   - Target: Reset confirmation copy is rendered through `Foglet.TUI.TextWidth.wrap/2` or an equivalent existing width-aware helper. In `"email"` mode it gives generic reset-instructions-sent copy. In `"no_email"` mode it says email delivery is disabled, directs the user to contact a sysop/operator for a reset token, lists active non-deleted sysop email addresses when any exist as a comma-separated list, falls back to generic sysop contact copy when none exist, and offers a token-consume entry.
   - Acceptance: Rendering tests at 64x22 assert reset confirmation text occupies multiple accessible rows without silent truncation; no-email tests assert active sysop emails appear comma-separated when present, deleted/inactive/non-sysop emails do not appear, and the no-sysop fallback remains honest.

5. **Token consume form**: A new `:reset_consume` sub-state lets logged-out users enter raw reset token, new password, and password confirmation.
   - Current: `:reset_consume` exists only as a breadcrumb mapping from Phase 27; Login has no token entry form, key routing, validation, or Accounts call for raw reset token consumption.
   - Target: Users can reach `:reset_consume` from the Forgot Password flow and directly from the Login menu. The form collects raw reset token, new password, and password confirmation; mismatched confirmation or invalid password stays in the form with an inline error; Escape returns to the Login menu.
   - Acceptance: TUI tests assert both entry paths initialize `screen_state[:login].sub == :reset_consume`, Tab/Shift+Tab or the screen's established focus controls route input among all fields, mismatched confirmation blocks submission without consuming a token, and Escape clears token/password fields back to the menu.

6. **Atomic single-use reset consumption**: Raw reset tokens are consumed atomically through the Accounts boundary.
   - Current: `reset_user_password/2` updates a known `User` and deletes outstanding reset tokens in a transaction, but there is no public operation that verifies a raw reset token and consumes it as a single atomic action; two consumers can be specified only indirectly by first querying the token's user.
   - Target: The owning Accounts/Verification boundary exposes a raw-token consume operation that verifies a non-expired `reset_password` token, updates the user's password, deletes outstanding reset tokens for that user, and returns one success or a generic invalid/expired error without leaking token details. The operation runs inside `Repo.transact/1` so concurrent consumption of the same raw token allows exactly one successful password change.
   - Acceptance: Domain tests assert valid token consumption updates the password and removes reset tokens; invalid, malformed, expired, and already-used tokens fail without password change; a concurrent-consume test with two parallel attempts against the same token observes exactly one success; Login token-consume submission returns to the logged-out menu on success and never places the raw token in breadcrumb, status, chrome, modal, or command text.

## Boundaries

**In scope:**
- Login menu and reset sub-state behavior for Forgot Password and token consumption.
- Email-only local validation for reset request input.
- Enumeration-safe reset request behavior for valid email-shaped inputs, including token side-effect tests.
- Width-aware rendering for reset confirmation/no-email copy at 64x22 and resize-relevant state.
- No-email operator-assisted copy that lists active non-deleted sysop emails when available.
- Accounts/Verification raw-token consume operation with atomic single-use semantics.
- Focused tests under the existing Accounts and TUI login test structure.

**Out of scope:**
- Browser password reset routes or controllers - Foglet remains SSH-first and Phase 15 explicitly closed unsupported browser reset copy.
- Sending email in `"no_email"` mode - this mode is intentionally operator-assisted.
- Adding new notification channels, webhooks, or email digests - those are dormant seed/backlog areas, not auth-flow stabilization.
- Changing registration, verification, or approval workflows beyond shared Login reset-menu interactions - Phase 31 is reset-flow scoped.
- Adding account recovery by handle, username, SSH key, or security questions - the reset request field is locked to email-only for this phase.
- Creating a full sysop contact-management feature - this phase only reads active non-deleted sysop user emails already present in Accounts data.
- Persisting UI-local reset form state beyond the active TUI session - tokens and password changes are durable; form input is not.

## Constraints

- The user-facing product surface remains SSH/TUI only; no end-user browser workflow may be introduced.
- Domain side effects for token verification, password update, and token deletion must stay behind the `Foglet.Accounts` / `Foglet.Accounts.Verification` boundary.
- Reset-token consume must use `Repo.transact/1` and must be atomic under concurrent attempts.
- Reset tokens must remain raw-only at the edge and hashed in storage, following `Foglet.Accounts.UserToken` conventions.
- Reset confirmation/no-email copy must use `Foglet.TUI.TextWidth.wrap/2` or an equivalent existing width-aware helper so compact terminal output is not a single silently truncated line.
- Tests should be load-bearing: assert state transitions, token rows, password changes, focus/input behavior, and wrapped row presence rather than relying only on literal copy matches.
- Raw reset token values must never appear in chrome, breadcrumb, status, command hints, or modal text.

## Acceptance Criteria

- [ ] Forgot Password is visible and opens `:reset_request` in both `"email"` and `"no_email"` delivery modes.
- [ ] Invalid local email input stays on `:reset_request`, displays an inline field error, and creates no `reset_password` token row.
- [ ] In email mode, valid active-user email submission creates one reset token while valid unknown/inactive/deleted emails create none, with identical outward TUI success state/message category.
- [ ] Reset confirmation/no-email copy wraps into accessible rows at 64x22 and remains accessible after a compact resize render.
- [ ] In no-email mode, reset confirmation lists active non-deleted sysop emails comma-separated when present and uses honest fallback copy when none exist.
- [ ] `:reset_consume` is reachable from both Forgot Password and the Login menu.
- [ ] The token-consume form collects token, new password, and confirmation, and mismatched confirmation blocks submission without consuming a token.
- [ ] A valid raw reset token updates the password, clears reset tokens, returns the user to the logged-out menu, and is single-use.
- [ ] Concurrent consumption of the same raw token produces exactly one success.
- [ ] Raw reset token text is absent from breadcrumb, status, chrome, modal, and command hint rendering.

## Ambiguity Report

| Dimension           | Score | Min   | Status | Notes |
|---------------------|-------|-------|--------|-------|
| Goal Clarity        | 0.92  | 0.75  | met    | Roadmap plus interview lock email-only reset request, no-email entry, token consume, and atomicity. |
| Boundary Clarity    | 0.84  | 0.70  | met    | Explicitly excludes browser reset, new channels, and non-email recovery methods. |
| Constraint Clarity  | 0.76  | 0.65  | met    | Locks Accounts boundary, `Repo.transact/1`, hashed-token conventions, compact wrapping, and load-bearing tests. |
| Acceptance Criteria | 0.88  | 0.70  | met    | Ten pass/fail criteria cover UI state, token rows, rendering, contacts, and concurrency. |
| **Ambiguity**       | 0.14  | <=0.20| met    | Gate passed after round 2. |

Status: met = met minimum, below = below minimum (planner treats as assumption)

## Interview Log

| Round | Perspective | Question summary | Decision locked |
|-------|-------------|------------------|-----------------|
| 1 | Researcher | In no-email mode, how should users discover and enter an operator-provided reset token? | Always show Forgot Password; no-email copy explains operator-assisted token entry and shows sysop emails when available, comma-separated for multiple sysops. |
| 1 | Researcher | Should forgot-password request accept only email or keep handle-or-email behavior? | Email-only request field. |
| 1 | Researcher | What level of enumeration-safe timing should Phase 31 require? | Avoid weak copy-only tests; tests should enforce load-bearing behavior rather than literal copy alone. |
| 2 | Researcher + Simplifier | What enumeration-safe behavior is load-bearing beyond identical copy? | Valid active email creates one token; valid unknown/inactive/deleted emails create none; outward result remains generic. |
| 2 | Researcher + Simplifier | What is the irreducible token-consume form surface? | Raw token, new password, and password confirmation. |
| 2 | Researcher + Simplifier | Which sysop contacts should no-email copy use? | Active non-deleted sysop user emails, comma-separated when multiple, with fallback if none. |

---

*Phase: 31-auth-flow*
*Spec created: 2026-04-27*
*Next step: $gsd-discuss-phase 31 - implementation decisions (how to build what's specified above)*
