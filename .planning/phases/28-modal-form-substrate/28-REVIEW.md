---
phase: 28-modal-form-substrate
reviewed: 2026-04-27T00:00:00Z
depth: standard
files_reviewed: 9
files_reviewed_list:
  - lib/foglet_bbs/tui/app.ex
  - lib/foglet_bbs/tui/screens/account/prefs_form.ex
  - lib/foglet_bbs/tui/screens/account/profile_form.ex
  - lib/foglet_bbs/tui/screens/sysop/site_form.ex
  - lib/foglet_bbs/tui/screens/sysop/site_form/state.ex
  - lib/foglet_bbs/tui/widgets/modal/form.ex
  - test/foglet_bbs/tui/screens/account_test.exs
  - test/foglet_bbs/tui/screens/sysop/site_form_test.exs
  - test/foglet_bbs/tui/widgets/modal/form_test.exs
findings:
  critical: 0
  warning: 2
  info: 3
  total: 5
status: issues_found
---

# Phase 28: Code Review Report (Gap Closure)

**Reviewed:** 2026-04-27
**Depth:** standard
**Files Reviewed:** 9
**Status:** issues_found
**Diff base:** 1fd1b9f
**Scope:** gap-closure deltas for BL-01, BL-02, BL-03, WR-01 (commits 8b4e504..92bf97b)

## Summary

The four gap-closure changes — BL-01 (`:form` modal lock release on async failure), BL-02 (SiteForm `submit_state` persistence across the per-render rebuild), BL-03 (`Modal.Form.init/1` empty-fields validation), and WR-01 (`:backtab` accepted on Account ProfileForm/PrefsForm guards) — are mechanically sound. Tracing each fix through the tests and call paths confirms the failure modes documented in the prior verification are now closed: a doomed oneliner submit lands in `{:error, _}` rather than wedging at `:submitting`; SiteForm now writes `submit_state` back via `sync_back/2` and seeds the per-render Modal.Form rebuild from it; `Modal.Form.init/1` raises `ArgumentError` when `:fields == []` instead of silently constructing a non-submittable form; and `:backtab` is no longer dropped on the Account guards.

Two correctness concerns surfaced during review. The defensive `_other` branch in `SiteForm.finalize_submit/2` writes a `:submitting` `submit_state` back to `SState` without driving it to a terminal value, which would wedge the form on the next event if that branch is ever reached (theoretically reachable; not exercised by tests). Separately, the SiteForm wrapper bypasses `Modal.Form.set_submit_state/2`'s `:submitting` guard via direct `Map.put(:submit_state, ...)` in three places — this is documented but breaks the public-API encapsulation contract that the module itself enforces with `ArgumentError`. Three lower-severity issues round out the report: stale `form.ex:N-M` line references in the new module-doc, a comment/code mismatch in `summarize_form_errors/1`, and `Modal.Form.init/1` not validating that `:fields` is a list (only that it is non-empty).

The test deltas (`account_test.exs` BL-01 / WR-01 sections, `site_form_test.exs` BL-02 section, `form_test.exs` BL-03 section) accurately exercise the fixes. No test reliability concerns.

## Warnings

### WR-01: `SiteForm.finalize_submit/2` `_other` branch can wedge the form at `:submitting`

**File:** `lib/foglet_bbs/tui/screens/sysop/site_form.ex:152-155`
**Issue:** The defensive `_other ->` branch calls `sync_back(state, new_form)` where `new_form` has `submit_state: :submitting` (set by `Modal.Form`'s `:enter` clause that just fired). `sync_back/2` (line 215) writes the form's `submit_state` back to `SState`. On the next event, `handle_key/2` rebuilds the Modal.Form with `Map.put(:submit_state, :submitting)`, the lock guard at `Modal.Form.handle_event/2` swallows every subsequent event, and the form has no path to release. Reachability: only when `SubmitStash.pop(SState)` returns a value matching neither `{:site, {:ok, _}}` nor `{:site, {:error, _}}` — in normal flow `on_submit` always stashes one of those, so this branch is unreachable today, but the comment ("Defensive: stash empty or unexpected — treat as no-op submit") signals the author expects it might fire. If it does, the form is wedged with no keyboard escape — exactly the BL-01 failure mode this phase exists to prevent.

**Fix:**
```elixir
_other ->
  # Defensive: stash empty or unexpected — drive submit_state out of
  # :submitting so the next event isn't lock-swallowed (BL-01 contract).
  reset_form = ModalForm.set_submit_state(new_form, :idle)
  {sync_back(state, reset_form), []}
```

### WR-02: SiteForm bypasses `Modal.Form.set_submit_state/2`'s `:submitting` guard via direct `Map.put`

**File:** `lib/foglet_bbs/tui/screens/sysop/site_form.ex:70, 95, 119`
**Issue:** `Modal.Form.set_submit_state/2` deliberately raises `ArgumentError` on `:submitting` (form.ex:359-364) because that transition "is reserved for the internal Enter-on-last-field clause." SiteForm circumvents this guard by writing `submit_state` directly with `Map.put(:submit_state, state.submit_state)` in three sites (`render/2`, `handle_key/2`, `submit/1`). The accompanying comment justifies this as "faithfully replay any persisted lifecycle value, including `:submitting` on the next render." The justification is reasonable, but the implementation breaks the public-API encapsulation contract that the widget itself enforces — any future invariant added to `set_submit_state/2` (validation, side effects, telemetry) is silently bypassed here, and a reader who trusts the `ArgumentError` guard as a real invariant will be surprised. This pattern also makes BL-02 fragile: if `Modal.Form` ever adds field-state coupling to `submit_state` (e.g., reset cursor on `:submitting` entry), this rebuild path will desynchronize.

**Fix:** Add a public escape hatch on `Modal.Form` for the documented "rebuild-and-replay" pattern, and replace the three `Map.put` sites with it:
```elixir
# In Modal.Form:
@doc """
Replay a previously-captured submit_state onto a freshly-built form
(Phase 28 D-17 rebuild pattern). Accepts the full lifecycle including
`:submitting`, unlike set_submit_state/2.
"""
@spec replay_submit_state(t(), submit_state()) :: t()
def replay_submit_state(%__MODULE__{} = state, value), do: %{state | submit_state: value}

# In SiteForm:
state |> SState.build_modal_form() |> ModalForm.replay_submit_state(state.submit_state) |> ...
```

If the bypass is intentional and the team prefers minimal API surface, downgrade by removing the `:submitting` raise from `set_submit_state/2` and updating the docstring — but pick one contract.

## Info

### IN-01: Stale `form.ex:N-M` line references in module documentation

**File:** `lib/foglet_bbs/tui/widgets/modal/form.ex:68, 70` and `lib/foglet_bbs/tui/screens/sysop/site_form.ex:89, 90`
**Issue:** The new "Submit-state lifecycle" module-doc cites:
- `form.ex:233-244` for the Enter-on-last-field clause — actual location is `form.ex:263-274`
- `form.ex:164-166` for the lock guard — actual location is `form.ex:194-196`

`site_form.ex` cites:
- `form.ex:164-166` for the lock guard — actual location is `form.ex:194-196`
- `form.ex:178-184` for the auto-reset preamble — actual location is `form.ex:208-214`

These references were apparently captured before recent line shifts and are now misleading by ~30 lines.

**Fix:** Either update the line numbers, or replace numeric references with searchable anchors (e.g., "Clause 0: Lock", "auto-reset preamble") so they survive future edits.

### IN-02: `summarize_form_errors/1` comment claims "shortest representative" but picks first by key order

**File:** `lib/foglet_bbs/tui/app.ex:1069-1077`
**Issue:** The helper docstring says "pick the shortest representative message," but the implementation pattern-matches `Map.values(errors)` and binds the first element via `[first | _]`. `Map.values/1` returns values in the map's iteration order (Erlang term order on keys), not by string length. With a single-error map (the only case exercised today by `put_oneliner_form_errors/2`/`put_hide_oneliner_form_errors/2`), this is fine. With multiple errors (e.g., `%{base: "X", body: "Y"}`), the chosen status-row message is the first by atom/string sort order, not the shortest.

**Fix:** Either pick the actual shortest:
```elixir
defp summarize_form_errors(errors) when is_map(errors) do
  errors
  |> Map.values()
  |> Enum.filter(&is_binary/1)
  |> Enum.min_by(&String.length/1, fn -> "validation" end)
end
```
…or update the comment to "first error message by key order" so it matches the code.

### IN-03: `Modal.Form.init/1` does not validate `:fields` is a list

**File:** `lib/foglet_bbs/tui/widgets/modal/form.ex:153-159`
**Issue:** BL-03 added a check for `fields == []` but not for non-list values. `Keyword.fetch!(opts, :fields)` returns whatever the caller passed; if that value is `nil`, `:atom`, or a map, the `fields == []` check evaluates to `false` (these terms aren't equal to `[]`), and the next line `Enum.map(fields, &build_field_state/1)` crashes with `Protocol.UndefinedError` rather than the friendly `ArgumentError` BL-03 introduced. The two BL-03 tests cover the empty-list case but not the "wrong type" case.

**Fix:**
```elixir
fields = Keyword.fetch!(opts, :fields)

cond do
  not is_list(fields) ->
    raise ArgumentError,
          "Modal.Form requires :fields to be a list; got #{inspect(fields)}"

  fields == [] ->
    raise ArgumentError,
          "Modal.Form requires at least one field; received an empty :fields list"

  true ->
    :ok
end
```

---

_Reviewed: 2026-04-27_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
