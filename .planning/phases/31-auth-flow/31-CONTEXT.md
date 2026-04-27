# Phase 31: Auth Flow - Context

**Gathered:** 2026-04-27 (assumptions mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 31 closes the v1.4 auth-flow stabilization gap: Forgot Password is reachable in both email and no-email modes, reset requests validate email locally while preserving enumeration-safe outward behavior, reset confirmation/no-email copy wraps at compact terminal sizes, and logged-out users can consume an operator-provided raw reset token atomically through the Accounts boundary. Browser reset routes, new notification channels, non-email recovery methods, and registration/verification workflow changes remain out of scope.
</domain>

<decisions>
## Implementation Decisions

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
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase Requirements
- `.planning/phases/31-auth-flow/31-SPEC.md` — Locked requirements, boundaries, acceptance criteria, and interview decisions for Phase 31.
- `.planning/ROADMAP.md` — Phase 31 goal, dependencies on Phase 26/27, and v1.4 sequencing.
- `.planning/REQUIREMENTS.md` — AUTH-01..AUTH-04, v1.4 out-of-scope constraints, and traceability.
- `.planning/PROJECT.md` — SSH-first product boundary and reset-recovery browser-free decision.

### Prior Phase Contracts
- `.planning/phases/26-layout-width-foundations/26-CONTEXT.md` — Width-aware `TextWidth.wrap/2` foundation and compact 64x22 layout expectations.
- `.planning/phases/27-cursor-breadcrumb-polish/27-03-SUMMARY.md` — `:reset_consume` breadcrumb recognition landed without token behavior.
- `.planning/phases/27-cursor-breadcrumb-polish/27-HUMAN-UAT.md` — Human breadcrumb feedback established flatter auth breadcrumb intent: Login menu shows root, Forgot Password shows `Foglet / Forgot Password`, and reset-consume drops the Login parent.
- `.planning/phases/28-modal-form-substrate/28-CONTEXT.md` — Modal.Form scope and shared form decisions; useful as a contrast because Phase 31 keeps Login auth forms inline.

### Source Files
- `lib/foglet_bbs/tui/screens/login.ex` — Current Login menu, reset request render/key handling, and reset delivery submission.
- `lib/foglet_bbs/tui/screens/login/state.ex` — Login sub-state shapes and focus helper mapping.
- `lib/foglet_bbs/accounts/verification.ex` — Password reset delivery, operator token generation, and password reset boundary.
- `lib/foglet_bbs/accounts/user_token.ex` — Hashed raw token generation and verification query helpers.
- `lib/foglet_bbs/accounts/user.ex` — Password changeset and account status/role fields.
- `lib/foglet_bbs/accounts.ex` — Existing active non-deleted sysop email query precedent.
- `lib/foglet_bbs/tui/text_width.ex` — Width-aware wrap helper required for compact reset copy.
- `lib/foglet_bbs/tui/widgets/chrome/breadcrumb_bar.ex` — Auth breadcrumb mapping, including `:reset_consume`.
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Foglet.TUI.Widgets.Input.TextInput` already powers Login and Forgot Password fields, includes insertion-point cursor behavior from Phase 27, and supports masked password fields.
- `Foglet.TUI.TextWidth.wrap/2` preserves explicit newline boundaries and wraps by terminal display width.
- `Foglet.Accounts.UserToken.build_email_token/2` stores only hashed reset tokens and returns the raw token once at the edge.
- `Foglet.Accounts.UserToken.verify_email_token_query/2` decodes and hashes raw tokens, checks expiry, and joins to the user while requiring `sent_to == user.email`.
- `Foglet.Accounts.User.password_changeset/2` validates and hashes new passwords.

### Established Patterns
- Login owns simple inline auth forms with sub-states in `screen_state[:login]`; forms are initialized by `Login.State` and key events are routed by `Login.handle_key/2`.
- Domain side effects stay behind `Foglet.Accounts.Verification`; Login calls boundary functions and renders generic outcomes.
- Multi-row database invariants use `Repo.transact/1`, with token cleanup already done inside `reset_user_password/2`.
- Compact TUI visual guarantees are covered by render/layout smoke tests at 64x22 and 80x24.

### Integration Points
- `Login.menu_keys/1` and `handle_menu_key/2` add the always-visible Forgot Password and token-consume entries.
- `Login.render_reset_request/2` becomes email-only and renders inline validation plus wrapped confirmation/no-email copy.
- A new `Login.render_reset_consume/2` and matching key handler manage token/new password/confirmation fields.
- `Verification.request_password_reset_delivery/1` may need an email-only path or stricter lookup behavior so active-email submissions create tokens while handle-only reset no longer remains a user-facing path.
- A new `Verification.consume_reset_token/2` or similarly named boundary function performs atomic raw-token verification, password update, and reset-token deletion.
</code_context>

<specifics>
## Specific Ideas

- The reset consume breadcrumb label is already `Enter Token`; keep this user-facing concept, but do not include token values in any chrome or status text.
- No-email mode should feel like a supported operator-assisted path, not an error state that says reset is unavailable.
- Tests should prefer state categories, token rows, password verification, and rendered row presence over brittle literal-copy-only assertions.
</specifics>

<deferred>
## Deferred Ideas

- Browser-based password reset remains out of scope.
- Operator-side reveal of most-recent unconsumed reset token remains future work (`ACCT-FUT-01` / related future sysop work), not Phase 31.
- New notification channels, webhooks, email digests, account recovery by handle/SSH key/security questions, and sysop contact management are out of scope.
</deferred>

---

*Phase: 31-auth-flow*
*Context gathered: 2026-04-27*
