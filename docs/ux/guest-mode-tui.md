# Guest Mode TUI UX Specification (FOG-583 / FOG-598)

Status: design handoff for the canonical FOG-583 integration branch.
Owner: TUI UX Designer.
Branch: `fog-583-guest-mode`.
Baseline inspected: `49269a7873f0d70e410556bc97532553beaf1ac7` plus current working tree static inspection on 2026-05-04.

## Source verification

At the start of this handoff, the canonical branch baseline had no first-class Guest Mode implementation yet:

- `lib/foglet_bbs/tui/screens/login/menu.ex` handled `L`, `R`, `F`, and `T`; no `G`/Guest route existed.
- `lib/foglet_bbs/tui/screens/login/render.ex` built the login command bar from Login/Register/Forgot/Token keys; no guest key appeared.
- `lib/foglet_bbs/tui/session_context.ex` used `user: nil` for unauthenticated sessions but had no explicit `guest_mode_enabled` or `guest?` intent flag.
- `lib/foglet_bbs/tui/screens/main_menu.ex` treated Boards, Compose, Door Games, and Logout as destination rows before any first-class guest distinction existed. If guest users route to Main Menu, the implementation must not leave Compose or Door launch as normal guest affordances.
- `lib/foglet_bbs/tui/screens/chat_room.ex` had transcript, sidebar, and composer behavior for board chat but no explicit read-only guest composer suppression yet.
- `lib/foglet_bbs/tui/screens/door_list.ex` launched visible doors through an explicit effect and confirmation modal, but had no guest denial state yet.

While this design handoff was being written, concurrent uncommitted implementation edits appeared in the shared worktree, including `SessionContext` guest fields. This document remains the UX acceptance contract for those implementation edits; it is not a code signoff.

The existing anonymous SSH session/session-promotion code should be preserved. Guest Mode should mean intentional read-only browsing state, not creation of a database user and not accidental nil-user fallthrough.

## User goal

A curious visitor should be able to enter Foglet without an account, understand they are browsing as a guest, read public BBS content, and know exactly why writing, chat sending, account, moderation, sysop, and door games require login.

## UX failure modes to design against

- The user presses a hidden or undocumented key and thinks the login screen ignored them.
- Guest entry drops them into the authenticated home layout with write/game/account affordances that later fail silently.
- Helper text says guests are read-only, but the screen still advertises `Compose`, chat composer, account, or launch controls.
- Denied actions do nothing, which feels broken in an SSH terminal where there is no browser chrome or toast history.
- The guest state is visually subtle enough that users forget whether they are logged in.
- Cramped terminals lose the Guest affordance or push reset/register actions out of the keybar.
- Guests appear in chat presence lists/counters, making them look like identified users.

## Interaction alternatives considered

### Alternative 1: visible Login-menu Guest option plus read-only guest chrome

Flow: Login menu shows `G Guest` when guest mode is enabled. Pressing `G` enters an explicit guest session, routes to Main Menu, and renders a stable guest state in chrome/body. Write/game/account actions are hidden where possible and denied with a modal if reached directly.

Pros:
- Most discoverable terminal-native entry point; no command guessing.
- Matches the board requirement and keeps Guest Mode first-class.
- Easy to test with render and SSH harness evidence: `G` from Login, then read-only browsing.
- Keeps guest identity visible through chrome/body instead of relying on one-time login copy.

Cons:
- Adds one more Login key in a crowded compact keybar.
- Requires every writable screen to make explicit guest decisions instead of relying on `current_user == nil` accidents.

### Alternative 2: read-only route-specific affordances without a persistent guest state

Flow: unauthenticated visitors can open some routes from Login or a public menu, and each read-only surface decides whether to show content. Denied actions are handled per screen.

Pros:
- Smaller initial Login menu change.
- Can be implemented incrementally for one surface at a time.

Cons:
- Users have no stable sense that they are in a deliberate guest session.
- High risk of inconsistent affordances and silent nil-user behavior.
- Harder for future features to remember the guest decision.
- Does not satisfy the stated `G` login entry expectation.

### Alternative 3: public preview screen before entering the BBS

Flow: Login `G` opens a preview/explanation screen. Enter continues to Main Menu; Esc returns to Login.

Pros:
- Gives more room to explain read-only constraints.
- Reduces surprise before users see authenticated-looking navigation.

Cons:
- Adds friction to the fastest browsing path.
- Another screen to maintain at narrow widths.
- Text-heavy explanation is a smell if the actual chrome and affordances are not self-explanatory.

## Recommendation

Use Alternative 1: `G Guest` on the Login menu, then a first-class read-only guest session with persistent guest-aware chrome and screen-level affordance gating.

Why this is good for Foglet users:

- It feels like a classic BBS guest tour: one obvious key, then immediate browsing.
- It makes read-only limits visible without demanding account/domain knowledge.
- It keeps the keyboard path short while protecting state-changing actions.
- It gives implementers and future contributors a clear invariant: guest state is explicit and screens must choose read vs. write behavior.

Alternative 3 can be added later if sysops want a richer welcome/tour, but should not block the first implementation.

## Guest state model for TUI surfaces

Implementation should expose explicit guest intent to screens. Suggested TUI-facing shape:

- `session_context.guest_mode_enabled`: boolean snapshot from runtime config at SSH channel attachment.
- `session_context.guest?` or equivalent helper predicate: true only after the user intentionally chose Guest Mode.
- `context.current_user`: remains `nil` for guests and unauthenticated Login.

Do not make screens infer intentional guest browsing solely from `current_user == nil`; Login also has no current user. A helper such as `ShellVisibility.guest?(context)` or `ShellVisibility.read_only_guest?(context)` is preferable for visible surface decisions.

## TUI interaction map

### Login menu

Enabled state:
- Visible option: `G Guest`.
- Keyboard: `G` / `g` starts or continues an anonymous guest session and navigates to `:main_menu`.
- Existing keys remain: `L Login`, `R Register` when registration is enabled, `F Forgot password`, `T Enter reset token`.
- Keybar order recommendation at normal width: `L Login`, `G Guest`, `R Register`, `T Reset token`, `F Forgot password`.
- If registration is disabled, hide `R` but keep `G` when guest mode is enabled.

Disabled state:
- Do not render `G Guest`.
- Pressing `G` should be inert or produce the same style of disabled behavior used by the existing Login menu policy. Prefer inert when no disabled-key copy pattern exists, but tests should assert it does not enter guest mode.

Layout/composition:
- Preserve centered menu composition.
- At 80x24, all active keys should be visible in the command bar without wrapping into noisy clutter.
- At cramped width (target 64x20 or current SizeGate minimum), keybar may drop lower-priority reset/register hints first, but `L Login` and `G Guest` must remain visible when guest mode is enabled.
- Avoid a large explanatory paragraph on Login. The option label plus read-only state on Main Menu should carry the flow.

### Guest Main Menu

Guest-visible destinations:
- `Boards` stays visible.
- `Logout`/`Quit` stays visible using the existing exit behavior.
- `Door Games` may either be visible as a denied destination or hidden with a direct-key denial. Because the parent explicitly requires a modal if a guest attempts Door Games, the recommended pattern is:
  - show no normal Door Games row for guests,
  - reserve `D` direct-key handling to open a denial modal if pressed.

Guest-hidden destinations/actions:
- `Compose` hidden.
- `Account` hidden.
- `Moderation` hidden.
- `Sysop` hidden.
- `Oneliner` action hidden.
- `Hide oneliner` hidden unless moderation policy ever makes it meaningful for guests; current recommendation is hidden.

Guest state indicator:
- Main body should include a compact read-only note in the right panel where oneliners normally appear, not a modal on entry.
- Suggested draft copy for implementation/content review: `Browsing as guest — read-only. Log in to post, chat, or play games.`
- Content Designer owns final shipped wording.

Layout/composition:
- Preserve the two-panel Main Menu structure at 80x24 so guest mode does not feel like a broken or lesser route.
- Navigation panel left remains fixed-width under the existing split-pane calculation.
- The guest note replaces/augments the oneliners panel content and wraps within the panel inner width.
- At cramped width, prioritize `Boards [B]`, exit key, and the read-only guest note; do not crowd the keybar with denied actions.

Keyboard:
- `B`: navigate to Board List and load readable boards.
- `C` / `O` / `A` / `M` / `S`: no visible affordance; if pressed, inert is acceptable for hidden/non-discoverable keys.
- `D`: open an alert/error modal explaining registered/login users can play door games.
- `Q`: quit/logout consistent with existing app behavior.

### Door Games denial modal for guests

Trigger points:
- Pressing `D` from Guest Main Menu.
- Direct route/effect attempts to `:door_list` or door launch while `guest?` is true.

Behavior:
- Do not navigate to the selector for guests.
- Do not list visible doors for guests.
- Show a modal instead of silent ignore.

Modal composition:
- Type: warning/error alert, not confirm.
- Max width: `min(64, terminal_width - 6)`.
- Body wraps inside modal borders.
- Keybar/actions: `Enter OK`, `Esc Back` or existing modal-dismiss equivalents.

Suggested draft copy for implementation/content review:
- Title: `Login Required`
- Body: `Door games are for registered users. Log in to play.`

### Board List / Board Screen / Thread List

Guest behavior:
- Guests can browse boards and threads they are allowed to view.
- Guests cannot create a new thread or reply.
- If the existing policy has boards with no anonymous read permission, they should simply not appear or should show the existing not-authorized state; do not expose internal authorization scope names.

Keybars:
- Board and thread navigation keys stay visible: selection, open, back.
- Compose/new-thread/reply keys are hidden when guest.
- If a write key is pressed by habit, prefer inert when the key has no visible hint; use a modal only when the route/action remains visible or direct route entry is plausible.

Text/list policy:
- Board and thread rows should keep existing alignment and truncation.
- Empty state for a guest-readable board with no content should be content-empty, not permission-scolding.
- Empty state when no readable boards exist should be plain: `No boards are available to guests right now.` Content Designer should review shipped copy.

### Post Reader

Guest behavior:
- Guests can read posts in readable threads.
- Reply/edit/moderation actions are hidden.
- Scroll/read navigation remains unchanged: `j/k` or arrow scroll behavior should not differ for guests.
- Read-pointer persistence must not run for guest sessions unless engineering has a deliberate anonymous-session mechanism; UI-local scroll state remains screen-local.

Composition:
- Preserve post card/body wrapping and the compact post-reader keybar.
- A subtle guest read-only indicator can live in chrome/status or keybar context, but do not insert repeated read-only notices between posts.

### Chat transcript in board screens

Guest behavior:
- Guests may view chat transcript where board chat is enabled.
- Guests do not appear in online lists/counters/presence sidebars.
- Guests cannot type into or send through the composer.
- Backend send paths must reject guest/nil users even if a UI route is reached directly.

Composition:
- Transcript region remains the primary region.
- Sidebar anchoring rules remain unchanged: `>=80` sidebar available, `60-79` collapsed by default/toggleable, `<60` transcript only.
- For guests, composer row becomes a read-only note in the same composer-height slot to avoid vertical jumping when authenticated users and guests switch flows.
- Suggested draft copy for implementation/content review: `Guest view — log in to chat.`
- At cramped width, clip/wrap this note inside the transcript/composer region; do not add a second keybar group.

Keyboard:
- Scroll keys remain active: Up/Down/PageUp/PageDown/Home/End as currently supported.
- Printable characters do not enter a hidden composer buffer while guest.
- Enter does not send.
- Sidebar toggle remains available only if the sidebar exists by width policy.

### Account / moderation / sysop direct routes

Guest behavior:
- These should not be visible from Main Menu.
- Direct route attempts should route back to Main Menu or show the existing not-authorized modal/state. Prefer modal for account (`Login Required`) because normal users may reasonably try to find login/profile from guest mode; moderation/sysop can use the existing not-authorized pattern.

### Exit / login transition

- `Q` from Guest Main Menu follows existing quit/logout behavior.
- If future design adds `L Login` from guest Main Menu, it should return to the Login form without destroying terminal state; this is optional and not required for the first slice.
- Guest-to-authenticated promotion via the existing Login flow must preserve the one-session-per-user semantics already owned by session promotion code.

## Acceptance scenarios for implementation and QA

Use these as keyboard-first checks. Screen names may use the render task for static layout evidence and the SSH harness for live flow evidence.

### A. Login Guest entry enabled

Given guest mode is enabled
When the Login screen renders at 80x24
Then `G Guest` is visible in the command bar/menu affordances
And `L Login` remains visible
And existing register/reset behavior is not visually broken

When the user presses `G`
Then Foglet routes to Main Menu
And the session is explicitly guest/read-only
And the status/chrome/body makes guest read-only state visible

### B. Login Guest disabled

Given guest mode is disabled
When the Login screen renders
Then `G Guest` is not visible

When the user presses `G`
Then Foglet does not route to Main Menu as guest
And no guest session flag is set

### C. Guest Main Menu affordances

Given a guest is on Main Menu at 80x24
Then `Boards` and exit are available
And `Compose`, `Account`, `Moderation`, `Sysop`, `Oneliner`, and `Hide oneliner` are not advertised
And a compact read-only guest note is visible

At cramped width
Then `Boards` and exit remain available
And the guest note stays inside panel borders without pushing keybar rows into overflow

### D. Guest board browsing

Given a guest is on Main Menu
When the user presses `B`
Then Board List opens with readable boards loaded

When the user opens a readable board and thread
Then Thread List and Post Reader navigation works
And write/reply/compose actions are not visible

### E. Guest write/action denial

Given a guest is on Main Menu
When the user presses `D`
Then a modal appears explaining that login/registration is required for door games
And no door is launched
And dismissing the modal returns to Guest Main Menu

Given a guest reaches a write route or write key path directly
When the write action is attempted
Then no persisted content is created
And the user either sees a clear login-required modal or the hidden key is inert by documented policy

### F. Guest chat read-only

Given a guest opens a board with chat enabled
Then the transcript is visible where chat history exists
And the chat composer is not editable
And a compact read-only chat note appears where composer input would be
And the guest does not appear in online sidebar/counter

When the user types printable characters or presses Enter
Then no composer buffer changes
And no chat send task runs

### G. Door direct-route guard

Given a guest session
When `:door_list` or a door launch effect is reached through a direct route, stale state, or future shortcut
Then the route/effect is denied before launch
And the denial modal/state is visible
And no door runner receives terminal control

### H. Render/narrow-width evidence

Implementation should provide render evidence for:

1. Login at 80x24 with guest enabled.
2. Login at cramped width with guest enabled.
3. Login at 80x24 with guest disabled.
4. Guest Main Menu at 80x24.
5. Guest Main Menu at cramped width.
6. Guest Door denial modal at 80x24 and cramped width.
7. Guest Thread List/Post Reader with write actions hidden.
8. Guest chat tab at 80x24 and `60-79` width range showing transcript read-only behavior.

## Test expectations

Focused implementation tests should cover:

- Config/session context: default enabled, disabled override, and explicit guest flag separate from unauthenticated Login.
- Login reducer/render: `G` only works when enabled; existing `L/R/F/T` keys still work.
- Main Menu: guest visibility predicates hide write/account/admin actions; `D` opens denial modal.
- Door List/effect: guest route/launch attempts are denied.
- Thread/Post composers: guest cannot create new threads/replies/posts.
- Chat: guest transcript loads; composer is disabled/hidden; send path rejects nil/guest; presence excludes guests.
- Render smoke tests for normal and cramped terminal sizes.
- SSH harness smoke: connect without an authenticated user, press `G`, browse boards/posts, attempt Door Games, verify denial, verify no chat send.

## Follow-up and ownership notes

- Content Designer should review final modal/read-only copy before release if implementation uses the suggested draft language.
- QA should perform live SSH/TUI smoke after implementation because static render evidence cannot prove terminal input routing, chat send suppression, or door launch denial.
- No active UX blocker is filed by this design handoff because implementation has not landed yet. If implementation exposes guest write/game/account affordances after this spec, route that as an active blocker on FOG-583 rather than backlog polish.

## Implementation may proceed

TUI UX recommendation: implementation may proceed using the visible `G Guest` entry plus read-only guest chrome pattern above. The critical product constraint is that guest mode must remove normal write/game/account affordances and provide a visible denial when Door Games is attempted, not merely rely on backend nil-user failures.
