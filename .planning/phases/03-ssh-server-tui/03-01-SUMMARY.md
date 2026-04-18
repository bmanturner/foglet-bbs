---
plan: 03-01
phase: 03-ssh-server-tui
status: complete
completed_at: 2026-04-18
---

# Plan 03-01 Summary: Foundation

## What Was Built

Added the Phase 3 foundation: Raxol 2.4 dependency, `users.status` migration, email verification code API, Phase 3 runtime config defaults, and 14 Wave-0 test stubs.

## Key Deliverables

### Raxol Dependency
- Raxol **2.4.0** installed from Hex (`f660fca97...`)
- Added to `mix.exs` as `{:raxol, "~> 2.4"}`, resolved in `mix.lock`
- Raxol DevHints feature disabled in `config/config.exs` via `features` map to work around a Raxol 2.4.0 startup bug (`normalize_init_result/1` doesn't handle `:ignore` return when compiled in test env)

### Migration
- Timestamp: `20260418010000` (sorts after Phase 2's last migration `20260418000013`)
- Adds `users.status` as `:string NOT NULL DEFAULT 'active'` with CHECK constraint `status IN ('active', 'pending', 'suspended')` and an index
- Round-trip verified: `mix ecto.migrate` → `mix ecto.rollback --step 1` → `mix ecto.migrate` all exit 0

### User Schema
- `field :status, Ecto.Enum, values: [:active, :pending, :suspended], default: :active`
- `User.status_changeset/2` added for sysop approval (Phase 8)
- `:status` is NOT in `registration_changeset/2` cast list — set programmatically only

### Accounts API
- `Accounts.register_pending_user/1`: inserts with `%User{status: :pending}` before changeset (D-05)
- `Accounts.build_verify_code/1`: generates + persists 6-char plain code, returns `{:ok, raw_code}`
- `Accounts.verify_email_code/2`: validates code, confirms user on match, cleans up tokens (D-10, D-12)
- `UserToken.build_verify_code/1`: generates plain 6-char uppercase alphanumeric code (NOT hashed — D-08)
- `UserToken.verify_code_query/2`: queries by exact code + email + 15-min window

### Seeds
- Replaced old Phase 1 config keys (`registration.mode`, `registration.require_email_verification`)
- New Phase 3 keys: `registration_mode = "open"` (D-02/D-03), `invite_code_generators = "sysop_only"` (D-04), `max_post_length = 8192` (D-31)
- Seeds run idempotently in both dev and test env

### Wave-0 Test Stubs
14 files created with `@tag :pending` + `flunk/1` stubs:
- `test/foglet_bbs/ssh/supervisor_test.exs` (4 stubs, async: false)
- `test/foglet_bbs/ssh/key_cb_test.exs` (6 stubs, async: true)
- `test/foglet_bbs/sessions/session_test.exs` (7 stubs, async: false)
- `test/foglet_bbs/sessions/supervisor_test.exs` (4 stubs, async: false)
- `test/foglet_bbs/tui/app_test.exs` (15 stubs, async: true)
- `test/foglet_bbs/tui/screens/login_test.exs` (5 stubs)
- `test/foglet_bbs/tui/screens/register_test.exs` (7 stubs)
- `test/foglet_bbs/tui/screens/verify_test.exs` (7 stubs)
- `test/foglet_bbs/tui/screens/main_menu_test.exs` (4 stubs)
- `test/foglet_bbs/tui/screens/board_list_test.exs` (4 stubs)
- `test/foglet_bbs/tui/screens/thread_list_test.exs` (3 stubs)
- `test/foglet_bbs/tui/screens/post_reader_test.exs` (5 stubs)
- `test/foglet_bbs/tui/screens/post_composer_test.exs` (7 stubs)
- `test/foglet_bbs/tui/widgets/modal_test.exs` (3 stubs)

## Test Results
- **11 green tests** in `accounts_verify_code_test.exs` (Tasks 1 + 2)
- **84 pending stubs** excluded from test run
- **149 total tests passing**, 0 failures

## Files Created
- `priv/repo/migrations/20260418010000_add_status_to_users.exs`
- `test/foglet_bbs/accounts_verify_code_test.exs`
- 14 Wave-0 test stub files (see above)

## Files Modified
- `mix.exs` — Raxol dependency added
- `mix.lock` — Raxol + transitive deps resolved
- `config/config.exs` — Raxol features map (DevHints workaround)
- `lib/foglet_bbs/accounts/user.ex` — :status field + status_changeset/2
- `lib/foglet_bbs/accounts/user_token.ex` — build_verify_code/1, verify_code_query/2
- `lib/foglet_bbs/accounts.ex` — register_pending_user/1, build_verify_code/1, verify_email_code/2
- `priv/repo/seeds.exs` — Phase 3 runtime config defaults

## Deviations
- **Raxol DevHints bug**: Raxol 2.4.0's `DevHints` GenServer crashes when compiled in test env (its `@mix_env` compile-time attr is `:test`, making `enabled: false`, but `normalize_init_result/1` only handles `{:ok, state}` not `:ignore`). Workaround: disabled `performance_monitoring` and `dev_performance_hints` in the Raxol `:features` config map. This is a Raxol upstream bug, not a project issue.
- `valid_user_attributes/0` was already present in `AccountsFixtures` — no changes needed to fixtures.

## Self-Check: PASSED
- `grep ':raxol, "~> 2.4"' mix.exs` — matches
- `grep 'raxol' mix.lock` — matches
- `grep 'field :status, Ecto.Enum' lib/foglet_bbs/accounts/user.ex` — matches
- `grep 'def register_pending_user' lib/foglet_bbs/accounts.ex` — matches
- `grep 'def verify_email_code' lib/foglet_bbs/accounts.ex` — matches
- `grep 'def build_verify_code' lib/foglet_bbs/accounts/user_token.ex` — matches
- `grep '"registration_mode"' priv/repo/seeds.exs` — matches, value "open"
- `mix test` — 149 passing, 84 excluded, 0 failures
- `mix precommit` — exits 0
