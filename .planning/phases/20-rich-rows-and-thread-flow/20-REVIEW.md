---
phase: 20-rich-rows-and-thread-flow
reviewed: 2026-04-25T21:13:29Z
depth: standard
files_reviewed: 6
files_reviewed_list:
  - lib/foglet_bbs/tui/widgets/list/rich_row.ex
  - lib/foglet_bbs/tui/screens/thread_list.ex
  - test/foglet_bbs/tui/widgets/list/rich_row_test.exs
  - test/foglet_bbs/tui/screens/thread_list_test.exs
  - test/foglet_bbs/tui/layout_smoke_test.exs
  - .planning/phases/20-rich-rows-and-thread-flow/20-VALIDATION.md
findings:
  blocker: 0
  warning: 1
  info: 0
  total: 1
status: issues_found
---

# Phase 20: Code Review Report

**Reviewed:** 2026-04-25T21:13:29Z
**Depth:** standard
**Files Reviewed:** 6
**Status:** issues_found

## Summary

Reviewed the Phase 20 RichRow implementation, ThreadList migration, focused widget/screen/layout tests, and validation artifact against `20-SPEC.md` and all `20-*-SUMMARY.md` files. No blocker-level correctness, security, or regression issues were found in the ThreadList row migration. The scoped Phase 20 test command passes.

One warning remains: the new `RichRow` API documents and accepts arbitrary state atoms, but only the three ThreadList atoms produce visible glyphs. That leaves the promised reusable state-cluster contract incomplete for Phase 21/25 callers.

Verification run:

```text
rtk mix test test/foglet_bbs/tui/widgets/list/rich_row_test.exs test/foglet_bbs/tui/screens/thread_list_test.exs test/foglet_bbs/tui/layout_smoke_test.exs
75 tests, 0 failures
```

`rtk mix compile --warnings-as-errors` exited successfully. Review-only exploratory `rtk mix run` commands were attempted but not used as gate evidence because one collided with the already-running SSH daemon on port 2222 and another ran in dev mode without the test helper module loaded.

## Warnings

### WR-01: Generic State Atoms Are Accepted But Rendered As Blank Slots

**Severity:** WARNING

**File:** `lib/foglet_bbs/tui/widgets/list/rich_row.ex:95`

**Issue:** `RichRow` claims a generic reusable state-cluster input, and the phase spec requires non-ThreadList states such as `:subscribed` or `:required` to render an expected glyph cluster for later callers. The implementation converts `state_cluster` to a `MapSet`, but `glyph_nodes/3` hardcodes only `:unread`, `:sticky`, and `:locked`; every other atom is silently discarded into whitespace. The current test at `test/foglet_bbs/tui/widgets/list/rich_row_test.exs:131` only verifies that generic atoms do not leak their names and keep width, so this regression is not caught. A future BoardList/operator caller cannot express new state glyphs without editing `RichRow`, which defeats the reusable API requirement.

**Fix:** Make the state-cluster input carry renderable glyph cells, or introduce a documented mapping API that callers can extend without changing `RichRow`. For example:

```elixir
state_cluster: [
  %{key: :subscribed, glyph: "◆", slot: :success},
  %{key: :required, glyph: "!", slot: :warning}
]
```

Then render exactly the supplied fixed-width cells, falling back to whitespace only for absent slots. Update the generic-state test to assert the expected glyphs and theme slots, not only width.

---

_Reviewed: 2026-04-25T21:13:29Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
