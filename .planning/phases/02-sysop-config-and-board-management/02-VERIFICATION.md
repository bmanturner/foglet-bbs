---
phase: 02-sysop-config-and-board-management
verified: 2026-04-24T14:43:17Z
status: human_needed
score: 4/4 must-haves verified
overrides_applied: 0
re_verification:
  previous_status: gaps_found
  previous_score: 3/4
  gaps_closed:
    - "BOARDS tab create/edit/submit errors route to the error modal instead of crashing or disappearing."
  gaps_remaining: []
  regressions: []
human_verification:
  - test: "Exercise SITE and LIMITS tabs over a real SSH/TUI session."
    expected: "Rows render legibly, focus movement is understandable, ordinary typing and Ctrl+S behave as covered by tests, and validation/errors are readable."
    why_human: "Terminal rendering, keyboard feel, and visual layout require an interactive TUI check."
  - test: "Exercise BOARDS create/edit/archive and category create/edit/archive over a real SSH/TUI session."
    expected: "Modal.Form overlays are usable, submit errors route to the shared error modal, list navigation is blocked while modals are open, and refreshed rows are visually coherent."
    why_human: "Automated tests prove handler state and domain wiring, but not end-to-end terminal usability."
  - test: "Open SYSTEM tab and press r over a real SSH/TUI session."
    expected: "The read-only snapshot renders version, uptime, session count, active boards, OTP process count, and DB pool size; r refreshes without adding mutating controls."
    why_human: "Snapshot data and handler behavior are programmatically checked, but final terminal presentation needs a human pass."
---

# Phase 2: Sysop Config and Board Management Verification Report

**Phase Goal:** Sysops can manage typed site policy, invite controls, board/category lifecycle, and system details from the TUI on top of the new authz backbone.
**Verified:** 2026-04-24T14:43:17Z
**Status:** human_needed
**Re-verification:** Yes - after gap closure plan 02-06

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Sysop can change seeded runtime config values for registration, invite policy, and operational limits from the TUI, and unschematized config keys are not exposed there. | VERIFIED | `SiteForm` and `LimitsForm` use fixed key lists, call `Schema.fetch_spec/1`, initialize from `Config.get!/1`, and save through actor-aware `Config.put/3`. The partition test asserts every `Schema.entries/0` key appears exactly once. |
| 2 | Invite generation policy can be set to `sysop_only`, `mods`, or `any_user`, and `any_user` mode can use either unlimited or numeric per-user invite caps. | VERIFIED | `Config.Schema` defines `invite_code_generators` enum and `invite_generation_per_user_limit` integer default 0/min 0. `SiteForm.visible_keys/1` hides the cap unless generators is `any_user`; tests cover hidden and visible states. |
| 3 | Sysop can create, update, list, and archive categories and boards from the `BOARDS` tab without direct database edits. | VERIFIED | `BoardsView` lists DB-backed categories/boards, dispatches Modal.Form submit to actor-aware `Foglet.Boards` functions, routes changesets inline, routes `:forbidden` and atom errors to the parent error modal, and confirm archive calls domain archive functions. Gap 02-06 is closed by the generic atom-error branch. |
| 4 | Sysop can inspect current system details from the `SYSTEM` tab. | VERIFIED | `SystemSnapshot` samples version, uptime, session count, active board-server count, process count, and DB pool size; `Sysop` delegates SYSTEM tab events to it and tests cover render, refresh, and non-mutating keys. |

**Score:** 4/4 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/foglet_bbs/config/schema.ex` | Typed config schema including invite cap | VERIFIED | `invite_generation_per_user_limit` is schematized with default 0 and min 0; invite generator enum includes `sysop_only`, `mods`, and `any_user`. |
| `lib/foglet_bbs/config.ex` | Typed accessor and actor-aware writer | VERIFIED | `invite_generation_per_user_limit/0` exists; `put/3` uses `Bodyguard.permit/4` before validation/write. |
| `priv/repo/seeds.exs` / `priv/repo/seeds/config.exs` | Seed row for every schema key | VERIFIED | Top-level seeds delegate to `seeds/config.exs`, which iterates `Schema.entries/0`; focused tests logged the invite cap seed as present. |
| `lib/foglet_bbs/boards/category.ex` | Category archive changeset | VERIFIED | `archive_changeset/1` only flips `archived`; category CRUD is actor-aware through `Foglet.Boards`. |
| `lib/foglet_bbs/boards.ex` | Actor-first category and board mutations | VERIFIED | Category and board create/update/archive paths call `Bodyguard.permit/4`; `create_board/3` now documents and normalizes `:board_server_unavailable`. |
| `lib/foglet_bbs/tui/screens/sysop/site_form.ex` | SITE form | VERIFIED | Renders schema-backed site keys, conditional invite cap visibility, nil-safe char handling, and save via `Config.put/3`. |
| `lib/foglet_bbs/tui/screens/sysop/limits_form.ex` | LIMITS form | VERIFIED | Renders schema-backed limits keys, saves via `Config.put/3`, and uses nil-safe `Map.get(event, :ctrl) || Map.get(event, :meta)`. |
| `lib/foglet_bbs/tui/screens/sysop/boards_view.ex` | BOARDS CRUD view | VERIFIED | Normal CRUD, validation errors, forbidden errors, archive confirmations, and generic atom submit errors are handled through the parent modal path. |
| `lib/foglet_bbs/tui/screens/sysop/system_snapshot.ex` | SYSTEM snapshot | VERIFIED | Read-only snapshot and `r` refresh implemented with BEAM/Repo introspection. |
| `test/foglet_bbs/tui/screens/sysop_test.exs` | TUI regression coverage | VERIFIED | Covers SITE/LIMITS partition and save behavior, BOARDS CRUD/error routing including `:board_server_unavailable`, LIMITS plain char input, and SYSTEM snapshot behavior. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `Schema.entries/0` | SITE/LIMITS partition | `@site_keys` / `@limits_keys` and `Schema.fetch_spec/1` | VERIFIED | Partition test asserts all schema keys appear exactly once and UI fetches specs by fixed key list. |
| `SiteForm` / `LimitsForm` | `Foglet.Config.put/3` | Ctrl+S submit | VERIFIED | Both forms call `Config.put(current_user, key, value)` and handle invalid, forbidden, unknown key, and DB error outcomes. |
| `Sysop` | SITE/LIMITS/BOARDS/SYSTEM submodules | `delegate_to_submodule/5` | VERIFIED | Active tab events lazy-init and delegate to the tab module; `{:error_modal, msg, dest}` becomes `%Foglet.TUI.Modal{type: :error}` and `current_screen: dest`. |
| `BoardsView` | `Foglet.Boards` mutations | Modal.Form submit and confirm archive | VERIFIED | `dispatch_submit/3` calls `create_board/3`, `update_board/3`, `create_category/2`, and `update_category/3`; confirm flow calls archive functions. Atom errors now route safely. |
| `SystemSnapshot` | BEAM/Repo introspection | zero-dependency APIs | VERIFIED | Uses `:erlang.statistics`, `Registry.count`, `DynamicSupervisor.count_children`, `:erlang.system_info`, and `Repo.config`. |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `SiteForm` | `drafts` | `Config.get!/1` per `@site_keys` | Yes | VERIFIED |
| `LimitsForm` | `drafts` | `Config.get!/1` per `@limits_keys` | Yes | VERIFIED |
| `BoardsView` | `categories`, `boards`, `rows` | `Boards.list_categories/0`, `Boards.list_boards/0` DB queries | Yes | VERIFIED |
| `SystemSnapshot` | `snapshot` | BEAM, Registry, DynamicSupervisor, Repo config | Yes | VERIFIED |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Phase 2 focused tests | `rtk mix test test/foglet_bbs/config_test.exs test/foglet_bbs/boards/boards_test.exs test/foglet_bbs/tui/screens/sysop_test.exs` | 119 tests, 0 failures | PASS |
| Compile gate | `rtk mix compile --warnings-as-errors` | Exit 0; dependency warnings from `raxol` were printed but did not fail the project compile | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| INVT-06 | 02-01, 02-03 | Sysop can set invite generation policy to `sysop_only`, `mods`, or `any_user`. | SATISFIED | Schema enum plus SITE form rendering/saving through `Config.put/3`; tests cover SITE render and save paths. |
| INVT-07 | 02-01, 02-03 | Sysop can set per-user invite generation limit to unlimited or numeric cap when `any_user` invites are enabled. | SATISFIED | Integer schema min 0/default 0, typed accessor, Config.put tests for 0/positive/invalid/forbidden, and conditional SITE row visibility tests. |
| SYSO-02 | 02-01, 02-03, 02-06 | Sysop can edit seeded runtime config values for registration, invite policy, and limits. | SATISFIED | SITE/LIMITS forms cover all schema keys exactly once and save through actor-aware config context; LIMITS plain char regression prevents `BadBooleanError`. |
| SYSO-03 | 02-02, 02-04, 02-06 | Sysop can create, update, list, and archive categories and boards from BOARDS tab. | SATISFIED | Domain actor-first CRUD exists; BOARDS tab uses those functions; 02-06 closes `:board_server_unavailable` submit error routing and test covers the real parent path. |
| SYSO-04 | 02-05 | Sysop can inspect system details from SYSTEM tab. | SATISFIED | Read-only snapshot renders required system fields and refreshes on `r`. |

No additional Phase 2 requirement IDs were found in `.planning/REQUIREMENTS.md` beyond INVT-06, INVT-07, SYSO-02, SYSO-03, and SYSO-04.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `lib/foglet_bbs/tui/screens/sysop.ex` | 120 | USERS placeholder | Info | Not a Phase 2 gap; USERS is outside this phase's requirement IDs. |
| `test/foglet_bbs/tui/screens/sysop_test.exs` | 839 | `Process.sleep(5)` in SYSTEM refresh test | Info | Existing test smell against project preference for synchronization, but it is not goal-blocking; the assertion only checks non-regressing uptime. |

### Human Verification Required

### 1. SITE and LIMITS SSH/TUI Pass

**Test:** Open Sysop over SSH, move through SITE and LIMITS, edit values, trigger inline validation, and save.
**Expected:** Rows render legibly, focus movement is understandable, ordinary typing and Ctrl+S match automated behavior, and validation/errors are readable.
**Why human:** Terminal rendering and keyboard feel cannot be fully verified by static inspection or unit tests.

### 2. BOARDS CRUD SSH/TUI Pass

**Test:** From BOARDS, create/edit/archive a board and category, including one validation error and one safe error-modal path if feasible.
**Expected:** Modal.Form overlays are usable, submit errors route to the shared error modal, list navigation is blocked while modals are open, and refreshed rows are visually coherent.
**Why human:** Handler tests verify state and domain wiring, but not the interactive terminal user experience.

### 3. SYSTEM SSH/TUI Pass

**Test:** Open SYSTEM and press `r`.
**Expected:** Version, uptime, session count, active boards, OTP process count, and DB pool size render clearly; `r` refreshes without mutating controls.
**Why human:** Snapshot data is programmatically verified, but final presentation still needs visual confirmation.

### Gaps Summary

The previous automated blocker is closed. `BoardsView.handle_submit_payload/2` now handles `{:error, reason} when is_atom(reason)` and resets local modal state before emitting `{:error_modal, db_error_message(reason), :main_menu}`. `Foglet.Boards.create_board/3` now documents and normalizes board-supervisor startup failures to `{:error, :board_server_unavailable}`, and the regression test drives the real `Sysop.handle_key/2` path to the parent error modal.

Automated checks verify the phase goal at the code and handler level. Final status remains `human_needed` because the deliverable is a terminal UI and the real SSH/Raxol interaction should be exercised manually before treating the phase as fully accepted.

---

_Verified: 2026-04-24T14:43:17Z_
_Verifier: Claude (gsd-verifier)_
