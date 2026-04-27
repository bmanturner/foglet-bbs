# Phase 31: Auth Flow - Research

**Researched:** 2026-04-27
**Domain:** SSH/TUI password reset flow, Accounts token consumption, compact terminal rendering
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

### Reset Request Surface
- **D-01:** The Login menu always exposes `[F] Forgot password`, regardless of `delivery_mode`.
- **D-02:** The reset request screen becomes email-only: the field label should be `Email:` or equivalent, invalid local email shapes render an inline field error, and invalid local submissions must not invoke Accounts reset delivery.
- **D-03:** Valid email-shaped submissions preserve a generic outward state/message category in email mode, whether the email belongs to an active user or not.

### Token Consume Surface
- **D-04:** Implement `:reset_consume` as an inline `Foglet.TUI.Screens.Login` sub-state with screen-local state in `Foglet.TUI.Screens.Login.State`.
- **D-05:** The token-consume form uses three `TextInput` fields: raw reset token, new password, and password confirmation. Password fields should be masked.
- **D-06:** Use the Login screen's existing lightweight focus/key-routing pattern for this auth form rather than introducing `Modal.Form`; Tab/Shift+Tab or the established Login focus controls must route input deterministically among all fields.
- **D-07:** Escape from `:reset_consume` returns to the Login menu and clears token/password fields. Successful consumption also returns to the logged-out Login menu.

### Accounts Boundary
- **D-08:** Add the raw reset-token consume operation to `Foglet.Accounts.Verification`, not to the TUI screen or Phoenix web modules.
- **D-09:** The consume operation reuses `Foglet.Accounts.UserToken.verify_email_token_query(raw, "reset_password")`, `Foglet.Accounts.User.password_changeset/2`, and `Repo.transact/1`.
- **D-10:** Token-consume results are generic at the edge: invalid, malformed, expired, or already-used tokens must not leak token details or account existence through user-facing copy.
- **D-11:** Raw reset token values must never appear in chrome, breadcrumb, status, modal, command hints, logs, or planning/test fixture output beyond the direct input field value under test.

### No-Email Copy And Sysop Contacts
- **D-12:** The Login screen renders reset confirmation and no-email operator-assistance copy through `Foglet.TUI.TextWidth.wrap/2` or an equivalent existing width-aware helper.
- **D-13:** Active, non-deleted sysop contact emails should be supplied through a narrow Accounts/Verification boundary helper rather than queried directly from the Login screen.
- **D-14:** No-email copy lists active non-deleted sysop email addresses comma-separated when any exist; otherwise it falls back to honest generic sysop/operator contact copy.
- **D-15:** The token-consume entry is reachable both from the Forgot Password flow and directly from the Login menu.

### Testing Shape
- **D-16:** Domain behavior belongs in `test/foglet_bbs/accounts/verification_test.exs`: token creation side effects, raw-token consume success/failure, password update, token deletion, and concurrent consume where exactly one attempt wins.
- **D-17:** Login key routing and reset flow state belong in `test/foglet_bbs/tui/screens/login_test.exs`: menu visibility in both modes, email validation, `:reset_consume` entry paths, focus movement, mismatch handling, Escape clearing, and generic outward results.
- **D-18:** Compact rendering and non-leak checks belong in `test/foglet_bbs/tui/layout_smoke_test.exs`: 64x22 wrapped reset/no-email copy, breadcrumb for `:reset_consume`, and absence of raw token text from chrome/status/command surfaces.

### the agent's Discretion
- Exact user-facing copy may be chosen by the planner/implementer as long as it is enumeration-safe, honest in no-email mode, terminal-native, and does not mention browser reset paths.
- Exact email validation implementation may be local/simple rather than RFC-complete; it must catch the spec's invalid shapes and avoid false comfort from copy-only tests.

### Deferred Ideas (OUT OF SCOPE)
- Browser-based password reset remains out of scope.
- Operator-side reveal of most-recent unconsumed reset token remains future work (`ACCT-FUT-01` / related future sysop work), not Phase 31.
- New notification channels, webhooks, email digests, account recovery by handle/SSH key/security questions, and sysop contact management are out of scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| AUTH-01 | Forgot Password validates email locally and preserves enumeration-safe success behavior. | Existing `Login` reset request delegates to `Verification.request_password_reset_delivery/1`; change screen validation before dispatch and keep generic result category. [VERIFIED: `.planning/REQUIREMENTS.md`; `lib/foglet_bbs/tui/screens/login.ex`; `lib/foglet_bbs/accounts/verification.ex`] |
| AUTH-02 | Reset confirmation wraps with `TextWidth.wrap/2` at 64x22. | `Foglet.TUI.TextWidth.wrap/2` exists and preserves newline boundaries while wrapping by display width. [VERIFIED: `lib/foglet_bbs/tui/text_width.ex`] |
| AUTH-03 | `:no_email` mode names operator-assisted SSH path and exposes token consume from Forgot Password and Login menu. | Current code hides Forgot Password in `no_email`; planner must make `[F]` unconditional and add a token-consume entry. [VERIFIED: `lib/foglet_bbs/tui/screens/login.ex`; `.planning/phases/31-auth-flow/31-SPEC.md`] |
| AUTH-04 | Accounts boundary atomically consumes raw reset token and drives `:reset_consume`. | Existing token primitive can verify raw reset token to user, and `reset_user_password/2` uses `Repo.transact/1`; planner must add one atomic consume operation in `Verification`. [VERIFIED: `lib/foglet_bbs/accounts/user_token.ex`; `lib/foglet_bbs/accounts/verification.ex`; deps Ecto docs in `deps/ecto/lib/ecto/repo.ex`] |
</phase_requirements>

## Summary

Phase 31 should be planned as a focused stabilization pass across three seams: `Foglet.Accounts.Verification` for durable token behavior, `Foglet.TUI.Screens.Login` plus `Login.State` for logged-out auth UI state, and `layout_smoke_test.exs` for compact rendering/non-leak proof. The project already has the core primitives: hashed raw reset tokens, `UserToken.verify_email_token_query/2`, `User.password_changeset/2`, `Repo.transact/1`, `TextInput`, and `TextWidth.wrap/2`. [VERIFIED: codebase grep and source reads]

The highest-risk implementation detail is atomic single-use token consumption. A naive flow that verifies the raw token, loads the user, then calls `reset_user_password/2` can pass happy-path tests while allowing concurrent consumers to both verify before either deletes tokens. Plan an atomic row-claim inside `Repo.transact/1`, using the decoded/hashed token query path and deleting/resetting within the same transaction. [VERIFIED: `UserToken.verify_email_token_query/2`; `Verification.reset_user_password/2`; Ecto `Repo.transact/2` docs in deps]

**Primary recommendation:** Add a `Verification.consume_reset_token(raw_token, attrs)` boundary that verifies and consumes inside one transaction, then wire `Login` inline `:reset_consume` state to that boundary with generic user-facing outcomes and explicit compact render tests. [VERIFIED: `.planning/phases/31-auth-flow/31-CONTEXT.md`; source files listed above]

## Project Constraints (from AGENTS.md)

- Use `rtk` as the command prefix in this repo. [VERIFIED: AGENTS.md user-provided instructions]
- Foglet is SSH-first; Phoenix is infrastructure and must not gain end-user browser auth workflows for this phase. [VERIFIED: AGENTS.md; `.planning/REQUIREMENTS.md` out-of-scope table]
- Keep domain workflows in `Foglet.*` contexts, not controllers, SSH callbacks, or TUI render functions. [VERIFIED: AGENTS.md]
- `Foglet.Accounts` owns users, auth, roles, invites, tokens, SSH keys, and deletion; token consume belongs in Accounts/Verification. [VERIFIED: AGENTS.md; phase context D-08]
- For TUI flows, keep global navigation in `Foglet.TUI.App`, screen-local state in screens or sibling state modules, data/mutations in contexts, and reusable display in widgets. [VERIFIED: AGENTS.md]
- Widgets must route colors through `Foglet.TUI.Theme`, pass theme explicitly, and keep render functions pure over loaded state. [VERIFIED: AGENTS.md; widget README]
- Use `start_supervised!/1` for test processes; avoid `Process.sleep/1` and `Process.alive?/1`; synchronize with monitors/messages/`:sys.get_state/1`. [VERIFIED: AGENTS.md]
- Run `mix precommit` when code changes are complete; note existing precommit may be affected by prior Dialyzer warnings from Phase 26 state. [VERIFIED: AGENTS.md; `.planning/STATE.md`]

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Local email validation | TUI screen | Accounts boundary for durable lookup only | Invalid shape must be rejected before `Verification.request_password_reset_delivery/1` is called. [VERIFIED: phase spec req 2] |
| Enumeration-safe reset request | Accounts / Backend | TUI screen | Accounts owns token side effects; TUI owns generic outward category and copy. [VERIFIED: `Verification.request_password_reset_delivery/1`; Login submit code] |
| Wrapped reset/no-email copy | Browser / Client equivalent: SSH TUI | Accounts helper for sysop contacts | Terminal render width and row composition belong in `Login`; sysop contact selection belongs behind Accounts. [VERIFIED: AGENTS.md; D-12/D-13] |
| Raw token consumption | Accounts / Backend | TUI screen | Verification, password update, and token deletion are durable domain side effects and must not live in render/key handlers. [VERIFIED: AGENTS.md; D-08/D-09] |
| Breadcrumb/status non-leak | SSH TUI chrome | Accounts boundary | Chrome derives labels from screen state only; raw token must stay only in the focused input buffer. [VERIFIED: `BreadcrumbBar.parts_for/1`; D-11] |

## Standard Stack

### Core

| Library / Module | Version | Purpose | Why Standard |
|------------------|---------|---------|--------------|
| Elixir / Mix | 1.19.5 observed | Runtime and test runner. | Project is an Elixir/Phoenix application. [VERIFIED: failed `rtk mix help` stack showed Mix 1.19.5; `mix.exs`] |
| Ecto / Ecto SQL | 3.13.5 | Repo transactions, queries, row deletion/update. | Existing contexts use `Repo.transact/1`; Ecto docs soft-deprecate `transaction/2` in favor of `transact/2`. [VERIFIED: `rtk mix deps`; `deps/ecto/CHANGELOG.md`] |
| Phoenix | 1.8.5 | Infrastructure only. | Present but out of scope for end-user reset UX. [VERIFIED: `rtk mix deps`; AGENTS.md] |
| Raxol / raxol_core | 2.4.0 | Terminal UI components and layout engine. | Existing Login and smoke tests render through Raxol primitives. [VERIFIED: `rtk mix deps`; widget gallery] |
| `Foglet.TUI.Widgets.Input.TextInput` | local | Single-line input for token/password fields. | Existing Login forms use it, including masked password fields. [VERIFIED: `Login.State.login_form/0`; widget README] |
| `Foglet.TUI.TextWidth` | local | Display-width wrapping/truncation. | Phase 26 delivered required wrap helper. [VERIFIED: `text_width.ex`; `.planning/ROADMAP.md`] |
| Argon2 | 4.1.3 | Password hash verification in tests and password changeset hashing. | Existing `User.password_changeset/2` hashes through Argon2. [VERIFIED: `rtk mix deps`; `user.ex`] |
| Swoosh | 1.25.0 | Email delivery test assertions for email mode. | Existing verification tests use Swoosh assertions. [VERIFIED: `rtk mix deps`; `verification_test.exs`] |

### Supporting

| Library / Module | Version | Purpose | When to Use |
|------------------|---------|---------|-------------|
| `Foglet.Config.delivery_mode/0` | local | Switch email vs no-email reset behavior. | Render/menu behavior and Verification delivery branch. [VERIFIED: `Login.delivery_mode/0`; `Verification.request_password_reset_delivery/1`] |
| `Foglet.Accounts.UserToken` | local | Build/verify hashed raw reset tokens. | Token consume implementation and tests. [VERIFIED: `user_token.ex`] |
| `Foglet.Accounts.User.password_changeset/2` | local | Validate and hash new password. | Raw token consume password update. [VERIFIED: `user.ex`] |
| `Raxol.UI.Layout.Engine` | vendored/dependency | Render smoke layout at exact sizes. | 64x22 wrap/non-leak tests. [VERIFIED: `layout_smoke_test.exs`] |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Inline `Login` sub-state | `Modal.Form` | Explicitly rejected by D-04/D-06 for this phase; inline Login focus pattern is already established. [VERIFIED: phase context] |
| Browser reset route | Phoenix controller/LiveView | Out of scope and violates SSH-first boundary. [VERIFIED: AGENTS.md; REQUIREMENTS out-of-scope] |
| RFC-complete email parser | Full email parsing dependency | Phase locks local/simple validation sufficient for invalid shapes; do not expand dependency surface. [VERIFIED: D-02 and discretion note] |
| Query sysops directly from Login | `Repo` calls in screen | Violates context boundary; add narrow Accounts/Verification helper. [VERIFIED: D-13; AGENTS.md] |

**Installation:** No new packages are recommended. Use existing dependencies. [VERIFIED: `rtk mix deps`; phase scope]

**Version verification:** Versions were checked with `rtk mix deps`; `rtk mix help deps` failed in the sandbox because Mix PubSub could not open a TCP socket (`:eperm`), but dependency listing succeeded. [VERIFIED: command output]

## Architecture Patterns

### System Architecture Diagram

```text
Logged-out SSH user
  |
  v
Login menu
  |-- [F] Forgot password ------------------------.
  |                                               |
  v                                               v
reset_request sub-state                    reset_consume sub-state
  |                                               |
  | local email shape check                       | token/password/confirm inputs
  |-- invalid -> inline error, no Accounts call   |-- mismatch -> inline error
  |-- valid --------------------------------.     |-- submit
  v                                        |     v
Verification.request_password_reset_delivery(email)
  |                                        Verification.consume_reset_token(raw, attrs)
  |                                        |
  | email mode: active user -> hashed token + email
  | email mode: unknown/inactive -> no token
  | no_email mode -> operator-assisted copy + consume entry
  v                                        v
Generic reset confirmation copy       Repo.transact atomic verify/update/delete
  |                                        |
  v                                        v
TextWidth.wrap(width budget)          success -> Login menu / failure -> generic error
```

### Recommended Project Structure

```text
lib/foglet_bbs/
├── accounts/
│   ├── verification.ex        # add consume_reset_token/2 and sysop contact helper
│   ├── user_token.ex          # reuse verify_email_token_query/2; no raw token storage
│   └── user.ex                # reuse password_changeset/2
└── tui/
    ├── screens/login.ex       # menu, reset_request, reset_consume render/key handling
    ├── screens/login/state.ex # reset_consume state + focus mapping
    └── text_width.ex          # existing wrap helper

test/foglet_bbs/
├── accounts/verification_test.exs
├── tui/screens/login_test.exs
└── tui/layout_smoke_test.exs
```

### Pattern 1: Generic Edge, Specific Side Effects

**What:** Return generic user-facing results for valid-shaped reset requests while asserting durable side effects separately. [VERIFIED: `Verification.request_password_reset_delivery/1`; `verification_test.exs`]

**When to use:** Forgot Password email submissions and token consume errors. [VERIFIED: AUTH-01/AUTH-04]

**Example:**

```elixir
# Source: lib/foglet_bbs/accounts/verification.ex
identifier
|> String.trim()
|> find_reset_delivery_user()
|> maybe_deliver_password_reset()

{:ok, :generic_response}
```

Planner note: preserve this generic category for valid emails; do not make copy depend on account status. [VERIFIED: phase spec req 3]

### Pattern 2: Inline Auth Form State in Login.State

**What:** Login form state lives under `state.screen_state[:login]`, with `focused_field` selecting the `TextInput` to update. [VERIFIED: `login/state.ex`; `login.ex`]

**When to use:** Add `:reset_consume` with fields `:token`, `:password`, and `:password_confirmation`. [VERIFIED: D-04/D-05]

**Example:**

```elixir
# Source: lib/foglet_bbs/tui/screens/login/state.ex
%{
  sub: :login_form,
  focused_field: :handle,
  handle_input: TextInput.init([]),
  password_input: TextInput.init(mask_char: "*"),
  error: nil
}
```

Planner note: extend `input_key/1` for the new focused fields and add deterministic forward/back focus helpers rather than special-casing each key in render code. [VERIFIED: local pattern]

### Pattern 3: Width-Aware Copy Rendering

**What:** Build wrapped rows from a message string using `TextWidth.wrap/2`, then render each row as its own `text/2` node. [VERIFIED: `TextWidth.wrap/2`; layout smoke helpers]

**When to use:** Reset success, no-email operator assistance, and any longer inline error/status text at 64x22. [VERIFIED: AUTH-02/AUTH-03]

**Example:**

```elixir
# Source: lib/foglet_bbs/tui/text_width.ex
def wrap(text, width) when is_integer(width) do
  text
  |> String.split("\n")
  |> Enum.flat_map(&wrap_line(&1, width))
end
```

Planner note: derive the wrap width from terminal content width, not a raw 80-column constant. [VERIFIED: Phase 26 state decisions about drawable widths]

### Anti-Patterns to Avoid

- **Handle-or-email reset field:** Phase 31 locks email-only request input; handle lookup belongs only to existing code being narrowed. [VERIFIED: 31-SPEC]
- **Copy-only enumeration safety tests:** Tests must assert token rows for active vs unknown/inactive/deleted users, not just literal text. [VERIFIED: 31-SPEC acceptance]
- **Raw token in state-derived chrome:** Breadcrumb is based on `:sub`, not field values; keep it that way. [VERIFIED: `BreadcrumbBar.login_parts/1`]
- **Token verification outside the transaction:** It creates a race where two consumers can verify before deletion. [VERIFIED: analysis from current `verify_email_token_query/2` + `reset_user_password/2` separation]
- **Repo calls in Login screen for sysop emails:** Add a helper to `Verification` or `Accounts`. [VERIFIED: D-13; AGENTS.md]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Password hashing | Custom hashing or direct `password_hash` edits | `User.password_changeset/2` | Enforces min/max and Argon2 hashing. [VERIFIED: `user.ex`] |
| Token encoding/hashing | Store or compare raw tokens manually | `UserToken.build_email_token/2` and `verify_email_token_query/2` | Existing primitive stores SHA256 hash and base64url raw edge token. [VERIFIED: `user_token.ex`] |
| Terminal text wrapping | `String.slice/2` or byte length | `Foglet.TUI.TextWidth.wrap/2` | Handles display width and grapheme boundaries. [VERIFIED: `text_width.ex`] |
| Auth form widgets | New widget/form system | Existing `TextInput` and Login focus routing | Locked by phase decisions and already tested. [VERIFIED: D-05/D-06; widget README] |
| Browser reset UX | Phoenix web reset pages | SSH/TUI reset consume flow | Browser reset is out of scope. [VERIFIED: REQUIREMENTS; AGENTS.md] |

**Key insight:** This phase is about composing existing primitives correctly under security and terminal constraints, not adding new infrastructure. [VERIFIED: source inspection]

## Common Pitfalls

### Pitfall 1: Atomicity Mirage

**What goes wrong:** `Repo.one(verify_query)` followed by `reset_user_password/2` appears transactional because reset deletes tokens, but concurrent callers can both verify before either delete runs. [VERIFIED: current source separation]

**Why it happens:** Verification returns a user row, not a claimed token row. [VERIFIED: `UserToken.verify_email_token_query/2` selects `u`]

**How to avoid:** Wrap raw-token decode/hash, token row lookup/claim, password changeset update, and reset-token deletion in one `Repo.transact/1`; use row locking or a conditional delete/update that lets exactly one transaction win. [VERIFIED: Ecto query locks supported in deps; `Repo.transact/2` docs]

**Warning signs:** Concurrent consume test sometimes returns two successes or leaves token rows after success. [ASSUMED]

### Pitfall 2: Invalid Email Still Dispatches

**What goes wrong:** The UI shows an inline error but still calls `Verification.request_password_reset_delivery/1`, creating tokens or mail side effects for malformed input. [VERIFIED: phase spec acceptance forbids this]

**How to avoid:** Put validation before the boundary call in `submit_reset_request/1`, and test malformed values create no `reset_password` rows. [VERIFIED: `login.ex`; 31-SPEC]

### Pitfall 3: No-Email Copy Sounds Like a Failure

**What goes wrong:** Existing `:no_email` path returns “unavailable,” which contradicts the operator-assisted reset goal. [VERIFIED: current `@reset_unavailable_message`; `Verification.request_password_reset_delivery/1`]

**How to avoid:** Treat no-email as a supported path in Login copy, while leaving email delivery disabled; list active non-deleted sysop emails via an Accounts helper. [VERIFIED: D-14]

### Pitfall 4: Wrapped Text Is Still One Node

**What goes wrong:** Calling a helper but rendering one long `text/2` node still lets layout truncate at compact width. [VERIFIED: current render uses single `text(login_ss.message)`]

**How to avoid:** Convert each wrapped line to a distinct row/text element and assert multiple visible rows at 64x22. [VERIFIED: layout smoke patterns]

### Pitfall 5: Masked Password Fields Drift From Focus

**What goes wrong:** Token-consume fields receive text in the wrong buffer after Tab/Shift+Tab. [VERIFIED: prior form focus requirements and existing Login tests]

**How to avoid:** Extend `Login.State.input_key/1` and focus cycling as the single source of truth; route all non-control keys through the focused `TextInput`. [VERIFIED: `FocusInput`/Login pattern]

## Code Examples

### Raw Token Query Primitive

```elixir
# Source: lib/foglet_bbs/accounts/user_token.ex
case Base.url_decode64(token, padding: false) do
  {:ok, decoded} ->
    hashed = :crypto.hash(@hash_algorithm, decoded)
    query =
      from t in by_token_and_context_query(hashed, context),
        join: u in assoc(t, :user),
        where: t.inserted_at > ago(^days, "day") and t.sent_to == u.email,
        select: u

    {:ok, query}

  :error ->
    :error
end
```

Use this behavior, but consider adding an internal helper that returns or locks the token row for atomic consume. [VERIFIED: source]

### Existing Password Reset Transaction

```elixir
# Source: lib/foglet_bbs/accounts/verification.ex
Repo.transact(fn ->
  with {:ok, updated} <- user |> User.password_changeset(attrs) |> Repo.update() do
    Repo.delete_all(UserToken.by_user_and_contexts_query(user, ["reset_password"]))
    {:ok, updated}
  end
end)
```

Use the same password changeset and token cleanup semantics inside raw-token consume. [VERIFIED: source; D-09]

### Existing Login Key Routing

```elixir
# Source: lib/foglet_bbs/tui/screens/login.ex
defp handle_form_key(event, state) do
  {new_input, _action} = TextInput.handle_event(event, focused_input(state))
  {:update, update_focused_input(state, new_input), []}
end
```

Use the same pattern for `:reset_consume`; add `:backtab`/Shift+Tab behavior if tests establish it for this form. [VERIFIED: source; D-06]

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `Repo.transaction/2` | `Repo.transact/2` | Ecto changelog shows `transaction/2` soft-deprecated in favor of `transact/2`. | Use `Repo.transact/1` as phase requires. [VERIFIED: `deps/ecto/CHANGELOG.md`; `deps/ecto/lib/ecto/repo.ex`] |
| Browser reset URLs | SSH terminal reset flow with raw token delivery | Existing email tests assert no `/users/reset_password`, `http://`, or `https://`. | Do not introduce browser links. [VERIFIED: `verification_test.exs`; REQUIREMENTS] |
| Handle-or-email forgot password | Email-only local validation | Locked by Phase 31 spec/context. | Planner should update labels, validation, and tests. [VERIFIED: 31-SPEC] |
| Hidden Forgot Password in no-email mode | Always-visible Forgot Password plus operator-assisted copy | Locked by D-01/D-14. | Planner must update menu keys and no-email tests. [VERIFIED: context] |

**Deprecated/outdated:**
- `@reset_unavailable_message`: replace with honest no-email operator-assisted copy. [VERIFIED: `login.ex`; 31-SPEC]
- Login reset label `Handle or email:`: replace with `Email:` or equivalent. [VERIFIED: `login.ex`; D-02]

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Concurrent consume warning signs may include intermittent two-success results, depending on DB isolation and implementation. | Common Pitfalls | Test strategy may need adjustment, but atomic single-winner requirement remains locked. |

## Open Questions

1. **Exact atomic consume strategy**
   - What we know: Must use `Repo.transact/1`, `verify_email_token_query/2`, `password_changeset/2`, and delete reset tokens. [VERIFIED: D-09]
   - What's unclear: Whether planner should prefer `FOR UPDATE` row locking, conditional `delete_all` as claim, or a small helper returning token row instead of user row.
   - Recommendation: Plan a first task that adds a private token-row verification helper in `Verification` or `UserToken`, then implement consume with a single-winner conditional row operation and a concurrent test.

2. **Sysop contact helper module**
   - What we know: The helper must be narrow and not queried directly from Login. [VERIFIED: D-13]
   - What's unclear: Whether to expose it as `Verification.active_sysop_contact_emails/0` or `Accounts.active_sysop_contact_emails/0`.
   - Recommendation: Put it in `Verification` if only reset copy uses it; put it in `Accounts` only if planner sees broader contact reuse.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| Elixir/Mix | Build/test | Yes | Mix 1.19.5 observed | None |
| Ecto / ecto_sql | Accounts transaction tests | Yes | 3.13.5 | None |
| Raxol | TUI render/tests | Yes | 2.4.0 | None |
| Argon2 | Password tests | Yes | 4.1.3 | None |
| Swoosh | Email mode tests | Yes | 1.25.0 | None |

**Missing dependencies with no fallback:** None found. [VERIFIED: `rtk mix deps`]

**Missing dependencies with fallback:** None found. [VERIFIED: `rtk mix deps`]

**Note:** `rtk mix help deps` failed under sandbox TCP restrictions, but `rtk mix deps` succeeded and provided dependency versions. [VERIFIED: command output]

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | ExUnit via Mix; DataCase for DB tests. [VERIFIED: test files] |
| Config file | `mix.exs`, `test/test_helper.exs`, `test/support/data_case.ex`. [VERIFIED: project files by convention/source presence inferred from tests] |
| Quick run command | `rtk mix test test/foglet_bbs/accounts/verification_test.exs test/foglet_bbs/tui/screens/login_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` |
| Full suite command | `rtk mix precommit` |

### Phase Requirements -> Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| AUTH-01 | Invalid local email rejects before dispatch; valid emails get generic result and correct token side effects. | unit/integration | `rtk mix test test/foglet_bbs/accounts/verification_test.exs test/foglet_bbs/tui/screens/login_test.exs` | Yes |
| AUTH-02 | Reset confirmation/no-email copy wraps at 64x22. | render smoke | `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs` | Yes |
| AUTH-03 | No-email operator-assisted copy and token-consume entry from both paths. | unit/render | `rtk mix test test/foglet_bbs/tui/screens/login_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` | Yes |
| AUTH-04 | Raw token consume updates password, deletes tokens, is single-use under concurrency, and UI returns to menu. | integration/unit/render | `rtk mix test test/foglet_bbs/accounts/verification_test.exs test/foglet_bbs/tui/screens/login_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` | Yes |

### Sampling Rate

- **Per task commit:** `rtk mix test test/foglet_bbs/accounts/verification_test.exs test/foglet_bbs/tui/screens/login_test.exs`
- **Per wave merge:** `rtk mix test test/foglet_bbs/accounts/verification_test.exs test/foglet_bbs/tui/screens/login_test.exs test/foglet_bbs/tui/layout_smoke_test.exs`
- **Phase gate:** `rtk mix precommit`, with any pre-existing Dialyzer blockage documented rather than hidden. [VERIFIED: AGENTS.md; `.planning/STATE.md`]

### Wave 0 Gaps

- None for test infrastructure; all target test files exist. [VERIFIED: `rg --files test/foglet_bbs`]
- Add new cases inside existing files rather than creating new harnesses unless concurrent consume needs a small helper module. [VERIFIED: D-16..D-18]

## Sources

### Primary (HIGH confidence)
- `.planning/phases/31-auth-flow/31-CONTEXT.md` - locked implementation decisions, test shape, deferred scope.
- `.planning/phases/31-auth-flow/31-SPEC.md` - requirements, boundaries, acceptance criteria.
- `.planning/REQUIREMENTS.md` - AUTH-01..AUTH-04 and v1.4 out-of-scope constraints.
- `.planning/ROADMAP.md` - Phase 31 goal and dependencies.
- `AGENTS.md` user-provided instructions - SSH-first boundary, context/TUI rules, test finish line.
- `lib/foglet_bbs/tui/screens/login.ex` - current Login menu/reset request behavior.
- `lib/foglet_bbs/tui/screens/login/state.ex` - current screen-local state/focus helpers.
- `lib/foglet_bbs/accounts/verification.ex` - reset delivery, reset password, operator token generation.
- `lib/foglet_bbs/accounts/user_token.ex` - raw token build/verify primitives.
- `lib/foglet_bbs/accounts/user.ex` - password changeset and account fields.
- `lib/foglet_bbs/tui/text_width.ex` - wrap helper behavior.
- `lib/foglet_bbs/tui/widgets/chrome/breadcrumb_bar.ex` - `:reset_consume` breadcrumb mapping.
- `test/foglet_bbs/accounts/verification_test.exs`, `test/foglet_bbs/tui/screens/login_test.exs`, `test/foglet_bbs/tui/layout_smoke_test.exs` - existing validation seams.
- `deps/ecto/CHANGELOG.md`, `deps/ecto/lib/ecto/repo.ex` - local official dependency docs for `Repo.transact/2`.

### Secondary (MEDIUM confidence)
- `docs/raxol/getting-started/WIDGET_GALLERY.md` - local Raxol component guidance.
- `lib/foglet_bbs/tui/widgets/README.md` - local widget conventions.

### Tertiary (LOW confidence)
- None.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - verified from local dependency list and source.
- Architecture: HIGH - phase decisions and AGENTS.md tightly constrain ownership.
- Pitfalls: HIGH for validation/wrap/no-email leaks; MEDIUM for exact atomic row-claim implementation because implementation choice remains open.

**Research date:** 2026-04-27
**Valid until:** 2026-05-27 for local architecture; re-check dependency docs if Ecto/Raxol versions change.
