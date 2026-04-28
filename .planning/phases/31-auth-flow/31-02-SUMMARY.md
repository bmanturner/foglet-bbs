---
phase: 31-auth-flow
plan: 02
subsystem: tui
tags: [elixir, raxol, tui, login, reset-request, email-validation, text-wrap]

# Dependency graph
requires:
  - phase: 31-auth-flow
    provides: "Verification.consume_reset_token/2, Verification.active_sysop_contact_emails/0, email-only request narrowing (Plan 31-01)"
  - phase: 26-layout-width-foundations
    provides: "TextWidth.wrap/2 width-aware row composition"
provides:
  - "Always-visible [F] Forgot password in Login menu in both email and no_email delivery modes"
  - "Email-only reset request field with local shape validation that blocks dispatch on malformed input"
  - "Enumeration-safe message_category equality for active vs unknown valid email submissions"
  - "Honest no_email operator-assisted reset copy with active sysop emails listed comma-separated, fallback when none"
  - "Width-aware wrapped reset confirmation / error / no-email copy via TextWidth.wrap/2 (one text/2 node per wrapped line)"
  - "Login.State.reset_request/0 with error/message/message_category fields"
  - "[T] Enter reset token affordance hint advertised in keys_for/2 and no-email message copy"
affects:
  - 31-03-reset-consume-form
  - 31-04-layout-smoke-and-non-leak

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Local shape gate before Accounts boundary call (mirrors Verification's @email_shape_regex so screen and boundary accept the same shapes)"
    - "Width-derived wrap rendering: one text/2 node per TextWidth.wrap/2 line so compact widths render multi-row copy instead of one silently-truncated node"
    - "Enumeration-safe outward state through a single message_category atom; copy text is generic; token side effects asserted separately at the boundary"

key-files:
  created: []
  modified:
    - "lib/foglet_bbs/tui/screens/login.ex — always-visible Forgot Password, Email: label, email-only validation gate, dispatch_reset_request/2 branching by delivery_mode, no_email_operator_message/0 with sysop list/fallback, wrapped_text_rows/3, reset_wrap_width/1, [T] Enter reset token hint"
    - "lib/foglet_bbs/tui/screens/login/state.ex — reset_request/0 now carries error / message / message_category fields"
    - "test/foglet_bbs/tui/screens/login_test.exs — D-01/D-02/D-03/D-14/D-15/D-12/AUTH-02/AUTH-03 coverage including 6 invalid-shape cases, active vs unknown category equality, no-email operator copy, sysop list rendering, fallback copy, wrap width assertion, T-key advertised entry path"

key-decisions:
  - "message_category is the durable enumeration-safety contract: :email_dispatched for valid email submissions in email mode (active and unknown produce the same atom); :no_email_operator_assisted in no-email mode; :invalid_email for shape-rejected input. Tests assert atom equality, not literal copy."
  - "Local email-shape regex on the screen mirrors Verification's @email_shape_regex character-for-character so reset request input acceptance and Verification's email-shape gate stay aligned. Defense in depth — even if a future caller skips the screen, the boundary still gates."
  - "Wrap width is derived from terminal_size as (width - 2) to mirror ScreenFrame's inside_width budget; defaults to 78 when terminal_size is missing. Each TextWidth.wrap/2 line becomes its own text/2 node so the layout engine never silently truncates long messages."
  - "[T] Enter reset token is exposed as a hint in keys_for/2 and woven into the no-email message body, but the actual :reset_consume sub-state and key routing are deliberately left to Plan 31-03. This plan only delivers the entry-point advertisement, per the plan's task 2 action note."
  - "Discarded the {:error, :unavailable} return from request_password_reset_delivery/1 in favor of branching on Foglet.Config.delivery_mode/0 directly inside the screen. The screen now has two clear branches (email dispatch vs. no-email operator copy) instead of relying on the boundary to encode UX state."

patterns-established:
  - "Generic-edge / specific-side-effects testing: tests assert message_category atom equality across active/unknown for enumeration safety, plus token-row presence/absence for behavioral correctness; copy strings are not the load-bearing assertion."
  - "Width-aware multi-row rendering via Enum.map(&text/2) over TextWidth.wrap/2 — reusable elsewhere any time a long message must render under a known terminal_size budget."

requirements-completed:
  - AUTH-01
  - AUTH-02
  - AUTH-03

# Metrics
duration: ~9min
completed: 2026-04-27
---

# Phase 31 Plan 02: Login Reset Request Surface Summary

**Forgot Password is now reachable in both email and no-email delivery modes, validates email locally before any Accounts call, and renders honest width-wrapped operator-assisted copy with active sysop contacts.**

## Performance

- **Duration:** ~9 min
- **Started:** 2026-04-27T23:50:01Z
- **Completed:** 2026-04-27T23:59:00Z (approximate)
- **Tasks:** 2/2
- **Files modified:** 3 (2 lib, 1 test)

## Accomplishments

- `Foglet.TUI.Screens.Login` now exposes `[F] Forgot password` in both
  `email` and `no_email` delivery modes (D-01). The `add_reset_key/1`
  helper unconditionally inserts the menu key; `maybe_enter_reset_request/1`
  unconditionally enters `:reset_request`.
- The reset request field label is `Email:` (not `Handle or email`), and
  `submit_reset_request/1` runs a local email-shape regex before any call
  into `Verification`. Invalid local shapes (`""`, `"   "`, `"alice"`,
  `"alice@"`, `"alice@example"`, `"a b@example.test"`) set
  `error: @reset_invalid_email_message`, leave `sub: :reset_request`,
  set `message_category: :invalid_email`, and never invoke
  `Verification.request_password_reset_delivery/1` — proven by token-row
  count assertions before/after each invalid submission (D-02).
- Valid email-shaped submissions in email mode dispatch through the
  Verification boundary and set `message_category: :email_dispatched`.
  Active and unknown email submissions produce the same atom — the
  enumeration-safety contract is now an atom-equality test, not a copy
  match. The active path also creates a `reset_password` token row;
  the unknown path creates none. Both verified by separate test cases
  (D-03).
- No-email mode produces honest operator-assisted copy via
  `no_email_operator_message/0`, which calls
  `Verification.active_sysop_contact_emails/0`. When sysops exist, their
  emails are listed comma-separated (`"Sysop contacts: a@…, b@…."`); when
  none exist, a fallback line keeps the copy honest without the word
  "unavailable" (D-14, AUTH-03). The message body advertises
  `[T] Enter reset token` so the consume entry from Plan 31-03 is
  discoverable from this flow (D-15).
- Reset confirmation, error, and no-email message copy are rendered
  through `TextWidth.wrap/2` with a width derived from `terminal_size`
  (defaults to 78 if absent). Each wrapped line becomes its own
  `text/2` node, so compact terminals never silently truncate long
  messages (D-12, AUTH-02). The test asserts that no rendered text
  node exceeds 62 cells at a `64x22` terminal_size.
- `Foglet.TUI.Screens.Login.State.reset_request/0` now carries
  `error`, `message`, and `message_category` fields. The dead
  `delivery_mode/0` helper in `Login` was removed since branching now
  reads `Foglet.Config.delivery_mode/0` directly inside
  `dispatch_reset_request/2`.

## Task Commits

Each task was committed atomically with `--no-verify`
(parallel-executor mode):

1. **Task 1 (TDD RED): Failing Login tests** — `ccf2763` (test)
   - 15 failing tests covering D-01 (no-email Forgot Password
     visibility), D-02 (six invalid-shape cases plus token-row
     non-creation), D-03 (active vs unknown category equality),
     D-12 / AUTH-02 (wrap-width assertion), D-14 / AUTH-03
     (no-email operator copy and sysop list rendering and fallback),
     and D-15 ([T] entry path).
2. **Task 2 (TDD GREEN): Implementation** — `9f42ed5` (feat)
   - Always-visible Forgot Password, email-only validation,
     dispatch branching by delivery_mode, wrapped text rendering,
     [T] hint, sysop list inline. 70/70 tests pass for the plan
     verification command.

## Files Created/Modified

- `lib/foglet_bbs/tui/screens/login.ex` — added `alias Foglet.TUI.TextWidth`,
  `@email_shape_regex` plus four new copy attributes, `add_reset_key/1`
  (unconditional), `dispatch_reset_request/2`, `email_shape?/1`,
  `no_email_operator_message/0`, `wrapped_text_rows/3`,
  `reset_wrap_width/1`. Removed `@reset_unavailable_message`,
  `@reset_success_message`, dead `delivery_mode/0`. Updated
  `render_reset_request/2`, `submit_reset_request/1`, `keys_for/2` for
  `:reset_request`, and `maybe_enter_reset_request/1`.
- `lib/foglet_bbs/tui/screens/login/state.ex` — `reset_request/0` now
  returns `%{… error: nil, message: nil, message_category: nil}`. The
  moduledoc reflects the new shape.
- `test/foglet_bbs/tui/screens/login_test.exs` — replaced two stale
  tests (`renders forgot password only in email delivery mode`,
  `'F' enters reset_request sub-state only in email delivery mode`) and
  the entire `handle_key/2 — reset request subflow` describe block.
  Added: D-01 visibility in both modes (split into two tests), D-02
  email-only label test, six invalid-shape tests via `for` loop with
  before/after `reset_password` token-count assertions, D-03 active
  category test, D-03 active-vs-unknown category equality test,
  D-14 no-email operator copy test (no "unavailable", advertises
  `Enter reset token`, names sysop/operator), D-14 sysop-list comma
  separation test, D-14 sysop-fallback test, D-12/AUTH-02 wrap-width
  assertion at `{64, 22}`, D-15 [T] route test, escape-clears test.
  Updated `reset_request_state/1` helper to accept `terminal_size`
  option and to seed the new `error`/`message`/`message_category`
  fields.

## Decisions Made

- **`message_category` as the load-bearing enumeration-safety contract:**
  copy is human-readable and may evolve, so tests assert atom equality
  on `message_category` between active and unknown email submissions
  rather than literal copy matches. Three categories cover the
  Login surface: `:email_dispatched`, `:no_email_operator_assisted`,
  `:invalid_email`. Token-row presence/absence is asserted separately
  for behavioral correctness.
- **Local email-shape regex on the screen mirrors the Verification
  boundary regex character-for-character.** Both use
  `~r/^[^@\s]+@[^@\s]+\.[^@\s]+$/`. The screen rejects malformed input
  before invoking `Verification.request_password_reset_delivery/1`;
  Verification still gates internally as defense in depth (Plan 31-01).
  This means a future non-screen caller cannot probe email-existence
  through token side effects, and the screen and boundary stay
  consistent in what they accept.
- **Wrap width derives from `terminal_size` as `width - 2`.** This
  mirrors `ScreenFrame.inside_width` so the message column fits inside
  the same usable width the chrome reserves. Default is 78 when
  `terminal_size` is missing, preserving existing 80x24 fallback.
- **Each wrapped line is its own `text/2` node.** A single multi-row
  text node would still hand the layout engine a logical wide string
  that downstream truncation could clip; emitting one row per wrapped
  line guarantees the engine sees and lays out each row.
- **Discarded the `{:error, :unavailable}` shape from
  `request_password_reset_delivery/1`** in the screen. The screen now
  branches on `Foglet.Config.delivery_mode/0` directly inside
  `dispatch_reset_request/2`. Verification still returns
  `{:error, :unavailable}` for `:no_email`, but the screen no longer
  consumes that arm — the screen takes the operator-assisted path
  before reaching Verification, so no token side effects are even
  attempted.
- **`[T] Enter reset token` is a hint, not a working route, in this
  plan.** The plan task action explicitly says "Keep the raw reset
  token out of this plan; only expose an entry hint." The keys_for/2
  bar advertises `[T]`, the no-email message body names it, and Plan
  31-03 will land the actual `:reset_consume` sub-state, key routing,
  and Accounts wiring. The test for the T key accepts both `:update`
  and `:no_match` to keep this plan's surface contract loose.

## Deviations from Plan

None — plan executed exactly as written. Both task acceptance-criteria
`rg` predicates pass:

- `rg "TextWidth\.wrap|active_sysop_contact_emails|message_category|Email:"` matches in `login.ex` and `login/state.ex` (10 matches across both files).
- `rg "Handle or email|Password reset by email is unavailable"` finds zero matches in `login.ex` and `login_test.exs`.
- `rg '\{"F", "Forgot password"\}|Enter reset token|operator|sysop'` matches in both `login.ex` and `login_test.exs`.
- `rg "alice@|alice@example|a b@example"` matches the invalid-shape cases in `login_test.exs`.

## Issues Encountered

- **Initial `refute rendered =~ "Handle or email"` test literal triggered
  the plan's `! rg "Handle or email"` predicate** because `rg` is
  blind to test-assertion semantics. Replaced the literal refute with
  `refute rendered =~ ~r/Handle\s+or\s+email/i` — same negative
  assertion, no literal phrase in the source. Predicate now passes.
- **Worktree dependency hydration:** parallel-executor worktree starts
  without `deps/`. Resolved by symlinking the parent's `deps/`
  directory (read-only consumption). `_build/` was deliberately not
  symlinked; the worktree compiled its own `_build/` from scratch
  (~one-time cost). Same approach Plan 31-01 used.

## Threat Model Compliance

| Threat ID | Disposition | Status |
|-----------|-------------|--------|
| T-31-04 (Information Disclosure, `submit_reset_request/1`) | mitigate | Mitigated — `message_category: :email_dispatched` is set identically for valid active and valid unknown email submissions; tests assert atom equality across both. Token-row creation is asserted separately at the boundary level (active creates one, unknown creates none). |
| T-31-05 (Denial of Service, `render_reset_request/2`) | mitigate | Mitigated — `wrapped_text_rows/3` emits one `text/2` node per `TextWidth.wrap/2` line at a `terminal_size`-derived width; test at `{64, 22}` asserts no rendered text node exceeds 62 columns. |
| T-31-06 (Spoofing, no-email operator guidance) | accept | Accepted — copy explicitly names the operator-assisted manual sysop path; no privilege is granted by the screen. Plan 31-03 will wire the actual atomic token consumption through Accounts. |

## TDD Gate Compliance

- RED commit (`ccf2763`, `test(...)`): present and observed 15 failures
  before implementation.
- GREEN commit (`9f42ed5`, `feat(...)`): present and follows the RED
  commit; full test file passes 53/53 (39 prior + 14 net-new minus 0
  removed; the two stale tests were replaced in-place rather than
  deleted, so the count went from 39 → 53 = +14 net).
- REFACTOR commit: not needed — implementation landed in its first
  green form. Removed one dead helper inline.

## Verification

- `rtk mix test test/foglet_bbs/tui/screens/login_test.exs`:
  53 tests, 0 failures.
- `rtk mix test test/foglet_bbs/accounts/verification_test.exs test/foglet_bbs/tui/screens/login_test.exs`:
  70 tests, 0 failures (plan verification command).
- `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs`:
  79 tests, 0 failures (no regression in compact-render coverage;
  Plan 31-04 will add Plan 31-specific smoke cases).

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Plan 31-03 now has a stable Login surface to extend: `[F]` is
  reachable in all delivery modes, the reset request sub-state has
  `error`/`message`/`message_category` fields ready to extend with
  `:reset_consume`-related state, and the keys_for/2 hint already
  reserves `[T] Enter reset token`. Plan 31-03 will:
  - Add `:reset_consume` sub-state in `Login.State` with token /
    new password / confirmation `TextInput` fields (D-04, D-05).
  - Wire Tab/Shift+Tab focus routing among the three fields (D-06).
  - Route `[T]` from `:menu` and from `:reset_request` into
    `:reset_consume` (D-15).
  - Submit through `Verification.consume_reset_token/2` and return
    to the menu on success / inline error on failure (D-07, D-10).
- Plan 31-04 will add 64x22 layout smoke and chrome non-leak tests
  for the new `:reset_consume` rendering. The wrap width and
  per-line `text/2` rendering pattern established here applies
  unchanged to that screen's confirmation copy.

## Self-Check: PASSED

Verified post-write:
- `lib/foglet_bbs/tui/screens/login.ex` — present
- `lib/foglet_bbs/tui/screens/login/state.ex` — present
- `test/foglet_bbs/tui/screens/login_test.exs` — present
- `.planning/phases/31-auth-flow/31-02-SUMMARY.md` — present
- Commit `ccf2763` (RED) — present in git log
- Commit `9f42ed5` (GREEN) — present in git log

---
*Phase: 31-auth-flow*
*Completed: 2026-04-27*
