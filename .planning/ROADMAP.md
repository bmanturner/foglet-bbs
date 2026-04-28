# Roadmap: Foglet BBS

## Milestones

- [x] **v1.1 Operations Surfaces & Invites** - Phases 0-8, including inserted Phase 1.1 (shipped 2026-04-24). See [v1.1 roadmap archive](milestones/v1.1-ROADMAP.md).
- [x] **v1.2 Pre-Alpha Gap Closure** - Phases 9-15 (shipped 2026-04-24). See [v1.2 roadmap archive](milestones/v1.2-ROADMAP.md).
- [x] **v1.3 TUI Screen Facelift** - Phases 16-25 (shipped 2026-04-26). See [v1.3 roadmap archive](milestones/v1.3-ROADMAP.md).
- [ ] **v1.4 Post-Facelift Polish & Bug Fixes** - Phases 26-33 (in progress). Driven by `ISSUES.md`.

## Current Status

v1.4 milestone in planning. Phases 26-33 derived from 38 requirements in `.planning/REQUIREMENTS.md`, grounded in the 4-researcher synthesis in `.planning/research/SUMMARY.md`. All 38 requirements mapped to exactly one phase.

## Phase Summary (v1.4)

| Phase | Name | Goal (one-line) | Requirements | UI |
|-------|------|-----------------|--------------|-----|
| 26 | Layout & Width Foundations | 4/4 | Complete   | 2026-04-26 |
| 27 | Cursor & Breadcrumb Polish | 3/3 | Complete   | 2026-04-26 |
| 28 | Modal.Form Substrate | 7/7 | Complete   | 2026-04-27 |
| 29 | Sysop Tab Lifecycle & Bodies | 4/4 | Complete    | 2026-04-27 |
| 30 | Account Workflow | Account Profile/Preferences/SSH-keys edits actually persist and accept multi-line paste | ACCT-01..05 (5) | yes |
| 31 | Auth Flow | 4/4 | Complete    | 2026-04-28 |
| 32 | Main Menu Chrome Polish | 3/3 | Complete   | 2026-04-28 |
| 33 | Composer Wrap & Boards Interaction | 3/3 | Complete    | 2026-04-28 |

## Phases

- [x] v1.1 Operations Surfaces & Invites (Phases 0-8)
- [x] v1.2 Pre-Alpha Gap Closure (Phases 9-15)
- [x] v1.3 TUI Screen Facelift (Phases 16-25)
- [x] **Phase 26: Layout & Width Foundations** — Tab-row glyph fix, responsive tables, viewport clamping, `TextWidth.wrap` helper, markdown blank-line preservation (completed 2026-04-26)
- [x] **Phase 27: Cursor & Breadcrumb Polish** — TextInput cursor follows insertion point; breadcrumb updates for Login sub-states (Register/Forgot/Verify/reset-consume) (completed 2026-04-26)
- [~] **Phase 28: Modal.Form Substrate** — Up/Down inter-field movement, `:backtab`, optional footer, single-source focus, submit-state machine, honest Esc. Implementation + gap-closure (28-05/06/07) + code review fixes complete; **4 live-SSH UAT items pending — see 28-HUMAN-UAT.md** (impl complete 2026-04-27)
- [x] **Phase 29: Sysop Tab Lifecycle & Bodies** — Auto-load on tab switch, tagged enum render, Site draft echo, Users status-gated keybinds, Invites row selection, command-bar consistency (completed 2026-04-27)
- [ ] **Phase 30: Account Workflow** — Profile persistence + flash, no-duplicate tab title, Preferences widgets reachable, IANA timezone selector, SSH-key paste accepts multi-line
- [x] **Phase 31: Auth Flow** — Forgot-password local validation (enum-safe), reset message wrap, no-email honest copy, atomic token-consume (Accounts boundary) (completed 2026-04-28)
- [x] **Phase 32: Main Menu Chrome Polish** — Border-embedded titles, no Oneliners glyph artifact, accent-colored nav keys, indent corrections, theme-routed colors (completed 2026-04-28)
- [x] **Phase 33: Composer Wrap & Boards Interaction** — Composer soft-wrap via `TextWidth.wrap`, Boards Enter on category toggles expansion (completed 2026-04-28)

## Phase Details

### Phase 26: Layout & Width Foundations
**Goal**: Width-math primitives stop overflowing terminals, tables breathe, and markdown preserves paragraph breaks — establishing a stable visual canvas before form/interaction fixes can be verified.
**Depends on**: Nothing (first v1.4 phase)
**Requirements**: LAYOUT-01, LAYOUT-02, LAYOUT-03, LAYOUT-04, LAYOUT-05, LAYOUT-06, POST-01
**Success Criteria** (what must be TRUE):
  1. At 64×22 SSH, every tabbed screen (Account, Moderation, Sysop) renders the tab row with no trailing border-glyph artifact past the rightmost tab; the rightmost tab-row column equals the frame's vertical glyph (`│`).
  2. At 64×22 and 80×24 SSH, Moderation LOG/USERS/BOARDS tabs and the Boards screen fit within the user's terminal — no rows render above the top edge or below the bottom; over-large content scrolls/paginates inside the content region.
  3. The Sysop Invites table at 80×24 renders Code, Status, Created, and Used by as visibly distinct columns with separator whitespace; the Moderation LOG table at 80×24 fills available width and elides long messages with `…`.
  4. `Foglet.TUI.TextWidth.wrap/2` exists, is grapheme-cluster-aware, and is exercised by a unit test using `あ`, combining `é`, ZWJ emoji, and a no-space ssh-rsa-shaped blob.
  5. A post body with two consecutive newlines renders as one blank visible line in the post reader; three or more newlines clamp to one blank; soft breaks render as line breaks.
**Plans**: 3 plans
Plans:
- [x] 27-01-PLAN.md — Implement insertion-point cursor rendering in shared TextInput
- [x] 27-02-PLAN.md — Map Login/Register/Forgot/Verify/reset-consume breadcrumbs in shared chrome
- [x] 27-03-PLAN.md — Add 64x22 and 80x24 cursor/breadcrumb render-smoke validation
**UI hint**: yes

### Phase 27: Cursor & Breadcrumb Polish
**Goal**: A real cursor follows the user's insertion point on every TextInput, and the shared chrome breadcrumb tracks Login sub-states correctly — so visual verification of every later form/auth fix is reliable.
**Depends on**: Phase 26 (visual verification needs the stable canvas)
**Requirements**: CURSOR-01, BREAD-01
**Success Criteria** (what must be TRUE):
  1. On a focused single-line TextInput, typing five characters then backspacing twice leaves the cursor at column 3 (cell-width based, via `TextWidth.display_width`); cursor disappears on blur/disable.
  2. The cursor renders consistently on every focused single-line input across Login, Register, Forgot Password, Verify, Account Profile, Account Preferences, and Sysop Site at 64×22 and 80×24 SSH.
  3. From the Login menu, navigating to Register shows breadcrumb `Foglet › Login › Register`; navigating to Forgot Password shows `Foglet › Login › Forgot Password`; Verify shows `Foglet › Login › Verify`; the new `:reset_consume` sub-state shows `Foglet › Login › Forgot Password › Enter Token`.
  4. Returning from any sub-state to the Login menu pops the segment back to `Foglet › Login`.
**Plans**: TBD
**UI hint**: yes

### Phase 28: Modal.Form Substrate
**Goal**: Modal.Form routes keystrokes to the focused field as a single source of truth, accepts the navigation gestures users expect (Tab/Shift+Tab/`:backtab`/Up/Down/Esc/Enter), and prevents double-submits — unblocking every Account and Sysop edit fix downstream.
**Depends on**: Phase 26 (canvas), Phase 27 (cursor for visual verification)
**Requirements**: FORM-01, FORM-02, FORM-03, FORM-04, FORM-05, FORM-06
**Success Criteria** (what must be TRUE):
  1. In a form with `[text, text, enum]` fields focused on field 1, pressing Down moves focus to field 2 (text); on the enum field, Up/Down still cycles enum values rather than changing focus.
  2. Pressing Shift+Tab and `:backtab` from field 2 both retreat focus to field 1; pressing Tab/Shift+Tab from the boundary fields wraps deterministically (documented direction).
  3. The Modal.Form footer `[Enter] Submit / [Esc] Cancel` is suppressed by default on form-bearing screens that already advertise those keybinds in the global command bar (Account, Sysop); the footer is rendered for true modal overlays that opt in.
  4. Pressing Enter twice in rapid succession on a submittable form invokes the boundary call exactly once (`submit_state` enum gates re-entry); a `:submitting` state is visible during async work.
  5. Pressing `:tab :tab :char "x"` on a `[text, text, text]` form (initial `focus_index: 0`) lands the `"x"` in the third field's buffer, not the first, second, or any default field; widget-internal focus state is asserted absent for form-bearing widgets.
  6. Pressing Esc on a focused form on Account and Sysop Site visibly cancels the active edit context (or shows an honest "draft discarded" affordance) — the command bar's `[Esc] Cancel` hint is no longer a lie; verified at 64×22 and 80×24 SSH.
**Plans**: 7 plans (4 original + 3 gap-closure)
Plans:
- [x] 28-01-PLAN.md — Modal.Form Up/Down focus, `:backtab`, configurable footer, single-source-of-truth tests (FORM-01..04)
- [x] 28-02-PLAN.md — Submit-state machine, input lock, `set_submit_state/2`, status row (FORM-05)
- [x] 28-03-PLAN.md — Honest Esc on Account Profile + Account Preferences (FORM-06)
- [x] 28-04-PLAN.md — Migrate Sysop SiteForm to Modal.Form wrapper, preserve Ctrl+S + validation + visibility (FORM-04, FORM-06)
- [x] 28-05-PLAN.md — BL-01 release Modal.Form lock on `:form` error paths + WR-01 accept `:backtab` on Account guards
- [x] 28-06-PLAN.md — BL-02 persist `submit_state` on `Sysop.SiteForm.State` across re-renders
- [x] 28-07-PLAN.md — BL-03 validate non-empty `:fields` in `Modal.Form.init/1`
**UAT outstanding**: 4 live-SSH spot-checks at 64×22 and 80×24 — see `.planning/phases/28-modal-form-substrate/28-HUMAN-UAT.md` (FORM-06 Esc UX, FORM-03 footer count, BL-01/02 live reproduction)
**UI hint**: yes

### Phase 29: Sysop Tab Lifecycle & Bodies
**Goal**: Sysop tabs auto-load on entry through `Foglet.TUI.Command`, render distinct loading/error/loaded states with a `[R] Retry` keybind on errors, and Sysop Site/Users/Invites surfaces actually function for an operator.
**Depends on**: Phase 26 (table widgets), Phase 28 (Modal.Form patterns)
**Requirements**: SYSOP-01, SYSOP-02, SYSOP-03, SYSOP-04, SYSOP-05, SYSOP-06, SYSOP-07
**Success Criteria** (what must be TRUE):
  1. Navigating to Sysop and switching to Boards/Limits/System/Users via Tab or digit jump dispatches each tab's load command exactly once with no "Press any key to load" gating; the loaded data renders within the tab.
  2. A simulated load failure on Boards, Limits, System, or Users renders an honest error message in place of a blank panel, with `[R] Retry` advertised in the command bar; `{:error, :forbidden}` from a non-sysop actor (test-only) renders a distinct "Insufficient role" panel instead of the loading state.
  3. On Sysop Site, focusing a field and typing echoes the draft value inline (not the saved Config); pressing Enter persists via `Foglet.Config.put/3` with an inline confirmation row; pressing Esc resets the draft to the saved value; the Site field subtitles contain no `REQ-IDs`, `phase` references, or internal planning notes.
  4. On Sysop Users, a user that is already `:approved` does not advertise an `[A] Approve` keybind; attempting any disallowed transition is mapped to user-facing copy ("…cannot be moved from active to pending") rather than the raw atom `:invalid_status_transition`.
  5. On Sysop Invites at 80×24 SSH, focusing a row visibly changes the row highlight; Enter on a focused row reveals contextual row-level actions (e.g. `[X] Revoke`) in the command bar.
  6. The command bar on Account, Moderation, and Sysop tabbed screens consistently advertises a `1-N Jump` group at both 64×22 and 80×24 SSH.
**Plans**: 4 plans
Plans:
- [x] 29-01-PLAN.md — Lifecycle foundation: tagged-enum slots + App load triad + tab-switch dispatch (SYSOP-01, SYSOP-02)
- [x] 29-02-PLAN.md — Retry advertising + USERS keybind gating + valid_status_transitions/1 + from→to error copy (SYSOP-02, SYSOP-05)
- [x] 29-03-PLAN.md — Site Enter/Esc verification + 5 @site_keys description rewrites + schema regex test (SYSOP-03, SYSOP-04)
- [x] 29-04-PLAN.md — INVITES focus highlight + two-step [X] Revoke + 1-N Jump consistency (SYSOP-06, SYSOP-07)
**UI hint**: yes

### Phase 30: Account Workflow
**Goal**: Account Profile changes persist visibly across screen exit/re-entry, Preferences fields are reachable through the right widgets (including a usable IANA timezone selector), redundant headers are gone, and the Account SSH Keys add-flow accepts a multi-line OpenSSH key as a single value.
**Depends on**: Phase 27 (cursor for visual verification), Phase 28 (Modal.Form patterns)
**Requirements**: ACCT-01, ACCT-02, ACCT-03, ACCT-04, ACCT-05
**Success Criteria** (what must be TRUE):
  1. Editing the Account Profile, pressing Enter, leaving Account, and re-entering shows the saved values in the form (verified by an integration test that asserts persistence after re-mount); an inline `[Saved]` row is visible for ~2-3 seconds after submit at 64×22 and 80×24 SSH.
  2. The PROFILE tab body does not begin with a duplicate `Profile` heading; any retained one-line subtitle is intentional and brief.
  3. Each visible Account Preferences field (timezone, time format, theme, toggles) is reachable via Tab/Up/Down and changeable via the appropriate widget (`SelectList`, `RadioGroup`, `Checkbox`); a `:tab :tab :char` test confirms keystrokes land in the focused field, not in a default field.
  4. The Account Preferences timezone field opens a type-ahead `SelectList` backed by `Tzdata.zone_list/0`; typing `lon` narrows the list, Enter commits the selection, and the existing value is visible while editing; the user can clear the field and pick a new zone without typing the full IANA identifier.
  5. On the Account SSH Keys add-flow, pasting a multi-line OpenSSH public key (algorithm + key + optional comment, with embedded `\n`) is accepted as a single field value — the embedded newline does not submit the form; the stored value is normalized to its single-line form; the field shows a truncated/elided preview at 64×22 SSH.
**Plans**: TBD
**UI hint**: yes

### Phase 31: Auth Flow
**Goal**: Forgot Password validates email locally with enumeration-safe success copy, the reset confirmation screen wraps long messages at 64×22 via `TextWidth.wrap`, the `:no_email` delivery mode renders an honest operator-assisted message, and a new `:reset_consume` sub-state lets a user atomically consume a reset token.
**Depends on**: Phase 26 (`TextWidth.wrap` helper), Phase 27 (breadcrumb segment for `:reset_consume`)
**Requirements**: AUTH-01, AUTH-02, AUTH-03, AUTH-04
**Success Criteria** (what must be TRUE):
  1. On Forgot Password, entering an invalid email (no `@`, missing domain) surfaces an inline error beneath the field; entering a valid email — whether or not it exists in the DB — produces identical success copy and identical timing (enumeration-safe).
  2. The reset confirmation screen at 64×22 SSH wraps long messages across multiple rows via `TextWidth.wrap`; resizing from 132×50 to 64×22 mid-flow keeps content accessible (no silent truncation).
  3. With `delivery_mode = :no_email`, the reset confirmation copy honestly names the operator-assisted SSH path and points to the token-consume entry; the token-consume entry is reachable from both the Forgot Password flow and the Login menu.
  4. A user can enter a raw reset token plus new password in the new `:reset_consume` sub-state; on success they are returned to a logged-out menu and the token is single-use (a concurrent-consume test asserts exactly one of two parallel attempts wins, atomically inside `Repo.transact/1`); the token never appears in chrome/breadcrumb/status.
**Plans**: 4 plans
Plans:
**Wave 1**
- [x] 31-01-PLAN.md — Accounts/Verification email reset side effects, sysop contacts, and atomic raw-token consume

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 31-02-PLAN.md — Login Forgot Password menu, email validation, wrapped reset/no-email copy

**Wave 3** *(blocked on Wave 2 completion)*
- [x] 31-03-PLAN.md — Login reset-consume form and Accounts consume submission

**Wave 4** *(blocked on Wave 3 completion)*
- [x] 31-04-PLAN.md — Compact reset rendering and raw-token non-leak validation
**UI hint**: yes

### Phase 32: Main Menu Chrome Polish
**Goal**: Main Menu Navigation and Oneliners panels render their titles embedded in the box top border, route every color through `Foglet.TUI.Theme`, accent the bracketed key glyph, fix indent alignment, and remove the Oneliners top-border glyph artifact.
**Depends on**: Phase 26 (width-math primitive shared with Oneliners glyph artifact)
**Requirements**: MENU-01, MENU-02, MENU-03, MENU-04, MENU-05
**Success Criteria** (what must be TRUE):
  1. Main Menu at 64×22 and 80×24 SSH renders the Navigation and Oneliners panel titles embedded in the top border (`┌─ Navigation ─┐`-style), not as the first row of body content.
  2. The Oneliners panel top border at 64×22, 65, 66, 80, and 81 columns shows no `||||`/repeated-glyph artifact (no off-by-one width math).
  3. Every Main Menu navigation row's bracketed key glyph (`[B]`, `[A]`, etc.) renders in the theme accent slot while the label uses the primary slot; a grep test confirms no hardcoded color literals (`IO.ANSI.*`, raw escapes) appear in `main_menu.ex`.
  4. Navigation rows are indented one column from the box left border; the key column is shifted one column left so row alignment matches the design intent.
  5. Switching to the operator-console theme re-renders both panels with theme-routed colors throughout (no hardcoded atoms); verified by snapshot test against both themes.
**Plans**: 3 plans
Plans:
- [x] 32-01-render-shape-PLAN.md — :panel-typed Navigation/Oneliners with embedded titles, multi-node nav rows (primary label + accent [X] key), one-column inner indent, theme-only colors
- [x] 32-02-oneliners-artifact-PLAN.md — Verify Oneliners top-border at widths 64/65/66/80/81; investigate root cause and apply minimal fix if artifact persists
- [x] 32-03-test-updates-PLAN.md — Update layout_smoke_test.exs and main_menu_test.exs assertions to match the new render shape; precommit gate

**UI hint**: yes

### Phase 33: Composer Wrap & Boards Interaction
**Goal**: The post composer soft-wraps lines that exceed the editor's column width via `TextWidth.wrap` (logical buffer unchanged on resize), and pressing Enter on a focused Boards-screen category toggles its expanded state with a visible indicator.
**Depends on**: Phase 26 (`TextWidth.wrap` helper), Phase 27 (cursor verification)
**Requirements**: POST-02, BOARD-01
**Success Criteria** (what must be TRUE):
  1. In the post composer (new-thread and reply), typing a line that exceeds the editor's column width visually wraps onto the next visual line; the submitted post text retains the logical (un-wrapped) content with no inserted `\n`.
  2. Resizing the terminal from 80×24 to 64×22 mid-compose re-flows the visual wrap without altering the underlying buffer; cursor navigation respects logical lines (verified at both sizes via SSH observation).
  3. On the Boards screen at 64×22 SSH, focusing a category and pressing Enter toggles its expanded state (collapsed → expanded → collapsed); the visible state indicator (`▸` collapsed, `▾` expanded, or equivalent) updates accordingly.
  4. Enter on a focused board leaf continues to navigate to the thread list (no regression of existing behavior); a sandbox query log confirms expand/collapse causes zero DB writes (UI-local state only).
**Plans**: 3 plans
Plans:
**Wave 1**
- [x] 33-01-composer-shared-wrap-PLAN.md — Shared `Compose.render_input/4` visual wrapping via `TextWidth.wrap/2`, cursor preservation, and shared renderer tests
- [x] 33-03-boards-enter-toggle-PLAN.md — Boards category Enter toggles local `BoardTree` expansion state, updates `▸`/`▾`, and preserves board-leaf navigation

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 33-02-composer-screen-coverage-PLAN.md — Reply and new-thread composers pass current render width, with compact/resize/submit preservation coverage

Cross-cutting constraints:
- Composer wrapping is render-only: `MultiLineInput.value` remains the logical submitted buffer, and `MultiLineInput` stays initialized with `wrap: :none`.
- Boards category expansion is UI-local only: no domain context calls, DB writes, subscribe/unsubscribe commands, or thread-loading commands for category Enter.
**UI hint**: yes

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 0-8 | v1.1 | 43/43 | Complete | 2026-04-24 |
| 9-15 | v1.2 | 26/26 | Complete | 2026-04-24 |
| 16-25 | v1.3 | 48/48 | Complete | 2026-04-26 |
| 26 | v1.4 | 1/4 | In Progress | - |
| 27 | v1.4 | 0/0 | Not started | - |
| 28 | v1.4 | 0/4 | Not started | - |
| 29 | v1.4 | 0/0 | Not started | - |
| 30 | v1.4 | 0/0 | Not started | - |
| 31 | v1.4 | 0/0 | Not started | - |
| 32 | v1.4 | 0/0 | Not started | - |
| 33 | v1.4 | 0/0 | Not started | - |
