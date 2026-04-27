---
phase: 28-modal-form-substrate
reviewed: 2026-04-27T18:34:00Z
depth: standard
files_reviewed: 11
files_reviewed_list:
  - lib/foglet_bbs/tui/app.ex
  - lib/foglet_bbs/tui/screens/account/prefs_form.ex
  - lib/foglet_bbs/tui/screens/account/profile_form.ex
  - lib/foglet_bbs/tui/screens/sysop/site_form.ex
  - lib/foglet_bbs/tui/screens/sysop/site_form/state.ex
  - lib/foglet_bbs/tui/widgets/modal/form.ex
  - test/foglet_bbs/tui/screens/account_test.exs
  - test/foglet_bbs/tui/screens/sysop/site_form_test.exs
  - test/foglet_bbs/tui/widgets/input_focus_state_test.exs
  - test/foglet_bbs/tui/widgets/modal/form_test.exs
  - test/support/foglet/tui/layout_smoke/account_helper.ex
findings:
  blocker: 3
  warning: 6
  total: 9
status: issues_found
---

# Phase 28: Code Review Report

**Reviewed:** 2026-04-27T18:34:00Z
**Depth:** standard
**Files Reviewed:** 11
**Status:** issues_found

## Summary

The Modal.Form substrate work (focus navigation, footer opt-in, submit-state
machine, honest Esc, Sysop SiteForm migration) is broadly well-shaped — the
public API is documented, the focus model is single-source-of-truth, and the
test surface is large. However, the new submit-state machine has two
integration paths where the lock guard interacts badly with how callers manage
the form struct, producing one user-locking modal bug and one
silent-status-row defect that nullifies most of the FORM-05 visibility
contract for the Sysop SITE form.

The Account oneliner / hide-oneliner flows in `app.ex` were not updated to
release the new `:submitting` lock on validation failure; once the user hits
Enter on a doomed oneliner, the entire modal — including Esc — becomes
unresponsive. The Sysop SiteForm rebuilds the Modal.Form fresh on every
keystroke, which means the submit-state set by `set_submit_state(:saved)` and
`set_submit_state({:error, "validation"})` is dropped immediately and never
rendered. There is also a small but pinnable inconsistency where Account
ProfileForm/PrefsForm omit `:backtab` from their key-allow-list, so the
CLIHandler-translated terminal back-tab silently no-matches on those screens.

## BLOCKER Issues

### BL-01: Oneliner / hide-oneliner modal becomes permanently unresponsive after a failed submit

**File:** `lib/foglet_bbs/tui/app.ex:1369-1398`, interacting with
`lib/foglet_bbs/tui/widgets/modal/form.ex:164-166` and
`lib/foglet_bbs/tui/app.ex:1023-1052`

**Issue:**
After Phase 28 added the submit-state lock guard
(`form.ex:164-166`), `ModalForm.handle_event/2` swallows every event when
`submit_state == :submitting`. The Account oneliner composer
(`do_update({:open_oneliner_composer}, …)`) and the hide-oneliner modal
(`do_update({:open_hide_oneliner_modal, …})`) drive the form through the
internal Enter-on-last-field transition, which sets `submit_state =
:submitting` and persists that form on `state.modal.message` at
`app.ex:1377`.

When the resulting backend call fails — e.g. `{:oneliner_created, {:error,
%Ecto.Changeset{}}}` (`app.ex:581-592`) or `{:oneliner_hidden, {:error,
:forbidden}}` (`app.ex:666-678`) — the error handlers funnel through
`put_oneliner_form_errors/2` / `put_hide_oneliner_form_errors/2`, which call
only `ModalForm.set_errors/2` and never `set_submit_state/2`. The form stays
in `:submitting` forever. Every subsequent key — including `:escape`, which
is the only documented dismissal path for `:form` modals — is short-circuited
by the lock clause and dropped. The user cannot edit the field, retry, or
close the modal; the only escape is to close the SSH session.

The existing `app.ex` test "failed save renders errors and leaves active
snapshots unchanged" only checks `update/2` directly and does not exercise
the `handle_modal_key(:form, …)` entry point that drives the Modal.Form
forward, so this regression is not caught.

**Fix:**
In every error handler that re-renders an existing `:form` modal, reset the
form's submit_state to `{:error, msg}` (or `:idle`) so the lock guard
releases. The natural place is `put_oneliner_form_errors/2` and
`put_hide_oneliner_form_errors/2`:

```elixir
defp put_oneliner_form_errors(
       %{modal: %Foglet.TUI.Modal{message: %ModalForm{} = form}} = state,
       errors
     ) do
  form =
    form
    |> ModalForm.set_errors(errors)
    |> ModalForm.set_submit_state({:error, summarize(errors)})

  %{state | modal: %{state.modal | message: form}}
end
```

Apply the same `set_submit_state` reset in `put_hide_oneliner_form_errors/2`.
Add a regression test that posts a doomed oneliner via the modal-key path
and asserts that a subsequent `%{key: :escape}` dismisses the modal.

---

### BL-02: Sysop SiteForm "Saving…/Saved./Error:" status row never renders, and FORM-05 lock has zero effect

**File:** `lib/foglet_bbs/tui/screens/sysop/site_form.ex:78-92, 115-187, 189-193`

**Issue:**
`SiteForm.handle_key/2` and `SiteForm.render/2` rebuild the Modal.Form from
scratch on every event and every render via `SState.build_modal_form/1`
(line 60-65 and 79-83). Because `build_modal_form/1`
(`site_form/state.ex:117-139`) calls `ModalForm.init/1`, the resulting form
always has `submit_state: :idle`.

Two follow-on defects fall out of this:

1. After a successful `Config.put` cascade, `persist_payload/3`
   (line 180-182) calls `ModalForm.set_submit_state(new_form, :saved)` and
   stores the result in a local `final_form2`. `sync_back/2` (line 189-193)
   then writes back **only** `drafts` and `focused` to `SState`; `final_form2`
   itself is discarded. On the next render, `build_modal_form` produces a
   fresh `:idle` form, so the "Saved." status row defined by
   `Modal.Form.render_status_row/2` (`form.ex:399-400`) is never visible to
   the operator. Likewise, the validation-error path at line 124
   (`set_submit_state(new_form2, {:error, "validation"})`) is dropped by the
   same `sync_back`, so "Error: validation" never displays. The
   `state.errors` map drives per-field inline errors, but the global status
   row contract (D-08, D-09 — "Status row replaces footer when active") is
   silently broken for the SITE form.

2. The FORM-05 lock guard never engages. Because every event produces a
   fresh `:idle` form, double-Enter or held-Enter races cannot be debounced
   by Modal.Form: the second Enter sees `:idle`, walks straight through the
   submit clause again, runs the on_submit callback a second time, and
   re-invokes `Foglet.Config.put/3` (which is idempotent for the same value
   but not free). The protective intent of FORM-05 D-02 is silently nullified
   on this screen.

This is also visible in the test surface: `site_form_test.exs` asserts
`Config.get!` after submit but never asserts the status row appears, so the
defect was not caught.

**Fix:**
Persist the Modal.Form alongside `SState` so `submit_state` survives across
events. Two reasonable shapes:

* Cache the most recent `%ModalForm{}` on `SState` (e.g. add `form: nil`
  field) and rebuild only when visible-keys change, OR
* Persist just the `submit_state` on `SState` and re-apply it after
  `build_modal_form` in `render/2` and `handle_key/2`.

```elixir
# In SState struct
defstruct current_user: nil, drafts: %{}, errors: %{}, focused: 0,
          submit_state: :idle

# In SiteForm.render/2
state
|> SState.build_modal_form()
|> Map.put(:submit_state, state.submit_state)
|> apply_errors(state.errors)
|> ModalForm.render(theme: theme)

# In persist_payload/3 success branch
new_state = %{final_state | submit_state: :saved}
{sync_back(new_state, new_form), []}
```

Add tests that drive Ctrl+S and assert "Saved." appears in the rendered
output, and that double-Ctrl+S only invokes `Config.put` once.

---

### BL-03: `Modal.Form` arithmetic crashes if a form is initialised with zero fields

**File:** `lib/foglet_bbs/tui/widgets/modal/form.ex:195-244, 251-273`

**Issue:**
Several focus-navigation clauses compute `n = length(state.fields)` and then
`rem(_, n)`. Specifically:

* Shift-Tab (line 197), `:shift_tab` (line 206), `:backtab` (line 215),
  `:tab` (line 222), Enter-advance (line 242), Down-advance (line 255), and
  Up-retreat (line 268) all unconditionally divide by `length(state.fields)`.
* `Enter` (line 233-244) computes `last_idx = length(state.fields) - 1`,
  yielding `-1` when fields is empty; `state.focus_index == -1` is false, so
  control falls through to the `rem(_, 0)` branch and raises
  `ArithmeticError`.

`Modal.Form.init/1` does not validate that `fields` is non-empty
(`form.ex:129-143`). Today every caller happens to pass at least one field,
but a future caller (or a screen that conditionally hides every field via
something like `SiteForm.State.visible_keys/1`) can produce an empty list
and crash the entire TUI app process. `SiteForm.State.visible_keys/1`
(`site_form/state.ex:101-108`) already supports filtering, and a future
visibility rule could take the visible set to zero.

**Fix:**
Either reject zero-field forms at `init/1` with a clear `ArgumentError`, or
guard each navigation clause:

```elixir
def init(opts) when is_list(opts) do
  fields = Keyword.fetch!(opts, :fields)
  fields == [] and raise ArgumentError, "Modal.Form requires at least one field"
  # ...
end
```

Add a unit test asserting `Modal.Form.init(fields: [], ...)` raises.

---

## WARNING Issues

### WR-01: ProfileForm/PrefsForm drop the CLIHandler-translated `:backtab` key

**File:** `lib/foglet_bbs/tui/screens/account/profile_form.ex:32-36`,
`lib/foglet_bbs/tui/screens/account/prefs_form.ex:34-37`

**Issue:**
Modal.Form FORM-02 / D-15 explicitly documents that `:backtab` (the
CLIHandler translation of terminal `ESC[Z`) is byte-equivalent to
`:shift_tab` and `%{key: :tab, shift: true}` — a dedicated clause exists
for it (`form.ex:213-217`). The Account ProfileForm and PrefsForm
`handle_key/3` guards limit the accepted key list to:

```elixir
when key in [:char, :backspace, :enter, :escape, :tab, :shift_tab, :up, :down]
```

`:backtab` is missing. When a real terminal sends `ESC[Z` while focus is on
PROFILE or PREFS, the call returns `:no_match` and the keystroke is dropped
(or worse, falls through to the global handler, depending on the screen
chain). This is a surprise inconsistency with both the Modal.Form public
contract and the Sysop SiteForm wrapper, which routes `:backtab` through
`Modal.Form.handle_event/2` correctly.

**Fix:**
Add `:backtab` to both guards:

```elixir
when key in [:char, :backspace, :enter, :escape, :tab, :shift_tab, :backtab, :up, :down]
```

Add a regression test that sends `%{key: :backtab}` to ProfileForm and
asserts focus moved backward.

---

### WR-02: SiteForm partial-Config.put cascade leaves drafts diverged from persisted state

**File:** `lib/foglet_bbs/tui/screens/sysop/site_form.ex:141-187`

**Issue:**
`persist_payload/3` walks the visible keys via `Enum.reduce_while/3` and
calls `Foglet.Config.put/3` per key. On `{:error, :forbidden}` or
`{:error, :db_error}` it halts the loop and returns
`{:error_modal, …, :main_menu}` events. If keys 1 and 2 succeeded and key 3
fails with `:db_error`, keys 1 and 2 remain persisted in Postgres while the
user is bounced to the main menu — but `final_state.drafts` for the failed
and unattempted keys still hold the user's edits. There is no transactional
boundary and no compensating rollback.

This is mentioned only obliquely by the implementation (the per-key Schema
puts are individually validated). The user has no way to know which keys
landed and which did not. For sysop site policy, partial state is a real
operational hazard: `delivery_mode` could land while
`require_email_verification` did not, producing exactly the invariant pair
that `validate_delivery_verification_pair/1` is supposed to prevent.

**Fix (preferred):** wrap the cascade in `Foglet.Config.put_many/2` (or a
new transactional helper) so the per-key puts succeed or fail as one unit.
**Fix (lesser):** at minimum, surface "Saved keys: A, B. Failed: C." copy in
the error modal so the operator can recover, and re-seed `drafts` from
`Config.get!/1` for keys that DID persist (so the form reflects truth).

---

### WR-03: SiteForm.State `on_cancel` callback is dead code; doc comment misleads

**File:** `lib/foglet_bbs/tui/screens/sysop/site_form/state.ex:20-25, 137`,
`lib/foglet_bbs/tui/screens/sysop/site_form.ex:73-76`

**Issue:**
`SiteForm.State.build_modal_form/1` registers
`on_cancel: fn -> SubmitStash.stash(__MODULE__, {:site, :cancelled}) end`
(line 137), and the moduledoc states (lines 20-25) "Cancel path: stash
`{:site, :cancelled}` so the wrapper can drive `reseed_drafts/1` on the
next render."

But `SiteForm.handle_key(%{key: :escape}, …)` (line 73-76) intercepts Esc
**before** the event ever reaches `Modal.Form.handle_event/2`, calling
`SState.reseed_drafts(state)` directly. The on_cancel stash is therefore
never written by this path, and the wrapper does not consume `{:site,
:cancelled}` anywhere. This is dead code and the moduledoc actively
misleads the next reader about the cancel contract.

**Fix:**
Either route the Esc handler through `Modal.Form.handle_event/2` (so the
on_cancel callback is honoured and the stash flows through `finalize_submit`
or a similar branch), OR drop the on_cancel callback (replace with a no-op,
e.g. `fn -> :ok end`) and update the moduledoc to state that the wrapper
intercepts Esc directly.

---

### WR-04: `SState.apply_errors` uses `String.to_existing_atom/1` on potentially untrusted error keys

**File:** `lib/foglet_bbs/tui/screens/sysop/site_form.ex:207-217`

**Issue:**
`apply_errors/2` converts the wrapper's string-keyed error map into atom
keys via `String.to_existing_atom/1`. Today the only string keys that reach
this path come from `stringify_keys/1` (line 232-237) over errors that
themselves came from `validate_delivery_verification_pair/1` (whose keys
are interned at compile time), so this is safe **today**. But there is no
clause for the `:base` error key shape that the rest of the form rendering
supports (`form.ex:367-370`), and a future caller that puts an error under,
e.g. `"invite_generation_per_user_limit"` while the field is hidden via
D-21 would still find that atom interned (compile-time list at
`state.ex:44-50`) — fine — but a typo'd or new error key would raise
`ArgumentError` and crash the SSH session.

**Fix:**
Add a defensive fall-through clause that drops unknown error keys with a
warning, rather than raising:

```elixir
defp apply_errors(%ModalForm{} = form, errors) do
  atom_errors =
    Enum.reduce(errors, %{}, fn
      {k, v}, acc when is_atom(k) ->
        Map.put(acc, k, v)

      {k, v}, acc when is_binary(k) ->
        case to_known_atom(k) do
          {:ok, atom} -> Map.put(acc, atom, v)
          :error ->
            require Logger
            Logger.warning("[SiteForm] dropping error for unknown key #{inspect(k)}")
            acc
        end
    end)

  ModalForm.set_errors(form, atom_errors)
end

defp to_known_atom(k) do
  {:ok, String.to_existing_atom(k)}
rescue
  ArgumentError -> :error
end
```

---

### WR-05: `Modal.Form.field_value/2` silently returns the first match on duplicate field names

**File:** `lib/foglet_bbs/tui/widgets/modal/form.ex:301-308`

**Issue:**
`field_value/2` finds field by `Enum.find_index(fields, &(&1.name == field_name))`,
returning the first match. If a caller accidentally configures two fields
with the same `:name` (a real possibility for code generators or copy-paste
errors), the second field is silently unreachable — typed values from it
are lost on submit (`collect_values/1` would also produce a map with the
second value clobbering the first). Modal.Form should reject duplicate
field names at `init/1`.

**Fix:**
Validate uniqueness at init:

```elixir
def init(opts) when is_list(opts) do
  fields = Keyword.fetch!(opts, :fields)

  names = Enum.map(fields, & &1.name)

  if length(names) != length(Enum.uniq(names)) do
    raise ArgumentError,
          "Modal.Form fields must have unique :name values, got: #{inspect(names)}"
  end
  # ...
end
```

---

### WR-06: `Modal.Form.handle_event/2` auto-reset preamble runs *before* the Esc cancel clause, masking subtle state during cancel

**File:** `lib/foglet_bbs/tui/widgets/modal/form.ex:169-190`

**Issue:**
The public entry runs `maybe_auto_reset_submit_state/1` before
`do_handle_event/2` for any non-`:submitting` state. This means that when
the form is in `:saved` or `{:error, _}` and the user presses Esc to
dismiss, the auto-reset to `:idle` happens first, then the cancel callback
fires. The `on_cancel` callback therefore sees a form that has just
silently mutated its `submit_state` even though the user's intent was to
cancel without affecting form state.

In practice this is benign for current callers — the cancel path immediately
discards the form — but it surprises the next reader and undermines the
documented FSM. A clearer design: the lock-guard short-circuit (`:submitting`)
is correct, but the auto-reset should happen lazily on the *next* event
that *would* mutate field state, not on every event including cancel.

**Fix:**
Either document explicitly that auto-reset fires on every non-locked event
(including Esc), or restructure so the auto-reset is folded into the
field-dispatch clause and not into Esc/Tab. A minimal documentation patch
is acceptable:

```elixir
# Auto-reset preamble (Phase 28 D-04) — collapses :saved and {:error, _}
# back to :idle on EVERY non-locked event, including :escape. Cancel
# callbacks observing submit_state will therefore always see :idle.
```

---

_Reviewed: 2026-04-27T18:34:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
