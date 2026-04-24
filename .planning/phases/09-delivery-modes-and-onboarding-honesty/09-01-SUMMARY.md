---
phase: 09-delivery-modes-and-onboarding-honesty
plan: 01
subsystem: auth
tags: [email, swoosh, runtime-config, accounts, onboarding]

requires: []
provides:
  - Delivery mode runtime config enum with no_email default
  - Typed Foglet.Config.delivery_mode/0 accessor
  - Swoosh mailer boundary and SMTP runtime configuration
  - Text-only verification and password-reset email builders
affects: [phase-09, accounts, config, onboarding]

tech-stack:
  added: [swoosh, gen_smtp]
  patterns:
    - Schematized non-secret runtime mode in Foglet.Config
    - OTP-configured Swoosh mailer boundary
    - Text-only Accounts email builder module

key-files:
  created:
    - lib/foglet_bbs/mailer.ex
    - lib/foglet_bbs/accounts/email.ex
  modified:
    - mix.exs
    - mix.lock
    - config/config.exs
    - config/runtime.exs
    - config/test.exs
    - lib/foglet_bbs/config/schema.ex
    - lib/foglet_bbs/config.ex
    - priv/repo/seeds/config.exs
    - test/foglet_bbs/config/schema_test.exs
    - test/foglet_bbs/config_test.exs
    - test/foglet_bbs/accounts/accounts_test.exs

key-decisions:
  - "Persist only delivery_mode in DB-backed config; keep SMTP credentials in runtime environment config."
  - "Use Foglet.Mailer as the only Swoosh delivery boundary."
  - "Keep reset email copy terminal-native and free of browser reset URLs."

patterns-established:
  - "Delivery mode is read through Foglet.Config.delivery_mode/0 and validates only email or no_email."
  - "Swoosh adapter settings are OTP runtime config, with tests using Swoosh.Adapters.Test."

requirements-completed: [MAIL-01, MAIL-02]

duration: 8min
completed: 2026-04-24
---

# Phase 09 Plan 01: Delivery Mode and Swoosh Foundation Summary

**Runtime delivery-mode config with a Swoosh mailer boundary and terminal-native Accounts email builders**

## Performance

- **Duration:** 8 min
- **Started:** 2026-04-24T16:44:56Z
- **Completed:** 2026-04-24T16:52:14Z
- **Tasks:** 2
- **Files modified:** 11

## Accomplishments

- Added schematized `"delivery_mode"` with values `"email"` and `"no_email"`, defaulting to `"no_email"`.
- Added `Foglet.Config.delivery_mode/0` and schema-driven seed coverage.
- Added Swoosh and `gen_smtp`, `Foglet.Mailer`, test adapter config, and env-backed SMTP runtime config.
- Added `Foglet.Accounts.Email.verification_code/2` and `password_reset/2` text builders without browser reset URLs.

## Task Commits

1. **Task 1 RED:** `5329eca` test(09-01): add failing delivery mode config tests
2. **Task 1 GREEN:** `1358022` feat(09-01): add delivery mode runtime config
3. **Task 2 RED:** `1c34185` included failing Swoosh email builder tests
4. **Task 2 GREEN:** `d8657d6` feat(09-01): add Swoosh mailer foundation

## Files Created/Modified

- `lib/foglet_bbs/config/schema.ex` - Adds the `delivery_mode` enum spec.
- `lib/foglet_bbs/config.ex` - Adds `delivery_mode/0`.
- `priv/repo/seeds/config.exs` - Documents schema-driven seeding of `"delivery_mode"`.
- `mix.exs` / `mix.lock` - Adds Swoosh and SMTP support.
- `config/config.exs` - Adds default local mailer adapter.
- `config/runtime.exs` - Adds env-backed SMTP adapter config.
- `config/test.exs` - Uses `Swoosh.Adapters.Test`.
- `lib/foglet_bbs/mailer.ex` - Adds the Swoosh mailer boundary.
- `lib/foglet_bbs/accounts/email.ex` - Adds transactional email builders.
- `test/foglet_bbs/config/schema_test.exs`, `test/foglet_bbs/config_test.exs`, `test/foglet_bbs/accounts/accounts_test.exs` - Cover config and email builder behavior.

## Decisions Made

- SMTP provider settings are read from `FOGLET_SMTP_*` environment variables only when an SMTP relay/host is present.
- The password-reset email carries terminal reset instructions and avoids `/users/reset_password`, `http://`, and `https://` copy.

## Deviations from Plan

None - plan scope executed as written.

## Issues Encountered

- A parallel worktree/orchestrator commit landed while Task 2 RED tests were staged, so the Task 2 RED tests were included in `1c34185` alongside unrelated phase-10 planning files. No additional changes were made to `STATE.md` or `ROADMAP.md` by this executor after that occurred.

## Known Stubs

None.

## Threat Flags

None beyond the planned mailer/env trust boundary in the plan threat model.

## Verification

- `rtk mix test test/foglet_bbs/config/schema_test.exs test/foglet_bbs/config_test.exs`
- `rtk mix deps.get`
- `rtk mix test test/foglet_bbs/accounts/accounts_test.exs`
- `rtk mix test test/foglet_bbs/config/schema_test.exs test/foglet_bbs/config_test.exs test/foglet_bbs/accounts/accounts_test.exs`
- `rtk mix precommit`

## Self-Check: PASSED

- Created files exist.
- Task commits exist.
- No summary-blocking stubs found in files created or modified by this plan.
- Browser reset URL grep returned no matches in `lib/foglet_bbs/accounts/email.ex`.

## User Setup Required

None for tests. Operators enabling email delivery later must provide runtime `FOGLET_SMTP_*` environment variables.

## Next Phase Readiness

MAIL-01 and MAIL-02 foundations are ready for downstream verification, reset, TUI, Sysop, and Mix-task behavior to branch from `Foglet.Config.delivery_mode/0` and deliver through `Foglet.Mailer`.

---
*Phase: 09-delivery-modes-and-onboarding-honesty*
*Completed: 2026-04-24*
