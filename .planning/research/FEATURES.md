# v1.4 Post-Facelift Polish & Bug Fixes — Feature Research

**Domain:** Terminal UI polish/bugfix milestone (SSH-first BBS, Raxol/Elixir, brownfield)
**Researched:** 2026-04-26
**Confidence:** HIGH (existing widget catalog confirms most capabilities are present; bugs are integration/wiring, not missing primitives)

The v1.4 work is *closing* the v1.3 facelift, not adding features. The "features" below are the **expected user-facing behaviors** of polish primitives. For each ISSUES.md cluster I'm calling out: what users expect (table stakes), what would be a quality differentiator, what's an anti-feature trap to avoid, what fix has to land first (dependencies), and concrete "good-looks-like" criteria the requirements step can convert into REQ-IDs.

---

## Polish Categories (one per ISSUES.md cluster)

### CAT-AUTH-CURSOR — Text-input cursor follows the typed character (Login #1)

**Table Stakes**
- Cursor is positioned **at the next-insert column**, not parked at field-start.
- When characters are typed, the cursor **advances with each keystroke**; on backspace it retreats.
- Cursor is visible (a reverse-video block on the next column, an underline under the next column, or a vertical bar between the previous and next column) — pick **one** treatment and apply it consistently across every TextInput on Login, Register, Forgot, Account, Sysop.
- Cursor is hidden on disabled / unfocused fields (no "ghost" cursors on fields that aren't capturing input).

**Differentiators**
- Distinct cursor styling for masked password fields (e.g. cursor still visible despite `*****` mask).
- Subtle blink for active focus (terminals support DECTCEM and DECSCUSR — but blinking can be jarring; a static reverse-block is the safer default).

**Anti-Features**
- A static "[ ]" or "│" marker that always sits at column zero regardless of input length — this is what users are reporting as "doesn't behave like a cursor."
- Per-character animation/easing — wastes redraw budget over SSH.

**Dependencies**
- None upstream. **Many downstream fixes depend on this** (see CAT-FORM-FOCUS, CAT-ACCOUNT-PROFILE) — without a real cursor, any field that gains focus will look broken.

**Notes / "Good" Definition**
Cursor column equals current `caret_index` over the field's visible buffer. The widget already exists (`Foglet.TUI.Widgets.Input.TextInput`); this is a render-pass fix, not a new component. Apply uniformly so users learn it once.

---

### CAT-AUTH-VALIDATION — Forgot-password / form validation (Login #2)

**Table Stakes**
- Email field requires non-empty value and rejects malformed input (no `@`, no domain) **before** firing the reset request.
- Errors render **inline beneath the field** (not as a global "Error" banner) and on submit, not on every keystroke (don't shame users mid-typing).
- The Forgot-password flow ends in a **definite success state** every time, even when the user enters an unknown email. (Username-enumeration safety — see Differentiators.)
- Submit button is disabled or visually de-emphasized while validation has not passed; Enter on the form should run validation, not silently consume the keypress.

**Differentiators**
- **Enumeration safety**: identical message and identical timing whether or not the email exists in the DB. OWASP/IdentityServer guidance says: same screen text, same response time, same control flow — so a SOC observer can't distinguish "valid email" from "unknown email." The Foglet `delivery_mode = :no_email` path makes this easier (no email to send means timing is naturally constant) but the success/failure UI must still look identical.
- Rate-limit reset attempts per remote address to stop enumeration brute-forcing.

**Anti-Features**
- Returning "no account exists with that email" — leaks user enumeration.
- Toast-style dismissable notifications — fight terminal UI conventions; prefer persistent inline error text.
- Validating on every keystroke and showing red errors before submit — feels hostile.

**Dependencies**
- Depends on **CAT-AUTH-NO-EMAIL** for the no-email branch (the success message must still render, even when no email was sent).
- Depends on **CAT-AUTH-RESET-RENDER** so the success message doesn't get truncated at 64×22.

---

### CAT-AUTH-BREADCRUMBS — Breadcrumbs update on Register / Forgot Password (Login #3)

**Table Stakes**
- Breadcrumb on Login: `Login`. On Register: `Login › Register`. On Forgot: `Login › Forgot Password`. On Verify: `Login › Verify`.
- Breadcrumb is rendered by **shared chrome** (already shipped Phase 18); this is a screen-side metadata fix where each sub-screen declares its breadcrumb segment.
- Returning to Login pops the segment.

**Differentiators**
- Breadcrumb is keyboard-actionable (e.g. clicking a parent segment with arrow keys returns to it). **Defer** this — it's not required for the v1.4 milestone and risks scope creep.

**Anti-Features**
- Per-screen ad-hoc title bars that bypass the shared chrome — makes the milestone harder to test and breaks the Phase 18 contract.

**Dependencies**
- None — purely a screen/chrome wiring fix.

**Notes**
Phase 18 already shipped breadcrumb-style titles. The bug is the modal sub-flows don't push their segment.

---

### CAT-AUTH-RESET-RENDER — Reset email message rendering at small terminals (Login #4)

**Table Stakes**
- The reset confirmation screen fits 64×22 (project's minimum). No content is hidden below the fold.
- Long token strings wrap or are presented in a copyable block (not in a sentence).
- After delivery success, the user has a clearly labelled next step: "Press [R] to enter your reset token" or similar — no dead-end screens.

**Differentiators**
- A "copy this token" hint that respects terminal copy/paste conventions (single contiguous line on its own row).

**Anti-Features**
- Multi-paragraph prose explaining what a reset email is. The screen is a confirmation, not a tutorial.

**Dependencies**
- Depends on **CAT-AUTH-NO-EMAIL** to define what message renders in `:no_email` mode.
- Sits alongside **CAT-MARKDOWN-NEWLINES** (newline handling on this screen specifically, but the global markdown fix solves it once).

---

### CAT-AUTH-NO-EMAIL — No-email password reset path with token-consume entry point (Login #4 cont'd)

**Table Stakes**
- When `delivery_mode = :no_email`, the reset confirmation screen tells the user honestly: "Email delivery is disabled on this BBS. Ask the sysop for your reset token, then press [R] to enter it."
- A **token-entry screen** exists that accepts a raw token + new password and consumes it via `Foglet.Accounts` reset-token API.
- That token-entry screen is reachable from the Forgot Password flow **and** from Login (so a user who pre-navigated away can still resume).
- Sysops can read the token via existing operator tooling (Mix task or Sysop screen) — no new operator UI in this milestone.

**Differentiators**
- Operator-side: surface the most-recent unconsumed reset token for a user inside Sysop › Users (already have user-status admin from v1.2 Phase 10). **Defer** unless trivially cheap — risks expanding scope.

**Anti-Features**
- Auto-resetting the password without a token (just because `:no_email` is set). Breaks security model.
- Showing the token to the user on-screen at request time. The reset token must remain a server-generated secret retrieved through an out-of-band channel; in `:no_email` that channel is "ask the sysop."

**Dependencies**
- Depends on **CAT-AUTH-VALIDATION** (email field validates first).
- Depends on **CAT-AUTH-RESET-RENDER** (rendering room for the longer no-email message).
- The PROJECT.md key decision already records: "Keep reset recovery browser-free for v1.2; operator-assisted SSH reset with raw tokens is honest and testable." This milestone makes that decision real.

---

### CAT-MAINMENU-CHROME — Box-title-on-border + theme application + indents + Oneliners glyph artifact (Main Menu #1, #2, #4–#7)

**Table Stakes**
- Panel titles ("Navigation", "Oneliners") render **on the top border** of their box, between two border glyphs (e.g. `┌─ Navigation ─┐` or `┤ Oneliners ├`), not as the first row of content inside the box.
- The Oneliners box top border has **no repeating `|||...` artifact** — that's almost certainly a width-math bug where a fill character is being multiplied by a wrong cell-count rather than padding to remaining width.
- Navigation items are **indented one column** from the box's left border; navigation key glyphs (`[B]`, `[A]`, etc.) are shifted one column **left** so the key column lines up with the border edge.
- Both Navigation and Oneliners panels honor the active theme — accents, foreground, dim, border colors all route through `Foglet.TUI.Theme` (D-07, D-09 in widget README).
- Navigation **keys** (the bracketed letter) render in the accent slot, not the body slot.

**Differentiators**
- Ascender/descender alignment of the title text within the border so it doesn't visually clip on terminals with unusual line-height (purely cosmetic).

**Anti-Features**
- Hardcoded color atoms (`:cyan`, `:yellow`) — directly violates D-07/D-09 routing through Theme.
- A separate "title" widget for each panel — duplicates the existing chrome convention.

**Dependencies**
- The **Oneliners glyph artifact (#2)** is most likely the same root cause as **CAT-GLOBAL-TAB-GLYPHS** (trailing border glyphs to the right of the rightmost tab) — both look like "fill char × N where N is computed wrong." Fix the underlying width-math primitive once, then both clear up.
- All five Main Menu items (#1, #4, #5, #6, #7) are pure render polish; they don't block each other but they share a theme contract — fix the theme routing once, ship all five together.

---

### CAT-MAINMENU-ARROWS — Up/Down arrow-key behavior (Main Menu #3) — RESOLVED

**Status:** Already resolved between ISSUES.md filing and milestone start. Confirmed in PROJECT.md Current Milestone "Already resolved between ISSUES.md filing and milestone start" subsection. Listed only so it doesn't get re-spec'd from ISSUES.md.

---

### CAT-ACCOUNT-PROFILE-PERSIST — Profile submit feedback + values persist (Account #1, #3)

**Table Stakes**
- Esc on a form returns the user to Account tab navigation (closes the modal/edit context); the command bar's "Esc Cancel" hint must be honest.
- Enter on the form submits, runs validation, calls into `Foglet.Accounts` context, and on success shows **inline confirmation** — e.g. flash row "Profile saved." that persists for 2–3 seconds.
- After save, leaving and re-entering the Account screen shows the **persisted values**, not the originals — i.e. the changeset actually committed and the screen re-fetches from `Foglet.Accounts` on mount.

**Differentiators**
- Optimistic UI that updates the on-screen field immediately and reconciles on persistence completion — **defer**, conservative for a stabilization milestone.

**Anti-Features**
- A modal "Saved!" dialog the user has to dismiss with another keystroke. Inline confirmation respects keyboard-first flow.
- Auto-save on field-blur. v1.4 is a stabilization pass, not a redesign; keep the explicit Submit contract.

**Dependencies**
- Depends on **CAT-FORM-FOCUS** (Tab/Shift+Tab navigation) and **CAT-FORM-KEYBINDS** (Esc/Enter wiring).
- Depends on **CAT-AUTH-CURSOR** (so each field's edit state visibly tracks the cursor).

---

### CAT-ACCOUNT-REDUNDANT-HEADERS — Tab content doesn't repeat tab name (Account #2, Account #7)

**Table Stakes**
- When the active tab is "PROFILE", the content area does **not** also start with a `Profile` heading — the tab strip already establishes context.
- The form footer does not duplicate keybinds that the global command bar already shows. If the command bar shows `[Enter] Submit  [Esc] Cancel`, the form should not re-render those.

**Differentiators**
- A subtle visual marker (a divider, or a one-line tagline like "Edit your profile") can replace the redundant heading without re-introducing duplication.

**Anti-Features**
- Stripping all in-content context — users still benefit from a one-line subtitle when the form is long.

**Dependencies**
- Pure copy/render fix. No upstream dependency.

---

### CAT-ACCOUNT-PREFERENCES-OPTIONS — Preferences fields are selectable / interactive (Account #4)

**Table Stakes**
- Every visible Preferences field is reachable by Tab and editable (text input, toggle, radio, or selector — pick the right widget per field type).
- 12h/24h time format is a `RadioGroup`. Theme is a `RadioGroup` or `Menu`. Timezone is the timezone-selector (CAT-ACCOUNT-TIMEZONE). Toggles use `Checkbox`.
- All widgets already exist in `lib/foglet_bbs/tui/widgets/input/` — this is wiring, not new components.

**Differentiators**
- Preview-on-hover (e.g. when 24h is selected the chrome clock immediately re-renders in 24h) — already largely shipped via Phase 6's preference-aware chrome refresh; verify it still works after this fix.

**Anti-Features**
- A "Save" footer that's separate from the global Submit/Cancel — adds a third location for the same keybinds.

**Dependencies**
- Depends on **CAT-FORM-FOCUS** so Shift+Tab works.
- Blocks **CAT-ACCOUNT-PROFILE-PERSIST** retrospective check (preferences are part of the same flow).

---

### CAT-FORM-FOCUS — Tab forward, Shift+Tab back, Esc cancel, Enter submit (Account #5, Account #8)

**Table Stakes**
- Tab moves to the next focusable field; Shift+Tab moves to the previous field. Wraps at the last field (Tab from last → first, Shift+Tab from first → last) — this is the convention.
- Keystrokes are routed to **the focused field only**. If the user typed in field A and then tabbed/clicked into field B, subsequent characters go to B, not A. The Account #8 bug ("type anything, the timezone field is selected and the typed character appears there") is exactly this: keystrokes are short-circuiting to a default field instead of following focus.
- Esc cancels the current edit context (form, tab, modal — whichever is innermost). Enter submits the innermost form when the focused widget doesn't itself consume Enter.

**Differentiators**
- Type-ahead within a select widget (e.g. typing "ame" jumps to "America/..." in a timezone selector) — needed for **CAT-ACCOUNT-TIMEZONE**.
- Visible focus ring on the active field (theme accent border or label highlight) — table stakes-adjacent; ship it.

**Anti-Features**
- Trapping focus inside a sub-widget so Tab does nothing — accessibility regression and blocks every other form fix.
- Global Tab handlers that fight per-field handlers — rule of thumb: if a focused widget does **not** explicitly consume Tab, the screen routes Tab to focus-next.

**Dependencies**
- **Blocks** every Account-tab and Sysop-tab fix. This is the **single highest-leverage fix in the milestone**.
- Depends on screen-state ownership: per AGENTS.md, focus state lives in the screen (or sibling `state.ex`), not in the widget. Verify before fixing — adding focus state into the widget would violate the widget contract.

---

### CAT-ACCOUNT-TIMEZONE — IANA timezone selector (Account #6)

**Table Stakes**
- Users can **clear** the timezone (set to nil/UTC default) — currently impossible per ISSUES.md.
- Users can **replace** the timezone without typing a full IANA string from memory.
- The selector displays a list of IANA zones (`Europe/London`, `America/New_York`, `Asia/Tokyo`, ...) sourced from the tzdata library bundled with the Elixir release.
- Type-ahead narrowing: typing "lon" filters to zones containing "lon".
- Enter on a filtered row commits the selection.

**Differentiators**
- Sort by likely-relevance: city-grouped, then alphabetical. Smart Interface Design Patterns recommends placing the user's likely zone (browser-detected, or last-used) at the top. For SSH the equivalent heuristic is "last-saved zone" or fall back to `Etc/UTC`.
- A "(Current: Europe/London)" indicator next to the input so the user sees the existing value while editing.

**Anti-Features**
- A single freeform text field where the user types the full IANA identifier with no completion — that's the current state and exactly what's filed.
- A pre-rendered list of 600+ zones with no filter — unusable in 64×22.
- Showing UTC offsets in the list as the primary key — IANA zones change historically; always show the IANA name, optionally annotated with offset.

**Dependencies**
- Depends on **CAT-FORM-FOCUS** (selector needs Tab/Shift+Tab).
- Depends on **CAT-FORM-KEYBINDS** (Enter commits selection).
- Existing `Display.Tree` and `Input.Menu` widgets are candidates; a thin filter wrapper over `List.SmartList` (which already supports search) is likely the cheapest path.

---

### CAT-ACCOUNT-SSHKEYS-PASTE — SSH-pubkey paste over an SSH session (Account #9)

**Table Stakes**
- On the Add SSH Key screen, the user can paste a multi-line SSH public key (`ssh-ed25519 AAAA... user@host\n` + sometimes a trailing comment line) and the input accepts it as a single value.
- The input recognizes **bracketed paste mode** (`ESC [ 200 ~` ... `ESC [ 201 ~`) and treats the bracketed payload as a single paste event, not as a stream of keystrokes that includes Enter (which would prematurely submit).
- Newline characters inside a bracketed paste are absorbed (replaced with space, or the leading/trailing whitespace is stripped) so the key is normalized to the single-line form `algorithm key comment`.
- After paste, the field shows the key in a truncated/elided form (first 16 chars + ellipsis + last 8 chars) so it fits the column.

**Differentiators**
- Drag-paste detection: even if the terminal does **not** support bracketed paste, detect "many characters arriving within a few ms with a newline" as a paste rather than typing, and apply the same normalization. This protects users on older clients.
- Key validation: parse the pasted blob through `:public_key.ssh_decode/2` (Erlang stdlib) before persisting; reject with an inline error if the format is bad.

**Anti-Features**
- Letting the embedded `\n` in the pasted key fire the form's Submit handler. Enter inside a bracketed-paste payload must be inert.
- Asking users to base64-decode the key themselves or paste it across multiple fields.
- Truncating silently on paste so users can't tell whether the whole key landed.

**Dependencies**
- Depends on the SSH channel forwarding bracketed-paste sequences correctly. Per AGENTS.md, `Foglet.SSH.CLIHandler` owns input forwarding — verify it doesn't strip CSI sequences before they reach Raxol. This is the only ISSUES.md item that crosses the SSH↔TUI boundary; budget for SSH-side investigation.
- Depends on **CAT-FORM-FOCUS** (paste lands in the focused field).

---

### CAT-FORM-KEYBINDS — Esc/Enter actually do what the command bar advertises (Account #1, Sysop #5)

**Table Stakes**
- If the command bar says `[Esc] Cancel`, Esc must close the form/modal.
- If it says `[Enter] Submit`, Enter on the form must validate and submit.
- The command bar is the **contract** — never let it advertise a keybind that isn't wired.

**Anti-Features**
- "Sometimes Enter submits, sometimes it inserts a newline" inconsistency — pick one per widget. Single-line TextInput: Enter submits the form. Multi-line composer: Enter inserts newline; Ctrl+Enter or `:wq`-style command submits.

**Dependencies**
- Companion to **CAT-FORM-FOCUS** — same root cause (event routing).
- Blocks **CAT-ACCOUNT-PROFILE-PERSIST** and most Sysop edit work.

---

### CAT-SYSOP-LOAD-ON-MOUNT — Load tab content on mount, not on "press any key" (Sysop #1)

**Table Stakes**
- When a Sysop tab gains focus, it kicks off its data fetch immediately (via `Foglet.TUI.Command` or Raxol command primitive — the existing async pattern).
- While loading, the tab shows the existing loading state (spinner / "Loading..." copy) — the milestone already has `Progress.Spinner`.
- On error, the tab shows an honest error state with a `[R] Retry` keybind.
- "Press any key to load" is removed from every tab.

**Differentiators**
- Background prefetch of the next/previous tab so tab-switching feels instant. **Defer** — performance optimization, not a polish requirement.

**Anti-Features**
- Synchronous loading on mount that blocks the screen render — must use the async command pattern.
- Auto-refresh on a timer — pulls weight without consent and is hard to test deterministically.

**Dependencies**
- Per AGENTS.md, off-process work belongs in `Foglet.TUI.Command`/Raxol commands — verify the existing patterns are followed.
- This is the prerequisite for **CAT-SYSOP-TAB-LOADS** (the tabs that "never load no matter what I press" #6, #7, #8 may simply be "not even wired to the press-any-key pattern" — once load-on-mount is in place, those may resolve as side-effects).

---

### CAT-SYSOP-TAB-LOADS — Boards / Limits / System tabs actually load (Sysop #6, #7, #8)

**Table Stakes**
- Each tab fetches its data through the appropriate context (`Foglet.Boards`, `Foglet.Config`, system telemetry source) on mount.
- On success, content renders. On error, an honest error message + `[R] Retry`.
- No "tab works only sometimes" failure modes — common cause is a race between mount-completion and data-fetch dispatch; use Raxol commands to make ordering deterministic.

**Dependencies**
- Depends on **CAT-SYSOP-LOAD-ON-MOUNT** (the gating "press any key" must be removed first).
- The fetches themselves should already work — these are existing v1.1/v1.2 contexts.

**Anti-Features**
- Returning a TUI-side default when the context call fails — silently shows a misleading empty state.

---

### CAT-SYSOP-USERS-INVALID-TRANSITION — "Invalid status transition" surfaced error (Sysop #9, #10, #11)

**Table Stakes**
- Users tab loads consistently (resolves once CAT-SYSOP-LOAD-ON-MOUNT lands) (#9).
- The "Invalid status transition" error is **either fixed at its source** (the v1.2 Phase 10 user-status admin context rejects an attempted transition that the UI shouldn't have allowed in the first place) **or** the UI prevents offering invalid transitions in the first place. Likely cause: the UI offers "Approve" on a user who's already approved, and the context's state-machine rejects it. Fix: gate the keybind on the user's current status.
- Advertised keys (#11 — "None of the advertised keys do anything") all do their advertised thing on at least one user row; if a key is contextual, the command bar reflects it dynamically.

**Differentiators**
- An inline status-machine diagram in operator-help that shows valid transitions (e.g. `pending → approved → suspended → reactivated`). **Defer**.

**Anti-Features**
- Showing all keybinds for all users regardless of state and relying on the context to reject invalid ones — that's exactly the "Invalid status transition" UX the user is reporting.

**Dependencies**
- Depends on **CAT-SYSOP-TAB-LOADS** (Users tab must load).
- Depends on **CAT-FORM-KEYBINDS** (advertised keys must do their thing).

---

### CAT-SYSOP-SITE-EDIT — Site tab editable + remove planning denotions (Sysop #3, #4)

**Table Stakes**
- Each Site field is editable through the existing `Modal.Form` widget.
- Subtitles under each field are **user-facing copy**, not internal planning notes (e.g. remove `[CONFIG-001]`, `phase 14 deliverable`, etc.). The form should describe what the field does for an operator, not what spec it satisfies.

**Dependencies**
- Depends on **CAT-FORM-FOCUS** + **CAT-FORM-KEYBINDS** (the edit gestures must work first).
- Pure copy fix for the subtitles — independent.

---

### CAT-SYSOP-INVITES-TABLE — Invites table column allocation (Sysop #12, #13)

**Table Stakes**
- The Invites table renders with proper column separators and proportional column widths. The reported output has *no* spacing between `Code`, `Status`, `Created`, `Used by` — width math collapsed all columns to zero whitespace.
- Each column is allocated min-width that fits its longest expected value: `Code` ~18 chars, `Status` ~10 chars, `Created` ~10 chars (`YYYY-MM-DD`), `Used by` flex-grow to fill remaining width.
- Existing invite codes are selectable (focus moves through rows; Enter on a row reveals row-level actions like "Revoke") (#13).

**Differentiators**
- A wide-terminal layout that adds an `Expires` column when the screen is ≥132 cols.
- Color-coded status badges (`available` green, `redeemed` dim, `revoked` red) routed through `Display.Badge` (already shipped).

**Anti-Features**
- Adding horizontal scrolling — terminal-table responsive layout means **resize columns**, not horizontal scroll. ANSI-table conventions don't include horizontal scroll, and SSH users won't expect it.
- A fixed-width pixel-style table that overflows on narrow terminals.

**Dependencies**
- Depends on the **width-math fix that also resolves CAT-MAINMENU-CHROME #2 and CAT-GLOBAL-TAB-GLYPHS #1**. The pattern looks identical: fill characters multiplied by a wrong cell-count. Fix the underlying TextWidth/padding helper once.
- The `Display.ConsoleTable` widget exists and should be used; if it's already in use here, the bug is in how this screen invokes it (column specs probably).

---

### CAT-SYSOP-COMMANDBAR-CONSISTENCY — Tabs command bar shows same hints across screens (Sysop #2)

**Table Stakes**
- When a screen has tabs, the command bar advertises a tab-jump key (`1-N Jump`) consistently across **every** tabbed screen (Account, Moderation, Sysop). Either every tabbed screen advertises it or none does — pick a rule.
- Small inconsistency, but it shapes user expectations.

**Dependencies**
- None. Pure command-bar wiring fix.

---

### CAT-MOD-LAYOUT-OVERFLOW — Moderation LOG/USERS/BOARDS tabs fit terminal (Moderation #1)

**Table Stakes**
- All three Moderation tabs fit 64×22 (project's minimum terminal). Content above the top edge or below the bottom edge is wrong.
- Where the data exceeds the available rows, it's **paginated or scrolled within the content region**, not by overflowing the screen.

**Dependencies**
- Pre-condition for **CAT-MOD-LOG-TRUNCATION** (you can't fix the LOG table's column allocation if the table is overflowing the screen entirely).
- Likely shares root cause with **CAT-BOARDS-LAYOUT-OVERFLOW** — both are sized using the same screen-frame helper. Fix once.

**Anti-Features**
- Reducing content density to make it fit — operator screens should remain dense (Operator Console mode). Fix the layout, don't strip the content.

---

### CAT-MOD-LOG-TRUNCATION — LOG table is responsive (Moderation #2)

**Table Stakes**
- LOG table consumes the full available width: when the terminal is 132 cols, the table fills 132 cols (minus chrome). Currently it's truncating at a fixed width.
- Long messages elide with `…` rather than hard-truncating mid-word.
- Timestamps render in the user's preferred timezone (already supported via Phase 6 chrome convention — propagate to LOG rows).

**Dependencies**
- Depends on **CAT-MOD-LAYOUT-OVERFLOW** (table can't be responsive if its container overflows).
- Same width-math primitive as **CAT-SYSOP-INVITES-TABLE**.

---

### CAT-BOARDS-LAYOUT-OVERFLOW — Boards screen fits terminal (Boards #1)

**Table Stakes**
- Boards screen renders within 64×22 minimum and looks composed at 80×24.
- Categories list and boards list together fit the visible area; scrolling within the list region is allowed, screen-wide overflow is not.

**Dependencies**
- Same root cause as **CAT-MOD-LAYOUT-OVERFLOW**.

---

### CAT-BOARDS-CATEGORY-EXPAND — Enter on category expands/collapses (Boards #2)

**Table Stakes**
- When a category row is focused, Enter toggles its expanded state (collapsed → shows children, expanded → hides children).
- Visual indicator on the category row reflects state: `▸` collapsed, `▾` expanded (or use existing `Display.Tree` widget which already supports this).
- When a board row (a leaf, not a category) is focused, Enter navigates to thread list — this is Boards #3 in ISSUES.md, marked as already resolved between filing and milestone start per PROJECT.md.

**Differentiators**
- Remember per-user expand/collapse state across sessions. **Defer** — adds persistence work outside this milestone.

**Anti-Features**
- Auto-expanding all categories on mount — overwhelms small terminals.
- Different keybinds for "expand category" vs "open board" — Enter should be the universal "do the contextual thing" key.

**Dependencies**
- The existing `Display.Tree` widget supports expand/collapse — verify whether the Boards screen uses it or rolls its own. If the latter, switching to `Tree` may resolve this for free.

---

### CAT-BOARDS-FREEZE — Selecting a board freezes the screen (Boards #3) — RESOLVED

**Status:** Already resolved between ISSUES.md filing and milestone start. Confirmed in PROJECT.md Current Milestone "Already resolved between ISSUES.md filing and milestone start" subsection. Listed only so it doesn't get re-spec'd from ISSUES.md.

---

### CAT-GLOBAL-TAB-GLYPHS — No trailing border glyphs after the rightmost tab (Globally #1)

**Table Stakes**
- When the tab strip's tabs total less width than the available row, the trailing space is filled with the **same border-character treatment as the rest of the chrome** (typically a single `─` continuation), not a visible repeating glyph artifact.
- `Foglet.TUI.Widgets.Input.Tabs` is the single owner of this rendering; one fix covers every tabbed screen.

**Dependencies**
- Same width-math root cause as **CAT-MAINMENU-CHROME** (Oneliners glyph) and **CAT-SYSOP-INVITES-TABLE** (cramped columns). Strong recommendation: consolidate into a single "fix the TextWidth-based padding helper" task so the requirements step can sequence it as a blocker for the three downstream visual fixes.

---

### CAT-MARKDOWN-NEWLINES — Respect markdown newlines (Globally #2)

**Table Stakes**
- Two consecutive newlines in source markdown render as a paragraph break: one visible blank line in the terminal output. Currently they're being collapsed.
- A single newline in source (a CommonMark "soft break") renders as either a single line break **or** a single space — pick one and apply consistently. For a BBS where users hand-type prose, **render soft breaks as line breaks** (matches user intuition; matches what the post composer shows).
- Maximum **one** blank line between any two non-blank lines — clamp `\n\n\n` to `\n\n` so users can't introduce big vertical gaps.
- `Post.MarkdownBody` widget is the single owner; fix once.

**Differentiators**
- A "tight mode" sysop config to render soft breaks as spaces instead — the CommonMark spec explicitly allows either. **Defer**.

**Anti-Features**
- Collapsing all newlines to a single space — destroys ASCII art, code-block-adjacent content, and intentional formatting.
- Preserving raw newlines verbatim with no clamping — users will accidentally produce posts that scroll forever.

**Dependencies**
- None. Pure renderer fix.

---

### CAT-COMPOSER-WORDWRAP — Editor word-wraps long lines (Globally #3)

**Table Stakes**
- The composer (new-thread + reply, both share `Composer.EditorFrame`) **soft-wraps** lines that exceed the editor's column width — the visual line breaks but the underlying text remains a single logical line.
- Cursor navigation respects logical lines: arrow Up from the second visual line of a long logical line moves the cursor up by visual line (within that logical line) until it reaches the top of that logical line, then up to the previous logical line.
- Submitted post text is the **logical** content (no `\n` characters inserted from soft wrap).
- At a width change (terminal resize), the visual wrap re-flows; the logical text is unchanged.

**Differentiators**
- Hard-wrap at 80 chars on submit (insert real newlines) — historically common in mailers, but **defer**: BBS posts often want longer paragraphs that the reader's terminal will re-wrap.

**Anti-Features**
- Hard-wrapping on every keystroke (inserting `\n` into the buffer at column N) — destroys logical-line semantics and breaks markdown.
- Horizontal scrolling within the composer — fights terminal text-editor convention; nano, vim's `:set wrap`, and Bubble Tea's textarea all soft-wrap.

**Dependencies**
- Tightly coupled to **CAT-MARKDOWN-NEWLINES**: the composer's preview pane uses the same renderer, so the markdown fix needs to be coordinated with the wrap fix. If the renderer collapses newlines, the user's wrapped paragraphs will look wrong in preview.

---

## Feature Dependencies (Fix-Ordering Graph)

This is what the requirements step needs most. There are three "root" fixes that gate ~70% of the milestone; everything else hangs off them.

```
[ROOT-A: TextWidth/padding helper fix]
    ├── CAT-GLOBAL-TAB-GLYPHS         (trailing glyphs after rightmost tab)
    ├── CAT-MAINMENU-CHROME           (specifically the Oneliners |||... artifact)
    └── CAT-SYSOP-INVITES-TABLE       (cramped columns)

[ROOT-B: Form event routing — focus + keybinds]
    ├── CAT-AUTH-CURSOR               (cursor follows char)
    ├── CAT-FORM-FOCUS                (Tab / Shift+Tab / focus-aware keystrokes)
    ├── CAT-FORM-KEYBINDS             (Esc/Enter wired to advertised behavior)
    │       ├── CAT-AUTH-VALIDATION
    │       ├── CAT-AUTH-NO-EMAIL
    │       ├── CAT-ACCOUNT-PROFILE-PERSIST
    │       ├── CAT-ACCOUNT-PREFERENCES-OPTIONS
    │       │       └── CAT-ACCOUNT-TIMEZONE   (selector needs Tab/Enter)
    │       ├── CAT-ACCOUNT-SSHKEYS-PASTE      (paste lands in focused field)
    │       ├── CAT-SYSOP-SITE-EDIT
    │       ├── CAT-SYSOP-USERS-INVALID-TRANSITION
    │       └── CAT-SYSOP-INVITES-TABLE        (#13 — selecting invites)

[ROOT-C: Screen-frame layout / load-on-mount]
    ├── CAT-SYSOP-LOAD-ON-MOUNT
    │       └── CAT-SYSOP-TAB-LOADS
    │               └── CAT-SYSOP-USERS-INVALID-TRANSITION (Users tab must load)
    ├── CAT-MOD-LAYOUT-OVERFLOW
    │       └── CAT-MOD-LOG-TRUNCATION
    └── CAT-BOARDS-LAYOUT-OVERFLOW
            └── CAT-BOARDS-CATEGORY-EXPAND

Independent (no upstream blocker — can ship in parallel):
    CAT-AUTH-BREADCRUMBS
    CAT-AUTH-RESET-RENDER          (depends on AUTH-NO-EMAIL for copy)
    CAT-MAINMENU-CHROME            (titles-on-border, theme, indents — non-||| parts)
    CAT-ACCOUNT-REDUNDANT-HEADERS
    CAT-SYSOP-COMMANDBAR-CONSISTENCY
    CAT-MARKDOWN-NEWLINES
    CAT-COMPOSER-WORDWRAP           (couples with markdown fix for preview)
```

### Critical Ordering Constraints

1. **Width-math primitive (ROOT-A) before Invites table, Oneliners glyph, tab-row glyphs.** Same root cause; fix once.
2. **Form focus + keybinds (ROOT-B) before any Account or Sysop edit fix.** The Account #8 bug ("typed character appears in the timezone field regardless of focus") is a symptom of broken event routing. Fix routing before fixing any individual field.
3. **Load-on-mount (CAT-SYSOP-LOAD-ON-MOUNT) before "tab never loads" (#6, #7, #8).** Some of those tabs may resolve as side-effects of removing "press any key."
4. **Layout-overflow (CAT-MOD-LAYOUT-OVERFLOW, CAT-BOARDS-LAYOUT-OVERFLOW) before LOG truncation, before Boards expand/collapse.** Can't reason about a sub-region's behavior when its container overflows.
5. **CAT-AUTH-NO-EMAIL before CAT-AUTH-RESET-RENDER.** The render fix needs to know what message to render; that's defined by the no-email branch.
6. **CAT-MARKDOWN-NEWLINES coordinates with CAT-COMPOSER-WORDWRAP.** Composer preview uses the renderer; ship together to avoid mid-milestone preview regressions.

---

## Anti-Features Summary (cross-cutting "do not build")

- **No new product features** — milestone is stabilization. SEED-001 (webhooks) and SEED-002 (verification UX) stay dormant per PROJECT.md.
- **No browser-based reset flow** — PROJECT.md's existing key decision: "Keep reset recovery browser-free; operator-assisted SSH reset with raw tokens is honest and testable."
- **No web UI for the timezone selector, paste handler, or any form** — terminal-first product surface only.
- **No silent auto-saves** — explicit Submit contract preserved.
- **No horizontal scrolling on tables** — terminal convention is column-resize, not scroll.
- **No keyboard-shortcut redesigns** — Tab/Shift+Tab/Enter/Esc match existing conventions; do not introduce vim/emacs alternatives in this milestone.
- **No hardcoded colors** — all rendering routes through `Foglet.TUI.Theme` per D-07/D-09.
- **No widget-internal focus state** — focus lives in the screen or sibling state module per AGENTS.md and the widget README.
- **No expansion of moderation/sysop scope** — site/board scope shapes (`:site`, `{:board, board_id}`) are stable; do not add a third scope as part of stabilization.

---

## Confidence Assessment

| Area | Confidence | Reason |
|------|------------|--------|
| Required behaviors per category | HIGH | ISSUES.md is concrete and reproducible; PROJECT.md confirms scope; existing widget catalog confirms primitives exist |
| Dependency ordering | HIGH | Three root causes are visible in the bug shapes themselves (width-math, event routing, load-on-mount); ordering follows directly |
| Bracketed paste over SSH | MEDIUM | Convention is well-documented but Foglet's specific SSH→Raxol input forwarding pipeline needs verification (CLIHandler boundary) |
| IANA timezone selector design | HIGH | Smart Interface Design Patterns + IANA tz list discussion converge on the same UX |
| Markdown soft-break rendering | MEDIUM | CommonMark spec explicitly leaves this renderer-defined; the Foglet choice (soft breaks → line breaks) is a product decision, not a forced one |
| Username-enumeration safety | HIGH | OWASP guidance is unambiguous |
| Composer word-wrap | HIGH | nano/Bubble Tea/Warp converge on soft-wrap as default for prose composers |

## Gaps for Phase-Specific Research Later

- The exact SSH→Raxol input chain for bracketed paste — whether `Foglet.SSH.CLIHandler` already passes CSI sequences through or strips them. Worth a small spike during the SSH-keys-paste fix.
- Whether the "Invalid status transition" error has a stale-state cause (the UI was rendered against an old user record) vs. an actually-invalid action — needs reproduction during fix.
- Whether `Display.Tree` already supports the Boards screen's expand/collapse semantics or whether the screen rolls its own — affects the size of CAT-BOARDS-CATEGORY-EXPAND.

---

## Sources

- [Bracketed-paste mode — cirw.in](https://cirw.in/blog/bracketed-paste)
- [Bracketed-paste — Wikipedia](https://en.wikipedia.org/wiki/Bracketed-paste)
- [XTerm bracketed-paste docs](https://invisible-island.net/xterm/xterm-paste64.html)
- [CyberArk — Multiline input with bracketed paste mode](https://docs.cyberark.com/pam-self-hosted/latest/en/content/pasimp/psm_for_ssh_multiline-input.htm)
- [Cursor (user interface) — Wikipedia](https://en.wikipedia.org/wiki/Cursor_(user_interface))
- [Linux console cursor features — Baeldung](https://www.baeldung.com/linux/console-cursor-features)
- [CommonMark spec — Hard line breaks](https://spec.commonmark.org/0.17/)
- [CommonMark Discussion — Soft line-breaks should not introduce spaces](https://talk.commonmark.org/t/soft-line-breaks-should-not-introduce-spaces/285)
- [Doppler Docs — TUI Guide](https://docs.doppler.com/docs/tui)
- [Mike Ellis — What should the Enter key do within a form?](https://medium.com/@mikeellisut/what-should-the-enter-key-do-within-a-form-3383eb6297ea)
- [Designing A Time Zone Selection UX — Smart Interface Design Patterns](https://smart-interface-design-patterns.com/articles/time-zone-selection-ux/)
- [How to select zones for a TimeZone picker — IANA tz list](https://lists.iana.org/hyperkitty/list/tz@iana.org/thread/RDI2IRJBQZWQHKVPLJP4I6EWBV6TY2FO/)
- [Akimbo Core — Preventing Username Enumeration](https://akimbocore.com/article/preventing-username-enumeration/)
- [OWASP — Testing for Account Enumeration](https://owasp.org/www-project-web-security-testing-guide/latest/4-Web_Application_Security_Testing/03-Identity_Management_Testing/04-Testing_for_Account_Enumeration_and_Guessable_User_Account)
- [PingDirectory — Password reset tokens](https://docs.pingidentity.com/pingdirectory/11.0/pingdirectory_security_guide/pd_sec_password_reset_tokens.html)
- [Password Reset Tokens: Secure Implementation Guide](https://www.onlinehashcrack.com/guides/password-recovery/password-reset-tokens-secure-implementation-guide.php)
- [nano command manual — soft wrap](https://www.nano-editor.org/dist/v2.2/nano.html)
- [Warp — Modern text editing](https://docs.warp.dev/terminal/editor)
- [Wikipedia — Box-drawing characters](https://en.wikipedia.org/wiki/Box-drawing_characters)
- [Textual — Border styles](https://textual.textualize.io/styles/border/)
- [Responsive HTML Tables using Flex — Paul Bradley](https://paulbradley.dev/css-flex-responsive-tables/)
