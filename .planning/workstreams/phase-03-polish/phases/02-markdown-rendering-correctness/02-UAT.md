---
status: testing
phase: 02-markdown-rendering-correctness
source: [02-01-SUMMARY.md, 02-02-SUMMARY.md, 02-03-SUMMARY.md]
started: 2026-04-20T00:00:00Z
updated: 2026-04-20T00:00:00Z
---

## Current Test

number: 1
name: Post Renders Without \n Artifacts
expected: |
  Open a post in the reader. The post body displays clean text without literal
  \n characters or blank lines between every styled run. Each logical paragraph
  appears as a separate line, not as raw escape sequences.
awaiting: user response

## Tests

### 1. Post Renders Without \n Artifacts
expected: Open a post in the reader. The post body displays clean text without literal \n characters or blank lines between every styled run. Each logical paragraph appears as a separate line, not as raw escape sequences.
result: [pending]

### 2. Markdown Styles Display Correctly
expected: In the post reader, bold text appears visually distinct (accent color), italic text uses the primary style, dim text appears muted. Multiple styles can appear on the same line without breaking layout.
result: [pending]

### 3. Post Card Header Format
expected: Each post shows a header with "Post X of N", "By @handle", and a time-ago string (e.g., "3h ago") — all in a dim/muted color — followed by a themed divider line separating it from the body.
result: [pending]

### 4. j/k Scrolls Within a Long Post
expected: Open a post with more content than fits the screen. Press j to scroll down (more lines reveal), press k to scroll back up. Scroll doesn't go below 0 or past the end of content.
result: [pending]

### 5. N/P Navigation Resets Scroll to Top
expected: While scrolled partway through a post, press N or P to navigate to the next/previous post. The new post renders from the top (scroll_offset resets to 0, not mid-post).
result: [pending]

### 6. Terminal Resize Refreshes Post Content
expected: Resize the terminal while reading a post. The content re-renders to fit the new width without stale layout artifacts or content from the old width persisting.
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
