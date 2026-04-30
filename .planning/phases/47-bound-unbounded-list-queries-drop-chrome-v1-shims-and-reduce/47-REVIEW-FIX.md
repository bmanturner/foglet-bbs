---
phase: 47-bound-unbounded-list-queries-drop-chrome-v1-shims-and-reduce
fixed_at: 2026-04-30T09:50:00Z
review_path: .planning/phases/47-bound-unbounded-list-queries-drop-chrome-v1-shims-and-reduce/47-REVIEW.md
iteration: 4
findings_in_scope: 9
fixed: 8
skipped: 1
status: partial
---

# Phase 47: Code Review Fix Report

**Fixed at:** 2026-04-30T09:50:00Z
**Source review:** `.planning/phases/47-bound-unbounded-list-queries-drop-chrome-v1-shims-and-reduce/47-REVIEW.md`
**Iteration:** 4

**Summary:**
- Findings in scope: 9 (4 warnings + 5 info; user passed `--all`)
- Fixed: 8
- Skipped: 1 (IN-01, no-action by reviewer's own recommendation)

After all fixes the suite is green: `rtk mix test` reports `1 property,
2241 tests, 0 failures`. `rtk mix precommit` (compile
`--warnings-as-errors`, format, credo `--strict`, sobelow, dialyzer)
also passes.

## Fixed Issues

### WR-01: `LoginForm.handle_task_result/3` masks all task errors as `:invalid_credentials`

**Files modified:** `lib/foglet_bbs/tui/screens/login/login_form.ex`
**Commit:** `418ae208`
**Applied fix:** Reserved `{:error, :invalid_credentials}` for the
explicit auth-failure shape returned by `authenticate_login/5`.
Task-pipeline errors (network failures, GenServer crashes, timeouts,
the `WithClauseError` from WR-02) now `Logger.error` and surface an
"unavailable" modal instead of being silently re-categorized as bad
credentials. Combined with WR-02 in a single commit because both fixes
live in the same file and are causally linked: WR-02's crash is what
WR-01's mask was hiding.

### WR-02: `authenticate_login/5` `with` chain has unhandled fall-through cases

**Files modified:** `lib/foglet_bbs/tui/screens/login/login_form.ex`
**Commit:** `418ae208`
**Applied fix:** Added two catch-all clauses to the `with` `else`:
`{:error, other}` for unanticipated auth-error tuples and bare-atom
`other` for unanticipated user statuses. Both `Logger.error` the
unexpected shape and degrade to `{:error, :invalid_credentials}` so
the user-facing copy stays sensible while operators see the
breadcrumb.

### WR-03: `PostReader.load_posts/2` writes to `state.screen_state` without nil-guard

**Files modified:** `lib/foglet_bbs/tui/screens/post_reader.ex`
**Commit:** `d5139a3a`
**Applied fix:** Added the `state.screen_state || %{}` fallback to the
`Map.put` call in `load_posts/2`, mirroring the safer treatment already
present in `apply_flush_result/4`. `load_posts/2` is documented as a
public test seam / direct-invocation entry point and partial fixtures
with `nil` screen_state would otherwise raise `BadMapError`. Audited
the rest of the module — no other unguarded `state.screen_state` writes.

### WR-04: `app_state_from_local/2` duplicated across four sibling screen modules

**Files modified:**
- `lib/foglet_bbs/tui/screens/shared/app_state_bridge.ex` (new)
- `lib/foglet_bbs/tui/screens/login.ex`
- `lib/foglet_bbs/tui/screens/login/login_form.ex`
- `lib/foglet_bbs/tui/screens/login/render.ex`
- `lib/foglet_bbs/tui/screens/register.ex`
- `lib/foglet_bbs/tui/screens/verify.ex`

**Commit:** `dd56f456`
**Applied fix:** Extracted
`Foglet.TUI.Screens.Shared.AppStateBridge.from_context/4` parameterized
by `screen_atom` and a default-state thunk. Replaced all five
near-verbatim copies with one-line delegating helpers. Removed the four
`TODO(WR-01)` markers; deleted the prose acknowledging session_pid
drift (the bridge guarantees uniform shape now).

The reviewer also flagged duplicated `domain_module/2` helpers in the
same screens. That consolidation is broader (the helpers have different
default-mapping per screen and use `state.domain` rather than
`session_context`) and is left for a follow-up commit. The user's
guidance was to use judgement; the AppStateBridge extraction was small
and safe, the domain_module merge is not, so I scoped this fix to the
former.

### IN-02: `Posts.create_reply/4` returns `:posting_not_allowed` for "thread does not exist"

**Files modified:** `lib/foglet_bbs/posts.ex`
**Commit:** `b38d1388`
**Applied fix:** Added an inline comment explaining that the
`not match?(%Thread{board_id: ^board_id}, thread)` clause intentionally
folds three failure modes (thread not found, thread in another board,
value is not a Thread struct) into a single error to avoid leaking
thread existence to callers without post-creation permission. Did NOT
split into separate error atoms — the obscuring is deliberate
security-information-hiding.

### IN-03: `PostReader` `:on_route_enter` `:load` path does not honor read-pointer position

**Files modified:** `lib/foglet_bbs/tui/screens/post_reader.ex`
**Commit:** `dd484644`
**Applied fix:** Made the reducer-path `update(:load, …)` consult
`state.pending_read_positions[thread_id]` exactly like the test-seam
`load_posts/2` does. Both paths now route through the same
`load_window_opts/2` helper, which emits `direction: :around` with
`around_message_number: pointer` when a pointer exists, and falls back
to the prior `:jump_last → :last` / default `:initial` mapping
otherwise. Dropped the now-unused `load_direction/1`.

**Status note:** `fixed: requires human verification`. This is a
behavioral logic change to a load path. Tier 1 + Tier 2 verification
(read-back, compile, full test suite green) confirm syntax and that
no existing test broke, but they cannot confirm the runtime "if you
saw it, you read it" promise actually holds across all re-entry shapes.
The 88-test `post_reader_test.exs` suite passed unchanged.

### IN-04: `Posts.list_reader_window` `:previous` direction with nil cursor returns ambiguous `has_next?`

**Files modified:** `lib/foglet_bbs/posts.ex`
**Commit:** `01eb597d`
**Applied fix:** Mirrored the BL-01 fix from the `:next` branch — only
consider `has_next?` true when the cursor is a positive integer:

```elixir
has_next? =
  posts != [] and is_integer(cursor) and cursor > 0 and
    reader_has_next?(thread_id, posts, cursor)
```

Production callers (`PostReader.load_adjacent_window/3`) already pass
valid cursors so this is not a live bug, but the public API contract
permits the nil case and the previous result was misleading.

### IN-05: `SessionAlias.promote_session/2` proceeds with current_user update even when session_pid is missing

**Files modified:** `lib/foglet_bbs/tui/app/session_alias.ex`
**Commit:** `dde0453f`
**Applied fix:** Per the reviewer's guidance ("Decide whether the
no-pid case should be a no-op or proceed; either way, document it
explicitly"), kept the proceed-anyway behavior (production wires the
pid before `set_user` fires, so the no-pid path is reachable only in
tests, and refusing to promote would force every test to fabricate a
pid). Added a comment block documenting the decision and listing the
three consequences (session telemetry lost, SSH-05 cannot be enforced,
heartbeat calls become no-ops). Expanded the existing `Logger.warning`
text to mention SSH-05 alongside the prior telemetry note.

## Skipped Issues

### IN-01: `Threads.move_thread/2` hard-pattern-matches `Repo.update_all` return shape

**File:** `lib/foglet_bbs/threads.ex:336-340`
**Reason:** No-action: the reviewer's own recommendation in the **Fix:**
section is "No change required." The strict
`{_count, nil} = Repo.update_all(...)` match is intentional defensive
code — the in-line comment at lines 333–335 explicitly states the
intent ("fail loudly rather than silently swallow it"). The reviewer
flagged it as Info to surface the contract coupling, not to request a
change.
**Original issue:** `{_count, nil} = Repo.update_all(...)` will raise
`MatchError` if Ecto ever returns a different shape. Documented as
intentional defensive behavior; logged as Info.

---

_Fixed: 2026-04-30T09:50:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 4_
