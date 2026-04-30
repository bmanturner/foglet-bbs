---
phase: 43-large-screen-decomposition
verified: 2026-04-30T00:34:07Z
status: gaps_found
score: 8/9 must-haves verified
overrides_applied: 0
gaps:
  - truth: "Render modules remain pure over loaded state/context and avoid Repo, PubSub, task starts, durable writes, runtime config reads, and screen-state mutations."
    status: failed
    reason: "Sysop.Render lazy-initializes SiteForm during render when ss.site_form is nil; SiteForm.State.new/1 loads drafts with Config.get!/1, so a render path still performs runtime config reads instead of consuming already-loaded screen state."
    artifacts:
      - path: "lib/foglet_bbs/tui/screens/sysop/render.ex"
        issue: "render_tab_body(\"SITE\", ...) calls SiteForm.render(SiteForm.init([]), theme) from inside render."
      - path: "lib/foglet_bbs/tui/screens/sysop/site_form/state.ex"
        issue: "SiteForm.State.new/1 calls load_drafts/0, which calls Config.get!/1 for each site key."
    missing:
      - "Initialize Sysop site_form on the reducer/state side, or route SITE config loading through update/effects, so Sysop.Render only renders an already-loaded SiteForm state."
---

# Phase 43: Large Screen Decomposition Verification Report

**Phase Goal:** Maintainers can work on oversized TUI screens through clear reducer, state, and render boundaries.
**Verified:** 2026-04-30T00:34:07Z
**Status:** gaps_found
**Re-verification:** No - initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|---|---|---|
| 1 | Maintainer can modify PostReader, Sysop, Login, MainMenu, NewThread, and Account screen rendering without digging through unrelated reducer code. | VERIFIED | All six screens have sibling render modules under `lib/foglet_bbs/tui/screens/*/render.ex`; top-level modules delegate via `Render.render(...)`; detailed helper-family grep found no moved helper names remaining in top-level screen modules. |
| 2 | Maintainer can test reducer behavior for decomposed screens without invoking render helpers. | VERIFIED | Direct `update/3` reducer tests exist across all six target screen test files; combined Phase 43 screen/layout suite passed: 547 tests, 0 failures. |
| 3 | Maintainer can identify each decomposed screen's local state owner and render entry point from module names and documentation. | VERIFIED | `layout_smoke_test.exs:274` checks top-level, state, and render files/modules for all six; `SCREEN_CONTRACT.md:204` documents the large-screen pattern and names the Phase 43 examples. |
| 4 | Existing TUI behavior remains stable through reducer tests and render smoke verification after the splits. | VERIFIED | Targeted Phase 43 suite passed; `rtk mix foglet.tui.render --list` listed all six target screens; CLI render smokes for `login`, `main_menu`, `new_thread`, `account`, `sysop`, and `post_reader` exited 0. |
| 5 | Top-level screen modules remain reducer-facing `Foglet.TUI.Screen` implementations. | VERIFIED | Each top-level module exports `init/1`, `update/3`, and `render/2`; Sysop/PostReader retain subscriptions/public non-render seams where required. |
| 6 | Render modules own frame/content/keybar assembly and detailed body/tab/helper rendering. | VERIFIED | Render modules call `ScreenFrame.render` and own screen body assembly; Sysop/Account render modules still orchestrate existing body surface modules instead of replacing them. |
| 7 | Render modules keep styling through `Foglet.TUI.Theme` and existing widgets. | VERIFIED | Render modules call `Theme.from_state`/`Theme.resolve` and existing widgets such as `ScreenFrame`, `Tabs`, `SelectionList`, `EditorFrame`, `PostCard`, and `Spinner`; no visual workflow redesign found. |
| 8 | Review fixes are actually present. | VERIFIED | `PostReader.Render.render/2` uses `context.terminal_size || @default_terminal_size`; direct render modules for Login/NewThread no longer contain `Config.get`, `Config.get!`, or `Config.fetch`. |
| 9 | Render modules remain pure over loaded state/context and avoid runtime reads, side effects, and state mutation. | FAILED | `Sysop.Render` line 156 calls `SiteForm.init([])` in render; `SiteForm.State.new/1` line 88 loads drafts, and `load_drafts/0` line 181 calls `Config.get!/1`. This violates the Phase 43 contract in `SCREEN_CONTRACT.md:213-219`. |

**Score:** 8/9 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `lib/foglet_bbs/tui/screens/{post_reader,sysop,login,main_menu,new_thread,account}.ex` | Reducer-facing screen modules | VERIFIED | Export `init/1`, `update/3`, `render/2`; top-level render callbacks delegate to sibling render modules. |
| `lib/foglet_bbs/tui/screens/{post_reader,sysop,login,main_menu,new_thread,account}/state.ex` | Local state owners | VERIFIED | All six state modules exist and load. |
| `lib/foglet_bbs/tui/screens/{post_reader,sysop,login,main_menu,new_thread,account}/render.ex` | Render entry points | PARTIAL | All six exist and are wired; Sysop render has an indirect runtime config read gap. |
| `lib/foglet_bbs/tui/SCREEN_CONTRACT.md` | Large screen decomposition docs | VERIFIED | Section `## Large Screen Decomposition` exists and states reducer/state/render responsibilities and render constraints. |
| `test/foglet_bbs/tui/layout_smoke_test.exs` | Cross-screen source-shape and render smoke coverage | VERIFIED | Checks all six target files/modules and forbidden runtime-call strings in render files. |

### Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| Top-level screen modules | Sibling render modules | `Render.render(...)` callbacks | VERIFIED | Delegation found in all six top-level modules. |
| Render modules | Existing widgets/surfaces | `ScreenFrame.render`, `Tabs.render`, `PostCard`, `SiteForm`, `ProfileForm`, etc. | VERIFIED | Rendering responsibilities moved without replacing established surface widgets. |
| Reducer modules | Domain/runtime side effects | `Effect.task`, modal submit, context calls | VERIFIED | Effects remain in top-level reducer modules rather than render modules. |
| `Sysop.Render` | `SiteForm.State` config loading | `SiteForm.init([])` during render | FAILED | Indirect render-time `Config.get!/1` remains. |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|---|---|---|---|---|
| `PostReader.Render` | `%State{}.posts`, `render_cache`, selected index | `PostReader.update/3`, bounded window task paths, reducer-owned warm/cache helpers | Yes | VERIFIED |
| `NewThread.Render` | `%State{}` fields and configured limits | `NewThread.init/1`, reducer validation, `session_context`/state fields | Yes | VERIFIED |
| `Login.Render` | local login state and session registration mode | `Login.init/1`, `Login.update/3`, `context.session_context` | Yes | VERIFIED |
| `MainMenu.Render` | `%MainMenu.State{}` and visible command data | `MainMenu.normalize_state/2`, `visible_destination_entries/1`, `visible_actions/1` | Yes | VERIFIED |
| `Account.Render` | `%Account.State{}` tabs/forms/theme preview | `Account.init/1`, `Account.update/3`, derived render model | Yes | VERIFIED |
| `Sysop.Render` | `%Sysop.State{}.site_form` | Existing state if present; otherwise `SiteForm.init([])` during render | No, render fetches config itself on nil state | FAILED |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| Phase 43 reducer/layout suite | `rtk mix test test/foglet_bbs/tui/screens/new_thread_test.exs test/foglet_bbs/tui/screens/login_test.exs test/foglet_bbs/tui/screens/main_menu_test.exs test/foglet_bbs/tui/screens/sysop_test.exs test/foglet_bbs/tui/screens/account_test.exs test/foglet_bbs/tui/screens/post_reader_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` | 547 tests, 0 failures | PASS |
| Compile gate | `rtk mix compile --warnings-as-errors` | Exit 0 | PASS |
| Render screen discovery | `rtk mix foglet.tui.render --list` | Listed `login`, `main_menu`, `new_thread`, `account`, `sysop`, `post_reader` | PASS |
| CLI render smoke | `rtk mix foglet.tui.render login --no-frame` and five sibling commands | All six exited 0 | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|---|---|---|---|---|
| TUI-05 | 43-01 through 43-05 | Maintainer can work on the largest TUI screens through separated reducer/state/render modules where mixed responsibilities were identified. | BLOCKED | Structural split is present for all six screens, but Sysop render still owns a runtime config-loading path, so mixed render/data responsibility remains. |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|---|---:|---|---|---|
| `lib/foglet_bbs/tui/screens/sysop/render.ex` | 156 | `SiteForm.render(SiteForm.init([]), theme)` | BLOCKER | Render path initializes state instead of consuming already-loaded state. |
| `lib/foglet_bbs/tui/screens/sysop/site_form/state.ex` | 181 | `Config.get!/1` in `load_drafts/0` | BLOCKER | The render-time SiteForm initialization can hit runtime config/Repo through the ETS-backed cache. |

### Human Verification Required

None required for this verifier decision. CLI render smoke verified the named screens render without crashing; the blocker is a deterministic code/data-flow violation.

### Gaps Summary

Phase 43 substantially completed the decomposition shape: files exist, top-level screen modules delegate, reducer tests and render smokes pass, and the review fixes for PostReader nil terminal size plus Login/NewThread config reads are present.

The phase goal is still blocked because `Sysop.Render` has one remaining render-time data-loading path. The fix should move `SiteForm` initialization/config loading to the reducer/state side, so render receives either a loaded `site_form` or an explicit loading/error state and never calls `SiteForm.init/1`.

---

_Verified: 2026-04-30T00:34:07Z_
_Verifier: the agent (gsd-verifier)_
