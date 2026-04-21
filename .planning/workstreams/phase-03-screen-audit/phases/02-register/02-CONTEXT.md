# Phase 2: Register — Context

**Gathered:** 2026-04-21
**Status:** Ready for planning
**Workstream:** phase-03-screen-audit

<domain>
## Phase Boundary

Apply Phase 1's `Input.TextInput` pattern to the wizard's single-line input, collapsing the
current multi-step sequential wizard into a two-step structure:

- **invite_only mode:** `invite_code step → combined step (handle + email + password + confirm_password) → submit`
- **open / sysop_approved mode:** `combined step (handle + email + password + confirm_password) → submit`

Migrate `state.register_wizard` (top-level App struct field) to `state.screen_state[:register]`;
rewrite the `submit/2` registration pipeline as a `with` chain; land at strictly lower LoC.

**In scope:**
- Restructure wizard from sequential one-field-per-step to two-step form:
  - `:invite_code` step: single TextInput (unchanged semantics, gains TextInput widget)
  - `:combined` step: four TextInput instances — handle, email, password (masked), confirm_password (masked)
- Add `init_screen_state/1` (AUDIT-19), implementing lazy self-init from `screen_state[:register]`
- Remove `state.register_wizard` from App struct (`app.ex:53-56`)
- Migrate wizard dispatch at `app.ex:354-361` (`:submit_step` / `:cancel_step`) to read/write through `state.screen_state[:register]`
- Update `login.ex:maybe_register/1` to remove the `register_wizard: default_wizard(state)` write (AUDIT-13(b) expanded — see D-05)
- Rewrite `submit/2` as a `with` chain (REGISTER-03 / AUDIT-09)
- Preserve `apply/3` + `function_exported?/3` + `credo:disable` for `consume_invite_code` verbatim (REGISTER-04)
- Verify AUDIT rubric items 05–22 pass; `mix precommit` green

**Out of scope:**
- Any modification to `Input.TextInput` itself (micro-patch already shipped as D-01 pre-Phase-1)
- Any touch of `app.ex` beyond lines 53-56 and 354-361, and `login.ex` beyond `maybe_register/1`
- Adding layout regions not present today (AUDIT-17 — below error line reserved on gateway screens)
- Pre-migrating `state.verify_state` writes in `submit/2` — Phase 3 owns that

</domain>

<decisions>
## Implementation Decisions

### Wizard step restructure (NEW — user decision, overrides ROADMAP sequential flow)

- **D-01:** The wizard is restructured from sequential one-field-per-step to a **two-step form**:

  **Step `:invite_code`** (invite_only mode only):
  - Single `Input.TextInput` instance, `bordered: false`
  - Enter validates and advances to the `:combined` step

  **Step `:combined`** (all modes — the only step for open/sysop_approved):
  - Four `Input.TextInput` instances: `:handle`, `:email`, `:password`, `:confirm_password`
  - Password and confirm_password fields use `mask_char: "*"`
  - Tab cycles focus: handle → email → password → confirm_password → (wrap to handle)
  - Enter on `:handle`, `:email`, `:password` advances focus to next field
  - Enter on `:confirm_password` submits (validates confirm == password, then calls `submit/2`)
  - Escape cancels (returns to login screen, clears wizard state)

  This replaces the current `handle → email → password` sequential flow. The `:confirm` step
  described in REQUIREMENTS REGISTER-06 Watch List (iv) is the `confirm_password` field within
  the `:combined` step, not a separate wizard step.

- **D-02:** Key routing on `:combined` step follows Phase 1 D-06 precedent:
  - Tab: screen intercepts, cycles `focused_field` (handle → email → password → confirm_password)
  - Escape: screen intercepts, transitions to `:login`, clears `screen_state[:register]`
  - Enter: screen intercepts — advances focus to next field OR submits on last field
  - All other keys (char, backspace, cursor movement): delegated to the focused TextInput

- **D-03:** Confirm-password validation: on Enter from `:confirm_password`, the screen validates
  `password_input.value == confirm_password_input.value` before calling `submit/2`. On mismatch,
  set `error: "Passwords do not match."` in `screen_state[:register]` without advancing.

### Wizard state shape

- **D-04:** `screen_state[:register]` is a flat map (follows Phase 1 D-04 flat-map precedent):
  ```elixir
  %{
    mode:                 "open" | "invite_only" | "sysop_approved",
    step:                 :invite_code | :combined,
    focused_field:        :handle | :email | :password | :confirm_password | :invite_code,
    invite_code_input:    %Widgets.Input.TextInput{},   # nil when step != :invite_code
    handle_input:         %Widgets.Input.TextInput{},
    email_input:          %Widgets.Input.TextInput{},
    password_input:       %Widgets.Input.TextInput{},
    confirm_input:        %Widgets.Input.TextInput{},
    collected:            %{},                          # accumulates :invite_code after step advance
    error:                nil | String.t()
  }
  ```

  No nested `data:` sub-map — the `collected:` key accumulates validated step outputs (invite code).
  Handle, email, password values are read directly from the TextInput structs at submit time.

  `init_screen_state/1` returns the `:combined` default (mode read from `registration_mode/1`
  at init time). If mode is `"invite_only"`, `step` is `:invite_code`; otherwise `:combined`.
  TextInput structs are created eagerly inside `init_screen_state/1` (all four present from the
  start, regardless of mode — simpler than lazy allocation per step because the `:combined` step
  always needs all four).

- **D-05 (AUDIT-19):** `init_screen_state/1` is public with spec:
  ```elixir
  @spec init_screen_state(keyword()) :: map()
  def init_screen_state(opts \\ [])
  ```
  Opts currently unused but present for AUDIT-19 signature conformance.

### Wizard initialization (self-init)

- **D-06:** `register.ex` self-initializes `screen_state[:register]` lazily:
  ```elixir
  defp get_register_ss(state) do
    get_in(state, [:screen_state, :register]) || init_screen_state()
  end
  ```
  `login.ex:maybe_register/1` drops the `register_wizard: default_wizard(state)` write —
  it becomes `%{state | current_screen: :register}` only. `app.ex` does not initialize the
  wizard state; `register.ex` owns its own state bootstrap on first render/keypress.

### AUDIT-13(b) scope-fence expansion

- **D-07:** AUDIT-13(b) is expanded to cover one additional touch:
  - `login.ex:maybe_register/1` — remove `register_wizard: default_wizard(state)` write
    (one-line deletion; no behavioral change since `register.ex` self-initializes)
  - Previously documented: `app.ex:53-56` (field declaration) and `app.ex:354-361` (wizard dispatch)
  - No other `login.ex` or `app.ex` lines may be touched.

### app.ex wizard dispatch migration

- **D-08:** `app.ex:354-361` wizard dispatch is rewritten to route through `screen_state[:register]`:
  - Remove the `defp do_update({:register_wizard, event}, state)` clause that calls
    `Screens.Register.handle_wizard_event/2` (or migrate `handle_wizard_event/2` to accept
    `screen_state[:register]` directly — planner's choice on exact naming)
  - `:submit_step` self-dispatch semantics preserved: submitting a step still round-trips
    through `App.update/2` to advance the wizard (REGISTER-06 Watch List (i))
  - Modal-close `screen_state: %{}` reset behavior preserved (Watch List (ii))
  - Key-dispatch ordering in `handle_key/2` preserved — source-order dependencies load-bearing
    (Watch List (iii) / Pitfall 6)

### `with` chain scope

- **D-09:** The `with` chain refactor (REGISTER-03 / AUDIT-09) targets the nested
  `case {:ok,_}|{:error,_}` chains inside `submit/2`. The `sysop_approved` head is simple
  enough to refactor separately; the open/invite_only head gets a `with` chain covering:
  `register_user` → `post_login_screen` → `build_verify_code`. Planner decides the exact
  clause structure; all existing branches (verify path, main_menu path, changeset errors,
  build_verify_code error) must be preserved bit-for-bit.

  The existing `apply(Foglet.Accounts, :consume_invite_code, [code])` + `function_exported?/3`
  guard + `# credo:disable-for-next-line` at `valid_invite_code?/1` is preserved verbatim (D-04
  REGISTER-04 — this suppression is the documented exception in AUDIT-15).

### `Foglet.Config` render-path (inherited, no action)

- **D-10:** `Config.get("registration_mode")` inside `registration_mode/1` is safe —
  `Foglet.Config` is ETS read-through cached (workstream locked decision). No change
  required to the render path; document only (same as Phase 1 D-07).

### Claude's Discretion

- Exact naming of the registration screen state helpers (`get_register_ss/1`, `put_register_ss/2`,
  `clear_register_ss/2`, etc.) — follow Phase 1 `get_login_ss`/`put_login_ss` naming style.
- Whether `handle_wizard_event/2` is kept as a public function (§6 domain hooks in AUDIT-18
  canonical layout) or collapsed into the `do_update` dispatch directly — planner's call.
- AUDIT-18 canonical section ordering — planner handles the reorder; Register has no unexpected
  deviations expected beyond `handle_wizard_event/2` placement.
- Line count target: current 294 LoC. Deleting the sequential step handlers and the nested
  `case` chains should bring this below 294. Planner verifies AUDIT-16 at end of plan.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase requirements

- `.planning/workstreams/phase-03-screen-audit/REQUIREMENTS.md` §Phase 2 — REGISTER-01..06
  (TextInput adoption, wizard-step dispatcher, with-chain, consume_invite_code preservation,
  rubric, top-level wizard-state migration + Watch List)
- `.planning/workstreams/phase-03-screen-audit/ROADMAP.md` §Phase 2 — 5 success criteria
  verbatim (TextInput in all steps, AUDIT-16 size gate, wizard-state migration, with-chain,
  rubric pass)
- `.planning/workstreams/phase-03-screen-audit/REQUIREMENTS.md` §Audit-wide — AUDIT-05..22
  rubric (grep gates, widget contract, section order AUDIT-18, `init_screen_state/1` AUDIT-19)

### Phase 1 inherited patterns (MUST read)

- `.planning/workstreams/phase-03-screen-audit/phases/01-login/01-CONTEXT.md`
  — D-01 (`bordered: false` micro-patch), D-02 (inline label+TextInput row layout),
  D-03 (lazy TextInput init — NOTE: Phase 2 uses eager init for TextInput structs in
  init_screen_state/1; the lazy principle applies at the screen-state level not field level),
  D-04 (flat screen_state shape), D-06 (key routing: screen intercepts Tab/Escape/Enter)

### Phase 0 shared helpers

- `.planning/workstreams/phase-03-screen-audit/phases/00-cross-cutting-extractions-prelude/00-CONTEXT.md`
  — D-01 (`Theme.from_state/1` API), D-02 (`Screens.Domain.get/2` API)

### Current screen and widget code

- `lib/foglet_bbs/tui/screens/register.ex` — current 294-LoC file; Phase 2 replaces this.
- `lib/foglet_bbs/tui/widgets/input/text_input.ex` — TextInput contract: `init/1`,
  `handle_event/2`, `render/2`, `bordered: false` option (D-01 micro-patch).
- `lib/foglet_bbs/tui/app.ex` — `defstruct` at `:53-56` (remove `register_wizard` field);
  `do_update({:register_wizard, event}, state)` at `:354-361` (migrate wizard dispatch).
- `lib/foglet_bbs/tui/screens/login.ex` — `maybe_register/1` function (remove
  `register_wizard: default_wizard(state)` write; this is the AUDIT-13(b) expansion).

### Architecture and widget docs

- `docs/ARCHITECTURE.md` — App/screen/widget boundaries; D-14 stateful widget contract.
- `lib/foglet_bbs/tui/widgets/README.md` — overview of themed widgets in foglet_bbs.
- `docs/raxol/getting-started/WIDGET_GALLERY.md` — Raxol TextInput primitives.

### Project-level

- `CLAUDE.md` — Elixir gotchas (block-expression rebinding, struct Access, `mix precommit`).

</canonical_refs>

<code_context>
## Existing Code Insights

### Current wizard architecture (to be replaced)

- `default_wizard/1` (private) — creates initial wizard map with `:mode`, `:step`, `:data`,
  `:error`, `:current_input`. Replaced by `init_screen_state/1`.
- `advance/4` (private, per-step clauses) — one clause per step, reads `current_input`, writes
  updated wizard map. Replaced by: for `:invite_code`, a single validation + step-advance;
  for `:combined`, the Enter-on-confirm submission path.
- `handle_wizard_event/2` (public) — dispatched from `app.ex`. Will read/write
  `screen_state[:register]` post-migration.
- `submit/2` (private, two heads) — `sysop_approved` head simple case; open/invite_only head
  has three nested cases (`register_user` → `post_login_screen` → `build_verify_code`).
  Both heads write `state.register_wizard` — must migrate to `screen_state[:register]`.

### Preserved verbatim

- `valid_invite_code?/1` — `apply/3` + `function_exported?/3` + `credo:disable` block.
  Touch only if formatting forces it; must compile green.
- `maybe_log_verify_code/2` — conditional `if @log_verify_codes do...end` macro block.
- `changeset_error_text/1` — unchanged.
- `registration_mode/1` and `session_ctx/1` — unchanged (Config render-path safe per D-10).

### Integration points

- `state.screen_state[:register]` — sole storage after Phase 2 (no top-level struct field).
- `Accounts.register_user/1`, `Accounts.register_pending_user/1` — synchronous; no spinner
  (ops complete before next render frame; AUDIT-10 evaluates spinner only for async ops).
- `Accounts.post_login_screen/1`, `Accounts.build_verify_code/1` — existing, unchanged.
- `state.verify_state: %{...}` write in `submit/2` — left as-is; Phase 3 migrates it.

### State migration impact

- `app.ex:53-56`: Remove `register_wizard: map() | nil` from `@type t` and `defstruct`.
- `app.ex:354-361`: Migrate `do_update({:register_wizard, event}, state)` dispatch.
- `login.ex:maybe_register/1`: Drop `register_wizard: default_wizard(state)` from the
  `%{state | ...}` update — leave only `current_screen: :register`.

</code_context>

<specifics>
## Specific Ideas

- **Combined step is a 4-field form**, structurally analogous to Phase 1's 2-field login form.
  The planner should mirror login.ex's post-Phase-1 structure (screen_state sub-map + focused_field
  + TextInput structs + error key) but extended to 4 fields.
- **Confirm-password validation** is screen-side (compare `password_input.value` and
  `confirm_input.value` on Enter from confirm), not an `Accounts` call.
- **Wizard step display**: for the `:combined` step, all four fields are rendered simultaneously
  (same row structure as Phase 1 login form). For the `:invite_code` step, only one field is
  shown. The `error` field is rendered below the last visible field per AUDIT-17 (no fill below).
- **AUDIT-18 canonical section order**: Register has `handle_wizard_event/2` as a public function
  called from `app.ex`. It belongs in §6 (public domain-hook callbacks) of the canonical layout.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 02-register*
*Context gathered: 2026-04-21*
