---
phase: 31-auth-flow
plan: 01
subsystem: auth
tags: [elixir, ecto, accounts, password-reset, sysop-contacts, atomic-transaction]

# Dependency graph
requires:
  - phase: 26-layout-width-foundations
    provides: TextWidth.wrap/2 (used by downstream Login render copy plans)
  - phase: 27-cursor-breadcrumb-polish
    provides: ":reset_consume breadcrumb mapping (pre-existing chrome-only stub)"
provides:
  - "Foglet.Accounts.Verification.consume_reset_token/2 — atomic single-use raw reset token consume"
  - "Foglet.Accounts.Verification.active_sysop_contact_emails/0 — narrow sysop email helper for no-email reset copy"
  - "Email-only narrowing of Verification.request_password_reset_delivery/1 (handle-shaped inputs no longer create tokens)"
  - "Foglet.Accounts.UserToken.reset_token_claim_query/1 — row-targeting query for atomic claim"
affects:
  - 31-02-login-screen-reset-flow
  - 31-03-reset-consume-form
  - 31-04-layout-smoke-and-non-leak

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Atomic single-use token consume via Repo.transact/1 + delete_all row-claim"
    - "Email-shape gate before Accounts boundary lookup"
    - "Narrow context-owned helpers for cross-screen UI data (sysop emails)"

key-files:
  created: []
  modified:
    - "lib/foglet_bbs/accounts/verification.ex — consume_reset_token/2, active_sysop_contact_emails/0, email-only request narrowing"
    - "lib/foglet_bbs/accounts/user_token.ex — reset_token_claim_query/1 row-targeting helper"
    - "test/foglet_bbs/accounts/verification_test.exs — domain coverage for D-02/D-03/D-08..D-11/D-13/D-14/D-16"

key-decisions:
  - "Atomic single-winner via delete_all row-claim: PostgreSQL row locking serializes concurrent transactions; the loser sees {0, _} and short-circuits to :invalid_or_expired."
  - "Sysop-contact helper lives on Foglet.Accounts.Verification (not Foglet.Accounts) per CONTEXT D-13 since reset copy is the only consumer and Verification already owns reset side effects."
  - "Local email shape regex mirrors User.registration_changeset's email format so the same shapes accepted at register-time are accepted at reset-time."
  - "Generic invalid_or_expired error covers unknown, malformed, expired, and already-consumed tokens to honor D-10 (no token/account existence leak)."
  - "by_user_and_contexts_query cleanup retained inside consume_reset_token/2 even after the row-claim delete: defense in depth for any other outstanding reset tokens for the same user."

patterns-established:
  - "Row-claim pattern: Repo.delete_all(matching query) inside Repo.transact/1 returns {1, _} for the winner and {0, _} for losers — use this for any single-use token-style consume."
  - "Shape gate before lookup: validate input shape (email regex) inside the boundary so handle-shaped inputs cannot probe email-existence by side effect."

requirements-completed:
  - AUTH-01
  - AUTH-03
  - AUTH-04

# Metrics
duration: ~22min
completed: 2026-04-27
---

# Phase 31 Plan 01: Accounts/Verification Foundation Summary

**Atomic single-use raw reset-token consume, narrow active-sysop-email helper, and email-only request narrowing all delivered behind the Foglet.Accounts.Verification boundary.**

## Performance

- **Duration:** ~22 min
- **Started:** 2026-04-27T23:25:00Z (approximate; worktree boot)
- **Completed:** 2026-04-27T23:47:15Z
- **Tasks:** 2/2
- **Files modified:** 3 (2 lib, 1 test)

## Accomplishments

- `Foglet.Accounts.Verification.consume_reset_token/2` verifies the raw reset
  token, claims its hashed row inside `Repo.transact/1` via a delete-all
  row-claim, runs `User.password_changeset/2`, and removes any other
  outstanding reset tokens for the user — concurrent consumers race on the
  delete and exactly one observes `{1, _}`. Generic `:invalid_or_expired`
  covers unknown / malformed / expired / already-consumed tokens with no
  token-or-account-existence leak (D-08, D-09, D-10, D-16).
- `Foglet.Accounts.Verification.active_sysop_contact_emails/0` returns active,
  non-deleted sysop emails sorted by email for the Login no-email reset copy.
  Excludes pending, suspended, rejected, deleted, non-sysop, and nil-email
  users (D-13, D-14).
- `Verification.request_password_reset_delivery/1` is now email-only at the
  boundary level: handle-shaped identifiers no longer trigger token
  side effects. The lookup uses the same email-shape regex shape that
  `User.registration_changeset` validates against, so reset request input
  acceptance and registration acceptance stay aligned (D-02, D-13).
- `Foglet.Accounts.UserToken.reset_token_claim_query/1` is a narrow internal
  helper that returns a row-targeting query for the matching reset_password
  hashed token, designed for atomic single-use consumption inside a
  transaction.

## Task Commits

Each task was committed atomically with `--no-verify` (parallel-executor mode):

1. **Task 1 (TDD RED): Failing domain tests** — `7cb9962` (test)
   - 10 failing tests covering email-only narrowing, sysop contacts, and
     consume happy-path / single-use / expired / malformed / unknown /
     invalid-password / concurrent-success-exactly-once.
2. **Task 2 (TDD GREEN): Implementation** — `ec5b57f` (feat)
   - `consume_reset_token/2`, `active_sysop_contact_emails/0`,
     `reset_token_claim_query/1`, and email-shape gate in
     `request_password_reset_delivery/1`.

## Files Created/Modified

- `lib/foglet_bbs/accounts/verification.ex` — added `consume_reset_token/2`,
  `active_sysop_contact_emails/0`, `@email_shape_regex` module attribute, and
  narrowed `find_reset_delivery_user/1` to email-shape-gated email lookup.
- `lib/foglet_bbs/accounts/user_token.ex` — added
  `reset_token_claim_query/1` for atomic row-claim deletion inside
  `Repo.transact/1`.
- `test/foglet_bbs/accounts/verification_test.exs` — replaced handle-active
  reset coverage with handle-no-token coverage, expanded
  enumeration-safety to deleted/pending/suspended/rejected emails, added
  6 cases for `consume_reset_token/2` (including a concurrent-consume
  test with two `Task.async` consumers and explicit `Sandbox.allow/3`),
  and added 2 cases for `active_sysop_contact_emails/0`.

## Decisions Made

- **Single-winner row-claim implementation:** `Repo.delete_all` of the
  hashed-token-matching query inside `Repo.transact/1`. Two concurrent
  transactions targeting the same row serialize through PostgreSQL's row
  locking; the second observes `{0, _}` and bails out before the password
  changeset runs. This is simpler than `FOR UPDATE` row-locking with a
  separate `Repo.delete` and avoids stale-row footguns. Verified by the
  concurrent test: exactly one `{:ok, %User{}}` and one
  `{:error, :invalid_or_expired}`.
- **Sysop helper on `Verification`, not `Accounts`:** Phase 31 only has
  reset copy consuming this helper. Following CONTEXT D-13 / RESEARCH Open
  Question 2, putting it on Verification keeps the call site adjacent to
  the rest of reset-flow boundary functions. If broader contact reuse
  emerges later, hoisting to `Accounts` is a one-line move.
- **Email-shape gate at the boundary, not just the screen:** Even though
  the Login screen will validate locally (next plan), Verification also
  rejects non-email shapes inside the boundary so handle-shaped identifiers
  cannot probe email-existence indirectly through token side effects. This
  is defense in depth and makes the boundary's enumeration-safety property
  hold regardless of which UI calls it.
- **Generic `:invalid_or_expired` covers all token failure modes:**
  unknown, malformed, expired, already-consumed all return the same atom.
  Token-validation-pass-but-password-validation-fail returns
  `{:error, %Ecto.Changeset{}}` because that signal is needed to render
  inline password errors to a user who already proved possession of the
  token.
- **Defense-in-depth cleanup retained:** Even after the row-claim has
  deleted the consumed token, the success path still runs
  `Repo.delete_all(by_user_and_contexts_query(user, ["reset_password"]))`
  so any other outstanding reset tokens (e.g., a user requested two
  resets) are invalidated by the password change. Mirrors
  `reset_user_password/2`'s existing semantics.

## Deviations from Plan

None — plan executed exactly as written, including the planner's
recommendation to add a narrow internal `UserToken` helper for the
row-claim. All four `acceptance_criteria` rg predicates from the plan
match the post-implementation files.

## Issues Encountered

- **Worktree dependency hydration:** the parallel-executor worktree
  starts without `deps/`. Resolved by symlinking the parent's
  `deps/` directory (read-only consumption). `_build/` was deliberately
  not symlinked to avoid concurrent compile races with other agents;
  the worktree compiled its own `_build/` from scratch (~one-time cost).
- **Concurrent test sandbox:** parallel `Task.async` calls in the
  concurrent-consume test must check out the SQL sandbox connection.
  Used `Ecto.Adapters.SQL.Sandbox.allow(FogletBbs.Repo, parent, self())`
  inside each task. With `async: false`, the connection runs in shared
  mode so the calls are no-ops, but they remain safe and correct if a
  future async-mode change is made.

## Threat Model Compliance

| Threat ID | Disposition | Status |
|-----------|-------------|--------|
| T-31-01 (Tampering, `consume_reset_token/2`) | mitigate | Mitigated — verify, claim, update, cleanup all inside `Repo.transact/1`; concurrent test proves single winner. |
| T-31-02 (Information Disclosure, `request_password_reset_delivery/1`) | mitigate | Mitigated — `{:ok, :generic_response}` returned for valid email-shaped submissions whether or not an account exists; token side effects asserted separately. |
| T-31-03 (Information Disclosure, `active_sysop_contact_emails/0`) | mitigate | Mitigated — query filters on `role: :sysop`, `status: :active`, non-nil email; tests confirm pending/suspended/rejected/deleted/non-sysop emails are excluded. |

## TDD Gate Compliance

- RED commit (`7cb9962`, `test(...)`): present and observed 10 failures
  before implementation.
- GREEN commit (`ec5b57f`, `feat(...)`): present and follows the RED
  commit; full test file passes 17/17.
- REFACTOR commit: not needed — implementation landed in its first
  green form without further cleanup.

## Verification

- `rtk mix test test/foglet_bbs/accounts/verification_test.exs`:
  17 tests, 0 failures.
- `rtk mix test test/foglet_bbs/accounts/`:
  127 tests, 0 failures (no regressions across the Accounts namespace).
- `rtk mix test test/foglet_bbs/tui/screens/login_test.exs`:
  39 tests, 0 failures (Login screen behavior unchanged at the
  boundary call site; downstream plans 31-02..31-04 will update copy
  and screen state).

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- `Verification.consume_reset_token/2` and
  `Verification.active_sysop_contact_emails/0` are now callable from the
  Login screen, unblocking plan 31-02 (login menu visibility + reset
  request narrowing) and plan 31-03 (`:reset_consume` sub-state and
  form key routing).
- The boundary contract is stable: callers should pattern-match on
  `{:ok, %User{}}`, `{:error, :invalid_or_expired}`, and
  `{:error, %Ecto.Changeset{}}`. No raw token text needs to be
  forwarded back to chrome — D-11 holds at the boundary because
  the function never emits the raw token in any return shape.

## Self-Check: PASSED

Verified post-write:
- `lib/foglet_bbs/accounts/verification.ex` — present
- `lib/foglet_bbs/accounts/user_token.ex` — present
- `test/foglet_bbs/accounts/verification_test.exs` — present
- `.planning/phases/31-auth-flow/31-01-SUMMARY.md` — present
- Commit `7cb9962` (RED) — present in git log
- Commit `ec5b57f` (GREEN) — present in git log

---
*Phase: 31-auth-flow*
*Completed: 2026-04-27*
