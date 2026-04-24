# Phase 15: Reset Path Gap Closure - Research

**Researched:** 2026-04-24
**Domain:** SSH-first password reset delivery, break-glass Mix task output, operator documentation, and ExUnit coverage
**Confidence:** HIGH

## User Constraints

No Phase 15 `CONTEXT.md` exists yet. [VERIFIED: `gsd-sdk query init.phase-op 15`]

Locked constraints for planning come from the roadmap, requirements, milestone audit, Phase 14 verification, and project instructions:

- Foglet is SSH-first/TUI-first; Phoenix is infrastructure, and end-user browser workflows are out of scope unless architecture docs are updated. [VERIFIED: `AGENTS.md`, `.planning/PROJECT.md`, `.planning/REQUIREMENTS.md`]
- Phase 15 must address MAIL-04, MAIL-06, HYGN-02, and HYGN-03. [VERIFIED: `.planning/ROADMAP.md`, `.planning/REQUIREMENTS.md`]
- Phase 15 closes audit gaps MAIL-04, MAIL-06, HYGN-02, HYGN-03, INT-01, INT-02, FLOW-RESET-01, and FLOW-RESET-02. [VERIFIED: `.planning/ROADMAP.md`, `.planning/v1.2-MILESTONE-AUDIT.md`]
- The break-glass reset Mix task must stop emitting a browser reset URL unless a supported route or SSH/TUI token-consumption path exists. [VERIFIED: `.planning/ROADMAP.md`, `.planning/v1.2-MILESTONE-AUDIT.md`]
- SMTP password reset and no-email/operator retrieval copy must expose a raw token or supported terminal-native instruction without claiming unsupported browser behavior. [VERIFIED: `.planning/ROADMAP.md`, `.planning/v1.2-MILESTONE-AUDIT.md`]
- Focused reset blocker tests must assert happy path, forbidden path, and user/operator-facing copy for the supported reset flow. [VERIFIED: `.planning/ROADMAP.md`, `.planning/REQUIREMENTS.md`]
- README operator notes and Phase 14 blocker records must agree about reset support. [VERIFIED: `.planning/ROADMAP.md`, `.planning/v1.2-MILESTONE-AUDIT.md`]
- Use `rtk` as the shell command prefix in this repo, including `rtk mix test` and `rtk mix precommit`. [VERIFIED: `AGENTS.md`, `/Users/brendan.turner/.codex/RTK.md`]
- Domain behavior belongs in `Foglet.*` contexts, not controllers, SSH callbacks, or TUI render functions. [VERIFIED: `AGENTS.md`]
- Context mutations must use authorization boundaries where actor-triggered side effects exist; hidden or disabled UI is never authorization. [VERIFIED: `AGENTS.md`]
- Runtime config uses `Foglet.Config` typed accessors over an ETS-backed database cache; secrets stay in environment/runtime config, not DB-backed config. [VERIFIED: `AGENTS.md`]

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| MAIL-04 | User can receive a password reset email when SMTP delivery is configured, while the existing Mix task remains available as a break-glass path. [VERIFIED: `.planning/REQUIREMENTS.md`] | Existing email delivery sends a raw reset token with terminal-native copy; the break-glass task should reuse token generation but stop presenting the token as an HTTP URL. [VERIFIED: `lib/foglet_bbs/accounts.ex`, `lib/foglet_bbs/accounts/email.ex`, `lib/mix/tasks/foglet.user.reset_password.ex`] |
| MAIL-06 | Operator can retrieve verification, reset, or pending-approval delivery details through an explicit no-email/operator-visible workflow when SMTP delivery is disabled. [VERIFIED: `.planning/REQUIREMENTS.md`] | Verification retrieval already has a Mix task pattern; reset retrieval exists but currently prints an unsupported URL, so planning should convert it to token/details output. [VERIFIED: `lib/mix/tasks/foglet.user.verification_code.ex`, `lib/mix/tasks/foglet.user.reset_password.ex`, `.planning/v1.2-MILESTONE-AUDIT.md`] |
| HYGN-02 | Pre-alpha blocker flows have focused tests for happy path, forbidden path, and user-facing error/copy behavior. [VERIFIED: `.planning/REQUIREMENTS.md`] | Current reset task tests cover token persistence and forbidden handles/deleted users but assert `/users/reset_password/`; they must be rewritten around token output and browser-free copy. [VERIFIED: `test/mix/tasks/foglet_user_reset_password_test.exs`, `.planning/phases/14-launch-hygiene-and-operator-notes/14-VERIFICATION.md`] |
| HYGN-03 | Pre-alpha docs or operator notes describe how to run Foglet in SMTP mode and no-email mode. [VERIFIED: `.planning/REQUIREMENTS.md`] | README currently says the reset task generates an operator reset URL and says no upstream Phase 9-13 blockers are recorded, contradicting the Phase 14 blocker log. [VERIFIED: `README.md`, `.planning/phases/14-launch-hygiene-and-operator-notes/14-BLOCKERS.md`, `.planning/v1.2-MILESTONE-AUDIT.md`] |

## Summary

Phase 15 should close a launch-honesty defect, not add a new browser reset product surface. Foglet already has a terminal-native password-reset email builder that exposes a raw reset token and explicitly tells users to return to SSH; the unsupported behavior is concentrated in `mix foglet.user.reset_password`, which builds `https://<host>/users/reset_password/<token>` even though `FogletBbsWeb.Router` exposes no reset route. [VERIFIED: `lib/foglet_bbs/accounts/email.ex`, `lib/mix/tasks/foglet.user.reset_password.ex`, `lib/foglet_bbs_web/router.ex`]

The planner should use existing Accounts/UserToken primitives and rewrite the break-glass output, tests, README, and Phase 14 blocker records around raw token retrieval or explicit operator-assisted terminal instructions. [VERIFIED: `lib/foglet_bbs/accounts.ex`, `lib/foglet_bbs/accounts/user_token.ex`, `test/mix/tasks/foglet_user_reset_password_test.exs`, `README.md`]

**Primary recommendation:** Change `mix foglet.user.reset_password HANDLE` to print a raw reset token and SSH/operator instructions, never `/users/reset_password/`, then update reset tests and README/blocker records to match. [VERIFIED: `.planning/ROADMAP.md`, `.planning/v1.2-MILESTONE-AUDIT.md`, codebase grep]

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|--------------|----------------|-----------|
| Reset token generation and verification | API / Backend (`Foglet.Accounts`, `Foglet.Accounts.UserToken`) | Database / Storage (`user_tokens`) | Accounts owns password reset mutation and token persistence; `user_tokens` stores hashed reset token rows. [VERIFIED: `AGENTS.md`, `lib/foglet_bbs/accounts.ex`, `lib/foglet_bbs/accounts/user_token.ex`] |
| SMTP reset delivery | API / Backend (`Foglet.Accounts`, `Foglet.Accounts.Email`, `Foglet.Mailer`) | External mail adapter | `request_password_reset_delivery/1` is delivery-mode aware and `Email.password_reset/2` builds terminal-native token email. [VERIFIED: `lib/foglet_bbs/accounts.ex`, `lib/foglet_bbs/accounts/email.ex`, `config/test.exs`] |
| Break-glass operator reset retrieval | CLI / Backend (`Mix.Tasks.Foglet.User.ResetPassword`) | API / Backend (`Foglet.Accounts`) | Mix task is the operator entry point and should delegate token creation to Accounts instead of creating separate token logic. [VERIFIED: `lib/mix/tasks/foglet.user.reset_password.ex`, `lib/foglet_bbs/accounts.ex`] |
| Reset user interaction | SSH / TUI | API / Backend | Login screen currently offers password reset request only in email mode; no TUI token-consumption screen was found. [VERIFIED: `lib/foglet_bbs/tui/screens/login.ex`, codebase grep] |
| Browser reset route | Not owned in v1.2 | Phoenix operational infrastructure | Router exposes `/`, `/api`, and dev dashboard only; project constraints prohibit end-user browser workflows for this milestone. [VERIFIED: `lib/foglet_bbs_web/router.ex`, `AGENTS.md`, `.planning/REQUIREMENTS.md`] |
| Operator docs and blocker alignment | Documentation / Planning artifacts | Tests as regression guard | README and Phase 14 blocker records currently disagree and must be made consistent. [VERIFIED: `README.md`, `.planning/phases/14-launch-hygiene-and-operator-notes/14-BLOCKERS.md`] |

## Standard Stack

### Core

| Library / Module | Version | Purpose | Why Standard |
|------------------|---------|---------|--------------|
| Elixir / Mix | Mix 1.19.5 on Erlang/OTP 28 | Build, Mix tasks, ExUnit | Existing project runtime and command surface. [VERIFIED: `rtk mix --version`, `mix.exs`] |
| Phoenix | 1.8.5 | Operational endpoint/router/PubSub infrastructure | Existing app foundation; not the user reset surface for v1.2. [VERIFIED: `mix.lock`, `AGENTS.md`, `lib/foglet_bbs_web/router.ex`] |
| Ecto SQL | 3.13.5 | Repo queries and transactions | Existing persistence layer for users and tokens. [VERIFIED: `mix.lock`, `lib/foglet_bbs/accounts.ex`] |
| Swoosh | 1.25.0 | Transactional email construction/delivery | Existing mailer boundary for verification, reset, and status notices. [VERIFIED: `mix.lock`, `config/test.exs`, `lib/foglet_bbs/accounts/email.ex`] |
| Argon2 | argon2_elixir 4.1.3 | Password hashing and reset-password verification tests | Existing password hashing dependency used by reset tests. [VERIFIED: `mix.lock`, `test/foglet_bbs/accounts/accounts_test.exs`] |
| `Foglet.Accounts.UserToken` | local module | Reset token construction, hashing, expiry, verification query | Existing phx.gen.auth-style token primitive with 1-day reset token validity. [VERIFIED: `lib/foglet_bbs/accounts/user_token.ex`] |

### Supporting

| Library / Module | Version | Purpose | When to Use |
|------------------|---------|---------|-------------|
| ExUnit | bundled with Mix 1.19.5 | Focused unit/integration tests | Use for Accounts, Mix task, TUI copy, and README/blocker grep checks. [VERIFIED: `rtk mix --version`, existing tests] |
| Swoosh test adapter/assertions | Swoosh 1.25.0 | Assert reset email content in tests | Use where SMTP-mode reset behavior is verified. [VERIFIED: `config/test.exs`, `test/foglet_bbs/accounts/accounts_test.exs`] |
| `Foglet.Config` | local module | Delivery-mode reads and test setup/restore | Use `Config.delivery_mode/0` or `Config.put!/3` in task/tests, restoring cache state in `on_exit`. [VERIFIED: `lib/foglet_bbs/config.ex`, existing tests] |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Raw token output in Mix task | Add Phoenix `/users/reset_password/:token` route | Contradicts SSH-first v1.2 boundary and expands browser product surface. [VERIFIED: `AGENTS.md`, `.planning/REQUIREMENTS.md`, `lib/foglet_bbs_web/router.ex`] |
| Raw token output in Mix task | Add full TUI token-consumption reset screen now | Could be valid future work, but no existing TUI token-consumption path was found and Phase 15 success criteria allow token or supported terminal-native instruction. [VERIFIED: codebase grep, `.planning/ROADMAP.md`] |
| Existing Accounts/UserToken primitives | Hand-roll separate CLI token storage | Would duplicate hashing, expiry, sent-to, and invalidation semantics already present in `UserToken` and Accounts. [VERIFIED: `lib/foglet_bbs/accounts/user_token.ex`, `lib/foglet_bbs/accounts.ex`] |

**Installation:** No new packages should be added. [VERIFIED: `mix.exs`, phase scope]

**Version verification:** Versions above are from `mix.lock` and `rtk mix --version`, not npm. [VERIFIED: `mix.lock`, `rtk mix --version`]

## Architecture Patterns

### System Architecture Diagram

```text
SMTP reset request from Login (email mode)
  -> Foglet.TUI.Screens.Login
  -> Foglet.Accounts.request_password_reset_delivery(identifier)
  -> delivery_mode == "email"?
       yes -> find active user by handle/email
          -> UserToken.build_email_token(user, "reset_password")
          -> Repo.insert(user_tokens hashed token)
          -> Foglet.Accounts.Email.password_reset(user, raw_token)
          -> Foglet.Mailer.deliver(...)
          -> generic TUI response
       no -> {:error, :unavailable}

Break-glass/no-email operator retrieval
  -> mix foglet.user.reset_password HANDLE
  -> Accounts.get_user_by_handle(handle)
  -> reject missing/deleted user
  -> Accounts reset-token helper / existing deliver_user_reset_password_instructions
  -> UserToken.build_email_token + Repo.insert
  -> print raw token + terminal/operator instructions
  -> never print /users/reset_password/ unless a supported route exists
```

Diagram facts are verified against `lib/foglet_bbs/tui/screens/login.ex`, `lib/foglet_bbs/accounts.ex`, `lib/foglet_bbs/accounts/email.ex`, and `lib/mix/tasks/foglet.user.reset_password.ex`. [VERIFIED: codebase grep]

### Recommended Project Structure

```text
lib/
├── foglet_bbs/accounts.ex                 # token generation/reset mutation boundary
├── foglet_bbs/accounts/email.ex           # SMTP reset email copy
├── foglet_bbs/accounts/user_token.ex      # hashed reset token semantics
└── mix/tasks/foglet.user.reset_password.ex # break-glass operator retrieval output

test/
├── foglet_bbs/accounts/accounts_test.exs  # SMTP email/token semantics
├── foglet_bbs/tui/screens/login_test.exs  # reset request UI/copy
├── foglet_bbs/tui/screens/delivery_copy_test.exs # browser-free copy audit
└── mix/tasks/foglet_user_reset_password_test.exs # operator task happy/forbidden/copy paths

README.md
.planning/phases/14-launch-hygiene-and-operator-notes/14-BLOCKERS.md
```

This structure mirrors existing source/test locations. [VERIFIED: codebase grep]

### Pattern 1: Reuse Hashed Reset Token Primitive

**What:** Generate raw reset tokens with `UserToken.build_email_token(user, "reset_password")`, persist only the hashed token row, and expose the raw token only in the immediate delivery channel. [VERIFIED: `lib/foglet_bbs/accounts/user_token.ex`, `lib/foglet_bbs/accounts.ex`]

**When to use:** Use this for SMTP password reset email and break-glass operator retrieval. [VERIFIED: `lib/foglet_bbs/accounts.ex`, `lib/mix/tasks/foglet.user.reset_password.ex`]

**Example:**

```elixir
# Source: lib/foglet_bbs/accounts.ex and lib/foglet_bbs/accounts/user_token.ex
{raw, token_struct} = UserToken.build_email_token(user, "reset_password")
{:ok, _token} = Repo.insert(token_struct)
raw
```

### Pattern 2: Mode-Honest Operator Copy

**What:** Keep email-mode and no-email-mode operator output distinct, but both should print terminal-native instructions and avoid `http://`, `https://`, or `/users/reset_password/`. [VERIFIED: `.planning/ROADMAP.md`, `.planning/v1.2-MILESTONE-AUDIT.md`, `test/foglet_bbs/tui/screens/delivery_copy_test.exs`]

**When to use:** Use in `Mix.Tasks.Foglet.User.ResetPassword` and any README/operator examples. [VERIFIED: `lib/mix/tasks/foglet.user.reset_password.ex`, `README.md`]

**Example:**

```elixir
# Source pattern: test/mix/tasks/foglet_user_verification_code_test.exs style + Phase 15 audit requirement
Mix.shell().info("No-email reset details for #{user.handle}:")
Mix.shell().info("  Reset token: #{raw_token}")
Mix.shell().info("Give this token to the user through your operator-assisted SSH reset procedure.")
```

### Pattern 3: Enumeration-Safe SMTP Request, Explicit Operator Task

**What:** User-facing reset requests in email mode return a generic response, while operator tasks can report missing/deleted-user errors because they are break-glass tooling. [VERIFIED: `lib/foglet_bbs/accounts.ex`, `test/foglet_bbs/accounts/accounts_test.exs`, `test/mix/tasks/foglet_user_reset_password_test.exs`]

**When to use:** Preserve generic Login reset copy; do not leak account existence through the TUI request path. [VERIFIED: `lib/foglet_bbs/tui/screens/login.ex`, `test/foglet_bbs/tui/screens/login_test.exs`]

### Anti-Patterns to Avoid

- **Adding `/users/reset_password/:token` only to satisfy existing task copy:** This creates an end-user browser workflow explicitly outside v1.2 scope. [VERIFIED: `AGENTS.md`, `.planning/REQUIREMENTS.md`, `.planning/v1.2-MILESTONE-AUDIT.md`]
- **Printing a reset URL when no route consumes it:** This is the critical Phase 15 blocker. [VERIFIED: `.planning/v1.2-MILESTONE-AUDIT.md`, `.planning/phases/14-launch-hygiene-and-operator-notes/14-VERIFICATION.md`]
- **Duplicating token generation in the Mix task:** `UserToken` already handles random bytes, base64url encoding, hashing, expiry, and sent-to matching. [VERIFIED: `lib/foglet_bbs/accounts/user_token.ex`]
- **Claiming “email was sent” from break-glass task:** The current task does not send email and tests already guard that copy. [VERIFIED: `lib/mix/tasks/foglet.user.reset_password.ex`, `test/mix/tasks/foglet_user_reset_password_test.exs`]
- **Reintroducing direct README-specific ExUnit tests:** Phase 14 removed README tests by user request; use targeted grep/manual verification instead unless the user reverses that decision. [VERIFIED: `.planning/phases/14-launch-hygiene-and-operator-notes/14-03-SUMMARY.md`, `.planning/phases/14-launch-hygiene-and-operator-notes/14-VERIFICATION.md`]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Reset token cryptography | Custom token encoding/hash/expiry logic in Mix task | `Foglet.Accounts.UserToken.build_email_token/2` and `verify_email_token_query/2` | Existing token code stores hashed raw tokens, base64url encodes raw token, and enforces 1-day reset expiry. [VERIFIED: `lib/foglet_bbs/accounts/user_token.ex`] |
| Password update semantics | Direct `Repo.update` from Mix task | `Foglet.Accounts.reset_user_password/2` when a supported token consumption path exists | Existing function changes password and deletes outstanding reset tokens. [VERIFIED: `lib/foglet_bbs/accounts.ex`, `test/foglet_bbs/accounts/accounts_test.exs`] |
| SMTP reset email | Manual mail structs outside Accounts.Email | `Foglet.Accounts.Email.password_reset/2` via `Foglet.Mailer` | Existing email copy is terminal-native and browser-free. [VERIFIED: `lib/foglet_bbs/accounts/email.ex`, `test/foglet_bbs/accounts/accounts_test.exs`] |
| Delivery-mode persistence | New env vars or string scattering | `Foglet.Config.delivery_mode/0` | Delivery mode is already schematized and visible in Sysop config. [VERIFIED: `lib/foglet_bbs/config.ex`, `lib/foglet_bbs/config/schema.ex`, Phase 14 config tests] |
| README consistency checks | Broad brittle README test suite | Focused grep/manual audit plus code tests | README-specific tests were removed by user request; Phase 15 can still assert no reset URL strings with grep. [VERIFIED: `.planning/phases/14-launch-hygiene-and-operator-notes/14-03-SUMMARY.md`] |

**Key insight:** The existing secure primitive is a reset token, not a URL; Phase 15 should make every surface tell the truth about that primitive. [VERIFIED: `lib/foglet_bbs/accounts/user_token.ex`, `.planning/v1.2-MILESTONE-AUDIT.md`]

## Common Pitfalls

### Pitfall 1: Treating Browser URL Removal as Enough

**What goes wrong:** The task stops printing `https://...` but README or tests still describe an operator reset URL. [VERIFIED: current `README.md`, `test/mix/tasks/foglet_user_reset_password_test.exs`]

**Why it happens:** Phase 14 changed docs and blocker records in separate places, creating contradictory claims. [VERIFIED: `.planning/phases/14-launch-hygiene-and-operator-notes/14-VERIFICATION.md`]

**How to avoid:** Plan one task that updates Mix task output and tests, and one task that updates README plus `14-BLOCKERS.md` consistency. [VERIFIED: `.planning/ROADMAP.md`]

**Warning signs:** `rtk rg -n "/users/reset_password|operator reset URL|reset URL" README.md lib test .planning/phases/14-launch-hygiene-and-operator-notes/14-BLOCKERS.md` still finds launch-supporting claims. [VERIFIED: codebase grep]

### Pitfall 2: Accidentally Creating an Unsupported Product Surface

**What goes wrong:** Planner adds Phoenix reset routes to make old URL tests pass. [VERIFIED: `.planning/v1.2-MILESTONE-AUDIT.md`]

**Why it happens:** The task currently names a route shape that looks like generated Phoenix auth. [VERIFIED: `lib/mix/tasks/foglet.user.reset_password.ex`]

**How to avoid:** Keep Phase 15 scoped to SSH/operator-supported behavior unless the architecture docs explicitly change. [VERIFIED: `AGENTS.md`, `.planning/REQUIREMENTS.md`]

**Warning signs:** New `FogletBbsWeb.UserResetPasswordController`, router `get "/users/reset_password/:token"`, or browser form tests appear in the plan. [VERIFIED: current router lacks those routes]

### Pitfall 3: Leaking Account Enumeration in User-Facing Reset Flow

**What goes wrong:** Login reset copy or Accounts return values reveal whether an identifier exists. [VERIFIED: existing `request_password_reset_delivery/1` tests]

**Why it happens:** Operator task semantics are explicit, but user-facing reset request semantics are generic. [VERIFIED: `lib/foglet_bbs/accounts.ex`, `test/foglet_bbs/accounts/accounts_test.exs`]

**How to avoid:** Do not change `request_password_reset_delivery/1` outward response shape while fixing the Mix task. [VERIFIED: `lib/foglet_bbs/accounts.ex`]

**Warning signs:** TUI reset request messages include “user not found,” “pending,” “suspended,” or “deleted.” [VERIFIED: `test/foglet_bbs/accounts/accounts_test.exs`]

### Pitfall 4: Losing Reset Token Invalidations

**What goes wrong:** A future token-consumption path updates password but leaves old reset tokens valid. [VERIFIED: `reset_user_password/2` behavior]

**Why it happens:** Direct schema updates bypass Accounts context invariants. [VERIFIED: `AGENTS.md`, `lib/foglet_bbs/accounts.ex`]

**How to avoid:** Use `Accounts.reset_user_password/2` for actual password changes. [VERIFIED: `lib/foglet_bbs/accounts.ex`]

**Warning signs:** Tests update `User.password_changeset` directly outside Accounts for reset completion. [VERIFIED: codebase grep]

## Code Examples

Verified patterns from project sources:

### Browser-Free Password Reset Email

```elixir
# Source: lib/foglet_bbs/accounts/email.ex
def password_reset(%User{} = user, reset_token) when is_binary(reset_token) do
  new()
  |> to({user.handle, user.email})
  |> from(@from)
  |> subject("Foglet password reset instructions")
  |> text_body("""
  A password reset was requested for your Foglet account.

  Reset token:

  #{reset_token}

  Return to the SSH terminal reset flow and enter this token when prompted.
  """)
end
```

### Reset Token Verification Query

```elixir
# Source: lib/foglet_bbs/accounts/user_token.ex
{:ok, query} = UserToken.verify_email_token_query(raw_token, "reset_password")
user = Repo.one(query)
```

### Reset Password Mutation Invalidates Tokens

```elixir
# Source: lib/foglet_bbs/accounts.ex
Repo.transact(fn ->
  with {:ok, updated} <- user |> User.password_changeset(attrs) |> Repo.update() do
    Repo.delete_all(UserToken.by_user_and_contexts_query(user, ["reset_password"]))
    {:ok, updated}
  end
end)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Browser reset URL in break-glass task | Raw reset token plus SSH/operator instructions | Phase 15 should make this change. [VERIFIED: `.planning/ROADMAP.md`] | Closes MAIL-04, MAIL-06, HYGN-02, HYGN-03 launch honesty gap. [VERIFIED: `.planning/v1.2-MILESTONE-AUDIT.md`] |
| Email reset body with URL-style reset | Terminal-native token email | Already implemented before Phase 15. [VERIFIED: `lib/foglet_bbs/accounts/email.ex`, tests] | SMTP reset delivery can stay browser-free. [VERIFIED: `test/foglet_bbs/accounts/accounts_test.exs`] |
| README says no blockers and documents reset URL | README should document token/operator-assisted reset and reference resolved blocker state | Phase 15 should make this change. [VERIFIED: `README.md`, `.planning/phases/14-launch-hygiene-and-operator-notes/14-BLOCKERS.md`] | Removes INT-02 contradiction. [VERIFIED: `.planning/v1.2-MILESTONE-AUDIT.md`] |

**Deprecated/outdated:**
- `https://<host>/users/reset_password/<token>` output is deprecated for v1.2 because no matching router route or TUI consumption path exists. [VERIFIED: `lib/mix/tasks/foglet.user.reset_password.ex`, `lib/foglet_bbs_web/router.ex`, codebase grep]
- README wording “operator reset URL” is outdated because Phase 14 verification records it as a false promise. [VERIFIED: `README.md`, `.planning/phases/14-launch-hygiene-and-operator-notes/14-VERIFICATION.md`]

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | It is unclear whether the user wants actual in-terminal password reset completion now or is satisfied with operator-assisted retrieval honesty. [ASSUMED] | Open Questions | Planner may choose too small or too large a Phase 15 scope. |
| A2 | It is unclear whether planner should keep `deliver_user_reset_password_instructions/2` API compatibility or introduce a clearer helper like `generate_reset_token_for_operator/1`. [ASSUMED] | Open Questions | Planner may choose an awkward API shape that preserves URL terminology. |

## Open Questions

1. **Should Phase 15 implement a real TUI token-consumption flow, or only make retrieval honest?**
   - What we know: Success criteria allow a token or supported terminal-native reset instruction, and no TUI token-consumption path is currently wired. [VERIFIED: `.planning/ROADMAP.md`, codebase grep]
   - What's unclear: Whether the user wants actual in-terminal password reset completion now or is satisfied with operator-assisted retrieval honesty. [ASSUMED]
   - Recommendation: Plan the minimum closure as raw token retrieval and browser-free copy; add a future phase for TUI token consumption if desired. [VERIFIED: phase scope + current codebase]

2. **Should `Accounts.deliver_user_reset_password_instructions/2` be renamed or supplemented?**
   - What we know: It persists a reset token and returns `url_fn.(raw)`, and its docs still say “return the URL.” [VERIFIED: `lib/foglet_bbs/accounts.ex`]
   - What's unclear: Whether planner should keep API compatibility and pass an identity/token formatting function, or introduce a clearer helper like `generate_reset_token_for_operator/1`. [ASSUMED]
   - Recommendation: Prefer adding a small clearly named Accounts helper if it reduces URL terminology, while keeping behavior centralized in Accounts/UserToken. [VERIFIED: `AGENTS.md`, existing context boundary]

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| `rtk` | All repo commands | Yes | Installed; command wrapper verified by successful `rtk ...` commands. [VERIFIED: command execution] | Use `rtk proxy <cmd>` only if wrapper filtering blocks required output. [VERIFIED: RTK docs] |
| Mix / Elixir | Tests and Mix task changes | Yes | Mix 1.19.5, Erlang/OTP 28. [VERIFIED: `rtk mix --version`] | None needed. |
| PostgreSQL test DB | DataCase and Mix task tests | Required by existing `mix test` alias | Test config points to localhost PostgreSQL with SQL sandbox. [VERIFIED: `config/test.exs`, `mix.exs`] | Planner should run existing targeted tests; if DB unavailable, execution is blocked. |
| Swoosh test adapter | Email reset tests | Yes | Swoosh 1.25.0 with `Swoosh.Adapters.Test` in test config. [VERIFIED: `mix.lock`, `config/test.exs`] | None needed. |

**Missing dependencies with no fallback:**
- None found during research. [VERIFIED: command execution and config inspection]

**Missing dependencies with fallback:**
- None found during research. [VERIFIED: command execution and config inspection]

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | ExUnit with Mix aliases. [VERIFIED: `mix.exs`, `test/test_helper.exs`] |
| Config file | `config/test.exs`. [VERIFIED: `config/test.exs`] |
| Quick run command | `rtk mix test test/mix/tasks/foglet_user_reset_password_test.exs test/foglet_bbs/accounts/accounts_test.exs test/foglet_bbs/tui/screens/delivery_copy_test.exs test/foglet_bbs/tui/screens/login_test.exs` |
| Full suite command | `rtk mix precommit`. [VERIFIED: `AGENTS.md`, `mix.exs`] |

### Phase Requirements -> Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| MAIL-04 | SMTP reset delivery sends terminal-native token email; break-glass remains available without email. [VERIFIED: requirements + code] | unit/integration | `rtk mix test test/foglet_bbs/accounts/accounts_test.exs test/mix/tasks/foglet_user_reset_password_test.exs` | Yes, update required. |
| MAIL-06 | No-email operator reset retrieval prints token/details without URL. [VERIFIED: requirements + current task] | Mix task | `rtk mix test test/mix/tasks/foglet_user_reset_password_test.exs` | Yes, update required. |
| HYGN-02 | Reset blocker tests cover happy path, forbidden path, and copy. [VERIFIED: requirements + Phase 14 verification] | Mix task + copy audit | `rtk mix test test/mix/tasks/foglet_user_reset_password_test.exs test/foglet_bbs/tui/screens/delivery_copy_test.exs` | Yes, update required. |
| HYGN-03 | README and Phase 14 blocker records agree about supported reset behavior. [VERIFIED: requirements + audit] | grep/manual docs audit | `rtk rg -n "/users/reset_password|operator reset URL|reset URL" README.md .planning/phases/14-launch-hygiene-and-operator-notes/14-BLOCKERS.md` | Yes, update required. |

### Sampling Rate

- **Per task commit:** Run the narrowest affected command, usually `rtk mix test test/mix/tasks/foglet_user_reset_password_test.exs`. [VERIFIED: existing validation style]
- **Per wave merge:** Run the quick run command above. [VERIFIED: affected files]
- **Phase gate:** Run `rtk mix precommit` before verification. [VERIFIED: `AGENTS.md`, `mix.exs`]

### Wave 0 Gaps

- [ ] Update `test/mix/tasks/foglet_user_reset_password_test.exs` so it rejects browser URLs and validates raw-token round trip. [VERIFIED: current test asserts `/users/reset_password/`]
- [ ] Update or add copy audit coverage to ensure task/TUI/email reset copy remains browser-free. [VERIFIED: `test/foglet_bbs/tui/screens/delivery_copy_test.exs`]
- [ ] Add a documentation grep/manual check for README and `14-BLOCKERS.md` consistency without reintroducing README-specific ExUnit tests. [VERIFIED: Phase 14 user override]

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|------------------|
| V2 Authentication | Yes | Reset tokens are random, base64url raw values with hashed database storage; password reset uses Accounts context. [VERIFIED: `lib/foglet_bbs/accounts/user_token.ex`, `lib/foglet_bbs/accounts.ex`] |
| V3 Session Management | No direct change | Phase 15 does not change login sessions. [VERIFIED: phase scope] |
| V4 Access Control | Yes | Operator task rejects missing/deleted users; any future interactive mutation should remain in Accounts authorization boundary. [VERIFIED: `test/mix/tasks/foglet_user_reset_password_test.exs`, `AGENTS.md`] |
| V5 Input Validation | Yes | Mix task requires a handle and rejects unknown flags through `OptionParser.parse!/2`. [VERIFIED: `lib/mix/tasks/foglet.user.reset_password.ex`, tests] |
| V6 Cryptography | Yes | Use `:crypto.strong_rand_bytes` and SHA-256 hashing through existing `UserToken`; do not hand-roll. [VERIFIED: `lib/foglet_bbs/accounts/user_token.ex`] |

### Known Threat Patterns for Reset Flow

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Account enumeration through reset request | Information Disclosure | Preserve generic response from `request_password_reset_delivery/1`. [VERIFIED: `lib/foglet_bbs/accounts.ex`, tests] |
| Token disclosure in persistent storage | Information Disclosure | Store hashed token in `user_tokens`; show raw token only once through email/operator channel. [VERIFIED: `lib/foglet_bbs/accounts/user_token.ex`] |
| Replay of used reset token | Elevation of Privilege | `reset_user_password/2` deletes outstanding reset tokens after password change. [VERIFIED: `lib/foglet_bbs/accounts.ex`, tests] |
| Unsupported route claim | Spoofing / Information Disclosure | Remove browser URL output and docs unless route exists. [VERIFIED: `.planning/v1.2-MILESTONE-AUDIT.md`] |
| Deleted user reset | Elevation of Privilege | Existing Mix task rejects deleted users. [VERIFIED: `lib/mix/tasks/foglet.user.reset_password.ex`, tests] |

## Sources

### Primary (HIGH confidence)

- `AGENTS.md` - SSH-first boundary, context rules, config rules, tests/precommit.
- `/Users/brendan.turner/.codex/RTK.md` - `rtk` command prefix rule.
- `.planning/ROADMAP.md` - Phase 15 goal, requirements, success criteria.
- `.planning/REQUIREMENTS.md` - MAIL-04, MAIL-06, HYGN-02, HYGN-03 definitions and out-of-scope browser workflows.
- `.planning/v1.2-MILESTONE-AUDIT.md` - Critical reset URL integration gap and README contradiction.
- `.planning/phases/14-launch-hygiene-and-operator-notes/14-VERIFICATION.md` - Phase 14 failed/partial reset blocker evidence.
- `.planning/phases/14-launch-hygiene-and-operator-notes/14-BLOCKERS.md` - Current blocker record.
- `lib/mix/tasks/foglet.user.reset_password.ex` - Current unsupported URL output.
- `lib/foglet_bbs/accounts.ex` - Reset delivery and reset password context behavior.
- `lib/foglet_bbs/accounts/user_token.ex` - Reset token hashing, expiry, verification.
- `lib/foglet_bbs/accounts/email.ex` - Browser-free reset email body.
- `lib/foglet_bbs_web/router.ex` - No reset route.
- `test/mix/tasks/foglet_user_reset_password_test.exs` - Current task tests that assert URL output.
- `test/foglet_bbs/accounts/accounts_test.exs` - SMTP reset delivery and token invalidation tests.
- `README.md` - Current contradictory operator reset URL docs.

### Secondary (MEDIUM confidence)

- Existing Phase 09 and Phase 14 validation docs for validation style and commands. [VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-VALIDATION.md`, `.planning/phases/14-launch-hygiene-and-operator-notes/14-VALIDATION.md`]

### Tertiary (LOW confidence)

- None.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - verified from `mix.exs`, `mix.lock`, and command output.
- Architecture: HIGH - verified from project instructions, router, Accounts, UserToken, email builder, Login, and Mix task source.
- Pitfalls: HIGH - derived from current failing audit evidence and source/tests.

**Research date:** 2026-04-24
**Valid until:** 2026-05-24 for repo-local findings; re-run grep if reset routes or TUI token consumption are added before planning.

## RESEARCH COMPLETE

**Phase:** 15 - reset-path-gap-closure
**Confidence:** HIGH

### Key Findings

- The blocking defect is the break-glass task and docs presenting reset tokens as unsupported browser URLs. [VERIFIED: audit + code]
- SMTP reset email copy is already terminal-native and browser-free. [VERIFIED: `lib/foglet_bbs/accounts/email.ex`, tests]
- `FogletBbsWeb.Router` has no reset route, and project constraints prohibit adding end-user browser workflows for v1.2. [VERIFIED: router + AGENTS]
- Existing tests must be rewritten because they currently assert `/users/reset_password/` output. [VERIFIED: `test/mix/tasks/foglet_user_reset_password_test.exs`]
- README and Phase 14 blocker records must be aligned as part of closure. [VERIFIED: README + blocker log + milestone audit]

### File Created

`.planning/phases/15-reset-path-gap-closure/15-RESEARCH.md`

### Confidence Assessment

| Area | Level | Reason |
|------|-------|--------|
| Standard Stack | HIGH | Verified from `mix.exs`, `mix.lock`, and `rtk mix --version`. |
| Architecture | HIGH | Verified from source boundaries and project instructions. |
| Pitfalls | HIGH | Verified from explicit audit blockers and current test/doc contradictions. |

### Open Questions

Minimum closure can use raw token/operator instructions now; a full TUI token-consumption reset flow remains a product decision for planning or a later phase. [VERIFIED: roadmap success criteria + codebase grep]

### Ready for Planning

Research complete. Planner can now create PLAN.md files.
