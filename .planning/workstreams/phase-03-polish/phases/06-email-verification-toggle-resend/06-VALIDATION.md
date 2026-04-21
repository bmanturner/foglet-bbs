---
phase: 6
slug: email-verification-toggle-resend
workstream: phase-03-polish
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-04-20
---

# Phase 6 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution of Plans 06-01, 06-02, 06-03.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit (Elixir stdlib) |
| **Config file** | `mix.exs`, `test/test_helper.exs` |
| **Quick run command** | `mix test test/foglet_bbs/accounts/accounts_test.exs test/foglet_bbs/tui/screens/verify_test.exs test/foglet_bbs/tui/screens/login_test.exs test/foglet_bbs/tui/screens/register_test.exs` |
| **Full suite command** | `mix test` |
| **Estimated runtime** | ~15s quick, ~90s full |
| **DB setup** | `FogletBbs.DataCase` — Ecto sandbox per test, seeds NOT required (`Foglet.Config.get/2` fallback) |

---

## Sampling Rate

- **After every task commit:** Run the quick suite (four test files above).
- **After every plan wave:** Run `mix test` (full suite).
- **Before `/gsd-verify-work`:** Full suite green, `mix compile --warnings-as-errors` clean, `mix format --check-formatted` clean.
- **Max feedback latency:** ~15s quick, ~90s full.
- **No watch-mode flags.** `mix test.watch` is NOT part of this phase's validation contract.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------------|-----------|-------------------|-------------|--------|
| 6-01-01 | 01 | 1 | VERIFY-01 | Seed rows created idempotently; no privilege escalation | integration | `mix run priv/repo/seeds.exs` | ✅ | ⬜ pending |
| 6-01-02 | 01 | 1 | VERIFY-01 | `post_login_screen/1` defaults to `:verify` when config missing (safe posture) | unit | `mix test test/foglet_bbs/accounts/accounts_test.exs` | ✅ | ⬜ pending |
| 6-01-03 | 01 | 1 | VERIFY-01 | 4 unit tests for each branch of `post_login_screen/1` | unit | `mix test test/foglet_bbs/accounts/accounts_test.exs` | ✅ | ⬜ pending |
| 6-02-01 | 02 | 2 | VERIFY-01 | `login.ex` routes through `post_login_screen/1`; `Mix.env() != :prod` wraps `Logger.info` | unit + integration | `mix test test/foglet_bbs/tui/screens/login_test.exs` | ✅ | ⬜ pending |
| 6-02-02 | 02 | 2 | VERIFY-01 | `register.ex` routes through `post_login_screen/1`; same Mix.env guard | unit + integration | `mix test test/foglet_bbs/tui/screens/register_test.exs` | ✅ | ⬜ pending |
| 6-02-03 | 02 | 2 | VERIFY-01 | 3 login_test tests (toggle=true, toggle=false, confirmed invariance) | unit | `mix test test/foglet_bbs/tui/screens/login_test.exs` | ✅ | ⬜ pending |
| 6-02-04 | 02 | 2 | VERIFY-01 | 2 register_test tests (toggle=true, toggle=false) OR documented blocker | unit | `mix test test/foglet_bbs/tui/screens/register_test.exs` | ✅ | ⬜ pending |
| 6-03-01 | 03 | 3 | VERIFY-02 | `resend_cooldown_until` added at 6+ init sites; schema consistency | unit | `mix test test/foglet_bbs/tui/screens/verify_test.exs` | ✅ | ⬜ pending |
| 6-03-02 | 03 | 3 | VERIFY-02 | `cooldown_modal/2` takes DateTime + prefix; `resend_cooldown?/1` predicate exists | unit | `mix test test/foglet_bbs/tui/screens/verify_test.exs` | ✅ | ⬜ pending |
| 6-03-03 | 03 | 3 | VERIFY-02 | Config-driven resend duration; `Foglet.Config.get/2` default = 60 | unit | `mix test test/foglet_bbs/tui/screens/verify_test.exs` | ✅ | ⬜ pending |
| 6-03-04 | 03 | 3 | VERIFY-02 | 5 verify_test tests for the two-timer model | unit | `mix test test/foglet_bbs/tui/screens/verify_test.exs` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

None — the four target test files already exist:
- `test/foglet_bbs/accounts/accounts_test.exs`
- `test/foglet_bbs/tui/screens/verify_test.exs`
- `test/foglet_bbs/tui/screens/login_test.exs`
- `test/foglet_bbs/tui/screens/register_test.exs`

Each new describe block is appended inside its existing file. No new fixtures, no new test helpers (except the two `build_*_state` helpers inside `login_test.exs` and `register_test.exs` respectively, and only if not already present).

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Sysop flipping `require_email_verification` from IEx is observed by the next login | VERIFY-01 | Automated test cannot simulate an IEx session against a running SSH daemon | (1) `iex -S mix phx.server`, (2) `Foglet.Config.put!("require_email_verification", false)`, (3) SSH in as an unconfirmed user, (4) observe `:main_menu` lands (no verify). |
| Dev-mode code logging visible in `mix phx.server` stdout; absent in a `:prod` release | VERIFY-02 | Manual inspection of compiled release artifacts | (1) `MIX_ENV=prod mix release`; (2) grep the `_build/prod/rel/*` bytecode for the literal string `[verify] code for`; (3) confirm zero matches. Dev mode: `mix phx.server` + register a new user, confirm the Logger.info line shows in stdout. |
| Verify screen visually shows resend cooldown feedback to the user | VERIFY-02 | Terminal visual rendering | SSH in, route to verify, press R twice quickly — second press should show a red "Please wait Ns to resend." modal. |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify via `mix test ...` commands OR are documented manual-only with a clear trigger.
- [x] Sampling continuity: no 3 consecutive tasks without automated verify.
- [x] Wave 0 covers all MISSING references (Wave 0 is empty — no missing references).
- [x] No watch-mode flags.
- [x] Feedback latency: ~15s quick, ~90s full. Well under any reasonable ceiling.
- [x] `nyquist_compliant: true` set in frontmatter.

**Approval:** pending (to be set by `/gsd-verify-work` after Phase 6 execution).
