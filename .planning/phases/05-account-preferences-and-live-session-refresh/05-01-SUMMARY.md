---
phase: 05-account-preferences-and-live-session-refresh
plan: 01
subsystem: accounts
tags: [ecto, accounts, preferences, timezone, timex]

requires:
  - phase: 03-invite-persistence-and-registration-enforcement
    provides: existing Accounts registration and update_profile boundaries
provides:
  - users.timezone persistence with non-null Etc/UTC fallback
  - Account preference defaults for timezone, time_format, and theme
  - Accounts.update_profile/2 validation for private profile and preference saves
affects: [account-screen, session-preferences, chrome-clock]

tech-stack:
  added: [timex]
  patterns:
    - Account profile/preference validation stays in Foglet.Accounts.User.profile_changeset/2
    - User preference maps are merged before validation so unrelated JSON keys survive saves

key-files:
  created:
    - priv/repo/migrations/20260424020939_add_timezone_to_users.exs
  modified:
    - mix.exs
    - mix.lock
    - lib/foglet_bbs/accounts/user.ex
    - test/foglet_bbs/accounts/accounts_test.exs

key-decisions:
  - "Kept Account preference writes behind Accounts.update_profile/2 and User.profile_changeset/2."
  - "Used registered theme id strings from Foglet.TUI.Theme.ids/0 instead of atomizing user input."
  - "Kept time_format in users.preferences and did not add a dedicated column."

patterns-established:
  - "Preference merge: normalize preference keys to strings, merge incoming keys into existing JSON, then validate the merged map."
  - "Theme validation: compare user input to Atom.to_string/1 over registered theme ids; never String.to_atom/1."

requirements-completed: [ACCT-02, ACCT-03, ACCT-04, ACCT-05]

duration: 12min
completed: 2026-04-24
---

# Phase 05 Plan 01: Account Preference Persistence Summary

**Account preference persistence with Timex-backed timezone defaults, validated profile saves, and safe theme/time-format contracts.**

## Performance

- **Duration:** 12 min
- **Started:** 2026-04-24T02:06:05Z
- **Completed:** 2026-04-24T02:18:27Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments

- Added Timex and a `users.timezone` migration with non-null `"Etc/UTC"` fallback.
- Defaulted new accounts to a valid timezone, `preferences["time_format"] == "12h"`, and saved theme `"gray"`.
- Hardened `Accounts.update_profile/2` validation for timezone, time format, registered theme ids, private profile blank normalization, and length caps.
- Added Accounts tests proving valid persistence, invalid-save rejection without row mutation, and preference key preservation.

## Task Commits

1. **Task 1 RED: account preference defaults test** - `4d16e74` (test)
2. **Task 1 GREEN: preference defaults and timezone storage** - `10c286f` (feat)
3. **Task 2 RED: profile preference validation tests** - `ec10399` (test)
4. **Task 2 GREEN: profile preference validation** - `e8b0f8c` (feat)

## Files Created/Modified

- `mix.exs` - Adds Timex and marks existing Gettext as the dependency override.
- `mix.lock` - Locks Timex and its dependency chain.
- `priv/repo/migrations/20260424020939_add_timezone_to_users.exs` - Adds `users.timezone` with non-null `"Etc/UTC"` default.
- `lib/foglet_bbs/accounts/user.ex` - Adds timezone field/defaulting and Account profile/preference validation.
- `test/foglet_bbs/accounts/accounts_test.exs` - Covers defaults, valid saves, invalid saves, blank normalization, length caps, and preference merging.

## Decisions Made

- Kept `time_format` in `users.preferences` rather than adding a column, matching D-01.
- Validated theme strings against registered ids via `Atom.to_string/1`; no user input is atomized.
- Preserved unrelated preference keys by merging incoming maps into the existing persisted preference map before validation.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Resolved Timex/Gettext dependency solver conflict**
- **Found during:** Task 1 (Add timezone storage and new-account defaults)
- **Issue:** `mix deps.get` could not solve `{:timex, "~> 3.7"}` with the app's existing `{:gettext, "~> 1.0"}` dependency because Timex constrains Gettext below 1.0.
- **Fix:** Kept the app's existing Gettext version and marked it as `override: true`, allowing Timex 3.7.13 to lock without downgrading the project dependency.
- **Files modified:** `mix.exs`, `mix.lock`
- **Verification:** `mix deps.get`, `mix test test/foglet_bbs/accounts/accounts_test.exs`, `mix compile --warnings-as-errors`, and `mix precommit` all passed.
- **Committed in:** `10c286f`

---

**Total deviations:** 1 auto-fixed (Rule 3).
**Impact on plan:** Necessary dependency-resolution fix only; no product scope change.

## Issues Encountered

- The local test database had the new migration marked as applied while missing the `timezone` column, likely because the generated migration existed briefly before being edited. The local test schema was repaired with the same `ALTER TABLE` now present in the migration, and verification then passed.
- Pre-existing vendored Raxol warnings still print during Mix commands; they did not fail the project compile or precommit gates.

## Verification

- `mix test test/foglet_bbs/accounts/accounts_test.exs` - passed, 38 tests.
- `mix compile --warnings-as-errors` - passed.
- `mix precommit` - passed, including compile, format, Credo strict, Sobelow, and Dialyzer.

## Known Stubs

None.

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| threat_flag: trust-boundary-validation | `lib/foglet_bbs/accounts/user.ex` | Account profile/preference input now crosses into persistence through `profile_changeset/2`; mitigations from T-05-01 through T-05-03 were implemented. |

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

The Accounts boundary now persists and validates the preference contract that later Account UI and live-session refresh plans can consume. Invalid saves return changesets and do not mutate persisted rows.

## Self-Check: PASSED

- Confirmed all created/modified plan files exist.
- Confirmed task commits `4d16e74`, `10c286f`, `ec10399`, and `e8b0f8c` exist in git history.

---
*Phase: 05-account-preferences-and-live-session-refresh*
*Completed: 2026-04-24*
