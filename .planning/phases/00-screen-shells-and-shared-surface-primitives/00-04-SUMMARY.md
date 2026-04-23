---
phase: "00"
plan: "04"
subsystem: tui-account-screen
tags: [tui, screens, account, phase-00, tdd]
dependency_graph:
  requires:
    - "00-01 (account_test.exs RED test bed)"
    - "00-02 (InvitesSurface shared primitive)"
    - "00-03 (ShellVisibility helper, App routing seams, Account stub to replace)"
  provides:
    - "Foglet.TUI.Screens.Account — full Screen behaviour implementation (ACCT-01)"
    - "Foglet.TUI.Screens.Account.State — screen-local state struct with tabs + invites"
  affects:
    - "Plan 07 (MainMenu wiring will call Account.render/1 directly)"
    - "Phase 5 (adds real profile/prefs data — no shell changes needed)"
    - "Phase 4 (activates InvitesSurface real data — no shell changes needed)"
tech_stack:
  added: []
  patterns:
    - "Screen behaviour with dedicated State module in sub-directory (D-03, D-04)"
    - "Parent-owned tab state via Foglet.TUI.Widgets.Input.Tabs (D-05)"
    - "Conditional INVITES tab via ShellVisibility.invites_visible?/2 (D-09)"
    - "Map.get for struct/map-safe field access (supports both %App{} structs and plain maps)"
    - "role: option translation in init_screen_state for direct test callers"
key_files:
  created:
    - lib/foglet_bbs/tui/screens/account/state.ex
    - lib/foglet_bbs/tui/screens/account.ex
  modified:
    - lib/foglet_bbs/tui/screens/account.ex (replaced Plan 03 stub)
decisions:
  - "Used Map.get(state, :current_user) instead of state[:current_user] — structs do not implement Access, and state may be a %Foglet.TUI.App{} struct or a plain map depending on call site"
  - "Added role: option translation in init_screen_state so tests can call Account.init_screen_state(role: :sysop) directly without constructing full state"
  - "tab body label lookup uses State.tab_labels(invites?) at render time so the rendered tab bar and body always agree on which labels are present"
metrics:
  duration: "~25 minutes"
  completed: "2026-04-23T13:33:00Z"
  tasks_completed: 2
  files_created: 2
  files_modified: 0
---

# Phase 00 Plan 04: Account Shell Screen Summary

**One-liner:** Account shell (ACCT-01) with PROFILE/PREFS tabs and conditional INVITES via the shared InvitesSurface primitive, delegating tab focus to Foglet.TUI.Widgets.Input.Tabs, with read-only scaffold-only placeholder copy throughout.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Create Foglet.TUI.Screens.Account.State struct | 9a1d827 | lib/foglet_bbs/tui/screens/account/state.ex |
| 2 | Create Foglet.TUI.Screens.Account screen module | fc86660 | lib/foglet_bbs/tui/screens/account.ex |

## Module Paths Created

- `lib/foglet_bbs/tui/screens/account/state.ex` — `Foglet.TUI.Screens.Account.State`
- `lib/foglet_bbs/tui/screens/account.ex` — `Foglet.TUI.Screens.Account`

## Tab Labels and Order

| Condition | Tab Labels (in order) |
|-----------|----------------------|
| Default (role :user, no policy) | `["PROFILE", "PREFS"]` |
| invites_visible? = true (role :sysop) | `["PROFILE", "PREFS", "INVITES"]` |

Tab index 0 = PROFILE, 1 = PREFS, 2 = INVITES (when visible).

## Tests That Flipped RED to GREEN (from Plan 01 account_test.exs)

All 12 tests in `test/foglet_bbs/tui/screens/account_test.exs`:

1. `init_screen_state/1 returns a struct with active_tab: 0 and a Tabs wrapper state`
2. `render/1 does not crash with default screen state`
3. `shows PROFILE and PREFS tab labels by default`
4. `omits INVITES when InvitesSurface.visible?/2 returns false`
5. `includes INVITES when InvitesSurface.visible?/2 returns true`
6. `renders scaffold-only placeholder copy (no fake save buttons)`
7. `Right arrow advances active_tab via Tabs.handle_event/2`
8. `digit '2' jumps to second tab (index 1)`
9. `'Q' returns to :main_menu`
10. `'q' returns to :main_menu`
11. `unknown key returns :no_match`
12. `Account screen does NOT dispatch any fake operator commands (Save/Generate/Revoke)`

## Account Smoke Test Status

`test/foglet_bbs/tui/layout_smoke_test.exs` — account shell smoke test:

- "account shell renders PROFILE/PREFS tab labels at distinct x positions within height=24" — **PASS**

The two remaining failures in layout_smoke_test.exs (`moderation shell renders all five tab labels` and `sysop shell renders all five tab labels`) are pending Plans 05 and 06 respectively — not in scope for this plan.

## Forbidden-Function / Import Guards

| Guard | Command | Result |
|-------|---------|--------|
| No fake action functions | `! grep -qE "def (save_profile|save_prefs|generate_invite|revoke_invite|approve)"` | PASS |
| No Repo/domain imports | `! grep -qE "(FogletBbs\.Repo|Foglet\.Accounts\.|Foglet\.Invites\.)"` | PASS |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] struct[:field] access fails on %Foglet.TUI.App{} structs**

- **Found during:** Task 2, layout_smoke_test.exs execution
- **Issue:** `state[:current_user]` and `state[:session_context]` use the Access protocol, which is not implemented by `%Foglet.TUI.App{}` structs. `account_test.exs` converts the struct to a plain map via `Map.from_struct/1`, so the unit tests passed. But `layout_smoke_test.exs` passes the struct directly, causing `ArgumentError: Foglet.TUI.App does not implement the Access behaviour`.
- **Fix:** Changed to `Map.get(state, :current_user)` and `Map.get(state, :session_context)` in both `render/1` and `init_opts_from_state/1`. `Map.get` works on both plain maps and structs.
- **Files modified:** `lib/foglet_bbs/tui/screens/account.ex`
- **Commit:** fc86660 (included in task commit)

## Known Stubs

| Stub | File | Line | Reason |
|------|------|------|--------|
| PROFILE tab body placeholder text | `lib/foglet_bbs/tui/screens/account.ex` | ~127 | Phase 5 adds real profile data; D-13 requires read-only scaffold only in Phase 0 |
| PREFS tab body placeholder text | `lib/foglet_bbs/tui/screens/account.ex` | ~133 | Phase 5 adds real preferences; D-13 requires read-only scaffold only in Phase 0 |
| INVITES tab body delegates to InvitesSurface.render (items: []) | `lib/foglet_bbs/tui/screens/account.ex` | ~139 | Phase 4 activates real invite rendering; Phase 0 shows "Invite management is scaffolded" |

All three stubs are intentional per D-13 and documented in the plan. None prevent the plan's goal (navigable Account shell with stable tab switching) from being achieved.

## Threat Model Coverage

| Threat ID | Mitigation Applied |
|-----------|--------------------|
| T-00-01 | No fake save/generate/revoke functions defined; commands list always `[]`; no Repo/domain imports |
| T-00-04 | INVITES tab body delegates entirely to `InvitesSurface.render/2` from Plan 02 |
| T-00-INPUT | Unknown keys return `:no_match`; Q/q handled explicitly before tab delegation |

## Threat Flags

None — no new network endpoints, auth paths, file access patterns, or schema changes introduced.

## Self-Check: PASSED

Files confirmed present:

- `lib/foglet_bbs/tui/screens/account/state.ex` — FOUND
- `lib/foglet_bbs/tui/screens/account.ex` — FOUND

Commits confirmed:

- `9a1d827` (Account.State) — FOUND
- `fc86660` (Account screen) — FOUND

All 12 account_test.exs tests: PASS (0 failures)
Account smoke test: PASS
`mix compile --warnings-as-errors`: exits 0
`mix format --check-formatted` on both lib files: exits 0
