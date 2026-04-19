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

- truth: "Server boots and SSH connections complete without crashing"
  status: fixed
  reason: "Raxol.SSH.CLIHandler calls Raxol.SSH.Server.register_connection() but Foglet.SSH.ConnectionCounter (which registers under that name) was not added to the supervision tree"
  severity: blocker
  test: 1
  fix: "Added Foglet.SSH.ConnectionCounter to ssh_children/0 in application.ex before Foglet.SSH.Supervisor"

- truth: "KeyBar renders pinned to the bottom of the terminal window"
  status: failed
  reason: "User reported: keybar hints are directly below the menu options instead of being at the bottom of the window"
  severity: minor
  test: 2
  artifacts: []
  missing: []

- truth: "StatusBar shows handle once; no duplicate title line in content area"
  status: failed
  reason: "User reported: 'Foglet BBS — Main Menu | @needz' appears in status bar AND again as first line below status bar (redundant)"
  severity: minor
  test: 3
  artifacts: []
  missing: []

- truth: "Registration completes without crashing in sysop_approved mode"
  status: failed
  reason: "Render crash: KeyError on :error key missing from initial state %{mode: 'sysop_approved', step: :start, current_input: 'r'} — render function accesses state[:error] which does not exist at start"
  severity: blocker
  test: 4
  artifacts: []
  missing: []

- truth: "Board List loads subscribed boards after pressing B from Main Menu"
  status: failed
  reason: "User reported: Board List screen shows 'Loading...' indefinitely — boards never render despite user having subscriptions"
  severity: major
  test: 8
  artifacts: []
  missing: []

- truth: "Register screen renders without crashing in open mode"
  status: failed
  reason: "Same root cause as test 4: KeyError on :error key missing from initial register state — affects both open and sysop_approved modes"
  severity: blocker
  test: 6
  artifacts: []
  missing: []

- truth: "Suspended account modal is dismissible with Enter key"
  status: failed
  reason: "User reported: Enter key does nothing on suspended account modal — only Esc dismisses it"
  severity: minor
  test: 5
  artifacts: []
  missing: []

- truth: "TUI re-renders to fit new terminal dimensions on resize"
  status: failed
  reason: "User reported: TUI does not resize when terminal window is resized"
  severity: major
  test: 15
  artifacts: []
  missing: []
