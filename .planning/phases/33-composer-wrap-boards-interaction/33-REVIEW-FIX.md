---
phase: 33-composer-wrap-boards-interaction
fixed_at: 2026-04-28T14:54:50Z
review_path: .planning/phases/33-composer-wrap-boards-interaction/33-REVIEW.md
iteration: 1
findings_in_scope: 1
fixed: 1
skipped: 0
status: all_fixed
---

# Phase 33: Code Review Fix Report

**Fixed at:** 2026-04-28T14:54:50Z
**Source review:** .planning/phases/33-composer-wrap-boards-interaction/33-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 1
- Fixed: 1
- Skipped: 0

## Fixed Issues

### WR-01: Multi-Codepoint Graphemes Are Truncated On Input

**Files modified:** `lib/foglet_bbs/tui/widgets/compose.ex`, `lib/foglet_bbs/tui/screens/post_composer.ex`, `lib/foglet_bbs/tui/screens/new_thread.ex`, `test/foglet_bbs/tui/widgets/compose_test.exs`, `test/foglet_bbs/tui/screens/post_composer_test.exs`, `test/foglet_bbs/tui/screens/new_thread_test.exs`
**Commit:** f9fcb78
**Applied fix:** Added `Compose.apply_key/2` to apply all printable codepoints from typed grapheme events, routed PostComposer and NewThread body input through it, and added regression coverage for decomposed combining marks plus joiner sequences in the shared widget and both composer screens.

---

_Fixed: 2026-04-28T14:54:50Z_
_Fixer: the agent (gsd-code-fixer)_
_Iteration: 1_
