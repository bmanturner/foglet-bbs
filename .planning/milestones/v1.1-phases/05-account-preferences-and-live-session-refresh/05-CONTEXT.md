# Phase 05: account-preferences-and-live-session-refresh - Context

**Gathered:** 2026-04-24 (assumptions mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Users can edit private Account profile fields, timezone, time display, and theme preferences, with saved changes persisted and reflected in the active TUI session without reconnecting. This phase establishes the preference model, Account editing UX, validation, theme preview, and live session refresh only; Phase 6 consumes these preferences for chrome clock rendering.
</domain>

<decisions>
## Implementation Decisions

### Persistence Contract
- **D-01:** Extend the existing `users` row for Account preferences: add dedicated `users.timezone`, continue storing `preferences["time_format"]`, and continue storing the saved theme in `users.theme`.
- **D-02:** Keep `Foglet.Accounts.update_profile/2` as the Account profile/preference mutation boundary rather than creating a separate preferences table or Account-only persistence API.
- **D-03:** New user defaulting belongs in the Accounts/User registration path so all registration modes persist timezone, default `"12h"` time format, and the default registered Foglet theme consistently.

### Validation Ownership
- **D-04:** Put timezone, time format, theme, and bounded private-profile validation in `Foglet.Accounts.User.profile_changeset/2` so invalid values are rejected for every caller of `Accounts.update_profile/2`, not only the TUI.
- **D-05:** Validate `timezone` as an IANA timezone with Timex; use `Timex.Timezone.exists?/1` for save validation.
- **D-06:** Derive the default timezone from `Timex.Timezone.local/0` plus `Timex.Timezone.name_of/1` when possible, and fall back to `"Etc/UTC"` when local timezone resolution is unavailable or invalid.
- **D-07:** Validate `preferences["time_format"]` as exactly `"12h"` or `"24h"`.
- **D-08:** Validate `theme` against registered Foglet theme ids from `Foglet.TUI.Theme.ids/0`, preserving string storage and atom/string round-trip behavior.
- **D-09:** Normalize blank `location`, `tagline`, and `real_name` values to `nil`; enforce the SPEC maximums of 80, 120, and 120 characters respectively.

### Account UI Shape
- **D-10:** Prefer exploring inline editable forms directly inside the Account `PROFILE` and `PREFS` tabs instead of locking `Foglet.TUI.Widgets.Modal.Form` as the default UX.
- **D-11:** Treat Phase 5 as the reference opportunity for a good inline page form pattern in Foglet's TUI, especially because inline theme selection may make unsaved theme preview more natural than a modal flow.
- **D-12:** Researcher and planner may still choose `Modal.Form` if codebase evidence shows it is clearly better, but the default planning bias should be inline Account forms with explicit focus, save, cancel/revert, and field-error behavior.
- **D-13:** Preserve the existing Account screen/tab model: `PROFILE`, `PREFS`, and conditional `INVITES` stay in `Foglet.TUI.Screens.Account.State`; Account continues to own local UI state under `state.screen_state[:account]`.
- **D-14:** Do not change shared `INVITES` behavior in Phase 5. Account profile/preference input must coexist with, not replace or fork, the Phase 4 shared invite delegation.

### Theme Preview
- **D-15:** Theme preview should be modeled as an unsaved candidate theme in Account state. Rendering may temporarily resolve that candidate for the Account screen, but persisted `users.theme`, durable session theme, and session process state must remain unchanged until save.
- **D-16:** Canceling, leaving Account, or otherwise discarding unsaved changes must revert rendering to the saved session/user theme and leave the database unchanged.
- **D-17:** Theme preview is scoped to theme only; timezone and time-format preview remain out of scope.

### Live Session Refresh
- **D-18:** A successful Account save updates all three active snapshots together: `state.current_user`, `state.session_context` preference fields including `theme`, and the backing `Foglet.Sessions.Session` state.
- **D-19:** Add a first-class session update API for preference snapshots rather than reaching into the Session GenServer state from Account code.
- **D-20:** `Foglet.SSH.CLIHandler` should seed `session_context` from the saved user preference snapshot when an authenticated session starts instead of always using `Foglet.TUI.Theme.default()`.
- **D-21:** The session preference snapshot should include at least saved timezone, saved time format, and resolved theme so Phase 6 can render user-facing time without reconnecting.

### Testing and Quality Gate
- **D-22:** Cover persistence and validation in Accounts/User tests, including invalid timezone, invalid time format, invalid theme, blank profile normalization, and max-length rejection.
- **D-23:** Cover Account TUI inline editing behavior with focused tests for field navigation, save, cancel/revert, field-level errors, and unsaved theme preview.
- **D-24:** Cover live refresh through TUI/session tests proving a successful save updates `state.current_user`, `state.session_context`, and `Foglet.Sessions.Session.get_state/1`.
- **D-25:** `mix precommit` must pass before Phase 5 is considered complete.

### the agent's Discretion
- Exact inline form layout, key bindings, and field ordering, as long as terminal-native focus, save, cancel/revert, and visible error feedback are clear.
- Whether Profile and Prefs use one shared inline-form helper module or separate small tab modules.
- Exact wording of validation and success messages.
- Whether Timex default-timezone derivation is wrapped in `User`, `Accounts`, or a small helper module, as long as the validation/defaulting contract is tested.

### Folded Todos
None — `gsd-sdk query todo.match-phase 05` returned 0 matches.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase Scope and Requirements
- `.planning/phases/05-account-preferences-and-live-session-refresh/05-SPEC.md` — locked Phase 5 requirements, boundaries, constraints, acceptance criteria, and out-of-scope items.
- `.planning/ROADMAP.md` — Phase 5 goal and success criteria.
- `.planning/REQUIREMENTS.md` — `ACCT-02`, `ACCT-03`, `ACCT-04`, `ACCT-05`, and `ACCT-06`.
- `.planning/PROJECT.md` — terminal-first product direction, Account/preferences milestone target, and preference-model key decision.

### Prior Decisions
- `.planning/phases/00-screen-shells-and-shared-surface-primitives/00-CONTEXT.md` — Account shell/tab architecture, local screen-state pattern, and no fake persistence.
- `.planning/phases/01.1-shared-modal-form-primitive/01.1-CONTEXT.md` — Modal.Form capabilities and constraints; useful comparison point, but not locked as Phase 5's default UX.
- `.planning/phases/04-shared-invite-surface-activation/04-CONTEXT.md` — Account `INVITES` delegation and shared invite behavior that Phase 5 must preserve.

### Codebase and External References
- `.planning/codebase/STRUCTURE.md` — relevant Accounts, Sessions, SSH, and TUI module layout.
- `.planning/codebase/CONVENTIONS.md` — changeset, tagged-tuple, TUI state, module, and test conventions.
- `.planning/codebase/STACK.md` — current dependency stack and quality pipeline.
- `docs/ARCHITECTURE.md` — TUI/session layering and domain boundaries.
- `docs/DATA_MODEL.md` — user schema and persistence invariants.
- `docs/raxol/README.md` — Raxol documentation entry point.
- `docs/raxol/getting-started/WIDGET_GALLERY.md` — available TUI primitives.
- `lib/foglet_bbs/tui/widgets/README.md` — local themed widget overview.
- `https://hexdocs.pm/timex/Timex.Timezone.html` — Timex timezone validation/defaulting functions (`exists?/1`, `local/0`, `name_of/1`).
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Foglet.Accounts.User.profile_changeset/2` — existing profile/preference changeset to extend with timezone, time-format, theme, and private profile validation.
- `Foglet.Accounts.update_profile/2` — existing context mutation boundary for Account profile writes.
- `Foglet.TUI.Screens.Account` and `Foglet.TUI.Screens.Account.State` — existing Account tab screen and local state home for inline form state, candidate theme, errors, dirty flags, and shared invite state.
- `Foglet.TUI.Theme.ids/0`, `resolve/1`, `default/0`, and `from_state/1` — registered theme validation and session-scoped theme resolution.
- `Foglet.Sessions.Session` — active session GenServer to extend with a preference snapshot and update API.
- `Foglet.SSH.CLIHandler.build_context/3` — connection-time session context builder that currently always uses `Foglet.TUI.Theme.default()`.
- `Foglet.TUI.Widgets.Input.TextInput`, `Checkbox`, `RadioGroup`, and `Tabs` — reusable primitives for inline profile/preference fields.
- `Foglet.TUI.Widgets.Modal.Form` — available fallback/reference for typed form behavior, callbacks, and inline error rendering.

### Established Patterns
- Context functions return tagged tuples and changesets; TUI maps validation errors into visible field or save errors.
- Ecto schemas use dedicated changesets per mutation pathway; Account saves must not cast handle, email, password, role, status, or invite-policy fields.
- Screens own local state under `state.screen_state`; non-trivial tabs can delegate to helper modules while keeping the App router stable.
- Theme decisions route through `%Foglet.TUI.Theme{}` slots and `Theme.from_state/1`.
- TUI visibility checks are advisory; domain functions remain the persistence and validation trust boundary.

### Integration Points
- Add a migration for `users.timezone` and update user defaulting/backfill behavior.
- Extend `Foglet.Accounts.User` and `Foglet.Accounts` for the validated preference contract.
- Extend Account render/key handling and Account.State for inline profile/prefs editing, dirty state, unsaved theme candidate, and validation feedback.
- Extend Session state/API and SSH/TUI context construction so saved preferences are available at session start and refreshed after Account saves.
- Keep Account's `INVITES` tab delegation to shared invite modules unchanged.
</code_context>

<specifics>
## Specific Ideas

- The user specifically wants to explore inline Account forms because theme preview may be easier and more user-friendly inline than inside a modal.
- Phase 5 should leave behind a good reference pattern for inline page forms in Foglet's TUI if that UX proves sound.
- `Modal.Form` is still a relevant comparison and fallback, but downstream agents should not assume modal-first just because the primitive exists.
- Timex reference: `Timex.Timezone.exists?/1` validates zone names; `Timex.Timezone.local/0` and `Timex.Timezone.name_of/1` can support best-effort local default derivation with `"Etc/UTC"` fallback.
</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

### Reviewed Todos (not folded)
None reviewed — `gsd-sdk query todo.match-phase 05` returned 0 matches.
</deferred>

---

*Phase: 05-account-preferences-and-live-session-refresh*
*Context gathered: 2026-04-24*
