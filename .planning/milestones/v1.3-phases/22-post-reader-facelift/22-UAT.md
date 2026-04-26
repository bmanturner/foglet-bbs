---
status: complete
phase: 22-post-reader-facelift
source: [.planning/phases/22-post-reader-facelift/22-01-SUMMARY.md, .planning/phases/22-post-reader-facelift/22-02-SUMMARY.md, .planning/phases/22-post-reader-facelift/22-03-SUMMARY.md]
started: 2026-04-26T13:58:21Z
updated: 2026-04-26T13:58:55Z
---

## Current Test
[testing complete]

## Tests

### 1. Compact Post Header
expected: In the post reader, the selected post shows a compact fixed header with the post number, author handle, and age-style metadata. The header stays separate from the scrollable body.
result: pass

### 2. Compact Reader Progress
expected: The post reader shows compact progress text such as "Posts 3/12" as a fixed row outside the body viewport.
result: pass

### 3. Guttered Markdown Body
expected: Body content appears inside the scrollable viewport with a visible left gutter, markdown styling is preserved, and narrow widths still render without crashing or leaking formatting markers.
result: pass

### 4. Body-Only Viewport Scrolling
expected: Scrolling the post reader moves only the post body rows; the header and progress rows remain fixed while navigation, reply, back, and read-pointer behavior continue to work as before.
result: pass

### 5. Terminal Size Smoke
expected: At 64x22, 80x24, and 132x50 terminal sizes, the post reader keeps header text, post number, author, progress, guttered body text, and command bar visible without horizontal overflow or overlapping text.
result: pass

## Summary

total: 5
passed: 5
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps

[none yet]
