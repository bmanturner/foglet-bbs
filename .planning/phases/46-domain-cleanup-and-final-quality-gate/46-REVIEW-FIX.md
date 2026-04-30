---
phase: 46-domain-cleanup-and-final-quality-gate
fixed_at: 2026-04-29T22:55:00Z
review_path: .planning/phases/46-domain-cleanup-and-final-quality-gate/46-REVIEW.md
iteration: 1
findings_in_scope: 6
fixed: 6
skipped: 0
status: all_fixed
---

# Phase 46: Code Review Fix Report

**Fixed at:** 2026-04-29T22:55:00Z
**Source review:** `.planning/phases/46-domain-cleanup-and-final-quality-gate/46-REVIEW.md`
**Iteration:** 1

**Summary:**
- Findings in scope: 6 (3 Warning + 3 Info, fix_scope=all)
- Fixed: 6
- Skipped: 0

All findings applied. Verified with `mix compile --warnings-as-errors`,
`mix dialyzer` (59 errors / 59 skipped — same as baseline; no regressions),
and `mix test test/foglet_bbs/tui/size_gate_test.exs` (17/17 passing).

## Fixed Issues

### WR-01: `verify/state.ex` `t()` narrowing is half-applied — mutator specs still take/return `map()`

**Files modified:** `lib/foglet_bbs/tui/screens/verify/state.ex`
**Commit:** `e3f6d61c`
**Applied fix:** Narrowed `record_invalid_attempt/3` and `after_resend/2`
specs from `map()` to `t()` for both arg and return. Verified that both
call sites in `verify.ex:216` and `verify.ex:241` pass values originating
from `VerifyState.get/1` (already typed `t()`), so no Pitfall-1 plain-map
caller pressure exists. Dialyzer reports no new `:contract_supertype` or
other warnings post-edit (Bucket C* `:contract_supertype` skip count
unchanged at baseline).

### WR-02: `.dialyzer_ignore.exs` Bucket A comment misrepresents what it covers

**Files modified:** `.dialyzer_ignore.exs`
**Commit:** `a3603167`
**Applied fix:** Renamed Bucket A header from "Ecto schema t/0 false
positives" to "`:unknown_type` false positives" and added explicit prose
covering the `posts/reader_window.ex` member (its `t/0` references
`Foglet.Posts.Post.t/0`, propagating the unresolved schema type into
reader_window's spec surface). The "stated reason" invariant now matches
reality. Verified ignore file parses (`elixir -e Code.eval_file/1`).

### WR-03: `Boards.Server.@dialyzer {:no_opaque, ...}` directive masks all `:no_opaque` family warnings, not just `:call_without_opaque`

**Files modified:** `lib/foglet_bbs/boards/server.ex`
**Commit:** `a3b4a3ef`
**Applied fix:** Chose option 2 from REVIEW.md (rationale rewrite). Added
a "Scope caveat" paragraph above the `@dialyzer` directive explicitly
naming the family-level tags absorbed (`:opaque_match`, `:opaque_neq`,
`:opaque_size`) and instructing the next maintainer to re-run dialyzer
without the directive before re-applying it if they introduce a new
pattern-match or comparison against `Ecto.Multi` internals. The directive
itself is unchanged — option 1 (tag-scoped form) was rejected as
conservative because OTP version compatibility for tag-scoped `:no_opaque`
is not verified in this environment.

### IN-01: `Login.focused_input/1` default-field hardcode couples to `LoginState.input_key/1` happening to accept `:handle`

**Files modified:** `lib/foglet_bbs/tui/screens/login.ex`
**Commit:** `ccf3e547`
**Applied fix:** Picked the documentation option (cheaper, behaviour
unchanged). Added a multi-line comment immediately above
`focused_input/1` explaining the implicit constraint: `:handle` must
remain a member of `LoginState.focused_field()` because
`LoginState.get/1` may return `%{}` (per the IN-003 commitment), in which
case `FocusInput.get_focused/3` falls back to `:handle` and invokes
`input_key(:handle)`. The matching default in `update_focused_input/2`
is also covered by the comment.

### IN-02: `boards/supervisor.ex:28` doc comment still references the deleted helper as the call mechanism

**Files modified:** `lib/foglet_bbs/boards/supervisor.ex`
**Commit:** `1924eb0d`
**Applied fix:** Rewrote the `@doc` for `start_board/1` to fully qualify
both the caller (`FogletBbs.Application.start/2`) and the canonical
implementation location (`lib/foglet_bbs/boards.ex`). A reader who has
just seen DOM-01 delete a same-named local helper can no longer
mistakenly think the doc refers to the deleted symbol.

### IN-03: `size_gate.render/1` defensive `_ -> {0, 0}` fallback emits a "0×0" message that misleads users

**Files modified:** `lib/foglet_bbs/tui/size_gate.ex`,
`test/foglet_bbs/tui/size_gate_test.exs`
**Commit:** `2f23461f`
**Applied fix:** Replaced the `{cols, rows} = case ... -> {0, 0} end`
fallback with a `size_text` string that interpolates "C×R" on the happy
path and yields the literal `"unknown"` on the defensive branch. Updated
the rendered line to `"Your terminal is currently: #{size_text}."` and
updated the matching unit test (`size_gate_test.exs:105`) to assert on
`"unknown"` instead of `"0×0"`. All 17 size_gate tests pass.

## Verification Notes

- `mix compile --warnings-as-errors`: clean (only pre-existing Mogrify
  and Benchee.Formatter warnings from upstream raxol, unrelated to this
  phase).
- `mix dialyzer`: 59 errors, 59 skipped, 3 unnecessary skips. Identical
  to baseline before fixes. The WR-01 `t()` narrowing in
  `verify/state.ex` did not introduce any new `:contract_supertype`
  warning (Bucket C* `verify/state.ex` skip remains in place and matches
  pre-existing `:contract_supertype` from the multi-shape state map per
  46-CONTEXT D-03).
- `mix test test/foglet_bbs/tui/size_gate_test.exs`: 17/17 passing.

---

_Fixed: 2026-04-29T22:55:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
