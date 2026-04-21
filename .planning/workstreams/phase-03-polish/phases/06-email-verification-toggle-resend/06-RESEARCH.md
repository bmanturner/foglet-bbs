---
phase: 6
slug: email-verification-toggle-resend
workstream: phase-03-polish
status: complete
confidence: HIGH
generated: 2026-04-20
---

# Phase 6 — Research: Email Verification Toggle + Resend

> Every factual claim is tagged `[VERIFIED: codebase grep]`, `[CITED: <source>]`, or `[ASSUMED]`.
> CONTEXT.md is the constraint. This research confirms feasibility and surfaces pitfalls the planner must respect.

---

## 1. Scope Summary (from CONTEXT.md)

- **VERIFY-01:** Sysop config key `require_email_verification` (boolean, default `true`). When false, new registrations bypass `:verify` and existing `confirmed_at: nil` users land on `:main_menu` on next login. No DB migration; runtime-only bypass.
- **VERIFY-02:** Split resend cooldown from invalid-attempts cooldown. New `resend_cooldown_until` field on `verify_state`, new config key `email_verify_resend_cooldown_seconds` (integer, default `60`). Gate dev code logging on `Mix.env() != :prod`.

No new runtime dependencies. All work lands in three pre-existing files plus one Accounts function, with `priv/repo/seeds.exs` and three test files updated.

---

## 2. Standard Stack Confirmation

| Concern | Existing API | Status |
|---------|--------------|--------|
| Config read/write | `Foglet.Config.get!/1`, `Foglet.Config.put!/3`, ETS-backed cache | `[VERIFIED: lib/foglet_bbs/config.ex:44-100]` — no changes needed |
| Config seeding | Tuple-list pattern in `priv/repo/seeds.exs:43-49` | `[VERIFIED: priv/repo/seeds.exs:43]` — Phase 4 precedent (`max_post_length`) |
| Email verify code lifecycle | `Accounts.build_verify_code/1`, `Accounts.verify_email_code/2` | `[VERIFIED: lib/foglet_bbs/accounts.ex:161, 179]` — no changes needed |
| Session promotion | `{:promote_session, user}` command handled by `App.do_update/2` → sets `current_screen: :main_menu` | `[VERIFIED: lib/foglet_bbs/tui/app.ex:498-504]` |
| Verify state shape | `%{buffer, attempts, cooldown_until}` initialised at 6 call sites | `[VERIFIED: lib/foglet_bbs/tui/screens/verify.ex:23, 58, 74, 99, 140, 186, 202]` — all six must gain `resend_cooldown_until: nil` |

---

## 3. Key Pitfalls and How to Avoid Them

### Pitfall 1 — `Mix.env()` in a release

`Mix.env/0` is a compile-time function; at runtime in a release (`mix release`), `Mix` is not loaded and the call raises `UndefinedFunctionError`.

**Why Phase 6 is safe:** Elixir resolves `Mix.env()` at **compile time** when wrapped in `if Mix.env() != :prod do ... end`. In a `:prod` compile, the expression becomes `if :prod != :prod do ... end` → `if false do ... end`, and the compiler dead-codes the branch. No runtime `Mix` call survives. `[CITED: https://hexdocs.pm/mix/Mix.html#env/0]`

**Alternative considered:** `Application.compile_env(:foglet_bbs, :env)` with `config :foglet_bbs, :env, Mix.env()` in `config/config.exs`. More ceremony, same effect. Rejected for Phase 6 to minimize surface area. `[ASSUMED]` — the team may revisit when the release config hardens in a later milestone.

### Pitfall 2 — `Foglet.Config.get!/1` raises on missing key

The seed migration guarantees the key exists in a freshly seeded DB. But a stale test DB (seeds not rerun after checkout) raises `Ecto.NoResultsError`.

**Mitigation:** Use `Foglet.Config.get/2` with an explicit default in `Accounts.post_login_screen/1`:
```elixir
Foglet.Config.get("require_email_verification", true)
```
This matches CONTEXT.md "Claude's Discretion" — the planner decides per-testability. `[VERIFIED: lib/foglet_bbs/config.ex:63-68]` — `get/2` already exists and falls back to `default` when the DB row is missing.

### Pitfall 3 — Resend cooldown modal using the wrong field

`cooldown_modal/1` at `verify.ex:129-132` currently reads `vs.cooldown_until` directly. If the planner naively reuses it for the resend path, a user who hit invalid-attempts cooldown would see their resend path blocked by the invalid-attempts cooldown — violating D-10's "two independent timers."

**Mitigation:** Extract a `cooldown_modal/2` variant that takes a DateTime (not a verify_state) and a message prefix. The callers pass `vs.cooldown_until` or `vs.resend_cooldown_until` explicitly. `[VERIFIED: lib/foglet_bbs/tui/screens/verify.ex:129-132]`

### Pitfall 4 — Six verify_state initialisation sites, easy to miss one

`verify_state` is constructed or reset at:
- `verify.ex:23` — `render/1` default
- `verify.ex:58` — `handle_key(:backspace, ...)` default
- `verify.ex:74` — `handle_key(:char, ...)` default
- `verify.ex:99` — `handle_verify_event({:set_buffer, ...}, ...)` default
- `verify.ex:140` — `submit_raw/1` default
- `verify.ex:186` — `resend_code/1` default
- `verify.ex:202` — `resend_code_raw/1` default/reset (sets `cooldown_until: nil`)

Plus two external sites:
- `login.ex:283` — new verify_state on first route to `:verify`
- `register.ex:249` — new verify_state on first route to `:verify`

**Mitigation:** Every default map MUST include `resend_cooldown_until: nil`. The planner's Task 3 (verify.ex) and Task 2 (login/register) each list the exact line numbers. A grep acceptance criterion (`grep -c 'cooldown_until: nil' verify.ex` = at least 7 after change) guards against a miss.

`[VERIFIED: codebase grep]` — all sites enumerated by reading the three files end-to-end.

### Pitfall 5 — `DateTime.diff/3` returning negative values

`DateTime.diff(future, now, :second)` returns a negative integer if `future` is in the past (the cooldown has expired but the field hasn't been cleared). The existing `cooldown_modal/1` already guards with `max(remaining, 0)` at line 131. The planner must preserve this guard in the extracted `cooldown_modal/2`. `[VERIFIED: verify.ex:130-131]`

### Pitfall 6 — Resend cooldown clearing invalid-attempts cooldown

Current `resend_code_raw/1` (verify.ex:203) resets `cooldown_until: nil` as part of its success path. Per D-10 "two independent timers," this wipes a legitimate invalid-attempts cooldown when a user resends.

**Options:**
- (A) Preserve current behavior: successful resend clears BOTH `attempts`, `buffer`, and `cooldown_until` (invalid-attempts). Intuition: "successful resend = clean slate."
- (B) Only clear `attempts` and `buffer`, leave `cooldown_until` intact. Intuition: "cooldowns are independent; resend shouldn't bypass a lockout."

**CONTEXT.md D-09 says:** "Continue to clear `buffer`, `attempts`, and `cooldown_until` (the invalid-attempts cooldown) on successful resend — this matches current behavior." → **Option A is locked.** The planner must NOT silently switch to Option B.

`[VERIFIED: CONTEXT.md D-09]` — Option A is locked; planner preserves the semantics the user expects.

### Pitfall 7 — ETS cache staleness after config flip

`Foglet.Config.put!/3` invalidates the ETS cache for the specific key. A sysop flipping `require_email_verification` via `put!/3` from IEx or a Mix task will be seen by the next `get!/1` call. No polling or subscription needed. `[VERIFIED: lib/foglet_bbs/config.ex:98]`

### Pitfall 8 — Race between register_user and Accounts.post_login_screen

After `Accounts.register_user/1` returns `{:ok, user}`, the user struct has `confirmed_at: nil` (registration_changeset doesn't set it). Calling `post_login_screen(user)` immediately returns `:main_menu` iff `require_email_verification` is false. No race; the new user row is already committed by `Repo.insert/1`. `[VERIFIED: lib/foglet_bbs/accounts.ex:43-58]`

---

## 4. Test Strategy

### Unit tests (fast, async: true where possible)

| Module | Coverage | File |
|--------|----------|------|
| `Foglet.Accounts` | `post_login_screen/1` — 4 cases: confirmed user, unconfirmed + toggle=true, unconfirmed + toggle=false, missing config key falls back to default `true` | `test/foglet_bbs/accounts/accounts_test.exs` |
| `Foglet.TUI.Screens.Verify` | `resend_cooldown_until` initialization, `resend_cooldown?/1`, resend cooldown modal, two-independent-timers property | `test/foglet_bbs/tui/screens/verify_test.exs` |

### Integration tests (async: false — flip config)

| Scenario | Assertion | File |
|----------|-----------|------|
| Register with toggle=true | user lands on `:verify`, verify_state populated, verify code built | `test/foglet_bbs/tui/screens/register_test.exs` |
| Register with toggle=false | user lands on `:main_menu` (no verify_state built, no Logger.info) | same |
| Login unconfirmed + toggle=true | routes to `:verify` (existing behavior preserved) | `test/foglet_bbs/tui/screens/login_test.exs` |
| Login unconfirmed + toggle=false | routes to `:main_menu` via `{:promote_session, user}` | same |
| Login confirmed + toggle=true or false | always `:main_menu` (no config read side effect) | same |

**Test fixtures:** `test/support/` should expose a `put_config/2` helper that uses `Foglet.Config.put!/3` and ensures cleanup in `on_exit`. If not present, inline `Foglet.Config.put!("require_email_verification", true)` in the test setup and `on_exit` restore. `[VERIFIED: no `put_config` helper found — inline usage is fine for Phase 6]`

### Test isolation caveat — ETS cache

`Foglet.Config` uses a public named ETS table. Flipping a config key in test A and not cleaning up in `on_exit` leaks state to test B. Use `async: false` for config-mutating tests and always `on_exit(fn -> Foglet.Config.put!("key", original_value) end)`. `[VERIFIED: lib/foglet_bbs/config.ex:20, 77-100]`

---

## 5. Validation Architecture (Nyquist)

### Test Infrastructure

| Property | Value |
|----------|-------|
| Framework | ExUnit (Elixir stdlib) |
| Config file | `mix.exs` + `test/test_helper.exs` |
| Quick run | `mix test test/foglet_bbs/accounts/accounts_test.exs test/foglet_bbs/tui/screens/verify_test.exs` |
| Full suite | `mix test` |
| Estimated runtime | ~15s quick, ~90s full |

### Sampling Rate

- After every task commit: run the quick suite above
- After every plan wave: run `mix test` (full)
- Before `/gsd-verify-work`: full suite green, `mix format --check-formatted` clean, `mix compile --warnings-as-errors` clean
- Max feedback latency: ~15s quick, ~90s full

### Wave 0 Requirements

None. The three test files (`accounts_test.exs`, `verify_test.exs`, `login_test.exs`, `register_test.exs`) already exist; Phase 6 adds tests to existing `describe` blocks or appends new ones. `[VERIFIED: test/foglet_bbs/ dir listing]`

---

## 6. Project Constraints (from CLAUDE.md)

Extracted from `./CLAUDE.md`:
- `mix precommit` must pass before calling the phase done.
- Elixir lists do not support index access — use `Enum.at/2` or pattern match. (Not relevant to Phase 6 — no list indexing planned.)
- Structs do not implement Access — use `struct.field` or `Ecto.Changeset.get_field/2`. The verify_state is a plain map, so `Map.get/3` and `%{vs | field: value}` are correct.
- `String.to_atom/1` on user input is forbidden. (Not relevant — no user-input atomization.)
- Predicate function names end in `?` and do NOT start with `is_`. → **`resend_cooldown?/1`** is the correct name (mirrors existing `cooldown?/1`). NOT `is_resend_cooldown_active/1`.
- Phoenix 1.8 Layouts / Flash conventions. (Not relevant — Phase 6 is TUI-only, no LiveView or controller changes.)
- `start_supervised!/1` for processes in tests. (Not relevant — Phase 6 has no new processes.)
- Avoid `Process.sleep/1`. (Relevant: cooldown tests must set `DateTime` values directly, not wait.)
- `Req` for HTTP. (Not relevant — no HTTP calls.)

All Phase 6 changes honor these constraints.

---

## 7. Canonical Refs (from CONTEXT.md, expanded)

The planner and executor MUST read these before planning/implementing.

### Existing code (modified)
- `lib/foglet_bbs/accounts.ex:1-322` — full file; `post_login_screen/1` adds near `confirm_user/1` at line 150
- `lib/foglet_bbs/tui/screens/login.ex:267-313` — `submit_login/1` is refactored at lines 272-284
- `lib/foglet_bbs/tui/screens/register.ex:236-258` — `submit/2` is refactored at lines 238-252
- `lib/foglet_bbs/tui/screens/verify.ex:1-211` — full file; six verify_state sites + resend path updated
- `priv/repo/seeds.exs:43-49` — `default_config` tuple list

### Existing code (read-only)
- `lib/foglet_bbs/config.ex` — API already stable
- `lib/foglet_bbs/tui/app.ex:498-504` — `{:promote_session, _}` handler sets `current_screen: :main_menu`
- `lib/foglet_bbs/accounts/user.ex` — `confirmed_at` field

### Tests (modified or extended)
- `test/foglet_bbs/accounts/accounts_test.exs` — append `post_login_screen/1` describe block
- `test/foglet_bbs/tui/screens/verify_test.exs` — extend resend describe block; add resend_cooldown_until cases
- `test/foglet_bbs/tui/screens/login_test.exs` — add toggle=false branch
- `test/foglet_bbs/tui/screens/register_test.exs` — add toggle=false branch

---

## 8. Open Questions / Planner's Discretion

1. **Post-register UX when toggle=false** — land on plain `:main_menu` (no welcome modal) vs a brief "Welcome, @handle" modal. **Recommendation: plain `:main_menu` for Phase 6 simplicity.** A welcome modal can be added when post-login presence work in Milestone 4 reshapes the `:main_menu` entry anyway. `[ASSUMED]` — planner has discretion per CONTEXT.md.
2. **`Foglet.Config.get!/1` vs `get/2`** — recommend `get/2` with explicit default `true` for `require_email_verification` and `60` for `email_verify_resend_cooldown_seconds`, for test robustness. Seeds guarantee presence in prod; defaults avoid brittle test setup. `[ASSUMED]` — planner's call.
3. **Shared `cooldown_modal/2` location** — keep in `verify.ex` (private). Not worth promoting to `Foglet.TUI.Widgets.Compose` (Phase 4's widget) because Compose has no cooldown concept. `[ASSUMED]`

## RESEARCH COMPLETE
