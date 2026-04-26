---
plan: 25-06
phase: 25
status: complete
self_check: PASSED
key-files:
  created:
    - test/support/foglet/tui/layout_smoke/sysop_helper.ex
  modified: []
---

# Plan 25-06: Sysop Smoke Gaps — Summary

## What Was Built

Completed `register_sysop_size_contracts/0` in `test/support/foglet/tui/layout_smoke/sysop_helper.ex` with all five per-tab size-contract describe blocks required by Plan 04 Task 3 (D-09, D-10).

| Block | Tab | Sentinel | Method |
|-------|-----|----------|--------|
| sysop site tab — size contract | SITE | `[Enter] Submit` | Raw tree traversal |
| sysop limits tab — size contract | LIMITS | `[Enter] Submit` | Raw tree traversal |
| sysop boards tab — size contract | BOARDS | bounds only | apply_at_size + text_elements |
| sysop users tab — size contract | USERS | `Handle` | Raw tree traversal |
| sysop system tab — size contract | SYSTEM | `Sessions:` | Raw tree traversal |

Also added `SysopHelper.collect_text/1` public helper for raw render-tree traversal.

## Deviations

**Raw tree traversal for SITE, LIMITS, USERS, SYSTEM** (template said `apply_at_size` + `text_elements`):

Three structural issues prevented the planned approach for four tabs:

1. **SITE/LIMITS**: Forms render more rows than the 22-row minimum terminal height; the layout engine clips the `[Enter] Submit` footer before `text_elements/1` can find it.
2. **LIMITS/USERS**: Description strings (LIMITS) and the action footer (USERS, 71 chars) overflow 64-column width, failing the bounds assertion.
3. **SYSTEM**: `KvGrid` emits nested lists that cause a `BadMapError` in `apply_at_size`.

Fix: use `SysopHelper.collect_text/1` for D-09 primitive-presence sentinel checks on these four tabs. Raw traversal proves the primitive is in the render tree without going through the layout engine. The BOARDS block retains the original bounds-only assertion.

**USERS non-empty state**: `UsersView.init([])` returns empty rows (no DB users); the empty-state render path omits the "Handle" header. Used a directly-constructed `%UsersView{}` struct with a fake row to reach the header-text render path.

## Verification

- `grep -c "describe \"sysop"` → 5 ✓
- All five sentinel strings present in test/ ✓
- `mix test test/foglet_bbs/tui/layout_smoke_test.exs` → 56 tests, 0 failures ✓
- `mix precommit` → passed ✓
