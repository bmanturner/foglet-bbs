# Phase 6: Email verification toggle + resend — Context

**Gathered:** 2026-04-20
**Status:** Ready for planning
**Workstream:** phase-03-polish (v1.0.1)

<domain>
## Phase Boundary

Two orthogonal polish items on the existing email-verification flow:

1. **VERIFY-01** — Sysop can disable email verification site-wide via `Foglet.Config`. When disabled, new registrations skip the verify step entirely and existing `confirmed_at: nil` users gain access on next login (retroactive bypass, no DB migration).
2. **VERIFY-02** — The Verify screen's existing "Resend code" key hint is already wired; polish it by separating resend cooldown from the invalid-attempts cooldown, making resend cooldown duration config-tunable, and gating dev-mode code logging on non-prod Mix env.

**In scope:**
- Two new `Foglet.Config` keys: `require_email_verification` (bool, default `true`) and `email_verify_resend_cooldown_seconds` (integer, default `60`). Seeded via `priv/repo/seeds.exs`.
- New `Foglet.Accounts.post_login_screen/1` function returning `:main_menu | :verify`.
- `register.ex` and `login.ex` route via `Accounts.post_login_screen/1` instead of inline `confirmed_at: nil` guards.
- `verify_state` gains `resend_cooldown_until` field independent of `cooldown_until`.
- Verify screen's `resend_code` path checks/sets only `resend_cooldown_until`, uses config-driven cooldown duration.
- `Logger.info("[verify] code for @...")` calls gated on `Mix.env() != :prod`.

**Explicitly NOT in scope:**
- Actual SMTP email delivery — deferred to Milestone 10 (Swoosh re-enable).
- Sysop in-TUI toggle screen for `require_email_verification` — deferred to Milestone 8.
- Tunable `max_attempts`, `cooldown_seconds`, `code_length` — keep as hardcoded module attrs.
- Retroactive DB migration for `confirmed_at: nil` users when toggle flips false — NOT done; the retroactive bypass is at the login-guard level only.
- Mid-session invalidation when toggle flips — config only affects new login/register flows.
- Email delivery hook seam for Phase 10 — out of scope; Phase 10 will refactor if needed.

**Dependencies:** Phase 1 (Verify screen already uses `ScreenFrame` and theme). No dependency on Phase 2, 3, 4, or 5. Can ship immediately after Phase 1 in theory; sequenced last in roadmap for minor-priority reasons.

</domain>

<decisions>
## Implementation Decisions

### Config keys

- **D-01:** New `Foglet.Config` key `require_email_verification`, type boolean, default `true`. Seeded via `priv/repo/seeds.exs` using the same tuple-list pattern as `max_post_length`: `{"require_email_verification", true, "When false, new registrations skip verify and existing confirmed_at: nil users gain access on login"}`.
- **D-02:** New `Foglet.Config` key `email_verify_resend_cooldown_seconds`, type integer, default `60`. Seeded: `{"email_verify_resend_cooldown_seconds", 60, "Minimum seconds between resend-code presses on the Verify screen"}`.
- **D-03:** Do NOT add config keys for `max_attempts`, `cooldown_seconds` (invalid-attempts), or `code_length`. These stay as module attrs `@max_attempts 5`, `@cooldown_seconds 60`, `@code_length 6` in `verify.ex`. Scope discipline.

### Retroactive bypass placement (Accounts context API)

- **D-04:** New function `Foglet.Accounts.post_login_screen(user) :: :main_menu | :verify`. Logic:
  - If `user.confirmed_at != nil` → `:main_menu`
  - If `Foglet.Config.get!("require_email_verification") == false` → `:main_menu`
  - Otherwise → `:verify`
- **D-05:** `login.ex:272-281` is refactored to call `Accounts.post_login_screen(user)` after `authenticate_by_password/2` succeeds. If the result is `:main_menu`, the existing `build_verify_code` + `Logger.info` + route-to-verify path is skipped entirely and the user lands on `:main_menu`. If `:verify`, current behavior is preserved.
- **D-06:** `register.ex:239-248` is refactored the same way. After `Accounts.register_user(attrs)` returns `{:ok, user}`, it calls `Accounts.post_login_screen(user)` to decide whether to build a verify code and route to `:verify`, or skip directly to `:main_menu`.
- **D-07:** Retroactive bypass is purely runtime: existing DB rows with `confirmed_at: nil` are NOT updated. When toggle is `false`, they bypass the login guard via `post_login_screen/1`. If toggle flips back to `true`, the same users are routed to verify on their next login (current behavior). This matches REQUIREMENTS' locked decision exactly.

### Resend cooldown model

- **D-08:** Verify screen `verify_state` gains a new field `resend_cooldown_until :: DateTime.t() | nil`, independent of the existing `cooldown_until` (which continues to track invalid-attempts cooldown only).
- **D-09:** `resend_code_raw/1` in `verify.ex:198-210`:
  - Before generating a new code: check `resend_cooldown_until` via a new helper `resend_cooldown?/1`. If active, return a modal `{type: :error, message: "Please wait Ns before requesting another code."}` and no-op.
  - After successfully generating a new code: set `resend_cooldown_until: DateTime.add(now, Foglet.Config.get!("email_verify_resend_cooldown_seconds"), :second)`.
  - Continue to clear `buffer`, `attempts`, and `cooldown_until` (the invalid-attempts cooldown) on successful resend — this matches current behavior.
- **D-10:** Invalid-attempts path at `verify.ex:167-180` is UNTOUCHED. It continues to set `cooldown_until` only. The resend path uses only `resend_cooldown_until`. Two independent timers.
- **D-11:** `handle_key` for "R"/"r" (`verify.ex:69`) — on cooldown hit, show modal with seconds remaining. Re-use the `cooldown_modal/1` message style but read from `resend_cooldown_until`. Planner may extract a shared helper `cooldown_modal/2` that takes a DateTime and a prefix message.

### Dev-mode code logging

- **D-12:** `Logger.info("[verify] code for @#{user.handle}: #{code}")` calls at `register.ex:241-242` and `login.ex:274-275` are wrapped in a `Mix.env() != :prod` check. In prod (including staging), no code is logged. In `:dev` / `:test`, logging continues as-is.
- **D-13:** When `require_email_verification == false`, no verify code is generated at register/login time (D-05, D-06) — so the Logger path is never hit. No explicit check needed in Phase 6; the short-circuit logic naturally avoids it.

### Live-toggle behavior

- **D-14:** `verify.ex/render/1` and `verify.ex/handle_key/2` do NOT re-check `require_email_verification`. A user already on the Verify screen when the sysop flips the config is NOT kicked off — their session flow completes normally (they can submit, resend, or Esc to login). Config affects only new login/register flows.
- **D-15:** No reverse-direction handling: if the sysop flips toggle from `false → true` while a user is on `:main_menu` (confirmed or bypassed), nothing happens. Config does not force re-verification of active sessions.

### Claude's Discretion

- **Post-register UX when toggle is false:** D-06 says register jumps to `:main_menu`. Planner may add a brief "Welcome, @handle" modal or land on a plain main_menu screen. Both are acceptable; REQUIREMENTS doesn't mandate a confirmation modal. The existing `register_success_modal/1` pattern (if any — verify by reading register.ex) can be reused or suppressed.
- **Shared cooldown modal helper:** D-11 suggests extracting `cooldown_modal/2`. Planner decides whether this lives in `verify.ex` or `Foglet.TUI.Widgets.Compose` (from Phase 4) — the latter would require Compose to grow a cooldown concept, which it doesn't today. Keeping it in `verify.ex` as `cooldown_modal/2` taking a DateTime + message prefix is simpler.
- **`Foglet.Config.get!` vs `get` + default:** The config seed guarantees the key exists after migration, so `get!` is safe. For test environments that bypass seeds, `get` with a default fallback may be more robust. Planner decides per testability.
- **Integration test coverage scope:** REQUIREMENTS doesn't specify test depth. Planner should include: (1) toggle=true existing-unconfirmed routes to verify, (2) toggle=false same user routes to main_menu, (3) toggle=false register skips verify, (4) resend cooldown fires after first press, (5) resend cooldown is independent of invalid-attempts cooldown (hit invalid 5x → can still resend; hit resend once → can still enter codes).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Workstream Requirements and Roadmap
- `.planning/workstreams/phase-03-polish/REQUIREMENTS.md` — VERIFY-01, VERIFY-02 requirements; locked decision (retroactive bypass via login guard only)
- `.planning/workstreams/phase-03-polish/ROADMAP.md` — Phase 6 success criteria; dependency on Phase 1

### Related Seed
- `.planning/seeds/SEED-002-email-verification-ux.md` — Original seed; breadcrumbs to existing code (`verify.ex:101,109`, `login.ex:273`, `register.ex:245`, `accounts.ex:156`)

### Research
- `.planning/workstreams/phase-03-polish/research/FEATURES.md` §10 — Email verification toggle analysis (Table stakes for polish); SMTP deferred to Milestone 10
- `.planning/workstreams/phase-03-polish/research/SUMMARY.md` — Confirmed retroactive-bypass policy

### Prior Phase Context
- `.planning/workstreams/phase-03-polish/phases/01-widget-foundation-theme-screen-chrome/01-CONTEXT.md` — Theme slots and ScreenFrame (already used by verify.ex)
- `.planning/workstreams/phase-03-polish/phases/04-composer-thread-creation-end-to-end/04-CONTEXT.md` — Config key seed pattern precedent (D-13 for `max_thread_title_length`; Phase 6 follows the same shape)

### Existing Code to Modify
- `lib/foglet_bbs/accounts.ex` — add `post_login_screen/1` (D-04); existing `build_verify_code/1` and `verify_email_code/2` unchanged
- `lib/foglet_bbs/tui/screens/login.ex` (line 272-281) — route via `post_login_screen/1` (D-05); wrap Logger.info in Mix.env guard (D-12)
- `lib/foglet_bbs/tui/screens/register.ex` (line 239-248) — route via `post_login_screen/1` (D-06); wrap Logger.info in Mix.env guard (D-12)
- `lib/foglet_bbs/tui/screens/verify.ex` — add `resend_cooldown_until` to verify_state initialisations (lines 23, 58, 74, 99, 140, 186, 202); new `resend_cooldown?/1` helper; `resend_code_raw/1` reads/writes only `resend_cooldown_until` (D-08..D-10); `cooldown_modal/2` variant (D-11)
- `priv/repo/seeds.exs` — add two new config seed tuples at line 48 region (D-01, D-02)

### Domain Code (read-only — NOT modified)
- `lib/foglet_bbs/accounts/user.ex:29` — `confirmed_at` field
- `lib/foglet_bbs/accounts/user.ex:93` — `confirm_changeset/1` (used by `verify_email_code/2`)
- `lib/foglet_bbs/accounts/user_token.ex:68-69` — `build_verify_code/1`
- `lib/foglet_bbs/config.ex` — `get!/1`, `put!/3` (existing API)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Foglet.Accounts.verify_email_code/2` and `Foglet.Accounts.build_verify_code/1` — already correct, no changes needed.
- Verify screen already has: `{"R", "Resend code"}` key hint (`verify.ex:47`), handler (`verify.ex:69`), cooldown logic (`verify.ex:123-132`), resend modal (`verify.ex:201`). Phase 6 refines this, doesn't rebuild it.
- `Foglet.Config.get!/1` — returns the seeded value; `put!/3` used for sysop tuning via `mix foglet.config.set` (or `iex`). Already exists.
- `priv/repo/seeds.exs:48` — exact precedent for seeding new config keys (`max_post_length` tuple). Phase 6 adds two new tuples to the same list.
- `register.ex` and `login.ex` both follow the same pattern: authenticate/register → `build_verify_code` → Logger.info → route to `:verify`. Both refactor identically via `post_login_screen/1`.

### Established Patterns
- Config keys are seeded as 3-tuples `{"key_name", default_value, "description"}` (see `priv/repo/seeds.exs:48`). New keys follow the same shape.
- `verify_state` shape is `%{buffer, attempts, cooldown_until}` — gaining one field `resend_cooldown_until` (D-08). All verify_state initialisations (6 sites in `verify.ex`) must include the new field.
- `%{type: :error | :info, message: "..."}` modal pattern — reused for resend-cooldown feedback (D-11).
- `Mix.env()` compile-time call — used in other places in the codebase per Elixir convention; wrap Logger.info in `if Mix.env() != :prod do ... end`.

### Integration Points
- `Foglet.Accounts` — add `post_login_screen/1` function; read `Foglet.Config.get!("require_email_verification")`
- `verify.ex:23, 58, 74, 99, 140, 186, 202` — all `verify_state` default/init sites; add `resend_cooldown_until: nil`
- `verify.ex:123-132` — extract or reuse `cooldown?/1` pattern for `resend_cooldown?/1`
- `login.ex:272-281` — route via `Accounts.post_login_screen/1`
- `register.ex:239-248` — route via `Accounts.post_login_screen/1`
- `priv/repo/seeds.exs:48` — add two new config seed tuples

### Scope Fencing Notes
- SMTP delivery is explicitly deferred (Milestone 10). "Resend" in Phase 6 = regenerate code and log to stdout in dev. No Swoosh, no Mailer, no templates.
- Sysop in-TUI toggle screen deferred to Milestone 8. v1.0.1 sysops use `mix foglet.config.set require_email_verification false` or `Foglet.Config.put!/3` from IEx.
- Retroactive bypass is LOGIN-GUARD ONLY. No DB-level retroactive confirm. This matches REQUIREMENTS' locked policy exactly and keeps the reverse direction (toggle back on) clean.

</code_context>

<specifics>
## Specific Ideas

- **Two independent cooldowns** (D-08..D-10) — user's mental model is: "invalid attempts = lock me out temporarily; resend = prevent me from spamming." These are different concerns with different durations.
- **`Foglet.Accounts.post_login_screen/1` name** — reads naturally at call sites: `case Accounts.post_login_screen(user), do: (:main_menu -> ... ; :verify -> ...)`. Clearer than `needs_verification?(user)` because it directly returns the target screen.
- **Dev logger gated on Mix.env()** — classic Elixir pattern, avoids leaking codes in prod. When SMTP lands in Milestone 10, the `Logger.info` line can be replaced with actual email delivery; until then, dev devs rely on server logs.
- **Live-toggle mid-session non-handling** (D-14, D-15) — explicit decision to keep session behavior simple. Config affects the entry points (login, register), not the session loop.

</specifics>

<deferred>
## Deferred Ideas

- **Actual SMTP email delivery via Swoosh** — Milestone 10.
- **Sysop in-TUI toggle screen** — Milestone 8 (`Sysop Administration In-TUI`).
- **Tunable `@max_attempts`, `@cooldown_seconds`, `@code_length`** — Deferred; not required by sysops today.
- **Post-register welcome modal when toggle is false** — Planner's discretion; not required by REQUIREMENTS.
- **Live-toggle mid-session invalidation** — Explicitly rejected (D-14, D-15).
- **Email delivery hook seam for Phase 10** — Out of scope; Milestone 10 will refactor if needed.
- **DB migration to retroactively confirm `confirmed_at: nil` users** — Rejected by locked decision; login-guard-only bypass preserves reversibility.
- **Resend-specific max-attempts limit** — Considered; rejected. Resend cooldown itself rate-limits.

</deferred>

---

*Phase: 06-email-verification-toggle-resend*
*Context gathered: 2026-04-20*
