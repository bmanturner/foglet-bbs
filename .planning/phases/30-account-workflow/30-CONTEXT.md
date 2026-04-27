# Phase 30: account-workflow - Context

**Gathered:** 2026-04-27 (assumptions mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 30 closes the v1.4 Account workflow gaps locked in `30-SPEC.md`: render an inline `[Saved]` flash on Profile/Prefs submit and verify re-entry via human UAT (ACCT-01), suppress Modal.Form's internal title row inside tabbed-inline form callers (ACCT-02), make Preferences fields commit-correctly with timezone re-rendered as a Timex-backed type-ahead `SelectList` (ACCT-03 + ACCT-04), and replace the hand-rolled SSH-keys add form with a Modal.Form overlay so multi-line OpenSSH key paste lands in the buffer and persists in normalized single-line form (ACCT-05). FORM-01/04/05 substrate work, cursor rendering, new preferences columns, account deletion, and any browser surface remain out of scope.
</domain>

<decisions>
## Implementation Decisions

### SSH-keys add — overlay Modal.Form (ACCT-05)
- **D-01:** Pressing `a`/`A` on the SSH KEYS list (`Foglet.TUI.Screens.Account.SSHKeysActions.handle_key/3:62-66`) dispatches `{:show_modal, %Foglet.TUI.Modal{type: :form, title: "Add SSH Key", message: %ModalForm{...}}}`. The hand-rolled `mode: :add` branch in `SSHKeysState` and the inline `SSHKeysSurface.maybe_form/2` add-form rendering are removed. The SSH-keys list rendering, revoke flow, and load path are untouched.
- **D-02:** The new `ModalForm` carries two fields: `label` typed `:text`, and `public_key` typed `:textarea`. Submit normalizes `public_key` via `String.replace(value, ~r/\s+/, " ") |> String.trim/1` BEFORE constructing the `SSHKey` changeset and calling `Foglet.Accounts.register_ssh_key/2` (changeset `String.trim/1` already exists at `accounts/ssh_key.ex:54` but does not collapse internal whitespace).
- **D-03:** No bracketed-paste handling is added in this phase. The textarea's existing `apply_raw_edit/2` (`widgets/modal/form.ex:391-397`) accumulates `:enter` and `:char "\n"` events into the buffer — that is the contract this phase commits to. Whether real SSH paste arrives that way is verified by the manual UAT (D-19), not by an automated harness.
- **D-04:** Submit success dismisses the overlay (`{:close_modal}` action shape already routed at `app.ex`); failure shows the changeset error inside the Modal.Form using its existing `set_errors/2` path (`form.ex:177-179`), keeping the overlay open so the user can correct and retry.

### Modal.Form internal-title option (ACCT-02)
- **D-05:** Add an `:internal_title?` boolean option to `Foglet.TUI.Widgets.Modal.Form.init/1` (default `true`). `Modal.Form.render/2` consults it and conditionally emits the title row at `form.ex:191` and the divider at `form.ex:192`.
- **D-06:** Tabbed-inline callers pass `internal_title?: false`: `ProfileForm` (`profile_form.ex` form builder via `Account.State`) and `PrefsForm` (`prefs_form.ex` form builder via `Account.State`). Future Sysop SiteForm migration onto Modal.Form (Phase 28) opts in there.
- **D-07:** Overlay callers — including the new SSH-keys add overlay (D-01) and existing overlays at `app.ex:546` (Post Oneliner) and `app.ex:606` (Hide Oneliner) — keep the default `true` and thus retain their title row. The overlay's own visual frame is the title's natural home.

### Saved flash render & clear (ACCT-01)
- **D-08:** Render `state.status_message` as an inline `[Saved]` row inside `ProfileForm.render/2` (`profile_form.ex:21-23`) and `PrefsForm.render/2` (`prefs_form.ex:22-24`) — appended below the Modal.Form output. The row renders only when `status_message` is non-nil; copy is `[Saved]` (no period, no longer copy) per SPEC line 35.
- **D-09:** Add a `status_message_seen?: boolean()` field to `Foglet.TUI.Screens.Account.State` (`state.ex:50-68`). Set to `false` whenever `status_message` is set. On the FIRST true input event in `Account.do_handle_key/3` where `status_message_seen? == false`, flip it to `true` and clear `status_message` to `nil` for the next render. "True input event" means `:char` / `:backspace` / `:enter` / arrow keys / `:tab` / `:escape` — NOT idle telemetry, resize, or PubSub-delivered events.
- **D-10:** Persistence-on-re-entry is verified via manual SSH/TUI UAT only (SPEC ACCT-01). No app.ex or session_context changes are required: the actor's `current_user` is already refreshed at `app.ex:1185` and `Account.State.seed_from_user/2` re-runs on tab entry, so saved values reappear automatically when the underlying path is intact. If UAT surfaces a regression, the fix lands in the same phase under the same acceptance.

### Timezone SelectList field type (ACCT-04 / ACCT-03)
- **D-11:** Add a new Modal.Form field type `:select_list`. Field state wraps `Foglet.TUI.Widgets.List.SmartList` initialized with `enable_search: true` (`widgets/list/smart_list.ex:46-51,81-106`). Modal.Form's `dispatch_to_field/3` (`form.ex:267-325`) gains a clause for `:select_list` that forwards events to the wrapped SmartList and absorbs `{:item_selected, value}` actions into the field's draft value.
- **D-12:** PrefsForm's `timezone` field changes type from `:text` to `:select_list`; `:options` is sourced from `Tzdata.zone_list/0` mapped to `{zone, zone}` tuples. Tzdata is consumed transitively via Timex (`mix.lock:71-73`); no new dep is added (SPEC line 82).
- **D-13:** Filter contract is case-insensitive substring match on the IANA zone string (SPEC line 50). If Raxol's `SelectList` defaults to a different match strategy, add a thin `filtered_options` override on the Foglet side rather than vendoring Raxol changes — flagged for the planner under canonical refs.
- **D-14:** Saved-value visibility while editing is satisfied by SmartList's existing in-place rendering: the field's current value is shown in the closed state and the SelectList opens with that value pre-selected (SPEC line 50 acceptance bullet).
- **D-15:** Validation falls back to existing precedent: `User.validate_timezone/1` (`accounts/user.ex:265-272`) and `ClockFormatter` (`widgets/chrome/clock_formatter.ex:44`) use `Timex.Timezone.exists?/1` with `Etc/UTC` deterministic fallback. The SelectList's options list constrains input to valid IANA names by construction — invalid free-text submission is structurally impossible.

### time_format / theme commit verification (ACCT-03)
- **D-16:** Phase 30 owns ONLY (a) the integration test that exercises Up/Down + Enter on time_format and theme RadioGroup fields and asserts read-back via `Foglet.Accounts.get_preferences/1`, and (b) the inline `[Saved]` flash on the same Preferences submit path. The substrate fix (focus-routing / submit-state) is owned by Phase 28 FORM-04/FORM-05 and is OUT of scope for this phase.
- **D-17:** Phase 30 implementation is gated on Phase 28 FORM-04/05 landing first. If scheduling forces the inverse order, the planner surfaces the dependency as a blocker rather than duplicating Phase 28's substrate fix inside PrefsForm.
- **D-18:** Add a `:checkbox` rendering smoke test that builds a synthetic Modal.Form with one `:boolean` field and asserts `render/2` does not raise. No production boolean preference is surfaced — `PrefsForm`'s production fields stay at `timezone`, `time_format`, `theme` (SPEC line 78).

### Test strategy & UAT artifact
- **D-19:** Land a phase-owned UAT artifact at `.planning/phases/30-account-workflow/30-HUMAN-UAT.md` covering four manual SSH/TUI checks at both 64×22 and 80×24: (1) Profile re-entry persistence, (2) `[Saved]` flash visibility and clear-on-keypress, (3) timezone SelectList fits the PREFERENCES tab body without overflow, (4) SSH-key paste end-to-end (paste appears in the field, embedded `\n` does not submit, persisted value is single-line, list shows truncated/elided preview).
- **D-20:** Land three new test files: `test/foglet_bbs/tui/screens/account/prefs_form_test.exs` (timezone SelectList rendering + filter, time_format/theme persistence + flash, `:checkbox` smoke); `test/foglet_bbs/tui/screens/account/ssh_keys_paste_test.exs` (multi-line key fed through the overlay's Modal.Form via codepoint stream, byte-for-byte assertion on the persisted normalized value); `test/foglet_bbs/tui/widgets/modal/form_internal_title_test.exs` (`:internal_title?` opt true/false rendering, plus a Login regression check that default-on still emits the title row).

### Folded Todos
None — `gsd-tools.cjs todo.match-phase` returned an unknown-command error (this version of gsd-tools doesn't expose that subcommand). No todos in `.planning/STATE.md` Pending Todos section reference Account workflow.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase Definition
- `.planning/phases/30-account-workflow/30-SPEC.md` — Locked requirements (ACCT-01..05), boundaries, constraints, and 18 pass/fail acceptance criteria.
- `.planning/ROADMAP.md` — v1.4 phase sequencing, Phase 30 success criteria (lines 100-111), dependencies on Phase 27 (cursor) and Phase 28 (Modal.Form substrate).
- `.planning/REQUIREMENTS.md` — ACCT-01..05 entries (lines 46-50) traced to ISSUES.md (Account #2/#3/#4/#6/#9).
- `.planning/PROJECT.md` — SSH/TUI-first product boundary; v1.4 stabilization scope.

### Cross-phase dependencies
- `.planning/phases/26-layout-width-foundations/26-CONTEXT.md` — D-02 (keep screen changes thin; pass dimensions/user context into shared widgets), D-07/D-08 (timezone is a TUI presentation concern; Timex validation; `Etc/UTC` fallback).
- `.planning/phases/28-modal-form-substrate/28-SPEC.md` (when written) — FORM-01 (Up/Down focus), FORM-04 (focus routing single source of truth), FORM-05 (`submit_state` machine). Phase 30 consumes these; if 28-SPEC.md doesn't yet exist, the planner reads `.planning/REQUIREMENTS.md` FORM-01..06 entries.
- `.planning/phases/27-cursor-breadcrumb-polish/27-HUMAN-UAT.md` — UAT-artifact precedent for `30-HUMAN-UAT.md` (D-19).

### TUI widget contracts
- `lib/foglet_bbs/tui/widgets/README.md` — Foglet widget catalog, theme-routing requirements, stateful/stateless widget contracts.
- `docs/raxol/getting-started/WIDGET_GALLERY.md` — Raxol layout, table, tree, viewport, and SelectList primitive reference.

### Domain context
- `docs/DATA_MODEL.md` — User schema, preferences embedding, ssh_keys association invariants. Read before any changeset touches.
- `lib/foglet_bbs/accounts.ex`, `lib/foglet_bbs/accounts/user.ex` (changeset functions), `lib/foglet_bbs/accounts/ssh_key.ex` — domain mutation surface; `update_profile/2`, `update_preferences/2`, `register_ssh_key/2` are the only context entry points this phase calls.
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Foglet.TUI.Widgets.Modal.Form` (`lib/foglet_bbs/tui/widgets/modal/form.ex`) — supports `:text`, `:textarea` (`:251-265,295-325,391-397`), `:enum` (RadioGroup), `:boolean` (Checkbox); `dispatch_to_field/3` accepts new field types (D-11).
- `Foglet.TUI.Widgets.List.SmartList` (`lib/foglet_bbs/tui/widgets/list/smart_list.ex`) — wraps Raxol's `SelectList` with `enable_search: true`, paging, and the `{:item_selected, value}` action shape Modal.Form needs.
- `Foglet.TUI.Modal` overlay struct + `Foglet.TUI.Widgets.Modal.render/2` — already rendered via `app.ex:187,197` and used at `app.ex:546,606` for Oneliner overlays. Provides the precedent for the SSH-keys add overlay (D-01).
- `Foglet.Accounts.update_profile/2`, `update_preferences/2`, `register_ssh_key/2` — domain entry points; persistence pipeline is intact (`app.ex:902-908` re-keys preferences attrs, `User.profile_changeset/2` casts `:preferences` and `:theme`).
- `Tzdata.zone_list/0` (transitive via Timex 3.7.13) — IANA zone enumeration for D-12.
- `Foglet.TUI.Theme` slots — all color decisions in modified Account render paths route through `Theme` per `mix.lock` and Phase 26 D-11 precedent.

### Established Patterns
- Stateful widgets follow Raxol's `init/1` → `handle_event/2` → `render/2` triplet; stateless widgets expose render functions only (`widgets/README.md`).
- Form submit collects all field values via `Modal.Form.collect_values/1` (`form.ex:327-331`); commands flow `screen submit handler → App.do_update → save_account → Foglet.Accounts.<fn> → Repo.update`.
- Modal overlays are dispatched via `{:show_modal, %Foglet.TUI.Modal{...}}`; modal-form key events are routed at `app.ex:1018,1031,1366` so a Modal.Form held inside a Modal overlay receives keystrokes identically to a tab-embedded Modal.Form.
- Status message / flash precedent: `state.status_message` is set in three locations (`profile_form.ex:48`, `prefs_form.ex:63`, `app.ex:1229`) but never rendered today — D-08 closes this gap.
- Per-screen state in a sibling `state.ex` module (`screens/account/state.ex`) — Phase 30 extends this, not Modal.Form, with the new `status_message_seen?` field (D-09).

### Integration Points
- `Foglet.TUI.Screens.Account.handle_event/2` and `delegate_*_key/3` (`account.ex:204-237`) — current dispatch fan-out for PROFILE / PREFERENCES / SSH KEYS. After D-01 the `delegate_ssh_keys_key/3` clause for `mode: :add` is removed; modal-overlay events flow through the existing `app.ex:1018,1031,1366` pipeline instead.
- `Foglet.TUI.Screens.Account.State.seed_from_user/2` (`state.ex`) — re-runs on tab entry, re-seeding form values from the (refreshed) `current_user`. This is the persistence-on-re-entry path that ACCT-01 manual UAT verifies.
- `Foglet.TUI.App.do_update({:show_modal, _}, state)` (`app.ex:327`) — overlay entry point.
- `Foglet.TUI.App.handle_event({_, %{modal: %Foglet.TUI.Modal{message: %ModalForm{}}}})` clauses (`app.ex:1018,1031,1366`) — modal-form keystroke routing; absorb `:char`, `:tab`, `:enter`, `:escape` correctly today for Oneliner overlays.
- `Foglet.Accounts.register_ssh_key/2` — single domain entry point for SSH-key creation; D-02's normalization runs in the form submit handler before this is called.
</code_context>

<specifics>
## Specific Ideas

- The user explicitly directed: "If you're gonna use Modal.Form for adding an ssh key it has to be the overlay mode that is activated by pressing the appropriate key on the ssh keys tab." → D-01.
- `[Saved]` is the locked flash copy (SPEC line 35). Other variants (`Saved.`, `Account changes saved.`, `Profile ready to save.`) currently in code are normalized to `[Saved]` for Phase 30's submit paths.
- The keybind for triggering the SSH-keys add overlay is `a`/`A` per existing precedent (`ssh_keys_actions.ex:62-66`); no new keybind is introduced.
</specifics>

<deferred>
## Deferred Ideas

- **Bracketed-paste detection at the SSH/Raxol input layer.** Out of scope for Phase 30 (D-03). If real SSH paste fails the manual UAT (D-19) despite the textarea rendering correctly, file a follow-up phase to add `ESC[200~`/`ESC[201~` handling in `Foglet.SSH.CLIHandler`. ~80 LOC + test surface estimate from prior PITFALLS analysis.
- **Profile/Prefs as overlays.** Could mirror the SSH-keys overlay pattern for visual consistency. Out of scope for Phase 30 — the current inline tab embedding is shipping behavior; the user did not ask to change it.
- **`Modal.Form.set_flash/2` colocation.** Cleaner than tracking flash visibility on the screen state, but couples Modal.Form to a presentation concern and overlaps Phase 28's `submit_state` work. Out of scope.
- **Phase 28 FORM-04/05 substrate fix.** Phase 30 verifies the result; the substrate work itself is Phase 28's deliverable.

### Reviewed Todos (not folded)
- `gsd-tools.cjs todo.match-phase 30` returned `Error: Unknown command: todo.match-phase` — the gsd-tools subcommand surface in this checkout doesn't expose that query. No todos folded; no todos surfaced as relevant in the manual `.planning/STATE.md` review.
</deferred>
