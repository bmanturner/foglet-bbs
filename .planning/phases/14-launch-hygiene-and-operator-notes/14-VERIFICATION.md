---
phase: 14-launch-hygiene-and-operator-notes
verified: 2026-04-24T21:58:00Z
status: gaps_found
verifier: codex
requirements:
  - HYGN-01
  - HYGN-02
  - HYGN-03
---

# Phase 14 Verification

## Verdict

FAILED/PARTIAL. Phase 14 delivered the Sysop config accountability audit and some terminal-copy guardrails, but it failed the central launch-honesty goal by preserving and documenting a fake password-reset URL workflow. The reset-password Mix task emits `/users/reset_password/...` HTTP URLs even though Foglet has no supported HTTP reset interaction and no TUI token-consumption path.

Responsible party: Codex, during this Phase 14 execution. Codex failed to identify the reset-password URL as a false promise, documented it in README operator notes, and initially treated the related tests as launch-hygiene evidence instead of flagging them as a blocker.

## Requirement Coverage

- HYGN-01: Covered. `test/foglet_bbs/tui/screens/sysop/config_accountability_test.exs` enumerates `Foglet.Config.Schema.entries/0`, checks SITE/LIMITS form key coverage, proves actor-aware successful writes, nil-actor forbidden behavior, and no-email plus required-verification blocking.
- HYGN-02: Failed/partially covered. Existing and added tests cover some launch-copy claims, delivery-copy behavior, verification/user-status Mix task copy and forbidden paths, required-board unsubscribe behavior, and Sysop config accountability. However, the reset-password Mix task and its tests still assert a browser-style reset URL despite no supported HTTP/TUI consumption path. The broader audit-and-prune pass for weak tests was not completed.
- HYGN-03: Failed/partially covered. `README.md` was updated with SSH-first and delivery-mode notes, but it also documented `mix foglet.user.reset_password HANDLE` as generating an operator reset URL. That is a false capability claim for this product. README-specific tests were intentionally removed by user request.

## Evidence

- Sysop config visibility ledger exists and is tied to schema and form key lists.
- `14-BLOCKERS.md` now records a critical blocker: reset-password URL output is a false HTTP workflow promise. Earlier "no blockers" statements in Plan 14 summaries were wrong.
- Launch-copy audit remains scoped to terminal-visible TUI and Mix task source; it no longer audits `README.md`.
- README was rewritten as pre-alpha operator notes instead of target-state product copy.
- README test file was deleted: `test/readme_operator_notes_test.exs`.

## Verification Commands

- `rtk mix test test/foglet_bbs/tui/screens/sysop/config_accountability_test.exs test/foglet_bbs/tui/screens/sysop_test.exs test/foglet_bbs/tui/screens/sysop/site_form_test.exs test/foglet_bbs/config test/foglet_bbs/tui/screens/launch_copy_audit_test.exs test/foglet_bbs/tui/screens/delivery_copy_test.exs test/mix/tasks/foglet_user_reset_password_test.exs test/mix/tasks/foglet_user_verification_code_test.exs test/mix/tasks/foglet_user_status_test.exs test/mix/tasks/foglet.board_subscriptions_test.exs`
  - Result: 140 tests, 0 failures after Wave 1 merge.
- `rtk mix test test/readme_operator_notes_test.exs test/foglet_bbs/tui/screens/launch_copy_audit_test.exs test/foglet_bbs/tui/screens/sysop/config_accountability_test.exs test/foglet_bbs/tui/screens/sysop_test.exs test/foglet_bbs/tui/screens/sysop/site_form_test.exs test/foglet_bbs/tui/screens/delivery_copy_test.exs test/mix/tasks/foglet_user_reset_password_test.exs test/mix/tasks/foglet_user_verification_code_test.exs test/mix/tasks/foglet_user_status_test.exs test/mix/tasks/foglet.board_subscriptions_test.exs`
  - Result before README test removal: 102 tests, 0 failures.
- `rtk mix test test/foglet_bbs/tui/screens/launch_copy_audit_test.exs`
  - Result after README test removal: 2 tests, 0 failures.

## Gaps

### 1. Critical launch-honesty failure: fake reset-password URL workflow

`lib/mix/tasks/foglet.user.reset_password.ex` builds and prints `https://<host>/users/reset_password/<token>`. Foglet does not support end-user HTTP interactions, does not have a supported HTTP reset-password product flow, and has no TUI token-consumption path for that token. Therefore the task output, README wording, and tests that assert `/users/reset_password/` are false launch promises.

Responsible party: Codex. This gap was missed and then documented as acceptable during Phase 14 execution by Codex. It should have been flagged immediately as a blocker under HYGN-02/HYGN-03.

Expected remediation: remove or change `mix foglet.user.reset_password` so it does not emit HTTP URLs, remove README claims that imply a usable reset URL, and rewrite/delete tests that assert `/users/reset_password/` output unless a real SSH/TUI reset-token consumption flow is implemented.

### 2. Low-value test pruning audit was not completed

The phase spec required removing or rewriting tests that are static, redundant, or too shallow to catch meaningful regressions. The executed work added coverage and audited selected blocker-flow tests, but it did not perform or document a real suite-wide weak-test pruning pass.

Expected remediation: run a focused test-quality audit for v1.2 blocker-flow tests, remove/rewrite weak tests only where deeper behavior coverage exists, and document each removal/rewrite with rationale.

### 3. README operator notes are no longer test-backed

README.md now carries the intended operator notes, but direct README-specific tests were removed by user request. This is accepted for this run, but it means HYGN-03 is verified by file inspection rather than executable tests.

Expected remediation: none unless the project later wants documentation linting or a non-test review checklist for README operator notes.

## Residual Notes

`rtk mix precommit` passed in the 14-03 worktree before the README test removal. It was not rerun after the final user-requested test deletion because the user asked to wrap up and write this verification artifact.
