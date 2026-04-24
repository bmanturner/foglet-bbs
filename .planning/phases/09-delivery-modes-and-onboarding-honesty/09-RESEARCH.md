# Phase 09: Delivery Modes and Onboarding Honesty - Research

**Researched:** 2026-04-24  
**Domain:** Elixir/Phoenix transactional email, runtime config, account verification/reset, SSH/TUI onboarding  
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
## Implementation Decisions

### Delivery Mode Configuration
- **D-01:** Represent delivery mode as one schematized, runtime-editable, non-secret config key with exactly two enum values: Swoosh email delivery enabled and explicit no-email mode.
- **D-02:** Expose delivery mode through a typed `Foglet.Config` accessor so `Foglet.Accounts`, TUI screens, Sysop forms, tests, and Mix tasks branch from one canonical runtime API.
- **D-03:** Keep Swoosh adapter settings, API keys, SMTP credentials, and other secrets in runtime/environment configuration, not in DB-backed `configuration` rows.

### Verification Delivery Boundary
- **D-04:** Registration, login re-entry, and Verify-screen resend should stop treating `Accounts.build_verify_code/1` as the delivery workflow.
- **D-05:** Add an Accounts-level delivery function that creates the verification code, attempts Swoosh delivery when email mode is enabled, and returns only generic success/failure information to TUI callers.
- **D-06:** TUI screens should render delivery state and copy from Accounts/Config results; they should not own Swoosh calls, direct token persistence, or ad hoc delivery-mode branching.
- **D-07:** Preserve existing Verify-screen code entry, invalid-attempt cooldown, resend cooldown, and their independence while changing resend success/failure copy to match attempted delivery.

### Password Reset Flow
- **D-08:** Add a terminal-native password-reset request subflow to the Login screen, available only when Swoosh email mode is configured.
- **D-09:** Back user-requested reset with an enumeration-safe Accounts function that targets active, non-deleted users and gives the same outward response for unknown, deleted, inactive, and delivery-failure cases.
- **D-10:** Do not expose the existing browser-style reset URL to end users. User-facing reset delivery must not point to unimplemented browser reset pages.
- **D-11:** Preserve operator break-glass reset intent, but align the Mix task with delivery mode so no-email mode does not present normal user reset delivery as available.

### Operator Surfaces And Honest Copy
- **D-12:** Integrate delivery-mode visibility and editability into existing Sysop config surfaces rather than creating a separate administration surface.
- **D-13:** Existing Sysop config placement rules still apply: new schematized keys must be intentionally placed in the correct tab/form list and not appear accidentally.
- **D-14:** Normal operator configuration must block or clearly flag `delivery_mode=no_email` combined with `require_email_verification=true`.
- **D-15:** Update Register, Login, Verify, Sysop, and reset-task copy so it distinguishes emailed instructions, delivery attempted, no-email unavailable paths, pending sysop approval, and break-glass generated outcomes.
- **D-16:** Pending approval copy must remain honest for Phase 9 and must not promise MAIL-07 approval/rejection notification delivery before Phase 10 implements it.

### Claude's Discretion
- Exact enum key name and enum string values, as long as the two user-visible states are unambiguous and typed.
- Exact terminal layout for the Login reset-request subflow, provided it follows existing Login screen patterns and remains SSH/TUI-first.
- Exact generic success/failure wording, provided tests prove it avoids false delivery claims and user enumeration.
- Exact Swoosh mailer module placement and adapter configuration pattern, subject to official Swoosh/Phoenix guidance during research.

### Deferred Ideas (OUT OF SCOPE)
## Deferred Ideas

- MAIL-07 approval/rejection notification delivery — Phase 10.
- Browser password-reset pages or other end-user browser workflows — out of scope for v1.2 unless architecture docs change.
- No-email verification relay and no-email password-reset relay — explicitly invalid for Phase 9.
- Webhook notifications, email digests, delivery retry queues, outbound delivery logs, and durable background delivery processing — future notification/reach work.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| MAIL-01 | Operator can configure Swoosh email delivery mode or explicit no-email mode, and verification/default behavior matches that mode. | Use `Foglet.Config.Schema` enum key, seed default, typed accessor, and `Sysop.SiteForm` placement. The runtime mailer adapter can be SMTP, Mailgun, SendGrid, Postmark, SES, or any Swoosh-supported provider; the DB-backed mode should only distinguish `email` from `no_email`. [VERIFIED: `.planning/REQUIREMENTS.md`; VERIFIED: `lib/foglet_bbs/config/schema.ex`; VERIFIED: `lib/foglet_bbs/tui/screens/sysop/site_form.ex`; CITED: https://hexdocs.pm/swoosh/Swoosh.html] |
| MAIL-02 | User receives an email verification code after registration when Swoosh email delivery is configured and verification is required. | Wrap `Accounts.build_verify_code/1` in an Accounts delivery function that creates a Swoosh email and calls `Foglet.Mailer.deliver/1`. [VERIFIED: `lib/foglet_bbs/accounts.ex`; CITED: https://hexdocs.pm/swoosh/Swoosh.Mailer.html] |
| MAIL-03 | User can request a fresh verification code from the Verify screen with cooldown-aware feedback. | Keep `Verify`'s resend cooldown and invalid-attempt cooldown state, replacing direct code generation with the Accounts delivery function. [VERIFIED: `lib/foglet_bbs/tui/screens/verify.ex`; VERIFIED: `test/foglet_bbs/tui/screens/verify_test.exs`] |
| MAIL-04 | User can receive a password reset email when Swoosh email delivery is configured, while the existing Mix task remains available as a break-glass path. | Add a terminal login reset request backed by enumeration-safe Accounts delivery and update the Mix task to reflect delivery mode. [VERIFIED: `lib/foglet_bbs/tui/screens/login.ex`; VERIFIED: `lib/mix/tasks/foglet.user.reset_password.ex`; CITED: https://cheatsheetseries.owasp.org/cheatsheets/Forgot_Password_Cheat_Sheet.html] |
| MAIL-05 | User-facing TUI copy never claims a code or notification was emailed unless Foglet actually attempted delivery. | Change Register, Login, Verify, and reset messages currently claiming email/notification without delivery. [VERIFIED: `lib/foglet_bbs/tui/screens/register.ex`; VERIFIED: `lib/foglet_bbs/tui/screens/verify.ex`; VERIFIED: `lib/foglet_bbs/tui/screens/login.ex`] |
| MAIL-06 | Operator can retrieve verification, reset, or pending-approval delivery details through an explicit no-email/operator-visible workflow when email delivery is disabled. | Phase 9 context narrows this to operator-visible delivery-mode implications and no-email unavailability, not user relay flows. [VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-CONTEXT.md`; VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-SPEC.md`] |
</phase_requirements>

## Summary

Phase 9 should add a small Swoosh-backed transactional delivery layer, not a general notification system. Swoosh is the locked email library, current on Hex as `1.25.0` as of 2026-04-02, and it supports both API-provider adapters and SMTP. SMTP delivery requires the separate `gen_smtp` dependency; API-provider adapters such as Mailgun, SendGrid, Postmark, and Amazon SES use their own Swoosh adapter configuration instead. [VERIFIED: Hex package page; CITED: https://hex.pm/packages/swoosh; CITED: https://hexdocs.pm/swoosh/Swoosh.html; CITED: https://hexdocs.pm/swoosh/Swoosh.Adapters.SMTP.html]

The established architecture is: runtime mode lives in `Foglet.Config`, delivery orchestration lives in `Foglet.Accounts`, email construction lives in a small mailer/email module pair, and TUI/Mix surfaces only consume typed results. [VERIFIED: `CLAUDE.md`; VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-CONTEXT.md`; VERIFIED: `lib/foglet_bbs/config.ex`; VERIFIED: `lib/foglet_bbs/accounts.ex`]

The largest implementation risks are false delivery copy, user enumeration in password reset, treating token generation as delivery, and accidentally creating browser or no-email relay workflows that the phase explicitly forbids. [VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-SPEC.md`; CITED: https://cheatsheetseries.owasp.org/cheatsheets/Forgot_Password_Cheat_Sheet.html]

**Primary recommendation:** Implement `Foglet.Accounts` delivery APIs that return enumeration-safe, UI-oriented result atoms, use `Foglet.Mailer` as the only delivery boundary in email mode, use `Swoosh.Adapters.Test` in tests, and keep no-email mode as an explicit disabling mode rather than a relay path. Configure the concrete provider adapter in runtime config so Foglet can support SMTP, Mailgun, SendGrid, Postmark, SES, and other Swoosh adapters without changing Accounts or TUI code. [VERIFIED: codebase grep; CITED: https://hexdocs.pm/swoosh/Swoosh.Mailer.html; CITED: https://hexdocs.pm/swoosh/Swoosh.html; CITED: https://hexdocs.pm/swoosh/Swoosh.Adapters.Test.html]

## Project Constraints (from CLAUDE.md)

- Foglet is SSH-first; do not add end-user browser workflows for reset or verification in this phase. [VERIFIED: `CLAUDE.md`]
- Use `rtk` as the shell prefix for repo commands such as `rtk mix test`. [VERIFIED: `CLAUDE.md`]
- Keep domain workflows in `Foglet.*` contexts, not Phoenix controllers, SSH callbacks, or TUI render functions. [VERIFIED: `CLAUDE.md`]
- `Foglet.Accounts` owns users, auth, roles, invites, tokens, SSH keys, and deletion. [VERIFIED: `CLAUDE.md`]
- `Foglet.Config` owns runtime configuration and ETS-backed caching. [VERIFIED: `CLAUDE.md`]
- Actor-triggered runtime config writes must use `Config.put/3`; trusted setup/tests/Mix tasks may use `Config.put!/3`. [VERIFIED: `CLAUDE.md`]
- Keep secrets in environment/runtime config, not DB-backed config. [VERIFIED: `CLAUDE.md`]
- TUI behavior belongs in `Foglet.TUI.App` and screens; screens should own local rendering/key handling while data/mutations stay in contexts. [VERIFIED: `CLAUDE.md`]
- Use `start_supervised!/1` for processes in tests and avoid `Process.sleep/1`; synchronize through explicit state/messages. [VERIFIED: `CLAUDE.md`]
- Run `mix precommit` when implementation changes are complete. [VERIFIED: `CLAUDE.md`]

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|--------------|----------------|-----------|
| Delivery mode config | API / Backend (`Foglet.Config`) | Database / Storage (`configuration`) | Non-secret mode is persisted, schematized, cached, and read through typed accessors. [VERIFIED: `lib/foglet_bbs/config.ex`; VERIFIED: `lib/foglet_bbs/config/schema.ex`] |
| Provider credentials and adapter settings | Runtime / OTP config | External email provider | Secrets must not be stored in the `configuration` table; Swoosh reads mailer adapter config from OTP app config. [VERIFIED: `CLAUDE.md`; CITED: https://hexdocs.pm/swoosh/Swoosh.Mailer.html] |
| Verification code delivery | API / Backend (`Foglet.Accounts`) | External provider via Swoosh | Code persistence already exists in Accounts and delivery must wrap it rather than live in TUI. [VERIFIED: `lib/foglet_bbs/accounts.ex`; VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-CONTEXT.md`] |
| Verify screen cooldown feedback | Browser / Client equivalent: SSH TUI screen | API / Backend (`Foglet.Accounts`) | Screen owns local cooldown/buffer state, while Accounts owns token generation and delivery attempt. [VERIFIED: `lib/foglet_bbs/tui/screens/verify.ex`; VERIFIED: `CLAUDE.md`] |
| Password reset request | API / Backend (`Foglet.Accounts`) | SSH TUI Login screen | Enumeration-safe lookup, token persistence, and delivery belong in Accounts; Login only collects input and renders generic result copy. [VERIFIED: `lib/foglet_bbs/tui/screens/login.ex`; CITED: https://cheatsheetseries.owasp.org/cheatsheets/Forgot_Password_Cheat_Sheet.html] |
| Operator break-glass reset | Mix task | API / Backend (`Foglet.Accounts`, `Foglet.Config`) | Task is an operator shell surface; delivery-mode policy and token operations must stay in contexts. [VERIFIED: `lib/mix/tasks/foglet.user.reset_password.ex`; VERIFIED: `CLAUDE.md`] |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `swoosh` | `~> 1.25` (`1.25.0`, published 2026-04-02) | Compose, deliver, and test transactional email through provider adapters. | Current Swoosh docs define `Swoosh.Mailer` as an adapter wrapper and list API-provider adapters plus SMTP/test support. [CITED: https://hex.pm/packages/swoosh; CITED: https://hexdocs.pm/swoosh/Swoosh.html; CITED: https://hexdocs.pm/swoosh/Swoosh.Mailer.html] |
| `gen_smtp` | `~> 1.3` (`1.3.0`, published 2025-05-30) | SMTP client used underneath `Swoosh.Adapters.SMTP`. | Add only when Foglet's documented runtime configuration includes SMTP. Swoosh API-provider adapters do not require `gen_smtp`. [CITED: https://hexdocs.pm/swoosh/Swoosh.Adapters.SMTP.html; CITED: https://hex.pm/packages/gen_smtp] |
| `Swoosh.Adapters.Test` | from `swoosh` `1.25.0` | Assert delivered email in ExUnit. | Official adapter sends emails as messages to current process and pairs with `Swoosh.TestAssertions`. [CITED: https://hexdocs.pm/swoosh/Swoosh.Adapters.Test.html] |
| `Foglet.Config` | existing | Runtime delivery mode and verification toggle access. | Existing code already provides schematized keys, validation, DB upsert, ETS invalidation, and typed accessors. [VERIFIED: `lib/foglet_bbs/config.ex`; VERIFIED: `lib/foglet_bbs/config/schema.ex`] |
| `Foglet.Accounts.UserToken` | existing | Verification/reset token persistence. | Existing Accounts code already builds verification codes and reset email tokens. [VERIFIED: `lib/foglet_bbs/accounts.ex`; VERIFIED: `docs/DATA_MODEL.md`] |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `Swoosh.Email` | from `swoosh` `1.25.0` | Build text email structs with `to`, `from`, `subject`, and body fields. | Use in `Foglet.Accounts.Email` or equivalent small email-builder module. [CITED: https://hexdocs.pm/swoosh/Swoosh.html] |
| `Swoosh.Mailer` telemetry | from `swoosh` `1.25.0` | Emits delivery start/stop/exception telemetry. | Do not build delivery logs in Phase 9, but leave delivery code compatible with Swoosh telemetry. [CITED: https://hexdocs.pm/swoosh/Swoosh.Mailer.html; VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-SPEC.md`] |
| OWASP Forgot Password Cheat Sheet | current web doc crawled 2026 | Security control reference for generic reset request responses. | Use for reset request copy and avoiding user enumeration. [CITED: https://cheatsheetseries.owasp.org/cheatsheets/Forgot_Password_Cheat_Sheet.html] |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Swoosh synchronous delivery now | Oban-delivered background jobs | Out of scope: durable delivery queues/logs are deferred; current phase only needs attempted synchronous delivery and honest copy. [VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-SPEC.md`; VERIFIED: `.planning/codebase/INTEGRATIONS.md`] |
| `Phoenix.Swoosh` templates | Plain `Swoosh.Email` text builders | Phoenix templates are useful for HTML/template rendering, but Foglet's product surface is terminal-first and Phase 9 needs simple transactional text copy. [CITED: https://hexdocs.pm/phoenix_swoosh/Phoenix.Swoosh.html; VERIFIED: `CLAUDE.md`] |
| Browser reset routes | Terminal reset request plus operator break-glass task | Browser reset pages are explicitly out of scope and no route exists today. [VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-SPEC.md`; VERIFIED: `lib/mix/tasks/foglet.user.reset_password.ex`] |

**Installation:**
```elixir
# mix.exs
{:swoosh, "~> 1.25"},
{:gen_smtp, "~> 1.3"} # only required for Swoosh.Adapters.SMTP
```

**Version verification:** `swoosh` latest is `1.25.0`, last updated Apr 02, 2026; `gen_smtp` latest is `1.3.0`, last updated May 30, 2025. [CITED: https://hex.pm/packages/swoosh; CITED: https://hex.pm/packages/gen_smtp]

## Architecture Patterns

### System Architecture Diagram

```text
Sysop Site Config
  -> Foglet.Config.put/3
  -> configuration row + ETS invalidation
  -> Foglet.Config.delivery_mode()

Register / Login / Verify TUI
  -> Foglet.Accounts delivery API
  -> reads Foglet.Config.delivery_mode()
  -> if "email": create token/code -> build Swoosh.Email -> Foglet.Mailer.deliver()
  -> runtime config selects Swoosh provider adapter: SMTP, Mailgun, SendGrid, Postmark, SES, etc.
  -> if "no_email": return unavailable/skip result without token relay workflow
  -> TUI renders generic, mode-accurate copy

Login Reset Request
  -> Foglet.Accounts.request_password_reset_delivery(identifier)
  -> same outward response for unknown/deleted/inactive/failure
  -> for active match in email mode: create reset token -> build email -> deliver
  -> TUI renders generic response, never browser URL

Mix Break-Glass Reset
  -> reads Foglet.Config.delivery_mode()
  -> email mode: preserve operator reset behavior with honest wording
  -> no-email mode: do not present normal user reset delivery as available
```

### Recommended Project Structure

```text
lib/
├── foglet_bbs/
│   ├── accounts.ex              # public delivery/reset APIs and policy branching
│   ├── accounts/
│   │   ├── email.ex             # Swoosh.Email builders for verify/reset text
│   │   └── user_token.ex        # existing token/code builders, reused
│   ├── config.ex                # typed delivery_mode accessor
│   └── config/schema.ex         # delivery_mode enum spec/default
├── foglet_bbs/mailer.ex         # use Swoosh.Mailer, otp_app: :foglet_bbs
└── mix/tasks/
    └── foglet.user.reset_password.ex

config/
├── config.exs                   # mailer default adapter or non-secret baseline
├── runtime.exs                  # Swoosh provider adapter settings from env
└── test.exs                     # Swoosh.Adapters.Test

test/
├── foglet_bbs/accounts/accounts_test.exs
├── foglet_bbs/config/schema_test.exs
├── foglet_bbs/tui/screens/login_test.exs
├── foglet_bbs/tui/screens/register_test.exs
├── foglet_bbs/tui/screens/verify_test.exs
└── mix/tasks/foglet_user_reset_password_test.exs
```

### Pattern 1: Mailer Wrapper

**What:** Define one project mailer with `use Swoosh.Mailer, otp_app: :foglet_bbs`. [CITED: https://hexdocs.pm/swoosh/Swoosh.Mailer.html]  
**When to use:** Every Accounts delivery function should call this mailer, not adapter modules directly. [VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-CONTEXT.md`]

```elixir
# Source: https://hexdocs.pm/swoosh/Swoosh.Mailer.html
defmodule Foglet.Mailer do
  use Swoosh.Mailer, otp_app: :foglet_bbs
end
```

### Pattern 2: Accounts-Level Delivery Result

**What:** Wrap token creation and email delivery in Accounts and return UI-safe atoms such as `{:ok, :attempted}` or `{:error, :unavailable}`. [VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-CONTEXT.md`]  
**When to use:** Register, Login verify re-entry, Verify resend, and Login reset request. [VERIFIED: `lib/foglet_bbs/tui/screens/register.ex`; VERIFIED: `lib/foglet_bbs/tui/screens/login.ex`; VERIFIED: `lib/foglet_bbs/tui/screens/verify.ex`]

```elixir
# Source: verified Foglet context pattern + Swoosh.Mailer docs
def deliver_verification_code(%User{} = user) do
  if Foglet.Config.delivery_mode() == "email" do
    with {:ok, code} <- build_verify_code(user),
         email <- Foglet.Accounts.Email.verify_code(user, code),
         {:ok, _meta} <- Foglet.Mailer.deliver(email) do
      {:ok, :attempted}
    else
      _ -> {:error, :delivery_failed}
    end
  else
    {:error, :unavailable}
  end
end
```

### Pattern 3: Enumeration-Safe Reset Request

**What:** Return the same outward response for known, unknown, deleted, inactive, and delivery-failure cases. [CITED: https://cheatsheetseries.owasp.org/cheatsheets/Forgot_Password_Cheat_Sheet.html]  
**When to use:** Terminal login reset request. [VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-SPEC.md`]

```elixir
# Source: OWASP Forgot Password Cheat Sheet + phase SPEC
def request_password_reset_delivery(identifier) when is_binary(identifier) do
  if Foglet.Config.delivery_mode() == "email" do
    identifier
    |> find_active_reset_candidate()
    |> maybe_deliver_reset_email()

    {:ok, :generic_response}
  else
    {:error, :unavailable}
  end
end
```

### Anti-Patterns to Avoid

- **Calling `Accounts.build_verify_code/1` from TUI as delivery:** This only persists a code; it does not attempt email. [VERIFIED: `lib/foglet_bbs/accounts.ex`; VERIFIED: `lib/foglet_bbs/tui/screens/verify.ex`]
- **Putting provider credentials in `configuration`:** Phase decisions and project rules require secrets in runtime/environment config. [VERIFIED: `CLAUDE.md`; VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-CONTEXT.md`]
- **Returning different reset messages for unknown users:** OWASP identifies user enumeration as a common reset vulnerability and recommends consistent messages. [CITED: https://cheatsheetseries.owasp.org/cheatsheets/Forgot_Password_Cheat_Sheet.html]
- **Adding browser reset pages:** Explicitly out of scope for this SSH-first milestone. [VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-SPEC.md`; VERIFIED: `CLAUDE.md`]
- **Using no-email mode as an operator relay workflow:** Phase 9 explicitly marks no-email verification/reset relay invalid. [VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-CONTEXT.md`]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Provider-specific delivery dispatch | Custom Mailgun/SendGrid/Postmark/SES clients or `case provider do` branches in Accounts | `Foglet.Mailer.deliver/1` with the configured Swoosh adapter | Swoosh already owns provider adapters; app code should build email structs and call the mailer boundary. [CITED: https://hexdocs.pm/swoosh/Swoosh.html; CITED: https://hexdocs.pm/swoosh/Swoosh.Mailer.html] |
| SMTP protocol delivery | Custom `:gen_tcp` SMTP client | `Swoosh.Adapters.SMTP` + `gen_smtp` | Swoosh officially wraps SMTP delivery through `gen_smtp`. [CITED: https://hexdocs.pm/swoosh/Swoosh.Adapters.SMTP.html] |
| Email test capture | Custom process mailbox tracker | `Swoosh.Adapters.Test` + `Swoosh.TestAssertions` | Official test adapter sends emails as messages to the current process and is intended for tests. [CITED: https://hexdocs.pm/swoosh/Swoosh.Adapters.Test.html] |
| Runtime config storage | New config table or env-only mode flag | Existing `Foglet.Config.Schema` + `Foglet.Config` typed accessor | Existing implementation already validates, persists, caches, and actor-authorizes runtime config. [VERIFIED: `lib/foglet_bbs/config.ex`; VERIFIED: `lib/foglet_bbs/config/schema.ex`] |
| Verification code generation | New code table/algorithm | Existing `UserToken.build_verify_code/1` via `Accounts.build_verify_code/1` | Existing code already creates expiring 6-character verify tokens. [VERIFIED: `lib/foglet_bbs/accounts.ex`] |
| Reset token generation | New reset token format | Existing `UserToken.build_email_token(user, "reset_password")` through Accounts | Existing reset token persistence already exists and is tested. [VERIFIED: `lib/foglet_bbs/accounts.ex`; VERIFIED: `.planning/codebase/TESTING.md`] |
| Password-reset security policy | Ad hoc copy and branching | OWASP forgot-password controls | Consistent outward messages and side-channel delivery are standard controls. [CITED: https://cheatsheetseries.owasp.org/cheatsheets/Forgot_Password_Cheat_Sheet.html] |

**Key insight:** Phase 9 is a boundary repair: connect existing token/cooldown/config primitives to Swoosh and honest copy; do not introduce a delivery subsystem, queue, browser account recovery product, or no-email relay design. [VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-SPEC.md`; VERIFIED: `.planning/codebase/INTEGRATIONS.md`]

## Common Pitfalls

### Pitfall 1: Token Created, Delivery Not Attempted
**What goes wrong:** UI says "emailed" because a token exists, but no mailer was called. [VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-SPEC.md`]  
**Why it happens:** Existing TUI calls `Accounts.build_verify_code/1` directly. [VERIFIED: `lib/foglet_bbs/tui/screens/login.ex`; VERIFIED: `lib/foglet_bbs/tui/screens/register.ex`; VERIFIED: `lib/foglet_bbs/tui/screens/verify.ex`]  
**How to avoid:** Replace TUI token calls with Accounts delivery APIs. [VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-CONTEXT.md`]  
**Warning signs:** `Accounts.build_verify_code(` remains in TUI modules after implementation. [VERIFIED: codebase grep]

### Pitfall 2: Reset User Enumeration
**What goes wrong:** Unknown, deleted, inactive, or delivery-failed requests receive distinct copy or timing. [CITED: https://cheatsheetseries.owasp.org/cheatsheets/Forgot_Password_Cheat_Sheet.html]  
**Why it happens:** Implementers short-circuit on lookup failure or expose provider errors. [CITED: https://cheatsheetseries.owasp.org/cheatsheets/Forgot_Password_Cheat_Sheet.html]  
**How to avoid:** Always return generic terminal copy in email mode and log/provider-detail internally only if needed. [CITED: https://cheatsheetseries.owasp.org/cheatsheets/Forgot_Password_Cheat_Sheet.html; VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-SPEC.md`]  
**Warning signs:** Tests assert "not found", "inactive", or "delivery failed" text on the user-facing reset path. [VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-SPEC.md`]

### Pitfall 3: Invalid Config Combination Persists
**What goes wrong:** `delivery_mode=no_email` and `require_email_verification=true` coexist, routing users into impossible verification. [VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-SPEC.md`]  
**Why it happens:** Current schema validates each key independently. [VERIFIED: `lib/foglet_bbs/config/schema.ex`]  
**How to avoid:** Add cross-field validation at the Sysop form save boundary and any operator Mix path that changes the mode. [VERIFIED: `lib/foglet_bbs/tui/screens/sysop/site_form.ex`; VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-CONTEXT.md`]  
**Warning signs:** `Schema.validate/2` alone is expected to catch cross-key invalidity. [VERIFIED: `lib/foglet_bbs/config/schema.ex`]

### Pitfall 4: Provider Secrets Stored in DB Config
**What goes wrong:** SMTP usernames/passwords or API provider keys are persisted in `configuration`. [VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-CONTEXT.md`]  
**Why it happens:** Delivery mode and adapter credentials are conflated. [VERIFIED: `CLAUDE.md`]  
**How to avoid:** Store only the non-secret enum in `Foglet.Config`; read the selected Swoosh adapter and all provider settings from runtime env/OTP config. [CITED: https://hexdocs.pm/swoosh/Swoosh.Mailer.html; VERIFIED: `CLAUDE.md`]  
**Warning signs:** New config schema keys contain password, key, token, relay credentials, or provider secrets. [VERIFIED: `CLAUDE.md`]

### Pitfall 5: Test Adapter Mismatch
**What goes wrong:** Swoosh test assertions fail because delivery happens in another process or wrong adapter is configured. [CITED: https://hexdocs.pm/swoosh/Swoosh.Adapters.Test.html]  
**Why it happens:** `Swoosh.Adapters.Test` sends emails to current process; E2E/request process cases may need Sandbox, but Phase 9 mostly uses direct context/screen tests. [CITED: https://hexdocs.pm/swoosh/Swoosh.Adapters.Test.html; VERIFIED: `.planning/codebase/TESTING.md`]  
**How to avoid:** Use direct Accounts/TUI tests with `Swoosh.Adapters.Test`; only switch to `Swoosh.Adapters.Sandbox` if implementation moves delivery into a different process. [CITED: https://hexdocs.pm/swoosh/Swoosh.Adapters.Test.html]  
**Warning signs:** Tests call delivery via spawned command/process and expect current-process assertions. [CITED: https://hexdocs.pm/swoosh/Swoosh.Adapters.Test.html]

## Code Examples

### Swoosh Mailer Configuration

```elixir
# Source: https://hexdocs.pm/swoosh/Swoosh.Mailer.html
defmodule Foglet.Mailer do
  use Swoosh.Mailer, otp_app: :foglet_bbs
end

# config/test.exs
config :foglet_bbs, Foglet.Mailer,
  adapter: Swoosh.Adapters.Test
```

### Provider Runtime Shape

```elixir
# Source: https://hexdocs.pm/swoosh/Swoosh.html
# Runtime config should choose exactly one concrete Swoosh adapter.
config :foglet_bbs, Foglet.Mailer,
  adapter: Swoosh.Adapters.Mailgun,
  api_key: System.fetch_env!("FOGLET_MAILGUN_API_KEY"),
  domain: System.fetch_env!("FOGLET_MAILGUN_DOMAIN")

# Source: https://hexdocs.pm/swoosh/Swoosh.Adapters.SMTP.html
# Add {:gen_smtp, "~> 1.3"} only when using this adapter.
config :foglet_bbs, Foglet.Mailer,
  adapter: Swoosh.Adapters.SMTP,
  relay: System.fetch_env!("FOGLET_SMTP_RELAY"),
  username: System.get_env("FOGLET_SMTP_USERNAME"),
  password: System.get_env("FOGLET_SMTP_PASSWORD"),
  tls: :always,
  auth: :if_available,
  port: String.to_integer(System.get_env("FOGLET_SMTP_PORT", "587"))
```

### Email Builder

```elixir
# Source: https://hexdocs.pm/swoosh/Swoosh.html
defmodule Foglet.Accounts.Email do
  import Swoosh.Email

  def verify_code(user, code) do
    new()
    |> to({user.handle, user.email})
    |> from({"Foglet BBS", sender()})
    |> subject("Your Foglet verification code")
    |> text_body("Your Foglet verification code is #{code}.")
  end

  defp sender, do: Application.fetch_env!(:foglet_bbs, :mail_from)
end
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Token generation named like delivery | Separate token creation from attempted delivery | Phase 9 locked decision, 2026-04-24 | TUI copy must be based on delivery attempt result, not token creation. [VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-CONTEXT.md`] |
| No mailer in repo | Swoosh `1.25.0` + SMTP adapter + test adapter | Swoosh latest verified 2026-04-24 | Add dependencies and project mailer instead of custom email logic. [CITED: https://hex.pm/packages/swoosh] |
| Browser-style reset URL printed by task | Terminal reset request in email mode and break-glass task with honest operator wording | Phase 9 locked decision, 2026-04-24 | User-facing reset must not expose `/users/reset_password/:token`. [VERIFIED: `lib/mix/tasks/foglet.user.reset_password.ex`; VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-SPEC.md`] |
| Pending approval promises email | Pending approval copy must not promise Phase 10 notification delivery | Phase 9 locked decision, 2026-04-24 | Update Register/Login copy before MAIL-07 exists. [VERIFIED: `lib/foglet_bbs/tui/screens/register.ex`; VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-CONTEXT.md`] |

**Deprecated/outdated:**
- Existing comments saying "Phase 10 adds Swoosh delivery" are stale relative to the v1.2 roadmap; Phase 9 now owns verification/reset delivery. [VERIFIED: `lib/foglet_bbs/accounts.ex`; VERIFIED: `lib/mix/tasks/foglet.user.reset_password.ex`; VERIFIED: `.planning/ROADMAP.md`]
- `phoenix_swoosh` is optional for template rendering and not required for plain text transactional mail. [CITED: https://hexdocs.pm/phoenix_swoosh/Phoenix.Swoosh.html; CITED: https://hexdocs.pm/swoosh/Swoosh.html]

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Runtime env names should be adapter-specific, for example `FOGLET_MAILGUN_API_KEY`/`FOGLET_MAILGUN_DOMAIN` for Mailgun or `FOGLET_SMTP_RELAY`/`FOGLET_SMTP_USERNAME`/`FOGLET_SMTP_PASSWORD`/`FOGLET_SMTP_PORT` for SMTP. [ASSUMED] | Code Examples | Operator docs/tests may need different env names if project conventions choose alternatives. |
| A2 | `delivery_mode` enum strings should be `"email"` and `"no_email"`. [ASSUMED] | Architecture Patterns | This keeps the persisted runtime mode provider-agnostic while adapter selection remains in OTP runtime config. |
| A3 | Direct `Swoosh.Adapters.Test` assertions are sufficient for most Phase 9 tests. [ASSUMED] | Common Pitfalls | If delivery moves to a different process, tests may need `Swoosh.Adapters.Sandbox`. |

## Open Questions

1. **Exact no-email operator retrieval wording**
   - What we know: no-email verification/reset relay is out of scope, but MAIL-06 says operator can retrieve delivery details through an explicit no-email/operator-visible workflow. [VERIFIED: `.planning/REQUIREMENTS.md`; VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-CONTEXT.md`]
   - What's unclear: whether the planner should implement a read-only operator explanation surface only, or also expose existing break-glass generated details in email mode. [ASSUMED]
   - Recommendation: Follow CONTEXT D-11 and SPEC boundaries: no-email mode should make user reset unavailable and not generate relay details; operator surfaces should explain the implication explicitly. [VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-SPEC.md`]

2. **Email body exact copy**
   - What we know: user-facing terminal copy must be honest and reset copy must be enumeration-safe. [VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-SPEC.md`; CITED: https://cheatsheetseries.owasp.org/cheatsheets/Forgot_Password_Cheat_Sheet.html]
   - What's unclear: exact email subject/body text is discretionary. [VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-CONTEXT.md`]
   - Recommendation: Keep text-only transactional emails minimal and avoid browser-reset links in user-facing reset mail until a terminal reset completion flow exists. [VERIFIED: `CLAUDE.md`; VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-SPEC.md`]

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| Elixir | Build/tests | yes | 1.19.5 / OTP 28 | none needed. [VERIFIED: `elixir --version`] |
| Mix | Dependency and test tasks | yes | 1.19.5 / OTP 28 | none needed. [VERIFIED: `mix --version`] |
| Swoosh | Email delivery | no | not in `mix.exs` or `mix deps` | Add dependency. [VERIFIED: `mix.exs`; VERIFIED: `rtk mix deps`] |
| gen_smtp | SMTP adapter only | no | not in `mix.exs` or `mix deps` | Add dependency only if SMTP is documented as a supported runtime adapter. API-provider adapters do not need it. [VERIFIED: `mix.exs`; VERIFIED: `rtk mix deps`; CITED: https://hexdocs.pm/swoosh/Swoosh.Adapters.SMTP.html] |
| Provider credentials | Runtime email delivery | unknown | environment-specific | Tests use `Swoosh.Adapters.Test`; production docs must require env config for the selected Swoosh adapter. [ASSUMED] |

**Missing dependencies with no fallback:**
- `swoosh` must be added for email mode implementation; `gen_smtp` must be added only if SMTP is included as a supported adapter. [VERIFIED: `mix.exs`; CITED: https://hexdocs.pm/swoosh/Swoosh.html; CITED: https://hexdocs.pm/swoosh/Swoosh.Adapters.SMTP.html]

**Missing dependencies with fallback:**
- Real provider credentials are not needed for automated tests because Swoosh provides a test adapter. [CITED: https://hexdocs.pm/swoosh/Swoosh.Adapters.Test.html]

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | ExUnit, built into Elixir; current runtime Mix/Elixir `1.19.5`. [VERIFIED: `.planning/codebase/TESTING.md`; VERIFIED: `mix --version`] |
| Config file | `test/test_helper.exs`; `mix test` alias seeds config before tests. [VERIFIED: `.planning/codebase/TESTING.md`; VERIFIED: `mix.exs`] |
| Quick run command | `rtk mix test test/foglet_bbs/accounts/accounts_test.exs test/foglet_bbs/tui/screens/verify_test.exs` |
| Full suite command | `rtk mix precommit` |

### Phase Requirements -> Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| MAIL-01 | delivery mode schema/accessor and invalid no-email+verification config | unit/integration | `rtk mix test test/foglet_bbs/config/schema_test.exs test/foglet_bbs/tui/screens/sysop_site_form_test.exs` | partial; Wave 0 may add Sysop focused tests. [VERIFIED: `.planning/codebase/TESTING.md`] |
| MAIL-02 | registration/login verification delivery attempts Swoosh in email mode | integration | `rtk mix test test/foglet_bbs/accounts/accounts_test.exs test/foglet_bbs/tui/screens/register_test.exs test/foglet_bbs/tui/screens/login_test.exs` | yes, update existing. [VERIFIED: test files grep] |
| MAIL-03 | Verify resend cooldown remains independent and delivery copy is honest | unit | `rtk mix test test/foglet_bbs/tui/screens/verify_test.exs` | yes. [VERIFIED: `test/foglet_bbs/tui/screens/verify_test.exs`] |
| MAIL-04 | terminal reset request sends email only in email mode and remains generic | unit/integration | `rtk mix test test/foglet_bbs/accounts/accounts_test.exs test/foglet_bbs/tui/screens/login_test.exs test/mix/tasks/foglet_user_reset_password_test.exs` | partial; reset request UI tests need additions. [VERIFIED: `.planning/codebase/TESTING.md`] |
| MAIL-05 | terminal/Mix copy has no false email/notification claims | unit/snapshot-style assertions | `rtk mix test test/foglet_bbs/tui/screens/register_test.exs test/foglet_bbs/tui/screens/login_test.exs test/foglet_bbs/tui/screens/verify_test.exs test/mix/tasks/foglet_user_reset_password_test.exs` | yes, update existing. [VERIFIED: test files grep] |
| MAIL-06 | no-email operator-visible workflow makes reset/verification unavailable honestly | unit/integration | `rtk mix test test/foglet_bbs/tui/screens/sysop_site_form_test.exs test/mix/tasks/foglet_user_reset_password_test.exs` | partial; likely add focused tests. [VERIFIED: `.planning/codebase/TESTING.md`] |

### Sampling Rate

- **Per task commit:** Run the focused file touched by the task, usually `rtk mix test path/to/file_test.exs`. [VERIFIED: `.planning/codebase/TESTING.md`]
- **Per wave merge:** Run all Phase 9 touched test files plus `rtk mix compile --warnings-as-errors`. [VERIFIED: `CLAUDE.md`]
- **Phase gate:** `rtk mix precommit` green before `/gsd-verify-work`. [VERIFIED: `CLAUDE.md`]

### Wave 0 Gaps

- [ ] Add Swoosh test configuration and dependency setup before delivery tests. [VERIFIED: `mix.exs`; CITED: https://hexdocs.pm/swoosh/Swoosh.Adapters.Test.html]
- [ ] Add or extend Sysop SiteForm tests for `delivery_mode` placement and no-email+verification blocking. [VERIFIED: `lib/foglet_bbs/tui/screens/sysop/site_form.ex`]
- [ ] Add Accounts delivery tests using `Swoosh.TestAssertions`. [CITED: https://hexdocs.pm/swoosh/Swoosh.Adapters.Test.html]
- [ ] Add Login reset-request tests because no terminal reset subflow exists today. [VERIFIED: `lib/foglet_bbs/tui/screens/login.ex`]

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|------------------|
| V2 Authentication | yes | Existing Accounts password/token functions plus OWASP reset request controls. [VERIFIED: `lib/foglet_bbs/accounts.ex`; CITED: https://cheatsheetseries.owasp.org/cheatsheets/Forgot_Password_Cheat_Sheet.html] |
| V3 Session Management | no direct change | Do not auto-login after reset request; no session mutation occurs in request step. [CITED: https://cheatsheetseries.owasp.org/cheatsheets/Forgot_Password_Cheat_Sheet.html] |
| V4 Access Control | yes | Sysop config writes use `Config.put/3` and Bodyguard authorization. [VERIFIED: `lib/foglet_bbs/config.ex`; VERIFIED: `CLAUDE.md`] |
| V5 Input Validation | yes | Config enum/range validation through `Foglet.Config.Schema`; reset identifier normalized in Accounts. [VERIFIED: `lib/foglet_bbs/config/schema.ex`; ASSUMED] |
| V6 Cryptography | yes | Reuse existing cryptographically-generated token/code helpers; do not create custom random token logic. [VERIFIED: `lib/foglet_bbs/accounts.ex`; CITED: https://cheatsheetseries.owasp.org/cheatsheets/Forgot_Password_Cheat_Sheet.html] |
| V9 Communications | yes | Provider credentials in runtime env; TLS/auth options configured through the selected Swoosh adapter. [VERIFIED: `CLAUDE.md`; CITED: https://hexdocs.pm/swoosh/Swoosh.Mailer.html] |

### Known Threat Patterns for Foglet Phase 9

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| User enumeration through reset request | Information Disclosure | Uniform outward message for existent and non-existent accounts. [CITED: https://cheatsheetseries.owasp.org/cheatsheets/Forgot_Password_Cheat_Sheet.html] |
| False delivery claims | Repudiation / Integrity | Copy only says email was attempted after Accounts calls Swoosh; no-email mode uses unavailable copy. [VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-SPEC.md`] |
| Secret leakage through DB config | Information Disclosure | Keep provider credentials in runtime/environment config. [VERIFIED: `CLAUDE.md`] |
| Token brute force or stale token use | Tampering / Elevation | Reuse existing expiring/single-use token semantics and cooldowns; preserve Verify cooldown tests. [VERIFIED: `lib/foglet_bbs/accounts.ex`; VERIFIED: `lib/foglet_bbs/tui/screens/verify.ex`] |
| Host-header/browser reset confusion | Spoofing / Information Disclosure | Do not expose browser reset URLs to users in Phase 9. [VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-SPEC.md`; CITED: https://cheatsheetseries.owasp.org/cheatsheets/Forgot_Password_Cheat_Sheet.html] |

## Sources

### Primary (HIGH confidence)
- `CLAUDE.md` - project boundaries, config/secrets, TUI/context, and testing directives.
- `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-CONTEXT.md` - locked implementation decisions and deferred work.
- `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-SPEC.md` - locked requirements and acceptance criteria.
- `.planning/REQUIREMENTS.md` - MAIL-01 through MAIL-06.
- `lib/foglet_bbs/config.ex`, `lib/foglet_bbs/config/schema.ex` - current runtime config implementation.
- `lib/foglet_bbs/accounts.ex` - current verification/reset token APIs.
- `lib/foglet_bbs/tui/screens/login.ex`, `register.ex`, `verify.ex`, `sysop/site_form.ex` - current TUI integration points.
- `lib/mix/tasks/foglet.user.reset_password.ex` - current operator reset task.
- https://hex.pm/packages/swoosh - current Swoosh version/package metadata.
- https://hexdocs.pm/swoosh/Swoosh.Mailer.html - mailer API/config.
- https://hexdocs.pm/swoosh/Swoosh.Adapters.SMTP.html - SMTP adapter and `gen_smtp` requirement.
- https://hexdocs.pm/swoosh/Swoosh.Adapters.Test.html - test adapter behavior.
- https://cheatsheetseries.owasp.org/cheatsheets/Forgot_Password_Cheat_Sheet.html - reset request security controls.

### Secondary (MEDIUM confidence)
- https://hex.pm/packages/gen_smtp - latest `gen_smtp` version metadata.
- https://hexdocs.pm/phoenix_swoosh/Phoenix.Swoosh.html - optional template rendering context.

### Tertiary (LOW confidence)
- None.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - locked by phase context and verified against current Hex/HexDocs. [VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-CONTEXT.md`; CITED: https://hex.pm/packages/swoosh]
- Architecture: HIGH - project conventions and current module boundaries are explicit and verified in code. [VERIFIED: `CLAUDE.md`; VERIFIED: `lib/foglet_bbs/config.ex`; VERIFIED: `lib/foglet_bbs/accounts.ex`]
- Pitfalls: HIGH - current code demonstrates the delivery-honesty gap and OWASP verifies reset enumeration risks. [VERIFIED: `lib/foglet_bbs/tui/screens/verify.ex`; CITED: https://cheatsheetseries.owasp.org/cheatsheets/Forgot_Password_Cheat_Sheet.html]

**Research date:** 2026-04-24  
**Valid until:** 2026-05-01 for package-version assertions; phase/codebase findings valid until touched.
