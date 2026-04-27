---
status: diagnosed
trigger: "Press Enter on Sysop Site form does nothing; holding Enter saves. Test 4 in 28-HUMAN-UAT.md."
created: 2026-04-27T22:43:26Z
updated: 2026-04-27T22:55:00Z
---

## Current Focus

hypothesis: CONFIRMED — `Foglet.TUI.Widgets.Modal.Form.handle_event/2` Clause 4 (`%{key: :enter}`) only fires `on_submit` when `focus_index == last_idx`. On any other field, Enter is a "focus advance" (acts identically to Tab). With initial `focused: 0` and 5 visible Site fields, a brief Enter on field 0 just walks focus to field 1 — submit never fires. Holding Enter generates ~N auto-repeat events that walk focus all the way to the last field, where the next repeat finally submits. There is no `:key_press`/`:key_release` event-state filter — SSH bytestream produces the same event shape per repeat. The "hold to save" perception is exactly N consecutive focus-advances landing on the last field, then one more Enter triggering the submit.
test: Read `lib/foglet_bbs/tui/widgets/modal/form.ex:270-288` (Clause 4). Read `lib/foglet_bbs/tui/screens/sysop/site_form/state.ex:32-89` to confirm field count (5) and initial `focused: 0`. Read `lib/foglet_bbs/tui/screens/sysop.ex:259-376` to confirm Sysop does not consume Enter for SITE — it falls through to SiteForm. Read `lib/foglet_bbs/ssh/cli_handler.ex:209-214` to confirm raw SSH bytes go through `IOAdapter.parse_input/1` which produces a single `:key` event per byte (no press/release/repeat distinction).
expecting: All evidence to align with the focus-advance hypothesis; no `:key_press`/`:key_release` filtering; same root cause applies to Account → Profile (Gap 1).
next_action: Return ROOT CAUSE FOUND.

## Symptoms

expected: A single discrete press of Enter on the Sysop Site form fires the bound submit handler once.
actual: Pressing (briefly) Enter does nothing visible. Holding Enter (auto-repeat) eventually fires submit. Ctrl+S submits correctly.
errors: None.
reproduction: SSH in, navigate to Sysop → Site (focus defaults to field 0 = `registration_mode`), edit a field, press Enter (briefly) → no save (focus silently advances to field 1). Hold Enter ~5 repeats → focus walks to last field (`invite_generation_per_user_limit` integer when visible, else `require_email_verification` boolean) → next Enter submits.
started: Phase 28 (Modal.Form substrate). Discovered during 28 UAT (Test 4). The Modal.Form REQ-5 contract (Enter advances focus, Enter-on-last submits) is the SPEC behavior; the discoverability defect is that this contract conflicts with the user's "Enter saves" mental model.

## Eliminated

- hypothesis: Modal.Form filters key events on a `:key_press`/`:key_release`/`:key_repeat` discriminator
  evidence: `rtk grep -rn ":key_press\|:key_release\|:key_repeat" lib/foglet_bbs/` returned zero matches. SSH delivers a single byte per keystroke (no native press/release/repeat states); CLIHandler dispatches each byte through `IOAdapter.parse_input/1` which yields a single `Raxol.Core.Events.Event{type: :key, data: %{key: :enter}}` per byte. There is no event-state field for the handler to filter on.
  timestamp: 2026-04-27T22:50:00Z

- hypothesis: Sysop screen consumes Enter before SiteForm sees it (e.g. on the SITE tab)
  evidence: `lib/foglet_bbs/tui/screens/sysop.ex:272-289` shows the `:enter` handler short-circuits ONLY for INVITES (revoke arming); for every other tab including SITE it falls through to `do_handle_key/2 → delegate_to_active_tab → delegate_to_submodule(:site_form, SiteForm)`. SiteForm.handle_key receives `%{key: :enter}` cleanly.
  timestamp: 2026-04-27T22:51:00Z

- hypothesis: Tabs widget consumes Enter (Sysop) and short-circuits before SiteForm
  evidence: `lib/foglet_bbs/tui/widgets/input/tabs.ex:133-138` `derive_action/2` only returns `{:tab_changed, idx}` when `active_index` actually changes. Enter does not change tab index, so action is nil; in `do_handle_key/2` (`sysop.ex:347-376`) the `if action == nil and new_tabs == ss.tabs` branch fires → `delegate_to_active_tab` runs → SiteForm.handle_key gets the event.
  timestamp: 2026-04-27T22:52:00Z

## Evidence

- timestamp: 2026-04-27T22:46:00Z
  checked: `lib/foglet_bbs/tui/widgets/modal/form.ex:270-288` (Clause 4: Enter)
  found: |
    defp do_handle_event(%__MODULE__{} = state, %{key: :enter}) do
      last_idx = length(state.fields) - 1
      if state.focus_index == last_idx do
        payload = collect_values(state)
        _ = state.on_submit.(payload)
        {%{state | submit_state: :submitting}, :submitted}
      else
        n = length(state.fields)
        {%{state | focus_index: rem(state.focus_index + 1, n)}, nil}
      end
    end
  implication: Enter on a NON-last field is byte-identical to Tab — pure focus advance, no submit, no action emitted. This is the documented Phase 28 REQ-5 contract ("Enter-on-last-field submits"). Brief tap on field 0 with 5 fields visible = 1 advance to field 1, no save. Hold for ~5 auto-repeats = 4 advances + 1 submit on the final repeat once focus_index == 4.

- timestamp: 2026-04-27T22:47:00Z
  checked: `lib/foglet_bbs/tui/screens/sysop/site_form/state.ex:32-89` and visibility logic at `:114-121`
  found: |
    @site_keys = ["registration_mode", "invite_code_generators", "delivery_mode",
                  "require_email_verification", "invite_generation_per_user_limit"]
    defstruct ... focused: 0, ...
    visible_keys/1 hides invite_generation_per_user_limit unless invite_code_generators == "any_user"
  implication: Initial focused=0 (registration_mode, an enum); the LAST visible field is either invite_generation_per_user_limit (integer) when "any_user", or require_email_verification (boolean) otherwise. Either way, focus 0 → last is 3-4 advances. Brief Enter tap from focus 0 will NEVER reach the submit branch. Held Enter eventually does.

- timestamp: 2026-04-27T22:48:00Z
  checked: `lib/foglet_bbs/tui/screens/sysop/site_form.ex:75-78` (Ctrl+S handler) and `:111-133` (`submit/1`)
  found: |
    def handle_key(%{key: :char, char: "s", ctrl: true}, %SState{} = state), do: submit(state)
    defp submit/1 builds the form, sets focus to last_idx via set_focus/2, then dispatches %{key: :enter} → ModalForm.handle_event reaches the Enter-on-last branch deterministically.
  implication: Ctrl+S works because it forces focus_index to last_idx BEFORE dispatching Enter. The SAME submit path is taken — Modal.Form.Clause 4 — so the handler itself is not broken. The defect is purely a focus-state precondition: only the Ctrl+S path satisfies it; bare Enter does not.

- timestamp: 2026-04-27T22:49:00Z
  checked: `lib/foglet_bbs/ssh/cli_handler.ex:209-214` (data callback)
  found: |
    def handle_ssh_msg({:ssh_cm, _conn, {:data, _ch, _type, data}}, state) do
      events = IOAdapter.parse_input(data)
      dispatch_events(state.lifecycle_pid, events)
      ...
    end
  implication: Each byte received from SSH becomes one or more Raxol events via Raxol.SSH.IOAdapter.parse_input/1. SSH delivers Enter as a single byte ("\r" → 0x0D); there is NO native press/release/repeat distinction over an SSH byte stream. OS-level auto-repeat at the client side is what makes "hold Enter" deliver multiple bytes — each becomes a separate, identical `:enter` event. This rules out the orientation hypothesis entirely.

- timestamp: 2026-04-27T22:53:00Z
  checked: `lib/foglet_bbs/tui/screens/account/profile_form.ex:30-69` and `lib/foglet_bbs/tui/screens/account/state.ex:188-205`
  found: |
    Profile fields: [location (text), tagline (text), real_name (text)] — 3 fields, default focus 0 (location).
    handle_key in `:enter, :escape, :tab, :shift_tab, :backtab, :up, :down, :char, :backspace` fans straight to `ModalForm.handle_event`.
    On `:submitted` action returns `[{:account_save_profile, attrs}]` and sets `status_message: "Profile ready to save."`
  implication: Same Modal.Form contract — Enter on focus 0 (location) advances to tagline (1) → real_name (2) → submit only on the THIRD Enter. Brief tap on Profile Location does NOT save. The Account screen does NOT render `status_message` on screen (grep confirms: `status_message` is set but never displayed in `account.ex` render). Even when the save fires, there is no visible affordance — magnifying the perception that "save is broken."

- timestamp: 2026-04-27T22:54:00Z
  checked: `.planning/phases/28-modal-form-substrate/28-CONTEXT.md:39-43` and `28-SPEC.md:13`
  found: D-05 explicitly specs: "`Modal.Form.handle_event(%{key: :enter}, ...)` on the last field transitions :idle → :submitting, invokes on_submit exactly once, and returns {state, :submitted}." This is the designed contract.
  implication: The behavior IS the spec. The Phase 28 substrate inherits "Enter advances; Enter-on-last submits" from the legacy ModalForm contract (REQ-5). What's missing is either (a) a discoverable affordance ("Enter advances field; Ctrl+S saves" — the footer copy is wrong; it currently says "[Enter] Submit"), or (b) a contract change so Enter-from-anywhere submits on single-field-style forms or always submits regardless of focus.

## Resolution

root_cause: |
  Modal.Form.handle_event/2 Clause 4 (`form.ex:277-288`) treats Enter as a focus-advance on every field except the last; only Enter while `focus_index == last_idx` invokes `on_submit`. SSH delivers one identical `:enter` event per pressed byte (no press/release/repeat states), so a brief Enter tap from initial focus 0 advances exactly one field and never submits. Holding Enter sends auto-repeat bytes from the OS-level keyboard repeat at the client; those events walk focus all the way to the last field where the final repeat finally lands on the submit branch — producing the user's "hold-to-save" perception. The same mechanism applies to Account → Profile (3 text fields, default focus 0): a single Enter on Location advances to Tagline; the user perceives no save because (a) submit needs 3 consecutive Enter presses to reach `real_name` and (b) Account does not render `status_message` so even a successful save is invisible.

fix: ""  # diagnose-only mode
verification: ""
files_changed: []
