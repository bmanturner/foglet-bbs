# Phase 29: Sysop Tab Lifecycle & Bodies — Specification

**Created:** 2026-04-27
**Ambiguity score:** 0.169 (gate: ≤ 0.20)
**Requirements:** 7 locked

## Goal

The Sysop screen's BOARDS, LIMITS, SYSTEM, and USERS tabs auto-load on entry through `Foglet.TUI.Command`, render an honest `:not_loaded | :loading | {:loaded, data} | {:error, reason}` lifecycle with a `[R] Retry` keybind on errors, and the operator-facing surfaces (Sysop Site draft echo + persist + Esc reset, USERS keybind gating + transition copy, INVITES row focus + `[X] Revoke`, consistent `1-N Jump` advertising on Account/Moderation/Sysop) work end-to-end for an operator without typing a key to "wake up" a tab.

## Background

`Foglet.TUI.Screens.Sysop` (`lib/foglet_bbs/tui/screens/sysop.ex`) renders six tabs — `SITE`, `BOARDS`, `LIMITS`, `SYSTEM`, `USERS`, and (when the actor sees them) `INVITES`. Tab navigation is delegated to `Foglet.TUI.Widgets.Input.Tabs`; the screen-local state is `Foglet.TUI.Screens.Sysop.State` keyed in `state.screen_state[:sysop]`.

Today every non-INVITES tab body opens with a placeholder row — for example `placeholder("Press any key to load runtime limits.", theme)` — and the corresponding submodule struct is only initialised lazily inside `delegate_to_active_tab/3` (`sysop.ex:194`) on the first key event the user routes there:

```elixir
defp delegate_to_submodule(event, state, ss, field, module) do
  sub = Map.get(ss, field) || module.init(current_user: state.current_user)
  {new_sub, events} = module.handle_key(event, sub)
  ...
end
```

Only `INVITES` has a primitive auto-load via `maybe_load_invites_on_entry/2` (`sysop.ex:220`). `Foglet.TUI.Command.task/2` already exists (`lib/foglet_bbs/tui/command.ex`) and is used by `Foglet.TUI.App` for boards, oneliners, and moderation loads — but is never used by Sysop tabs.

The `State` struct (`sysop/state.ex`) holds each submodule slot as plain `term() | nil`:

```elixir
defstruct [
  :tabs,
  active_tab: 0,
  tab_labels: @base_tabs,
  invites: InvitesState.new(),
  site_form: nil,
  limits_form: nil,
  boards_view: nil,
  system_snapshot: nil,
  users_view: nil
]
```

There is no tagged `:not_loaded | :loading | {:loaded, data} | {:error, reason}` state today — a load failure has no honest representation, and there is no `[R] Retry` keybind anywhere in the Sysop render path.

`Foglet.TUI.Screens.Sysop.SiteForm` (`lib/foglet_bbs/tui/screens/sysop/site_form.ex`) seeds drafts synchronously from `Foglet.Config.get!/1` inside `init/1`, renders them inline, and `submit/1` already calls `Foglet.Config.put/3` for every visible key. SiteForm has no `:escape` clause and no inline confirmation row after a successful submit. `Foglet.Config.Schema` field descriptions for the `@site_keys` set contain literal planning IDs that surface as Site subtitles — for example:

```
"Account registration policy (D-02/D-03): open | invite_only | sysop_approved"
"Who may generate invite codes (D-04): sysop_only | mods | any_user"
```

`Foglet.TUI.Screens.Sysop.UsersView` (`users_view.ex:60`) accepts `A`/`R`/`S`/`U` on any focused row regardless of its current status; the always-visible `@footer` advertises all four. Bad transitions are caught only after `Foglet.Accounts.transition_user_status/3` returns — at which point `error_message(:invalid_transition)` maps to `"Invalid status transition."`, which is user-facing but does not name the from/to of the rejected move. (Note: REQUIREMENTS.md SYSOP-05 mentions `:invalid_status_transition`; the actual atom in `Foglet.Accounts` is `:invalid_transition`. The mapping already exists; the copy upgrade is the work.)

`Foglet.TUI.Screens.Shared.InvitesSurface` renders invites via `ConsoleTable`; per-row focus and selection state live in `Foglet.TUI.Screens.Shared.InvitesState`, mutated by `Foglet.TUI.Screens.Shared.InvitesActions`. Whether row-focus highlight already differs visibly from unfocused rows at 80×24 SSH is not asserted by any current test — to be confirmed during plan-phase.

The Sysop command bar advertises a Jump hint dynamically: `"1-5"` or `"1-6"` based on INVITES visibility (`sysop.ex:61`). The Account screen has no Jump command-bar group at all. The Moderation screen hardcodes `{"1-6", "Jump"}` (`moderation.ex:44`) even when its 5 base tabs are visible without INVITES.

This phase locks the operator surface: every Sysop tab populates honestly on entry, fails honestly when the boundary call breaks, and exposes the contextual operator actions a sysop expects without "Press any key" gating. SiteForm is delivered onto Modal.Form by Phase 28; Phase 29 sits on top of that substrate to deliver the operator-visible behaviour.

## Requirements

1. **Auto-load on tab entry via `Foglet.TUI.Command`**: Switching to a non-loaded BOARDS, LIMITS, SYSTEM, or USERS tab dispatches a single load command without requiring a key press; the resulting data renders inside the tab on the next App update cycle.
   - Current: `render_tab_body/3` for BOARDS, LIMITS, SYSTEM, and USERS emits `placeholder("Press any key to load …", theme)` until the corresponding submodule struct is lazily initialised inside `delegate_to_submodule/5` on the user's first keypress. `Foglet.TUI.Command.task/2` is never invoked from Sysop. Only INVITES auto-loads (`maybe_load_invites_on_entry/2`).
   - Target: When `handle_key/2` resolves a tab change to BOARDS, LIMITS, SYSTEM, or USERS and that tab's state slot is `:not_loaded`, the screen returns a `Foglet.TUI.Command.task/2`-wrapped command alongside the state update; the command's success path transitions the slot to `{:loaded, struct}` and renders the populated body. SITE remains synchronous (its drafts seed inside `SiteForm.init/1` from the ETS-cached `Foglet.Config`); INVITES retains its existing `maybe_load_invites_on_entry/2` path. No `"Press any key to load"` placeholder copy remains in `lib/foglet_bbs/tui/screens/sysop.ex`.
   - Acceptance: A render-smoke test that switches the Sysop screen from SITE to BOARDS via a Tab event asserts the rendered body contains BoardsView's loaded content (or a `:loading` indicator that resolves to loaded content within one App update cycle), not the substring `"Press any key"`. A grep test asserts no `"Press any key"` literal remains in `sysop.ex`. A round-trip command test asserts that switching to USERS dispatches exactly one `Foglet.TUI.Command.task/2` for `:load_sysop_users` per entry (idempotent: a second tab switch back into USERS while already `{:loaded, _}` does not redispatch).

2. **Tagged lifecycle state for BOARDS, LIMITS, SYSTEM, USERS — with `[R] Retry` and a distinct `:forbidden` panel**: Each of those four slots holds `:not_loaded | :loading | {:loaded, struct} | {:error, reason}`; the renderer emits distinct output per state; on `{:error, reason}` the command bar advertises `[R] Retry` and pressing `R` re-dispatches the load command; `{:error, :forbidden}` renders a distinct "Insufficient role" panel and does NOT advertise `[R] Retry`.
   - Current: `Foglet.TUI.Screens.Sysop.State` declares `boards_view`, `limits_form`, `system_snapshot`, and `users_view` as `term() | nil`. There is no error rendering, no retry keybind, and no role-aware error panel. A failed boundary call would either crash the task (visible only via the App's task-error modal) or leave the slot `nil`, which `render_tab_body/3` would interpret as "Press any key".
   - Target: Each of those four slots is a tagged tuple/atom from the set `:not_loaded | :loading | {:loaded, struct} | {:error, reason}`. `render_tab_body/3` matches on the tag: `:not_loaded` and `:loading` render an honest loading indicator (loading copy chosen in plan-phase); `{:loaded, struct}` delegates to the existing submodule renderer; `{:error, :forbidden}` renders an "Insufficient role" panel; `{:error, _other}` renders an honest error panel. While any of those four tabs is `{:error, reason}` other than `:forbidden`, the Sysop command bar gains a `[R] Retry` group with key `"R"`; pressing `R` transitions that tab back to `:loading` and re-dispatches the load command. While the tab is `{:error, :forbidden}`, `[R] Retry` is suppressed because retry will not change the outcome.
   - Acceptance: A unit test for `Foglet.TUI.Screens.Sysop.State` asserts each of the four slots accepts and round-trips every value of the tagged enum without `nil` leakage to a renderer. A render-smoke test injecting `{:error, :load_timeout}` on USERS asserts (a) an error panel is visible, (b) the command bar contains the substring `"[R] Retry"`, and (c) dispatching a `%{key: :char, char: "R"}` event re-dispatches a `:load_sysop_users` command. A second render-smoke test injecting `{:error, :forbidden}` on USERS asserts (a) an "Insufficient role" panel is visible (or equivalent honest copy chosen in plan-phase), (b) the substring `"[R] Retry"` is NOT present, and (c) `R` is a no-op.

3. **Sysop Site editable: drafts echoed inline, Enter persists, Esc resets**: On the Modal.Form-based Sysop Site (delivered by Phase 28), focusing a field and typing echoes the in-flight draft value rather than the saved `Foglet.Config` value; pressing Enter persists every visible key via `Foglet.Config.put/3` with a visible inline confirmation row in the next render; pressing Esc resets all drafts to the saved values without leaving the tab.
   - Current: `SiteForm.init/1` seeds drafts from `Foglet.Config.get!/1` and `submit/1` already calls `Foglet.Config.put/3` for every visible key. Render already shows the draft value inline. There is no `:escape` clause in `SiteForm.handle_key/2`, and there is no inline confirmation row after a successful `submit/1` — successful writes return `{state, []}` with no visible signal. Phase 28 is migrating the consumer onto Modal.Form's substrate.
   - Target: After Phase 28's migration, the Modal.Form-based Sysop Site renders the in-flight draft for the focused field while the user types (no flicker back to the saved value mid-edit). Pressing Enter on a submittable form invokes the existing `Foglet.Config.put/3` path (gated by Phase 28's `submit_state` machine to prevent double-write); on `{:ok, _entry}` for every visible key, the next render emits a visible inline confirmation row distinct from regular field rows (literal copy chosen in plan-phase). Pressing Esc on the Sysop Site tab body reseeds every draft from the current `Foglet.Config.get!/1` value and emits a visible "draft discarded" status row consistent with Phase 28 R6's contract; Esc does not pop the tab.
   - Acceptance: An integration test on Sysop Site focuses `registration_mode`, types a value (e.g. cycles via space) and asserts the rendered tab body shows the in-flight draft (not the saved value); presses Enter and asserts (a) `Foglet.Config.get!/1` reflects the new value and (b) the next render contains the inline confirmation row substring chosen in plan-phase. A second test edits a field, presses Esc, and asserts the draft equals the saved value AND the next render contains a discard status row. A 64×22 SSH render check confirms the confirmation row is visible inside the tab body without overflowing.

4. **Site field subtitles use user-facing operator copy, no internal references**: The Sysop Site rendered output contains no `(D-XX)`, `REQ-XX`, "Phase N", "Pitfall N", or "deliverable" tokens; every `Foglet.Config.Schema` description for keys in `Foglet.TUI.Screens.Sysop.SiteForm.@site_keys` is rewritten in user-facing operator copy.
   - Current: `Foglet.Config.Schema` field descriptions surface as Site subtitles via `SiteForm.render_row/4`. Today's literal strings include `"Account registration policy (D-02/D-03): …"`, `"Who may generate invite codes (D-04): …"`, and `"Maximum post body length in characters (D-31)"`.
   - Target: Every `description:` for keys in `@site_keys` (today: `registration_mode`, `invite_code_generators`, `delivery_mode`, `require_email_verification`, `invite_generation_per_user_limit`) is rewritten to operator-facing copy with no `(D-\d+)`, `REQ-\w+`, `Phase \d+`, `Pitfall \d+`, or `deliverable` substring (case-insensitive). Plan-phase chooses the literal replacement strings.
   - Acceptance: A grep test over `lib/foglet_bbs/config/schema.ex` matches no `(D-\d+|REQ-[A-Z]+-\d+|Phase \d+|Pitfall \d+|deliverable)` (case-insensitive) on any `description:` line whose key appears in `Foglet.TUI.Screens.Sysop.SiteForm.site_keys/0`. A snapshot-style render test of the Sysop Site tab body contains none of those tokens.

5. **USERS keybind gating + named from→to transition copy**: The USERS tab only advertises and dispatches keybinds whose target status is reachable from the focused row's current status; an `:invalid_transition` that nonetheless reaches `Foglet.Accounts` surfaces user-facing copy that names the from/to status, not the raw atom.
   - Current: `UsersView.handle_key/2` accepts `A`/`R`/`S`/`U` on any focused row regardless of its status; the always-visible `@footer = "[A] Approve  [R] Reject  [S] Suspend  [U] Reactivate  [j/k] Move"` advertises all four. `error_message(:invalid_transition)` returns `"Invalid status transition."` — already user-facing but does not name the from/to.
   - Target: `UsersView` computes the set of valid target statuses for the focused row using the same predicate `Foglet.Accounts` enforces (mirror or expose; chosen in plan-phase) and renders only the corresponding subset of keybinds in its footer/command bar. With a focused `:active` row, `[A] Approve` is NOT advertised; pressing `A` is a no-op (no status_message, no boundary call). When `Foglet.Accounts.transition_user_status/3` returns `{:error, :invalid_transition}` (e.g. via test-only injection), the rendered status_message contains both the from-status and the to-status names, not the substring `invalid_transition` or `:invalid_transition`.
   - Acceptance: A unit test on `UsersView` with a focused `:active` row asserts (a) the rendered footer does NOT contain `"[A] Approve"`, (b) `handle_key(%{key: :char, char: "A"}, state)` returns the same state with no `status_message` change. A unit test that injects `{:error, :invalid_transition}` from `Foglet.Accounts.transition_user_status/3` (via a test stub) asserts the resulting `state.message` matches a from→to copy pattern (literal pattern locked in plan-phase) and does NOT contain the substring `invalid_transition`.

6. **INVITES row focus highlight + Enter→`[X] Revoke` contextual command**: Focusing an invite row visibly changes its highlight at 80×24 SSH; pressing Enter on a focused, non-revoked invite reveals an `[X] Revoke` command in the command bar; pressing `X` invokes the existing revoke action; revoked rows do not advertise `[X] Revoke`.
   - Current: `Foglet.TUI.Screens.Shared.InvitesSurface` renders via `ConsoleTable`; per-row selection state lives in `Foglet.TUI.Screens.Shared.InvitesState`; mutations route through `Foglet.TUI.Screens.Shared.InvitesActions`. Whether row-focus highlight is visibly distinct from unfocused rows at 80×24, and whether Enter currently reveals contextual row-level actions, is not asserted by any current test — to be audited in plan-phase.
   - Target: At 80×24 SSH, the focused INVITES row renders with a visibly different highlight from unfocused rows (specific style chosen in plan-phase, routed through `Foglet.TUI.Theme`). Pressing Enter on a focused row whose status is not `:revoked` adds an `[X] Revoke` group to the Sysop command bar; pressing `X` dispatches the existing revoke side effect through `InvitesActions`. Pressing Enter on a focused row whose status is `:revoked` does NOT advertise `[X] Revoke`. No commands beyond `[X] Revoke` are added in Phase 29 (resend, regenerate, copy code are out of scope).
   - Acceptance: A render-smoke test at 80×24 SSH with three invites (none revoked) asserts the focused row's rendered tokens differ from the unfocused rows' tokens. A second test with a non-revoked focused row asserts that after a `%{key: :enter}` event, the rendered command bar contains the substring `"[X] Revoke"` and dispatching `%{key: :char, char: "X"}` mutates the focused invite's state through the existing `InvitesActions` revoke path. A third test with a `:revoked` focused row asserts `"[X] Revoke"` is NOT present after Enter.

7. **`1-N Jump` group consistent across Account, Moderation, Sysop**: Every tab-bearing screen advertises a `Tabs` command-bar group whose Jump hint reads `1-N` where `N` equals the count of currently visible tabs.
   - Current: `lib/foglet_bbs/tui/screens/account.ex` defines no Jump command group at all. `lib/foglet_bbs/tui/screens/moderation.ex:44` hardcodes `@key_list [{"←/→", "Tab"}, {"1-6", "Jump"}, {"Q", "Back"}]` even when its 5 base tabs are visible without INVITES (the hint is wrong by 1 in that case). `lib/foglet_bbs/tui/screens/sysop.ex:61` already computes `"1-5"` or `"1-6"` dynamically based on INVITES visibility.
   - Target: Account, Moderation, and Sysop each compute the visible-tab count `N` from their respective `tab_labels(state)` and render a Jump command group whose label reads `"1-N"` (e.g. `"1-3"` on Account base, `"1-4"` on Account with INVITES, `"1-5"` or `"1-6"` on Moderation, `"1-5"` or `"1-6"` on Sysop). No screen renders a hardcoded literal that disagrees with the visible tab count. Account adds the group; Moderation switches to dynamic; Sysop pattern stays as is.
   - Acceptance: A render-smoke test for each of Account / Moderation / Sysop, run at both 64×22 and 80×24 SSH and across both INVITES-visible and INVITES-hidden actor contexts, asserts that the rendered command bar contains the exact substring `"1-N Jump"` (or `"1-N Jump"`, whichever the chrome formats — chosen in plan-phase) where `N` matches the actually-rendered tab count. A grep test asserts the literal string `{"1-6", "Jump"}` no longer appears in `lib/foglet_bbs/tui/screens/moderation.ex`.

## Boundaries

**In scope:**
- Auto-load lifecycle for BOARDS, LIMITS, SYSTEM, USERS via `Foglet.TUI.Command.task/2`
- Tagged `:not_loaded | :loading | {:loaded, struct} | {:error, reason}` state on those four slots in `Foglet.TUI.Screens.Sysop.State`
- `[R] Retry` keybind advertising on non-`:forbidden` errors; distinct "Insufficient role" panel for `{:error, :forbidden}`
- Sysop Site draft-echo rendering, Enter→`Foglet.Config.put/3` persistence, inline confirmation row, and Esc→reset-drafts behaviour, sitting on top of Phase 28's Modal.Form-based SiteForm
- Rewritten user-facing copy for `Foglet.TUI.Screens.Sysop.SiteForm.@site_keys` descriptions in `Foglet.Config.Schema`
- USERS keybind gating per focused-row status; user-facing from→to copy on `:invalid_transition`
- INVITES row-focus visible highlight at 80×24 and Enter→`[X] Revoke` contextual command
- `1-N Jump` command-bar group made consistent across Account, Moderation, Sysop

**Out of scope:**
- `Foglet.TUI.Screens.Sysop.SiteForm` → `Modal.Form` migration — owned by Phase 28
- Modal.Form substrate work (focus routing, submit-state machine, footer suppression) — owned by Phase 28
- New schematized `@site_keys` or new `Foglet.Config.Schema` keys — only existing key descriptions are rewritten
- New status transitions, new role types, or new error atoms in `Foglet.Accounts` — Phase 29 only consumes the existing transition surface
- INVITES `Resend` / `Regenerate` / `Copy code` / `Show full code` — only `[X] Revoke` is added per Round 1 lock
- Account Profile / Preferences edits — owned by Phase 30
- Auth flow, reset-token UX, `:reset_consume` sub-state — owned by Phase 31
- Main Menu Navigation/Oneliners chrome — owned by Phase 32
- Composer wrap, Boards expand/collapse — owned by Phase 33
- Webhook notifications, email digests, browser admin — explicitly out of v1.4 scope per REQUIREMENTS.md

## Constraints

- Lifecycle dispatch must use `Foglet.TUI.Command.task/2` (the only sanctioned wrapper around Raxol task commands). Direct calls to `Raxol.Core.Runtime.Command.task/1` from Sysop screens are forbidden so `{:task_error, op, reason}` propagation stays uniform.
- All new copy routes through user-facing operator language; all colour decisions route through `Foglet.TUI.Theme` slots (no hardcoded `IO.ANSI.*` or atom literals — Phase 26 / v1.3 D-09 invariant).
- Render contracts are verified at 64×22 SSH minimum and 80×24 SSH compact target — explicitly for the INVITES focus highlight, the Sysop Site confirmation/discard rows, and the `1-N Jump` group.
- Tagged enum state must round-trip through `state.screen_state[:sysop]` without `nil` leakage to render functions; `nil` is a state-construction error, not a rendered state.
- `{:error, :forbidden}` from any boundary call (e.g. `Foglet.Accounts.list_user_status_admin_targets/1`) MUST render as the dedicated "Insufficient role" panel, not as a generic load error — and MUST suppress the `[R] Retry` advertisement.
- Sysop Site Esc must NOT pop the screen or unmount the tab — it reseeds drafts in place per Phase 28's `Modal.Form` `on_cancel` contract.
- Domain mutations stay in contexts: `Foglet.Config.put/3` for SITE writes, `Foglet.Accounts.transition_user_status/3` for USERS transitions, existing `InvitesActions` revoke for INVITES — Phase 29 adds no new domain code.
- INVITES retains its existing `maybe_load_invites_on_entry/2` lifecycle; it is NOT migrated onto the tagged enum lifecycle in Phase 29.

## Acceptance Criteria

- [ ] Switching to BOARDS, LIMITS, SYSTEM, or USERS auto-dispatches a `Foglet.TUI.Command.task/2` load on entry; no `"Press any key"` placeholder copy remains in `lib/foglet_bbs/tui/screens/sysop.ex`
- [ ] Each of `boards_view`, `limits_form`, `system_snapshot`, `users_view` in `Foglet.TUI.Screens.Sysop.State` is a tagged enum value (`:not_loaded | :loading | {:loaded, struct} | {:error, reason}`); the renderer emits distinct visible output per state
- [ ] On `{:error, reason}` (reason ≠ `:forbidden`) for any of those four tabs, the Sysop command bar advertises `[R] Retry`; pressing `R` re-dispatches the load command
- [ ] On `{:error, :forbidden}` for any of those four tabs, the rendered body is a distinct "Insufficient role" panel and `[R] Retry` is suppressed
- [ ] On Sysop Site, focusing a field and typing renders the in-flight draft in the tab body (not the saved Config value); pressing Enter persists every visible key via `Foglet.Config.put/3` and the next render contains an inline confirmation row; pressing Esc resets drafts to the saved values and the next render contains a discard status row
- [ ] `Foglet.Config.Schema` description strings for keys in `Foglet.TUI.Screens.Sysop.SiteForm.@site_keys` contain no `(D-\d+)`, `REQ-[A-Z]+-\d+`, `Phase \d+`, `Pitfall \d+`, or `deliverable` token (case-insensitive)
- [ ] On Sysop USERS with a focused `:active` row, the footer/command bar does NOT advertise `[A] Approve` and pressing `A` is a no-op
- [ ] When `Foglet.Accounts.transition_user_status/3` returns `{:error, :invalid_transition}`, the rendered USERS `status_message` names both the from-status and the to-status and does NOT contain the substring `invalid_transition`
- [ ] At 80×24 SSH on INVITES, the focused row's rendered tokens differ from unfocused rows
- [ ] At 80×24 SSH, pressing Enter on a focused non-revoked INVITE reveals `[X] Revoke` in the command bar and pressing `X` dispatches the existing revoke action via `InvitesActions`; on a `:revoked` focused row, `[X] Revoke` is NOT advertised
- [ ] Account, Moderation, and Sysop command bars all advertise `1-N Jump` where `N` matches the visible tab count, at both 64×22 and 80×24 SSH and across INVITES-visible and INVITES-hidden actor contexts
- [ ] No literal `{"1-6", "Jump"}` (or any other hardcoded `1-X` Jump literal) remains in `lib/foglet_bbs/tui/screens/moderation.ex` or `lib/foglet_bbs/tui/screens/account.ex`

## Ambiguity Report

| Dimension          | Score | Min  | Status | Notes                                                                  |
|--------------------|-------|------|--------|------------------------------------------------------------------------|
| Goal Clarity       | 0.92  | 0.75 | ✓      | Per-tab deliverables grounded against current code                      |
| Boundary Clarity   | 0.82  | 0.70 | ✓      | Phase 28/30/31/32/33 hand-offs explicit; INVITES scope locked to Revoke |
| Constraint Clarity | 0.72  | 0.65 | ✓      | Lifecycle vehicle (`Foglet.TUI.Command`) and theme/copy rules locked    |
| Acceptance Criteria| 0.80  | 0.70 | ✓      | 12 pass/fail criteria; literal copy strings deferred to plan-phase      |
| **Ambiguity**      | 0.169 | ≤0.20| ✓      | Gate met after one round + codebase verification                        |

Status: ✓ = met minimum, ⚠ = below minimum (planner treats as assumption)

## Interview Log

| Round | Perspective    | Question summary                                          | Decision locked                                                                                          |
|-------|----------------|-----------------------------------------------------------|----------------------------------------------------------------------------------------------------------|
| 1     | Researcher     | Phase 28 vs 29 SiteForm ownership                         | Phase 28 owns SiteForm→Modal.Form migration; Phase 29 only adds lifecycle / draft echo / Esc / persist   |
| 1     | Researcher     | Tagged enum state — does SITE need `:loading`?            | Tagged enum applies only to BOARDS/LIMITS/SYSTEM/USERS; SITE stays sync; INVITES keeps existing pattern  |
| 1     | Researcher     | Scope of INVITES contextual row actions                   | `[X] Revoke` only — no Resend/Regenerate/Copy in Phase 29                                                |
| 1     | Researcher     | (verification) Account / Moderation Jump-hint state today | Account has no Jump group; Moderation hardcodes `1-6` even when only 5 tabs visible; Sysop already dynamic |
| 1     | Researcher     | (verification) Real `Foglet.Accounts` transition error    | Real atom is `:invalid_transition` (REQUIREMENTS.md SYSOP-05's `:invalid_status_transition` is incorrect)  |
| Gate  | Spec Gate      | Lock literal copy strings now or defer to plan-phase?     | Lock the contract; defer literal strings (confirmation row, discard row, transition copy) to plan-phase    |

---

*Phase: 29-sysop-tab-lifecycle-bodies*
*Spec created: 2026-04-27*
*Next step: /gsd-discuss-phase 29 — implementation decisions (how to wire the tagged enum lifecycle through `Foglet.TUI.Command`, where to compute the per-row valid-status predicate, and the literal copy for confirmation / discard / transition rows)*
