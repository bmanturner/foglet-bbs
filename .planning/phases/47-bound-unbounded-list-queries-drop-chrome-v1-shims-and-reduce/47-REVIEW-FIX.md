---
phase: 47-bound-unbounded-list-queries-drop-chrome-v1-shims-and-reduce
fixed_at: 2026-04-30T15:31:47Z
review_path: .planning/phases/47-bound-unbounded-list-queries-drop-chrome-v1-shims-and-reduce/47-REVIEW.md
iteration: 6
findings_in_scope: 6
fixed: 5
skipped: 1
status: partial
---

# Phase 47: Code Review Fix Report (Iteration 6)

**Fixed at:** 2026-04-30T15:31:47Z
**Source review:** `.planning/phases/47-bound-unbounded-list-queries-drop-chrome-v1-shims-and-reduce/47-REVIEW.md`
**Iteration:** 6

**Summary:**
- Findings in scope: 6 (0 critical, 3 warning, 3 info — `--all` scope)
- Fixed: 5
- Skipped: 1 (IN-03, explicitly no-action per reviewer)

`rtk mix precommit` (compile --warnings-as-errors, deps.unlock --unused,
format, credo --strict, sobelow --exit Low, dialyzer) passed clean after
the full fix set landed. `rtk mix test test/foglet_bbs/tui/screens`
reports 761 tests, 0 failures.

## Fixed Issues

### WR-01: `LoginForm.login_success_result/3` non-exhaustive case on `deliver_verification_code/1`

**Files modified:** `lib/foglet_bbs/tui/screens/login/login_form.ex`
**Commit:** 8e246862
**Applied fix:** Added a logged catch-all clause (`other ->`) to the
`case verification_mod.deliver_verification_code(user) do` block in
`login_success_result/3`. Mirrors the existing `authenticate_login/5`
defensive `else` branch a few lines above and the iteration-5 Register
WR-01 fix. Unanticipated success/error shapes now log a `Logger.warning`
breadcrumb and degrade to `:delivery_failed` (closest existing
semantic) instead of raising `CaseClauseError` and getting silently
re-categorized as a transient "temporarily unavailable" fault.

### WR-02: `Verify.handle_verify_resend_result/2` and `handle_verify_submit_result/3` non-exhaustive on success shapes

**Files modified:** `lib/foglet_bbs/tui/screens/verify.ex`
**Commit:** acb00082
**Applied fix:** Two catch-all clauses added:

1. `handle_verify_resend_result({:ok, _other}, vs)` — degrades to the
   optimistic `:attempted` modal so a future
   `{:ok, :queued}` (or any non-`:attempted` ok shape) does not raise
   `FunctionClauseError` out of the screen reducer (which has no
   `{:task_error, …}` fallback wired for `:verify_resend`).
2. `handle_verify_submit_result(other, vs, %Context{})` — degrades to
   the generic verification-failed modal so a future contract change
   to `verify_email_code/2` (e.g. `{:ok, user, meta}`) does not crash
   the reducer.

Both paths log a `Logger.warning` breadcrumb so the contract drift is
visible in logs.

### WR-03: `ResetRequest.dispatch_reset_request/3` non-exhaustive on `Foglet.Config.delivery_mode/0`

**Files modified:** `lib/foglet_bbs/tui/screens/login/reset_request.ex`
**Commit:** d1330db0
**Applied fix:** Added a logged catch-all (`other ->`) to the
`case Foglet.Config.delivery_mode() do` block. Falls back to the
no-email operator-assisted path so an unknown mode (typo'd config
value, future variant, schema migration) no longer raises
`CaseClauseError` and gets surfaced via the misleading
`@reset_invalid_email_message` modal that tells the user their email
is malformed when the actual fault is server delivery-mode
misconfiguration.

### IN-01: `Moderation.jump_hint/1` has no fallback clause for `n <= 0`

**Files modified:** `lib/foglet_bbs/tui/screens/moderation.ex`
**Commit:** 196f19dd
**Applied fix:** Added `defp jump_hint(_), do: "1"` as a fallback
clause. Restores the contract assumed by the iteration-3 IN-03 defense
in `tab_labels_from_tabs/1` (which returns `[]` on a malformed
`%Tabs{}` struct). Without this fallback, `length([]) = 0` would crash
`jump_hint(0)` with `FunctionClauseError`, defeating the upstream
defense.

### IN-02: `Account.Render.jump_hint/1` has the same `n <= 0` gap

**Files modified:** `lib/foglet_bbs/tui/screens/account/render.ex`
**Commit:** 332802e5
**Applied fix:** Same shape as IN-01. Added `defp jump_hint(_), do: "1"`
fallback so a transient `[]` from `tab_labels(ss)` (e.g., during tab
re-init) does not crash the account screen render. The optional
`Map.get(&1, :label, "?")` hardening of `tab_labels/1` was not applied
— the immediate `FunctionClauseError` defect is resolved without it,
and changing `Map.fetch!` semantics warrants a separate review.

## Skipped Issues

### IN-03: `PostReader.apply_flush_result/4` clears no pointer state on partial failure

**File:** `lib/foglet_bbs/tui/screens/post_reader.ex:522-539`
**Reason:** Reviewer explicitly classified this as "No change required
for Phase 47" — it is tracked so the partial-success cleanup is a
deliberate decision rather than an oversight. The current "retry both"
behavior is safe given the monotonic-merge contract on
`Boards.advance_board_read_pointer/3`, and the reviewer flagged any
per-side atomic split as a Phase 48+ optimization.
**Original issue:** When `board_result` succeeds and `thread_result`
fails, the next retry re-attempts the (already-successful) board
flush. Idempotent and safe, but wasteful until the thread flush
eventually succeeds.

---

_Fixed: 2026-04-30T15:31:47Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 6_
