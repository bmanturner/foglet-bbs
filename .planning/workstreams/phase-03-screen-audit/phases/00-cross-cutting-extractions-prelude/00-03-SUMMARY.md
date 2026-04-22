# Plan 00-03 Summary: Call-Site Migration

**Status:** COMPLETE
**Executed:** 2026-04-21
**Commit:** (included in prior work)

## Overview

Migrated all 14 in-scope theme extraction sites to `Theme.from_state/1` and all 8 screen-level domain-lookup sites to `Domain.get/2`. Added `alias Foglet.TUI.Screens.Domain` to 5 screen files.

## Migration Summary

| Type | Count | Status |
|------|-------|--------|
| Theme sites (T-01..T-15) | 14 | ✅ Migrated |
| Domain sites (D-01..D-08) | 8 | ✅ Migrated |
| Domain aliases added | 5 | ✅ Added |
| Files modified | 12 | ✅ Complete |

## Files Modified

### Screens (9 files)
1. `login.ex` — Theme site T-01 (line 36)
2. `register.ex` — Theme site T-02 (line 30)
3. `verify.ex` — Theme site T-03 (line 41)
4. `main_menu.ex` — Theme site T-04 (line 18)
5. `board_list.ex` — Theme T-05 + Domain D-01 (:boards)
6. `thread_list.ex` — Theme T-06 + Domain D-02 (:threads)
7. `new_thread.ex` — Theme T-10,T-11 + Domain D-03 (:threads)
8. `post_reader.ex` — Theme T-07,T-08 + Domain D-04..D-07 (4 sites)
9. `post_composer.ex` — Theme T-09 + Domain D-08 (:posts)

### Non-Screens (3 files, per D-10 scope fence)
10. `screen_frame.ex` — Theme T-12 (line 34)
11. `size_gate.ex` — Theme T-15 (lines 67-70, Kernel.|| form)
12. `app.ex` — Theme T-14 (modal overlay line 170 only)

## Out-of-Scope Preserved (D-10 Fence)

| File | Site | Status |
|------|------|--------|
| `status_bar.ex` | Theme site line 37 | ✅ UNTOUCHED (out of scope) |
| `app.ex` | 6 domain sites in do_update | ✅ UNTOUCHED (out of scope) |

## Verification Results

### Grep Gate #8 (theme extraction)
```bash
rg -n '\(Map\.get\(state, :session_context\) \|\| %\{\}\) \|> Map\.get\(:theme\)' \
  lib/foglet_bbs/tui/screens/ \
  lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex \
  lib/foglet_bbs/tui/size_gate.ex \
  lib/foglet_bbs/tui/app.ex
```
**Result:** 0 matches ✅

### Grep Gate #9 (domain lookup)
```bash
rg -n 'get_in\((ctx|sc), \[:domain,' lib/foglet_bbs/tui/screens/
```
**Result:** 0 matches ✅

### Out-of-Scope Confirmation
```bash
# status_bar.ex still has inlined theme chain
rg -n '\(Map\.get\(state, :session_context\) \|\| %\{\}\) \|> Map\.get\(:theme\)' \
  lib/foglet_bbs/tui/widgets/chrome/status_bar.ex
```
**Result:** 1 match (preserved) ✅

```bash
# app.ex still has 6 domain sites
rg -c 'get_in\((ctx|sc), \[:domain,' lib/foglet_bbs/tui/app.ex
```
**Result:** 6 matches (preserved) ✅

### Smoke Test (D-08)
```bash
mix test test/foglet_bbs/tui/layout_smoke_test.exs
```
**Result:** PASS ✅

### Precommit (AUDIT-15)
```bash
mix precommit
```
**Result:** PASS ✅

## Migration Pattern Applied

### Theme (standard form)
```elixir
# BEFORE
theme = (Map.get(state, :session_context) || %{}) |> Map.get(:theme) || Theme.default()

# AFTER
theme = Theme.from_state(state)
```

### Domain
```elixir
# BEFORE
some_mod = get_in(ctx, [:domain, :key]) || Foglet.Default

# AFTER
some_mod =
  case Domain.get(ctx, :key) do
    {:ok, mod} -> mod
    {:error, :not_configured} -> Foglet.Default
  end
```

## Deviations
None. Execution matched 00-03-PLAN.md specification exactly.

## Phase 0 Status

**Phase 0: Cross-cutting extractions (prelude) is COMPLETE.**

All success criteria met:
1. ✅ `Theme.from_state/1` exists and is called from all in-scope sites
2. ✅ `Domain.get/2` exists and is called from all screen-level domain sites
3. ✅ Tests ship with both helpers
4. ✅ Grep gates #8 and #9 return zero
5. ✅ No user-visible behavior change (smoke test passes)

**Phases 1–9 are now unblocked** to proceed under their strict one-screen-per-phase scope fence.
