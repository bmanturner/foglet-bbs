---
status: testing
phase: 04-composer-thread-creation-end-to-end
source:
  - 04-01-SUMMARY.md
  - 04-02-SUMMARY.md
  - 04-03-SUMMARY.md
  - 04-04-SUMMARY.md
started: 2026-04-20T00:00:00Z
updated: 2026-04-20T00:00:00Z
---

## Current Test

number: 1
name: Cold Start Smoke Test
expected: |
  Kill any running server. Run `mix ecto.reset && mix run priv/repo/seeds.exs`. Seeds complete with no errors. Start the app. It boots without errors or crashes.
awaiting: user response

## Tests

### 1. Cold Start Smoke Test
expected: Kill any running server. Run `mix ecto.reset && mix run priv/repo/seeds.exs`. Seeds complete with no errors. Start the app. It boots without errors or crashes.
result: [pending]

### 2. ThreadList [C] opens NewThread wizard
expected: From the thread list screen, press [C]. The new-thread composer wizard opens (board picker step). It does NOT crash or route to the post composer with a nil thread.
result: [pending]

### 3. NewThread: title cap + live counter
expected: In the NewThread wizard body step, type a title. Once you reach 60 characters, additional keystrokes are ignored (title stops growing). A live character counter is visible (e.g. "42/60").
result: [pending]

### 4. NewThread: origin-aware cancel
expected: Open NewThread from the main menu — press Ctrl+C → returns to main menu. Open NewThread from the thread list ([C]) — press Ctrl+C → returns to thread list. Cancel always goes back to where you came from.
result: [pending]

### 5. NewThread: submit navigates to thread list with new thread
expected: Complete the NewThread wizard and submit. The screen transitions to the thread list, which reloads and shows the newly created thread.
result: [pending]

### 6. PostComposer: origin-aware cancel
expected: Open the post composer from the main menu — press Ctrl+C → returns to main menu. Open it from inside a thread (post reader [R]) — press Ctrl+C → returns to post reader. Cancel routes back to the originating screen.
result: [pending]

### 7. PostComposer: reply-jump after submit
expected: Reply to a post in a thread. After submitting, the post reader scrolls to your newly created reply (cursor lands on it). You do not stay at the previous position.
result: [pending]

### 8. Composer preview renders markdown
expected: In either the NewThread body step or PostComposer, type markdown (e.g. `**bold**`, `# heading`, a blank line between paragraphs). Toggle preview mode. The preview shows rendered markdown — no literal `\n` characters are visible, bold text is styled, paragraphs are separated.
result: [pending]

## Summary

total: 8
passed: 0
issues: 0
pending: 8
skipped: 0

## Gaps

[none yet]
