---
phase: 29-sysop-tab-lifecycle-bodies
reviewed: 2026-04-27T21:42:27Z
depth: standard
files_reviewed: 21
files_reviewed_list:
  - lib/foglet_bbs/accounts.ex
  - lib/foglet_bbs/config/schema.ex
  - lib/foglet_bbs/tui/app.ex
  - lib/foglet_bbs/tui/screens/account.ex
  - lib/foglet_bbs/tui/screens/domain.ex
  - lib/foglet_bbs/tui/screens/moderation.ex
  - lib/foglet_bbs/tui/screens/shared/invites_surface.ex
  - lib/foglet_bbs/tui/screens/sysop.ex
  - lib/foglet_bbs/tui/screens/sysop/state.ex
  - lib/foglet_bbs/tui/screens/sysop/users_view.ex
  - lib/foglet_bbs/tui/widgets/chrome/normalizer.ex
  - test/foglet_bbs/accounts/accounts_test.exs
  - test/foglet_bbs/config/schema_test.exs
  - test/foglet_bbs/tui/app_test.exs
  - test/foglet_bbs/tui/layout_smoke_test.exs
  - test/foglet_bbs/tui/screens/shared/invites_surface_test.exs
  - test/foglet_bbs/tui/screens/sysop_test.exs
  - test/foglet_bbs/tui/screens/sysop/site_form_test.exs
  - test/foglet_bbs/tui/widgets/chrome/normalizer_test.exs
  - test/support/fake_accounts.ex
  - test/support/foglet/tui/layout_smoke/sysop_helper.ex
findings:
  blocker: 0
  warning: 7
  total: 7
status: issues_found
---

# Phase 29: Code Review Report

**Reviewed:** 2026-04-27T21:42:27Z
**Depth:** standard
**Files Reviewed:** 21
**Status:** issues_found

## Summary

Phase 29 (sysop tab lifecycle bodies) lands cleanly. The lifecycle tagged-enum
plumbing in `Sysop.State`, the App-level load triad
(`{:load_sysop_*}` → task → `{:sysop_*_loaded, _}` → `put_sysop_loaded|error`),
and the [R]etry / [X]Revoke gestures all match what the test bank exercises. The
new `Foglet.Accounts.transition_user_status/3` boundary is well-shaped:
authorization runs before target lookup so unauthorized callers can't probe
account existence, status normalization is `to_existing_atom/1`-safe via rescue,
and the stale-row `{:error, :invalid_transition}` path produces operator-named
copy via `UsersView.invalid_transition_message/3`.

No blocker-level defects were found in scope. Findings below cluster around two
themes:

1. **Operator-facing copy hygiene** — the SYSOP-04 invariant locked by
   `schema_test.exs` covers only `@site_keys`. The two LIMITS-tab descriptions
   leak planning IDs ("D-31", "D-13", "phase-03-polish Phase 4") to operators
   even though the test file names this exact class of leak as forbidden.
2. **Defensive map-access asymmetry** — Sysop screen mutators assume
   `state.screen_state` is a non-nil map; the sibling Moderation/Account
   screens defensively coerce `nil → %{}`. Today the App default is `%{}`, so
   this is dormant, but any future call site that constructs an App map
   without the default will crash inside Sysop. The pattern is worth
   tightening because it's load-bearing on a no-default invariant the file
   itself doesn't document.

## Warnings

### WR-01: LIMITS schema descriptions leak planning IDs to operators

**File:** `lib/foglet_bbs/config/schema.ex:72,81`
**Issue:** The two integer-typed LIMITS keys carry descriptions that contain
forbidden tokens per the SYSOP-04 invariant in `schema_test.exs:406-424`:

```elixir
%{key: "max_post_length",         description: "Maximum post body length in characters (D-31)", ...},
%{key: "max_thread_title_length", description: "Maximum thread title length in characters (D-13, phase-03-polish Phase 4)", ...},
```

These descriptions DO render to operators — `sysop_test.exs:845-854` asserts
`String.contains?(flat, spec.description)` for every `LimitsForm.limits_keys()`
key. The SYSOP-04 grep test (`schema_test.exs:416-424`) explicitly catches
`/(D-\d+|REQ-[A-Z]+-\d+|Phase \d+|Pitfall \d+|deliverable)/i` but only for the
hard-coded `@site_keys` list, leaving the LIMITS descriptions outside the
guard's scope even though the same content rule applies. This is a documented
content invariant violation that operators will see in the LIMITS tab.

**Fix:** Rewrite the two descriptions to remove the planning markers and end
with a period (matching the @site_keys hygiene rule), and broaden the SYSOP-04
test to cover every key whose description renders. For example:

```elixir
%{
  key: "max_post_length",
  ...
  description: "Maximum post body length in characters."
},
%{
  key: "max_thread_title_length",
  ...
  description: "Maximum thread title length in characters."
}
```

And in `schema_test.exs`, replace the hardcoded `@site_keys` list with the
union of `SiteForm.site_keys() ++ LimitsForm.limits_keys()` (or
`Schema.entries() |> Enum.map(& &1.key)`) so future renamed/added keys are
covered automatically.

### WR-02: `Foglet.TUI.Screens.Sysop` writes via `Map.put(state.screen_state, ...)` without nil-coalescing

**File:** `lib/foglet_bbs/tui/screens/sysop.ex:276,301,324,364,395,446`
**Issue:** Six call sites in `sysop.ex` write `Map.put(state.screen_state, :sysop, new_ss)` directly. If a caller constructs an App-shaped map without the
`screen_state: %{}` default (e.g. a test that builds a bare `%App{}` and then
calls `Map.from_struct/1` and overwrites `screen_state` with `nil`, or a future
subscribe path that mutates the field), `Map.put(nil, :sysop, _)` crashes with
`BadMapError`. The sibling screens defensively coalesce — `account.ex:275`
uses `Map.put(state.screen_state, :account, ss)` against the typed `t()`
struct, but `moderation.ex:383` and `app.ex` consistently use
`Map.get(state, :screen_state) || %{}` / `state.screen_state || %{}`.

The hard-default in `app.ex:78` (`screen_state: %{}`) keeps this latent today,
but the inconsistency means one of the screens is a single typed-struct change
away from breaking — and the Sysop screen is the one without the guard.

**Fix:** Either match the defensive idiom from `app.ex` and `moderation.ex` at
each Sysop write site:

```elixir
new_screen_state = Map.put(state.screen_state || %{}, :sysop, new_ss)
```

…or extract a single `put_sysop_state/2` helper at the bottom of the module:

```elixir
defp put_sysop_state(state, ss) do
  %{state | screen_state: Map.put(state.screen_state || %{}, :sysop, ss)}
end
```

…and route every write site through it.

### WR-03: `delete_user/1` `Repo.update_all` does not bump `updated_at` on rewritten posts

**File:** `lib/foglet_bbs/accounts.ex:440-442`
**Issue:** During account anonymization, posts authored by the deleted user
are reassigned to the tombstone user via:

```elixir
Repo.update_all(from(p in Post, where: p.user_id == ^user.id),
  set: [user_id: tombstone_user_id()]
)
```

`Repo.update_all/3` does NOT trigger changesets and does NOT update timestamp
fields. The post's `updated_at` stays at whatever it was before deletion, even
though the row's `user_id` (a denormalised authoritative author reference) just
changed. Audit trails / change-detection (Phase 2+ moderation log, future ETL,
post-edit-detection UI) cannot reliably distinguish "post body edited" from
"author rewritten by tombstone flow" because both leave `updated_at` stale.

This is a correctness-ish concern rather than a true bug — Phase 1's deletion
contract documents post rewriting but doesn't promise an audit signature. Worth
fixing now while the contract is malleable.

**Fix:** Add `updated_at` to the `set:` clause:

```elixir
now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
Repo.update_all(from(p in Post, where: p.user_id == ^user.id),
  set: [user_id: tombstone_user_id(), updated_at: now]
)
```

(or set it to `^user.deleted_at` if you'd rather all anonymized posts share a
single anonymization timestamp).

### WR-04: `summarize_form_errors/1` truncation may surface a misleading "shortest message"

**File:** `lib/foglet_bbs/tui/app.ex:1175-1180`
**Issue:** When multiple form-validation errors are present, the App pulls the
single shortest binary value to drive the FORM-05 status row:

```elixir
defp summarize_form_errors(errors) when is_map(errors) do
  errors
  |> Map.values()
  |> Enum.filter(&is_binary/1)
  |> Enum.min_by(&String.length/1, fn -> "validation" end)
end
```

The comment at line 1173-1174 acknowledges this is deliberate ("ties resolve
to the first match"). But "shortest" is a poor proxy for "most relevant" — a
genuine high-signal error like `"Body cannot be blank."` (24 chars) gets
shadowed by an incidental `"Required."` (9 chars) on a different field. The
operator sees a one-line status row that doesn't match what the per-field
errors say. The fallback default `"validation"` is also a bare token that ends
up rendered without a period or context.

**Fix:** Either pick the first binary error in canonical field order
(matching how the form lays them out), or surface a generic
`"Please correct the highlighted fields."` whenever `length(values) > 1`. For
example:

```elixir
defp summarize_form_errors(errors) when is_map(errors) do
  binaries = errors |> Map.values() |> Enum.filter(&is_binary/1)

  case binaries do
    [] -> "validation"
    [single] -> single
    _multiple -> "Please correct the highlighted fields."
  end
end
```

### WR-05: `App.do_update({:load_sysop_*}, _)` flips slot to `:loading` redundantly when called from screen-emitted commands

**File:** `lib/foglet_bbs/tui/app.ex:552-609` and `lib/foglet_bbs/tui/screens/sysop.ex:487-491`
**Issue:** The Sysop screen's `dispatch_if_not_loaded/3` (sysop.ex:487-491)
already flips the lifecycle slot to `:loading` *and* emits a `{:load_sysop_*}`
tuple. When the App's `process_screen_commands/2` (app.ex:1519-1538) routes
that tuple through `do_update/2`, the matching App-level clause then calls
`put_sysop_loading(state, slot)` which writes `:loading` *again*. The two
writes are idempotent, so functionally this is a no-op — but the duplicated
state-mutation makes the load contract harder to reason about: the screen
appears to own the `:loading` transition (it advertises it in its return value),
but the App also does.

This isn't a correctness bug — but it's a footgun for the next refactor. The
test at `app_test.exs:1580-1620` (`all four lifecycle slots round-trip`)
exercises the App path directly with bare `App.update({:load_sysop_users}, _)`
and never the screen→app chain, so the double-write is invisible to tests.

**Fix:** Pick one owner. Recommended: keep the App as the single writer (it's
the place that actually fires the off-process task), and have the Sysop
screen emit only the dispatch tuple without pre-flipping the slot:

```elixir
defp dispatch_if_not_loaded(ss, slot, dispatch_tuple) do
  case Map.get(ss, slot) do
    :not_loaded -> {ss, [dispatch_tuple]}
    _ -> {ss, []}
  end
end
```

Then update `sysop_test.exs:262-273` (which currently asserts
`new_state.screen_state.sysop.users_view == :loading` after the screen-level
keypress) to instead assert that the dispatch tuple was emitted, and check the
loading state after the App round-trip.

### WR-06: `sysop.ex` `delegate_to_invites/3` clears `armed_revoke?` only on selected_index change, not on action

**File:** `lib/foglet_bbs/tui/screens/sysop.ex:381-401`
**Issue:** The armed-revoke flag is cleared only when the focused row index
changes:

```elixir
armed_after =
  if invites.selected_index != ss.invites.selected_index,
    do: false,
    else: ss.armed_revoke?
```

If the operator arms revoke (Enter on a non-revoked row), then performs a
non-navigation invites action that *doesn't* change `selected_index` —
e.g. `R Refresh`, `G Generate` (which appends to the list but keeps focus),
or the focused row's status changing as a side effect of a refresh — the
armed flag stays true. Subsequently pressing `X` will revoke whatever row is
*now* under the cursor, which may not be the row the operator armed against.

The X handler in `handle_key/2` does call `InvitesActions.revoke_selected/2`
which uses the *current* `selected_index`, so the revoke target is always the
focused row at X-press time. But the armed-state advertisement (the
"[X] Revoke" command-bar group) was earned by Enter on a different row,
which is the gesture-disambiguation drift D-25 sets out to prevent.

This is a UX / defense-in-depth concern, not a security or data-loss bug —
`InvitesActions.revoke_selected/2` is itself authorized at the boundary, and
revoking a non-revoked invite from any focus position is operator-intended.

**Fix:** Clear `armed_revoke?` whenever the InvitesActions-handled key was
anything other than a vertical move (`up`/`down`/`j`/`k`):

```elixir
defp delegate_to_invites(event, state, ss) do
  key = invite_key(event)

  case InvitesActions.handle_key(key, state.current_user, ss.invites) do
    {:ok, invites} ->
      armed_after = invites_arm_preserved?(key, invites, ss.invites) and ss.armed_revoke?
      ...
  end
end

defp invites_arm_preserved?(key, new_invites, old_invites) do
  key in [:up, :down, "j", "k", "J", "K"] and
    new_invites.selected_index == old_invites.selected_index
end
```

### WR-07: `Foglet.TUI.Screens.Sysop.handle_key/2` Enter on INVITES revoked-row falls through to tab widget instead of staying on the row

**File:** `lib/foglet_bbs/tui/screens/sysop.ex:269-282`
**Issue:** The Enter handler arms revoke only for non-revoked rows:

```elixir
case {active_label, InvitesState.selected_item(ss.invites)} do
  {"INVITES", %{status: status}} when status != :revoked -> ...arms...
  _ -> do_handle_key(event, state)
end
```

When the focused row IS already revoked, the Enter event falls through to
`do_handle_key/2`, which routes Enter through `Tabs.handle_event/2` first.
Looking at the Tabs widget contract used elsewhere (e.g. moderation.ex:79-87),
Enter is *not* normally a tab-switch key, so `Tabs.handle_event/2` should
return `{tabs, nil}` and the screen will then `delegate_to_active_tab` →
`delegate_to_invites` → `InvitesActions.handle_key(:enter, ...)` which is
`:no_match`. End result: Enter on a revoked row is a silent no-op.

The silent no-op is not wrong — but it also makes "the focused invite is
already revoked, you can't re-revoke" invisible to the operator. There's no
status row, banner, or hint that explains why the [X] Revoke advertisement
is absent for this row. An operator who sees a focused row and presses Enter
has reasonable expectation of *some* feedback.

**Fix:** Either advertise an empty-arm hint when the focused row is revoked
(add a `[Revoked]` annotation to the focused indicator in `InvitesSurface`),
or surface a one-shot status message via `InvitesState.error` when Enter is
pressed on a revoked row:

```elixir
{"INVITES", %{status: :revoked}} ->
  new_invites = %{ss.invites | error: "Invite already revoked."}
  new_ss = %{ss | invites: new_invites}
  ...
```

The latter requires a one-tick clear-on-next-event for the error string but
matches the existing InvitesState error-surfacing path.

---

_Reviewed: 2026-04-27T21:42:27Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
