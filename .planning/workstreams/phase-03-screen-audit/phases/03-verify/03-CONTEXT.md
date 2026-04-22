# Phase 3: Verify - Context

**Gathered:** 2026-04-21
**Status:** Ready for planning
**Workstream:** phase-03-screen-audit

<domain>
## Phase Boundary

Audit the `verify.ex` screen without changing its visible behavior model:

- Keep the hand-rolled 6-character `[ABC___]` slot visualization.
- Preserve the 5-attempt lockout semantics and the separate resend cooldown semantics shipped in `phase-03-polish` Phase 6.
- Migrate verify UI state from top-level `state.verify_state` into `state.screen_state[:verify]`.
- Consolidate the repeated default-state map literals behind a file-local private helper.
- Reorder the file to the canonical screen layout and add `init_screen_state/1` per AUDIT-18/AUDIT-19.

**In scope:**
- Add public `init_screen_state/1`.
- Add private `default_verify_state/0`.
- Replace the repeated inline default-state maps in `verify.ex` with the helper.
- Remove top-level `verify_state` ownership from `app.ex`.
- Update the Verify dispatch path to read/write `state.screen_state[:verify]`.
- Update the Verify entry points in `login.ex` and `register.ex` so they no longer seed a top-level `verify_state`.
- Update Verify tests and any layout smoke coverage to the new state shape.

**Out of scope:**
- Replacing the hand-rolled buffer with `Input.TextInput`.
- Any new visual treatment, inline banners, countdown rows, or additional helper modules.
- Any behavioral re-interpretation of resend, cooldown, lockout, or modal flows.
- Any cross-screen polish beyond the minimal entry-point touches needed for the state migration.

</domain>

<decisions>
## Implementation Decisions

### Verify-state ownership

- **D-01:** `verify.ex` owns the canonical Verify screen state after this phase. The public entry point is `init_screen_state/1`, and the file-local private helper `default_verify_state/0` is the single source of truth for the default map.
- **D-02:** `state.verify_state` is removed from the top-level `Foglet.TUI.App` struct. The canonical store becomes `state.screen_state[:verify]`.
- **D-03:** `login.ex` and `register.ex` stop constructing a top-level verify-state map when routing a user to `:verify`. They only set the navigation/user fields needed to enter the screen. `verify.ex` self-initializes from `screen_state[:verify]`.

### State shape and helper policy

- **D-04:** The default verify state remains structurally identical to today's behavior:
  ```elixir
  %{
    buffer: "",
    attempts: 0,
    cooldown_until: nil,
    resend_cooldown_until: nil
  }
  ```
- **D-05:** `default_verify_state/0` is private and file-local. No new shared helper module is introduced; this stays within AUDIT-14.
- **D-06:** `init_screen_state/1` returns the same map as `default_verify_state/0`. No additional view-only fields, timestamps, or UX bookkeeping keys are added.

### Cooldown feedback presentation

- **D-07:** Keep the current minimal Verify presentation. The inline render area continues to show only the instruction line, the slot visualization, and the existing status line.
- **D-08:** Blocked submit and blocked resend continue to use modal feedback (`state.modal`) rather than adding inline countdown text or extra persistent rows to the screen content.
- **D-09:** No inline resend countdown line is added. This preserves the gateway-screen sparseness rule and avoids claiming the area below the existing error/status region.

### Reset semantics

- **D-10:** Entering `:verify` starts with a fresh default verify state unless the user is already actively on the Verify screen in the same screen session. Entry paths from Login/Register should not carry forward a stale buffer or stale counters.
- **D-11:** Escape from Verify clears `screen_state[:verify]` and returns to `:login`, matching the current "cancel verification flow" behavior.
- **D-12:** Successful verify completion clears `screen_state[:verify]`.
- **D-13:** Register/login flows that successfully route to `:main_menu` never initialize verify screen state.

### Locked inherited behavior

- **D-14:** The 6-character `[ABC___]` buffer stays hand-rolled. This is the inherited `phase-03-polish` decision and must be documented in the moduledoc: TextInput cannot reproduce the slot visualization cleanly without a custom renderer and would conflict with the current flat display.
- **D-15:** The two-timer model stays intact:
  - `cooldown_until` gates code-entry submission after 5 failed attempts.
  - `resend_cooldown_until` gates resend requests only.
  - These timers are independent.
- **D-16:** Successful resend continues to clear `buffer`, `attempts`, and `cooldown_until`, then sets `resend_cooldown_until`. This is already locked from `phase-03-polish` Phase 6 and must not be reinterpreted during the audit.
- **D-17:** The existing modal-copy model stays intact:
  - invalid attempts show the existing invalid-code modal,
  - blocked cooldown actions show the existing "Wait Ns." modal,
  - successful resend shows the existing info modal.

### File organization and scope fence

- **D-18:** `verify.ex` is reordered to match the canonical screen section order from AUDIT-18. Any deviation must be justified in the moduledoc.
- **D-19:** `verify.ex` gains a public `init_screen_state/1` to satisfy AUDIT-19.
- **D-20:** Phase 3 operates under the documented AUDIT-13(c) exception:
  - `lib/foglet_bbs/tui/screens/verify.ex`
  - `lib/foglet_bbs/tui/app.ex` for top-level field removal + Verify dispatch migration
  - `lib/foglet_bbs/tui/screens/login.ex` and `register.ex` only where they seed Verify entry state
  - matching tests that must move from `verify_state` to `screen_state[:verify]`

### Claude's Discretion

- Exact helper names beyond `init_screen_state/1` and `default_verify_state/0` (`get_verify_ss/1`, `put_verify_ss/2`, `clear_verify_ss/1`) are planner discretion; follow the existing naming style used in audited screens.
- Whether `handle_verify_event/2` remains public as a dedicated dispatch entry point or is slightly reshaped internally is planner discretion, as long as `App.update/2` still has a clean Verify dispatch path.
- Exact moduledoc wording is planner discretion, but it must explicitly cite the inherited keep-hand-rolled decision and any canonical-layout deviation if one remains after reordering.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase requirements

- `.planning/workstreams/phase-03-screen-audit/REQUIREMENTS.md` — VERIFY-01..VERIFY-05 and audit-wide AUDIT-05..22.
- `.planning/workstreams/phase-03-screen-audit/ROADMAP.md` — Phase 3 goal, success criteria, and the AUDIT-13(c) scope-fence exception.
- `.planning/workstreams/phase-03-screen-audit/STATE.md` — confirms Phase 3 is next and that the wizard-state migration pattern established in Phase 2 is inherited here.

### Prior workstream context this phase inherits

- `.planning/workstreams/phase-03-polish/phases/06-email-verification-toggle-resend/06-RESEARCH.md` — documents the two-independent-cooldowns model, the extracted `cooldown_modal/2`, and the locked resend-reset semantics.
- `.planning/workstreams/phase-03-polish/phases/06-email-verification-toggle-resend/06-VERIFICATION.md` — verifies the resend affordance, cooldown feedback, config-driven resend duration, and the current verify-state shape.
- `.planning/workstreams/phase-03-polish/phases/07-migrate-hand-rolled-ui-components-to-raxol-widgets/07-CONTEXT.md` — explicitly locks the Verify code buffer as intentionally hand-rolled.

### Phase 2 precedent to inherit

- `.planning/workstreams/phase-03-screen-audit/phases/02-register/02-CONTEXT.md` — state migration precedent: screen owns its own `screen_state`, entry path stops owning the top-level wizard state, and `init_screen_state/1` is the canonical public initializer.

### Code to read before planning

- `lib/foglet_bbs/tui/screens/verify.ex` — current Verify implementation with duplicated default-state literals and top-level `verify_state` ownership.
- `lib/foglet_bbs/tui/app.ex` — current top-level `verify_state` field and `{:verify_event, event}` dispatch path.
- `lib/foglet_bbs/tui/screens/login.ex` — Verify entry path in `start_verify_flow/2`.
- `lib/foglet_bbs/tui/screens/register.ex` — Verify entry path in `handle_register_success/4`.
- `test/foglet_bbs/tui/screens/verify_test.exs` — current tests that still assert against top-level `verify_state`.
- `test/foglet_bbs/tui/layout_smoke_test.exs` — Verify render smoke coverage using the current top-level state shape.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable assets

- `Theme.from_state/1` is already in place, so Phase 3 does not need any theme-lookup changes.
- The current Verify implementation already has the exact slot-rendering behavior the workstream wants to keep.
- The current Verify tests already cover the important behavioral seams:
  - code entry and uppercasing,
  - 5-attempt lockout,
  - resend cooldown,
  - resend-vs-entry independence,
  - config-driven resend duration.

### Established patterns

- Phase 2 established the screen-owned-state migration pattern: entry paths stop seeding a top-level state blob and the screen owns initialization through `screen_state`.
- Gateway screens in this workstream keep a strict sparseness bias. Verify should not gain new persistent rows for status copy or helper text.
- Modal feedback is already the accepted mechanism for transient blocked-action messaging.

### Integration points

- `app.ex` must drop `verify_state` from the struct and keep Verify event dispatch working against `screen_state[:verify]`.
- `login.ex` and `register.ex` must stop creating a top-level verify-state map when routing into Verify.
- The Verify tests and layout smoke test must move to the new state ownership model so the migration is locked by coverage.

</code_context>

<specifics>
## Specific Ideas

- The accepted default path is "no more discussion" rather than adding new UX decisions. Planning should treat the current screen as visually correct and focus on state ownership, duplication removal, and canonical module shape.
- The screen should continue to look like a gateway, not a dashboard: one instruction line, one slot-display line, one status line, and modal overlays for temporary feedback.
- The migration should eliminate the repeated inline `%{buffer: \"\", attempts: 0, cooldown_until: nil, resend_cooldown_until: nil}` literals everywhere they appear in `verify.ex`.

</specifics>

<deferred>
## Deferred Ideas

- Inline resend countdown text or a dedicated cooldown row — deferred; out of scope for this restraint audit.
- Converting the Verify screen to `Input.TextInput` with a custom renderer — deferred; explicitly rejected by inherited decisions.
- Any broader gateway-screen UX redesign shared across login/register/verify — separate work, not part of this phase.

</deferred>

---

*Phase: 03-verify*
*Context gathered: 2026-04-21*
