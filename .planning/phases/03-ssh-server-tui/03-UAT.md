---
status: complete
phase: 03-ssh-server-tui
source:
  - 03-01-SUMMARY.md
  - 03-02-SUMMARY.md
  - 03-03-SUMMARY.md
  - 03-04-SUMMARY.md
started: 2026-04-18T00:00:00Z
updated: 2026-04-19T00:00:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Cold Start Smoke Test
expected: Kill any running server/service. Clear ephemeral state if needed. Run `mix ecto.migrate` then `mix run priv/repo/seeds.exs` — both complete without errors. Start the app with `mix phx.server`. Server boots, SSH daemon binds port 2222, and a basic health check (homepage load or `ssh -p 2222 localhost`) responds without crashing.
result: pass

### 2. SSH Connection Shows Login Screen
expected: Run `ssh -p 2222 localhost` (or equivalent). The TUI renders immediately — you see a Login screen with a username/password form, KeyBar hints at the bottom, and a StatusBar at the top. No raw terminal garbage or crash output.
result: issue
reported: "I see a menu page. The status bar is at the top, but the keybar hints are directly below the menu options instead of being at the bottom of the window"
severity: minor

### 3. Login with Active User
expected: Enter valid credentials for an active account. TUI transitions to the Main Menu screen showing three single-key options: `[B] Boards`, `[C] Compose`, `[Q] Quit`. StatusBar shows your handle.
result: issue
reported: "Status bar shows 'Foglet BBS — Main Menu | @needz' and the same text appears again as the first line below the status bar (redundant). KeyBar '[B] Boards [C] Compose [Q] Logout' appears directly below menu options, not pinned to bottom of window."
severity: minor

### 4. Login with Pending Account
expected: Enter credentials for a user whose status is `pending` (e.g., registered via sysop-approved mode but not yet approved). TUI shows a modal or message indicating the account is pending approval, then exits or returns to login — does NOT drop into the main menu.
result: issue
reported: "Registration crashes in sysop_approved mode with render error: KeyError{key: :error} — the Login/Register screen's render function accesses state[:error] but the initial state %{mode: 'sysop_approved', step: :start, current_input: 'r'} has no :error key. Cannot create a pending user to test login."
severity: blocker

### 5. Login with Suspended Account
expected: Enter credentials for a suspended user. TUI shows a message indicating the account is suspended and does not allow access to the main menu.
result: issue
reported: "Suspended account modal appears and blocks access to main menu (correct), but Enter key does nothing — only Esc dismisses the modal."
severity: minor

### 6. New User Registration (Open Mode)
expected: From the Login screen, navigate to Register. With `registration_mode = "open"`, complete the registration wizard — provide handle, password, email. Account is created and you are prompted to verify your email.
result: issue
reported: "Pressing R crashes with same render error as test 4: KeyError{key: :error} on initial register state. registration_mode was still 'sysop_approved' but same crash occurs in 'open' mode — root bug is state[:error] missing at init regardless of mode."
severity: blocker

### 7. Email Verification (6-Char Code)
expected: After registration, you land on the Verify screen. Enter the 6-character uppercase code (from server logs or email). TUI accepts the code, activates the account, and transitions to the Main Menu (or Login with success message). Entering a wrong code 5 times triggers a cooldown message.
result: blocked
blocked_by: prior-phase
reason: "Can't register — registration render crash (tests 4 & 6) blocks access to Verify screen"

### 8. Main Menu Single-Key Navigation
expected: From Main Menu, press `B` — transitions to Board List. Press `Q` — session ends/disconnects. Press `C` — opens Post Composer for a new thread. Each key responds immediately with no extra confirmations.
result: issue
reported: "B key navigates to Board List screen but it shows 'Loading...' and never loads boards. Could not test Q or C."
severity: major

### 9. Board List Navigation
expected: Board List loads your subscribed boards (from Phase 2 data). Use `j`/`k` or arrow keys to move selection up/down through the list. Press Enter on a board — transitions to Thread List for that board.
result: blocked
blocked_by: prior-phase
reason: "Board List stuck on 'Loading...' — same issue as test 8"

### 10. Thread List Navigation and Sorting
expected: Thread List loads threads for the selected board. Sticky threads appear at the top of the list; non-sticky threads below sorted by most-recent post first. `j`/`k` navigates the list. Press Enter on a thread — transitions to Post Reader. Press `Q` — returns to Board List.
result: blocked
blocked_by: prior-phase
reason: "Board List stuck on 'Loading...' — same issue as tests 8 & 9"

### 11. Post Reader Navigation
expected: Post Reader loads posts for the selected thread. `n`/space/`N` advance to the next post; `p`/`P` go to the previous. The post counter (e.g., "1/5") updates. Press `R` — opens Post Composer with the current post's first 5 lines quoted as context. Press `Q` — returns to Thread List (and flushes read pointers).
result: blocked
blocked_by: prior-phase
reason: "Cannot reach Post Reader — Board List never loads"

### 12. Post Composer — Edit, Preview, Submit, Cancel
expected: In Post Composer, type a reply. Press `Tab` — view toggles to Markdown preview of your text. Press `Tab` again — returns to edit mode. Press `Ctrl+S` — post is submitted, you return to Post Reader and the new post appears. Separately, open composer and press `Ctrl+C` — immediately returns to Thread List with no confirmation prompt.
result: blocked
blocked_by: prior-phase
reason: "Cannot reach Post Composer via board navigation — Board List never loads"

### 13. Post Length Enforcement
expected: In Post Composer, attempt to submit a post exceeding 8192 characters (the `max_post_length` default). Pressing `Ctrl+S` shows an error message (character limit exceeded) and does NOT submit the post. The char count display reflects the limit.
result: blocked
blocked_by: prior-phase
reason: "Cannot reach Post Composer via board navigation — Board List never loads"

### 14. Read Pointer Persistence
expected: Read several posts in a thread and press `Q` to exit. Disconnect and reconnect. Navigate back to the same thread — the read position resumes where you left off (already-read posts are marked read, unread count in Board List is updated). This confirms `flush_read_pointers` actually wrote to the DB.
result: blocked
blocked_by: prior-phase
reason: "Cannot reach Thread/Post views — Board List never loads"

### 15. Terminal Resize Handling
expected: While viewing any TUI screen (e.g., Post Reader), resize your terminal window. The TUI re-renders cleanly to fit the new dimensions — no crash, no garbled output, no loss of content. Navigation continues to work after resize.
result: issue
reported: "TUI does not resize when terminal window is resized."
severity: major

## Summary

total: 15
passed: 0
issues: 8
skipped: 0
blocked: 7
pending: 0

## Gaps

- truth: "KeyBar renders pinned to the bottom of the terminal window"
  status: diagnosed
  reason: "User reported: keybar hints are directly below the menu options instead of being at the bottom of the window"
  severity: minor
  test: 2
  root_cause: "Outer column in every screen's render/1 uses column style: %{gap: 0} with no justify directive and no spacer between content block and KeyBar — Raxol allocates only as much height as content needs and renders KeyBar immediately after"
  artifacts:
    - path: "lib/foglet_bbs/tui/screens/main_menu.ex"
      issue: "outer column has no justify or spacer before KeyBar"
    - path: "lib/foglet_bbs/tui/screens/login.ex"
      issue: "same structural problem — all screens likely affected"
  missing:
    - "Add spacer(flex: 1) between content block and KeyBar.render(...) in every screen, OR use justify: :space_between on the outer column"

- truth: "StatusBar shows handle once; no duplicate title line in content area"
  status: diagnosed
  reason: "User reported: 'Foglet BBS — Main Menu | @needz' appears in status bar AND again as first line below status bar (redundant)"
  severity: minor
  test: 3
  root_cause: "main_menu.ex render/1 contains both text(\" Foglet BBS \", style: [:bold]) (line 21) AND StatusBar.render(...) (line 23) in the same column. The StatusBar already renders the full title 'Foglet BBS — Main Menu | @handle', so the standalone text creates a redundant title element."
  artifacts:
    - path: "lib/foglet_bbs/tui/screens/main_menu.ex"
      issue: "line 21: redundant text(\" Foglet BBS \", bold) + divider() should be removed — StatusBar.render already provides the full title"
  missing:
    - "Remove text(\" Foglet BBS \", style: [:bold]) and divider() from main_menu.ex render/1"

- truth: "Registration completes without crashing in sysop_approved mode"
  status: diagnosed
  reason: "Render crash: KeyError on :error key missing from initial state"
  severity: blocker
  test: 4
  root_cause: "login.ex maybe_register/1 (line 249) creates register_wizard as %{mode: mode, step: :start} — missing :error, :data, :current_input keys. Register.render/1 (line 26) bypasses default_wizard/1 fallback because register_wizard is non-nil, then crashes at w.error (line 29) via KeyError."
  artifacts:
    - path: "lib/foglet_bbs/tui/screens/login.ex"
      issue: "line 249: incomplete wizard map missing :error, :data, :current_input; also :start is not a valid step (should use first_step_for/1)"
    - path: "lib/foglet_bbs/tui/screens/register.ex"
      issue: "line 26-29: w = state.register_wizard || default_wizard(state) — default_wizard never fires because register_wizard is already non-nil"
  missing:
    - "In login.ex maybe_register/1, replace partial map with Register.default_wizard(state) (make it public) or include all keys: %{mode: mode, step: first_step_for(mode), data: %{}, error: nil, current_input: \"\"}"

- truth: "Register screen renders without crashing in open mode"
  status: diagnosed
  reason: "Same root cause as test 4: KeyError on :error key missing from initial register state — affects both modes"
  severity: blocker
  test: 6
  root_cause: "Identical to test 4 — same login.ex maybe_register/1 incomplete map, same crash in Register.render/1 regardless of registration mode"
  artifacts:
    - path: "lib/foglet_bbs/tui/screens/login.ex"
      issue: "line 249: same fix as test 4 covers both modes"
  missing:
    - "Same fix as test 4 — already covered"

- truth: "Suspended account modal is dismissible with Enter key"
  status: diagnosed
  reason: "User reported: Enter key does nothing on suspended account modal — only Esc dismisses it"
  severity: minor
  test: 5
  root_cause: "do_update({:key, key_event}, state) in app.ex delegates to screen_module.handle_key first; modal intercept in global_key_handler only fires on :no_match. Login's handle_form_key(%{key: :enter}, state) always matches Enter and returns {:update, ...} without checking state.modal, so the modal-dismiss path in global_key_handler (lines 609-611) is never reached."
  artifacts:
    - path: "lib/foglet_bbs/tui/app.ex"
      issue: "lines 303-318: key dispatch has no modal-intercept guard before delegating to screen module"
    - path: "lib/foglet_bbs/tui/screens/login.ex"
      issue: "lines 83-93: handle_form_key for :enter matches unconditionally without checking state.modal"
  missing:
    - "In app.ex do_update({:key, ...}, state), add modal-intercept guard: when state.modal is non-nil, route key directly to global_key_handler/2 before calling screen_module.handle_key"

- truth: "Board List loads subscribed boards after pressing B from Main Menu"
  status: diagnosed
  reason: "User reported: Board List screen shows 'Loading...' indefinitely — boards never render despite user having subscriptions"
  severity: major
  test: 8
  root_cause: "App.update/2 has do_update clauses matching bare tuples {:boards_loaded, boards} etc., but Raxol's Command.task runtime wraps every task result in {:command_result, inner} before delivering to update/2. No {:command_result, ...} clause exists, so all async results hit the catch-all and are silently discarded — board_list stays nil indefinitely."
  artifacts:
    - path: "lib/foglet_bbs/tui/app.ex"
      issue: "lines 349, 366, 395, 418: do_update clauses match bare {:boards_loaded, ...} etc. but must match {:command_result, {:boards_loaded, ...}}"
  missing:
    - "Add do_update({:command_result, inner}, state) dispatcher that re-dispatches do_update(inner, state), OR change all four result-handler clauses to match {:command_result, {:boards_loaded, boards}} form"

- truth: "TUI re-renders to fit new terminal dimensions on resize"
  status: diagnosed
  reason: "User reported: TUI does not resize when terminal window is resized"
  severity: major
  test: 15
  root_cause: "CLIHandler dispatches Event.window(width, height, :resize) for SSH :window_change, but Event.window/3 creates type: :window. Raxol's Dispatcher.system_event?/1 only includes type: :resize in the system event list — :window is absent — so the resize event is routed to the app path instead of handle_resize_event/2. The Rendering Engine's {width, height} and ScreenBuffer are never updated via {:update_size, ...}, so every re-render uses the original 80x24 dimensions."
  artifacts:
    - path: "lib/foglet_bbs/ssh/cli_handler.ex"
      issue: "line 158: Event.window(width, height, :resize) produces type: :window, not type: :resize — mismatches Dispatcher's system_event? check"
  missing:
    - "In CLIHandler, for :window_change, use Event.new(:resize, %{width: width, height: height}) so Dispatcher routes it through handle_resize_event/2 which sends {:update_size, ...} to the Rendering Engine"
