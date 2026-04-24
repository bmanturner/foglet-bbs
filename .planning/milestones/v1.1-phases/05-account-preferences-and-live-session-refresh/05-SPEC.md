# Phase 5: Account Preferences and Live Session Refresh - Specification

**Created:** 2026-04-24
**Ambiguity score:** 0.13 (gate: <= 0.20)
**Requirements:** 6 locked

## Goal

Users can edit private Account profile fields, timezone, time display, and theme preferences, with saved changes persisted and reflected in the active TUI session without reconnecting.

## Background

The Account screen exists today as a scaffold with `PROFILE`, `PREFS`, and conditional `INVITES` tabs. `PROFILE` and `PREFS` render placeholder text and dispatch no save commands. The `users` schema already stores `location`, `tagline`, `real_name`, `theme`, and `preferences`, and `Accounts.update_profile/2` persists profile-shaped updates through `User.profile_changeset/2`. There is no first-class `users.timezone` column, no explicit `time_format` preference contract, no Timex dependency, no Account preference editing UI, and SSH session context always starts with `Foglet.TUI.Theme.default()` instead of deriving presentation state from the saved user.

## Requirements

1. **Timezone storage and default**: Persist each user's timezone in a dedicated `users.timezone` string column.
   - Current: `users` has no `timezone` column; timezone is only described in milestone requirements.
   - Target: New users receive a non-null default timezone derived from the configured system timezone when available, otherwise `"Etc/UTC"`.
   - Acceptance: A newly registered user has a persisted `timezone`; when no system timezone is configured or resolvable, the persisted value is `"Etc/UTC"`.

2. **Preference validation contract**: Account preference saves validate timezone, time format, and theme against explicit allowed values.
   - Current: `User.profile_changeset/2` accepts arbitrary `theme` and `preferences` values without a timezone field.
   - Target: Timezone values are valid IANA names using Timex, `preferences["time_format"]` is either `"12h"` or `"24h"`, and `theme` is one of the registered Foglet theme ids.
   - Acceptance: Saving an invalid timezone, invalid time format, or unknown theme returns an invalid changeset or visible Account error and does not mutate the persisted user row.

3. **Private profile editing**: Users can edit private profile fields from Account.
   - Current: `PROFILE` renders placeholder copy and no Account save path exists.
   - Target: Account allows the current user to edit `location`, `tagline`, and `real_name`; blank input is normalized to `nil`; `location` is capped at 80 characters, `tagline` at 120 characters, and `real_name` at 120 characters.
   - Acceptance: Saving valid profile values persists them for the current user; saving blank values stores `nil`; values over their maximum lengths are rejected and leave existing persisted values unchanged.

4. **Presentation preference editing**: Users can edit timezone, time format, and saved theme from Account.
   - Current: `PREFS` renders placeholder copy; `theme` exists but is not driven by Account, and time display has no locked storage key.
   - Target: Account allows the current user to save `timezone`, `preferences["time_format"]`, and `theme`; new users default to `"12h"` time format and the default registered Foglet theme until changed.
   - Acceptance: Saving valid preference values persists the timezone column, persists `preferences["time_format"]`, persists `theme`, and reloading the user returns the saved values.

5. **Best-effort theme preview**: Theme selection previews the highlighted candidate before save without persisting it.
   - Current: Account has no theme selector and the active session theme is fixed at session startup.
   - Target: While navigating or selecting theme options in Account, the visible Account screen rerenders using the highlighted candidate theme before save; the persisted user theme and durable session theme remain unchanged until save.
   - Acceptance: Moving the Account theme selection to a different registered theme changes the rendered Account output before save; canceling or leaving without saving reverts rendering to the saved theme and does not update the database.

6. **Live session refresh after save**: Saved Account changes refresh the active TUI and session process without reconnecting.
   - Current: SSH session context is built with `Theme.default()` and there is no Account save path that updates `state.current_user`, `state.session_context`, or `Foglet.Sessions.Session`.
   - Target: After a successful Account save, the active TUI state has the reloaded user, `session_context.theme` reflects the saved theme, session context includes the saved timezone and time format, and the backing `Foglet.Sessions.Session` GenServer is updated with the same preference snapshot.
   - Acceptance: In a running TUI state with a session pid, saving Account preferences updates the rendered theme/time preference snapshot immediately, updates `state.current_user`, and a subsequent session-state read exposes the saved preference values without reconnecting.

## Boundaries

**In scope:**
- Add Timex as the timezone validation and future timestamp conversion dependency for this milestone.
- Add a dedicated `users.timezone` column with defaulting for new users.
- Store 12-hour/24-hour display as `preferences["time_format"]` with values `"12h"` and `"24h"`.
- Keep saved theme in the existing `users.theme` field and validate it against registered Foglet themes.
- Replace Account `PROFILE` and `PREFS` placeholders with editable current-user behavior and save/error feedback.
- Refresh active TUI state and the backing session process after successful Account saves.
- Provide best-effort unsaved theme preview while selecting themes in Account.

**Out of scope:**
- Phase 6 chrome clock rendering and once-per-minute refresh - Phase 6 consumes the preference model produced here.
- Broad timestamp conversion across all screens - this phase establishes validated preferences and live session state only.
- Live preview for timezone or time format selections - only theme preview is required before save.
- Password, email, and SSH key management - these are v2 Account requirements.
- Public profile display, search, privacy controls, markdown profile content, or profile activity rendering - Phase 5 edits private Account data only.
- Theme creation, editing, accessibility variants, or registry administration - users choose from registered Foglet themes only.
- Changing invite tab behavior - Phase 4 owns shared invite activation.

## Constraints

- Timezone validation and conversion support must use Timex for this milestone.
- The database continues to store canonical UTC timestamps; `users.timezone` stores an IANA timezone name string.
- `users.preferences` remains a JSON map for presentation flags such as `time_format`; do not add a dedicated `time_format` column in this phase.
- Saved theme identifiers must round-trip between the string stored on `users.theme` and the atom ids returned by `Foglet.TUI.Theme.ids/0`.
- Account saves must not allow the current user to change `handle`, `email`, `password`, `role`, `status`, or invite policy fields.
- Invalid Account saves must preserve the previous persisted values and display field-level or save-level errors in Account.

## Acceptance Criteria

- [ ] New users persist a valid `users.timezone`, defaulting to the configured system timezone when available and `"Etc/UTC"` otherwise.
- [ ] Invalid timezone names are rejected and do not change the persisted user row.
- [ ] Invalid `preferences["time_format"]` values are rejected; only `"12h"` and `"24h"` are accepted.
- [ ] Invalid theme ids are rejected; only registered Foglet theme ids are accepted.
- [ ] `location`, `tagline`, and `real_name` can be saved from Account, blank values become `nil`, and max-length violations are rejected.
- [ ] Timezone, time format, and theme can be saved from Account and are present after reloading the user.
- [ ] Moving theme selection in Account previews the candidate theme before save.
- [ ] Canceling or leaving Account with an unsaved theme candidate restores the saved theme and does not mutate the database.
- [ ] Successful Account saves update `state.current_user`, `state.session_context.theme`, timezone/time-format session context, and the backing `Foglet.Sessions.Session` without reconnecting.
- [ ] Phase 6 chrome clock rendering is not implemented in this phase.

## Ambiguity Report

| Dimension           | Score | Min   | Status | Notes |
|---------------------|-------|-------|--------|-------|
| Goal Clarity        | 0.94  | 0.75  | met    | Account profile/preference saves plus immediate session refresh are explicit. |
| Boundary Clarity    | 0.90  | 0.70  | met    | Phase 6 clock work, broad timestamp conversion, and account security settings are excluded. |
| Constraint Clarity  | 0.86  | 0.65  | met    | Timex, timezone column, JSON time format, and registered theme validation are locked. |
| Acceptance Criteria | 0.84  | 0.70  | met    | Pass/fail checks cover persistence, validation, preview, and live refresh. |
| **Ambiguity**       | 0.13  | <=0.20| met    | Gate passed after round 3. |

Status: met = met minimum, warning = below minimum (planner treats as assumption)

## Interview Log

| Round | Perspective | Question summary | Decision locked |
|-------|-------------|------------------|-----------------|
| 1 | Researcher | Where should timezone and time format be stored? | `users.timezone` becomes a new column; `preferences["time_format"]` stores `"12h"` or `"24h"`; `users.theme` remains the saved theme field. |
| 1 | Researcher | What must live session refresh update? | Successful saves update active TUI state and the backing `Foglet.Sessions.Session` GenServer. |
| 1 | Researcher | Should the spec lock exact Account interaction style? | No; the spec locks observable behavior and leaves form/modal/sub-state implementation to discuss-phase and plan-phase. |
| 2 | Researcher + Simplifier | What is minimum timezone behavior? | Use Timex; validate IANA timezone names; default new users to system timezone when available, otherwise `"Etc/UTC"`. |
| 2 | Researcher + Simplifier | What profile validation is required? | Optional bounded strings: `location` max 80, `tagline` max 120, `real_name` max 120; blanks normalize to `nil`. |
| 2 | Researcher + Simplifier | What preference set must update live? | Timezone, time format, and theme only; email digest, last-caller visibility, password/email/SSH keys, and preview hints are excluded. |
| 2 | Researcher + Simplifier | Should selected themes preview before save? | Best-effort preview is desired when selecting themes. |
| 3 | Boundary Keeper | How strong is the theme preview requirement? | Account rerenders with the highlighted candidate theme before save; persistence/session theme remain unchanged until save; cancel/leave reverts. |
| 3 | Boundary Keeper | Should Timex be canonical for this phase? | Yes; add Timex and use it for timezone validation and future user-facing timestamp conversion. |
| 3 | Boundary Keeper | What is explicitly out of scope? | Exclude Phase 6 chrome clock, broad timestamp conversion, timezone/time-format previews, account security settings, public profiles, theme authoring, and invite behavior changes. |

---

*Phase: 05-account-preferences-and-live-session-refresh*
*Spec created: 2026-04-24*
*Next step: $gsd-discuss-phase 5 - implementation decisions (how to build what's specified above)*
