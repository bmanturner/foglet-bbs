# Phase 28: Modal.Form Substrate — Research

**Researched:** 2026-04-27
**Domain:** Elixir / Raxol stateful TUI widget — multi-field form substrate, parent-owned focus routing, submit-state FSM, Esc cancel semantics
**Confidence:** HIGH (substrate is in-tree, requirements are line-locked to existing code, all decisions pre-locked in CONTEXT.md D-01..D-21)

## Summary

Phase 28 is **substrate hardening on a known module**, not greenfield. `Foglet.TUI.Widgets.Modal.Form` already exists, already implements the D-14 stateful-widget contract, and is already consumed by `ProfileForm` and `PrefsForm`. The six FORM-* requirements add or amend a small, enumerable set of clauses inside `lib/foglet_bbs/tui/widgets/modal/form.ex` plus a SiteForm rewrite to ride the same substrate.

The fixed stack — Elixir + Raxol + Erlang `:ssh` — has no alternatives to consider. Raxol does **not** provide a built-in multi-field form widget (verified against `vendor/raxol/lib/raxol/ui/components/`); the `:up`/`:down`/`:tab`/`:enter`/`:escape` flat-map event shape is the established Foglet convention emitted by `Foglet.TUI.Input.translate_key/1` and consumed by every existing screen. CONTEXT.md D-01..D-21 already locked every gray-area decision (submit-state machine shape, footer opt-in semantics, no-flash Esc, `:backtab` ≡ `:shift_tab`, SiteForm migration shape). The planner's job is sequencing — not architectural choice.

**Primary recommendation:** Implement the requirements as a focused diff against `form.ex` in clause order (lock guard first → `:backtab` → `:up`/`:down` → submit-state setter → footer opt-in → status row), then migrate SiteForm to a `Sysop.SiteForm.State` + thin `Sysop.SiteForm` wrapper that mirrors `ProfileForm`/`PrefsForm` exactly. Use the existing `test/foglet_bbs/tui/widgets/modal/form_test.exs` as the test home for substrate clauses; rewrite `test/foglet_bbs/tui/screens/sysop/site_form_test.exs` to assert on Modal.Form rendering (D-18). The negative-fact tests (no leaf-widget focus state, double-Enter idempotence, `:submitting` event lock) are all expressible as pure `handle_event/2` reductions with `assert_receive` / `refute_receive` — no `Process.sleep`, no monitors needed.

## User Constraints (from CONTEXT.md)

### Locked Decisions

**Submit-state machine (D-01..D-05):**
- D-01: `Modal.Form` struct gains `submit_state` field, default `:idle`. Allowed: `:idle | :submitting | :saved | {:error, term}`.
- D-02: First-clause guard `handle_event(_event, %{submit_state: :submitting} = state)` swallows every event, returns `{state, nil}`.
- D-03: Public setter `Modal.Form.set_submit_state(form, new_state)` accepts only `:idle | :saved | {:error, term}`. The `:submitting` transition is reserved for the internal Enter-on-last clause.
- D-04: `:saved` and `{:error, _}` auto-reset to `:idle` on the next user event after the lock-clause check (terminal-state badge clears on next keystroke).
- D-05: `handle_event(%{key: :enter}, ...)` on the last field transitions `:idle → :submitting`, invokes `on_submit` exactly once, returns `{state, :submitted}`. `SubmitStash` payload-handoff preserved verbatim.

**Footer opt-in (D-06, D-07):**
- D-06: `init/1` accepts `:show_footer` (boolean, default `false`). `App.render_modal_overlay/2` opts in.
- D-07: Set at `init/1`, not `render/2`. Per-render re-init forms (SiteForm pattern at `site_form.ex:316`) pass `show_footer: false` every re-init.

**In-flight status row (D-08, D-09):**
- D-08: When `submit_state == :submitting`, render emits `Saving…` row in `theme.dim.fg`. `:saved` → `Saved.` for one cycle. `{:error, msg}` → `Error: <msg>` in `theme.error.fg`.
- D-09: Status row replaces (does not duplicate) the footer when both would render. Layout math at 64×22 unchanged versus pre-D-06.

**Honest Esc — no flash (D-10..D-12):**
- D-10: Esc fires `on_cancel`; consuming screens reseed drafts. **No "Changes discarded." status row is rendered.** Field reversion on next render is the visible signal.
- D-11: ProfileForm and PrefsForm have their existing `status_message: "Profile changes discarded."` / `"Preference changes discarded."` **removed**. Tests asserting that copy update to assert field reversion only.
- D-12: SiteForm does not gain a `status_message` field. Esc reseeds via `Foglet.Config.get!/1` and triggers a redraw — no inline copy.

**Up/Down focus movement (D-13, D-14):**
- D-13: `handle_event/2` gains `%{key: :up}` and `%{key: :down}` clauses placed before catch-all. Inspect `Enum.at(state.fields, state.focus_index).type`: `:enum` falls through to `dispatch_to_field/3`; `:text | :integer | :textarea` advance/retreat `focus_index` with wrap.
- D-14: Wrap direction documented in `@moduledoc`: forward (Tab/Down) wraps last → 0; backward (Shift+Tab/`:backtab`/Up) wraps 0 → last.

**`:backtab` parity (D-15):**
- D-15: Single `handle_event(%{key: :backtab}, state)` clause adjacent to the existing `:shift_tab` clause (form.ex:119), identical body. `@moduledoc` documents `:backtab` ≡ `:shift_tab` ≡ `%{key: :tab, shift: true}`.

**Single-source-of-truth focus (D-16):**
- D-16: No leaf widget code changes required. Verified by grep test: no `:focused` / `:focus_index` / `focused?` field on any leaf input widget defstruct.

**SiteForm migration (D-17..D-21):**
- D-17: SiteForm restructured as thin wrapper analogous to ProfileForm/PrefsForm. Sibling `Foglet.TUI.Screens.Sysop.SiteForm.State` holds bespoke struct (`current_user`, `drafts`, `errors`, `focused`). Modal.Form built fresh per render (matches `site_form.ex:316`).
- D-18: SiteForm's bespoke "▸ key: value" + description-line render **dropped** in favor of Modal.Form's standard rendering. Field labels and descriptions sourced from `Foglet.Config.Schema.fetch_spec/1`. Tests rewritten.
- D-19: Ctrl+S submit shortcut **preserved** at screen-level handler. Routes to the same validate → `Foglet.Config.put/3` → `SubmitStash` path that Enter-on-last uses.
- D-20: `validate_delivery_verification_pair/1` runs inside `on_submit` before any `Foglet.Config.put/3` call. Validation failures call `set_errors/2` and transition `submit_state` to `:idle` or `{:error, msg}`.
- D-21: Conditional visibility (`invite_generation_per_user_limit` hidden unless `invite_code_generators == "any_user"`) preserved. Visible-keys filter runs in screen wrapper before constructing per-render Modal.Form `:fields` list.

### Claude's Discretion

- Test ordering (smoke first vs RED→GREEN per requirement).
- Whether the `:saved` auto-clear lives in the lock-guard clause or in a separate first-cleanup pass before clauses run.
- Status-row literal copy (`Saving…` vs `Saving...` ASCII-fallback choice — D-08 says `Saving…` with ellipsis).
- Whether D-19 Ctrl+S shortcut goes through `Sysop.SiteForm.handle_key/2` directly or routes through `Modal.Form.handle_event/2` first (the spec phrasing "preserved at screen-level" suggests the former).

### Deferred Ideas (OUT OF SCOPE)

- Sysop Site editability lifecycle, draft echo, Config persistence errors-to-copy, `[R] Retry` keybind — Phase 29 (`SYSOP-03`).
- Sysop Site field subtitle copy / REQ-ID scrubbing — Phase 29 (`SYSOP-04`).
- Account Profile persistence + Saved flash — Phase 30 (`ACCT-01`).
- Account Preferences widget reachability, IANA timezone selector, multi-line SSH key paste — Phase 30 (`ACCT-03/04/05`).
- TextInput cursor rendering — Phase 27 (complete).
- Composer soft-wrap, Boards Enter toggling — Phase 33.
- True modal overlay confirmation dialogs (new product surfaces).
- Real timer-driven flash window (`Process.send_after/3` ~2s clear) — superseded by D-10.

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| FORM-01 | Up/Down inter-field focus on text/integer/textarea fields, enum cycling preserved | D-13 prescribes the clause shape; existing `dispatch_to_field/3` clauses at `form.ex:280-289` already handle enum `:up`/`:down` cycling. Add `:up`/`:down` clauses before the catch-all dispatch (Clause 5 at `form.ex:147`). |
| FORM-02 | `:backtab` accepted as Shift+Tab equivalent | D-15 prescribes a one-clause addition adjacent to `form.ex:119`. Existing test at `form_test.exs:469-478` already exercises `%{key: :shift_tab}`; mirror with `%{key: :backtab}`. |
| FORM-03 | Configurable footer suppressed by default, opt-in for true overlays | D-06/D-07 lock the `:show_footer` boolean at `init/1`. Single overlay caller is `app.ex:197` (`render_modal_overlay/2`). All three consuming screens (Profile/Prefs/Site) get `false` by default → no diff to those callers. |
| FORM-04 | Single-source-of-truth focus routing | D-16: no leaf code change. Already correct: `TextInput.defstruct` at `text_input.ex:42` is `[:raxol_state, :validator, :on_submit, last_action: nil]` (no focus field); `RadioGroup` and `Checkbox` are stateless render-only modules. Phase 28 adds a guard test that asserts this. |
| FORM-05 | Submit-state machine prevents double-submit and shows in-flight state | D-01..D-05 + D-08. Add `submit_state` field to defstruct, add lock-guard as Clause 0, transition logic in Clause 4 (Enter), public setter, status row in render. PITFALLS.md F3 (lines 196-218) is the canonical reference for this pattern. |
| FORM-06 | Honest Esc on Account Profile, Account Preferences, and Sysop Site | D-10..D-12: drop "Changes discarded." copy. Modal.Form's existing `:escape` clause (`form.ex:102-105`) needs no change. ProfileForm/PrefsForm `:cancelled` branches at `profile_form.ex:51-53` and `prefs_form.ex:67-70` lose the `status_message` set. SiteForm gets a fresh `:cancelled` branch in its new wrapper that calls `Foglet.Config.get!/1` to reseed drafts. |

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Focus routing (`focus_index`) | Stateful widget (`Modal.Form`) | — | D-14 contract: substrate widget owns its own state; leaf inputs are stateless render targets. |
| Per-field buffer state (`field_states`) | Stateful widget (`Modal.Form`) | — | Already correct in tree; collected via `collect_values/1` at submit time. |
| Submit lifecycle FSM (`submit_state`) | Stateful widget (`Modal.Form`) | Consuming screen (transitions out of `:submitting`) | Substrate guarantees idempotence; consumer drives terminal-state transitions per D-03. |
| Payload capture | `SubmitStash` (process dictionary) | Consuming screen | D-05 preserves the `SubmitStash.with_stashed/2` pattern verbatim. |
| Boundary call (`Foglet.Config.put/3`, `Foglet.Accounts.*`) | Consuming screen | — | AGENTS.md: domain workflows live in contexts; widgets call them via `on_submit` callback. |
| Esc draft reset | Consuming screen | Modal.Form (fires `on_cancel`) | Modal.Form is data-shape-agnostic; only the consumer knows what "saved values" means. |
| Status-row rendering (`Saving…`) | Stateful widget (`Modal.Form`) | — | D-08: row is layout-coupled to footer position; substrate owns it. |
| Ctrl+S shortcut (Sysop only) | Consuming screen (`Sysop.SiteForm`) | — | D-19: screen-level handler routes to same `on_submit` path as Enter. Modal.Form does not handle Ctrl+S generically. |
| Conditional field visibility (`invite_generation_per_user_limit`) | Consuming screen wrapper | — | D-21: visible-keys filter runs before per-render Modal.Form construction. |

## Standard Stack

This is a fixed-stack, in-repo phase. The "stack" is the existing Foglet/Raxol primitive surface.

### Core (touched by Phase 28)
| Module | Path | Purpose | Why Standard |
|--------|------|---------|--------------|
| `Foglet.TUI.Widgets.Modal.Form` | `lib/foglet_bbs/tui/widgets/modal/form.ex` | Substrate being hardened | Already the D-14 substrate; this phase extends it minimally. |
| `Foglet.TUI.Widgets.Modal.Form.SubmitStash` | `lib/foglet_bbs/tui/widgets/modal/form/submit_stash.ex` | Per-process payload handoff | D-05 preserves verbatim; safer than raw `Process.put/get` (Codex Concern 4). |
| `Foglet.TUI.Theme` | `lib/foglet_bbs/tui/theme.ex` | Color/style slot map | All Modal.Form colors route through `theme.dim.fg`, `theme.error.fg`, `theme.title.fg`, `theme.accent.fg`, `theme.primary.fg`, `theme.border.fg` (D-07/D-09). |
| `Foglet.Config.Schema` | `lib/foglet_bbs/config/schema.ex` | Schema lookup for SiteForm | `fetch_spec/1` returns `{:ok, %{type, label, description, enum?, min?, max?}}` — feeds Modal.Form `:fields` for SiteForm. [VERIFIED: `site_form.ex:119`] |
| `Foglet.Config` | `lib/foglet_bbs/config/config.ex` | Read-through ETS cache | `get!/1` for Esc reseed (D-12); `put/3` actor-aware writer for `on_submit` (D-19/D-20). |

### Supporting (referenced, not modified)
| Module | Purpose | When to Use |
|--------|---------|-------------|
| `Foglet.TUI.Widgets.Input.TextInput` | Single-line input widget | Already passes `focused?` keyword (no struct field) — D-16 verified. |
| `Foglet.TUI.Widgets.Input.RadioGroup` | Stateless enum render | No defstruct — D-16 trivially satisfied. |
| `Foglet.TUI.Widgets.Input.Checkbox` | Stateless boolean render | No defstruct — D-16 trivially satisfied. |
| `Raxol.UI.Components.Input.MultiLineInput` | Vendored Raxol textarea | Already wrapped via `Compose` — Phase 28 does not touch its quirks. |
| `Foglet.TUI.Widgets.Compose` | Shared composer plumbing + `translate_key/1` | Used by textarea dispatch in Modal.Form. |
| `Foglet.TUI.Input` | Top-level key event translator | `lib/foglet_bbs/tui/input.ex` defines the canonical flat-map shapes (`:up`, `:down`, `:tab`, etc.) — no Phase 28 change. |

### Alternatives Considered
None. The stack is locked by AGENTS.md and the substrate already exists in-tree.

**Verification:** No external library version pins for this phase. The vendored `Raxol` is at `vendor/raxol/`; Phase 28 does not bump it. `[VERIFIED: codebase grep]`

## Architecture Patterns

### System Architecture Diagram

```
                                 SSH terminal (64×22 / 80×24)
                                         │
                                         ▼
                              Foglet.SSH.CLIHandler
                              (key event flat-map shape:
                               %{key: :tab|:shift_tab|:backtab|
                                      :up|:down|:enter|:escape|
                                      :char|:backspace, char?, ...})
                                         │
                                         ▼
                                   Foglet.TUI.App
                                  (modal? → render_modal_overlay
                                   else  → render_screen)
                                         │
                              ┌──────────┴──────────┐
                              ▼                     ▼
                  render_modal_overlay        render_screen
                  show_footer: true           (per-screen handle_key
                  (Phase 28 single caller)     dispatch)
                              │                     │
                              │                     ▼
                              │               Account screen          Sysop screen
                              │              (handle_key)            (handle_key →
                              │                  │                    delegate_to_active_tab
                              │                  ▼                    SITE → SiteForm)
                              │            ProfileForm.handle_key            │
                              │            PrefsForm.handle_key              ▼
                              │                  │                    Sysop.SiteForm
                              │                  │                    (Phase 28 wrapper:
                              │                  │                     Ctrl+S shortcut,
                              │                  │                     visible_keys filter,
                              │                  │                     re-init Modal.Form)
                              │                  │                          │
                              └──────────────────┴──────────────────────────┘
                                                 │
                                                 ▼
                              Modal.Form.handle_event(event, form)
                              ┌─────────────────────────────────────┐
                              │ Clause 0: :submitting lock guard   │  ← NEW (D-02)
                              │   swallows ALL events              │
                              ├─────────────────────────────────────┤
                              │ Clause 1: :escape → on_cancel      │
                              ├─────────────────────────────────────┤
                              │ Clause 2: :tab+shift / :shift_tab  │
                              │ Clause 2c: :backtab                │  ← NEW (D-15)
                              ├─────────────────────────────────────┤
                              │ Clause 3: :tab                     │
                              ├─────────────────────────────────────┤
                              │ Clause 3a: :up / :down             │  ← NEW (D-13)
                              │   if focused field type is enum    │
                              │     → fall through to Clause 5      │
                              │   else → focus advance/retreat      │
                              ├─────────────────────────────────────┤
                              │ Clause 4: :enter                   │
                              │   on last → :idle→:submitting,     │  ← MODIFIED (D-05)
                              │             on_submit, :submitted   │
                              │   else → advance focus              │
                              ├─────────────────────────────────────┤
                              │ Clause 5: dispatch_to_field         │
                              │   (TextInput/Checkbox/RadioGroup/   │
                              │    enum cycling/MLI textarea)       │
                              └─────────────────────────────────────┘
                                                 │
                                                 ▼
                              SubmitStash.stash(consumer_module, payload)
                              {form, :submitted}
                                                 │
                                                 ▼
                              Consuming screen pops payload via
                              SubmitStash.with_stashed/2,
                              calls boundary (Foglet.Config.put/3 or
                              Foglet.Accounts.update_user_profile/3),
                              calls Modal.Form.set_submit_state(form,
                                :saved | {:error, msg})
                                                 │
                                                 ▼
                                   Render → Saving… / Saved. / Error: …
                                   in theme.dim.fg / theme.error.fg
```

### Recommended Project Structure

No new modules outside the established tree. The migration creates one new sibling state module:

```
lib/foglet_bbs/tui/
├── widgets/modal/
│   ├── form.ex                    # MODIFIED — Clauses 0/2c/3a, :show_footer, submit_state, set_submit_state/2
│   └── form/
│       └── submit_stash.ex        # UNCHANGED
├── screens/
│   ├── account/
│   │   ├── profile_form.ex        # MODIFIED — drop status_message on :cancelled (D-11)
│   │   ├── prefs_form.ex          # MODIFIED — drop status_message on :cancelled (D-11)
│   │   └── state.ex               # UNCHANGED
│   └── sysop/
│       ├── site_form.ex           # REWRITTEN as thin wrapper (D-17, D-18)
│       └── site_form/
│           └── state.ex           # NEW — bespoke struct (current_user, drafts, errors, focused)
└── app.ex                         # MODIFIED — render_modal_overlay/2 passes show_footer: true (D-06)
```

### Pattern 1: Lock-Guard as First Clause (D-02)

**What:** A first-position `handle_event/2` clause that pattern-matches `submit_state: :submitting` and swallows every event.

**When to use:** Whenever a stateful widget has an in-flight async submit and must guarantee idempotence + input freeze.

**Example:**
```elixir
# Source: form.ex (this phase adds it)
# Clause 0: :submitting lock — swallows all events while async submit is in flight (D-02).
# Placed BEFORE Clause 1 so it short-circuits even Esc.
def handle_event(_event, %__MODULE__{submit_state: :submitting} = state) do
  {state, nil}
end

# Clause 0a: terminal-state auto-clear — :saved / {:error, _} clear on next
# user event so the next keystroke acts on a clean :idle form (D-04).
# Placed AFTER the :submitting lock so it cannot intercept events the lock
# should swallow.
def handle_event(event, %__MODULE__{submit_state: ss} = state)
    when ss == :saved or (is_tuple(ss) and elem(ss, 0) == :error) do
  handle_event(event, %{state | submit_state: :idle})
end
```

**Why this clause order matters:** Esc inside `:submitting` must not fire `on_cancel` (would race the in-flight save). The lock clause is unconditional.

### Pattern 2: Type-Inspect-Then-Dispatch for Up/Down (D-13)

**What:** A clause that reads the focused field's spec and either advances focus (for text/integer/textarea) or falls through to the catch-all dispatch (for enum cycling).

**Where:** Insert between Clause 3 (`:tab`) and Clause 4 (`:enter`) — i.e. after horizontal-tab handlers, before submit handler.

**Example:**
```elixir
# Source: form.ex (this phase adds it). Mirrors the Tab/Shift-Tab wrap math.
# Clause 3a: Up/Down — focus movement on text/integer/textarea, cycling on enum (D-13).
def handle_event(%{key: key} = event, %__MODULE__{} = state) when key in [:up, :down] do
  spec = Enum.at(state.fields, state.focus_index)

  case spec.type do
    :enum ->
      # Fall through to dispatch_to_field for value cycling — preserves D-25 D-03 semantics.
      dispatch_to_focused(event, state)

    type when type in [:text, :integer, :textarea] ->
      n = length(state.fields)
      delta = if key == :down, do: 1, else: -1
      new_idx = rem(state.focus_index + delta + n, n)
      {%{state | focus_index: new_idx}, nil}

    _ ->
      {state, nil}
  end
end

defp dispatch_to_focused(event, %__MODULE__{} = state) do
  spec = Enum.at(state.fields, state.focus_index)
  field_state = Enum.at(state.field_states, state.focus_index)
  new_field_state = dispatch_to_field(spec, field_state, event)
  new_states = List.replace_at(state.field_states, state.focus_index, new_field_state)
  {%{state | field_states: new_states}, nil}
end
```

**Note:** The current Clause 5 catch-all does the same dispatch; refactoring it into `dispatch_to_focused/2` lets the new `:up`/`:down` clause reuse it cleanly. This is a refactor, not a behavior change.

### Pattern 3: SubmitStash Handoff with Submit-State Cooperation (D-05, D-19)

**What:** `on_submit` stashes the payload; the screen pops it, calls the boundary, and transitions `submit_state` via the public setter.

**Example (preserved from ProfileForm; SiteForm migrates to this shape):**
```elixir
# Source: lib/foglet_bbs/tui/screens/account/profile_form.ex:34-53
# (extended here to show the Phase 28 set_submit_state/2 transition)
defp do_handle_key(event, %State{profile_form: form} = state, current_user) do
  {new_form, action} = ModalForm.handle_event(event, form)
  state = %{state | profile_form: new_form}

  case action do
    :submitted ->
      {:profile, payload} = SubmitStash.pop(__MODULE__)
      attrs = %{location: payload.location, tagline: payload.tagline, real_name: payload.real_name}

      # Phase 28: profile_form is now in :submitting. The save command runs
      # async; on completion the screen calls set_submit_state(:saved | {:error, _}).
      {:ok, %{state | profile_dirty?: false}, [{:account_save_profile, attrs}]}

    :cancelled ->
      # Phase 28 D-11: status_message removal. Field reversion is the visible signal.
      {:ok, State.seed_from_user(state, current_user), []}

    _ ->
      dirty? = action == nil and text_input_event?(event)
      {:ok, %{state | profile_dirty?: state.profile_dirty? or dirty?}, []}
  end
end
```

### Pattern 4: SiteForm-as-Wrapper (D-17, D-18, D-21)

**What:** Bespoke screen state (`SiteForm.State`) holds drafts/errors/focused; the wrapper builds Modal.Form fresh every render from the visible-keys list.

**Example (target shape — to be written):**
```elixir
# Source: target structure for lib/foglet_bbs/tui/screens/sysop/site_form.ex
defmodule Foglet.TUI.Screens.Sysop.SiteForm do
  alias Foglet.Config
  alias Foglet.Config.Schema
  alias Foglet.TUI.Screens.Sysop.SiteForm.State
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm
  alias Foglet.TUI.Widgets.Modal.Form.SubmitStash

  @site_keys ~w[registration_mode invite_code_generators delivery_mode
                require_email_verification invite_generation_per_user_limit]

  @spec init(keyword()) :: State.t()
  def init(opts), do: State.init(opts, @site_keys)

  @spec render(State.t(), Theme.t()) :: any()
  def render(%State{} = state, %Theme{} = theme) do
    # D-21: visible-keys filter runs before constructing Modal.Form fields
    fields = build_fields(state)

    # D-17: re-init Modal.Form per render (matches existing pattern at site_form.ex:316)
    form = build_modal_form(state, fields)

    ModalForm.render(form, theme: theme)
  end

  # D-19: Ctrl+S shortcut at screen level — bypasses Modal.Form's Enter/last-field gate.
  def handle_key(%{key: :char, char: "s", ctrl: true}, %State{} = state) do
    submit_via_modal_form_path(state)
  end

  def handle_key(event, %State{} = state)
      when is_map_key(event, :key) do
    fields = build_fields(state)
    form = build_modal_form(state, fields)
    {new_form, action} = ModalForm.handle_event(event, form)

    # Sync focus_index back to bespoke state so re-render preserves position
    new_state = State.update_focus(state, new_form.focus_index)

    case action do
      :submitted ->
        {:site, payload} = SubmitStash.pop(__MODULE__)
        commit_payload(new_state, payload)

      :cancelled ->
        # D-12: reseed via Config.get!/1, no status_message
        {State.reseed_from_config(new_state, @site_keys), []}

      _ ->
        {new_state, []}
    end
  end

  defp build_modal_form(state, fields) do
    ModalForm.init(
      title: "Site policy",
      fields: fields,
      show_footer: false,        # D-06 default
      on_submit: fn payload ->
        SubmitStash.stash(__MODULE__, {:site, payload})
      end,
      on_cancel: fn -> :ok end
    )
  end
end
```

### Anti-Patterns to Avoid

- **Storing `focused?` in `TextInput.defstruct`:** D-16 forbids it. Pass `focused?` as a render keyword instead. (Already correct; PITFALLS.md F1 is the historical fix.)
- **Calling `on_submit` synchronously inside `Enter` without state-gating:** This is the F3 bug. Phase 28 fixes it via D-05's `:idle → :submitting` transition + Clause 0 guard.
- **Calling `set_submit_state(form, :submitting)` from the consuming screen:** D-03 rejects this. `:submitting` is reserved for the internal Enter clause. Setter raises or returns unchanged on `:submitting` input.
- **Adding a `Process.send_after/3`-driven flash window for "Changes discarded.":** D-10 explicitly drops this. Don't reintroduce.
- **Wrapping Modal.Form output in `box`/`border` inside the substrate:** Pitfall 4 (`form.ex:17-18`). Only `App.render_modal_overlay/2` adds chrome.
- **Using literal color atoms in the `Saving…` row:** D-08 routes through `theme.dim.fg`. Same hygiene rules as the rest of `form.ex`.
- **Letting Esc reach `on_cancel` while `submit_state == :submitting`:** Clause 0 lock guard prevents this. Don't add an Esc-specific bypass.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Multi-field form substrate | A second form widget alongside Modal.Form | Modal.Form (this phase) | Already in tree; this phase IS the substrate. SiteForm migration removes the only divergent implementation. |
| Cross-process payload handoff | Raw `Process.put/get` keyed manually | `Foglet.TUI.Widgets.Modal.Form.SubmitStash` with `with_stashed/2` | Cleanup-on-exception via `after`; Codex Concern 4 hardening already done. |
| Submit-state booleans (`pending?: true`) | Pair of `pending?` / `saved?` flags | The `submit_state :: :idle | :submitting | :saved | {:error, _}` enum | PITFALLS.md F3 explicitly prescribes the enum; pairs of flags drift out of sync after async events. |
| Key event normalization | `case key do :tab → :tab; "Tab" → :tab; ...` per consumer | `Foglet.TUI.Input.translate_key/1` upstream + flat-map shape | `lib/foglet_bbs/tui/input.ex` is the canonical translator. CLIHandler emits `:shift_tab` for back-tab; Modal.Form treats `:backtab` ≡ `:shift_tab` (D-15). |
| Schema-to-field-spec mapping for SiteForm | Hand-converting Schema specs to Modal.Form `:fields` maps inline | A `defp build_fields/1` helper in `Sysop.SiteForm` that delegates to `Schema.fetch_spec/1` | `Foglet.Config.Schema` is the authoritative metadata source (D-01 guardrail in `site_form.ex:8-10`). |
| Conditional-visibility re-render machinery | A stateful `visible?` flag on Modal.Form | Per-render Modal.Form re-init with computed visible-keys (D-17, `site_form.ex:316`) | Bespoke screen state is the source of truth; the substrate is built ephemerally. Avoids stateful re-sync logic that was the F1 bug. |
| Boundary calls (Config writes, Account updates) | Inline DB writes from the widget | `Foglet.Config.put/3` / `Foglet.Accounts.update_user_profile/3` from the consuming screen's `on_submit` | AGENTS.md: domain workflows live in contexts, never widgets. |
| Theme-routed colors | Literal `:cyan`, `:red`, etc. atoms | `theme.dim.fg`, `theme.error.fg`, `theme.title.fg`, `theme.accent.fg` slots | D-07/D-09; the `flatten_text` and `color_atom_leaked?/2` test helpers already enforce this. |

**Key insight:** Every concern this phase touches is already solved somewhere in-tree. The work is structural alignment + adding three new clauses to `form.ex` + migrating one screen — not invention.

## Common Pitfalls

### Pitfall 1: Lock guard in wrong position lets Esc race the submit

**What goes wrong:** If the `:submitting` lock-guard clause is placed after Clause 1 (`:escape`), pressing Esc during a save fires `on_cancel` and the screen reseeds drafts mid-flight; on save success the next render shows old data overwriting the (now-saved) values.
**Why it happens:** Pattern-match dispatch order in Elixir is top-to-bottom. The first matching clause wins.
**How to avoid:** Place the lock guard as **Clause 0**, before everything else. D-02 prescribes this; the test in this phase asserts `Esc + :submitting` produces `{state, nil}` and does NOT call `on_cancel`.
**Warning signs:** Test "Esc during :submitting does not fire on_cancel" returns `:cancelled`.

### Pitfall 2: Auto-clear on `:saved` swallows the very event that triggered the next action

**What goes wrong:** D-04 says `:saved` and `{:error, _}` auto-reset on the next event. Naive implementation puts the auto-clear in a separate `handle_event/2` clause that returns `{state_with_idle, nil}` — but the original event is now lost (e.g. the user pressed `Tab` to move to the next field; we cleared the badge but didn't move focus).
**Why it happens:** Clause cascade returns early after the state-clear.
**How to avoid:** The auto-clear clause must **recursively call `handle_event/2`** with the cleared state so the original event is processed by the appropriate clause:
```elixir
def handle_event(event, %__MODULE__{submit_state: ss} = state)
    when ss == :saved or (is_tuple(ss) and elem(ss, 0) == :error) do
  handle_event(event, %{state | submit_state: :idle})
end
```
**Warning signs:** After a successful save, pressing Tab shows the cleared `Saving…`/`Saved.` row but focus didn't move.

### Pitfall 3: `Enter` on a non-last field while `:idle` — does it transition `submit_state`?

**What goes wrong:** D-05 says Enter on last field transitions `:idle → :submitting`. But Enter on a non-last field also matches Clause 4. If the clause naively transitions `submit_state` regardless, Tab-equivalent behavior locks the form.
**Why it happens:** Easy to forget the `if state.focus_index == last_idx` branch already in `form.ex:136-143` and only update one path.
**How to avoid:** The transition lives **inside** the `if last_idx` branch, alongside the `on_submit.()` call. The else-branch (advance focus) leaves `submit_state` untouched.
**Warning signs:** Test "Enter on field 0 of 3 advances focus and does not lock the form" sees `submit_state == :submitting` after one Enter.

### Pitfall 4: Up/Down clause placement breaks enum cycling

**What goes wrong:** If `:up`/`:down` clauses are placed before the catch-all dispatch but inside an unconditional focus-mover, enum fields lose their cycling behavior (existing tests at `form_test.exs:163-174` will break).
**Why it happens:** Existing dispatch at `form.ex:280-289` matches `%{type: :enum}` plus `%{key: :down}`/`%{key: :up}` — the new clause has to fall through to that path for enum.
**How to avoid:** D-13 prescribes the type-inspect: only advance focus when the focused field is `:text | :integer | :textarea`. For `:enum`, fall through to `dispatch_to_field/3`.
**Warning signs:** `field_value(form, :theme_id)` returns `:dark` (unchanged) after a `:down` event when the form is on the enum field; existing test `field_value/2 returns updated choice after :down event` fails.

### Pitfall 5: Footer suppression breaks layout math at 64×22

**What goes wrong:** D-09 says `Saving…` row replaces the footer when both would render — but the layout math at 64×22 was sized assuming a 1-row footer. Naive `:show_footer false` removes the row entirely; the form is now 1 row shorter than tests expect.
**Why it happens:** `column [] do [title_row, divider] ++ field_rows ++ base_error_rows ++ [footer] end` at `form.ex:210-212` is hardcoded to always include footer.
**How to avoid:** Build the footer-or-status-row as a list (possibly empty), append it conditionally:
```elixir
trailing_rows =
  case state.submit_state do
    :submitting -> [text("Saving…", fg: theme.dim.fg)]
    :saved      -> [text("Saved.", fg: theme.dim.fg)]
    {:error, m} -> [text("Error: #{m}", fg: theme.error.fg)]
    :idle when state.show_footer -> [text("[Enter] Submit   [Esc] Cancel", fg: theme.dim.fg)]
    :idle -> []
  end

column [] do
  [title_row, divider] ++ field_rows ++ base_error_rows ++ trailing_rows
end
```
**Warning signs:** Layout smoke test at 64×22 fails with off-by-one row count; or D-09 footer-replacement test sees both `Saving…` and `[Enter] Submit` in the same render.

### Pitfall 6: SiteForm Ctrl+S routed through Modal.Form skips the pre-flight validator

**What goes wrong:** If Ctrl+S is naively routed through `Modal.Form.handle_event/2` as a synthetic `:enter` event, the `validate_delivery_verification_pair/1` check (D-20) might run too late or twice.
**Why it happens:** D-20 says validation runs **inside `on_submit`**, before any `Foglet.Config.put/3`. If Ctrl+S bypasses the wrapper and goes through Modal.Form directly, the screen-level handler doesn't get a chance to slot in the validator.
**How to avoid:** D-19 explicitly says the Ctrl+S shortcut "is preserved at screen-level handler" and "routes to the same validate → `Foglet.Config.put/3` → `SubmitStash` path". Implement Ctrl+S in `Sysop.SiteForm.handle_key/2` as a direct call to the same private `submit/1` function the `:submitted` action invokes — do **not** synthesize a `:enter` event for Modal.Form.
**Warning signs:** Test "Ctrl+S with delivery_mode=no_email and require_verification=true sets errors and does not call Config.put" sees a Config write happen.

### Pitfall 7: SiteForm `focused` index drifts when visible_keys filter changes

**What goes wrong:** User is on field index 4 (`invite_generation_per_user_limit`), changes `invite_code_generators` away from `"any_user"` — the limit field disappears from `visible_keys`. Next render's Modal.Form has only 4 fields (indices 0..3) but `state.focused == 4`.
**Why it happens:** Conditional visibility is a feature; index drift is the natural consequence.
**How to avoid:** When constructing the per-render Modal.Form, clamp `focus_index` to `length(fields) - 1`:
```elixir
defp build_modal_form(%State{focused: f} = state, fields) do
  clamped_focus = min(f, length(fields) - 1) |> max(0)
  form = ModalForm.init(...)
  %{form | focus_index: clamped_focus}
end
```
**Warning signs:** Crash on `Enum.at(fields, focus_index)` returning nil; or focus marker disappears from rendered output.

### Pitfall 8: Test using `Process.sleep` to wait for `:submitting → :saved`

**What goes wrong:** Naive test: `Form.handle_event(:enter, form)` → `Process.sleep(100)` → assert `submit_state == :saved`. But Modal.Form is **synchronous**; `set_submit_state/2` is a pure function. The screen-level test should drive transitions explicitly.
**Why it happens:** Reflexive habit from async-Web testing.
**How to avoid:** Modal.Form is pure — drive it as `form |> Form.handle_event(:enter, _) |> Form.set_submit_state(:saved)` and assert at each step. AGENTS.md forbids `Process.sleep/1` in tests.
**Warning signs:** Test file imports nothing async, yet uses `Process.sleep`. Reviewer should flag immediately.

## Code Examples

### Adding the `:show_footer` Init Option (D-06)

```elixir
# Source: form.ex (modification of init/1 at line 83)
@spec init(keyword()) :: t()
def init(opts) when is_list(opts) do
  fields = Keyword.fetch!(opts, :fields)
  field_states = Enum.map(fields, &build_field_state/1)

  %__MODULE__{
    title: Keyword.get(opts, :title, ""),
    fields: fields,
    field_states: field_states,
    focus_index: 0,
    errors: %{},
    on_submit: Keyword.fetch!(opts, :on_submit),
    on_cancel: Keyword.fetch!(opts, :on_cancel),
    show_footer: Keyword.get(opts, :show_footer, false),  # NEW (D-06)
    submit_state: :idle                                   # NEW (D-01)
  }
end
```

### Single Caller Opt-In at the Overlay Boundary (D-06)

```elixir
# Source: app.ex:197 — render_modal_overlay/2 (current and target)
# NOTE: Phase 28 audit — only render_modal_overlay/2 callers should pass
# show_footer: true. The form is constructed elsewhere (modal opener), so
# the actual change lands wherever a Modal.Form is init/1'd specifically
# for overlay use. Audit grep:
#   $ grep -rn "Modal.Form.init\|ModalForm.init" lib/foglet_bbs/tui/
# Every existing call site (ProfileForm, PrefsForm, BoardsView CRUD modals,
# the new SiteForm wrapper) gets the default show_footer: false. Only true
# overlay invocations opt in.
```

### Enter Clause with Submit-State Transition (D-05)

```elixir
# Source: form.ex (modification of Clause 4 at line 133)
def handle_event(%{key: :enter}, %__MODULE__{submit_state: :idle} = state) do
  last_idx = length(state.fields) - 1

  if state.focus_index == last_idx do
    payload = collect_values(state)
    new_state = %{state | submit_state: :submitting}     # NEW (D-05)
    _ = state.on_submit.(payload)
    {new_state, :submitted}
  else
    n = length(state.fields)
    {%{state | focus_index: rem(state.focus_index + 1, n)}, nil}
  end
end
```

Note: this clause is reachable only when `submit_state == :idle` because Clause 0 swallows `:submitting` and Clause 0a auto-clears `:saved`/`:error` to `:idle` first.

### Public Setter (D-03)

```elixir
# Source: form.ex (NEW, sibling to set_errors/2 at line 177)
@doc """
Transition `submit_state` out of `:submitting` to a terminal state.

Accepts only `:idle | :saved | {:error, term}`. Attempts to transition to
`:submitting` from outside the substrate are rejected (no-op) — that
transition is reserved for the internal Enter-on-last clause (D-05).

The terminal states `:saved` and `{:error, _}` auto-clear to `:idle` on
the next user event (D-04), so callers do not need to call
`set_submit_state(form, :idle)` after the user has acknowledged the
result.
"""
@spec set_submit_state(t(), :idle | :saved | {:error, term()}) :: t()
def set_submit_state(%__MODULE__{} = state, :submitting), do: state
def set_submit_state(%__MODULE__{} = state, new_state)
    when new_state == :idle or new_state == :saved
    when is_tuple(new_state) and tuple_size(new_state) == 2 and elem(new_state, 0) == :error do
  %{state | submit_state: new_state}
end
```

### Render-Time Trailing-Row Selection (D-08, D-09)

```elixir
# Source: form.ex (modification of render/2 at line 188)
@spec render(t(), keyword()) :: any()
def render(%__MODULE__{} = state, opts) do
  %Theme{} = theme = Keyword.fetch!(opts, :theme)

  title_row = text(state.title, fg: theme.title.fg, style: [:bold])
  divider = text(String.duplicate("─", 40), fg: theme.border.fg)

  field_rows =
    state.fields
    |> Enum.with_index()
    |> Enum.flat_map(fn {spec, idx} ->
      focused? = idx == state.focus_index
      field_state = Enum.at(state.field_states, idx)
      render_field(spec, field_state, focused?, state.errors, theme)
    end)

  base_error_rows =
    case Map.get(state.errors, :base) do
      nil -> []
      msg -> [text(msg, fg: theme.error.fg)]
    end

  trailing_rows = render_trailing(state, theme)  # NEW

  column [] do
    [title_row, divider] ++ field_rows ++ base_error_rows ++ trailing_rows
  end
end

# NEW (D-08, D-09)
defp render_trailing(%__MODULE__{submit_state: :submitting}, theme),
  do: [text("Saving…", fg: theme.dim.fg)]

defp render_trailing(%__MODULE__{submit_state: :saved}, theme),
  do: [text("Saved.", fg: theme.dim.fg)]

defp render_trailing(%__MODULE__{submit_state: {:error, msg}}, theme),
  do: [text("Error: #{msg}", fg: theme.error.fg)]

defp render_trailing(%__MODULE__{submit_state: :idle, show_footer: true}, theme),
  do: [text("[Enter] Submit   [Esc] Cancel", fg: theme.dim.fg)]

defp render_trailing(%__MODULE__{}, _theme), do: []
```

## Test Strategy

The test surface for Phase 28 is entirely deterministic — every requirement reduces to a pure-function reduction over `handle_event/2`, which is already the established testing pattern in `test/foglet_bbs/tui/widgets/modal/form_test.exs`. **No `Process.sleep`, no `Process.alive?`, no async-via-PubSub gymnastics required.**

### Test Layout

| File | Purpose | What's New |
|------|---------|------------|
| `test/foglet_bbs/tui/widgets/modal/form_test.exs` | Modal.Form substrate unit tests | Add `describe` blocks for: `submit_state` FSM, `:show_footer`, `:up`/`:down` focus, `:backtab`. Existing tests pass unchanged. |
| `test/foglet_bbs/tui/screens/account/profile_form_test.exs` | ProfileForm consumer tests | Drop assertions on "Profile changes discarded." copy (D-11); replace with field-reversion assertions. |
| `test/foglet_bbs/tui/screens/account/prefs_form_test.exs` | PrefsForm consumer tests | Same as ProfileForm — D-11 cleanup. |
| `test/foglet_bbs/tui/screens/sysop/site_form_test.exs` | SiteForm migration tests | **Rewrite** to assert on Modal.Form-rendered output (D-18). Preserve delivery-verification-pair test, conditional-visibility tests, Ctrl+S submit path. |
| `test/foglet_bbs/tui/widgets/leaf_focus_state_grep_test.exs` | NEW — D-16 verification | A grep-based test that scans `lib/foglet_bbs/tui/widgets/input/*.ex` for `:focused` / `focus_index` / `focused?:` field declarations on defstructs. |
| `test/foglet_bbs/tui/layout_smoke_test.exs` | Existing 64×22/80×24 layout test | Add cases asserting no duplicate footer on Account Profile, Account Prefs, Sysop Site at both sizes (FORM-03). |

### Negative-Fact Tests

These prove "X does not happen" — historically the hardest tests to write robustly. Each below has a deterministic, non-flaky shape:

**FORM-04 — No leaf-widget focus state:**
```elixir
test "no leaf input widget defstruct carries a focus field (D-16)" do
  for module <- [TextInput, RadioGroup, Checkbox] do
    if function_exported?(module, :__struct__, 0) do
      keys = module.__struct__() |> Map.from_struct() |> Map.keys()
      forbidden = Enum.filter(keys, fn k ->
        k_str = Atom.to_string(k)
        k_str =~ ~r/^focus|focused|focus_index/
      end)
      assert forbidden == [],
             "#{inspect(module)} defstruct contains focus state field(s): #{inspect(forbidden)}. " <>
             "Phase 28 D-16 forbids leaf widget focus state — focus is owned by Modal.Form."
    end
  end
end
```
This is a structural assertion against `__struct__/0` reflection; cannot flake.

**FORM-05 — Double-Enter idempotence:**
```elixir
test "two :enter events back-to-back invoke on_submit exactly once (D-05)" do
  pid = self()
  fields = [%{name: :x, type: :text, label: "X"}]
  form = Form.init(
    title: "T", fields: fields,
    on_submit: fn payload -> send(pid, {:submit_called, payload}) end,
    on_cancel: fn -> nil end
  )

  {f1, action1} = Form.handle_event(%{key: :enter}, form)
  assert action1 == :submitted
  assert f1.submit_state == :submitting
  assert_receive {:submit_called, _payload}, 100

  # Second Enter while :submitting must be swallowed by Clause 0.
  {f2, action2} = Form.handle_event(%{key: :enter}, f1)
  assert action2 == nil
  assert f2 == f1, "second Enter mutated state — lock guard failed"
  refute_receive {:submit_called, _}, 50
end
```
`assert_receive` / `refute_receive` use ExUnit's mailbox primitives — deterministic, no `Process.sleep`. The 100ms timeout is generous; the actual call is synchronous.

**FORM-05 — `:submitting` event lock (full event sweep):**
```elixir
test ":submitting swallows every event listed in the constraint (D-02)" do
  fields = [%{name: :x, type: :text, label: "X", value: "abc"}]
  form = %{Form.init(title: "T", fields: fields, on_submit: fn _ -> nil end, on_cancel: fn -> nil end)
           | submit_state: :submitting}

  events = [
    %{key: :tab}, %{key: :tab, shift: true}, %{key: :shift_tab}, %{key: :backtab},
    %{key: :up}, %{key: :down},
    %{key: :char, char: "z"}, %{key: :backspace},
    %{key: :enter}, %{key: :escape}
  ]

  for event <- events do
    {result, action} = Form.handle_event(event, form)
    assert result == form, "#{inspect(event)} mutated state under :submitting"
    assert action == nil, "#{inspect(event)} returned non-nil action under :submitting"
  end
end
```
Pure reduction; one assertion per event in a loop; no timing concerns.

### Sequence Tests for Focus Routing (FORM-04)

```elixir
test ":tab :tab :char 'x' lands 'x' in third field, leaves first/second empty (D-13, D-16, PITFALLS F1)" do
  fields = [
    %{name: :a, type: :text, label: "A"},
    %{name: :b, type: :text, label: "B"},
    %{name: :c, type: :text, label: "C"}
  ]
  form = test_form(fields)  # initial focus_index: 0

  events = [%{key: :tab}, %{key: :tab}, %{key: :char, char: "x"}]
  {final, _} = Enum.reduce(events, {form, nil}, fn ev, {f, _} ->
    Form.handle_event(ev, f)
  end)

  # Focus advances 0 → 1 → 2; "x" lands on field index 2 (third field).
  # Assert all three buffers to pin both the positive routing claim and the
  # negative "no stale write" claim in one test.
  assert Form.field_value(final, :a) == ""
  assert Form.field_value(final, :b) == ""
  assert Form.field_value(final, :c) == "x"
end
```

**Note:** SPEC FORM-04 was clarified 2026-04-27 — canonical assertion is "lands in the third field's buffer (index 2), with the first and second fields' buffers remaining empty," with explicit initial `focus_index: 0`. SPEC §4 acceptance, §Acceptance Criteria checkbox, and ROADMAP success criterion #5 are updated to match. (Was assumption A1; resolved.)

### `:up`/`:down` Enum Cycling Preservation (FORM-01)

```elixir
test "down on enum field cycles value and does NOT change focus (D-13)" do
  fields = [
    %{name: :a, type: :text, label: "A"},
    %{name: :b, type: :text, label: "B"},
    %{name: :c, type: :enum, label: "C", choices: [:x, :y, :z], value: :x}
  ]
  form = test_form(fields)

  # Move focus to the enum field
  {f1, _} = Form.handle_event(%{key: :down}, form)   # focus 0 → 1 (text)
  assert f1.focus_index == 1
  {f2, _} = Form.handle_event(%{key: :down}, f1)     # focus 1 → 2 (enum)
  assert f2.focus_index == 2
  assert Form.field_value(f2, :c) == :x

  # Subsequent :down events cycle the enum value, focus stays at 2
  {f3, _} = Form.handle_event(%{key: :down}, f2)
  assert f3.focus_index == 2, "focus moved off enum on :down — D-13 violated"
  assert Form.field_value(f3, :c) == :y

  {f4, _} = Form.handle_event(%{key: :up}, f3)
  assert f4.focus_index == 2
  assert Form.field_value(f4, :c) == :x
end
```

### Footer Suppression (FORM-03)

```elixir
test "default :show_footer is false; rendered output contains no [Enter] Submit (D-06)" do
  form = test_form()  # no :show_footer arg → defaults to false
  flat = form |> Form.render(theme: theme()) |> flatten_text()
  refute flat =~ "[Enter] Submit"
  refute flat =~ "[Esc] Cancel"
end

test "show_footer: true restores the footer for true overlay use (D-06)" do
  form = Form.init(
    title: "T",
    fields: [%{name: :x, type: :text, label: "X"}],
    show_footer: true,
    on_submit: fn _ -> nil end,
    on_cancel: fn -> nil end
  )
  flat = form |> Form.render(theme: theme()) |> flatten_text()
  assert flat =~ "[Enter] Submit"
  assert flat =~ "[Esc] Cancel"
end
```

The existing test at `form_test.exs:308-323` (`"D-19 refreshed body renders title, required markers, and action footer"`) currently asserts the footer **is** present. Phase 28 must update this test to either pass `show_footer: true` explicitly or assert the new default-off behavior. **PLANNER:** flag this as a test-update task, not just a codepath update.

### Layout Smoke at 64×22 / 80×24 (FORM-03)

```elixir
# Source pattern: test/foglet_bbs/tui/layout_smoke_test.exs:299-307 (existing template)
for {width, height} <- [{64, 22}, {80, 24}] do
  @width width
  @height height
  @tag :"phase_28 — no duplicate footer"
  test "Account Profile at #{width}x#{height} renders exactly one Enter/Esc hint group" do
    state = build_account_profile_state(@width, @height)
    rendered = render_full_screen(state)
    text = rendered |> collect_text_lines() |> Enum.join("\n")

    enter_count = Regex.scan(~r/\[Enter\]/, text) |> length()
    esc_count = Regex.scan(~r/\[Esc\]/, text) |> length()

    assert enter_count == 1, "expected 1 [Enter] hint at #{@width}x#{@height}, found #{enter_count}"
    assert esc_count == 1, "expected 1 [Esc] hint at #{@width}x#{@height}, found #{esc_count}"
  end
end
```

The single `[Enter]` hint comes from the global command bar (KeyBar / Sysop chrome); the substrate-side footer is suppressed by D-06 default.

### Esc Reseed Tests (FORM-06)

```elixir
test "Esc on ProfileForm reseeds drafts to saved values (D-10, D-11)" do
  user = %User{location: "Boston", tagline: "hi", real_name: "Alice"}
  state = State.seed_from_user(%State{}, user)

  # User edits the location field
  state = put_in_form_field(state, :profile_form, :location, "Tokyo")
  assert form_field_value(state, :profile_form, :location) == "Tokyo"

  # User presses Esc
  {:ok, new_state, _events} = ProfileForm.handle_key(%{key: :escape}, state, user)

  # Field reverts (D-10 — this is the visible signal)
  assert form_field_value(new_state, :profile_form, :location) == "Boston"
  # D-11: no status_message about discard
  refute new_state.status_message =~ "discarded",
         "Phase 28 D-11 removed the discard copy; got: #{inspect(new_state.status_message)}"
end
```

### What This Test Strategy Does NOT Need

- **No `Process.sleep`:** every transition is synchronous within `handle_event/2`.
- **No process monitors:** the form is a pure struct; there's no process to observe.
- **No PubSub fixtures:** Phase 28 doesn't subscribe to anything.
- **No Mox / Mock library:** `on_submit` callbacks send to `self()` and `assert_receive` does the rest. Existing pattern at `form_test.exs:27` already uses this.

## Runtime State Inventory

> N/A for greenfield substrate work. Phase 28 is **code-only** changes — no stored data, no live service config, no OS-registered state, no secrets, no build artifacts. Confirmed by:

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — no DB schema, no ETS keys, no Mem0 changes. `Foglet.Config` table writes pre-existed and behavior is unchanged. | None |
| Live service config | None — no n8n / Datadog / external service. | None |
| OS-registered state | None — no scheduled tasks, no pm2 processes. | None |
| Secrets/env vars | None — no new env vars. | None |
| Build artifacts | None — no compiled binaries; `mix precommit` will recompile from source. | None |

## Environment Availability

> N/A. Phase 28 is pure Elixir code changes within the existing project. No new external dependencies, no new tooling.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Elixir / OTP | All Foglet code | ✓ | (project's pinned version) | — |
| Raxol (vendored) | Modal.Form, render | ✓ | Vendored at `vendor/raxol/` | — |
| ExUnit | Tests | ✓ | bundled with Elixir | — |

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | ExUnit (bundled with Elixir; project uses `mix test`) |
| Config file | `mix.exs` + `test/test_helper.exs` |
| Quick run command | `rtk mix test test/foglet_bbs/tui/widgets/modal/form_test.exs` |
| Full suite command | `rtk mix test` |
| Phase precommit | `rtk mix precommit` (compile-warnings-as-errors + format + Credo + Sobelow + Dialyzer) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| FORM-01 | Up/Down focus on text/integer/textarea, enum cycling preserved | unit | `rtk mix test test/foglet_bbs/tui/widgets/modal/form_test.exs --only :"phase_28 form-01"` | ✅ form_test.exs |
| FORM-02 | `:backtab` ≡ `:shift_tab` | unit | `rtk mix test test/foglet_bbs/tui/widgets/modal/form_test.exs --only :"phase_28 form-02"` | ✅ form_test.exs |
| FORM-03 | Footer suppressed by default; opt-in restores it; no duplicate hints at 64×22/80×24 | unit + layout smoke | `rtk mix test test/foglet_bbs/tui/widgets/modal/form_test.exs test/foglet_bbs/tui/layout_smoke_test.exs --only :"phase_28 form-03"` | ✅ both exist |
| FORM-04 | Single-source-of-truth focus; no leaf widget focus state | unit + grep | `rtk mix test test/foglet_bbs/tui/widgets/leaf_focus_state_grep_test.exs` | ❌ Wave 0 — new file |
| FORM-05 | Submit-state FSM; double-Enter idempotence; `:submitting` lock | unit | `rtk mix test test/foglet_bbs/tui/widgets/modal/form_test.exs --only :"phase_28 form-05"` | ✅ form_test.exs |
| FORM-06 | Honest Esc on Profile/Prefs/Site reseeds drafts (no flash copy) | screen integration | `rtk mix test test/foglet_bbs/tui/screens/account/profile_form_test.exs test/foglet_bbs/tui/screens/account/prefs_form_test.exs test/foglet_bbs/tui/screens/sysop/site_form_test.exs --only :"phase_28 form-06"` | ✅ all three exist |
| FORM-03 / FORM-06 | SSH human verification at 64×22 and 80×24 | manual | `rtk mix foglet.tui.render account_profile --width 64 --height 22` and SSH session | manual — visual |

### Sampling Rate

- **Per task commit:** `rtk mix test test/foglet_bbs/tui/widgets/modal/form_test.exs` (under 10 seconds; covers most substrate unit tests)
- **Per wave merge:** `rtk mix test test/foglet_bbs/tui/` (full TUI suite; ~30-90 seconds)
- **Phase gate:** `rtk mix precommit` (full suite + format + Credo + Sobelow + Dialyzer; the AGENTS.md-mandated gate before declaring complete)

### Wave 0 Gaps

- [ ] `test/foglet_bbs/tui/widgets/leaf_focus_state_grep_test.exs` — new file, asserts D-16 (no leaf-widget focus state). Grep-based assertion against `__struct__/0` reflection.
- [ ] (Optional) Tag taxonomy — add `@tag :"phase_28 form-01"` etc. to new `describe` blocks so the per-requirement filtered test runs work cleanly. Existing tests are untagged; mixing tagged and untagged is fine.
- [ ] `test/foglet_bbs/tui/widgets/modal/form_test.exs:308-323` — existing "D-19 refreshed body renders title, required markers, and action footer" test currently asserts footer presence by default; must be updated for D-06's flipped default. This is a test rewrite, not a new file.

*(Framework install: not needed — ExUnit ships with Elixir; project's `mix.exs` already configures it.)*

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | Phase 28 does not touch auth; existing `Foglet.Authorization` permits remain in place. |
| V3 Session Management | no | No session changes. |
| V4 Access Control | partial | `Foglet.Config.put/3` already actor-aware (the `current_user` arg). SiteForm migration preserves this — `state.current_user` flows into the on_submit handler unchanged. Verified by `site_form.ex:251`. |
| V5 Input Validation | yes | Modal.Form coerces `:integer` via `Integer.parse/1` (returns `nil` on failure — `form.ex:335-340`). SiteForm validates delivery/verification pair before `Config.put/3` (D-20). No new untrusted input surfaces. |
| V6 Cryptography | no | No crypto in this phase. |

### Known Threat Patterns for Foglet TUI Stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Operator-only screens reachable by non-sysops | Elevation of Privilege | `Foglet.Config.put/3` returns `{:error, :forbidden}` for non-sysops; SiteForm migration must preserve the `current_user`-aware call. The boundary is in the boundary call, not the form — phase doesn't change this. |
| Double-submit causing duplicate writes | Tampering / DoS | D-05 / Pitfall 8 — `submit_state` FSM serializes Enter and the lock guard prevents re-entry. This phase is the mitigation. |
| Esc-during-submit racing the boundary | Tampering | Clause 0 lock guard swallows Esc during `:submitting` — `on_cancel` cannot fire while a save is in flight. |
| Stale draft saved after successful Esc | Tampering | D-12 mandates `Config.get!/1` reseed on Esc; the next render reflects authoritative values, not in-memory drafts. |

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Bespoke `▸ key: value` text rows in SiteForm | Modal.Form-rendered fields with TextInput/RadioGroup/Checkbox primitives | Phase 28 (D-18) | Tests that asserted on the bespoke format need rewriting. Visual diff at 64×22 will be slightly different (proper labels + widgets vs key strings). |
| Synchronous `on_submit.()` with no idempotence | `:idle → :submitting` FSM with lock guard | Phase 28 (D-05) | Eliminates the F3 bug class permanently. Existing consumers (Profile/Prefs) gain idempotence "for free" — no API changes required. |
| Status row "[Enter] Submit / [Esc] Cancel" rendered unconditionally | Conditional based on `:show_footer` (default off); `Saving…` row when `:submitting` | Phase 28 (D-06, D-08) | Fixes duplicate-footer chrome on Account/Sysop screens. Single overlay caller (`App.render_modal_overlay/2`) opts in. |
| `Modal.Form` recognizes `:shift_tab` and `%{key: :tab, shift: true}` only | `Modal.Form` also recognizes `:backtab` | Phase 28 (D-15) | Convergent with Sysop SiteForm/LimitsForm convention. CLIHandler-emitted shapes (`:shift_tab` from ESC[Z) and Raxol-native shapes (`%{key: :tab, shift: true}`) and Foglet bespoke shapes (`:backtab`) all dispatch identically. |

**Deprecated/outdated:**
- "Changes discarded." inline status flash on Esc — D-10 removes the chrome. Field reversion is the visible signal.
- Per-screen bespoke focus indices unbacked by Modal.Form — SiteForm was the last hold-out; Phase 28 retires it.

## Project Constraints (from AGENTS.md and CLAUDE.md)

| Directive | Source | How Phase 28 honors it |
|-----------|--------|------------------------|
| Use `rtk` as shell command prefix | AGENTS.md | All test commands prefixed `rtk mix test`. |
| No `Process.sleep/1` in tests | AGENTS.md | Test Strategy uses `assert_receive`/`refute_receive` only — entire substrate is synchronous. |
| No `Process.alive?/1` in tests | AGENTS.md | Modal.Form is a pure struct; no processes to observe. |
| Use `start_supervised!/1` for processes | AGENTS.md | N/A — no GenServers added. |
| Theme-routed colors only (D-07/D-09) | AGENTS.md, widgets/README.md | All new render rows use `theme.dim.fg` / `theme.error.fg`. Existing `flatten_text` + `color_atom_leaked?/2` test helpers enforce this. |
| Schemas own changesets; contexts own transactions | AGENTS.md | N/A — no schema/migration changes. |
| No browser-based form workflows | SPEC Constraints | N/A — Phase 28 is SSH-TUI only. |
| `mix precommit` must pass before declaring complete | AGENTS.md | Phase gate command: `rtk mix precommit`. |
| Stateful widgets expose `init/1` + `handle_event/2` + `render/2` (D-14) | widgets/README.md | Modal.Form already conforms; Phase 28 only adds clauses + struct fields. |
| Body-only render (no outer box/border) | form.ex:17-18 / Pitfall 4 | Phase 28 does not introduce wrapping; trailing rows are siblings of field rows. |
| `Foglet.Config.put/3` actor-aware writes | AGENTS.md | SiteForm `on_submit` continues to pass `state.current_user` as the actor. |
| TUI rendering inspectable via `mix foglet.tui.render` | AGENTS.md | Use `rtk mix foglet.tui.render account_profile --width 64 --height 22` for FORM-03 visual checks during development. |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | ~~SPEC FORM-04's "`:tab :tab :char 'x'` lands `'x'` in second field" arithmetic is inconsistent.~~ **RESOLVED 2026-04-27:** SPEC and ROADMAP updated to "third field's buffer" with explicit initial `focus_index: 0`. Canonical test asserts `"x"` lands in field index 2; field indexes 0 and 1 remain empty. | Test Strategy | n/a — resolved. |
| A2 | The auto-clear behavior of `:saved` and `{:error, _}` recurses into `handle_event/2` with `submit_state: :idle` so the original event still gets processed. | Pattern 1, Pitfall 2 | If implemented as a non-recursing clause, the user's first post-save keystroke is silently dropped. |
| A3 | The `set_submit_state/2` setter rejects `:submitting` silently (no-op) rather than raising. D-03 says "rejected if requested externally" without specifying mechanism. | Code Examples | If raising is intended, callers must wrap in try/rescue. Lower risk because no caller should invoke this — but the test should pin the chosen behavior. |
| A4 | Modal.Form's `:show_footer` opt-in at `init/1` (D-06/D-07) means the consumer cannot toggle the footer between renders without re-init. SiteForm's per-render re-init pattern (D-17) absorbs this. | Footer pattern | If a future use case wanted dynamic toggling, the option would have to move to `render/2`. Out of scope for Phase 28. |
| A5 | The visible-keys clamp of `focus_index` (Pitfall 7) is needed because conditional visibility can shrink the field list below the current focus. CONTEXT.md does not explicitly call this out. | Pitfall 7 | If not implemented, an `Enum.at(fields, focus_index)` call returns `nil` and a downstream `.type` access crashes — a real bug. **Recommendation:** test it explicitly. |

**Note on confidence:** Every other claim in this research is `[VERIFIED: codebase grep]` or `[CITED: form.ex:NN]` — assumptions above are the only items the planner should flag for user/spec confirmation before locking task definitions.

## Open Questions

1. ~~**SPEC FORM-04 arithmetic ambiguity (A1)**~~ **RESOLVED 2026-04-27.**
   - Resolution: Spec corrected — `:tab :tab :char "x"` on a `[text, text, text]` form with initial `focus_index: 0` lands `"x"` in the **third** field's buffer (index 2). Field indexes 0 and 1 remain empty. SPEC §4 acceptance, §Acceptance Criteria checkbox, and ROADMAP success criterion #5 all updated to match.
   - Test should assert all three field buffers (0 and 1 empty, 2 == `"x"`) to pin both the positive routing claim and the negative no-stale-write claim.

2. **`set_submit_state(:submitting)` rejection mechanism (A3)**
   - What we know: D-03 says "rejected if requested externally".
   - What's unclear: Silent no-op vs raise vs return `{:error, :reserved_transition}`.
   - Recommendation: Planner picks silent no-op (simpler, returns same struct unchanged) and pins it with a test. If user wants a raise-based contract, they can flag during plan-check.

3. **Visible-keys focus clamp (A5)**
   - What we know: CONTEXT.md D-21 mandates conditional visibility for `invite_generation_per_user_limit`.
   - What's unclear: Whether the spec author considered focus-drift when the visible field list shrinks.
   - Recommendation: Implement clamping defensively (Pitfall 7's pattern) and ship a unit test. Low cost to write; defensive against a real crash class.

## Sources

### Primary (HIGH confidence) — codebase
- `lib/foglet_bbs/tui/widgets/modal/form.ex` — substrate source of truth; line numbers cited throughout this research.
- `lib/foglet_bbs/tui/widgets/modal/form/submit_stash.ex` — payload-handoff pattern; preserved verbatim per D-05.
- `lib/foglet_bbs/tui/widgets/input/text_input.ex:42` — confirmed `defstruct [:raxol_state, :validator, :on_submit, last_action: nil]` (no focus field).
- `lib/foglet_bbs/tui/widgets/input/radio_group.ex:1-21` — confirmed stateless (no defstruct).
- `lib/foglet_bbs/tui/widgets/input/checkbox.ex:1-20` — confirmed stateless (no defstruct).
- `lib/foglet_bbs/tui/screens/account/profile_form.ex` — reference Modal.Form consumer (Pattern 3 source).
- `lib/foglet_bbs/tui/screens/account/prefs_form.ex` — reference Modal.Form consumer with enum live preview.
- `lib/foglet_bbs/tui/screens/sysop/site_form.ex` — current bespoke implementation; migration target.
- `lib/foglet_bbs/tui/app.ex:187,197` — single `render_modal_overlay/2` opt-in caller for `:show_footer: true`.
- `lib/foglet_bbs/tui/screens/sysop.ex:194-204` — `delegate_to_active_tab` dispatch into `SiteForm` (preserved by migration).
- `lib/foglet_bbs/tui/input.ex:14-20` — canonical flat-map key shapes (`:up`, `:down`, `:tab`, `:enter`, etc.).
- `test/foglet_bbs/tui/widgets/modal/form_test.exs` — established test patterns; existing tests at lines 195-241 (Tab/Shift-Tab wrap), 308-323 (footer assertion to flip), 412-440 (enum field_value/2), 444-516 (shift_tab event-shape parity).
- `test/foglet_bbs/tui/screens/sysop/site_form_test.exs` — current site form tests; rewrite per D-18.
- `test/foglet_bbs/tui/layout_smoke_test.exs:299-307` — 64×22 / 80×24 / 132×50 size-loop pattern to mirror for FORM-03.
- `.planning/research/PITFALLS.md:140-218` — F1 (focus state divergence), F3 (Enter re-fire), F4 (Tab affordance) — canonical statement of the bugs Phase 28 fixes.
- `.planning/phases/28-modal-form-substrate/28-SPEC.md` — six requirements + acceptance criteria.
- `.planning/phases/28-modal-form-substrate/28-CONTEXT.md` — 21 locked decisions D-01..D-21.
- `vendor/raxol/lib/raxol/ui/components/input/menu.ex:73-80`, `display/tree.ex:71-78` — Raxol's own components use `%Event{type: :key, data: %{key: :up}}` shape; Foglet flattens this at `Foglet.TUI.Input.translate_key/1`. **Verified: Raxol does not provide a multi-field form widget.**

### Secondary (MEDIUM confidence)
- `lib/foglet_bbs/tui/screens/sysop/limits_form.ex:56-57` — confirms the `:shift_tab` + `:backtab` adjacent-clause convention is already established in Foglet (D-15 brings Modal.Form into line).
- `AGENTS.md` — TUI/Modal.Form section (theme routing, screen vs widget boundaries, `mix precommit` gate).
- `CLAUDE.md` (project) — extends AGENTS.md verbatim.

### Tertiary (LOW confidence)
- None — every claim in this research has a verified source in the codebase or CONTEXT.md/SPEC.

## Metadata

**Confidence breakdown:**
- Standard stack: **HIGH** — fixed in-tree, no external alternatives.
- Architecture patterns: **HIGH** — every pattern traceable to existing code (Pattern 1/2/3 in form.ex; Pattern 4 mirrors ProfileForm exactly).
- Pitfalls: **HIGH** — F1/F3/F4 are documented in `.planning/research/PITFALLS.md` from a prior phase; this research extends them with phase-specific mechanics (Pitfall 1, 2, 5, 6, 7) inferred from the dispatch order and existing failure modes.
- Test strategy: **HIGH** — entire substrate is synchronous and pure; `assert_receive`/`refute_receive` patterns already established in `form_test.exs`.
- SiteForm migration: **MEDIUM-HIGH** — D-17..D-21 prescribe the shape; Pitfall 6 (Ctrl+S routing) and Pitfall 7 (focus clamp) are inferred risks the planner must address.

**Research date:** 2026-04-27
**Valid until:** 2026-05-27 (substrate is in-tree, low churn; refresh if Raxol vendor bumps or if Phase 29/30 lands first and changes consumer assumptions)
