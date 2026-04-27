# Phase 30: Account Workflow — Specification

**Created:** 2026-04-27
**Ambiguity score:** 0.16 (gate: ≤ 0.20)
**Requirements:** 5 locked

## Goal

After Phase 30, Account Profile edits visibly persist across screen exit/re-entry with an inline `[Saved]` flash; the PROFILE/PREFERENCES/SSH KEYS tab bodies do not repeat the active tab's name; every visible Preferences field is changeable via the right widget (timezone via a Timex-backed type-ahead `SelectList`, time_format and theme via `RadioGroup`); and the SSH Keys add-flow accepts a multi-line OpenSSH public-key paste, storing it in normalized single-line form.

## Background

Account screens already exist and route through the Modal.Form substrate landing in Phase 28:

- `lib/foglet_bbs/tui/screens/account.ex` — tab dispatch (PROFILE / PREFERENCES / SSH KEYS).
- `lib/foglet_bbs/tui/screens/account/profile_form.ex` — Modal.Form-backed Profile editor; submits via `{:account_save_profile, attrs}` → `Foglet.Accounts.update_profile/2` → `Repo.update`.
- `lib/foglet_bbs/tui/screens/account/prefs_form.ex` — Preferences form with fields `timezone (:text)`, `time_format (:enum 12h|24h)`, `theme (:enum from Theme.ids/0)`.
- `lib/foglet_bbs/tui/screens/account/ssh_keys_state.ex` + `ssh_keys_actions.ex` + `ssh_keys_surface.ex` — custom (non-Modal.Form) SSH-keys surface; add-mode handles input char-by-char and submits on Enter.
- `lib/foglet_bbs/tui/widgets/modal/form.ex` — Modal.Form renders an internal title row above field rows for every form; this title is the "duplicate heading" inside tabbed Account screens.
- `Timex ~> 3.7` is already a dep (`mix.exs:67`); `Timex.Timezone.exists?/1` is used elsewhere; Tzdata is transitive.

What's broken / missing today (gap → target):

- **Saved flash is invisible.** `state.status_message` is set on save but ProfileForm/PrefsForm never render it; users cannot tell whether submit took effect (Account #3).
- **Profile re-entry not verified.** Persistence path is wired through `update_profile/2` but a defdelegate-drop refactor (commit `6d86de1`) shipped during v1.4 without an integration check that saved values reappear after exit/re-entry. Needs human SSH/TUI UAT to confirm or surface the regression.
- **Modal.Form's internal title row duplicates the active tab name** on PROFILE / PREFERENCES / SSH KEYS (and any other tabbed form-bearing screen, e.g. Sysop SITE) — the tab strip already establishes the heading (Account #2).
- **Preferences widgets do not commit changes.** time_format and theme render as `RadioGroup`, but selecting a different value does not persist — a focus-routing/commit gap that Phase 28's FORM-01/FORM-04/FORM-05 work is expected to repair; Phase 30 verifies the result and flips the user-visible behavior.
- **Timezone is a free-text field**, not a type-ahead selector — users cannot clear, replace, or pick a zone without knowing the full IANA identifier (Account #6).
- **SSH-key paste does nothing.** Pasting any text into the focused `public_key` field produces no visible result; multi-line content can never be entered (Account #9). The cause is implementation-level (paste bytes are not delivered to `SSHKeysActions.handle_key/3` as `:char` events, or are dropped); the user-visible contract is what Phase 30 must guarantee.

## Requirements

1. **ACCT-01 — Profile persists with visible Saved flash**: Profile submit produces a visible `[Saved]` row, and saved values reappear on screen re-entry.
   - Current: ProfileForm submit reaches `Accounts.update_profile/2`, but the inline `[Saved]` flash is invisible (`state.status_message` is set but not rendered) and re-entry behavior has not been UAT-verified since the v1.4 `Accounts` defdelegate-drop refactor.
   - Target: After Profile submit at 64×22 and 80×24 SSH, an inline `[Saved]` row is rendered inside the PROFILE tab body. The flash remains visible until the next user keypress or screen exit (no timer). Leaving Account and re-entering at the PROFILE tab shows the previously saved values in their fields.
   - Acceptance: Human SSH/TUI UAT script (recorded in the phase verification artifact) executes — at both 64×22 and 80×24 — (a) edit a Profile field, (b) press Enter, (c) observe an inline `[Saved]` row beneath the form, (d) press any key and observe the row disappear, (e) leave Account and re-enter, (f) observe the saved value in the field. All six checks pass.

2. **ACCT-02 — No tab-name duplication inside tab bodies**: Modal.Form gains a caller-controlled way to suppress its internal title row, and every tabbed form-bearing Account screen disables it.
   - Current: `lib/foglet_bbs/tui/widgets/modal/form.ex` always renders an internal title row at the top of the form body; inside PROFILE, PREFERENCES, and SSH KEYS the row reads "Profile" / "Preferences" / "SSH Keys" — a duplicate of the active tab label already shown by the tab strip.
   - Target: Modal.Form accepts an option (e.g. `:show_internal_title` / equivalent) to suppress the internal title row; ProfileForm, PrefsForm, and the new Modal.Form-backed SSH-keys add form (if Modal.Form is reused under ACCT-05) pass the suppress option. Sysop SITE and any other tabbed Modal.Form callers may opt in. No regression elsewhere: forms outside tabbed containers continue to render their internal title.
   - Acceptance: Inspecting the PROFILE / PREFERENCES / SSH KEYS tab bodies via `mix foglet.tui.render` at 64×22 and 80×24 shows the form fields starting on the row immediately under the tab strip's separator, with no `Profile` / `Preferences` / `SSH Keys` heading row above them. A non-tabbed Modal.Form caller (e.g. Login) still renders its internal title row (regression check).

3. **ACCT-03 — Preferences fields are reachable and committable via the right widget**: timezone uses a `SelectList` (per ACCT-04), time_format and theme are `RadioGroup`s whose selection actually persists on submit, and the form pipeline is verified to render `:checkbox` for any future boolean preference without code changes.
   - Current: `prefs_form.ex` renders timezone as a TextInput, time_format and theme as RadioGroups. Selecting a different time_format or theme value via the RadioGroup does not commit on submit (a focus-routing / submit-state gap shared with FORM-01/FORM-04/FORM-05 in Phase 28). No boolean preferences are surfaced today; the `:checkbox` field type exists in `widgets/modal/form.ex` but has no PrefsForm caller.
   - Target: With Phase 28's Modal.Form fixes in place, time_format and theme RadioGroup selection persists end-to-end (form draft → submit → `Accounts.update_preferences/2` → `Repo.update` → re-mount shows new value). Timezone is replaced by a `SelectList` (see ACCT-04). The `:checkbox` field type is exercised by a non-shipped fixture or test path that confirms the rendering pipeline accepts it; no production boolean is added in this phase.
   - Acceptance: Automated test asserts that for each of `time_format` and `theme`, changing the focused value via Up/Down + Enter and submitting via Enter results in the new value being persisted (read-back from `Foglet.Accounts.get_preferences/1` matches). A pipeline test (or rendering smoke) confirms PrefsForm renders a `:checkbox` field type without raising. PrefsForm production fields remain `timezone`, `time_format`, `theme` — no new prefs.

4. **ACCT-04 — Timezone field is an IANA type-ahead SelectList backed by Timex**: users can clear, replace, or pick a timezone without typing the full identifier; the current value is visible while editing.
   - Current: Timezone is a `:text` field with no validation client-side and no list-of-zones helper. Users must type a full valid IANA name (e.g. `America/New_York`) from memory; clearing the field is impossible to do safely (any partial match fails validation on submit).
   - Target: Timezone is rendered as a `SelectList` whose source is the IANA zone list available via Timex (`Timex.timezones/0` or equivalent zone enumeration; Tzdata is transitive). Typing `lon` narrows the list to zones containing `lon` (case-insensitive substring match). Enter on a focused row commits the selection. The currently-saved value is visible in the field while the SelectList is open. The user can clear the field (Esc / dedicated clear binding) and pick a new zone without typing the full identifier. Invalid/unknown values cannot be submitted (constrained by the SelectList's source).
   - Acceptance: Test asserts (a) opening Preferences with a saved value shows that value in the field, (b) opening the SelectList and typing `lon` filters to zones whose IANA name matches `lon` case-insensitively (e.g. `Europe/London`, `America/Atikokan` is excluded but `America/Bogota` is included only if `lon` matches; the operative check is that `Europe/London` is in the filtered set), (c) Enter on `Europe/London` commits and on submit the persisted value is `Europe/London`, (d) clearing and selecting a different zone (e.g. `Asia/Tokyo`) without typing the full identifier persists `Asia/Tokyo`. Manual SSH/TUI UAT at 64×22 confirms the SelectList fits within the PREFERENCES tab body without overflowing.

5. **ACCT-05 — SSH-key add accepts multi-line paste, stores normalized single-line value**: paste content reaches the public_key field and the persisted value is the single-line `algorithm key [comment]` form.
   - Current: In SSH KEYS add-mode, focusing the `public_key` field and pasting any text produces no visible result — paste bytes never reach `SSHKeysActions.handle_key/3` as `:char` events (or are dropped). Multi-line keys cannot be entered. Embedded `\n` characters during a hypothetical paste would prematurely submit the form because Enter handling triggers submit.
   - Target: Pasting an OpenSSH public key (single-line or multi-line `algorithm\nbase64\ncomment`) into a focused `public_key` field results in (a) the pasted content being captured into the field's draft buffer in full, (b) embedded newlines NOT triggering form submission while paste is in progress, and (c) on Enter-to-submit, the persisted `public_key` value being the single-line normalized form `algorithm base64 [comment]` (internal newlines collapsed to single spaces, leading/trailing whitespace trimmed). The implementation strategy (bracketed-paste-mode, raw-byte capture, Modal.Form `:textarea` reuse, etc.) is left to discuss-phase. The field shows a truncated/elided preview at 64×22 SSH so the value fits the column.
   - Acceptance: Automated test passes a binary representing a multi-line OpenSSH ed25519 key (with literal `\n` between algorithm/key/comment) through the add-flow's submit pipeline; the resulting persisted `public_key` matches the single-line normalized form (asserted byte-for-byte against an expected `ssh-ed25519 AAAA... user@host` string). Manual SSH/TUI UAT at 64×22 confirms (a) pasting a multi-line key into the focused field shows the content in the field (truncated/elided is acceptable), (b) the form is not submitted by the paste itself, (c) pressing Enter after paste persists a single-line value visible in the SSH-keys list.

## Boundaries

**In scope:**

- Modal.Form gets an option to suppress its internal title row; ProfileForm, PrefsForm, and SSH-keys add (whatever the chosen implementation under ACCT-05) pass the suppress option. Sysop SITE and any other tabbed Modal.Form caller may opt in but is not required.
- Render `state.status_message` as an inline `[Saved]` flash row inside ProfileForm and PrefsForm tab bodies; clear on next keypress or screen exit (no timer).
- Replace timezone TextInput with a Timex-backed type-ahead `SelectList`; reuse existing widgets, no new Raxol primitives.
- Verify (via test) that time_format and theme RadioGroup selections persist after Phase 28's Modal.Form work lands; render the inline `[Saved]` flash on Preferences submit.
- SSH-keys add-flow: deliver pasted content to the `public_key` field, normalize to single-line on submit, render an elided preview at 64×22.
- Add a phase-owned UAT script under `.planning/phases/30-account-workflow/` for ACCT-01 and ACCT-04 and ACCT-05 manual checks (recorded in the verification artifact).

**Out of scope:**

- Modal.Form FORM-01 / FORM-04 / FORM-05 (Up/Down focus, focus routing, submit_state) — owned by Phase 28; Phase 30 only consumes the result.
- Cursor rendering inside Account text inputs — owned by Phase 27 (CURSOR-01).
- Adding new Preferences fields (notifications, signatures, mute lists) — no schema or column additions; PrefsForm production fields stay at timezone, time_format, theme.
- Account deletion flow / role changes / operator promotion — no Phase 30 work touches these paths.
- Browser/HTML access to Account screens — Foglet remains SSH-first (PROJECT.md decision); no LiveView Account page.
- Tzdata version-update tooling / scheduled refresh — Timex's bundled Tzdata is sufficient for v1.4; periodic-update process is not introduced in this phase.
- SSH-keys list management (revoke, rename, reorder) — only the add-flow paste path is in scope; existing list keybinds are untouched.

## Constraints

- 64×22 is the hard minimum terminal size; 80×24 is the compact target. Every visible behavior must work at 64×22 SSH.
- Timezone selector source is Timex (`{:timex, "~> 3.7"}` already in `mix.exs`). No new dependency is added in this phase. Tzdata is consumed transitively via Timex.
- The `[Saved]` flash MUST NOT use a timer / `Process.send_after`; it clears on the next keypress or screen exit. This avoids cross-phase test flake and keeps the TUI command/event surface unchanged.
- All color decisions in modified Account render paths route through `Foglet.TUI.Theme` slots (no hardcoded `IO.ANSI.*` literals).
- Modal.Form's existing callers outside tabbed containers must continue to render their internal title row by default (suppression is opt-in per call site).
- Domain mutations (`update_profile/2`, `update_preferences/2`, `add_ssh_key/2`) remain inside `Foglet.Accounts`; no domain logic is added to TUI screens or Modal.Form.
- The SSH-keys public_key persisted value is a single-line normalized string; the schema/changeset constraint stays a single `:string` column (no migration in this phase).

## Acceptance Criteria

- [ ] After Profile submit at 64×22 SSH, an inline `[Saved]` row is rendered inside the PROFILE tab body.
- [ ] After Preferences submit at 64×22 SSH, an inline `[Saved]` row is rendered inside the PREFERENCES tab body.
- [ ] The `[Saved]` row disappears on the next keypress or screen exit (no timer).
- [ ] Manual UAT confirms: edit Profile → submit → leave Account → re-enter → saved values appear in the form fields. Recorded at 64×22 and 80×24.
- [ ] No `Profile` / `Preferences` / `SSH Keys` heading row appears between the tab strip's separator and the first form field on the corresponding tab body (verified via `mix foglet.tui.render` at 64×22 and 80×24).
- [ ] A non-tabbed Modal.Form caller (e.g. Login) still renders its internal title row (regression check).
- [ ] PrefsForm timezone field is rendered as a `SelectList`, not a TextInput.
- [ ] Typing `lon` in the timezone SelectList filters to zones whose IANA name matches `lon` case-insensitively, and `Europe/London` is in the filtered set.
- [ ] Selecting `Europe/London` and submitting persists `Europe/London` to the user's preferences (read-back via `Foglet.Accounts.get_preferences/1`).
- [ ] Clearing the timezone field and selecting `Asia/Tokyo` without typing the full identifier persists `Asia/Tokyo`.
- [ ] Selecting a different `time_format` (12h ↔ 24h) via RadioGroup + Enter on submit persists the new value.
- [ ] Selecting a different `theme` via RadioGroup + Enter on submit persists the new value.
- [ ] PrefsForm rendering pipeline accepts a `:checkbox` field type without raising (smoke test).
- [ ] Pasting a multi-line OpenSSH public key into the focused `public_key` field results in the content being captured (verified manually at 64×22 SSH).
- [ ] Embedded newlines during paste do NOT trigger form submission.
- [ ] On Enter-to-submit after paste, the persisted `public_key` is the single-line normalized form `algorithm base64 [comment]` (asserted byte-for-byte in an automated test against an expected string).
- [ ] After successful add, the SSH-keys list shows the new key with a truncated/elided preview at 64×22 SSH.
- [ ] No hardcoded `IO.ANSI.*` literals appear in modified Account render paths.

## Ambiguity Report

| Dimension          | Score | Min  | Status | Notes                                                 |
|--------------------|-------|------|--------|-------------------------------------------------------|
| Goal Clarity       | 0.90  | 0.75 | ✓      | 5 falsifiable sub-goals                               |
| Boundary Clarity   | 0.80  | 0.70 | ✓      | Modal.Form title-row work in scope; FORM-01..05 not   |
| Constraint Clarity | 0.78  | 0.65 | ✓      | Timex (no new dep); flash uses no timer; 64×22 hard   |
| Acceptance Criteria| 0.85  | 0.70 | ✓      | 18 pass/fail checkboxes                               |
| **Ambiguity**      | 0.16  | ≤0.20| ✓      |                                                       |

Status: ✓ = met minimum, ⚠ = below minimum (planner treats as assumption)

## Interview Log

| Round | Perspective       | Question summary                                          | Decision locked                                                                 |
|-------|-------------------|-----------------------------------------------------------|---------------------------------------------------------------------------------|
| 1     | Researcher        | ACCT-01 — persistence broken vs flash invisible vs both?   | Both — render the flash AND audit the persistence path (manual UAT, see below) |
| 1     | Researcher        | ACCT-02 — what counts as the duplicate heading?            | Modal.Form's internal title row is the duplicate                               |
| 1     | Researcher        | ACCT-03 — which fields actually need a widget change?      | Timezone → SelectList; time_format & theme already render but selection-commit is broken (Phase 28 FORM-01/04 dep); no new prefs |
| 2     | Boundary Keeper   | Tzdata vs Timex vs static list?                           | Use Timex (already a dep)                                                       |
| 2     | Boundary Keeper   | ACCT-05 — bracketed paste vs field-local vs textarea?     | "Nothing happens on paste today" — frame contract as outcome, not implementation |
| 2     | Boundary Keeper   | ACCT-01 audit scope — integration test vs checklist vs skip? | Make persistence re-entry a human UAT item                                    |
| 2     | Boundary Keeper   | Flash duration — timer vs keypress vs persistent?         | Show until next keypress or screen exit (no timer)                              |
| 3     | Boundary Keeper   | ACCT-02 boundary — Profile only vs all 3 vs project-wide? | All forms project-wide that live inside a tabbed container                      |
| 3     | Failure Analyst   | ACCT-03 toggles — surface schema booleans now?            | Treat Checkbox as a forward-compatibility check — no production boolean added   |
| 3     | Failure Analyst   | ACCT-05 paste contract — visible vs bracketed vs normalized? | Stored value matches normalized form (implementation deferred to discuss-phase) |
| 3     | Boundary Keeper   | Out-of-scope confirmation                                 | Browser, new prefs, deletion/role changes confirmed OUT; Modal.Form internal-title work IN |

---

*Phase: 30-account-workflow*
*Spec created: 2026-04-27*
*Next step: /gsd-discuss-phase 30 — implementation decisions (paste capture strategy, SelectList widget choice, internal-title API name)*
