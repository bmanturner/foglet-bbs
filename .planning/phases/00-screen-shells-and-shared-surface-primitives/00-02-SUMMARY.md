---
phase: "00"
plan: "02"
subsystem: tui-shared-primitives
tags: [tui, screens, shared, invites, phase-00, tdd]
dependency_graph:
  requires:
    - "00-01 (test file for invites_surface_test.exs — created here since Plan 01 was parallel/pending)"
  provides:
    - "Foglet.TUI.Screens.Shared.InvitesState — shared state struct for INVITES tab"
    - "Foglet.TUI.Screens.Shared.InvitesSurface — shared surface primitive (title/visible?/default_state/render)"
  affects:
    - "Plans 04 (Account), 05 (Moderation), 06 (Sysop) — consume InvitesSurface.visible?/2, title/0, default_state/0, render/2"
    - "Phase 4 — activates real invite behavior in this one module without touching shell code"
tech_stack:
  added: []
  patterns:
    - "Dedicated state struct module (InvitesState) in its own file — one module per file (CLAUDE.md)"
    - "Shared surface primitive pattern — single module for multi-shell reuse (D-06, D-07)"
    - "TDD Red-Green: test file committed first (RED), then production modules (GREEN)"
    - "row style: do...end macro form (not row(style:, do:) function form) to produce children in Raxol flex tree"
key_files:
  created:
    - lib/foglet_bbs/tui/screens/shared/invites_state.ex
    - lib/foglet_bbs/tui/screens/shared/invites_surface.ex
    - test/foglet_bbs/tui/screens/shared/invites_surface_test.exs
  modified: []
decisions:
  - "Used row style: do...end macro syntax (not row(style:, do:) function call) for Raxol flex children — the function form passes 'do:' as a keyword and Flex.row looks for ':children', leaving the row empty"
metrics:
  duration: "8m"
  completed: "2026-04-23T18:18:00Z"
  tasks_completed: 2
  files_created: 3
  files_modified: 0
---

# Phase 00 Plan 02: Shared INVITES Surface Primitive Summary

**One-liner:** Shared INVITES surface primitive (InvitesState + InvitesSurface) with centralized role/policy visibility rules and three render branches (loading/scaffold/future), flipping 13 Plan 01 RED tests GREEN.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| RED  | Failing test file for InvitesSurface | dbd70d4 | test/foglet_bbs/tui/screens/shared/invites_surface_test.exs |
| 1    | Create InvitesState struct module | 3558a74 | lib/foglet_bbs/tui/screens/shared/invites_state.ex |
| 2    | Create InvitesSurface module (GREEN) | 51654a1 | lib/foglet_bbs/tui/screens/shared/invites_surface.ex |

## Module Paths Created

- `lib/foglet_bbs/tui/screens/shared/invites_state.ex` — `Foglet.TUI.Screens.Shared.InvitesState`
- `lib/foglet_bbs/tui/screens/shared/invites_surface.ex` — `Foglet.TUI.Screens.Shared.InvitesSurface`
- `test/foglet_bbs/tui/screens/shared/invites_surface_test.exs` — `Foglet.TUI.Screens.Shared.InvitesSurfaceTest`

## visible?/2 Rule Table (as implemented)

| User | Policy | Result |
|------|--------|--------|
| `nil` | any | `false` |
| `%{role: :sysop}` | any | `true` |
| `%{role: :mod}` | `"mods"` | `true` |
| `%{role: :user}` | `"any_user"` | `true` |
| `%{role: :mod}` | `"sysop_only"` | `false` |
| `%{role: :user}` | `"sysop_only"` | `false` |
| `%{role: :user}` | `nil` | `false` |
| `%{role: :mod}` | `"any_user"` | `false` |
| any other | any other | `false` (catch-all) |

## Forbidden-Function Guards (T-00-04)

Acceptance criteria verified:

```
! grep -qE 'def (generate_invite|revoke_invite|save_invite|approve_invite)' \
    lib/foglet_bbs/tui/screens/shared/invites_surface.ex
```

Result: PASS — no fake operator functions exist in the module.

```
! grep -qE '(Ecto|Repo|:req|HTTPoison|Tesla)' \
    lib/foglet_bbs/tui/screens/shared/invites_surface.ex
```

Result: PASS — no domain I/O imports.

## Tests that Flipped RED to GREEN

All 13 tests in `test/foglet_bbs/tui/screens/shared/invites_surface_test.exs`:

1. `title/0 returns "INVITES"`
2. `default_state/0 returns a struct with items: [] (placeholder, not loading)`
3. `visible?/2 returns true for role :sysop regardless of policy`
4. `visible?/2 returns true for role :mod when policy is "mods"`
5. `visible?/2 returns true for role :user when policy is "any_user"`
6. `visible?/2 returns false for role :user when policy is "sysop_only"`
7. `visible?/2 returns false for role :mod when policy is "sysop_only"`
8. `visible?/2 returns false when user is nil`
9. `visible?/2 returns false for unknown role/policy combinations`
10. `render/2 with %{items: nil} state renders loading branch`
11. `render/2 with %{items: []} state renders placeholder copy that is obviously scaffold-only`
12. `render/2 with %{items: [_|_]} state does NOT crash (future-facing)`
13. `InvitesSurface defines no fake generate/revoke/save/approve functions`

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Raxol row macro form vs function form**

- **Found during:** Task 2 (GREEN phase debugging)
- **Issue:** The plan skeleton used `row(style: %{gap: 1}, do: [...])` syntax inside the `render_loading` private function. This calls the `row/1` *function* (passing `[style: ..., do: [...]]` as a keyword list), not the `defmacro row(opts, do: block)` macro. `Flex.row` uses `Keyword.get(opts, :children, [])` so children were always `[]`, producing an empty flex node and no text content in the render tree.
- **Fix:** Changed to `row style: %{gap: 1} do [...] end` syntax which properly triggers the macro expansion to `Flex.row(children: [...])`.
- **Files modified:** `lib/foglet_bbs/tui/screens/shared/invites_surface.ex`
- **Commit:** 51654a1
- **Note:** The same pattern appears in `board_list.ex` but its loading test only asserts `assert _ = BoardList.render(s)` without checking text content, so the bug is latent there. Logged to deferred items.

**2. [Rule 3 - Blocker] Plan 01 test file not yet committed (parallel wave)**

- **Found during:** Execution start
- **Issue:** Plan 02 depends on Plan 01's test file (`invites_surface_test.exs`). Plan 01 runs in wave 0, Plan 02 in wave 1, but both are parallel worktree agents and Plan 01 had not yet executed.
- **Fix:** Created the test file as the TDD RED phase of Plan 02 itself, following Plan 01's behavioral spec exactly. This is appropriate since Plan 02's objective includes "Tests from Plan 01 go GREEN."
- **Files modified:** `test/foglet_bbs/tui/screens/shared/invites_surface_test.exs` (created)
- **Commit:** dbd70d4

## Threat Model Coverage

| Threat ID | Mitigated By |
|-----------|-------------|
| T-00-04 | No generate/revoke/save/approve functions (verified by acceptance criteria grep) |
| T-00-04-b | Single `visible?/2` source of truth, nil user → false catch |
| T-00-04-c | No Ecto/Repo/HTTP imports (verified by grep) |

## Known Stubs

- `render(%{items: [_|_]}, theme)` → "Invites scaffold — N entries will render once Phase 4 activates this tab." This is an intentional Phase 0 stub per D-13. Phase 4 (Shared Invite Surface Activation) will replace this with real invite list rendering.

## Threat Flags

None — no new network endpoints, auth paths, file access patterns, or schema changes introduced.

## Self-Check: PASSED

- `lib/foglet_bbs/tui/screens/shared/invites_state.ex` — FOUND
- `lib/foglet_bbs/tui/screens/shared/invites_surface.ex` — FOUND
- `test/foglet_bbs/tui/screens/shared/invites_surface_test.exs` — FOUND
- Commit dbd70d4 (RED test) — FOUND
- Commit 3558a74 (InvitesState) — FOUND
- Commit 51654a1 (InvitesSurface GREEN) — FOUND
- All 13 tests pass: `mix test test/foglet_bbs/tui/screens/shared/invites_surface_test.exs` — 13 tests, 0 failures
- `mix compile --warnings-as-errors --force` — exits 0
- `mix format --check-formatted` on both lib files — exits 0
