---
phase: 46-domain-cleanup-and-final-quality-gate
reviewed: 2026-04-29T23:10:00Z
depth: standard
files_reviewed: 8
files_reviewed_list:
  - .dialyzer_ignore.exs
  - lib/foglet_bbs/boards/server.ex
  - lib/foglet_bbs/boards/supervisor.ex
  - lib/foglet_bbs/tui/screens/login.ex
  - lib/foglet_bbs/tui/screens/login/state.ex
  - lib/foglet_bbs/tui/screens/register/state.ex
  - lib/foglet_bbs/tui/screens/verify/state.ex
  - lib/foglet_bbs/tui/size_gate.ex
findings:
  blocker: 0
  warning: 0
  info: 0
  total: 0
status: clean
iteration: 2
---

# Phase 46: Code Review Report (Re-review)

**Reviewed:** 2026-04-29T23:10:00Z
**Depth:** standard
**Files Reviewed:** 8
**Status:** clean
**Iteration:** 2 (re-review of fixes from `46-REVIEW-FIX.md`)

## Summary

Re-review of Phase 46 after the six findings from iteration 1
(3 Warning + 3 Info) were addressed across commits `e3f6d61c..2f23461f`.
All fixes hold up under inspection, and no new defects were introduced.

The submitted file set is documentation-and-rationale heavy: five of the
six fixes are pure comment/typespec edits; one (IN-03) is a small
behavioural change in a render-time fallback string. Each fix was
verified in place against the source files.

## Verification of Iteration 1 Findings

### WR-01: `verify/state.ex` mutator `@spec` narrowing — FIXED

`record_invalid_attempt/3` (line 74) and `after_resend/2` (line 95) now
declare `t() -> t()` instead of `map() -> map()`. Both mutators return
`%{vs | ...}` updates which structurally preserve the input shape, so
`t()` is the correct contract. REVIEW-FIX records that both call sites
in `verify.ex` receive values from `VerifyState.get/1` (already typed
`t()`), so no Pitfall-1 plain-map caller pressure exists. No new
`:contract_supertype` skip required.

### WR-02: `.dialyzer_ignore.exs` Bucket A header — FIXED

Bucket A header (lines 5-11) renamed from "Ecto schema t/0 false
positives" to ":unknown_type false positives" and now explicitly
explains why `posts/reader_window.ex` is included (its `t/0` references
`Foglet.Posts.Post.t/0`, propagating the unresolved schema type into
its own spec surface). The "every entry has a stated reason" invariant
declared on line 2 now matches the file's contents.

### WR-03: `Boards.Server` `@dialyzer {:no_opaque, ...}` scope caveat — FIXED

A scope-caveat paragraph (`server.ex` lines 144-152) immediately above
the `@dialyzer` directive now enumerates the family-level tags that the
directive absorbs (`:opaque_match`, `:opaque_neq`, `:opaque_size`) and
instructs the next maintainer to re-run dialyzer with the directive
removed before re-applying it if a future edit adds a pattern-match or
comparison against `Ecto.Multi` internals. The directive itself is
unchanged; REVIEW-FIX correctly notes that tag-scoped `:no_opaque` was
not chosen for OTP-compatibility reasons.

### IN-01: `Login.focused_input/1` `:handle` default coupling — FIXED

A multi-line comment (`login.ex` lines 342-349) above `focused_input/1`
documents the implicit constraint: `:handle` must remain a member of
`LoginState.focused_field()` because `LoginState.get/1` may return `%{}`
(per IN-003), in which case `FocusInput.get_focused/3` falls back to
the default and invokes `LoginState.input_key(:handle)`. The comment
explicitly covers the matching default in `update_focused_input/2`
(line 358), so a future split of the focus atoms cannot quietly
desynchronise the two sites.

### IN-02: `boards/supervisor.ex` `start_board/1` doc disambiguation — FIXED

The `@doc` for `start_board/1` (lines 25-31) now fully qualifies both
the caller (`FogletBbs.Application.start/2`) and the canonical
implementation location (`lib/foglet_bbs/boards.ex`). A reader who has
just seen DOM-01 delete a same-named local helper can no longer
mistakenly think the doc refers to the deleted symbol.

### IN-03: `size_gate.render/1` "0×0" sentinel replaced with "unknown" — FIXED

The `case ... -> {0, 0}` fallback was replaced with a `size_text` string
(`size_gate.ex` lines 74-78) that interpolates `"C×R"` on the happy path
and yields the literal `"unknown"` on the defensive branch. Line 94
uses the new interpolation. The defensive comment (lines 67-73)
correctly explains why the branch is unreachable in production but kept
for unit-test ergonomics, and explicitly justifies the sentinel choice
("a stray screenshot of this output cannot be misread as a real
terminal-size detection bug"). REVIEW-FIX records the matching test
update at `size_gate_test.exs:105` and 17/17 size_gate tests pass.

## New Issues Introduced by Fixes

None. All six fixes are surgical: comment/typespec edits and one
literal-string change in a defensive render branch. No new control-flow
paths, no new public surface, no behavioural changes outside the
documented IN-03 user-visible string.

## Other Observations (Not Defects)

These are noted for context only; they are out of scope for this phase
and are not raised as findings:

- `register/state.ex` `get/1` returns `map() | nil` (line 71), whereas
  `login/state.ex` `get/1` returns `%{}` on miss (line 105). This
  asymmetry predates Phase 46 and is intentional per the IN-003 history
  documented in `login/state.ex` lines 95-103; any change would belong
  in a separate phase.
- The `boards/server.ex` Multi-step-label comments at lines 192 and 235
  ("Multi step labels `:post` / `:thread_update` are load-bearing")
  accurately mirror the `@moduledoc` invariant; no drift.
- The `@moduledoc` line-number references (lines 86-93 and 102-108) in
  `boards/server.ex` were already noted in iteration 1 as off by ~10
  lines from the post-edit positions; not material and not in this
  phase's scope to chase.

## Verification Confirmations from REVIEW-FIX

REVIEW-FIX reports `mix compile --warnings-as-errors` clean (only
pre-existing upstream raxol warnings), `mix dialyzer` at 59 errors / 59
skipped (identical to baseline; no regression from WR-01 narrowing),
and 17/17 size_gate tests passing. These match the expected outcomes
for the surgical changes inspected above.

---

_Reviewed: 2026-04-29T23:10:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
_Iteration: 2_
