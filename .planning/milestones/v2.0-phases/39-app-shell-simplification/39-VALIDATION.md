---
phase: 39
slug: app-shell-simplification
status: complete
nyquist_compliant: true
wave_0_complete: true
created: 2026-04-28
updated: 2026-04-29
---

# Phase 39 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit (Elixir stdlib) |
| **Config file** | `test/test_helper.exs`, `mix.exs` `:test_paths` (default `["test"]`) |
| **Quick run command** | `rtk mix test test/foglet_bbs/tui/app_test.exs` |
| **Targeted screen test** | `rtk mix test test/foglet_bbs/tui/screens/<screen>_test.exs` |
| **Full suite command** | `rtk mix test` |
| **Pre-commit chain** | `rtk mix precommit` (compile-warnings-as-errors, deps.unlock, format, credo --strict, sobelow, dialyzer — does NOT run `mix test`) |
| **Headless render** | `rtk mix foglet.tui.render <screen>` (ANSI-stripped output for byte-equivalence checks) |
| **Estimated runtime (full suite)** | ~30–60 seconds (Elixir/ExUnit on this codebase) |

---

## Sampling Rate

- **After every task commit:** `rtk mix compile --warnings-as-errors && rtk mix test test/foglet_bbs/tui/app_test.exs test/foglet_bbs/tui/screens/<edited>_test.exs`
- **After every plan wave:** `rtk mix test` (full suite) + `rtk mix foglet.tui.render` for the five tracked screens (`main_menu`, `board_list`, `thread_list`, `post_reader`, `account`)
- **Before `/gsd-verify-work`:** `rtk mix precommit` exits 0 + full `rtk mix test` green + render byte-equivalence diff is empty (after ANSI strip)
- **Max feedback latency:** ~60 seconds

---

## Per-Task Verification Map

> The planner fills task IDs once plans exist. Below is the requirement-level scaffold derived from RESEARCH.md §Validation Architecture and SPEC §Acceptance Criteria.

| Requirement | Test Type | Automated Command | File Exists | Status |
|-------------|-----------|-------------------|-------------|--------|
| STATE-02 (struct fields removed; D-19 pin) | unit (struct shape pin) | `rtk mix test test/foglet_bbs/tui/app_struct_test.exs` | ✅ verified by 39-SUMMARY / 39-VERIFICATION | ✅ complete |
| STATE-03 (BreadcrumbBar reads explicit input; D-10..D-12) | unit + render smoke | `rtk mix test test/foglet_bbs/tui/widgets/chrome/breadcrumb_bar_test.exs` + `rtk mix foglet.tui.render thread_list,post_reader,post_composer,new_thread` | ✅ verified by 39-SUMMARY / Phase 40 breadcrumb coverage | ✅ complete |
| STATE-04 (decoder helpers gone) | grep absence | `! grep -nE 'post_reader_state_thread_id\|post_composer_state_thread_id\|thread_list_state_board_id' lib/foglet_bbs/tui/app.ex` | ✅ verified by 39-SUMMARY / 39-VERIFICATION | ✅ complete |
| APP-01 (App = runtime shell; SPEC R10) | qualitative review + struct-shape pin | covered by STATE-02; line-count delta reported in SUMMARY.md (non-gating) | ✅ verified by SPEC R10 table in 39-SUMMARY | ✅ complete |
| APP-02 (no screen-specific result handlers; D-13) | grep absence + reducer test | `! grep -nE 'current_screen ==\|current_screen in \[' lib/foglet_bbs/tui/app.ex`; existing BoardList / PostReader reducer tests prove `{:board_activity,…}` and `{:thread_activity,…}` reach `update/3` | ✅ verified by 39-SUMMARY / 39-VERIFICATION | ✅ complete |
| APP-03 (PubSub from screen-declared interests; D-05..D-09, D-22) | unit (subscription pin) | `rtk mix test test/foglet_bbs/tui/app_test.exs` (subscribe/1 describe block) + new MainMenu-only-`["user:<id>"]` pin (D-18) | ✅ verified by 39-SUMMARY and Phase 40 dynamic PubSub evidence | ✅ complete |
| APP-04 (Modal handling unchanged; SPEC R9) | unit (existing modal precedence + SizeGate tests) | `rtk mix test test/foglet_bbs/tui/app_test.exs --only describe:"modal key dismissal"` | ✅ verified by 39-SUMMARY / 39-VERIFICATION | ✅ complete |

**Additional pins required by SPEC R6, R7:**

| Pin | Test Type | Command | File Exists |
|-----|-----------|---------|-------------|
| `Foglet.TUI.Screen.behaviour_info(:optional_callbacks)` includes `{:subscriptions, 2}` | unit | new block in `test/foglet_bbs/tui/screen_test.exs` (or `app_test.exs`) | ❌ Wave 0 |
| `function_exported?(Foglet.TUI.Screens.PostReader, :subscriptions, 2) == true` | unit | new block in `post_reader_test.exs` | ❌ Wave 0 |
| `function_exported?(Foglet.TUI.Screens.ThreadList, :subscriptions, 2) == true` | unit | new block in `thread_list_test.exs` | ❌ Wave 0 |
| `function_exported?(Foglet.TUI.Screens.BoardList, :subscriptions, 2) == true` (D-22) | unit | new block in `board_list_test.exs` | ❌ Wave 0 |
| Topic-list equivalence for 4 cases (authenticated MainMenu, BoardList route, ThreadList with `board_id`, PostReader with `thread_id`) | unit | preserve existing `app_test.exs:1483-1607` (D-16) + new MainMenu pin (D-18) | ⚠ existing + 1 new |
| `mix foglet.tui.render` byte-equivalence after ANSI-strip for `main_menu`, `board_list`, `thread_list`, `post_reader`, `account` | golden-snapshot | `rtk mix foglet.tui.render <screen> \| sed 's/\x1b\[[0-9;]*m//g' \| diff baseline.txt -` | ❌ Wave 0 baseline capture |

---

## Wave 0 Requirements

Wave 0 must run BEFORE any source change so tests fail-loud against the live struct shape and so render baselines reflect the pre-phase state.

- [x] `test/foglet_bbs/tui/app_struct_test.exs` — new file; struct-shape pin (D-19)
- [x] New unit block in `test/foglet_bbs/tui/screen_test.exs` — `@optional_callbacks` includes `{:subscriptions, 2}` (SPEC R6)
- [x] New `function_exported?/3` pins for `:subscriptions/2` in `post_reader_test.exs`, `thread_list_test.exs`, `board_list_test.exs` (SPEC R6, D-22)
- [x] New `app_test.exs` `subscribe/1` pin: authenticated MainMenu produces only `["user:<id>"]` (D-18)
- [x] **Baseline capture** for `rtk mix foglet.tui.render` golden snapshots — captured pre-phase output for `main_menu`, `board_list`, `thread_list`, `post_reader`, `account` under `test/foglet_bbs/tui/render_snapshots/`.
- [x] Test-fixture migration plan body (per D-23) — enumerated and completed in `39-07-SUMMARY.md`.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| App ends as runtime shell (qualitative) | APP-01 / SPEC R10 | "Every function attributable to a runtime-shell responsibility" is a code-review judgement, not a grep | After all plans land, code-review `lib/foglet_bbs/tui/app.ex` end-to-end and confirm each function maps to one of: Raxol callback, message normalization, route storage, screen-state storage, context construction, effect interpretation, modal/SizeGate, session/PubSub plumbing, rendering dispatch. Record the line-count delta in `39-SUMMARY.md` (non-gating). |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references (struct pin, callback pin, function_exported pins, MainMenu pin, render baselines, fixture site enumeration)
- [x] No watch-mode flags (`mix test --listen-on-stdin` etc. forbidden)
- [x] Feedback latency < 60s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** complete
