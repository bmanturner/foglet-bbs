# FOG-901 UX spec: selectable KV field lists and one-field edit overlays

Parent: FOG-899
Owner: TUI UX Designer
Canonical branch: fog/899-selectable-kv-edit-modals
Status: implementation-ready UX acceptance map

## Source verification

Verified against the current repository before specifying the new interaction:

- `lib/foglet_bbs/tui/screens/account/profile_form.ex` renders PROFILE through `Modal.Form` as a full inline form.
- `lib/foglet_bbs/tui/screens/account/prefs_form.ex` renders PREFS through `Modal.Form` as a full inline form and currently live-previews theme changes via `candidate_theme_id`.
- `lib/foglet_bbs/tui/screens/account/state.ex` defines PROFILE fields `Location`, `Tagline`, `Real name`; PREFS fields `Timezone`, `Time format`, `Theme`; timezone is already a `:select_list` with searchable choices.
- `lib/foglet_bbs/tui/screens/sysop/site_form.ex` renders SITE through a full inline `Modal.Form`, handles `E` as the current test-email action, and saves all visible keys from one form payload.
- `lib/foglet_bbs/tui/screens/sysop/site_form/state.ex` defines SITE keys, labels, conditional `invite_generation_per_user_limit`, delivery/email validation, and current test-email description behavior.
- `lib/foglet_bbs/tui/widgets/display/kv_grid.ex` is display-only and width-safe but has no selection, descriptions, or viewport ownership.
- `lib/foglet_bbs/tui/widgets/README.md` lists relevant primitives: `Display.KvGrid`, `List.SelectionList`, `List.SmartList`, `Modal.Form`, `Input.TextInput`, `Input.RadioGroup`, `Input.Checkbox`, `Input.Tabs`, and `Display.Table`.
- `docs/raxol/getting-started/WIDGET_GALLERY.md` confirms `viewport`, `split_pane`, `table`, `tree`, and list primitives available for composition.

Current render evidence captured before this spec:

- `/tmp/fog901-renders/account-64x22.txt`
- `/tmp/fog901-renders/account-80x24.txt`
- `/tmp/fog901-renders/account-100x30.txt`
- `/tmp/fog901-renders/account-120x36.txt`
- `/tmp/fog901-renders/sysop-64x22.txt`
- `/tmp/fog901-renders/sysop-80x24.txt`
- `/tmp/fog901-renders/sysop-100x30.txt`
- `/tmp/fog901-renders/sysop-120x36.txt`

Those renders show the current problem clearly: Account PROFILE presents field focus and full-form save/cancel chrome even in normal read mode, while Sysop SITE can show loading with full-form Save/Cancel hints. This spec replaces that default mode with a stable list surface plus one-field overlays.

## User goal

A member or sysop should be able to review settings at a glance, move to the exact field they want, edit only that field, and return to the same readable list without fighting hidden form focus, full-page save semantics, tab traps, or raw expert values.

## Interaction alternatives considered

### A. Keep full inline forms and improve helper text

Pros:
- Smallest implementation change.
- Reuses existing `Modal.Form` field specs and validators.

Cons:
- Leaves the core failure mode intact: tab navigation, field focus, save/cancel, viewport height, and tab switching all compete.
- Forces users to understand form-mode behavior even when they only want to inspect current values.
- Helper text would explain an awkward interaction rather than removing it.

Decision: reject. This is the current product smell FOG-899 is explicitly trying to remove.

### B. Selectable field list plus one-field overlay modal

Pros:
- Read mode becomes stable and scan-friendly.
- Editing is constrained to one field, so validation and save errors can be local and understandable.
- Tab switching works naturally from list mode because the list is not a text-entry form.
- Reuses existing field definitions and `Modal.Form` controls inside small overlays where they are appropriate.

Cons:
- Requires a reusable selectable field-list widget or wrapper plus per-field overlay state.
- Needs careful key conflict handling for Sysop SITE because `E` currently sends a test email.

Decision: choose this pattern. It best matches the user goal and the ticket.

### C. Wide split-pane settings editor

A master/detail layout could show a left field list and right inspector/help pane at 100+ columns.

Pros:
- Uses wide terminals more fully.
- Descriptions and validation hints can be visible without opening overlays.

Cons:
- Adds responsive complexity and divergent layouts to three surfaces that should feel predictable.
- At 64x22 and 80x24 it must collapse back to a list anyway.
- The affected field sets are short; a permanent inspector would be more chrome than value.

Decision: reject for this issue. Use the extra width for better row budgets and optional inline descriptions, not a second pane.

## Primitive fit

Primitives considered:
- `KvGrid`: good width-safe label/value primitive but display-only.
- `SelectionList`: good selection affordance, but not enough by itself for aligned key/value rows and descriptions.
- `SmartList`: too heavy; search/pagination/multiselect are not needed for these short field sets.
- `table`: rejected because field descriptions and wrapped value text matter more than rigid columns.
- `tree`: rejected; fields are not hierarchical.
- `split_pane`: rejected for this issue; field sets are short and consistent single-column behavior is preferable.
- `viewport`: required for field lists and overlay internals when content exceeds available height.
- `Modal.Form`: keep for one-field overlay bodies only, not default tab bodies.
- `TextInput`, `Checkbox`, `RadioGroup`/enum/select controls: required inside overlays by field type.

Chosen composition:

- New reusable `SelectableFieldList` display/input wrapper, preferably under `lib/foglet_bbs/tui/widgets/list/` or `display/`, rather than overloading `Display.KvGrid`.
- It can reuse `KvGrid` formatting logic or `TextWidth`, but it must own selection, description rows, empty-value placeholders, and scroll/viewport integration.
- Per-field edit overlays reuse `Modal.Form` with a one-field spec and compact modal chrome owned by the app/screen.

Why not only `KvGrid`:

`KvGrid` is correct as a read-only primitive for summaries. Adding selection, descriptions, viewport state, and edit affordances would contaminate a simple display widget used elsewhere. A wrapper/new widget keeps the primitive clean and gives this product pattern a name.

Implementation risks needing Elixir/OTP review:

- Per-field save effects must not bypass domain/context validation or authorization.
- Sysop SITE currently persists all visible keys in one submit path; one-key persistence must preserve cross-field validation for `delivery_mode` + `require_email_verification`.
- Theme preview is currently a live side effect in Account PREFS; implementation must deliberately scope preview to the overlay and cancel path.
- Existing `E` test-email behavior conflicts with new list-mode `E Edit` on SITE and must be remapped without breaking discoverability.

## Default/read mode layout contract

Applies to Account PROFILE, Account PREFS, and Sysop SITE.

### Regions

Inside the existing `ScreenFrame`:

1. Top status/breadcrumb stays unchanged.
2. Tab bar stays directly under the status line.
3. Thin divider stays under tabs.
4. Tab body is one scrollable field-list viewport.
5. Bottom command bar reflects list mode, not form mode.

The field list begins at the first row below the divider. It should not add another heavy outer border; the screen frame already frames the surface.

### Row anatomy

Each logical field row is a selectable block:

- Selection marker column: 2 chars.
  - Selected: `▸ ` or theme-equivalent strong marker.
  - Unselected: `  `.
- Label column:
  - 64x22: 14 chars max.
  - 80x24: 18 chars max.
  - 100x30 and wider: 24 chars max.
- Separator: ` : ` or two spaces after padded label. Prefer a quiet separator over table pipes.
- Value region: remaining width.
- Optional description line(s): indented to align with the value region or, at 64x22, indented one level under the row.

Selected treatment:

- The selected field's primary row must be unmistakable even without color: `▸` marker plus reverse/bold/themed selected background where supported.
- If a field has description lines, the selected background does not need to cover all description lines, but the description must visually belong to that selected block through indentation and spacing.
- Cursor should be hidden in list mode or placed outside text-entry positions; no text caret should appear in read mode.

Empty value placeholder:

- Use `—` for blank/nil user-facing values.
- Do not show empty spacing or `nil`.
- For booleans, show friendly values: `Yes` / `No` or `Enabled` / `Disabled` depending on field label. Keep copy finalization with Content Designer if wording changes beyond existing labels.

Text policy:

- Labels truncate with ellipsis only if they exceed the label budget; these labels should generally fit.
- Values use one visible line by default and truncate with ellipsis when too long.
- Descriptions may wrap to the viewport width, but each field block should remain compact: max 2 description lines in list mode. Longer help belongs in the overlay.
- Raw config keys are allowed for SITE only where the existing UI lacks an operator-facing label; prefer existing friendly labels from `SiteForm.State` where present.
- For enum SITE values, list mode should display the friendly labels already defined in `@value_labels`, not raw schema strings when a friendly label exists.

Spacing:

- No blank line between fields by default.
- A field with a description gets one dim line directly below it; no extra blank spacer unless the list is visually dense at 100+ columns.
- The list should feel like a BBS settings card, not a spreadsheet.

### Scrolling model

- Field-list viewport owns scroll offset per tab: `profile_field_list`, `prefs_field_list`, and `site_field_list` or equivalent screen-local state.
- Up/Down moves selection by one field and auto-scrolls to keep the selected field block visible.
- PageUp/PageDown scrolls by one viewport page and moves selection to the nearest visible field after scroll.
- Home/End moves to first/last visible field.
- If all fields fit, no scrollbar is required; if not, show a compact position indicator such as `3/6` or a thin scrollbar only if the existing viewport supports it cleanly.
- Descriptions are part of the selected field's block for visibility math; do not scroll to a state where the selected primary row is hidden and only its description remains.

### Command bar: list mode

Account PROFILE/PREFS list mode:

- System: `Ctrl+Q Back`
- Fields: `↑/↓ Select`
- Action: `E Edit`
- Tabs: `←/→ Tabs`

Sysop SITE list mode:

- System: `Q Back`
- Fields: `↑/↓ Select`
- Action: `E Edit`
- Tabs: `←/→ Tabs`

At narrow widths, retention priority should keep Back, Edit, and Select before secondary tab hints. Do not advertise Save/Cancel in list mode.

Tab switching:

- Left/Right and number tab shortcuts work from list mode without requiring Escape.
- Up/Down are field selection, not enum cycling, in list mode.
- Escape in list mode should either be a no-op or route to Back only if that matches existing screen convention; it must not be required to leave a hidden form focus state.

## Field coverage and display decisions

### Account PROFILE

Fields in render order:

1. Location
   - Value: current `user.location`; blank `—`.
   - Overlay control: text input.
2. Tagline
   - Value: current `user.tagline`; blank `—`.
   - Overlay control: text input.
3. Real name
   - Value: current `user.real_name`; blank `—`.
   - Description: `For friends and the sysop; blank uses your handle.`
   - Overlay control: text input.

PROFILE list mode must never show Save/Cancel chrome. Each overlay saves through the account profile update path with only the edited attribute changed. Other profile values must remain unchanged.

### Account PREFS

Fields in render order:

1. Timezone
   - Value: current timezone, preferably `America/Chicago`-style exact value with optional city match if already available.
   - Description: keep discoverability: search by city or IANA name.
   - Overlay control: searchable/selectable timezone picker. Do not regress to raw free text.
2. Time format
   - Value: `12h` or `24h`.
   - Overlay control: enum/radio choice.
3. Theme
   - Value: theme id or friendly theme label if available.
   - Description: preview decision below.
   - Overlay control: enum/radio choice.

Theme preview decision:

- Preview inside the Theme overlay while it is open. This preserves the existing instant-preview benefit but confines it to the place where the user is intentionally changing theme.
- Save commits and closes overlay.
- Cancel/Escape restores the pre-overlay theme immediately and closes overlay.
- The list behind the overlay may repaint in the candidate theme while the overlay is open; after cancel it must repaint in the persisted theme.
- Do not preview theme changes from list-mode selection movement.

### Sysop SITE

Visible fields in canonical render order:

1. `registration_mode`
   - Label: `Account registration`.
   - Display values: friendly labels from `@value_labels`.
   - Overlay control: enum/radio/select.
2. `invite_code_generators`
   - Label: `Invite code generators`.
   - Display values: friendly labels from `@value_labels`.
   - Overlay control: enum/radio/select.
3. `delivery_mode`
   - Label: `Email delivery`.
   - Display values: friendly labels from `@value_labels`.
   - Overlay control: enum/radio/select.
   - Test-email action placement: see below.
4. `require_email_verification`
   - Label may remain raw if no friendly label exists, but recommended label is `Require email verification`.
   - Display value: `Yes`/`No`.
   - Overlay control: boolean checkbox/toggle.
5. `guest_mode_enabled`
   - Label: `Guest mode`.
   - Display value: `Enabled`/`Disabled`.
   - Overlay control: boolean checkbox/toggle.
6. `invite_generation_per_user_limit`
   - Visible only when `invite_code_generators == any_user`.
   - Recommended label: `Invites per user`.
   - Display value: integer or `—` if blank is valid.
   - Overlay control: integer input with min/max validation surfaced in overlay.

SITE test-email placement:

- `E` is reserved globally for `Edit` in list mode.
- Move test email to a secondary action available only when selected field is `Email delivery` and current delivery mode is `email`.
- Recommended key: `T Test email`.
- Command bar on SITE when `Email delivery` is selected and test is available:
  - System: `Q Back`
  - Fields: `↑/↓ Select`
  - Action: `E Edit`, `T Test email`
  - Tabs: `←/→ Tabs`
- If selected field is not `Email delivery`, hide `T Test email` from the keybar.
- Test-email status should render as the `Email delivery` description/status line in the field list: sending, sent, missing email, forbidden, or check logs. This preserves the existing contextual placement without colliding with edit.

Invalid SITE combination:

- `delivery_mode=no_email` and `require_email_verification=true` must produce an overlay error, not a silent list no-op.
- Because this is a cross-field invariant, either overlay may show the error if saving creates the invalid pair.
- Error text should name the conflict and the other field: e.g. `No-email mode cannot require email verification. Turn off Require email verification first.` Final wording can be Content Designer-reviewed.

## Overlay edit ergonomics

### Shared overlay structure

- Centered modal over the existing screen.
- Max width:
  - 64x22: terminal width minus 4 columns; no wider than 60.
  - 80x24: 64 columns.
  - 100x30+: 72 columns unless the field control needs more.
- Max height:
  - 64x22: 14 rows.
  - 80x24: 16 rows.
  - 100x30+: 18-20 rows.
- Internal viewport/list if field control exceeds modal height, especially timezone search.
- Title format: `Edit <Field label>`.
- Body shows one field control only plus description/helper and error/status region.
- Footer/command bar inside or through global overlay mode should be compact: `Enter Save`, `Esc Cancel`, plus field-specific navigation/search hints.

### Overlay controls by type

Text/integer:
- Focus starts in the input.
- Left/Right/Home/End edit the input.
- Enter saves.
- Esc cancels.
- Validation errors appear below the input and keep the overlay open.

Enum/boolean:
- Use a small radio/select list rather than free typing.
- Up/Down changes highlighted choice inside overlay.
- Enter saves highlighted choice.
- Esc cancels.
- For boolean, a checkbox/toggle is acceptable if selected/focused state is unmistakable.

Timezone:
- Use searchable/selectable picker.
- Typing filters by city or IANA name.
- Up/Down moves filtered choices.
- Enter saves highlighted timezone.
- Esc cancels.
- Empty/no-match state says no matches and keeps the search field focused.
- The current timezone is preselected and visible on open.

### Overlay command bar

When overlay is open, the visible commands are modal-scoped:

- Text/integer: `Enter Save`, `Esc Cancel`; optionally `←/→ Move` only if width allows.
- Enum/boolean: `↑/↓ Choose`, `Enter Save`, `Esc Cancel`.
- Timezone: `Type Search`, `↑/↓ Choose`, `Enter Save`, `Esc Cancel`.

Do not show tab-switching while overlay is open. Tab switching should be gated until overlay closes.

### Save/cancel semantics

- Save submits only the selected field value.
- On success: close overlay, update persisted/session state, rebuild list rows, keep selection on the edited field, and show the new value immediately.
- On validation/persistence error: keep overlay open, keep user input intact, show error near the field or in a modal status row.
- On cancel/Escape: close overlay, discard draft value, keep list selection on the same field, show previous persisted value.
- If a field becomes hidden after save, e.g. `invite_code_generators` changes away from `any_user`, clamp selection to the nearest visible field and reset viewport enough to keep it visible.

## Breakpoint behavior

### 64x22 minimum

- Single-column field list only.
- Label budget about 14 chars; values truncate aggressively with ellipsis.
- Descriptions wrap to max 1 visible line in list mode where necessary.
- Command bar keeps Back, Edit, Select; tab hint may compact/drop before those.
- Overlay uses nearly full width and internal scrolling. Timezone picker shows fewer rows but remains searchable.
- No required control may be hidden; if modal content exceeds height, internal viewport owns scroll.

### 80x24 baseline

- Single-column field list, deliberate not merely surviving.
- Label budget about 18 chars.
- Most PROFILE/PREFS/SITE values fit or truncate cleanly.
- One-line descriptions remain visible for Real name, Timezone, Theme, and Email delivery status where applicable.
- Command bar should show Back, Edit, Select, Tabs in normal list mode.
- Overlay target width around 64 columns.

### 100x30 comfortable

- Single-column field list remains preferred for consistency.
- Increase label budget to about 24 chars and value budget accordingly.
- Descriptions may use up to 2 lines if useful.
- More overlay choices can be visible without scrolling.
- Do not add a split pane just to fill space; use breathing room and clearer row rhythm.

### 120x36+ wide operator view

- Still single-column for these short forms unless implementation naturally supports an optional right-side detail panel without diverging behavior.
- Extra width should improve value readability and description wrapping.
- If a future inspector is added, it should be a non-blocking enhancement showing selected field help/status, not a separate edit path.
- Keybar can show secondary actions like `T Test email` when relevant, but avoid listing every fallback key.

## Acceptance scenarios

### Selection and tab switching

1. Open Account PROFILE.
2. See fields as selectable rows with Location selected by default.
3. Press Down: selection moves to Tagline; no text caret appears.
4. Press Right: active tab changes to PREFS without pressing Escape first.
5. Press Left: active tab returns to PROFILE and selection is preserved or reset deterministically to first field.

Pass condition: list mode has no Save/Cancel command hints and selected row is visually obvious.

### PROFILE edit/save

1. On PROFILE, select Tagline.
2. Press `E`.
3. Overlay title says `Edit Tagline`.
4. Type a new tagline.
5. Press Enter.

Pass condition: overlay closes, list still shows Tagline selected, and Tagline value updates immediately. Location and Real name remain unchanged.

### PROFILE cancel

1. Select Real name.
2. Press `E`.
3. Type a new value.
4. Press Esc.

Pass condition: overlay closes and Real name list value remains the prior value or `—`.

### PREFS timezone picker

1. Open Account PREFS.
2. Select Timezone.
3. Press `E`.
4. Type `Chicago`.
5. Use Down/Up if needed and press Enter on `America/Chicago`.

Pass condition: timezone overlay is searchable/discoverable, not raw IANA free text; saved timezone appears in the list after close.

### PREFS theme preview and cancel

1. Open Account PREFS.
2. Select Theme.
3. Press `E`.
4. Move to a different theme choice.
5. Observe preview while overlay is open.
6. Press Esc.

Pass condition: overlay closes and the screen returns to the previously persisted theme.

### PREFS theme save

1. Reopen Theme overlay.
2. Choose a different theme.
3. Press Enter.

Pass condition: overlay closes, theme remains applied, and Theme list value updates.

### SITE test email action

1. Open Sysop SITE with `delivery_mode=email`.
2. Select Email delivery.
3. Confirm command bar shows `E Edit` and `T Test email`.
4. Press `T`.

Pass condition: no edit overlay opens; Email delivery description/status line changes to sending/sent/error state. On other SITE rows, `T Test email` is not advertised.

### SITE edit conditional field

1. Open Sysop SITE.
2. Select Invite code generators.
3. Press `E`.
4. Choose `Any signed-in user` and save.

Pass condition: overlay closes and `Invites per user` appears as a selectable row. Selection remains deterministic and visible.

### SITE conditional field hides after save

1. With `Invites per user` visible, select Invite code generators.
2. Press `E`.
3. Choose `Sysops only` and save.

Pass condition: overlay closes, `Invites per user` row disappears, selection clamps to a visible row, and viewport does not leave blank/hidden focus.

### SITE validation failure in overlay

1. Set or keep Require email verification = true.
2. Select Email delivery.
3. Press `E`.
4. Choose No email and save.

Pass condition: overlay stays open and shows an error explaining the conflict with email verification. The list behind the modal does not pretend the value saved.

### Post-save refresh

For every PROFILE, PREFS, and SITE field:

1. Select field.
2. Open overlay.
3. Change value.
4. Save.

Pass condition: overlay closes and the read/list row shows the saved value without navigating away or refreshing manually.

### Modal command-bar behavior

1. Open any overlay.
2. Confirm list-mode tab hints disappear.
3. Confirm overlay commands match the active control type.
4. Press Esc.

Pass condition: overlay closes; list-mode command bar returns.

### Narrow viewport behavior

At 64x22 and 80x24:

1. Render Account PROFILE, Account PREFS, and Sysop SITE.
2. Move through every field.
3. Open each overlay.

Pass condition: selected field remains visible, no border overflow occurs, command bar does not lie, and required save/cancel controls remain reachable.

## Required render/QA evidence for implementation signoff

Implementation cannot be signed off by static inspection only. Provide at least:

- Render or SSH harness evidence for Account PROFILE list mode at 64x22 and 80x24.
- Render or SSH harness evidence for Account PREFS timezone overlay at 64x22 or 80x24.
- Render or SSH harness evidence for Sysop SITE list mode with Email delivery selected and `T Test email` advertised.
- Evidence for one successful PROFILE save returning to updated list.
- Evidence for one successful PREFS timezone or theme save returning to updated list.
- Evidence for one SITE validation failure kept inside the overlay.
- Evidence that tab switching works from list mode without Escape.

## Follow-up backlog

None created from this UX spec.

Potential future polish intentionally not tracked here:

- A wide-terminal optional inspector panel for selected field help/status. This is not needed for FOG-899 because the field sets are short, and adding a second responsive layout would increase implementation risk without improving the core edit flow.
- Friendlier labels for every raw Sysop SITE key. FOG-899 can ship using existing labels plus the recommended labels above; final wording can be handled during implementation/content review if copy changes materially.
