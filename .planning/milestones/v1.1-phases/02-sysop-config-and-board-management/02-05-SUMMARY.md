---
phase: 02-sysop-config-and-board-management
plan: 05
subsystem: tui/sysop
tags: [sysop, system-tab, read-only, beam-introspection, phase-gate]
requires: [02-03, 02-04]
provides: [SYSTEM tab live, phase-02 precommit gate]
affects:
  - lib/foglet_bbs/tui/screens/sysop.ex
  - lib/foglet_bbs/tui/screens/sysop/system_snapshot.ex
  - test/foglet_bbs/tui/screens/sysop_test.exs
requirements: [SYSO-04]
decisions:
  - "Zero-dep BEAM introspection (`:erlang.statistics`, `Registry.count`, `DynamicSupervisor.count_children`) — D-21 / RESEARCH Pattern 7."
  - "Snapshot-on-init + manual `r` refresh — no auto-refresh ticker (D-20)."
  - "Safe guards around Registry / DynamicSupervisor lookups so the tab renders even if the supervisor names aren't running (test envs, warm boot races)."
metrics:
  completed: 2026-04-23
---

# Phase 02 Plan 05: SYSTEM Tab + Phase Quality Gate Summary

Read-only SYSTEM tab implemented as a sibling submodule
(`Foglet.TUI.Screens.Sysop.SystemSnapshot`) matching the SiteForm / LimitsForm
/ BoardsView triplet contract (`init/1`, `handle_key/2`, `render/2`). The
parent `Sysop.handle_key/2` gained a single `SYSTEM ->
delegate_to_submodule(..., :system_snapshot, SystemSnapshot)` clause — all
four non-placeholder tabs (SITE, LIMITS, BOARDS, SYSTEM) now route through
the same delegation spine. USERS remains the lone placeholder.

## Final Sysop shape

`lib/foglet_bbs/tui/screens/sysop.ex` now hosts:

- `render_tab_body/3` branches for SITE, BOARDS, LIMITS, SYSTEM (each calls the
  respective submodule's `render/2`) + a USERS placeholder.
- `delegate_to_active_tab/3` routes to SiteForm / LimitsForm / BoardsView /
  SystemSnapshot by active-tab label, with unknown tabs returning `:no_match`.

## Snapshot fields (D-21)

| Field          | Source                                             |
|----------------|----------------------------------------------------|
| Version        | `:application.get_key(:foglet_bbs, :vsn)`          |
| Uptime         | `:erlang.statistics(:wall_clock)` → `hh:mm:ss`     |
| Sessions       | `Registry.count(Foglet.Sessions.Registry)`         |
| Active boards  | `DynamicSupervisor.count_children(Foglet.Boards.Supervisor).active` |
| OTP processes  | `:erlang.system_info(:process_count)`              |
| DB pool size   | `FogletBbs.Repo.config()[:pool_size]`              |

## `mix precommit` — green

`compile --warnings-as-errors`, `format`, `credo --strict`, `sobelow`,
`dialyzer` all pass on the final commit. One dialyzer warning surfaced during
development (`pattern_match_cov` on the safe_dynsup fallback clause —
`DynamicSupervisor.count_children/1` always returns the full map) and was
fixed by replacing the case-with-fallback with a direct pattern match plus
rescue/catch for the error paths.

## Deviations

None. Plan executed as written, with two minor pragmatic additions that stayed
within the documented triplet contract:

1. **Registry / DynamicSupervisor safety guards** (`safe_registry_count/1`,
   `safe_dynsup_count/1`) — wrap the introspection calls in rescue/catch so
   the SYSTEM tab renders zeros rather than crashing if the named supervisors
   aren't up (e.g., test environments without the full app tree, or brief
   warm-boot windows). This is a Rule 2 robustness guard — no threat-register
   impact.
2. **Test lazy-init bypass** (`activate_system_tab/1`) — builds the snapshot
   directly via `SystemSnapshot.init/1` and assigns it into screen state,
   rather than round-tripping through `Sysop.handle_key` (which returns
   `:no_match` when a no-op delegation leaves submodule state unchanged —
   expected behaviour, not a bug). The production lazy-init path still works
   normally: the first mutating keystroke (`r`) persists the refreshed
   snapshot.

## Commits

- `18ccfbc` — feat(02-05): add SystemSnapshot submodule for SYSTEM tab (SYSO-04)
- `c5a31b3` — feat(02-05): wire SYSTEM tab delegation + tests + precommit green

## Self-Check: PASSED

- `lib/foglet_bbs/tui/screens/sysop/system_snapshot.ex` — FOUND
- `lib/foglet_bbs/tui/screens/sysop.ex` SYSTEM delegation — FOUND (`grep SystemSnapshot.handle_key` passes via `SystemSnapshot` alias + delegate_to_submodule)
- `test/foglet_bbs/tui/screens/sysop_test.exs` SYSTEM describe block — FOUND
- `mix precommit` — PASSED
- `mix test test/foglet_bbs/tui/screens/sysop_test.exs` — 27 tests, 0 failures
- Commits `18ccfbc`, `c5a31b3` — FOUND in git log
