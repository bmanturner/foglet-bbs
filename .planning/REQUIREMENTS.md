# Requirements: Foglet BBS — v1.4 Post-Facelift Polish & Bug Fixes

**Defined:** 2026-04-26
**Core Value:** A user can SSH into a living, reliable BBS and participate in conversations through a terminal-native experience that feels like arriving somewhere.
**Source of truth:** `ISSUES.md` filed during human SSH/TUI verification of v1.3.

## v1.4 Requirements

Requirements for the v1.4 stabilization milestone. Every requirement traces to one or more ISSUES.md items. Each maps to exactly one roadmap phase.

### Layout & Width Foundations

- [ ] **LAYOUT-01**: The Tabs widget renders no trailing border-glyph artifacts to the right of the rightmost tab on any tabbed screen, at every supported terminal width (Globally #1).
- [ ] **LAYOUT-02**: Moderation LOG, USERS, and BOARDS tabs render fully within the user's terminal at the 64×22 minimum, scrolling or paginating within the content region instead of overflowing above the top edge (Moderation #1).
- [ ] **LAYOUT-03**: The Boards screen renders fully within the user's terminal at the 64×22 minimum, with the categories+boards content scrolled inside the list region rather than overflowing the screen frame (Boards #1).
- [ ] **LAYOUT-04**: The Sysop INVITES table allocates proportional, separated columns (Code, Status, Created, Used by) using `Display.Table` auto-width semantics so columns are visibly distinct at every supported terminal width (Sysop #12).
- [ ] **LAYOUT-05**: The Moderation LOG table is responsive — it consumes available width up to the terminal limit, elides long messages with `…` rather than truncating mid-word, and renders timestamps in the user's preferred timezone (Moderation #2).
- [ ] **LAYOUT-06**: A reusable width-aware word-wrap helper exists in `Foglet.TUI.TextWidth` (or equivalent) and is grapheme-cluster-aware, supporting downstream consumers in composer wrap and reset-message wrap.

### Cursor & Breadcrumb Polish

- [ ] **CURSOR-01**: The TextInput widget renders a cursor that follows the active insertion point (advances on keystroke, retreats on backspace) on every focused single-line input across Login, Register, Forgot Password, Verify, Account, and Sysop screens (Login #1).
- [ ] **BREAD-01**: The shared chrome breadcrumb updates correctly when the Login screen forks into Register, Forgot Password, Verify, and the new no-email reset-consume sub-state, returning to the parent segment when the user navigates back (Login #3).

### Form Interaction (Modal.Form Substrate)

- [ ] **FORM-01**: Modal.Form supports Up/Down inter-field focus movement on text fields (preserving enum-cycling behavior on `:enum` fields), so users can reach every field in Account Preferences and Sysop Site without exclusively relying on Tab (Account #4, Account #8).
- [ ] **FORM-02**: Modal.Form accepts `:backtab` as an equivalent of Shift+Tab, matching the SiteForm convention, so Shift+Tab moves focus to the previous field on every form-bearing screen (Account #5).
- [ ] **FORM-03**: Modal.Form's bottom-rendered `[Enter] Submit / [Esc] Cancel` footer is configurable — disabled by default for screens that already advertise the same keybinds in the global command bar — eliminating duplicate footer copy on Account, Sysop, and similar surfaces (Account #7).
- [ ] **FORM-04**: Modal.Form keystrokes are routed only to the focused field; switching focus updates the destination of the next keystroke deterministically, with focus owned by a single source of truth (the parent screen's `focused_field`), so typing never lands in a stale field (Account #8).
- [ ] **FORM-05**: Modal.Form maintains an explicit `submit_state :: :idle | :submitting | :saved | {:error, term}`; only the `:idle` state accepts Enter, so accidental double-Enter or Enter-during-redraw cannot resubmit the form (cross-cutting `PITFALLS.md` F3).
- [ ] **FORM-06**: Esc keybind handlers honor advertised behavior — they cancel the active edit context (or visibly discard the draft) — so the command bar's `[Esc] Cancel` hint is not a lie on Account or Sysop Site (Account #1, Sysop #5).

### Sysop Tab Lifecycle & Bodies

- [ ] **SYSOP-01**: Sysop tabs (Site, Boards, Limits, System, Users, Invites) load their data on tab switch via `Foglet.TUI.Command`, removing the "Press any key to load" gating so tabs render data immediately on entry or show an honest loading/error state (Sysop #1).
- [ ] **SYSOP-02**: Sysop submodule loads (`BoardsView`, `LimitsForm`, `SystemSnapshot`, `UsersView`) survive failure scenarios with a tagged `:not_loaded | :loading | {:loaded, data} | {:error, reason}` state and render an honest error message with a `[R] Retry` keybind in place of the placeholder (Sysop #6, #7, #8, #9).
- [ ] **SYSOP-03**: The Sysop Site tab is editable: each field accepts user input via Modal.Form, draft values are visibly echoed inline (not the saved Config value), Enter submits via `Foglet.Config.put/3` with inline confirmation, and Escape resets drafts to saved values (Sysop #3, Sysop #5).
- [ ] **SYSOP-04**: Sysop Site field subtitles use user-facing operator copy with no internal planning notes, REQ-IDs, or phase-deliverable language exposed (Sysop #4).
- [ ] **SYSOP-05**: The Sysop Users tab gates its keybinds to the user's current status so disallowed transitions (e.g. approving an already-approved user) cannot be initiated, and any `{:error, :invalid_status_transition}` from `Foglet.Accounts` is mapped to user-facing copy rather than the raw atom (Sysop #10, #11).
- [ ] **SYSOP-06**: The Sysop Invites tab supports row-level focus movement and Enter on a row reveals the contextual row-level actions (e.g. Revoke), making existing invite codes selectable (Sysop #13).
- [ ] **SYSOP-07**: All tabbed screens (Account, Moderation, Sysop) advertise consistent tab navigation hints in the command bar, including a `1-N Jump` group where digit jump is supported (Sysop #2).

### Account Workflow

- [ ] **ACCT-01**: Account Profile submit persists changes — leaving the Account screen and returning shows the saved values, with an inline `[Saved]` flash row visible for ~2-3 seconds after submit (Account #3).
- [ ] **ACCT-02**: Account tab content does not duplicate the active tab title (e.g. no `Profile` heading inside the PROFILE tab body), reducing redundant text while keeping any helpful one-line subtitles (Account #2).
- [ ] **ACCT-03**: Account Preferences fields (timezone, time format, theme, toggles) are reachable and selectable via the appropriate widget (`SelectList`, `RadioGroup`, `Checkbox`) so every visible preference can be changed (Account #4).
- [ ] **ACCT-04**: Account Preferences exposes an IANA timezone selector backed by `Tzdata.zone_list/0` with type-ahead narrowing, allowing the user to clear, replace, or pick a timezone without typing the full identifier; the current value is visible while editing (Account #6).
- [ ] **ACCT-05**: Account SSH Keys add-flow accepts a multi-line OpenSSH public key as a single value — the embedded newline does not prematurely submit the form, the key is normalized to its single-line form, and the field shows a truncated/elided preview (Account #9).

### Auth Flow

- [ ] **AUTH-01**: The Login Forgot Password flow validates email format locally before dispatching the reset request; invalid input surfaces an inline error beneath the field; the success state is enumeration-safe (identical copy and timing whether or not the email exists) (Login #2).
- [ ] **AUTH-02**: The Login reset confirmation screen wraps long messages using the `Foglet.TUI.TextWidth` wrap helper so the message fits at the 64×22 minimum terminal without cropping, rendering across multiple rows when needed (Login #4).
- [ ] **AUTH-03**: When `delivery_mode = :no_email`, the reset flow renders an honest message naming the operator-assisted SSH path and provides a discoverable token-consume entry point reachable from both the Forgot Password flow and the Login menu (Login #4).
- [ ] **AUTH-04**: A `Foglet.Accounts` boundary supports verifying and consuming a raw password reset token atomically inside `Repo.transact/1` (single-use, with concurrent consume tested), powering a new `:reset_consume` sub-state that accepts a token plus new password and returns the user to a logged-out menu on success (Login #4).

### Main Menu Chrome Polish

- [ ] **MENU-01**: Main Menu Navigation and Oneliners panels render their titles embedded in the box top border (e.g. `┌─ Navigation ─┐`) rather than as the first row of body content (Main Menu #1).
- [ ] **MENU-02**: The Oneliners panel renders no `||||` or repeated-glyph artifacts on its top border at any supported terminal width (Main Menu #2).
- [ ] **MENU-03**: Main Menu navigation rows render the bracketed key glyph (`[B]`, `[A]`, etc.) in the theme accent slot while the label remains in the primary slot, with no hardcoded colors (Main Menu #4).
- [ ] **MENU-04**: Main Menu navigation rows are indented one column from the box left border, with the key column shifted left by one column so the row alignment matches the design intent (Main Menu #5).
- [ ] **MENU-05**: Both Navigation and Oneliners panels route every color decision through `Foglet.TUI.Theme` slots — no hardcoded color atoms anywhere in `main_menu.ex` (Main Menu #6, Main Menu #7).

### Post Rendering & Composer

- [ ] **POST-01**: The shared markdown renderer preserves paragraph breaks — two consecutive newlines render as one blank visible line, soft breaks render as line breaks, and three or more consecutive newlines clamp to one blank line — so post bodies are readable rather than cramped (Globally #2).
- [ ] **POST-02**: The post composer (new-thread and reply) soft-wraps lines that exceed the editor's column width using the `TextWidth` wrap helper; submitted post text retains logical (un-wrapped) content; a terminal resize re-flows the visual wrap without altering the underlying buffer (Globally #3).

### Boards Screen Interaction

- [ ] **BOARD-01**: Pressing Enter on a focused Boards-screen category toggles its expanded state (collapsed → expanded → collapsed), with a visible state indicator (`▸` / `▾` or equivalent), while Enter on a focused board leaf continues to navigate to the thread list (Boards #2).

## Future Requirements

Deferred from v1.4 — captured for visibility, not in this milestone's scope.

### Differentiators surfaced by research (defer)

- **ACCT-FUT-01**: Operator-side reveal of the most-recent unconsumed reset token in Sysop › Users.
- **BOARD-FUT-01**: Per-user persisted Boards expand/collapse state across sessions.
- **SYSOP-FUT-01**: Background prefetch of next/previous Sysop tab so tab-switching feels instant.
- **AUTH-FUT-01**: Drag-paste detection for SSH clients without bracketed-paste support (rapid stream + newline → treat as paste).
- **POST-FUT-01**: Hard-wrap-on-submit option in the composer (insert real newlines at column 80).
- **POST-FUT-02**: Sysop config flag `markdown_soft_break_as_space` for tight rendering.

### Carried forward from v1.3 close (still deferred)

- **UAT-FUT-01**: Phase 18 Chrome V2 human terminal scenarios — partially addressed by v1.4 LAYOUT/CURSOR/BREAD work; remaining items will be re-evaluated at v1.4 close.
- **UAT-FUT-02**: Phase 19 Main Menu human terminal scenarios — addressed by v1.4 MENU-* work; remaining items will be re-evaluated at v1.4 close.

### Dormant seeds (do not pull in)

- **SEED-001**: User notifications over webhook (triggers on Phase 10 / email-notification milestone).
- **SEED-002**: Email verification UX (resend + configurable requirement) (triggers on Phase 10 / email-notification milestone).

## Out of Scope

Explicitly excluded from v1.4. Documented to prevent scope creep — see `FEATURES.md` §"Anti-Features Summary" and `PITFALLS.md` for full rationale.

| Feature | Reason |
|---------|--------|
| New product features | v1.4 is a stabilization milestone — close v1.3 facelift debt before adding reach features |
| Browser-based password reset | PROJECT.md key decision: keep reset recovery browser-free for v1.x; SSH/operator path is honest and testable |
| Web UI for any v1.4 surface | Foglet is SSH-first; the Phoenix endpoint is operational infrastructure only |
| Auto-save on field-blur | Conservative stabilization milestone preserves explicit Submit contract |
| Modal "Saved!" dialogs | Inline confirmation respects keyboard-first BBS convention |
| Horizontal scrolling on tables | Terminal table convention is column-resize, not horizontal scroll |
| Toast/dismissable notifications | Persistent inline error/status text fits TUI conventions |
| Hardcoded color literals | All rendering routes through `Foglet.TUI.Theme` slots per v1.3 D-07 / D-09 |
| Widget-internal focus state | Focus state lives in the screen or sibling state module per AGENTS.md |
| New authorization scope shapes | `:site` and `{:board, board_id}` remain the only stable scopes |
| Forking the vendored Raxol fork | Bracketed paste lives in `Foglet.SSH.CLIHandler` — owns SSH lifecycle |
| Hard-wrap inserts on every keystroke | Composer ships logical lines; visual wrap is a render concern only |
| Per-character animation/easing | Wastes redraw budget over SSH |
| Auto-refresh on a timer | Hard to test deterministically; pulls weight without consent |
| Vim/emacs alternative keybind sets | Tab/Shift+Tab/Enter/Esc match existing v1.x conventions; no parallel scheme in this milestone |

## Resolved Pre-Milestone (struck from scope)

These two ISSUES.md items were resolved between filing and milestone start (per `PROJECT.md` Current Milestone "Already resolved" subsection) and are explicitly excluded from this milestone:

| ISSUES.md item | Status |
|---|---|
| Boards Screen #3 — selecting a board freezes the screen | Resolved before milestone start |
| Main Menu Screen #3 — Up/Down arrows inert on navigation | Resolved before milestone start |

## Traceability

Which phases cover which requirements. Filled by the roadmapper.

| Requirement | Phase | Status |
|-------------|-------|--------|
| LAYOUT-01 | Phase 26 | Pending |
| LAYOUT-02 | Phase 26 | Pending |
| LAYOUT-03 | Phase 26 | Pending |
| LAYOUT-04 | Phase 26 | Pending |
| LAYOUT-05 | Phase 26 | Pending |
| LAYOUT-06 | Phase 26 | Pending |
| POST-01 | Phase 26 | Pending |
| CURSOR-01 | Phase 27 | Pending |
| BREAD-01 | Phase 27 | Pending |
| FORM-01 | Phase 28 | Pending |
| FORM-02 | Phase 28 | Pending |
| FORM-03 | Phase 28 | Pending |
| FORM-04 | Phase 28 | Pending |
| FORM-05 | Phase 28 | Pending |
| FORM-06 | Phase 28 | Pending |
| SYSOP-01 | Phase 29 | Pending |
| SYSOP-02 | Phase 29 | Pending |
| SYSOP-03 | Phase 29 | Pending |
| SYSOP-04 | Phase 29 | Pending |
| SYSOP-05 | Phase 29 | Pending |
| SYSOP-06 | Phase 29 | Pending |
| SYSOP-07 | Phase 29 | Pending |
| ACCT-01 | Phase 30 | Pending |
| ACCT-02 | Phase 30 | Pending |
| ACCT-03 | Phase 30 | Pending |
| ACCT-04 | Phase 30 | Pending |
| ACCT-05 | Phase 30 | Pending |
| AUTH-01 | Phase 31 | Pending |
| AUTH-02 | Phase 31 | Pending |
| AUTH-03 | Phase 31 | Pending |
| AUTH-04 | Phase 31 | Pending |
| MENU-01 | Phase 32 | Pending |
| MENU-02 | Phase 32 | Pending |
| MENU-03 | Phase 32 | Pending |
| MENU-04 | Phase 32 | Pending |
| MENU-05 | Phase 32 | Pending |
| POST-02 | Phase 33 | Pending |
| BOARD-01 | Phase 33 | Pending |

**Coverage:**
- v1.4 requirements: 38 total (corrected from initial 32 estimate; the actual REQ-ID list contains 38 distinct items: LAYOUT 6 + CURSOR 1 + BREAD 1 + FORM 6 + SYSOP 7 + ACCT 5 + AUTH 4 + MENU 5 + POST 2 + BOARD 1)
- Mapped to phases: 38
- Unmapped: 0 ✓

---
*Requirements defined: 2026-04-26 — derived from ISSUES.md and v1.4 research synthesis*
*Last updated: 2026-04-26 — Traceability table populated by roadmapper at milestone-roadmap creation*
