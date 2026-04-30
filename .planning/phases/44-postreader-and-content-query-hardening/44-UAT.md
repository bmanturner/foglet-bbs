---
status: testing
phase: 44-postreader-and-content-query-hardening
source:
  - 44-01-SUMMARY.md
  - 44-02-SUMMARY.md
  - 44-03-SUMMARY.md
  - 44-04-SUMMARY.md
started: 2026-04-30T01:24:05Z
updated: 2026-04-30T01:24:05Z
---

## Current Test

number: 1
name: PostReader opens a long thread without freezing
expected: |
  Open a thread that contains hundreds of posts (e.g. via the SSH harness or
  a real client). PostReader should open promptly and display the first
  bounded window of posts (≤ ~50). The screen should not stall while loading
  the entire thread, and the initial post selection should land on the first
  post of the window.
awaiting: user response

## Tests

### 1. PostReader opens a long thread without freezing
expected: PostReader opens a thread with hundreds of posts promptly, showing only the active bounded window (≤ ~50 posts), no perceptible "loading entire thread" stall.
result: [pending]

### 2. Forward paging crosses window boundary seamlessly
expected: In the same long thread, press `n` / `space` / `page_down` until you reach the end of the visible window. PostReader requests the next bounded window and lands on the first post of that next window without an empty/blank intermediate state.
result: [pending]

### 3. Reverse paging loads the previous window and lands on its last post
expected: After paging forward at least one window, press `p` / `page_up` past the start of the current window. PostReader requests the previous bounded window and selects the *last* post of that previous window (so reading order stays continuous).
result: [pending]

### 4. Jump-to-last shows the newest window
expected: Use the jump-last command (typically `$` or end). PostReader loads the newest bounded window of the thread and selects the most recent post.
result: [pending]

### 5. Resize does not show stale-width rendering
expected: With PostReader open, resize the terminal (e.g. `resize 132x40` then `resize 80x24` in the harness, or resize a real SSH window). Reflowed text should match the new width on the very next render — no leftover wrapping/truncation from the previous width.
result: [pending]

### 6. Soft-deleted post shows as a tombstone in the reader
expected: When a post in the active reader window has been soft-deleted, PostReader still renders a row at its original message number (tombstone), rather than skipping the number or shifting subsequent message numbers up.
result: [pending]

### 7. Soft-deleted thread disappears from board thread list
expected: A soft-deleted thread no longer appears in the board's thread list screen for any user. The board's "last activity" / directory summary does not advertise the deleted thread's last post.
result: [pending]

### 8. Soft-deleted posts don't inflate unread counts
expected: Unread badges/counts on the board list (and main menu, if shown there) exclude soft-deleted posts. Deleting an unread post should drop the unread count by one for users who hadn't yet read it.
result: [pending]

## Summary

total: 8
passed: 0
issues: 0
pending: 8
skipped: 0

## Gaps

[none yet]
