---
status: partial
phase: 03-ssh-server-tui
source:
  - 03-01-SUMMARY.md
  - 03-02-SUMMARY.md
  - 03-03-SUMMARY.md
  - 03-04-SUMMARY.md
  - 03-05-SUMMARY.md
  - 03-06-SUMMARY.md
started: 2026-04-19T00:00:00Z
updated: 2026-04-19T00:00:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Cold Start Smoke Test
expected: Kill any running server/service. Clear ephemeral state if needed. Run `mix ecto.migrate` then `mix run priv/repo/seeds.exs` — both complete without errors. Start the app with `mix phx.server`. Server boots, SSH daemon binds port 2222, and a basic health check (homepage load or `ssh -p 2222 localhost`) responds without crashing.
result: pass
note: "[warning] no configuration found for otp_app :raxol and module Raxol.Endpoint — harmless, does not affect SSH TUI"

### 2. SSH Connection Shows Login Screen
expected: Run `ssh -p 2222 localhost` (or equivalent). The TUI renders immediately — you see a Login screen with a username/password form, KeyBar hints at the bottom of the window (not immediately below the form), and a StatusBar at the top. No raw terminal garbage or crash output.
result: issue
reported: "KeyBar hints are not at the bottom of the window. They are below the menu (with one row of space in between)."
severity: minor

### 3. Login with Active User
expected: Enter valid credentials for an active account. TUI transitions to the Main Menu screen showing three single-key options: `[B] Boards`, `[C] Compose`, `[Q] Quit`. StatusBar shows your handle once — no duplicate bold title line below the status bar.
result: issue
reported: "StatusBar on login screen has a row of hyphens separating it from the body, but on the main menu that row of hyphens is not present — inconsistent."
severity: cosmetic

### 4. Login with Pending Account
expected: Enter credentials for a user whose status is `pending`. TUI shows a modal or message indicating the account is pending approval, then exits or returns to login — does NOT drop into the main menu.
result: issue
reported: "Modal content hangs off screen on 80x24 (no wrapping). Enter and Esc both return to Register page instead of Login landing (Login/Register/Quit). Enter (Ok) and Esc (Dismiss) do the same thing — redundant key hint. Fix: modal should wrap, both Enter and Esc should dismiss, and user should be returned to Login landing."
severity: major

### 5. Login with Suspended Account
expected: Enter credentials for a suspended user. TUI shows a suspended-account modal. Both Enter and Esc dismiss the modal and return to the login form — does NOT allow access to the main menu.
result: pass

### 6. New User Registration (Open Mode)
expected: From the Login screen, press R. With `registration_mode = "open"`, the Register screen renders without crashing. Complete the wizard — provide handle, password, email. Account is created and you are prompted to verify your email.
result: pass

### 7. Email Verification (6-Char Code)
expected: After registration, you land on the Verify screen. Enter the 6-character uppercase code (from server logs or email). TUI accepts the code, activates the account, and transitions to the Main Menu (or Login with success message). Entering a wrong code 5 times triggers a cooldown message.
result: pass
note: "Major gap found: logging in again with unverified credentials bypasses verification and goes directly to main menu — see Gaps."

### 8. Main Menu Single-Key Navigation
expected: From Main Menu, press `B` — transitions to Board List (not stuck on "Loading..."). Press `Q` — session ends/disconnects. Press `C` — opens Post Composer for a new thread. Each key responds immediately with no extra confirmations.
result: pass

### 9. Board List Navigation
expected: Board List loads your subscribed boards (from Phase 2 data). Use `j`/`k` or arrow keys to move selection up/down through the list. Press Enter on a board — transitions to Thread List for that board.
result: pass

### 10. Thread List Navigation and Sorting
expected: Thread List loads threads for the selected board. Sticky threads appear at the top; non-sticky threads sorted by most-recent post first. `j`/`k` navigates the list. Press Enter on a thread — transitions to Post Reader. Press `Q` — returns to Board List.
result: blocked
blocked_by: prior-phase
reason: "No way to create posts yet — thread/post views cannot be tested without content."

### 11. Post Reader Navigation
expected: Post Reader loads posts for the selected thread. `n`/space advance to the next post; `p` goes to the previous. The post counter (e.g., "1/5") updates. Press `R` — opens Post Composer with the current post's first 5 lines quoted. Press `Q` — returns to Thread List.
result: blocked
blocked_by: prior-phase
reason: "No posts to read — blocked by same issue as test 10."

### 12. Post Composer — Edit, Preview, Submit, Cancel
expected: In Post Composer, type a reply. Press `Tab` — view toggles to Markdown preview. Press `Tab` again — returns to edit mode. Press `Ctrl+S` — post is submitted and you return to Post Reader with the new post visible. Separately, open composer and press `Ctrl+C` — immediately returns to Thread List.
result: blocked
blocked_by: prior-phase
reason: "Cannot reach Post Composer via board navigation — no threads exist."

### 13. Post Length Enforcement
expected: In Post Composer, attempt to submit a post exceeding 8192 characters. Pressing `Ctrl+S` shows an error message (character limit exceeded) and does NOT submit. The char count display reflects the limit.
result: blocked
blocked_by: prior-phase
reason: "No posts/threads — cannot reach Post Composer."

### 14. Read Pointer Persistence
expected: Read several posts in a thread and press `Q` to exit. Disconnect and reconnect. Navigate back to the same thread — read position resumes where you left off (already-read posts marked, unread count in Board List updated).
result: blocked
blocked_by: prior-phase
reason: "No posts to read — cannot test read pointer persistence."

### 15. Terminal Resize Handling
expected: While viewing any TUI screen, resize your terminal window. The TUI re-renders cleanly to fit the new dimensions — no crash, no garbled output, navigation continues to work after resize.
result: pass
note: "Post Composer issues observed during testing — see Gaps."

## Summary

total: 15
passed: 7
issues: 3
pending: 0
skipped: 0
blocked: 5

## Gaps

- truth: "KeyBar renders pinned to the bottom of the terminal window"
  status: failed
  reason: "User reported: KeyBar hints are not at the bottom of the window. They are below the menu (with one row of space in between)."
  severity: minor
  test: 2
  root_cause: ""
  artifacts: []
  missing: []

- truth: "StatusBar separator (row of hyphens) is consistent across all screens"
  status: failed
  reason: "User reported: StatusBar on login screen has a row of hyphens separating it from the body, but main menu is missing that separator — inconsistent."
  severity: cosmetic
  test: 3
  root_cause: ""
  artifacts: []
  missing: []

- truth: "Unverified user logging in is redirected to Verify screen, not Main Menu"
  status: failed
  reason: "User reported: logging in with unconfirmed credentials bypasses verification and lands on main menu directly."
  severity: major
  test: 7
  root_cause: ""
  artifacts: []
  missing: []

- truth: "Pending account modal wraps content, dismisses on Enter or Esc, and returns to Login landing"
  status: failed
  reason: "User reported: modal content hangs off screen on 80x24 (no wrapping); both Enter and Esc return to Register page instead of Login landing; Ok/Dismiss keys are redundant. Fix: wrap modal text, both keys dismiss, navigate back to Login landing."
  severity: major
  test: 4
  root_cause: ""
  artifacts: []
  missing: []

- truth: "New thread Post Composer (Main Menu C) includes markdown edit/preview tabs"
  status: failed
  reason: "User reported: new thread composer has a title field but no markdown edit/preview tabs. Reply composer has tabs but no title field. The two composer modes are inconsistently featured."
  severity: major
  test: observed
  root_cause: ""
  artifacts: []
  missing: []

- truth: "Post Composer markdown preview renders formatted output (e.g. **Hello** → Hello bold)"
  status: failed
  reason: "User reported: switching between edit and preview tabs shows no change — **Hello** remains **Hello** in preview instead of rendering as bold."
  severity: major
  test: observed
  root_cause: ""
  artifacts: []
  missing: []
