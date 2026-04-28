---
phase: 31-auth-flow
verified: 2026-04-28T00:00:00Z
status: passed
score: 4/4 requirements satisfied (15/15 decisions honored, 14/14 must-haves verified)
overrides_applied: 0
---

# Phase 31: Auth Flow Verification Report

**Phase Goal (ROADMAP / SPEC):** Forgot Password becomes an email-validated, enumeration-safe SSH/TUI flow that honestly supports both email delivery and operator-assisted raw-token reset consumption without leaking reset tokens in chrome.

**Verified:** 2026-04-28
**Status:** passed
**Re-verification:** No — initial verification.

---

## Top-Level Verdict: PASS-WITH-FOLLOWUPS

Phase 31 delivers the SPEC goal end-to-end. All four AUTH-01..AUTH-04 requirements are satisfied with load-bearing test coverage, all fifteen locked decisions D-01..D-15 are honored in code, and the focused phase suite (`verification_test.exs` + `login_test.exs` + `layout_smoke_test.exs`) passes 176/176. Two minor non-blocking findings are listed under "Non-blocking findings".

---

## Goal Achievement: Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Forgot Password is reachable in both email and no-email delivery modes; pressing F enters `:reset_request` | VERIFIED | `lib/foglet_bbs/tui/screens/login.ex:284-286` (`add_reset_key/1` unconditionally inserts `{"F", "Forgot password"}`); `lib/foglet_bbs/tui/screens/login.ex:486-488` (`maybe_enter_reset_request/1` unconditional). Tests at `test/foglet_bbs/tui/screens/login_test.exs:129-141` (render in both modes) and `:171-189` (F enters reset_request in both modes). |
| 2 | Reset request validates email shape locally; invalid input does NOT call Verification | VERIFIED | `lib/foglet_bbs/tui/screens/login.ex:496-515` (submit_reset_request gates via `email_shape?/1` before `dispatch_reset_request/2`); regex line 49. Tests at `login_test.exs:305-560` (six invalid-shape cases asserting token-row count is unchanged). |
| 3 | Valid active email creates exactly one reset_password token; valid unknown/inactive/deleted emails create none — same outward `message_category` | VERIFIED | `lib/foglet_bbs/accounts/verification.ex:99-112` (request_password_reset_delivery), `:232-246` (find_reset_delivery_user gates by email-shape AND `status: :active, deleted_at: nil`). Tests `verification_test.exs:79-247` cover active/unknown/deleted/pending/suspended/rejected. Login enumeration-safety: `login.ex:524-545` sets identical `:email_dispatched` category. |
| 4 | Reset confirmation/no-email copy wraps at 64x22 via TextWidth.wrap | VERIFIED | `login.ex:35` (alias TextWidth), `:453-457` (wrapped_text_rows emits one text/2 per wrapped line), `:463-468` (reset_wrap_width derives `width - 2` from terminal_size). Smoke tests `layout_smoke_test.exs:2606-2848` assert multi-row wrap at 64x22 and `display_width(row) <= 64`. |
| 5 | No-email mode lists active sysop emails comma-separated; falls back honestly when none; never says "unavailable" | VERIFIED | `login.ex:547-557` (no_email_operator_message); `verification.ex:209-217` (active_sysop_contact_emails filters `role: :sysop, status: :active, not is_nil(email)`, joins QueryHelpers.not_deleted). Smoke tests at `layout_smoke_test.exs:~2700-2848` build deleted/pending/non-sysop fixtures and assert exclusion + comma-separated rendering. |
| 6 | `:reset_consume` is reachable from BOTH the Login menu and the Forgot Password flow | VERIFIED | Menu path: `login.ex:119-120` (handle_menu_key for `t`/`T` → enter_reset_consume). Reset-request path: `login.ex:169-170` (handle_reset_key for `t`/`T`). Tests `login_test.exs:611-650` cover both entries. |
| 7 | Reset-consume form has three fields (token unmasked, password+confirmation masked) with deterministic Tab/Shift+Tab focus | VERIFIED | `state.ex:71-81` (reset_consume builds three TextInputs, password/confirmation with `mask_char: "*"`); `state.ex:125-137` (next_/prev_reset_consume_focus). Login.ex:184-211 (handle_reset_consume_key) routes Tab/`:backtab`/`:shift_tab`. Tests `login_test.exs:652-797` verify masking, focus cycle, and char-into-focused-input routing. |
| 8 | Mismatched password confirmation blocks submission without consuming a token | VERIFIED | `login.ex:577-582` (submit_reset_consume short-circuits before Accounts call on mismatch). Test `login_test.exs:801-834` asserts token row remains in DB after mismatch. |
| 9 | Successful raw-token consume returns to logged-out menu and clears all fields | VERIFIED | `login.ex:584-588` (`{:ok, _user} -> LoginState.put(state, LoginState.default())`). Test `login_test.exs:836-874` asserts `sub == :menu`, all input fields nil, password actually changed (`Auth.authenticate_by_password` returns the user). |
| 10 | Atomic single-use consumption: concurrent attempts produce exactly one success | VERIFIED | `verification.ex:168-189` (consume_reset_token uses `Repo.transact/1` + `Repo.delete_all(claim_query)` row-claim returning `{1,_}` for winner, `{0,_}` for loser). Test `verification_test.exs:400-428` runs two `Task.async` consumers and asserts `successes == 1, failures == 1`. |
| 11 | Generic invalid/expired/used/malformed copy is byte-identical (no failure-mode leak) | VERIFIED | `verification.ex:166-189` returns single `:invalid_or_expired` atom for all token failure modes. `login.ex:59` (`@reset_consume_invalid_or_expired_message`) — single string. Tests: `login_test.exs:898-923` asserts `err_unknown == err_malformed`; `:876-896` asserts copy contains none of `expired`/`already-used`/`malformed`. |
| 12 | Raw token never appears in chrome/breadcrumb/keys/error copy | VERIFIED | Sentinel-driven smoke tests at `layout_smoke_test.exs:2853-3033` (5 cases): chrome_frame absence at 64x22 AND 80x24, sentinel on exactly one focused-input row, breadcrumb parts state-derived, command-bar absence, error-row absence after mismatch. |
| 13 | All token consumption goes through Accounts.Verification — Login never reaches Repo | VERIFIED | `login.ex` aliases (`:31-38`) include no `Repo`. `grep -n Repo lib/foglet_bbs/tui/screens/login.ex` returns 0 hits. `submit_reset_consume/1` (`:584`) only calls `Verification.consume_reset_token/2`. |
| 14 | 64x22 layout: full reset flow renders without truncation at SSH minimum | VERIFIED | `layout_smoke_test.exs:2606-2848` proves email-mode confirmation, no-email + sysop list, and no-sysop fallback all produce multi-row content with `display_width <= 64`. Reset-consume sentinel test (`:2902-2930`) confirms the form lays out cleanly at 64x22. |

**Score:** 14/14 truths verified.

---

## Per-Requirement Audit (AUTH-01..AUTH-04)

| Req ID | Status | Code Evidence | Test Evidence |
|--------|--------|---------------|---------------|
| **AUTH-01** Login Forgot Password validates email locally; inline error; enumeration-safe | COVERED | `login.ex:49,496-545` (regex + dispatch); `verification.ex:99-112,232-246` (boundary email-shape gate + status filter) | `login_test.exs:305-573` (six invalid shapes, no-token-rows, active-vs-unknown category equality); `verification_test.exs:79-247` (active/unknown/deleted/pending/suspended/rejected token side-effects) |
| **AUTH-02** Reset confirmation wraps via TextWidth.wrap so 64x22 doesn't crop | COVERED | `login.ex:35,453-468` (wrapped_text_rows + reset_wrap_width) | `layout_smoke_test.exs:2606-2848` (multi-row + per-row width check at 64x22 in both email and no-email modes); `login_test.exs` wrap-width test at `~536-558` |
| **AUTH-03** No-email mode renders honest operator-assisted copy with discoverable token-consume entry from both Forgot Password and Login menu | COVERED | `login.ex:53-54,284-293,547-557` (intro/fallback copy, F+T menu keys, sysop list); `verification.ex:209-217` (active_sysop_contact_emails) | `login_test.exs:611-650` (T from menu and reset_request → reset_consume); `layout_smoke_test.exs:~2700-2848` (sysop list comma-separated, deleted/pending/non-sysop excluded, fallback honest); `verification_test.exs:248-307` |
| **AUTH-04** Atomic single-use reset-token consume powering `:reset_consume` sub-state | COVERED | `verification.ex:166-198` (consume_reset_token in Repo.transact + row-claim); `user_token.ex:140-163` (reset_token_claim_query); `login.ex:99,184-211,571-602` (sub-state routing + submit) | `verification_test.exs:308-428` (happy path, malformed, expired, unknown, invalid password, **concurrent two-Task.async asserting exactly one success**); `login_test.exs:801-957` (mismatch preserves token, success returns to menu, error generic, raw-token non-leak) |

---

## Per-Decision Audit (D-01..D-15)

| ID | Decision | Status | Evidence |
|----|----------|--------|----------|
| D-01 | `[F] Forgot password` always exposed regardless of delivery_mode | HONORED | `login.ex:281-286` (`add_reset_key/1` unconditional, no delivery_mode branch). `:486-488` (`maybe_enter_reset_request/1` unconditional). Tests cover both modes. |
| D-02 | Reset request becomes email-only; invalid local shapes never invoke Accounts | HONORED | `login.ex:49` (regex), `:502-512` (gate before dispatch). Field label "Email:" at `:366`. Verification also gates at boundary `verification.ex:238-245` (defense in depth). |
| D-03 | Valid email submissions preserve generic outward category in email mode regardless of account existence | HONORED | `login.ex:524-535` sets `:email_dispatched` for both branches; tests `login_test.exs` assert active vs unknown produce equal `message_category`. |
| D-04 | `:reset_consume` is inline Login sub-state with screen-local state in Login.State | HONORED | `state.ex:71-81` (reset_consume builder); `login.ex:80-100` (render+handle_key dispatch). No Modal.Form involvement. |
| D-05 | Three TextInput fields; password fields masked | HONORED | `state.ex:76-79` (token unmasked, password/confirmation `mask_char: "*"`). Test `login_test.exs:652-669` asserts mask_char per field. |
| D-06 | Existing Login focus pattern, not Modal.Form; Tab and Shift+Tab cycle | HONORED | `state.ex:125-137` (next/prev focus helpers); `login.ex:184-199` handles `:tab`, `:backtab`, AND `:shift_tab`. Tests cover the cycle in both directions plus character-routing. |
| D-07 | Escape returns to menu and clears fields; success also returns to menu | HONORED | `login.ex:203-206` (escape → LoginState.default()); `:584-588` (success → LoginState.default()). Tests `login_test.exs:836-874, 959-974`. |
| D-08 | Consume operation lives on Verification, not TUI/Web | HONORED | `verification.ex:168-189` is the sole boundary. Login does not import Repo. |
| D-09 | Reuse verify_email_token_query, password_changeset, Repo.transact | HONORED | `verification.ex:169` calls `UserToken.verify_email_token_query(raw, "reset_password")`; `:171` Repo.transact; `:192` `User.password_changeset(user, attrs)`. |
| D-10 | Generic edge: invalid/malformed/expired/used produce identical user-facing output | HONORED | Single `:invalid_or_expired` atom (`verification.ex:174,181,187`) maps to single `@reset_consume_invalid_or_expired_message` (`login.ex:59`). Tests assert byte-equality and absence of failure-mode words. |
| D-11 | Raw tokens never appear in chrome/breadcrumb/status/modal/command/log | HONORED | `keys_for(:reset_consume, _)` (`login.ex:235-241`) is state-derived. Sentinel smoke tests at `layout_smoke_test.exs:2853-3033` (5 cases) verify chrome_frame, breadcrumb parts, command bar, single-row placement, error-row absence. |
| D-12 | Reset confirmation/no-email copy uses TextWidth.wrap or equivalent | HONORED | `login.ex:35,453-468` use `Foglet.TUI.TextWidth.wrap/2`. |
| D-13 | Sysop contacts come from a narrow Accounts/Verification helper, not Login Repo queries | HONORED | `verification.ex:209-217` defines `active_sysop_contact_emails/0`; `login.ex:548` is the only consumer. Login imports no Ecto/Repo modules. |
| D-14 | No-email lists active non-deleted sysops comma-separated; honest fallback when none | HONORED | `login.ex:547-557` joins emails with `", "` or falls back to `@reset_no_email_no_sysops_fallback`. Smoke tests confirm rendering rules. |
| D-15 | Token-consume entry reachable from BOTH Forgot Password flow AND Login menu | HONORED | Menu: `login.ex:119-120`. Reset-request: `login.ex:169-170`. Both paths have dedicated tests at `login_test.exs:611-650`. |

All 15 decisions honored.

Note: D-16/D-17/D-18 (testing-shape decisions) are informational — they are honored implicitly by the test files actually existing and containing the required coverage.

---

## Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/foglet_bbs/accounts/verification.ex` | consume_reset_token/2, active_sysop_contact_emails/0, email-only narrow | VERIFIED | All three present (lines 168, 209, 232-246). 258 lines total. |
| `lib/foglet_bbs/accounts/user_token.ex` | reset_token_claim_query/1 | VERIFIED | Present at line 154. |
| `lib/foglet_bbs/tui/screens/login.ex` | reset_consume render/handle/submit, Forgot Password always-visible, wrapped copy, no-email operator copy, T entries from menu and reset_request | VERIFIED | All present; 699 lines. |
| `lib/foglet_bbs/tui/screens/login/state.ex` | reset_consume/0, input_key/1 for :token/:password_confirmation, next/prev focus helpers | VERIFIED | All present at lines 71-81, 117-119, 125-137. 138 lines. |
| `test/foglet_bbs/accounts/verification_test.exs` | Domain coverage for all reset behavior including concurrent | VERIFIED | 430 lines; concurrent test at 400-428. |
| `test/foglet_bbs/tui/screens/login_test.exs` | Login key-routing, validation, focus, mismatch, escape, generic errors, non-leak | VERIFIED | 1250 lines. |
| `test/foglet_bbs/tui/layout_smoke_test.exs` | 64x22 wrap + raw-token non-leak | VERIFIED | 3034 lines; Phase 31 describes at 2606 and 2853. |

---

## Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| `login.ex` | `Verification.consume_reset_token/2` | submit_reset_consume | WIRED | `login.ex:584` |
| `login.ex` | `Verification.request_password_reset_delivery/1` | dispatch_reset_request | WIRED | `login.ex:528` |
| `login.ex` | `Verification.active_sysop_contact_emails/0` | no_email_operator_message | WIRED | `login.ex:548` |
| `login.ex` | `TextWidth.wrap/2` | wrapped_text_rows | WIRED | `login.ex:455` |
| `verification.ex` | `UserToken.verify_email_token_query/2` | consume_reset_token raw verification | WIRED | `verification.ex:169` |
| `verification.ex` | `UserToken.reset_token_claim_query/1` | atomic row-claim delete | WIRED | `verification.ex:170,180` |
| `verification.ex` | `Repo.transact/1` | atomic transaction wrapper | WIRED | `verification.ex:171` |
| `verification.ex` | `User.password_changeset/2` | password update | WIRED | `verification.ex:192` |
| `BreadcrumbBar` | `:reset_consume` mapping | parts_for | WIRED | `breadcrumb_bar.ex:88-89` (`Foglet > Forgot Password > Enter Token`) |

All 9 critical links wired.

---

## Acceptance Command Results

Per `.planning/phases/31-auth-flow/31-VALIDATION.md`:

| Command | Result | Notes |
|---------|--------|-------|
| `rtk mix test test/foglet_bbs/accounts/verification_test.exs test/foglet_bbs/tui/screens/login_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` | **176 tests, 0 failures** (1.7s) | Verified directly during this verification run |
| `rtk mix precommit` | PASSED (per orchestrator note; not re-run here) | Compile/format/credo/sobelow/dialyzer all green |
| Full suite | 2026 tests, 0 failures (per orchestrator note) | No regressions |

---

## Phase Invariants

| Invariant | Status | Evidence |
|-----------|--------|----------|
| Atomic single-use claim — concurrent attempts produce exactly one success | VERIFIED | `verification.ex:171-185` (Repo.transact + delete_all row-claim); `verification_test.exs:400-428` two-Task.async test asserts `successes == 1, failures == 1`. |
| Generic error UX — invalid/expired/used identical | VERIFIED | Single atom `:invalid_or_expired`; single string `@reset_consume_invalid_or_expired_message`; tests assert byte equality (`login_test.exs:898-923`). |
| Non-leak — raw tokens absent from chrome, breadcrumb, key hints, error copy | VERIFIED | `layout_smoke_test.exs:2853-3033` (5 sentinel-based tests), `login_test.exs:925-957`. |
| 64x22 layout — full reset flow renders without truncation | VERIFIED | `layout_smoke_test.exs:2606-2848` asserts multi-row wrap and `display_width <= 64` for email and no-email confirmation copy at 64x22. |
| Boundary respect — screens never reach Repo directly | VERIFIED | `login.ex` does not import Repo; `grep -n Repo lib/foglet_bbs/tui/screens/login.ex` returns 0 matches. All token consumption routes through `Verification.consume_reset_token/2`. |

All five phase invariants hold.

---

## Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `test/foglet_bbs/tui/screens/login_test.exs` | 578 | `defp reset_consume_state(opts \\ [])` — default arg never used (compiler warning shown in test output) | Info | Cosmetic; one of two minor credo refactors already addressed in commit `29a8141` did NOT clean this up. Remove either the default value or add a no-arg call site. |
| (general) | — | No TODO/FIXME/PLACEHOLDER markers found in any phase 31 deliverable | — | Clean. |
| (general) | — | No empty implementations (`return null`, `=> {}`) found | — | Clean. |

No blocker or warning-severity anti-patterns.

---

## Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Phase 31 narrow suite green | `rtk mix test test/foglet_bbs/accounts/verification_test.exs test/foglet_bbs/tui/screens/login_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` | 176 tests, 0 failures | PASS |
| Atomic concurrent consume produces single winner | Embedded in test suite (`verification_test.exs:400-428` Task.async pair) | Asserts `successes == 1, failures == 1` | PASS |
| Boundary respect — no Repo import in Login | `grep -c "alias.*Repo\|FogletBbs\.Repo" lib/foglet_bbs/tui/screens/login.ex` | 0 | PASS |
| BreadcrumbBar mapping for `:reset_consume` resolves to expected parts | Smoke test in `layout_smoke_test.exs:2932-2952` | "Foglet" + "Forgot Password" + "Enter Token" | PASS |

---

## Requirements Coverage Matrix

| Req | Source Plan(s) | Description | Status | Evidence |
|-----|---------------|-------------|--------|----------|
| AUTH-01 | 31-01, 31-02, 31-04 | Email-only validation, inline error, enumeration-safe | SATISFIED | See Per-Requirement Audit. |
| AUTH-02 | 31-03 (via 31-04 smoke), 31-04 | TextWidth.wrap at 64x22 | SATISFIED | See Per-Requirement Audit. |
| AUTH-03 | 31-01, 31-02, 31-03, 31-04 | No-email honest operator copy + entry-point discovery | SATISFIED | See Per-Requirement Audit. |
| AUTH-04 | 31-01, 31-03, 31-04 | Atomic single-use raw-token consume + `:reset_consume` UX | SATISFIED | See Per-Requirement Audit. |

No orphaned phase-31 requirements. REQUIREMENTS.md status column for AUTH-01..AUTH-04 currently reads "Pending" — that should be flipped to "Done" by milestone close-out, but is not a phase blocker.

---

## Documentation

| File | Status | Notes |
|------|--------|-------|
| `31-01-SUMMARY.md` | Present, honest | Documents zero deviations; matches code. |
| `31-02-SUMMARY.md` | Present, honest | Documents one minor in-flight refactor (regex literal in test); matches code. |
| `31-03-SUMMARY.md` | Present, honest | Documents the menu-key label re-tuning ("Enter reset token" → "Reset token") to fit the 80x24 command bar; matches code at `login.ex:292`. |
| `31-04-SUMMARY.md` | Present, honest | Documents two test-only deviations (worktree dep symlinks, pending-status fixture fix) and the explicit decision to defer `rtk mix precommit` to the orchestrator. |

All four summaries are honest about deviations (none are scope-reducing).

---

## Non-Blocking Findings

These do not affect the verification verdict but should be tracked:

1. **Unused default argument warning** — `test/foglet_bbs/tui/screens/login_test.exs:578` declares `defp reset_consume_state(opts \\ [])` but every call site passes a keyword list. The default value is never used. Compiler emits a warning on every test run. **Fix:** drop the `\\ []` default or, less invasively, add a single zero-arity call site (e.g. in a smoke describe). Estimated effort: 1 line.

2. **REQUIREMENTS.md status column lag** — AUTH-01..AUTH-04 still show "Pending" in `.planning/REQUIREMENTS.md:163-166`. This is normally flipped at milestone close-out, not at phase close-out, so it is not a phase blocker. Just noting for the v1.4 audit.

3. **Plan 31-04 deferred `rtk mix precommit`** — Plan 31-04's Task 2 spec called for running `rtk mix precommit` inside the worktree; the executor deferred it to the orchestrator merge gate per parallel-executor instructions. The orchestrator did run `mix precommit` post-merge (per orchestrator-supplied note), so this resolved cleanly. No open action.

---

## Test Coverage Gaps

Reviewed each AUTH-XX against the test files. **No requirement lacks a direct, load-bearing test assertion.** Specifically:

- AUTH-01: 6+ invalid-shape cases, active vs unknown category equality, token-row count assertions before/after each invalid input.
- AUTH-02: 64x22 multi-row + per-row `display_width <= 64` smoke.
- AUTH-03: Sysop-list comma separation, deleted/pending/non-sysop exclusion, no-sysop fallback, T-key entry from both paths, no-"unavailable" assertion.
- AUTH-04: Concurrent two-Task.async test, mismatch-preserves-token, success-returns-to-menu, generic-error byte-equality, raw-token non-leak across chrome/breadcrumb/keys/error.

---

## Gaps Summary

**No gaps.** Phase 31 achieves its stated goal end-to-end with load-bearing test coverage and no scope-reducing deviations. Status: `passed`.

---

*Verified: 2026-04-28*
*Verifier: Claude (gsd-verifier, goal-backward mode)*
