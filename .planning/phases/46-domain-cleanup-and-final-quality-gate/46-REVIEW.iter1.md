---
phase: 46-domain-cleanup-and-final-quality-gate
reviewed: 2026-04-29T22:30:00Z
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
  warning: 3
  info: 3
  total: 6
status: issues_found
---

# Phase 46: Code Review Report

**Reviewed:** 2026-04-29T22:30:00Z
**Depth:** standard
**Files Reviewed:** 8
**Status:** issues_found (no blockers; warnings + info notes)

## Summary

Phase 46 scope is narrow and largely defensive: a stub deletion (DOM-01),
moduledoc additions (DOM-02), spec-narrowing on screen-state helpers, and
ignore-file restructuring (QUAL-01). I traced each surface against current
call sites and found no behavioural regressions and no new bugs introduced
by the phase's edits. There are no blockers.

What I did find: a handful of consistency, drift, and rationale-honesty
issues that the next maintainer would benefit from seeing. The most material
is that the `verify/state.ex` `@type t/0` introduction is only half-applied
— two mutators (`record_invalid_attempt/3`, `after_resend/2`) keep `map()`
specs even though their callers operate on `t()` values returned by
`get/1`. The dialyzer ignore file's per-file claims also don't fully match
which warnings are actually narrowed vs left broad.

I treat all findings below as "no-ship-blocker for v2.1, but worth
addressing before claiming the spec narrowing pass is complete."

## Warnings

### WR-01: `verify/state.ex` `t()` narrowing is half-applied — mutator specs still take/return `map()`

**File:** `lib/foglet_bbs/tui/screens/verify/state.ex:74-104`
**Issue:** Plan 46-03's stated goal for `verify/state.ex` was "introduce
`@type t/0`; narrow `default/0` → `t()`; `cooldown?/1`,
`resend_cooldown?/1` → `t()`; `put/2` second arg → `t()`." That is the
state of `default/0`, `get/1`, `put/2`, `cooldown?/1`, and
`resend_cooldown?/1`.

But `record_invalid_attempt/3` (line 74) and `after_resend/2` (line 95)
still declare:

```elixir
@spec record_invalid_attempt(map(), non_neg_integer(), non_neg_integer()) :: map()
@spec after_resend(map(), non_neg_integer()) :: map()
```

These are the only two mutators in the module that build a new state from
an existing one, and at every call site (`verify.ex:216`, `verify.ex:241`)
they receive a `vs` value that came directly from `VerifyState.get/1` —
which the new spec already promises to be `t()`. There is no Pitfall-1
"caller passes a plain map" pressure here; the callers are inside the
Verify screen reducer and only ever feed `t()` values.

This is the *inverse* of the plan-03 deviation note about
`register/state.ex` (where narrowing the state arg broke ~30 downstream
plain-map callers). Here narrowing is safe and the inconsistency just
makes the module's typing story confusing: `t()` for reads, `map()` for
writes.

**Fix:**
```elixir
@spec record_invalid_attempt(t(), non_neg_integer(), non_neg_integer()) :: t()
def record_invalid_attempt(vs, max_attempts, cooldown_seconds) do
  ...
end

@spec after_resend(t(), non_neg_integer()) :: t()
def after_resend(vs, cooldown_seconds) do
  ...
end
```

Both functions return a literal `%{vs | ...}` over a struct-shaped
`t()`-conformant map, so the return narrowing is sound. Run dialyzer
afterwards; if a `:contract_supertype` re-emerges (it shouldn't —
`vs.attempts + 1` produces a `non_neg_integer()` and the conditional
branch returns the same shape), revert just that one and document.

---

### WR-02: `.dialyzer_ignore.exs` Bucket A comment misrepresents what it covers

**File:** `.dialyzer_ignore.exs:5-11`
**Issue:** The Bucket A comment says:

```
# Bucket A — Ecto schema t/0 false positives.
# Dialyzer cannot resolve `t/0` from `use Ecto.Schema`; not a real bug.
```

But Bucket A includes `lib/foglet_bbs/posts/reader_window.ex`. That module
is not an Ecto schema — `46-03-SUMMARY.md` row says it was added to
Bucket A "(+ posts/reader_window.ex; was unsilenced)". The bucket header
claims a schema-shape rationale that doesn't apply to one of its members.

A reader doing the v2.1 close-pass invariant check ("every kept entry has
a stated reason in the shared comment block immediately above it") will
either (a) trust the header and miss the real reason for that one entry,
or (b) audit reader_window.ex and find the header is lying.

**Fix:** Either split Bucket A into "A1 — Ecto schemas" and "A2 — other
unknown_type" with an honest comment for the latter, or expand the Bucket
A header to acknowledge the non-schema member:

```
# Bucket A — :unknown_type false positives.
# Mostly Ecto schemas where dialyzer cannot resolve t/0 from
# `use Ecto.Schema`. reader_window.ex is included because <stated reason>.
```

The Phase 46 D-07 invariant explicitly commits to "every kept entry has a
stated reason"; "stated reason" should mean accurately stated.

---

### WR-03: `Boards.Server.@dialyzer {:no_opaque, ...}` directive masks all `:no_opaque` family warnings, not just `:call_without_opaque`

**File:** `lib/foglet_bbs/boards/server.ex:134-143`
**Issue:** The rationale comment correctly identifies the warning family
the directive is meant to silence — `:call_without_opaque` from
`Multi.new/0` flowing into a `Multi.t/0`-specced API. However, the
directive used is `{:no_opaque, ...}`, which silences the entire
`:no_opaque` warning class on those two functions. That class includes
`:opaque_match`, `:opaque_neq`, `:opaque_size`, etc. — not just
`:call_without_opaque`.

So if a future edit to `run_post_insert_multi/5` or
`run_thread_create_multi/4` introduces, say, a pattern-match against
`%Ecto.Multi{operations: [_ | _]}` (an `:opaque_match` violation that
*would* be a real bug), dialyzer will silently accept it.

The `46-03-SUMMARY.md` Bucket B writeup says the directive is "scoped
narrowly … so any future `:call_without_opaque` elsewhere in the module
remains observable" — which is true at the function-scope axis but not
at the warning-class axis. The rationale comment also implies a tighter
scope than the directive actually delivers.

**Fix:** Two options, in order of preference.

1. Use a tag-scoped directive if Erlang/Elixir supports it on the version
   in use (older OTPs only support the family-level tag). The closest
   stable tag is the family-level `:no_opaque`.

2. If only the family-level form is available, update the rationale
   comment to be honest about what is suppressed:

   ```
   # The :no_opaque family includes :call_without_opaque (the warning we
   # are silencing), :opaque_match, :opaque_neq, and :opaque_size.
   # Only :call_without_opaque fires here today. If you add a new
   # pattern-match or comparison against an Ecto.Multi internal field
   # inside these helpers, re-run dialyzer with this directive removed
   # before re-applying it — you may be silencing a real bug.
   ```

Either change keeps the v2.1 surface the same while making the trade-off
visible to the next maintainer. This is a doc-honesty issue, not a known
bug — the current bodies of both helpers don't pattern-match Multi
internals, so the over-suppression is latent.

## Info

### IN-01: `Login.focused_input/1` default-field hardcode couples to `LoginState.input_key/1` happening to accept `:handle`

**File:** `lib/foglet_bbs/tui/screens/login.ex:343`
**Issue:** `focused_input/1` calls
`FocusInput.get_focused(LoginState.get(state), &LoginState.input_key/1, :handle)`.
`FocusInput.get_focused/3` falls back to the third arg (`:handle`) when
`:focused_field` is absent and then invokes `mapper.(:handle)`. The new
narrow spec `input_key(focused_field()) :: input_field()` is exhaustive
over the documented atoms, and `:handle` is one of them, so no warning
fires today.

But this is a hidden constraint: if a future refactor removes `:handle`
from `focused_field` (e.g. login-form-only atoms get split into a
sibling state module), `input_key(:handle)` becomes a
`FunctionClauseError` on a code path the screen reducer enters whenever
it encounters a state with `:focused_field` missing. The
`LoginState.get/1` IN-003 commitment ("returns `%{}` rather than a
login-form-flavored stub") makes that path reachable.

**Fix:** Either pick a default that is invariant under future evolution
(e.g. always seed `:focused_field` in `LoginState.get/1` on the empty-map
fallback) or keep the hardcoded `:handle` and add a one-line comment at
the `&LoginState.input_key/1` call site noting the implicit assumption.
Low priority — current behaviour is correct.

---

### IN-02: `boards/supervisor.ex:28` doc comment still references the deleted helper as the call mechanism

**File:** `lib/foglet_bbs/boards/supervisor.ex:25-29`
**Issue:** The `@doc` for `start_board/1` reads:

> Called from Foglet.Boards context when a board is created, and from
> Application.start/2 (via Foglet.Boards.boot_board_servers/0) at boot.

This is technically correct (the real `Foglet.Boards.boot_board_servers/0`
in `lib/foglet_bbs/boards.ex:40` does call `start_board/1`), but a reader
who has just seen that DOM-01 deleted `boot_board_servers/0` from this
file may briefly think the doc is stale. The neighboring inline comment
at line 20-21 also mentions `boot_board_servers/0` "in Application.start/2"
which is correct but easily misread.

**Fix:** Disambiguate which `boot_board_servers/0` is meant — fully
qualify and clarify it lives in the context, not this file:

```
@doc """
Start a Board Server for the given board_id.
Called from `Foglet.Boards` context when a board is created, and at boot
from `FogletBbs.Application.start/2` via `Foglet.Boards.boot_board_servers/0`
(the canonical implementation in `lib/foglet_bbs/boards.ex`).
"""
```

This is purely documentation hygiene; behaviour is unchanged.

---

### IN-03: `size_gate.render/1` defensive `_ -> {0, 0}` fallback emits a "0×0" message that misleads users

**File:** `lib/foglet_bbs/tui/size_gate.ex:72-76`
**Issue:** The fallback when `terminal_size` is absent / malformed renders:

> Your terminal is currently: 0×0.

This is unreachable in production per the comment, and per `too_small?/1`
which short-circuits to "not gated" on a nil/missing value. So it only
manifests if a unit test calls `render/1` directly on `%{}`. That's fine
for tests, but the literal "0×0" in the rendered output is a small
honesty footgun — a future log/screenshot of this output would suggest a
real terminal-size detection bug was hit, when in fact it's a defensive
default.

**Fix:** Either render a different sentinel string when the terminal size
isn't available:

```elixir
size_text =
  case Map.get(state, :terminal_size) do
    {c, r} when is_integer(c) and is_integer(r) -> "#{c}×#{r}"
    _ -> "unknown"
  end
```

…and use it in the third line, or accept the current behaviour and add
an inline test-only-path note. Lowest priority finding in the report.

---

## Out-of-scope notes (not findings)

The 6 pre-existing test failures in `Foglet.TUI.AppTest` (FakePosts
`list_reader_window/2` undefined) and the 3 pre-existing dialyzer
warnings (`cli_handler.ex:467`/`:554`, `post_reader/render.ex:26`)
are correctly identified as Phase 44/45 artifacts, not Phase 46 work.
`deferred-items.md` carries them forward and `46-VERIFICATION.md`
flags AC #9 as `human_needed`. No review action needed; the maintainer
decision noted in the verification report stands.

The DOM-01 deletion has zero behavioural risk: the only callers of
`Foglet.Boards.Supervisor` outside this module reference `start_board/1`
and the supervisor pid (sysop snapshot, sysop_test restart). No call site
in `lib/` or `test/` invokes `Foglet.Boards.Supervisor.boot_board_servers/0`;
verified via grep. The real implementation in `lib/foglet_bbs/boards.ex:40`
remains untouched and is the only thing `application.ex:32` calls.

The DOM-02 moduledoc text accurately describes the runtime contract: I
verified that the `handle_call` clauses at lines 97-110 and 113-126
pattern-match on `{:ok, %{post: post}}` and
`{:ok, %{thread_update: thread, post: post}}` respectively (the line
numbers cited in the moduledoc — 86-93 and 102-108 — are off by ~10
lines from the post-edit positions, which is a trivial pre-existing
nit but not worth a separate finding given the labels are still
unambiguous).

---

_Reviewed: 2026-04-29T22:30:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
