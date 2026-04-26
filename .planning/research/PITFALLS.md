# Pitfalls Research — v1.4 Post-Facelift Polish & Bug Fixes

**Domain:** Polish/bugfix close-out for an Elixir/Phoenix + vendored-Raxol SSH BBS
**Researched:** 2026-04-26
**Confidence:** HIGH (grounded in `AGENTS.md`, `ISSUES.md`, the actual `lib/foglet_bbs/tui/**` layout, and v1.3 close-out notes)

This file is scoped to mistakes that bite when applying the ~37 fixes in `ISSUES.md`
on top of the already-shipped v1.3 facelift. It is *not* general Elixir/Phoenix
advice. Every pitfall maps to the v1.4 phase that should prevent it and lists a
specific test/check (not "be careful").

Phase labels used below match the v1.4 milestone targets in `.planning/PROJECT.md`:

- **P1 Layout** — interface-extends-above-terminal, tab-row glyph, Invites table
- **P2 Forms** — Account/Sysop Esc/Enter/Tab/focus/paste/feedback
- **P3 Sysop Loads** — Boards/Limits/System/Users tab loads, Users status transition
- **P4 Auth Flows** — cursor, breadcrumbs, forgot-password validation, reset-email cropping, no-email token-consume
- **P5 Main Menu Chrome** — box titles, theme/accent, indents, Oneliners glyph
- **P6 Editor & Markdown** — composer word wrap, markdown line-break preservation
- **P7 Boards Interaction** — Enter expand/collapse on a category
- **PX Cross-cutting** — applies across phases

---

## Layout & Rendering

### L1 — Re-introducing width assumptions that bypass `Foglet.TUI.TextWidth`

**Symptom:** A "fixed" Invites/Users/Limits table looks correct in seed data but
shifts a column or wraps the right border the moment a handle has emoji,
combining marks, or wide CJK glyphs. `screen_frame.ex` already routes through
`TextWidth.display_width/1` and `TextWidth.truncate/2`; siblings that were
written before v1.3 sometimes still call `String.length/1` or `byte_size/1`.

**Root cause:** Polish PRs frequently reach for `String.slice/3` or
`String.pad_trailing/2` because they're the obvious fix for "this column is too
narrow." Those helpers count graphemes, not display cells.

**Prevention:**
- Lint check: add a `mix credo` custom check (or a test that grep-fails) for
  `String.length`, `String.slice`, `String.pad_trailing`, `String.pad_leading`,
  and `byte_size` inside `lib/foglet_bbs/tui/widgets/**` and
  `lib/foglet_bbs/tui/screens/**`. Allowlist only `Foglet.TUI.TextWidth` itself.
- Add a `TextWidth` regression test seeded with `"あ"`, `"é"` (precomposed +
  combining), and ZWJ emoji that exercises the exact widget under repair.

**Phase:** P1 Layout, also cross-cuts P2 Forms (input rendering) and P5 Main Menu.

---

### L2 — Fixing the 80x24 layout and silently regressing 64x22

**Symptom:** Moderation/Boards screens stop "extending above the terminal" at
80x24 but draw negative-height regions or empty panels at 64x22. v1.3 explicitly
landed 64x22/80x24/132x50 smoke coverage for composers; the operator-console and
moderation panes did not all get the same matrix.

**Root cause:** Devs validate against their own iTerm window, not the contract.
The 64x22 case is a hard minimum per `PROJECT.md` Constraints.

**Prevention:**
- Every layout fix in P1 must add (or extend) a render-snapshot test at
  `{cols: 64, rows: 22}` *and* `{cols: 80, rows: 24}` for the touched
  screen/tab. Assert no row exceeds `rows`, no row's display width exceeds
  `cols`, and no panel renders with non-positive dimensions.
- Use `Foglet.TUI.SizeGate` semantics in tests so the same gating path that
  ships to users runs.

**Phase:** P1 Layout. Re-run for any screen touched by P2/P3/P5/P6/P7 as
collateral coverage.

---

### L3 — Tab-row trailing glyph fix that double-renders or eats the chrome's right edge

**Symptom:** ISSUES.md "Globally #1" — border glyphs to the right of the
right-most tab. The naive fix is to pad the tab row to full width, which then
collides with `screen_frame.ex` which itself draws the right border. Result:
either the corner glyph (`┐`) becomes a tab fill, or two paint passes write to
the same cell and one wins non-deterministically.

**Root cause:** `tabs.ex` and `screen_frame.ex` both think they own the right
edge. Without a single owner, fix-on-fix oscillates.

**Prevention:**
- Decide ownership in P1 and document it in `lib/foglet_bbs/tui/widgets/README.md`:
  "tab row paints from `x0` up to `x_end - 1`; the frame owns `x_end`."
- Add a focused widget test that renders `Tabs` *inside* a `ScreenFrame` and
  asserts the rightmost column for the tab row is exactly the frame's vertical
  glyph (`│`), not a tab fill character or a duplicate `┐`.
- Snapshot at 64, 65, 66, 80, 81 columns to catch off-by-one boundary cases.

**Phase:** P1 Layout (item 1.Globally).

---

### L4 — Markdown re-flow that drops fenced code or list-item indentation

**Symptom:** ISSUES.md "Globally #2" — "Respect newlines a bit better."
A naive fix in `Foglet.Markdown` (or the post renderer) collapses double
newlines to single but also strips the leading whitespace inside fenced code
blocks or unordered-list continuations.

**Root cause:** Whitespace collapsing is applied to the rendered token stream
instead of to inline runs only. Once you collapse inside a `<pre>`/code token,
post bodies become syntactically wrong.

**Prevention:**
- Property test: for any post body, `render(body) |> strip_styling` must
  contain every line of every fenced code block byte-for-byte.
- Fixture test with a body that mixes (a) two paragraphs separated by one blank
  line, (b) a fenced code block with deliberate blank lines inside, and (c) a
  multi-paragraph list item. Snapshot the rendered output once; assert it
  doesn't change.

**Phase:** P6 Editor & Markdown.

---

### L5 — Composer word-wrap that breaks inside a multi-byte grapheme

**Symptom:** ISSUES.md "Globally #3" + "Account #9" — long lines don't wrap, and
the SSH-key paste path (a single very long line) is broken. A naive
`String.split` on whitespace at the column boundary can split inside a wide
glyph or a combining-mark cluster, producing replacement characters or a stuck
cursor.

**Root cause:** Wrap math uses character counts instead of `TextWidth` cell
counts.

**Prevention:**
- Wrap helper lives in or next to `Foglet.TUI.TextWidth` and operates on
  graphemes with cell-width awareness. Reject splits that would land inside a
  cluster — break before the cluster instead.
- Test with: long URL with no spaces, line with `あ` glyphs at the boundary,
  emoji + ZWJ sequence at the boundary, ssh-rsa pubkey blob (~370 bytes,
  base64, no spaces).

**Phase:** P6 Editor & Markdown (also unblocks P2 SSH-key paste verification).

---

## Form Interaction

### F1 — Focus state stored in two places diverging after a re-render

**Symptom:** ISSUES.md "Account #8" — "If I select a different field and type
anything, the timezone field is selected and the typed character appears
there." Classic divergence: the form has a `focused_field` atom, *and* one of
the `TextInput` widgets has a `focused?: true` flag stored locally. After a
re-render, the local widget flag wins.

**Root cause:** `text_input.ex` was originally written stateful enough that it
remembers focus. When forms (`profile_form.ex`, `prefs_form.ex`,
`site_form.ex`, `limits_form.ex`) drive focus from a parent state struct, both
sources of truth fall out of sync after async events (validation, autosave,
PubSub refresh).

**Prevention:**
- Single owner: parent state's `focused_field` is the only truth. Make the
  TextInput render function take `focused?: boolean` as an explicit prop, and
  remove (or assert-empty) any internal focus state when rendered as part of a
  form.
- Test: drive a form through `:tab`, `:tab`, `:char "x"` and assert the `"x"`
  appears in the *second* field's value, not the first or the timezone field.

**Phase:** P2 Forms.

---

### F2 — Esc handler that consumes-then-rebroadcasts and loops

**Symptom:** ISSUES.md "Account #1" — "Escape does nothing." The likely fix is
to add an Esc handler in the form. The naive implementation calls back into
`Foglet.TUI.App` with the same `:escape` event so the App can close the screen,
which then re-routes Esc back to the screen, which routes it to the form...

**Root cause:** Esc has multiple legitimate meanings (close modal, blur field,
back to main menu). Without a documented routing order, fixes echo.

**Prevention:**
- Document the Esc precedence in `Foglet.TUI.App` module doc:
  modal > screen-local form (if a field is focused) > screen-level back nav.
- Each handler must return `:handled` or `:no_match` (the existing
  `account/profile_form.ex` already does this for keys; extend the shape so
  Esc is included). The App's screen dispatch must not rebroadcast a
  `:handled` event.
- Test: open Account → Profile, focus a field, press Esc, assert focus
  cleared *and* screen still on Account. Press Esc again, assert returned to
  Main Menu.

**Phase:** P2 Forms.

---

### F3 — Enter submit that re-fires on re-render after async completion

**Symptom:** ISSUES.md "Account #3" — "Profile screen says Enter to submit, but
there is no confirmation anything was submitted, and submitted values are gone
on re-entry." A worse failure mode of the same bug: the user presses Enter, a
`Command` runs, the screen re-renders with `submit_pending: true`, the next
keystroke that happens to be `:enter` (e.g. an Enter inside a confirmation
modal) re-routes here and fires a *second* submit.

**Root cause:** No idempotency on the submit command. Submit handler ignores
`pending?`/`in_flight?`.

**Prevention:**
- Form state has a `submit_state` enum: `:idle | :submitting | :saved | {:error, _}`.
  Only `:idle` accepts `:enter`. Render an inline "Saved." or "Saving…" affordance
  driven by this state — that *is* the submit feedback the bug asks for.
- Test: dispatch `:enter` twice in rapid succession, assert exactly one
  `Foglet.Accounts.update_user_profile/3` call (use `Mox` or
  `:meck`-style assertion).
- Persistence test: submit Profile → navigate to Main Menu → navigate back to
  Account → assert form fields show the saved values, not the defaults.

**Phase:** P2 Forms.

---

### F4 — Tab/Shift+Tab navigation that doesn't update the visible "selected" affordance

**Symptom:** ISSUES.md "Account #4, #5", "Sysop #3" — Preferences tab can't
select options, Shift+Tab doesn't go back, Site tab can't edit values. The
internal focused index moves but the rendered cursor/highlight doesn't, so the
user types into the wrong field (see F1).

**Root cause:** Render function pulls `focused_field` once at the top and
recomputes child props from a stale local; or the form group containing
checkbox/radio widgets doesn't pass `focused?` down at all.

**Prevention:**
- For each form widget (`text_input`, `checkbox`, `radio_group`, `button`, the
  timezone selector to be added), explicit `:focused?` prop passed every render.
- Snapshot test at each focus index: assert the focused widget's rendered
  output contains the focus marker (e.g. `▸` or reverse video) and *no other*
  widget on the screen contains that marker.
- Specifically test Shift+Tab from index 0 wraps to the last field (or stays at
  0 — pick one and document it, but be deterministic).

**Phase:** P2 Forms.

---

### F5 — Bracketed paste racing with single-keystroke routing (SSH key paste)

**Symptom:** ISSUES.md "Account #9" — pasting an SSH pubkey is impossible. With
bracketed paste enabled, the terminal sends `ESC [ 200 ~ ... ESC [ 201 ~`
around the paste. If `Foglet.TUI.Input` (or upstream Raxol) emits each byte as
a `:char` event without honoring the begin/end markers, the form sees ~370
individual keystrokes and partial routing (Tab, Enter, Esc) inside the pubkey
mangles state. If the paste is delivered as one big chunk but the form only
buffers `:char` for ASCII printable, the `+`, `=`, `/` in base64 are dropped.

**Root cause:** No paste-mode awareness in either `Foglet.TUI.Input` or in
`text_input.ex`'s `handle_event`.

**Prevention:**
- Detect `ESC [ 200 ~` / `ESC [ 201 ~` at the SSH input boundary (Raxol vendor
  fork, `lib/foglet_bbs/tui/input.ex` or the SSH CLI handler) and emit a single
  `{:paste, binary}` event.
- Forms append paste binaries directly to the focused field's buffer — no
  per-byte routing through the global key dispatcher.
- Test: feed a 372-byte ssh-ed25519 pubkey into the SSH Keys textarea inside a
  bracketed-paste sequence; assert the field buffer equals the pubkey string
  and no `:tab`/`:enter`/`:escape` side effects fired.

**Phase:** P2 Forms (SSH key tab specifically).

---

### F6 — TextInput cursor follow that breaks on multi-byte / wide / combining input

**Symptom:** ISSUES.md "Login #1" — cursor doesn't follow text being typed.
The fix-shaped-like-a-bug: maintain `cursor_col = String.length(value)`. For
ASCII this works; for `あ` (2 cells) or `é` (1 cell + combining mark, 1
codepoint) it desyncs.

**Root cause:** Cursor positioning is a display-cell concept, not a grapheme or
codepoint concept.

**Prevention:**
- Cursor column = `TextWidth.display_width(value_up_to_cursor)`.
- Test matrix: type `"a"`, `"あ"`, `"é"` (with combining), a ZWJ-joined family emoji sequence (e.g. man + ZWJ + woman + ZWJ + girl), and
  assert the rendered cursor cell equals the expected column for each.

**Phase:** P4 Auth Flows (this issue is filed under Login). Reuse the helper
in P2 Forms.

---

### F7 — "Submit was successful" silently true while persistence failed

**Symptom:** Profile submit command returns `:ok` because the message reached
the GenServer, but the changeset upstream was invalid and the function returned
`{:error, changeset}`. UI shows "Saved." Re-entering Account shows defaults
(see F3 part 2). This is a different shape of "no confirmation" than F3 — F3 is
about idempotency, this is about returning the wrong success.

**Root cause:** `Foglet.TUI.Command` callback handles the message-delivered
case, not the function's return value; or the handler pattern-matches `_` and
treats anything as success.

**Prevention:**
- Submit commands return one of: `{:ok, updated_struct}`, `{:error,
  Ecto.Changeset.t()}`, `{:error, atom()}`. Forms must pattern match all three;
  no fallthrough `_` clause.
- Test the unhappy path explicitly: invalid timezone string → submit → assert
  `submit_state == {:error, _}`, assert error message rendered, assert no
  `Repo` write occurred.

**Phase:** P2 Forms (Profile, Preferences, Site, Limits, status transitions).

---

## Tab Loading

### T1 — Mounting data-fetch in `render` instead of in a command/effect

**Symptom:** ISSUES.md "Sysop #6, #7, #8" — Boards/Limits/System tabs never
load. ISSUES.md "Sysop #1" — "press any key to load." A naive fix calls
`Foglet.Sysop.list_boards/1` directly in the render function. That re-fires on
every render, causing flicker, blanks, and DB hammer; or it fires once on
*input* (which is why "tab button loads it" but other keys don't).

**Root cause:** v1.3 separated render from effects; tab views written in a
hurry sometimes still gate loads on input handling instead of on a lifecycle
hook.

**Prevention:**
- Each Sysop sub-view (`boards_view.ex`, `limits_form.ex`, `system_snapshot.ex`,
  `users_view.ex`) implements an `on_enter/1` (or
  `init_load/1`) callback called by `Foglet.TUI.App` when the tab becomes
  active. The callback dispatches a `Foglet.TUI.Command` to load data; render
  is a pure function over `state`.
- Render functions must be free of `Foglet.Sysop.*` / `Foglet.Boards.*` /
  `Foglet.Repo.*` calls. Add a credo/test that grep-fails for those module
  prefixes inside the render section of each `*_view.ex` (or split render into
  a separate module without the alias available).
- Test: enter Sysop, switch tab to Boards using `:tab`/`:right`/`:1`-`:6`,
  assert the load command is dispatched exactly once per entry; switch
  away+back, assert it's dispatched again only if `force_refresh` requested.

**Phase:** P3 Sysop Loads.

---

### T2 — Async load completion arriving after the user switched tabs

**Symptom:** User opens Sysop → Boards (slow query), immediately presses `2` to
switch to Limits. Boards load eventually completes and a `{:loaded_boards,
result}` message arrives. The handler writes it into whatever `state.tab` is
currently — the Limits state — corrupting the Limits view.

**Root cause:** Load callbacks tag results with the message kind but not the
target tab; whoever's "current" gets the payload.

**Prevention:**
- All async loads carry the requesting tab key in the result message:
  `{:loaded, :boards, result}`. The `Sysop` state-reducer ignores any
  `{:loaded, tab, _}` whose `tab` doesn't match `state.active_tab` (or routes
  it to that tab's slot regardless — but never to "current").
- Test: simulate Boards load that takes 50ms, switch to Limits at 10ms,
  deliver Boards result at 60ms; assert Boards data lands in the boards slot,
  Limits state untouched, no flicker.

**Phase:** P3 Sysop Loads.

---

### T3 — Sysop Users status transition that throws on stale form state

**Symptom:** ISSUES.md "Sysop #10" — "Invalid status transition." A user in the
form is `:pending`. Operator clicks "Approve" → command dispatched. Before the
command completes, the operator selects a different user (now `:active`), and
the in-flight transition lands as `:pending → :active` but applies to the now-
selected `:active` user, hitting the locked status graph.

**Root cause:** Form references the *currently selected* user instead of the
user the action was launched against.

**Prevention:**
- Every status-transition command captures the target user's `id` *and*
  `current_status` at dispatch time. The Accounts boundary
  (`Foglet.Accounts.transition_user_status/3`) is already actor-aware; pass
  the snapshot too and let the boundary verify the from-status optimistically.
- Surface the locked-graph error as a friendly message with the actual
  from→to pair, not as the literal `"Invalid status transition."` string.
- Test: dispatch transition with a stale `from_status`, assert error
  `{:error, :status_transition_conflict, %{expected: ..., actual: ...}}`.

**Phase:** P3 Sysop Loads (specifically the Users tab fix).

---

### T4 — "Press any key to load" / `:tab` only — missing on-enter lifecycle hook

**Symptom:** ISSUES.md "Sysop #1" — "Only tab button loads it currently." This
means the load handler is wired into the tab-change event but not into the
screen-mount event, so first paint shows empty.

**Root cause:** No `on_mount`/`on_enter` callback in the screen lifecycle, only
`handle_event(:tab, …)`.

**Prevention:**
- Add a lifecycle hook to `Foglet.TUI.Screen` behaviour (or formalize the
  existing pattern) — when the App routes navigation to a screen, it calls
  `screen.on_mount(state, session)`. Sysop's `on_mount` selects the default
  tab and dispatches that tab's load command.
- Test: navigate from Main Menu → Sysop, assert the default tab's load
  command fires *without* any keystroke.

**Phase:** P3 Sysop Loads.

---

### T5 — Tabs (Boards, Limits, System) failing because Bodyguard denies before the load is attempted

**Symptom:** Tab "never loads" — but the real cause is that the actor-aware
load returns `{:error, :forbidden}` and the screen treats forbidden the same as
"still loading," showing a blank frame forever.

**Root cause:** Indistinguishable error states.

**Prevention:**
- Tab state is a tagged enum: `:not_loaded | :loading | {:loaded, data} |
  {:error, reason}`. Render every state distinctly; `{:error, :forbidden}`
  shows an honest "Insufficient role for this view" panel, not a blank.
- Test: load with a non-sysop actor, assert `{:error, :forbidden}` and the
  forbidden panel renders.

**Phase:** P3 Sysop Loads (also relates to A1 below).

---

## No-Email Reset Flow

### R1 — Token leaks into chrome / status bar

**Symptom:** Reset token (a high-entropy string) ends up in the breadcrumb,
status bar, or `Foglet.TUI.App`'s last-event log because the screen pushed it
there as transient state that some chrome widget surfaces.

**Root cause:** Reset screens often pass the token through screen state to
render an instruction line. If chrome reads "current screen state title,"
tokens can bleed in.

**Prevention:**
- Tokens live only in the screen-local state struct, never in
  `Foglet.TUI.App` state and never in fields read by `screen_frame.ex` or
  `breadcrumb_bar.ex`.
- Add a snapshot test that renders the no-email reset screen and asserts the
  token string does *not* appear inside the rendered breadcrumb row, status
  row, or command bar row — only in the body region.
- Bonus: log redaction — never `Logger.info` with a raw token.

**Phase:** P4 Auth Flows.

---

### R2 — Token-consume that doesn't enforce single-use, or single-uses on the wrong action

**Symptom:** ISSUES.md "Login #4" — "What happens when delivery_mode is
no-email?" The token-consume entry point is missing. A naive add: a screen
that accepts a token in a TextInput and unlocks the password reset form on
entry. If "consume" happens at form-load, an idle user with the screen open
has burned the token. If it happens at form-submit, the user can re-submit and
re-consume.

**Root cause:** Ambiguity about *when* a token is "used."

**Prevention:**
- Two-step at the Accounts boundary: `Foglet.Accounts.verify_reset_token/1`
  returns `{:ok, user}` *without* consuming. The actual reset call,
  `Foglet.Accounts.reset_password_with_token/3`, consumes inside the same
  `Repo.transact/1` that updates the password (atomic).
- Test the race: two concurrent `reset_password_with_token` calls with the
  same token, assert exactly one succeeds and one returns
  `{:error, :token_already_consumed}` (or similar). Use `Task.async_stream`
  or `Ecto.Adapters.SQL.Sandbox` shared mode.
- Test that opening the reset screen does NOT consume the token (verify it
  again after rendering and assert the token still verifies).

**Phase:** P4 Auth Flows. Pair with `Foglet.Accounts` boundary update; this is
*not* purely UI (see W3 below for the inverse pitfall).

---

### R3 — Reset email content cropped at small terminals because the panel renders statically

**Symptom:** ISSUES.md "Login #4" — "The reset email message gets cropped off
the screen on smaller terminals, and the reset password flow just ends." The
screen captures terminal size at mount and never re-flows on `SIGWINCH` /
Raxol resize event.

**Root cause:** Resize forwarded to App but not to inactive screens; or the
screen reads `state.size` once at mount.

**Prevention:**
- Render reads size every paint from the App's current `viewport` field;
  resize events trigger a re-render through the normal Raxol lifecycle. No
  caching of "max width" in screen-local state.
- Test: render at 64x22, simulate resize to 132x50, assert all reset-email
  lines now visible without scroll. Inverse: render at 132x50, resize to 64x22,
  assert content paginates or scrolls with a visible affordance — never just
  silently truncates.

**Phase:** P4 Auth Flows.

---

### R4 — No-email mode that quietly does the wrong thing

**Symptom:** Delivery mode is `:no_email`. User clicks "Forgot password." A
naive flow either (a) silently does nothing, (b) shows "check your email" for
an inbox that doesn't exist, or (c) drops to a token-entry form without
explaining where the token comes from.

**Root cause:** Branching on `delivery_mode` only at the email-send call site,
not at the UX text and flow.

**Prevention:**
- `Login.forgot_password` flow reads
  `Foglet.Config.get!(:delivery_mode)` and branches *the rendered copy*: in
  `:no_email`, the screen says "Ask a sysop to run `mix
  foglet.account_password_reset` and paste the token below" with a token-entry
  field; in `:email`, the screen says "Check your email for a reset link" with
  no token-entry field.
- Test both delivery modes via `Foglet.Config.put!/3` in a test fixture and
  assert the rendered copy and field set differ.

**Phase:** P4 Auth Flows.

---

## Workflow Hygiene

### W1 — Fixing a Sysop tab in isolation and breaking the Account/Moderation analog (shared INVITES)

**Symptom:** ISSUES.md "Sysop #12, #13" — Invites tab "looks fucked up." The
fix lands in `lib/foglet_bbs/tui/screens/sysop/state.ex` or the Sysop invites
view, but the actual rendering primitives live in
`lib/foglet_bbs/tui/screens/shared/invites_*.ex` which Account and Moderation
also call. Repaginating the columns in Sysop without re-running Account and
Moderation regresses both.

**Root cause:** Shared-primitive boundary is real but easy to forget. The
v1.1 milestone explicitly built `InvitesSurface` *to* share.

**Prevention:**
- Any change inside `lib/foglet_bbs/tui/screens/shared/**` triggers a test
  matrix: smoke-render Account/Invites, Moderation/Invites, Sysop/Invites at
  64x22 and 80x24. Make this matrix a single test file
  (`test/.../shared/invites_surface_matrix_test.exs`) that runs all three
  surfaces with the same fixtures.
- Code review checklist: did this PR touch `shared/`? If yes, were all three
  call sites verified?

**Phase:** PX cross-cutting; especially watch in P1 (Invites table layout) and
P2 (invite selection/actions).

---

### W2 — Theme override applied at one widget that overrides downstream

**Symptom:** ISSUES.md "Main Menu #4, #6, #7" — navigation keys not accent
colored, theme not applied to navigation/oneliners. The fix-shaped-like-a-bug:
hardcode an ANSI color in the navigation widget. This breaks
`Foglet.TUI.Theme` slot routing for any future theme switch and overrides
operator-console mode in subtle ways downstream.

**Root cause:** Skipping the theme indirection because "this one widget needs
exactly accent."

**Prevention:**
- Per AGENTS.md: "Route colors through `Foglet.TUI.Theme`, pass theme
  explicitly." Disallow raw color literals (`IO.ANSI.cyan/0`, `"\e[36m"`,
  `Raxol.Style.color/1`) inside `lib/foglet_bbs/tui/widgets/**` and
  `lib/foglet_bbs/tui/screens/**`. Add a test that grep-fails for these
  patterns; allowlist `lib/foglet_bbs/tui/theme.ex` and `theme/**`.
- If the theme is missing a slot, *add the slot* — the theme already covers
  facelift widget states per Phase 17.
- Test: render Main Menu with the default theme and the operator-console
  theme; assert navigation key glyphs use `theme.accent.fg`, not a hardcoded
  value.

**Phase:** P5 Main Menu Chrome.

---

### W3 — Re-running migrations or touching data when the fix is purely UI

**Symptom:** A "fix the Boards tab" PR adds a migration to backfill some flag,
because the dev assumed the empty render meant missing data. The actual cause
was render/load wiring (T1, T5). Now the milestone has a schema change
shipped with no domain test backing it.

**Root cause:** Confusing "blank UI" with "missing data."

**Prevention:**
- Phase intake check (mentally / in plan doc): is this a UI bug, a domain
  bug, or both? Default assumption for v1.4 is UI-only unless the issue
  description explicitly names a context (`Foglet.Accounts`,
  `Foglet.Boards`, etc.) function returning wrong data.
- Migration count assertion in CI: `mix ecto.migrations` count at v1.4 start
  vs. PR — if the count diverges, the PR description must explicitly justify
  the migration. Most v1.4 fixes should add zero migrations.
- Counter-example: the no-email token-consume entry point (R2) *does*
  legitimately need a domain change (`Foglet.Accounts.verify_reset_token/1`).
  Identify these explicitly in plans.

**Phase:** PX cross-cutting (planning gate).

---

### W4 — Test fixtures that lean on `Process.sleep/1` (banned by AGENTS.md)

**Symptom:** A test for the new on-enter load (T1) sleeps 50ms then asserts.
This ships, gets flaky on CI, gets `@tag :skip`'d, and the regression returns.

**Root cause:** Fastest way to "make a test pass" — and AGENTS.md
specifically calls this out as banned.

**Prevention:**
- Synchronize through monitors, explicit messages from the command
  callback, or `:sys.get_state/1` against a supervised process. Pattern
  already used by `test/foglet_bbs/sessions/supervisor_test.exs`.
- Add a test that grep-fails on `Process.sleep` introductions in *new* test
  files for v1.4. (The existing `Process.alive?` calls in
  sessions/supervisor tests are pre-existing and intentionally annotated;
  don't add more.)
- For `Foglet.TUI.Command` async results, the command harness should expose
  a synchronous-in-tests mode (a `dispatch_sync/2` or a deterministic test
  scheduler).

**Phase:** PX cross-cutting (any phase that adds tests).

---

### W5 — Skipping `mix precommit` because "it's just UI"

**Symptom:** A commit lands that compiles locally but fails Credo, Sobelow, or
Dialyzer in CI. AGENTS.md is explicit: run `mix precommit` (compile with
warnings as errors, formatter, Credo, Sobelow, Dialyzer) and fix any issues
before commit.

**Root cause:** UI-only PRs feel low-risk. Dialyzer cares about pattern
exhaustiveness in form `handle_key` reducers (F4) and submit-result handling
(F7).

**Prevention:**
- Plan execution flow ends with `rtk mix precommit` per phase, not per
  milestone. Every plan's "Done" definition includes precommit-clean.
- Pre-push hook (or CI gate on PR) runs `rtk mix precommit`; failing is a
  hard block.
- Rationale: F7 (submit result handling) without exhaustive matches is
  exactly what Dialyzer catches before users do.

**Phase:** PX cross-cutting (every phase).

---

### W6 — "Fix" lands without screen-level visual verification (the very debt v1.3 closed)

**Symptom:** A bug is fixed by reading the code, writing a unit test, and
calling it done — but the v1.3 close-out explicitly named "Human SSH/TUI
checks remain for Chrome V2 visual flow" as deferred. v1.4 inherits that
debt for the screens it touches and risks deferring it again.

**Root cause:** Visual verification is uncomfortable to schedule and easy to
defer to "next milestone."

**Prevention:**
- Each phase plan includes a SSH/TUI verification step run against a real
  terminal (iTerm/Alacritty/Kitty) at 64x22 *and* 80x24, with a written
  observation note added to the phase's STATE.md.
- A phase isn't "Done" until: precommit-clean + automated tests pass + human
  SSH verification recorded.
- Bonus: take a screenshot or `script(1)` capture of the fixed screen and
  link it from the plan. This costs ~30s per phase and prevents regression.

**Phase:** PX cross-cutting (every phase).

---

## Authorization & Domain

### A1 — Fixing a Sysop tab's *visibility* but not the underlying Bodyguard policy

**Symptom:** ISSUES.md "Sysop #6/#7/#8" gets fixed by enabling tab loads.
Someone notices a non-sysop role can navigate to Sysop directly and see the
content, because the tab visibility was assumed to be the security boundary.

**Root cause:** AGENTS.md is explicit: "Hidden or disabled UI is never
authorization; context mutations must still check policy." Easy to forget when
the bug presentation is "this UI doesn't load."

**Prevention:**
- Every Sysop tab's load command goes through
  `Bodyguard.permit/4` against `Foglet.Authorization` first, with the
  `:site` scope. Render path uses `Bodyguard.permit?/4` only for advisory
  rendering (T5 forbidden panel).
- Test: as a non-sysop actor, dispatch each tab's load command directly
  (bypassing UI), assert `{:error, :forbidden}`. As a sysop, assert success.
- Don't conflate "tab is in the UI" with "tab is authorized."

**Phase:** P3 Sysop Loads, also P5 (Account/Moderation differences in invite
visibility).

---

### A2 — Inadvertently changing scope shapes (`:site`, `{:board, board_id}`)

**Symptom:** A polish change to the moderation Boards tab tweaks how a
moderator's allowed boards are filtered, accidentally introducing a new scope
shape (`{:moderator, board_ids}` or similar). Future code that pattern-matches
the canonical pair breaks silently.

**Root cause:** v1.1 explicitly froze the scope shapes; touching scope-shaped
data in a polish PR is tempting if a filter "feels wrong."

**Prevention:**
- Per AGENTS.md: "Stable scope shapes are `:site` and `{:board, board_id}`."
  Add a Dialyzer spec on `Foglet.Authorization.scopes_for/2` that types the
  return as `[:site | {:board, pos_integer()}]` so any new shape is a type
  error.
- Test: assert `Foglet.Authorization.scopes_for/2` for each role only
  returns shapes from the allowed set.

**Phase:** PX cross-cutting (any phase that touches authorization or
moderation filtering).

---

### A3 — Editing schema/changeset to make a UI form "easier" instead of fixing the form

**Symptom:** ISSUES.md "Account #6" — no way to clear/replace the timezone.
The fix-shaped-like-a-bug: add `timezone` to the changeset's `cast/3` with
explicit nil acceptance and call it done. The actual issue is that the form
widget needs a selectable list (or a clear-on-empty-submit affordance).

**Root cause:** AGENTS.md: "Programmatically set foreign keys on structs
before changeset construction; do not add fields such as `user_id` to `cast/3`
just to make callers convenient." Same principle for *any* schema field —
don't loosen the changeset to paper over a UI gap.

**Prevention:**
- Plan review: if a v1.4 PR touches a changeset, the plan must justify why a
  UI-only fix won't work. Most v1.4 fixes should leave changesets untouched.
- Test: timezone field accepts canonical zone names from
  `Tzdata.zone_list/0` (or whichever the project uses), rejects garbage,
  accepts a sentinel "" or `nil` only if the product spec says timezone is
  optional. This is a domain decision, not a form decision.

**Phase:** P2 Forms (timezone selector).

---

### A4 — Read pointer / monotonic state regressed by a "looks better" UX fix

**Symptom:** ISSUES.md "Boards #2, #3" — Enter on category should
expand/collapse, selecting a board should navigate. While fixing navigation,
someone "helpfully" advances a thread/post read pointer based on view, but
not via the owning context.

**Root cause:** AGENTS.md: "Read pointers are monotonic persisted user state.
Advance them through the owning context and keep UI-local scroll/read state
separate." Easy to forget when the UX fix is "make Enter do the obvious
thing."

**Prevention:**
- Boards screen state stores UI-local expand/collapse state only. Never
  writes to `Foglet.Threads`/`Foglet.Posts` read pointers.
- Test: expand/collapse a category 10 times, assert no DB writes occurred
  (use `Ecto.Adapters.SQL.Sandbox` query log, or a counting `Repo` proxy).

**Phase:** P7 Boards Interaction.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Hardcode `IO.ANSI.cyan/0` instead of theme slot | Fix accent-color bug in 1 line | Breaks future theme switch; conflicts with operator-console mode | **Never** — extend the theme slot |
| Add `Process.sleep(50)` in a test | Test passes locally | Flaky on CI; AGENTS.md banned | **Never** — synchronize on monitors / messages |
| Skip `mix precommit` because "UI only" | Faster commit | Dialyzer/Credo regressions; F7-shaped bugs | **Never** — UI PRs *especially* benefit from Dialyzer |
| Read DB inside a render function | Unblocks tab load bug | T1: re-fires every paint; DB hammer; flicker | **Never** — use `Foglet.TUI.Command` |
| Loosen a changeset to accept whatever the form sends | Form "works" | A3 schema drift; lost validation | **Never** — fix the form |
| Snapshot-test only at 80x24 | Tests pass | L2 64x22 regression | **Never** — both sizes minimum, per `PROJECT.md` Constraints |
| Treat `{:error, :forbidden}` as `:loading` | Silent fallback | T5 indistinguishable failure modes | **Never** — distinct render branches |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Vendored Raxol input pipeline | Treating bracketed paste bytes as individual key events | Detect `ESC[200~`/`ESC[201~` at SSH boundary, emit single `{:paste, binary}` |
| `Foglet.TUI.Theme` | Reading colors directly via `IO.ANSI.*` in widgets | Pass theme explicitly into render; use slots |
| `Foglet.TUI.TextWidth` | Using `String.length` for column math after upgrading a widget | Use `display_width/1`, `truncate/2`, and the wrap helper |
| `Foglet.Config` runtime delivery_mode | Branching only at email-send call site | Branch UX text and field set too (R4) |
| `Foglet.Accounts` token consume | Consuming on screen mount instead of at password reset | Two-call boundary inside `Repo.transact/1` (R2) |
| `Bodyguard.permit/4` vs `permit?/4` | Using `permit?/4` as the security gate | `permit/4` for mutations; `permit?/4` only for advisory render (A1) |

## "Looks Done But Isn't" Checklist

- [ ] **Tab-row glyph fix:** Verify at 64, 65, 66, 80, 81 columns — off-by-one boundary cases are common.
- [ ] **Submit confirmation:** Visit Account, edit, submit, navigate away, navigate back — values must persist (F3 part 2).
- [ ] **Esc handler:** Verify Esc with field focused (clears focus) AND with no field focused (back-nav) — both paths.
- [ ] **Sysop tab load:** Verify load happens on first paint, not just on tab switch (T4) — open Sysop, assert no keystroke needed.
- [ ] **No-email reset:** Verify with `Foglet.Config.put!(:delivery_mode, :no_email, _)` — token-entry field appears, instructions name the Mix task (R4).
- [ ] **Reset email render:** Resize from 132x50 to 64x22 mid-flow — content must remain accessible (R3).
- [ ] **SSH key paste:** Paste an actual ed25519 pubkey via SSH (not a paste-buffer in tests) — confirm bracketed paste works end-to-end (F5).
- [ ] **Markdown render:** Render a post with fenced code containing blank lines — assert no whitespace collapse inside fence (L4).
- [ ] **Cursor follow:** Type `あ`, `é` (combining), and ZWJ emoji — cursor cell must match `TextWidth.display_width` (F6).
- [ ] **Invites table:** Render with shared `InvitesSurface` from Account, Moderation, AND Sysop — all three must look correct, not just Sysop (W1).
- [ ] **Forbidden tab:** As a non-sysop, dispatch a Sysop tab load directly — must return `{:error, :forbidden}`, not blank-as-loading (T5, A1).
- [ ] **`mix precommit`:** Run on every phase before close, not just at milestone end (W5).

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| L1 width assumption regressed a column | LOW | Audit grep for `String.length`/`String.slice`/`byte_size` in touched widgets; replace with `TextWidth` helpers; add fixture test |
| L4 markdown collapse broke fenced code | MEDIUM | Add property test first to lock the bug, then move whitespace collapse from token-stream to inline-runs only |
| F1 focus divergence | MEDIUM | Audit every form widget for internal focus state; remove or assert-empty when used inside a parent-driven form |
| F5 paste broken | MEDIUM | Add bracketed-paste detection at SSH input boundary; add `{:paste, binary}` event; route to focused field directly |
| R2 token consume race | HIGH | Move consume into a `Repo.transact/1` with the password update; revoke any tokens issued in the buggy window via Mix task |
| T2 cross-tab payload corruption | LOW | Tag every async result with the requesting tab key; route in reducer |
| W1 shared `InvitesSurface` regression | LOW | Run the cross-surface matrix test (Account+Moderation+Sysop); revert and re-fix in `shared/` |
| A1 UI-only authorization | HIGH | Add `Bodyguard.permit/4` to every Sysop load command; test with non-sysop actor; audit log to see if any data leaked |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| L1 Width helpers bypassed | P1 Layout | Grep test fails for `String.length` etc. in `tui/`; `TextWidth` regression test with multi-byte glyphs |
| L2 64x22 minimum regressed | P1 Layout | Snapshot tests at 64x22 AND 80x24 for every touched screen |
| L3 Tab-row trailing glyph | P1 Layout | Widget test: tab row's rightmost column equals frame's `│`, not duplicate corner |
| L4 Markdown re-flow drops fence content | P6 Editor & Markdown | Property test: fenced code byte-equal after render-strip |
| L5 Word wrap mid-grapheme | P6 Editor & Markdown | Wrap helper tests with `あ`, ZWJ emoji, ssh-rsa pubkey |
| F1 Focus divergence | P2 Forms | `:tab :tab :char "x"` lands in field 2 |
| F2 Esc echo loop | P2 Forms | Esc precedence documented; handlers return `:handled`/`:no_match` |
| F3 Submit double-fire | P2 Forms | `:enter :enter` triggers exactly one boundary call; `submit_state` enum drives feedback |
| F4 Tab/Shift+Tab visible affordance | P2 Forms | Per-index focus snapshot; only one widget shows focus marker |
| F5 Bracketed paste race | P2 Forms (SSH Keys) | 372-byte pubkey paste produces clean field buffer |
| F6 Cursor follow multi-byte | P4 Auth Flows (cursor), reused P2 | Cursor cell == `TextWidth.display_width(prefix)` for `a`/`あ`/`é`/ZWJ |
| F7 Submit "success" while persistence failed | P2 Forms | Unhappy-path test; no fallthrough match in submit handler |
| T1 Data fetch in render | P3 Sysop Loads | Grep test fails for `Foglet.Sysop.*`/`Foglet.Repo.*` in `*_view.ex` render section |
| T2 Cross-tab payload | P3 Sysop Loads | Concurrent tab-switch test with delayed result |
| T3 Stale status transition | P3 Sysop Loads (Users) | Snapshot from-status at dispatch; conflict surfaces friendly error |
| T4 Missing on-mount load | P3 Sysop Loads | Navigate to Sysop, assert load fires with zero keystrokes |
| T5 Forbidden treated as loading | P3 Sysop Loads | Tagged enum; forbidden panel rendered for non-sysop actor |
| R1 Token in chrome | P4 Auth Flows | Snapshot asserts token absent from breadcrumb/status/command rows |
| R2 Token consume race / wrong moment | P4 Auth Flows | Concurrent reset test (one wins); render-screen test (no consume) |
| R3 Reset email cropped, no resize | P4 Auth Flows | Resize 64x22 ↔ 132x50, content remains accessible |
| R4 No-email mode silent failure | P4 Auth Flows | Both delivery modes tested; UX copy and field set differ |
| W1 Shared INVITES regression | PX (especially P1, P2) | Cross-surface matrix test (Account+Moderation+Sysop) |
| W2 Theme override hardcoded color | P5 Main Menu | Grep test fails for `IO.ANSI.*` / raw escapes in widgets/screens |
| W3 Migration when fix is UI | PX planning gate | Migration count delta must be justified in plan |
| W4 `Process.sleep` in tests | PX every phase | Grep test fails for new `Process.sleep` introductions |
| W5 Skip `mix precommit` | PX every phase | Phase-done definition includes precommit-clean |
| W6 No SSH/TUI human verification | PX every phase | Phase-done definition includes 64x22 + 80x24 SSH/TUI observation note |
| A1 UI-only authorization | P3 Sysop Loads | Non-sysop actor calling tab load command returns `{:error, :forbidden}` |
| A2 Scope shape change | PX cross-cutting | Dialyzer spec on `scopes_for/2` enumerates allowed shapes |
| A3 Loosen changeset for UI | P2 Forms (timezone) | Plan-review gate: changeset edit must be justified |
| A4 Read pointer regressed by UX fix | P7 Boards | Sandbox query log: expand/collapse causes 0 writes |

## Sources

- `/Users/brendan.turner/Dev/personal/foglet_bbs/AGENTS.md` — testing finish line, banned `Process.sleep`/`Process.alive?`, `mix precommit`, contexts as boundaries, theme passing, scope shapes, read pointers
- `/Users/brendan.turner/Dev/personal/foglet_bbs/ISSUES.md` — the 37 v1.4 bugs grounding every pitfall
- `/Users/brendan.turner/Dev/personal/foglet_bbs/.planning/PROJECT.md` — 64x22 hard minimum, v1.3 deferred items (chrome verification, Main Menu PubSub refresh, glyph contrast)
- `/Users/brendan.turner/Dev/personal/foglet_bbs/.planning/MILESTONES.md` — v1.3 close-out (`TextWidth`, Chrome V2, operator-console primitives, shared `InvitesSurface`)
- `/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex` — confirmed `TextWidth` is already routed through chrome (so widgets that bypass it are out of pattern)
- `/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/screens/account/profile_form.ex`, `prefs_form.ex` — confirmed `:tab/:shift_tab/:enter/:escape` already in `handle_key` guards (so the "Esc does nothing" bug is in routing, not in matching)
- `/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/screens/sysop/{boards_view,limits_form,system_snapshot,users_view}.ex` — confirmed each tab is a separate module (so the on-mount lifecycle hook in T4 has a clean place to live)
- `/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/screens/shared/invites_*.ex` — confirms W1 cross-surface concern is real (three callers of one shared surface)

---
*Pitfalls research for: v1.4 Post-Facelift Polish & Bug Fixes*
*Researched: 2026-04-26*
