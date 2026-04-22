# Phase 1: Login — Context

**Gathered:** 2026-04-21
**Status:** Ready for planning
**Workstream:** phase-03-screen-audit

<domain>
## Phase Boundary

Replace the hand-rolled `handle_form_key/2` family (~50 LoC, 6 helper functions) and
the `form` state map with two `Widgets.Input.TextInput` instances (handle + password);
add the missing `init_screen_state/1`; rewrite the nested `case {:ok,_}|{:error,_}`
authentication chain as a `with` chain; land at ~150 LoC from 347.

All auth behaviour — modal payloads, `post_login_screen` dispatch, verify-code path,
`register_wizard` initialisation in `maybe_register/1` — is preserved bit-for-bit.

**In scope:**
- Delete `format_input_line/3`, `input_fg/2`, `focus_style/1`, `mask_password/1`,
  `drop_last_grapheme/1`, `append_to_focused/2`, and the entire `handle_form_key/2` family.
- Add `init_screen_state/1`.
- Rewrite `submit_login/1` as a `with` chain.
- Adopt `Input.TextInput` for handle + password (masked).
- Consume a new `bordered: false` option on `Input.TextInput` (added by the micro-patch
  described in D-01 below).
- Verify AUDIT rubric items 05–22 pass.

**Out of scope:**
- Any modification to `Input.TextInput` itself — that is the pre-Phase-1 micro-patch (D-01).
- Any change to `Foglet.Config` render-path reads — safe per inherited decision (D-06).
- Any touch of `app.ex`, widgets, chrome, or other screens (AUDIT-13 scope fence).
- Adding layout regions not present today (AUDIT-17 — below error line reserved).

</domain>

<decisions>
## Implementation Decisions

### Pre-Phase micro-patch (required before Phase 1 planning begins)

- **D-01:** `Input.TextInput` receives a `bordered: false` option in a **standalone commit
  before Phase 1**. This commit touches only `lib/foglet_bbs/tui/widgets/input/text_input.ex`
  (and its test) and must pass `mix precommit`. It is NOT part of the Phase 1 audit diff —
  keeping the audit diff to one screen file preserves AUDIT-13.

  The option must default to `bordered: true` (no breaking change to existing callers).
  When `bordered: false`, `render/2` calls `RaxolTextInput.render` directly without
  wrapping in the outer `box`.

### Form field layout

- **D-02:** Label and TextInput are **inline on the same row** — visually identical to the
  current flat `"Handle:   value█"` format. The label is a `text/2` element; the TextInput
  is rendered with `bordered: false`.

  Approximate structure:
  ```
  Handle:   brendan_
  Password: ****_
  ```

  This preserves today's row density and the "gateway stays minimal forever" principle
  (AUDIT-17 — below error line protected for login/register/verify).

  This layout sets the visual precedent for Phase 2 (Register) and Phase 7 (NewThread).

### Screen state initialisation

- **D-03:** `init_screen_state/1` returns the **minimal menu sub-state**:
  ```elixir
  def init_screen_state(_opts), do: %{sub: :menu}
  ```
  TextInput structs are created lazily inside `enter_login_form/1` each time the user
  presses L. This keeps the per-session memory footprint small (no TextInput state
  allocated for users who log in via keyboard shortcut to the form for the first time
  ever, or who never open the form).

  `enter_login_form/1` creates fresh TextInput instances — form always clears on entry,
  consistent with current behaviour.

  This lazy-init strategy sets the D-14 initialisation pattern for Phases 2 and 7.

### Login form sub-state shape (when sub == :login_form)

- **D-04:** The active form state is a flat map in `screen_state[:login]`:
  ```elixir
  %{
    sub: :login_form,
    focused_field: :handle | :password,
    handle_input:  %Widgets.Input.TextInput{},
    password_input: %Widgets.Input.TextInput{},
    error: nil | "Invalid credentials."
  }
  ```
  No nested `form:` sub-map. The `form` map from today is eliminated entirely — TextInput
  structs own their own values; the screen owns `error:` and `focused_field:`.

  This flat shape is the D-14 canonical structure for a two-field form screen.
  Phase 2 (Register) inherits this shape for its own `screen_state[:register]`.

### Error state

- **D-05:** Auth errors live as a top-level `error: nil | string` field in `login_ss`.
  On failed auth, the planner sets `error: "Invalid credentials."` and clears the
  `password_input` TextInput state (preserve handle, clear password — consistent with
  current behaviour). The error is rendered as a `text/2` after the password field with
  `fg: theme.error.fg, style: [:bold]`.

  On successful auth or Escape-back-to-menu, `error` is cleared along with the form.

### Key routing

- **D-06:** The screen **intercepts Tab, Escape, and Enter** before delegating to
  `Input.TextInput`. Only char input, backspace, and cursor-movement keys are delegated
  to the focused TextInput.

  Pattern:
  ```elixir
  # Tab — intercepted, cycles focused_field
  defp handle_form_key(%{key: :tab}, state), do: ...

  # Escape — intercepted, returns to :menu sub, clears form
  defp handle_form_key(%{key: :escape}, state), do: ...

  # Enter — intercepted, advance focus (handle→password) or submit (password)
  defp handle_form_key(%{key: :enter}, state), do: ...

  # Everything else — delegate to focused TextInput
  defp handle_form_key(event, state) do
    {new_input, _action} = TextInput.handle_event(event, focused_input(state))
    {:update, update_focused_input(state, new_input), []}
  end
  ```

  The `_action` return from TextInput is discarded for delegated events — `:submitted`
  and `:cancelled` are never produced because Enter and Escape are intercepted first.

  This pattern sets the key-routing precedent for Phase 2 (Register) and Phase 7 (NewThread).

### `Foglet.Config` render-path (inherited, no action)

- **D-07:** `Config.get("registration_mode")` inside `registration_mode/1` is safe —
  `Foglet.Config` is ETS read-through cached (LOGIN-05 inherited decision). No change
  required to the render path; document only.

### `with` chain scope

- **D-08:** The `with` chain in `submit_login/1` replaces the nested `case {:ok,_}|{:error,_}`
  at lines 267–308. The existing `handle_active_user/2` and `start_verify_flow/2` private
  helpers are retained as factored-out branches. The planner decides the exact `with`
  clause structure; all happy/error branches (`:active` → promote or verify, `:pending`,
  `:suspended`, `:invalid_credentials`) must be preserved bit-for-bit.

### Claude's Discretion

- Exact `@spec` for `init_screen_state/1` — infer from D-14 pattern (`keyword() :: map()`).
- Names of any new private helpers (`focused_input/1`, `update_focused_input/3`,
  `clear_error/1`, etc.) — follow existing `get_login_ss`/`put_login_ss` naming style.
- Row layout macro for inline label+TextInput — use whatever Raxol view primitive
  (e.g. `row`, `column` with `gap: 0`) keeps the ANSI output identical to today.
- AUDIT-18 canonical section re-ordering: planner handles; Login has no major deviations
  expected (no `Code.ensure_loaded` oddity, no render_cache).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase requirements

- `.planning/workstreams/phase-03-screen-audit/REQUIREMENTS.md` §Phase 1 — LOGIN-01..06
  (TextInput adoption, deleted functions, state shape, with-chain, Config safety, rubric).
- `.planning/workstreams/phase-03-screen-audit/ROADMAP.md` §Phase 1 — 5 success criteria
  verbatim (347→~150 LoC, hand-rolled plumbing deleted, AUDIT-16 size gate).
- `.planning/workstreams/phase-03-screen-audit/REQUIREMENTS.md` §Audit-wide — AUDIT-05..22
  rubric (grep gates, widget contract, section order AUDIT-18, `init_screen_state/1` AUDIT-19).

### Workstream context

- `.planning/workstreams/phase-03-screen-audit/phases/00-cross-cutting-extractions-prelude/00-CONTEXT.md`
  — D-14 widget contract, test mirror convention, helper API shapes that Phase 1 consumes.

### Current screen and widget code

- `lib/foglet_bbs/tui/screens/login.ex` — current 347-LoC file; Phase 1 replaces this.
- `lib/foglet_bbs/tui/widgets/input/text_input.ex` — TextInput contract: `init/1`,
  `handle_event/2`, `render/2`. The `bordered: false` option added by the micro-patch
  (D-01) must be read here after the patch lands.

### Architecture and widget docs

- `docs/ARCHITECTURE.md` — App/screen/widget boundaries; D-14 stateful widget contract.
- `lib/foglet_bbs/tui/widgets/README.md` — overview of themed widgets in foglet_bbs.
- `docs/raxol/getting-started/WIDGET_GALLERY.md` — Raxol TextInput primitives.

### Project-level

- `CLAUDE.md` — Elixir gotchas (block-expression rebinding, struct Access, `mix precommit`).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable assets

- **`Theme.from_state/1`** — already called at `login.ex:36`; no Phase 0 migration needed
  for this file.
- **`get_login_ss/1` + `put_login_ss/2`** — existing private helpers for reading/writing
  `state.screen_state[:login]`. Keep (or rename) these; they are the right pattern.
- **`ScreenFrame.render/4`** — already called correctly; unchanged.
- **`keys_for/2`** — already returns `[{"Tab", "Switch field"}, {"Enter", "Submit/Next"},
  {"Esc", "Cancel"}]` for `:login_form`. Unchanged.

### Functions to delete (LOGIN-02)

- `format_input_line/3` (`:217`)
- `input_fg/2` (`:221`)
- `focus_style/1` (`:213`)
- `mask_password/1` (`:225`)
- `drop_last_grapheme/1` (`:137`)
- `append_to_focused/2` (`:126`)
- `handle_form_key/2` family — replaced by new key routing pattern (D-06)

### Functions to rewrite

- `render_login_form/2` — uses `format_input_line`, `input_fg`, `focus_style`, `mask_password`.
  Rewrite to row layout with `text/2` label + `TextInput.render(state, [bordered: false, theme: theme])`.
- `enter_login_form/1` — rewrite to create fresh TextInput structs (D-03).
- `submit_login/1` — rewrite as `with` chain (D-08), keeping `handle_active_user/2` and
  `start_verify_flow/2` as-is.

### Existing handle_form_key/2 mapping to new routing

| Current handler | New behaviour |
|---|---|
| `%{key: :tab}` | Screen intercepts — cycle `focused_field` |
| `%{key: :enter}` | Screen intercepts — advance to :password or submit |
| `%{key: :backspace}` | Delegated to focused TextInput |
| `%{key: :escape}` | Screen intercepts — return to :menu, clear form |
| `%{key: :char, char: c}` | Delegated to focused TextInput |
| catch-all `:no_match` | Delegated to TextInput (returns `{state, nil}`), then `:no_match` |

### Integration points

- `state.screen_state[:login]` — sole storage; no top-level state fields used by Login.
- `Accounts.authenticate_by_password/2` — synchronous; no spinner needed (AUDIT-10).
- `Accounts.post_login_screen/1`, `Accounts.build_verify_code/1` — existing, unchanged.
- `state.register_wizard` write in `maybe_register/1` — this is pre-Phase-2 state; Phase 1
  does NOT migrate it (that belongs to Phase 2). Leave `maybe_register/1` exactly as-is.

</code_context>

<specifics>
## Specific Ideas

- **Micro-patch first.** The `bordered: false` option on `Input.TextInput` must land as
  a green standalone commit before the Phase 1 plan is written. The plan should reference
  the widget file post-patch and depend on `bordered: false` being available.
- **Visual parity goal.** The login form post-migration should be visually indistinguishable
  from today at default terminal size — the only user-visible change is the cursor style
  (TextInput cursor vs. `█` block), which is the accepted drift per the workstream locked
  decision.
- **~150 LoC target.** Deleting the 6 hand-rolled helpers, the `form` map handling,
  and the old `handle_form_key/2` family accounts for ~70 LoC. The `with` chain is
  typically shorter than nested `case`. Verify AUDIT-16 at the end of the plan.

</specifics>

<deferred>
## Deferred Ideas

- **`bordered: true` form variant** — the micro-patch adds the option but Phase 1 uses
  `bordered: false`. If a future screen wants a boxed input, the option is available.
- **Cursor style parity** — FUT-03 (extend `Input.TextInput` with a `█`-block cursor)
  remains deferred. Visual drift from the block cursor is accepted per workstream locked
  decision.
- **Input value extraction helper** — if getting `raxol_state.value` from a TextInput
  struct needs a wrapper, that's a planner decision; don't add a shared helper
  (AUDIT-14 prohibits new shared modules).

</deferred>

---

*Phase: 01-login*
*Context gathered: 2026-04-21*
