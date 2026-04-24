# Phase 02 deferred items

Tracking out-of-scope issues discovered during plan execution that were NOT
auto-fixed, for later cleanup.

## Plan 02-04

- **2026-04-23 — Pre-existing Config.Schema test failures.**
  `test/foglet_bbs/config/schema_test.exs` — two tests (`entries/0 returns
  exactly 6 entries in the documented order` and `defaults/0 returns a map
  of key → default covering exactly the 6 schematized keys`) hard-code the
  old count of 6 schematized keys. Plan 02-01 added a 7th
  (`invite_generation_per_user_limit`) but those assertions were not
  updated, so they fail on main and continue to fail here. Out of scope for
  Plan 02-04; trivial one-line update needed in a Plan 02-01 follow-up (or
  take the fix in whichever plan next touches
  `test/foglet_bbs/config/schema_test.exs`).

- **2026-04-23 — Pre-existing Credo `--strict` failure in
  `lib/foglet_bbs/accounts.ex:94`.** `Foglet.Accounts.register_invite_only_user/1`
  has a redundant final `{:ok, user} -> {:ok, user}` clause inside its
  `Repo.transact` `with`. Credo's "Last clause in `with` is redundant"
  refactoring rule flags it under `--strict`. Phase 03 territory; a
  concurrent session owns `lib/foglet_bbs/accounts.ex`, so Plan 02-04 did
  not touch it. Needs a one-line cleanup after the phase 03 work lands.
