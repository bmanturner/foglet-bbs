---
status: testing
phase: 03-read-pointer-correctness-thread-row-enrichment
source: 03-01-SUMMARY.md, 03-02-SUMMARY.md, 03-03-SUMMARY.md, 03-04-SUMMARY.md
started: 2026-04-20T00:00:00Z
updated: 2026-04-20T00:00:00Z
---

## Current Test

<!-- OVERWRITE each test - shows where we are -->

number: 1
name: Thread List Shows Metadata Per Row
expected: |
  In the thread list, each thread row displays its title on the left side and
  right-aligned metadata in the format "@handle · N posts · time-ago" (e.g.
  "@alice · 3 posts · 2h ago"). The two sides sit on the same line.
awaiting: user response

## Tests

### 1. Thread List Shows Metadata Per Row
expected: In the thread list, each thread row displays its title on the left side and right-aligned metadata in the format "@handle · N posts · time-ago" (e.g. "@alice · 3 posts · 2h ago"). The two sides sit on the same line.
result: [pending]

### 2. Unread Threads Appear Bold
expected: Threads you haven't read (or that have new replies since you last read them) appear with a bold title in the thread list. Threads you have fully read appear in normal weight.
result: [pending]

### 3. Long Thread Titles Truncate with Ellipsis
expected: When a thread title is too long to fit alongside the metadata, the title truncates with "…" (a single unicode ellipsis character). The metadata on the right remains fully visible and is never cut off.
result: [pending]

### 4. Post Reader Marks Thread as Read on Entry
expected: Open a thread that is shown as unread (bold title). Read through the posts. Press Q to return to the thread list. That thread now appears in normal (non-bold) weight, indicating it has been marked as read.
result: [pending]

### 5. Read Pointer Does Not Regress
expected: Read thread B (newer), then read thread A (older). Return to the thread list. Thread B should still appear as read (normal weight) — reading an older thread must not cause a newer thread's read pointer to go backwards and re-show as unread.
result: [pending]

### 6. Board Unread Count Refreshes After Reading
expected: Press Q from within a thread you just read. The board list screen refreshes its unread counts to reflect that you've read that thread. If all threads in a board are now read, the board shows 0 unread.
result: [pending]

## Summary

total: 6
passed: 0
issues: 0
pending: 6
skipped: 0
blocked: 0

## Gaps

[none yet]
