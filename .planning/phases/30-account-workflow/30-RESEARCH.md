# Phase 30: Account Workflow — Research

**Researched:** 2026-04-27
**Domain:** Elixir / Raxol TUI form interaction; Modal.Form substrate consumption; Timex/Tzdata timezone enumeration; OpenSSH key normalization; SSH multi-line paste contract.
**Confidence:** HIGH

## Summary

Phase 30 is a consumption phase that sits on top of an unusually well-developed substrate: Modal.Form (`lib/foglet_bbs/tui/widgets/modal/form.ex`), SmartList (a Foglet wrapper around Raxol's `SelectList` with `enable_search: true`), the existing `:textarea` field type with its `apply_raw_edit/2` raw-value mirror, the in-place modal overlay routing in `app.ex`, and the `Foglet.Accounts.update_profile/2` + `register_ssh_key/2` domain entry points. Almost every primitive Phase 30 needs already exists; the work is fitting them together correctly under five constraints (no new dependency, no timer for the `[Saved]` flash, no domain logic in TUI, 64×22 fits, single-line normalized public_key persistence).

The CONTEXT decisions (D-01..D-20) are correct in intent but contain three factual drift items that the planner must reconcile against the actual code: (1) `Foglet.Accounts.update_preferences/2` and `Foglet.Accounts.get_preferences/1` do not exist — preferences flow through `update_profile/2` with a `:preferences` attrs key and the read-back lives on `user.preferences`; (2) `apply_raw_edit/2`'s `%{key: :enter} -> rv <> "\n"` clause is currently unreachable because Modal.Form's Clause 4 short-circuits Enter before dispatching to the field, so the textarea CANNOT today receive `:enter` events as newline appends; (3) D-13's "filter contract" override is unnecessary — Raxol's `SelectList.filter_options/2` already does case-insensitive substring match. Items (1) and (3) are documentation-only fixes; item (2) is a real Modal.Form behavior gap that the SSH-keys overlay submit contract (Enter submits the form) collides with directly — pasting a multi-line key into a textarea-typed `public_key` field would currently submit on the FIRST embedded `\n` because InputParser converts byte 10 → `%{key: :enter}` and Modal.Form's Clause 4 catches that before the textarea sees it.

**Primary recommendation:** Land the five user-visible behaviors as separate, mostly-orthogonal tasks (internal-title flag, saved flash, timezone SelectList, time_format/theme persistence verification, SSH-keys overlay), and add ONE substrate amendment to Modal.Form: a Clause-4 prelude that routes `:enter` to the field dispatcher (not to submit) when the focused field is `:textarea`. Without that prelude, ACCT-05's "embedded newlines do NOT trigger form submission" acceptance criterion is not achievable with the current codebase.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| `[Saved]` flash render | TUI screen (ProfileForm/PrefsForm) | Account.State (status_message + status_message_seen?) | Presentation concern; status_message already exists on State, just unrendered. |
| `[Saved]` flash clear-on-keystroke | TUI screen (Account.do_handle_key) | Account.State | Clear must be event-driven, not timer-driven (constraint). |
| Internal-title suppression | Modal.Form widget | ProfileForm/PrefsForm/SSH-keys overlay (callers) | Single-source toggle on Modal.Form keeps every tabbed Modal.Form caller consistent; non-tabbed overlays default-on. |
| Timezone selection UI | SmartList (existing widget) | Modal.Form (`:select_list` field type adapter) | Existing widget already does case-insensitive substring filter + pagination; new Modal.Form adapter shape only. |
| Timezone source | `Tzdata.zone_list/0` | Timex (transitive dependency) | SPEC names Tzdata; verified 597 zones in current build (2026b). |
| Timezone validation | Domain (`Foglet.Accounts.User.validate_timezone`) | SelectList constrains to source list | SelectList prevents free-text input by construction; existing changeset validates anyway as defense-in-depth. |
| time_format/theme commit | Phase 28 substrate | Phase 30 verification only | FORM-04/FORM-05 is Phase 28's deliverable; Phase 30 owns ONLY the read-back assertion test. |
| SSH-key overlay add UI | Modal.Form (existing) | Foglet.TUI.Modal (overlay shell, type: :form) | Same overlay mechanism as oneliner post/hide; routing already exists at `app.ex:1585-1614`. |
| Multi-line paste capture | Modal.Form `:textarea` raw_value mirror | InputParser (chunked stream of events) | Paste arrives as a stream of `:char` and `:enter` events; the textarea must accumulate into `raw_value`. |
| OpenSSH normalization | Submit handler (in TUI) | `Foglet.Accounts.SSHKey.changeset` (existing trim) | SPEC line 56 names `String.replace(value, ~r/\s+/, " ") |> String.trim/1`; runs BEFORE the changeset because `compute_fingerprint/1` calls `:ssh_file.decode/2` which expects a well-formed line. |
| Domain persistence | `Foglet.Accounts.update_profile/2`, `register_ssh_key/2` | Repo via `Foglet.Schema` | Both already exist; no domain code in screens. |
| Re-entry hydration | `Account.State.seed_from_user/2` (existing) | `app.ex` `current_user` refresh | Re-runs on tab entry; the manual UAT (D-19) is the only verification step. |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Timex | 3.7.13 (already in mix.exs:67) | IANA timezone validation (`Timex.Timezone.exists?/1`) | Already a dep; `User.validate_timezone/1` and `ClockFormatter` already use it. |
| Tzdata | 1.1.3 (transitive via Timex) | IANA zone enumeration (`Tzdata.zone_list/0` — 597 zones) | Bundled with Timex; SPEC line 82 names it; no new dep. Verified count via `mix run -e`. |
| Raxol `SelectList` | vendored at `vendor/raxol/lib/raxol/ui/components/input/select_list.ex` | Type-ahead filtered list primitive | Already wrapped by Foglet's SmartList; `filter_options/2` is case-insensitive substring (`utils.ex:38-48`). |
| Raxol `MultiLineInput` | vendored | Textarea backing widget | Already used by Modal.Form `:textarea` (form.ex:521-535); known vendor limitation that newlines don't propagate back into `:value` after subsequent edits — Foglet works around with `raw_value` mirror. |

### Supporting (Foglet-owned, already exists)
| Module | Purpose | When to Use |
|--------|---------|-------------|
| `Foglet.TUI.Widgets.Modal.Form` | Stateful form container with submit-state machine | All form rendering — host for the new `internal_title?` flag, `:select_list` field type, and the textarea-Enter prelude. |
| `Foglet.TUI.Widgets.List.SmartList` | Stateful SelectList wrapper with search + pagination | Wrap Tzdata.zone_list/0 for the timezone field. Already used by Sysop. |
| `Foglet.TUI.Widgets.Modal.Form.SubmitStash` | Per-process submit-payload capture | New SSH-keys overlay submit handler — same pattern as `ProfileForm`/`PrefsForm`. |
| `Foglet.TUI.Modal` (overlay struct) | `%Foglet.TUI.Modal{type: :form, message: %ModalForm{}}` | Wraps the new SSH-keys add form so the overlay routing in `app.ex:1585-1614` picks it up. |
| `Foglet.TUI.Theme` slots | Color routing | Every modified render path; never use `IO.ANSI.*` literals. |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Tzdata.zone_list | Hand-rolled IANA zone list constant | Goes stale; SPEC explicitly forbids new dep but Tzdata is transitive — using it is free. |
| Modal.Form `:select_list` adapter | Vendoring Raxol SelectList changes | CONTEXT D-13 floats this; rejected — the existing Raxol substring filter is already exactly what SPEC line 50 specifies. |
| Bracketed paste detection in CLIHandler | Defer (D-03) | In scope only if manual UAT (D-19) reveals real SSH paste fails despite the textarea rendering correctly. ~80 LOC follow-up phase per CONTEXT line 113. |
| New `Foglet.Accounts.update_preferences/2` boundary fn | Reuse `update_profile/2` with `:preferences` attrs | Already wired through `app.ex:1008-1015` and `normalize_account_preferences/1`. CONTEXT references to `update_preferences/2`/`get_preferences/1` are factual drift — the API does not exist. |

**Installation:** No new dependencies. Confirm in mix.lock:
- `timex` 3.7.13 (line 71)
- `tzdata` 1.1.3 (line 73, transitive)

## Architecture Patterns

### System Architecture Diagram

```
SSH bytes (e.g. paste)
     ↓
Erlang :ssh channel  →  Foglet.SSH.CLIHandler.handle_ssh_msg({:data, ...})
     ↓
Raxol.SSH.IOAdapter.parse_input  →  InputParser.parse  (LF→:enter, CR→:enter, printable→:char)
     ↓
[stream of %{key: :char, ...}, %{key: :enter}, %{key: :char, ...} ...]
     ↓
Lifecycle dispatcher cast → App.handle_event/2
     ↓
        ┌───────────────────────────────────────────────────────┐
        │ if state.modal && modal.type == :form  →  modal-form  │
        │ else  →  active-screen handle_key/2                   │
        └───────────────────────────────────────────────────────┘
                  ↓                            ↓
   (overlay path: app.ex:1585)          (screen path: account.ex:93-131)
                  ↓                            ↓
            Modal.Form.handle_event/2          delegate_*_key/3
                  ↓                            ↓
            field dispatch  ←──────────  Modal.Form.handle_event/2
                  ↓
         on_submit → SubmitStash.stash → action :submitted
                  ↓
         caller pops payload → emits {:account_save_profile, _}
         or {:show_modal, _} or domain call (Accounts.register_ssh_key)
                  ↓
         save_account/3 → Accounts.update_profile/2 → Repo.update
                  ↓
         clear_account_save_state → AccountState.seed_from_user
                  ↓
         next render: status_message: "..." → ProfileForm/PrefsForm renders [Saved]
                  ↓
         next user keystroke → Account.do_handle_key sets status_message_seen? → clears
```

### Recommended Project Structure (additions only)

```
lib/foglet_bbs/tui/
├── widgets/modal/form.ex                  # ADD: :internal_title? option, :textarea Enter prelude, :select_list field type
├── screens/account/
│   ├── state.ex                           # ADD: status_message_seen? field; switch :timezone field type to :select_list
│   ├── profile_form.ex                    # ADD: render [Saved] row when status_message non-nil; pass internal_title?: false
│   ├── prefs_form.ex                      # ADD: render [Saved] row; pass internal_title?: false
│   ├── ssh_keys_actions.ex                # CHANGE: a/A handler → emits {:show_modal, ...} instead of SSHKeysState.start_add
│   ├── ssh_keys_overlay.ex                # NEW: builds the Modal.Form for SSH-key add; defines on_submit normalization
│   └── account.ex                         # ADD: status_message clear-on-keystroke logic in do_handle_key
.planning/phases/30-account-workflow/
└── 30-HUMAN-UAT.md                        # NEW: 4 manual SSH/TUI checks at 64×22 and 80×24 (D-19)
test/foglet_bbs/tui/
├── widgets/modal/form_internal_title_test.exs            # NEW (D-20)
└── screens/account/
    ├── prefs_form_test.exs                # NEW (D-20)
    └── ssh_keys_paste_test.exs            # NEW (D-20)
```

### Pattern 1: Modal.Form internal-title suppression flag

**What:** Add `:internal_title?` boolean option to `Modal.Form.init/1` (default `true`). `render/2` consults it before emitting the title row at form.ex:424 and divider at form.ex:425.

**When to use:** Tab-body form callers (ProfileForm, PrefsForm, future Sysop SiteForm) pass `internal_title?: false` so the tab strip's label is not duplicated. Overlay callers (SSH-keys add, oneliner post/hide) keep the default `true` since the centered overlay frame is the title's natural home.

**Example shape:**
```elixir
# In ModalForm.init/1, after Keyword.fetch!(opts, :fields):
internal_title? = Keyword.get(opts, :internal_title?, true)
# stored on the struct
%__MODULE__{
  ...,
  internal_title?: internal_title?
}

# In render/2:
title_rows =
  if state.internal_title? do
    [text(state.title, fg: theme.title.fg, style: [:bold]),
     text(String.duplicate("─", 40), fg: theme.border.fg)]
  else
    []
  end

column [] do
  title_rows ++ field_rows ++ base_error_rows ++ status_rows ++ footer_rows
end
```
Source: derived from existing `Modal.Form.render/2` (form.ex:421-461).

### Pattern 2: `[Saved]` flash without a timer

**What:** State already stores `status_message` (Account.State line 47). After save, `app.ex:1451` sets it to `"Account changes saved."`. The flash currently is invisible because no render path consumes it.

**When to use:** Render the row beneath the Modal.Form output in ProfileForm and PrefsForm. Add `status_message_seen?: false` to State; flip to true on first true input event in `Account.do_handle_key`; clear `status_message` to nil on the same flip so the next render drops the row.

**Example shape:**
```elixir
# In ProfileForm.render/2:
def render(%State{profile_form: form, status_message: msg}, %Theme{} = theme) do
  saved_row =
    case msg do
      nil -> []
      _  -> [text("[Saved]", fg: theme.success.fg)]   # SPEC line 35: literal "[Saved]"
    end

  column style: %{gap: 0} do
    [ModalForm.render(form, theme: theme) | saved_row]
  end
end

# In Account.do_handle_key (or in handle_key prelude):
defp maybe_clear_status_flash(%State{status_message: nil} = ss, _ev), do: ss
defp maybe_clear_status_flash(%State{status_message_seen?: true} = ss, _ev), do: ss
defp maybe_clear_status_flash(%State{} = ss, ev) do
  if true_input_event?(ev) do
    %{ss | status_message: nil, status_message_seen?: true}
  else
    ss
  end
end

# Where true_input_event? matches :char, :backspace, :enter, :tab, :shift_tab,
# :backtab, :escape, :up, :down, :left, :right (NOT :resize, :window, :idle).
```
Source: spec'd inline; modeled after CONTEXT D-09.

### Pattern 3: `:select_list` field type for Modal.Form

**What:** Add a new field type that wraps `Foglet.TUI.Widgets.List.SmartList` initialized with `enable_search: true`. `dispatch_to_field/3` forwards events to the wrapped SmartList; on `{:item_selected, value}` action, captures the value into the field's draft state. `coerce/2` returns the captured value (or `nil` if nothing selected yet — fall back to the spec's `:value`).

**When to use:** Any Modal.Form field whose source is a long enumerable best searched by substring (timezone, future user lookup, future board picker).

**Example shape:**
```elixir
defp build_field_state(%{type: :select_list} = spec) do
  options = Map.get(spec, :options, [])           # [{label, value}] tuples
  initial = Map.get(spec, :value)                 # current saved value or nil

  smart_list = SmartList.init(
    options: options,
    enable_search: true,
    page_size: Map.get(spec, :page_size, 8)       # 64x22 budget — cap visible rows
  )

  %{smart_list: smart_list, value: initial}
end

defp dispatch_to_field(%{type: :select_list}, %{smart_list: sl, value: v} = fs, event) do
  {new_sl, action} = SmartList.handle_event(event, sl)

  case action do
    {:item_selected, picked} -> %{fs | smart_list: new_sl, value: picked}
    _other                   -> %{fs | smart_list: new_sl}
  end
end

defp coerce(%{type: :select_list}, %{value: v}), do: v

defp render_widget(%{type: :select_list}, %{smart_list: sl}, _focused?, theme) do
  SmartList.render(sl, theme: theme)
end
```
Source: composed from `Modal.Form.dispatch_to_field/3` (form.ex:537-595) and `SmartList.handle_event/2` (smart_list.ex:117-132).

**Tab order:** SmartList consumes typed `:char` events as search input. To leave the field, the user presses Tab (Modal.Form Clause 3 line 264 catches Tab BEFORE dispatch_to_field, so this works automatically). Up/Down on `:select_list` should NOT advance form focus — they navigate the SmartList. Add a clause to Modal.Form's Clause 4b/4c (form.ex:295-317) so `:up`/`:down` on `:select_list` falls through to `dispatch_event_to_field` rather than moving focus. This mirrors how `:enum` already behaves.

### Pattern 4: Modal.Form `:textarea` Enter prelude (CRITICAL substrate amendment)

**What:** Modal.Form's Clause 4 (`%{key: :enter}`, form.ex:277-288) currently triggers submit-on-last-field unconditionally. When the focused field is `:textarea`, Enter must INSTEAD insert a newline into the field's `raw_value` and forward `{:enter}` to MultiLineInput — never trigger submit, never advance focus.

**Why:** ACCT-05 acceptance "embedded newlines during paste do NOT trigger form submission" (SPEC line 105) is otherwise unachievable. Pasted content from Erlang `:ssh` arrives as a stream of `:char` and `:enter` events (LF byte → `:enter` per `deps/raxol_terminal/lib/raxol/terminal/ansi/input_parser.ex:131`). The first `:enter` in the stream would submit the half-built form.

**Where:** New clause in Modal.Form `do_handle_event/2`, placed BEFORE Clause 4 so it intercepts:

```elixir
# Clause 3.5 (NEW): Enter on textarea — never submit, always insert newline.
defp do_handle_event(%__MODULE__{} = state, %{key: :enter} = event) do
  case Enum.at(state.fields, state.focus_index) do
    %{type: :textarea} ->
      dispatch_event_to_field(event, state)         # routes to apply_raw_edit + MLI {:enter}

    _other ->
      # fall through to Clause 4 (advance focus or submit)
      do_handle_enter_default(state)
  end
end
```

Once this prelude exists, the existing `apply_raw_edit/2` clause `defp apply_raw_edit(rv, %{key: :enter}), do: rv <> "\n"` (form.ex:675) becomes reachable and does what the CONTEXT D-03 already assumed it did.

**How submit happens with a `:textarea` last field:** With this prelude, Enter on a focused textarea no longer submits even when it's the last field. The user submits via Tab-to-cycle-back-to-a-non-textarea-field-then-Enter, or a dedicated submit gesture. For the SSH-keys overlay, the natural choice is `Ctrl+Enter` or having `label` be the last field (Tab order: public_key first, label last; submit when on label). The CONTEXT D-02 has fields in `[label, public_key]` order — keep that, BUT note that with public_key as last and `:textarea`, the user must Tab back to `label` to submit. SPEC's UAT says "pressing Enter after paste persists a single-line value" (line 56) — this works only if `label` is last and the user has tabbed to it. Planner: **invert CONTEXT D-02 field order to `[public_key, label]` (public_key first, label last) so Enter on the label fires submit**, OR introduce a Ctrl+Enter submit affordance. Recommendation: invert order — Ctrl+Enter is a new keybind not advertised anywhere else.

Source: derived from form.ex:277-322; alternative approaches in "Open Questions" below.

### Pattern 5: SSH-keys overlay routing (extending app.ex:1585-1614)

**What:** The existing `:form` modal dispatcher hardcodes two stash keys (oneliner / hide-oneliner). Add a third branch for the SSH-keys add submit, OR — preferred — generalize the dispatch using `SubmitStash.with_stashed/2` keyed by the calling overlay's module.

**When to use:** When the SSH-keys add overlay submits, the payload `%{label: ..., public_key: ...}` arrives via `SubmitStash.stash(__MODULE__, payload)`. The dispatcher pops it, normalizes `public_key` per SPEC line 56 (`String.replace(public_key, ~r/\s+/, " ") |> String.trim/1`), calls `Foglet.Accounts.register_ssh_key/2`, and on success closes the overlay; on `{:error, changeset}` keeps overlay open and uses `Modal.Form.set_errors/2` (form.ex:354-358).

**Example dispatcher generalization:**
```elixir
# In handle_modal_key(:form, _, _) — replace the two hardcoded take_*_submit calls:
case action do
  :submitted ->
    case SubmitStash.pop(state.modal.message.__overlay_owner__) do  # see note below
      nil -> {state, []}
      {:ssh_keys, payload}    -> do_update({:submit_ssh_key_add, payload}, state)
      {:oneliner, payload}    -> do_update({:submit_oneliner, payload}, state)
      {:hide_oneliner, p}     -> do_update({:submit_hide_oneliner, p}, state)
    end

  :cancelled -> do_update(:dismiss_modal, state)
  _other     -> {state, []}
end
```
The `__overlay_owner__` field is a small adapter — alternatively, store the payload tuple shape `{kind, payload}` directly (as ProfileForm/PrefsForm already do — see `profile_form.ex:45` `{:profile, payload}`). Recommendation: copy that pattern verbatim — `on_submit: fn p -> SubmitStash.stash(__MODULE__, {:ssh_keys, p}) end`, dispatcher does `SubmitStash.pop(SSHKeysOverlay)` (or per-module) and pattern-matches the kind tag.

Source: app.ex:1585-1614, profile_form.ex:39-69, prefs_form.ex:41-83.

### Anti-Patterns to Avoid

- **Adding a `:multiline_text` field type for the public_key field.** Don't — `:textarea` already exists, has the `raw_value` mirror, and is exercised by Sysop boards_view. Reuse it.
- **Bracketed-paste detection in CLIHandler in this phase.** CONTEXT D-03 explicitly defers this. The textarea + raw_value mirror is the contract; if real SSH paste fails at UAT, file a follow-up phase.
- **Hand-rolled timezone validator.** `Timex.Timezone.exists?/1` already exists; SelectList constrains input by construction so most validation is structural.
- **Calling `Foglet.Accounts.update_preferences/2`.** It does not exist. Use `update_profile/2` with `:preferences` in attrs (the path `app.ex:1008-1014` already uses).
- **A timer for the `[Saved]` flash.** Constraint line 83 forbids it. Use the `status_message_seen?` keystroke-clear pattern.
- **Suppressing the internal title row globally.** Constraint line 85 requires non-tabbed callers (Login, oneliner overlays) keep the default. Make the option opt-in per call site.
- **Hardcoding color atoms in modified Account paths.** Constraint line 84. Route through `Foglet.TUI.Theme` slots.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| IANA zone list | Static module attribute or fetch from JSON | `Tzdata.zone_list/0` | Bundled with Timex; updates with the dep; 597 zones in current build. |
| Type-ahead substring filter for SelectList | Custom filter loop | Raxol's built-in `filter_options/2` | Already case-insensitive substring (`utils.ex:38-48`). |
| Per-process submit payload capture | `Process.put`/`get` directly | `Foglet.TUI.Widgets.Modal.Form.SubmitStash` | Centralizes key shape; `with_stashed/2` guarantees cleanup on raise. |
| Overlay framing for SSH-keys add | Custom centered box | `%Foglet.TUI.Modal{type: :form, message: %ModalForm{}}` | Routes through `app.ex:1585-1614` automatically. |
| OpenSSH key parsing for fingerprint | Hand-rolled parser | `:ssh_file.decode/2` (called by `Foglet.Accounts.SSHKey.compute_fingerprint/1`) | Already wired; uses OTP's primitives. |
| Saved-status row primitive | New widget | Plain `text("[Saved]", fg: theme.success.fg)` row appended below `ModalForm.render/2` output | The flash is one row of theme-routed text, not a widget. |
| Timezone changeset validation | Defer to SelectList | Existing `User.validate_timezone/1` | Catches bad values from any future free-text path; SelectList constrains the UI. |

**Key insight:** The phase reads as "build five things" but is really "wire five things" — every primitive exists. The only NEW substrate is (a) the `:internal_title?` flag, (b) the `:select_list` field type adapter, and (c) the `:textarea` Enter prelude. Everything else is consumption.

## Common Pitfalls

### Pitfall 1: Modal.Form Clause 4 swallows Enter before textarea sees it
**What goes wrong:** Pasting a multi-line OpenSSH key submits the form on the first embedded `\n` because InputParser converts byte 10 → `%{key: :enter}` and Modal.Form's Clause 4 (form.ex:277-288) catches Enter unconditionally.
**Why it happens:** Existing textarea callers in Sysop never put `:textarea` last AND never paste multi-line content, so the issue has never surfaced.
**How to avoid:** Add the Pattern 4 prelude. Before Clause 4 fires, check the focused field type; if `:textarea`, dispatch the event to the field instead of the submit/advance branch.
**Warning signs:** Test that pastes `"ssh-ed25519\nAAAA…\nuser@host"` and expects `raw_value` to contain all three segments — without the prelude, only `"ssh-ed25519"` lands and the form submits.

### Pitfall 2: `apply_raw_edit/2` `:enter` clause is currently dead code
**What goes wrong:** Reading form.ex:675 gives the impression that `:enter` events accumulate `\n` into `raw_value`. They don't — Clause 4 short-circuits before this code path runs. The CONTEXT D-03 statement that "the textarea's existing apply_raw_edit/2 accumulates :enter and :char "\n" events into the buffer — that is the contract this phase commits to" is incorrect for the current codebase.
**Why it happens:** The `:enter` clause was likely added speculatively or for a future use. Today `:char "\n"` (form.ex:574) is reachable when codepoint events stream in (e.g., test harnesses), but `:enter` is not.
**How to avoid:** Either (a) land the Pattern 4 prelude (preferred), or (b) explicitly exercise `apply_raw_edit/2` via codepoint streams in tests and accept that the textarea will only accumulate newlines from `\n`-character paste, not from terminal-translated Enter events. (b) is fragile — terminals normalize CR/LF differently.

### Pitfall 3: Textarea last + Enter-to-submit is a UX dead-end
**What goes wrong:** With Pattern 4 in place, Enter on the focused `:textarea` ALWAYS inserts a newline. If `:textarea` is the LAST field, the user has no Enter-to-submit path on it — they must Tab to a non-textarea last field.
**Why it happens:** CONTEXT D-02 places fields in `[label, public_key]` order, making `:textarea` last.
**How to avoid:** Invert field order to `[public_key, label]`. Now `label` (a `:text`) is last; Enter on `label` submits. The user pastes the key (Tab away if needed, or stay on public_key — Enter no longer hijacks paste); types the label; presses Enter. Bonus: visual order matches how `ssh-keygen` output reads (key first, comment last).
**Warning signs:** Modal.Form FORM-04 routing tests must confirm Tab order matches the field declaration order.

### Pitfall 4: SelectList consumes typed characters as search; Tab is the only way out
**What goes wrong:** While the timezone SelectList is focused, every typed character lands in the search buffer (this is desired). But the user must press Tab to move focus to the next field. Up/Down navigates inside the list (also desired). On most-recently-saved value, focusing the field should re-open the SelectList with that value pre-selected.
**Why it happens:** `Raxol.SelectList.handle_event/3` claims `:char` events; SmartList preserves that behavior.
**How to avoid:** Verify in tests that (a) Tab from focused SelectList moves to next form field, (b) Up/Down on focused SelectList does NOT advance form focus_index — needs an explicit Modal.Form Clause 4b/4c addition for `:select_list`, mirroring `:enum`. Without that addition, Up/Down on the SelectList field would move focus AND fail to navigate the list.
**Warning signs:** Test that Up on a focused timezone field with `Etc/UTC` saved keeps focus on `:timezone` and moves the highlighted row in the list.

### Pitfall 5: Saved-flash clear-on-keystroke must skip non-input events
**What goes wrong:** If `status_message_seen?` flips on EVERY event, a `:resize` or `:idle` event clears the flash before the user has seen it.
**Why it happens:** Raxol delivers a wide event surface; not all events represent user input.
**How to avoid:** CONTEXT D-09 names the inclusion list explicitly: `:char`, `:backspace`, `:enter`, arrow keys, `:tab`, `:escape`, `:shift_tab`, `:backtab`. NOT `:resize`, `:window`, `:idle`, PubSub-delivered events. Implement `true_input_event?/1` in Account state or screen module and gate the flag flip on it.
**Warning signs:** Test that resize events don't clear the flash; test that the FIRST keystroke of any kind in the inclusion list does.

### Pitfall 6: Re-entry hydration depends on `current_user` being refreshed
**What goes wrong:** If `state.current_user` is not refreshed after `Repo.update`, leaving Account and re-entering shows the OLD field values because `seed_from_user/2` reads from a stale struct.
**Why it happens:** Elixir structs are immutable; the post-save reload at `app.ex:1407` (`Map.put(:current_user, updated_user)`) is what makes re-entry work.
**How to avoid:** This is already handled correctly in the codebase. The manual UAT (D-19) is the only verification — the CONTEXT explicitly accepts that no automated integration test covers this end-to-end and lets human SSH/TUI testing catch a regression.
**Warning signs:** None automated. UAT step (a→f) at SPEC lines 36-37 is the single check.

### Pitfall 7: OpenSSH key normalization MUST run before the changeset
**What goes wrong:** `Foglet.Accounts.SSHKey.changeset/2` passes the value to `compute_fingerprint/1` (ssh_key.ex:53-66) which calls `:ssh_file.decode/2`. That decoder is permissive but has subtle whitespace expectations — leading/trailing OK (the trim is there), but internal whitespace runs (e.g., `algorithm \n base64 \n  comment` with multi-space after newline) may produce `[]` (empty list) and a "invalid OpenSSH public key: empty" error.
**Why it happens:** The decoder expects either a single line or a properly-canonical multi-line PEM-style block; arbitrary whitespace runs from a paste-then-trim path don't match either.
**How to avoid:** Run SPEC line 56's normalization (`String.replace(value, ~r/\s+/, " ") |> String.trim/1`) in the SSH-keys overlay submit handler BEFORE constructing the changeset. CONTEXT D-02 already specifies this. Confirm with a test that pastes `"ssh-ed25519\n  \nAAAA...\n   user@host"` and asserts the persisted value is `"ssh-ed25519 AAAA... user@host"` byte-for-byte.
**Warning signs:** Test asserts `Foglet.Accounts.SSHKey.compute_fingerprint/1` returns `{:ok, "SHA256:..."}` against the normalized text but `{:error, ...}` against the un-normalized multi-line input.

### Pitfall 8: Tabbed Modal.Form callers may not be the only `internal_title?: false` consumers
**What goes wrong:** ACCT-02 names PROFILE, PREFERENCES, and SSH KEYS. The new SSH-keys add OVERLAY (Modal.Form embedded in a centered overlay) is NOT a tabbed caller — its title row is correct because the overlay frame doesn't supply a heading.
**Why it happens:** "Tabbed inline" vs "centered overlay" are different containers; the rule is about NOT duplicating a heading the surrounding container already shows.
**How to avoid:** CONTEXT D-07 already gets this right — overlay callers default `true`, tabbed inline callers pass `false`. Don't accidentally pass `internal_title?: false` to the SSH-keys overlay just because it's "an SSH keys form."
**Warning signs:** Visual UAT — the SSH-keys add overlay should have an "Add SSH Key" title row at the top of the centered box; PROFILE/PREFERENCES/SSH KEYS tabs should not.

### Pitfall 9: 64×22 budget for the timezone SelectList
**What goes wrong:** With 597 zones, the SelectList page_size + chrome (border + search row + pagination row) must fit in the PREFERENCES tab body height at 64×22.
**Why it happens:** Account screen frame consumes 4 columns of horizontal padding (account.ex:137 `inner_width = w - 4`); height budget is similarly tight after tab strip + key bar + Modal.Form fields above the timezone field.
**How to avoid:** Cap SmartList `:page_size` to ~5-6 entries. Verify via `mix foglet.tui.render preferences --width 64 --height 22` (existing renderer per AGENTS.md line 197). UAT bullet at SPEC line 51 covers this.
**Warning signs:** SelectList overflows below the key bar at 64×22.

## Runtime State Inventory

> Phase 30 is a feature/refactor phase, not a rename. Most categories don't apply. Documenting explicitly per protocol.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — no schema changes; no migration. `users.preferences` JSONB key remains `"time_format"`; `users.timezone` and `users.theme` remain string columns; `ssh_keys.public_key` remains a single `:string` column. | None. |
| Live service config | None — no Config keys added or renamed; no operator-facing settings change. | None. |
| OS-registered state | None — no daemons, scheduled tasks, or external services touched. | None. |
| Secrets/env vars | None — no new env vars; no SOPS keys touched. | None. |
| Build artifacts | None — no new compiled deps; vendored Raxol unchanged. | None. |

**Nothing found in any category** — verified by reading `lib/foglet_bbs/accounts.ex`, `lib/foglet_bbs/accounts/user.ex`, `lib/foglet_bbs/accounts/ssh_key.ex`, and the SPEC's "Constraints" section (line 87 confirms no migration).

## Code Examples

Verified patterns from the actual Foglet codebase:

### Pattern: Modal.Form on_submit + SubmitStash + screen handler
```elixir
# Source: lib/foglet_bbs/tui/screens/account/state.ex:188-204 (for ProfileForm)
# Reuse this exact shape for the SSH-keys overlay.
defp build_profile_form(draft) do
  ModalForm.init(
    title: "Profile",
    fields: [
      %{name: :location, type: :text, label: "Location", value: draft.location || ""},
      ...
    ],
    on_submit: fn payload -> SubmitStash.stash(__MODULE__, {:profile, payload}) end,
    on_cancel: fn -> :ok end
  )
end

# Source: lib/foglet_bbs/tui/screens/account/profile_form.ex:39-69
# Pop pattern in the screen's handle_key:
defp do_handle_key(event, %State{profile_form: form} = state, current_user) do
  {new_form, action} = ModalForm.handle_event(event, form)
  state = %{state | profile_form: new_form}

  case action do
    :submitted ->
      {:profile, payload} = SubmitStash.pop(__MODULE__)
      attrs = %{location: payload.location, ...}
      {:ok, %{state | ...}, [{:account_save_profile, attrs}]}

    :cancelled -> ...
    _ -> ...
  end
end
```

### Pattern: Modal overlay dispatch
```elixir
# Source: lib/foglet_bbs/tui/app.ex:625-654 (Post Oneliner overlay)
# Mirror this for the SSH-keys add overlay — replace fields and on_submit.
defp do_update({:open_post_oneliner_modal}, state) do
  form = ModalForm.init(
    title: "Post Oneliner",
    fields: [%{name: :body, type: :text, label: "Oneliner", max_length: 120}],
    on_submit: &stash_oneliner_submit/1,
    on_cancel: fn -> :dismiss_modal end
  )
  modal = %Foglet.TUI.Modal{type: :form, title: "Post Oneliner", message: form}
  {%{state | current_screen: :main_menu, modal: modal}, []}
end
```

### Pattern: Re-entry hydration via seed_from_user
```elixir
# Source: lib/foglet_bbs/tui/screens/account/state.ex:106-122
# Already wired correctly — Phase 30 only verifies via manual UAT.
def seed_from_user(%__MODULE__{} = state, user) do
  pd = profile_draft(user)
  prd = prefs_draft(user)

  %{state |
    profile_draft: pd,
    prefs_draft: prd,
    profile_form: build_profile_form(pd),
    prefs_form: build_prefs_form(prd),
    ...
  }
end
```

### Pattern: SmartList init + handle_event
```elixir
# Source: lib/foglet_bbs/tui/widgets/list/smart_list.ex:82-132
# Use this shape inside the new :select_list field type:
smart_list = SmartList.init(
  options: Enum.map(Tzdata.zone_list(), fn z -> {z, z} end),  # {label, value}
  enable_search: true,
  page_size: 6
)

# In dispatch_to_field:
{new_sl, action} = SmartList.handle_event(event, smart_list)
case action do
  {:item_selected, value} -> # capture into field state
  {:search_changed, _term} -> # no-op for the field; the search is internal
  _ -> :ok
end
```

### Pattern: Existing OpenSSH fingerprint flow (do not modify)
```elixir
# Source: lib/foglet_bbs/accounts/ssh_key.ex:36-44, 53-66
# Already correct; the Phase 30 normalization runs BEFORE this is called.
def changeset(ssh_key, attrs) do
  ssh_key
  |> cast(attrs, [:label, :public_key])
  |> validate_required([:label, :public_key])
  |> validate_length(:label, min: 1, max: 64)
  |> put_fingerprint()                      # internally calls compute_fingerprint
  |> unique_constraint(:fingerprint)
  |> unique_constraint(:label, name: :ssh_keys_user_id_label_index)
end
```

### Pattern: InputParser byte → event conversion (informational)
```elixir
# Source: deps/raxol_terminal/lib/raxol/terminal/ansi/input_parser.ex:129-148
# Documents WHY paste arrives as a stream of :char + :enter events.
# Pasted bytes are not bracketed; LF (10) and CR (13) both produce :enter events.
defp parse_one(<<13, rest::binary>>), do: {key_event(:enter), rest}     # CR
defp parse_one(<<10, rest::binary>>), do: {key_event(:enter), rest}     # LF
defp parse_one(<<127, rest::binary>>), do: {key_event(:backspace), rest}
defp parse_one(<<9, rest::binary>>), do: {key_event(:tab), rest}
defp parse_one(<<char, rest::binary>>) when char >= 32 and char <= 126 do
  {key_event(:char, char: <<char>>), rest}
end
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Hand-rolled SSH-keys add form (`SSHKeysState`/`SSHKeysActions` `:add` mode + `SSHKeysSurface.maybe_form/2`) | Modal.Form overlay activated via `a`/`A` keybind on the SSH KEYS list | Phase 30 (D-01) | Removes char-by-char input handler; makes paste possible; consistent with Profile/Prefs/Sysop forms. |
| Free-text timezone TextInput | SelectList over `Tzdata.zone_list/0` with substring filter | Phase 30 (D-11..D-15) | Eliminates "type the full IANA name from memory" failure mode. |
| Invisible `state.status_message` | Inline `[Saved]` row in ProfileForm/PrefsForm, cleared on next keystroke | Phase 30 (D-08, D-09) | First user-visible save confirmation; honors no-timer constraint. |
| Modal.Form always emits internal title row | `:internal_title?` opt-in flag (default `true`) | Phase 30 (D-05) | Removes duplicate heading inside tab bodies; non-tabbed callers unchanged. |

**Deprecated/outdated:**
- `Foglet.TUI.Screens.Account.SSHKeysState.start_add/1` (state.ex:91-100) and `cancel_add/1` (line 102-105) — after Phase 30 these become unreachable; planner should decide whether to delete or leave dormant for tests.
- `SSHKeysState.toggle_focus/1`, `put_focused_value/2`, `append_focused/2`, `backspace_focused/1` (lines 107-126) — unreachable once add-mode goes through Modal.Form.
- `SSHKeysActions.handle_key/3` clauses for `mode: :add` (`:tab`, `:enter`, `:escape`, `:backspace`, char appending — lines 83-96) — the `mode: :add` branch is removed; only the `:list` clauses remain.

## Project Constraints (from CLAUDE.md / AGENTS.md)

These constrain plan-phase output. Quoted/paraphrased from `AGENTS.md`:

- **Use `rtk` as the shell command prefix** in this repo (e.g., `rtk mix test`, `rtk git status`).
- **Foglet.* is the application/domain namespace.** TUI screens consume contexts; domain logic stays in `Foglet.Accounts`. Phase 30 calls `Foglet.Accounts.update_profile/2` and `Foglet.Accounts.register_ssh_key/2` only.
- **`FogletBbs.*` and `FogletBbsWeb.*` are Phoenix infrastructure.** No Phase 30 code touches them.
- **Programmatically set foreign keys on structs before changeset construction.** `register_ssh_key/2` already does this (`%SSHKey{user_id: user.id} |> SSHKey.changeset(attrs)` — accounts.ex:458-462). Don't add `user_id` to `cast/3`.
- **Stateful widgets follow `init/1 + handle_event/2 + render/2`.** Modal.Form already does; SmartList already does. New `:select_list` field type adapter follows the same shape.
- **Color decisions route through `Foglet.TUI.Theme` slots.** No `IO.ANSI.*` literals in modified Account paths (Constraint line 84).
- **Avoid `Process.sleep/1` and `Process.alive?/1` in tests.** Use `start_supervised!/1`, monitors, or `:sys.get_state/1`.
- **Run `rtk mix precommit` when code changes are complete.** Compile-with-warnings-as-errors, formatter, Credo, Sobelow, Dialyzer.
- **Read `docs/raxol/getting-started/WIDGET_GALLERY.md` and `lib/foglet_bbs/tui/widgets/README.md`** before TUI/widget work.
- **64×22 is the hard minimum terminal size; 80×24 is compact target.** Constraint line 81.
- **`[Saved]` flash MUST NOT use a timer.** Constraint line 83.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | ExUnit (Elixir 1.18+ / OTP 27); part of `mix test` |
| Config file | `mix.exs` (test_paths default `["test"]`) |
| Quick run command | `rtk mix test test/foglet_bbs/tui/screens/account_test.exs --max-failures 5` |
| Full suite command | `rtk mix precommit` (compile + format + credo + sobelow + dialyzer + test) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| ACCT-01 | `[Saved]` row visible after Profile submit; clears on next keypress | unit (TUI render) | `rtk mix test test/foglet_bbs/tui/screens/account_test.exs --only acct_01` | partial — `account_test.exs` exists (1000+ lines), but no `[Saved]` flash test. NEW test cases needed. |
| ACCT-01 | Re-entry after Profile save shows persisted values | manual UAT only (D-10, D-19) | n/a — recorded in `30-HUMAN-UAT.md` | ❌ Wave 0 — `30-HUMAN-UAT.md` does not exist. |
| ACCT-02 | No internal title row in PROFILE/PREFERENCES/SSH KEYS tab bodies; non-tabbed callers retain default | unit (Modal.Form render with both option values) | `rtk mix test test/foglet_bbs/tui/widgets/modal/form_internal_title_test.exs` | ❌ Wave 0 — D-20 names this file. |
| ACCT-02 | Login screen (non-tabbed Modal.Form caller) regression — title row still rendered | unit | same as above (regression case in same file) | ❌ Wave 0 |
| ACCT-03 | time_format RadioGroup change persists end-to-end (read-back via `user.preferences["time_format"]`) | integration (DB-backed) | `rtk mix test test/foglet_bbs/tui/screens/account/prefs_form_test.exs --only acct_03_time_format` | ❌ Wave 0 — D-20 names this file. |
| ACCT-03 | theme RadioGroup change persists end-to-end (read-back via `user.theme`) | integration | `rtk mix test test/foglet_bbs/tui/screens/account/prefs_form_test.exs --only acct_03_theme` | ❌ Wave 0 |
| ACCT-03 | `:checkbox` field type smoke render does not raise | unit | `rtk mix test test/foglet_bbs/tui/screens/account/prefs_form_test.exs --only acct_03_checkbox` | ❌ Wave 0 |
| ACCT-04 | Timezone SelectList opens with saved value | unit (TUI render) | `rtk mix test test/foglet_bbs/tui/screens/account/prefs_form_test.exs --only acct_04_open` | ❌ Wave 0 |
| ACCT-04 | Typing `lon` filters to zones containing `lon` (case-insensitive); `Europe/London` is in the filtered set | unit | `rtk mix test test/foglet_bbs/tui/screens/account/prefs_form_test.exs --only acct_04_filter` | ❌ Wave 0 |
| ACCT-04 | Selecting `Europe/London` and submitting persists `Europe/London` (read-back via `user.timezone`) | integration | `rtk mix test test/foglet_bbs/tui/screens/account/prefs_form_test.exs --only acct_04_persist` | ❌ Wave 0 |
| ACCT-04 | Clearing field and selecting `Asia/Tokyo` persists `Asia/Tokyo` | integration | `rtk mix test test/foglet_bbs/tui/screens/account/prefs_form_test.exs --only acct_04_clear` | ❌ Wave 0 |
| ACCT-04 | SelectList fits within 64×22 PREFERENCES tab body | manual UAT (renderer or live SSH) | `rtk mix foglet.tui.render preferences --width 64 --height 22`; visual inspection in `30-HUMAN-UAT.md` | ❌ Wave 0 |
| ACCT-05 | Multi-line OpenSSH key paste accumulates in `:public_key` field's `raw_value`; embedded `:enter` does not submit | unit (codepoint stream into Modal.Form) | `rtk mix test test/foglet_bbs/tui/screens/account/ssh_keys_paste_test.exs --only acct_05_paste` | ❌ Wave 0 |
| ACCT-05 | After Enter-to-submit, persisted `public_key` is single-line normalized (byte-for-byte against expected string) | integration | `rtk mix test test/foglet_bbs/tui/screens/account/ssh_keys_paste_test.exs --only acct_05_normalize` | ❌ Wave 0 |
| ACCT-05 | SSH-keys list shows new key with truncated/elided preview at 64×22 after add | manual UAT | `30-HUMAN-UAT.md` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `rtk mix test test/foglet_bbs/tui/screens/account_test.exs test/foglet_bbs/tui/widgets/modal/form_test.exs --max-failures 3`
- **Per wave merge:** `rtk mix test test/foglet_bbs/tui/screens/account test/foglet_bbs/tui/widgets/modal --max-failures 5`
- **Phase gate:** `rtk mix precommit` green; `30-HUMAN-UAT.md` checks recorded.

### Wave 0 Gaps
- [ ] `test/foglet_bbs/tui/widgets/modal/form_internal_title_test.exs` — internal_title? on/off rendering + Login regression check (D-20).
- [ ] `test/foglet_bbs/tui/screens/account/prefs_form_test.exs` — timezone SelectList + time_format/theme persistence + checkbox smoke (D-20).
- [ ] `test/foglet_bbs/tui/screens/account/ssh_keys_paste_test.exs` — codepoint-stream paste through the overlay; byte-for-byte normalization assertion (D-20).
- [ ] `.planning/phases/30-account-workflow/30-HUMAN-UAT.md` — four manual SSH/TUI checks at 64×22 and 80×24 (D-19).

(Existing infrastructure that does NOT need changes: `mix.exs`, `test/test_helper.exs`, `test/foglet_bbs/tui/widgets/modal/form_test.exs` — extends; `test/foglet_bbs/tui/screens/account_test.exs` — extends.)

## Security Domain

> Per project default: `security_enforcement` is enabled (no override in `.planning/config.json`).

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | yes (indirectly) | `Foglet.Accounts.Auth.authenticate_by_public_key/1` is the consumer of the persisted `public_key`; this phase's normalization MUST preserve fingerprint compatibility (the SHA256 over the decoded key bytes). |
| V3 Session Management | no | Phase 30 does not touch session lifecycle. |
| V4 Access Control | yes (low impact) | The SSH-keys add overlay calls `Foglet.Accounts.register_ssh_key/2` which already scopes to `%User{} = user` (the actor); no new scope shape. |
| V5 Input Validation | yes | `public_key` normalization (`String.replace(~r/\s+/, " ") |> String.trim/1`) followed by `:ssh_file.decode/2` validation in `compute_fingerprint/1`. Timezone constrained by SelectList source list. time_format / theme constrained by `:enum` choices. |
| V6 Cryptography | yes (consumer only) | `:ssh.hostkey_fingerprint(:sha256, key)` is OTP's primitive — never hand-roll. Already used. |

### Known Threat Patterns for Foglet/Elixir TUI

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Pasted public_key with embedded null bytes / control chars | Tampering / Input Validation | InputParser drops bytes < 32 except CR/LF/TAB/BS; the `~r/\s+/` collapse normalizes any tabs/CRs/LFs to single spaces. |
| Fingerprint collision via leading/trailing whitespace bypass | Tampering | `compute_fingerprint/1` already trims; `unique_constraint(:fingerprint)` catches collisions. The Phase 30 normalization runs BEFORE this so collisions are detected on the canonical form. |
| Submitting an `Etc/UTC` bypass via crafted timezone string | Spoofing | Not possible — SelectList constrains input to source list members; `User.validate_timezone/1` is defense-in-depth. |
| Cross-user SSH-key registration (registering someone else's key) | Spoofing | `register_ssh_key/2` always uses the actor's `user_id`; not configurable from the form. |
| `[Saved]` flash leaking sensitive data | Information Disclosure | Flash text is the literal `"[Saved]"` (SPEC line 35); no field values are rendered into it. |

## Sources

### Primary (HIGH confidence)
- **In-tree code, verified by reading:**
  - `lib/foglet_bbs/tui/widgets/modal/form.ex` — Modal.Form substrate (681 lines)
  - `lib/foglet_bbs/tui/widgets/list/smart_list.ex` — SelectList wrapper (314 lines)
  - `lib/foglet_bbs/tui/screens/account.ex` — Account shell screen (315 lines)
  - `lib/foglet_bbs/tui/screens/account/state.ex` — Account.State (242 lines)
  - `lib/foglet_bbs/tui/screens/account/profile_form.ex` — ProfileForm (75 lines)
  - `lib/foglet_bbs/tui/screens/account/prefs_form.ex` — PrefsForm (97 lines)
  - `lib/foglet_bbs/tui/screens/account/ssh_keys_state.ex` — SSHKeysState (199 lines)
  - `lib/foglet_bbs/tui/screens/account/ssh_keys_actions.ex` — SSHKeysActions (117 lines)
  - `lib/foglet_bbs/tui/widgets/modal/form/submit_stash.ex` — SubmitStash helper (62 lines)
  - `lib/foglet_bbs/tui/widgets/compose.ex` — translate_key (control codepoint filter at line 88-93)
  - `lib/foglet_bbs/tui/widgets/modal.ex` — overlay render dispatch (line 45-47)
  - `lib/foglet_bbs/tui/app.ex:1-1655` — overlay routing, save_account, modal-form dispatcher
  - `lib/foglet_bbs/accounts.ex:338-476` — update_profile, register_ssh_key, list_ssh_keys, revoke_ssh_key
  - `lib/foglet_bbs/accounts/ssh_key.ex` — changeset + compute_fingerprint
  - `lib/foglet_bbs/accounts/user.ex:265-272` — validate_timezone (Timex)
  - `lib/foglet_bbs/ssh/cli_handler.ex` — SSH lifecycle (no bracketed paste detection)
  - `vendor/raxol/lib/raxol/ssh/io_adapter.ex` — parse_input delegation
  - `deps/raxol_terminal/lib/raxol/terminal/ansi/input_parser.ex` — byte-to-event mapping
  - `vendor/raxol/lib/raxol/ui/components/input/select_list.ex` and `.../select_list/utils.ex:38-48` — case-insensitive substring filter
  - `mix.lock:71,73` — Timex 3.7.13, Tzdata 1.1.3
- **Tzdata zone count verified empirically:** `rtk mix run -e 'IO.puts(length(Tzdata.zone_list()))'` → 597 (2026b release).
- **Spec/Context:**
  - `.planning/phases/30-account-workflow/30-SPEC.md` — locked requirements
  - `.planning/phases/30-account-workflow/30-CONTEXT.md` — D-01..D-20 implementation decisions
  - `.planning/REQUIREMENTS.md:46-50` — ACCT-01..05 statements

### Secondary (MEDIUM confidence)
- AGENTS.md — project conventions (TUI architecture, contexts, widget rules)
- `lib/foglet_bbs/tui/widgets/README.md` — widget catalog
- `.planning/STATE.md` — milestone state, no relevant blockers

### Tertiary (LOW confidence)
- None — every load-bearing claim was verified by reading the named source file.

## Assumptions Log

> Every claim in this document is `[VERIFIED]` against the source file at the line cited or `[CITED]` against SPEC/CONTEXT, except the items listed below. None block the planner; all are flagged so the planner can confirm before locking decisions.

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Inverting CONTEXT D-02 field order to `[public_key, label]` is the correct UX call (so Enter on label submits after textarea Enter inserts newline) [ASSUMED — pattern reasoning, no user-stated preference] | Pitfall 3, Pattern 4 | Low — alternative is Ctrl+Enter on textarea, which works but is undocumented elsewhere in Foglet keybinds. Planner can pick either; both meet acceptance. |
| A2 | The Modal.Form `:textarea` Enter prelude is in scope for Phase 30 even though it amends Phase 28's substrate [ASSUMED — derived from "without it ACCT-05 acceptance is not achievable"] | Pitfall 1, Pattern 4 | Medium — if planner classifies this as Phase 28 substrate work, Phase 30 is blocked behind Phase 28 (CONTEXT D-17 already names that dependency). Recommended: treat the prelude as a Phase 30 add since it's narrowly scoped to enabling ACCT-05 paste, not a generic substrate change. |
| A3 | `compute_fingerprint/1` will reject normalized-but-malformed keys (e.g., paste with no algorithm prefix); the SPEC's byte-for-byte assertion is on a VALID ed25519 key only [ASSUMED — based on `:ssh_file.decode/2` strictness] | Pitfall 7 | Low — test expected to use a real ed25519 fixture, not malformed input. |
| A4 | The "true input event" inclusion list for status_message_seen? flip is exhaustive at: `:char`, `:backspace`, `:enter`, `:tab`, `:shift_tab`, `:backtab`, `:escape`, `:up`, `:down`, `:left`, `:right` [ASSUMED — SPEC says "next keypress" without enumerating] | Pattern 2, Pitfall 5 | Low — adding `:home`/`:end`/`:page_up`/`:page_down` later is non-breaking. |
| A5 | Page size of 5-6 entries fits the 64×22 PREFERENCES tab body [ASSUMED — back-of-envelope from frame budget] | Pitfall 9 | Low — visual UAT will catch overflow; planner should set page_size based on actual `mix foglet.tui.render` output, not on this estimate. |

## Open Questions

1. **Should `Foglet.Accounts.update_preferences/2` and `get_preferences/1` be ADDED in this phase as named boundary functions, or stay deferred?**
   - What we know: CONTEXT D-16 references them; the codebase uses `update_profile/2` with a `:preferences` attrs key; `get_preferences/1` does not exist (read-back is via `Accounts.get_user/1` then `user.preferences["time_format"]`).
   - What's unclear: whether the test in `prefs_form_test.exs` (D-20) will read via `Accounts.get_user/1` (works today) or expect `Accounts.get_preferences/1` (would require a new function).
   - Recommendation: keep the boundary surface unchanged; tests use `Accounts.get_user/1` and read `.preferences["time_format"]` / `.theme` / `.timezone`. Add `update_preferences/2` only if the planner decides the boundary clarity is worth the new function.

2. **Should the Modal.Form `:textarea` Enter prelude (Pattern 4) be a Phase 30 task or escalated to Phase 28?**
   - What we know: Phase 28 owns Modal.Form substrate (FORM-01..06); Phase 30 lists itself as a CONSUMER of Phase 28 (CONTEXT D-17). The prelude is a substrate change.
   - What's unclear: whether the planner has authority to add a small substrate amendment in a consumer phase, or must surface it as a blocker on Phase 28.
   - Recommendation: treat the prelude as a Phase 30 task — narrowly scoped to enabling ACCT-05 paste — and update Phase 28's substrate tests to include it as a regression check post-merge. Surface as a blocker only if Phase 28 is currently in flight and merging would create a conflict.

3. **What happens on the 64×22 SelectList when there are 597 zones and the search buffer is empty?**
   - What we know: SmartList renders `page_size` rows + search row + pagination row; with 597 entries and `page_size: 6` the user sees 6 zones + "Page 1 / N" hint until they type.
   - What's unclear: whether the initial pre-selected value (e.g., `Etc/UTC`) is on the visible page, OR the SelectList scrolls to bring it into view.
   - Recommendation: verify in `acct_04_open` test that `scroll_offset` lands the saved value within the visible rows. Raxol's `Utils.ensure_visible/1` (utils.ex:55-64) handles this — but the test should confirm.

4. **Does the existing `account_test.exs` need to be split, or just extended?**
   - What we know: it's 1000+ lines; CONTEXT D-20 names new test files for prefs_form / ssh_keys_paste / form_internal_title.
   - What's unclear: whether ACCT-01 `[Saved]` flash tests go in `account_test.exs` (existing) or `prefs_form_test.exs` / a new `profile_form_test.exs`.
   - Recommendation: ACCT-01 flash tests live in the existing `account_test.exs` (close to the State/render assertions); ACCT-03/04 prefs-specific tests live in the new `prefs_form_test.exs`. Don't create a new `profile_form_test.exs` unless the test surface grows beyond the flash check.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Elixir | ExUnit / mix | ✓ | per project (1.18+) | — |
| Erlang/OTP | `:ssh_file.decode/2`, `:ssh.hostkey_fingerprint/2` | ✓ | per project (OTP 27+) | — |
| Timex | `Timex.Timezone.exists?/1` (validate_timezone), `Timex.Timezone.local/0` | ✓ | 3.7.13 | — |
| Tzdata | `Tzdata.zone_list/0` | ✓ | 1.1.3 (transitive) | — |
| PostgreSQL | Repo backing for `users` and `ssh_keys` updates | ✓ | per project | — |
| `rtk` shell prefix | All bash commands per AGENTS.md | ✓ (verified `rtk` CLI is present and project's CLAUDE.md mandates its use) | — | If rtk is unavailable, fall back to bare `mix` invocations — but project mandate is to use rtk. |
| Raxol vendored fork | `MultiLineInput`, `SelectList`, `RadioGroup`, `Tabs` | ✓ | vendored at `vendor/raxol/` | — |
| Live SSH client (for D-19 manual UAT) | UAT script execution at 64×22 and 80×24 | manual | n/a | UAT step author runs against `localhost:2222` (per `Foglet.SSH.Supervisor` startup log). |

**Missing dependencies with no fallback:** None.
**Missing dependencies with fallback:** None.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — every library version verified in mix.lock; Tzdata zone count verified empirically.
- Architecture: HIGH — read every cited source file; CONTEXT decisions cross-checked against actual code.
- Pitfalls: HIGH — Pitfall 1, 2, 3 (the textarea-Enter chain) traced through Modal.Form clauses + InputParser byte mapping; Pitfall 9 (64×22 budget) is the only LOW item, gated by visual UAT.
- Pitfalls (Pitfall 4, 5, 6, 7, 8): MEDIUM-HIGH — derived from existing code patterns or explicit constraint statements.
- Code Examples: HIGH — every example block has a `Source:` citation to the file/line currently in the repo.

**Research date:** 2026-04-27
**Valid until:** 2026-05-27 (Phase 30 is consumption-phase, low API churn risk; if Phase 28 lands changes to Modal.Form substrate during this window, re-verify Modal.Form line numbers cited in Pattern 1, 3, 4).
