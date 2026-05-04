# Login Recovery TUI UX Specification (FOG-558 / FOG-559)

Status: design handoff for the canonical FOG-558 integration branch.
Owner: TUI UX Designer.
Branch: `fog-558-login-recovery-consolidation`.
Baseline inspected: `4074b426af8474829fc7ccaee248a0c2c96f2d13`.

## Source verification

Current source still implements two separate recovery surfaces:

- `lib/foglet_bbs/tui/screens/login.ex` routes `:reset_request` and `:reset_consume` as separate substates, while task results are correctly routed by task atom (`:reset_request`, `:reset_token`) rather than current substate.
- `lib/foglet_bbs/tui/screens/login/render.ex` renders `render_reset_request/2` and `render_reset_consume/2` as separate full-screen views with separate command bars.
- `lib/foglet_bbs/tui/screens/login/reset_request.ex` owns reset-request validation and email/no-email/sysop-assisted result messaging.
- `lib/foglet_bbs/tui/screens/login/reset_consume.ex` owns token/password field focus, password mismatch handling, token consumption, and generic non-enumerating token errors.
- `lib/foglet_bbs/tui/screens/login/state.ex` currently builds independent state maps for request and token-consume substates.
- `lib/foglet_bbs/tui/SCREEN_CONTRACT.md` keeps screen rendering pure and requires async work to flow through `Foglet.TUI.Effect.task/3`.
- `lib/foglet_bbs/tui/widgets/README.md` documents the command-bar priority contract and available themed input/tabs/chrome widgets.

The design below consolidates the visible user surface without changing the password-reset domain/security model. Implementation should preserve the existing task atoms and their async result semantics.

## User goal

A logged-out caller who cannot sign in should see one recovery place that answers two common situations:

1. I need reset instructions or a sysop-assisted token.
2. I already have a reset token and need to set a new password.

The user should not have to bounce through the login menu, remember that `F` means one half of recovery and `T` means the other half, or understand implementation names such as request/consume.

## Failure modes to design against

- Users request a token, then cannot find where to enter it.
- Users already holding a sysop token choose the wrong screen first.
- Side-by-side panes become cramped, clipped, or border-broken on SSH clients around 80 columns or narrower.
- Left/Right pane switching steals cursor movement from a text field when a user expects to edit within the field.
- The command bar mechanically lists every key and becomes noisy at the exact moment the user needs one primary action.
- Async reset-request or reset-token results arrive after the active pane changes and update the wrong visible area or erase the other pane's draft unexpectedly.
- Copy explains around an awkward flow instead of making the flow discoverable.

## Interaction alternatives considered

### Alternative 1: true split pane at wide/normal widths, stacked section fallback

Flow: login menu opens one Recovery screen. Wide/normal layouts show a left request pane and a right token pane together. The active pane has accent/bold treatment and owns field focus. Cramped layouts stack request above token and keep one active section at a time.

Pros:
- Best matches the desired mental model: two halves of one recovery task are visible at once.
- Users who already have a token can immediately see the token form without backing out of a request flow.
- Users who requested a token can see the next step in the same place.
- Wide terminals feel composed and intentional without adding another navigation level.

Cons:
- Requires careful width budgeting and responsive fallback.
- Needs a deliberate pane-switch key rule so Left/Right do not surprise text-field editing.
- More reducer/render state than simply renaming one existing screen.

### Alternative 2: tabs for Request Token / Use Token at all widths

Flow: Recovery screen shows a tab bar. Left/Right switches tabs. Only the selected tab's form is visible.

Pros:
- Simple width behavior at 80 columns and cramped sizes.
- Matches existing tab widget vocabulary and avoids side-by-side wrapping problems.
- Clear active state if tabs are rendered well.

Cons:
- Hides one half of the flow at all widths, reducing the benefit of consolidation.
- Users may still miss that the hidden tab is the next step unless the intro and keybar carry more explanatory weight.
- Turns a two-part recovery sequence into a mini navigation system.

### Alternative 3: single wizard-style choice then form

Flow: Recovery screen first asks `Request a token` or `Use a token`; Enter opens one form. Back returns to the choice.

Pros:
- Lowest visual density.
- Safest for very small terminal sizes.
- Easy to implement by reusing existing substates.

Cons:
- Least discoverable for the sequence. It still asks the user to choose a mode before seeing what information is required.
- Adds an extra step for users who already know what they need.
- Feels like renamed separate screens rather than one coherent recovery surface.

## Recommendation

Use Alternative 1: split pane when space allows, with a deliberate one-active-section compact fallback.

Why this is good for Foglet users:

- It makes the sequence visible instead of explanatory: request a token on the left if needed, enter a token on the right if you already have one.
- It supports both likely paths without a detour through the login menu.
- It keeps the old-network terminal feel: two plain panels, visible fields, no modal wizard unless a future security step requires it.
- It avoids magic values and hidden conventions. Users type only their email, token, and new password.
- It preserves a credible small-terminal story by falling back to one active section instead of forcing squeezed panes.

Content Designer should review final shipped wording, but implementation should not replace the interaction with helper text alone. The better UX is the visible paired surface plus clear active focus.

## Breakpoints and layout regions

### Frame contract

Use the existing `ScreenFrame` chrome:

- Breadcrumb/title: `Foglet > Login > Recovery` or equivalent within current frame conventions.
- Body: unified recovery content.
- Command bar: restrained, active-pane-aware commands.

### Wide layout: 100 columns and up

Use two bordered panes in one row.

Suggested body region after frame/chrome at 100x24:

```text
Recovery
Request a token if you need one. Use a token here if you already have one.

┌ Request reset ───────────────────────┐  ┌ Use reset token ───────────────────────┐
│ Email                                │  │ Token                                  │
│ > name@example.test                  │  │   ABCD-EFGH-IJKL                      │
│                                      │  │ New password                           │
│ If email is off, Foglet will show    │  │   ********                             │
│ sysop-assisted instructions here.    │  │ Confirm password                       │
│                                      │  │   ********                             │
└──────────────────────────────────────┘  └────────────────────────────────────────┘
```

Region rules:

- Outer body width is terminal width minus frame padding/borders.
- Two panes use a stable 50/50 split with a fixed 2-column gutter.
- Minimum useful pane inner width: 32 columns. Below that, do not render side by side.
- Pane titles: `Request reset` and `Use reset token` are UX labels; Content Designer may refine final copy.
- Active pane: accent/bold title and border. Inactive pane: normal border and dim/non-bold labels. Do not reverse the whole pane; that creates noisy blocks and can reduce readability in low-color terminals.
- The focused field inside the active pane keeps the existing label-accent pattern and visible cursor behavior from `TextInput`.
- Inactive pane fields remain visible but not focused. Existing values should remain visible/masked according to field type.

### Normal layout: 80 to 99 columns

Use the same two-pane idea only if both pane inner widths remain at least 32 columns after chrome and gutter. At exactly 80 columns this will likely be too tight once frame padding is included, so implementation should prefer the compact fallback unless render evidence proves the panes remain clean.

If side-by-side is used at 80-99 columns:

- Remove nonessential helper lines inside panes.
- Keep each label on its own line above the input when horizontal label+input rows would crowd.
- Wrap message/error text inside its pane; never allow messages to widen the pane or overflow borders.
- Keybar should show only `Tab Field`, `←/→ Pane`, active submit, and `Esc Back` as width allows.

### Compact layout: below split threshold, including 64x20

Use one active section at a time with a compact section switcher, not squeezed panes.

Suggested compact body:

```text
Recovery
Request a token if you need one. Use a token if you already have one.

[ Request reset ]  Use token

Email
> name@example.test

If email is off, Foglet will show sysop-assisted instructions here.
```

When token section is active:

```text
Recovery
Request a token if you need one. Use a token if you already have one.

Request reset  [ Use token ]

Token
> ABCD-EFGH-IJKL
New password
  ********
Confirm password
  ********
```

Compact rules:

- Render only the active form's fields. The inactive section appears only in the two-item switcher.
- Left/Right changes active section from the switcher/form context, subject to the text-input cursor rule below.
- Tab/Shift+Tab stays inside the active form. It does not cross from request to token form.
- Keep helper text to one or two wrapped lines under the section. Long sysop/no-email messages get a bounded message block and may scroll only if a future implementation adds a viewport.
- Minimum usable target: 64x20. If terminal size is below the app's global SizeGate minimum, the global too-small handling should win.

## Text, wrapping, and overflow policy

- Intro: max two wrapped lines at compact widths; place above panes/section switcher.
- Labels: never truncate field labels. If label+input would exceed region width, stack label above input.
- Inputs: cap display width to pane/section inner width. Tokens and emails may horizontally scroll inside `TextInput`; they must not overflow the pane.
- Password fields: keep masked rendering exactly as today.
- Errors/messages: wrap to the active pane/section inner width. Preserve generic non-enumerating token error semantics.
- No-email/sysop-assisted message: in split layout, show under the request pane. In compact layout, show under the request section. If multiple sysop emails exceed space, wrap by actual width; do not expose hidden horizontal overflow.
- Success after reset-token consumption: return to login menu with cleared recovery state, matching current behavior unless CTO/product chooses a logged-in auto-route separately.

## Focus and keyboard model

### State model

Implementation should move from two visible substates to one recovery substate, for example:

```elixir
%{
  sub: :recovery,
  active_pane: :request | :token,
  request: %{
    identifier_input: %TextInput{},
    error: nil | String.t(),
    message: nil | String.t(),
    message_category: nil | atom(),
    submitting?: boolean()
  },
  token: %{
    focused_field: :token | :password | :password_confirmation,
    token_input: %TextInput{},
    password_input: %TextInput{},
    password_confirmation_input: %TextInput{},
    error: nil | String.t(),
    submitting?: boolean()
  }
}
```

A different shape is acceptable if the reducer preserves independent drafts/messages for both forms and the async task-result routing remains by task atom.

### Left/Right pane switching

Do not let Left/Right steal normal text editing when the focused `TextInput` can use those keys for cursor movement.

Recommended rule:

- `Ctrl+Left` / `Ctrl+Right` always switch panes when supported by the input parser.
- Plain `Left` / `Right` switches panes only when the focused text input is at the corresponding edge:
  - `Left` on the first cursor position switches to the left/request pane.
  - `Right` on the end cursor position switches to the right/token pane.
  - Otherwise the key is forwarded to the focused input for cursor movement.
- If the current `TextInput` state does not expose cursor position cleanly, implementation should not guess. Use `Ctrl+Left` / `Ctrl+Right` as the reliable pane switch and show that in the keybar as `Ctrl+←/→ Pane`; leave plain arrows to text editing.

This preserves expected terminal editing behavior while still honoring the issue's desire for Left/Right pane switching when it does not conflict.

### Tab and Shift+Tab

- Request pane: Tab and Shift+Tab keep focus on the single email field and do nothing visible.
- Token pane: Tab moves `token -> password -> confirm -> token`; Shift+Tab reverses that cycle.
- Tab never switches panes. Users should not unexpectedly jump from entering an email to a token field.

### Enter behavior

- Request pane: Enter submits reset request if not already submitting.
- Token pane: Enter submits reset token/new password if not already submitting.
- If password and confirmation differ, show the existing non-domain-call mismatch error and keep focus in the token pane.
- Enter is inert while the active form is submitting, or it preserves existing task de-duplication behavior if already implemented elsewhere.

### Esc / Cancel / Back behavior

- Esc leaves the unified Recovery screen and returns to the Login menu.
- Esc clears recovery fields and messages, matching today's separate-screen cancel behavior, unless product explicitly asks to preserve drafts across back navigation.
- Ctrl+C remains the terminal fallback from `Login.update/3`; do not advertise it in the keybar.

### Menu entry behavior

The login menu should have one recovery entry instead of separate `Forgot password` and `Enter reset token` entries.

Recommended menu key:

- `F` / label `Recovery` or `Reset password`.

Do not keep a separate visible `T Enter reset token` command after consolidation; that recreates the split mental model. Content Designer may choose the final menu label.

## Command bar rules

Use grouped command-bar descriptors with priorities aligned to `Chrome.CommandBar` guidance.

Wide/normal recovery command bar:

- Field group: `Tab Field` and `Shift+Tab Prev` only when the active pane has multiple fields; for request pane, omit Shift+Tab or show no field group if width is tight.
- Pane group: `Ctrl+←/→ Pane` or `←/→ Pane` depending on the implemented conflict-safe rule.
- Actions group, request active: `Enter Request reset`, `Esc Back`.
- Actions group, token active: `Enter Use token`, `Esc Back`.

Priority guidance:

- `Esc Back`: priority 0.
- Active submit: priority 5.
- Pane switch: priority 10.
- Field cycling: priority 10.
- Secondary explanatory hints: omit rather than crowding the keybar.

Compact command bar:

- Request active: `Enter Request`, pane switch, `Esc Back`.
- Token active: `Tab Field`, `Enter Submit`, pane switch, `Esc Back`.
- If width is severely constrained, keep active submit and `Esc`; drop pane/field hints before dropping cancel.

## Empty, loading, submitting, and error states

This screen does not need an initial loading state because both forms are local until submitted.

Submitting request:

- Keep both panes visible.
- Disable request input editing if supported; otherwise ignore edits until task completes.
- Show a concise in-pane pending line such as `Sending reset request...` only if the task can visibly take long enough to matter.
- Token pane remains navigable unless CTO decides concurrent submissions are risky. If both tasks can run concurrently, task-result routing must update only its own pane data.

Submitting token:

- Keep token pane active.
- Disable token/password editing if supported; otherwise ignore edits until task completes.
- Request pane stays visible but inactive.

Request result messages:

- Email-dispatched and no-email/sysop-assisted messages appear in the request pane/section.
- Existing no-email/sysop contact behavior should be preserved.
- Remove old copy that tells users to press Esc then `[T]`; in the unified surface the next step is already visible. Content Designer owns the replacement sentence.

Token result errors:

- Invalid, expired, malformed, and used token failures remain the same generic non-enumerating message in the token pane.
- Password changeset errors remain generic.
- Password mismatch remains local and does not call Accounts.

## Acceptance scenarios for implementation

### Render scenarios

1. Login menu at 80x24 shows one recovery command and no separate `Enter reset token` command.
2. Recovery at wide size, e.g. 120x30, shows request and token panes side by side with stable widths and a clear active-pane treatment.
3. Wide recovery with request active shows request-specific Enter action in the keybar; switching active pane changes the keybar to token-specific submit.
4. Wide recovery with long email/token/sysop message wraps inside pane borders and does not move the opposite pane.
5. Recovery at 80x24 uses side-by-side only if both pane inner widths remain readable; otherwise it uses compact fallback. The rendered result must have no border overflow.
6. Recovery at 64x20 uses compact one-active-section layout with a visible two-section switcher, readable fields, and no hidden required action.
7. Compact request section with no-email/sysop-assisted message wraps inside the body; it does not push the command bar offscreen.
8. Compact token section shows token, new password, confirm password fields in order, with masked password fields.
9. Error states for invalid email, password mismatch, generic token failure, and generic password failure render in the correct active section without exposing private token/account details.
10. Submitting states do not visually erase the inactive pane/section draft.

### Reducer/key scenarios

1. From login menu, pressing the recovery key enters unified recovery with active pane `:request` and focus on the email field.
2. From recovery request pane, Enter with malformed email shows invalid-email error locally and does not emit a reset-request task.
3. From recovery request pane, Enter with valid email emits task atom `:reset_request` and updates only request-pane message/error on result.
4. Pane switch moves active pane without clearing either pane's inputs/messages.
5. Plain Left/Right are forwarded to text input when the cursor can move inside the current field. Pane switching via plain arrows occurs only at field edges, or Ctrl+Left/Ctrl+Right is used if cursor-position support is not reliable.
6. Token pane Tab and Shift+Tab cycle token/password/confirmation fields in the documented order.
7. Token pane password mismatch sets the local mismatch error and does not emit `:reset_token` task.
8. Token pane valid submission emits task atom `:reset_token`; success clears recovery state and returns to login menu.
9. A delayed `:reset_request` result arriving while token pane is active updates request-pane message without changing active pane or focused token field.
10. A delayed `:reset_token` result arriving while request pane is active updates token-pane error or clears on success without corrupting request message state.
11. Esc from either pane returns to login menu and clears recovery state.

### SSH/TUI QA scenarios

QA should verify after implementation:

1. At 120x30, login menu opens Recovery; both panes are visible; active pane treatment is clear in a real SSH session.
2. At 80x24, recovery remains readable with either approved split or compact fallback; no clipped borders/keybar overflow.
3. At 64x20, compact fallback is navigable: switch sections, type in fields, submit/cancel.
4. Request reset path with a seeded valid-looking email shows generic dispatched/no-email/sysop-assisted message in the request section.
5. Existing-token path can be exercised with a fixture or generated token; password mismatch and invalid token errors are clear and non-enumerating.
6. Resize from wide to compact and back preserves active pane, focused field, and typed drafts where practical.
7. Esc returns to login menu from both sections; Ctrl+C still quits as the terminal fallback and is not advertised as a distinct user action.

## Implementation handoff

Recommended touchpoints:

- `lib/foglet_bbs/tui/screens/login/state.ex`: add unified recovery state constructor and focus helpers, or equivalent shape.
- `lib/foglet_bbs/tui/screens/login.ex`: route a new `:recovery` substate while preserving `:reset_request` and `:reset_token` task-result atoms.
- `lib/foglet_bbs/tui/screens/login/render.ex`: replace separate reset render branches with unified recovery layout and responsive breakpoint logic.
- `lib/foglet_bbs/tui/screens/login/reset_request.ex` and `reset_consume.ex`: either adapt them behind the recovery reducer or introduce a sibling `recovery.ex` that reuses their validation/submission logic without duplicating security-sensitive behavior.
- Tests under `test/foglet_bbs/tui/screens/login*`: cover render model, key handling, task-result routing, and compact fallback.

Implementation should not change Accounts/Verification behavior for this issue unless CTO finds and routes a separate security/domain bug.

## Tradeoffs and residual risks

- The chosen split layout is slightly more work than tabs, but it is materially better for users because it shows the recovery sequence instead of hiding the second half.
- Plain Left/Right pane switching is desirable but risky inside text inputs. The fallback to Ctrl+Left/Ctrl+Right is acceptable and more humane than breaking cursor editing.
- 80-column side-by-side may be too dense with the current frame and command bar. Treat compact fallback at 80 columns as acceptable unless render evidence proves side-by-side remains clean.
- Request and token submissions may be technically independent, but concurrent tasks can create confusing visual states. If implementation cannot safely support concurrent submission, disable the inactive form while one task is pending and note that in tests.
- Copy constants currently tell users to press Esc then `[T]`. That must change in implementation; Content Designer owns final wording.

## Blocker questions

No CTO architecture conflict is required for the UX recommendation itself.

Implementation question for CTO/Elixir: only use plain Left/Right for pane switching if `TextInput` exposes enough cursor-position information to avoid stealing in-field cursor edits. Otherwise implement Ctrl+Left/Ctrl+Right pane switching and document that as the accepted conflict-free behavior.

## Follow-up backlog

None created by this design artifact. Potential future polish, not blocking FOG-558: if operators later add more logged-out account-help flows, consider a broader `Account help` surface with recovery, invite help, and sysop contact; that is intentionally out of scope for this consolidation.
