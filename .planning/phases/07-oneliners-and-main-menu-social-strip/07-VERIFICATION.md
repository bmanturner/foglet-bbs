---
phase: 07-oneliners-and-main-menu-social-strip
verified: 2026-04-24T03:47:52Z
status: human_needed
score: 12/12 must-haves verified
overrides_applied: 0
human_verification:
  - test: "SSH into the TUI as an authenticated user with existing visible oneliners."
    expected: "The first main-menu render shows the Oneliners strip with recent rows, keeps the normal menu/key bar visible, and does not show timestamps or hide controls."
    why_human: "Terminal visual layout and first-render feel need human inspection beyond structural render tests."
  - test: "Press O from the main menu, type a valid oneliner, submit it, then try an invalid/same-user post."
    expected: "The composer is focused, valid submit returns to the main menu with a refreshed strip, and invalid submit keeps the modal open with visible error copy."
    why_human: "End-to-end keyboard focus and modal interaction in the real terminal runtime need human confirmation."
---

# Phase 07: Oneliners and Main Menu Social Strip Verification Report

**Phase Goal:** The main menu gains a persistent, bounded social strip that feels alive without becoming chat-like noise.
**Verified:** 2026-04-24T03:47:52Z
**Status:** human_needed
**Re-verification:** No - initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | User oneliners are persisted in Postgres and survive application restart. | VERIFIED | Migration creates `oneliners`; `Foglet.Oneliners.create_entry/2` inserts through `Repo.transact`/`repo.insert` in `lib/foglet_bbs/oneliners.ex:26`. |
| 2 | Recent visible oneliners can be loaded newest first for the main menu. | VERIFIED | `list_recent_visible/1` filters `hidden == false`, orders by `desc: inserted_at`, bounds limit, and preloads users in `lib/foglet_bbs/oneliners.ex:47`. |
| 3 | Blank and 121-character bodies are rejected before insert; 120-character bodies are accepted. | VERIFIED | `Entry.create_changeset/2` trims, requires body/user, and validates `min: 1, max: 120` in `lib/foglet_bbs/oneliners/entry.ex:31`; tests cover blank/121/120. |
| 4 | The same authenticated user cannot create two visible oneliners in a row. | VERIFIED | `ensure_not_latest_visible_user/2` rejects same-user latest visible; domain test asserts row count unchanged. |
| 5 | User can view recent oneliners on the main menu. | VERIFIED | `MainMenu.render/1` reads `state.recent_oneliners` and renders an `Oneliners` split pane in `lib/foglet_bbs/tui/screens/main_menu.ex:62`. |
| 6 | The main menu keeps navigation, role-gated entries, and key-bar affordances intact. | VERIFIED | Existing B/C/A/M/S/Q handlers and visibility predicates remain; `main_menu_test.exs` covers role visibility and key handling. |
| 7 | Oneliner rows are one-line `@handle  body` rows with no timestamps. | VERIFIED | `oneliner_row/1` formats handle/body only and clips to one line in `lib/foglet_bbs/tui/screens/main_menu.ex:178`; tests assert no timestamp strings. |
| 8 | Opening or returning to main menu loads a bounded recent oneliner list. | VERIFIED | `App.init/1` calls `maybe_load_initial_oneliners/1`; `{:navigate, :main_menu}`, `{:set_user, user}`, `{:promote_session, user}`, and successful submit route through `{:load_oneliners}`. Review warning WR-01 is fixed by `lib/foglet_bbs/tui/app.ex:106` and test coverage at `test/foglet_bbs/tui/app_test.exs:42`. |
| 9 | User can press O on the main menu to open a focused oneliner composer modal. | VERIFIED | `MainMenu.handle_key/2` emits `{:open_oneliner_composer}`; `App` opens a `ModalForm` titled `Post Oneliner` with `max_length: 120`. |
| 10 | Valid submit persists one oneliner, refreshes the recent list, closes the modal, and returns to main menu. | VERIFIED | `{:submit_oneliner, %{body: body}}` calls `create_entry(current_user, %{body: body})`; `{:oneliner_created, {:ok, _}}` clears modal and queues reload in `lib/foglet_bbs/tui/app.ex:447`. |
| 11 | Invalid submit stays focused with a visible error and inserts no row. | VERIFIED | Domain rejects invalid bodies/same-user posts before insert; App maps changeset and same-user errors into focused modal errors in `lib/foglet_bbs/tui/app.ex:467`. |
| 12 | Cancel returns to main menu without creating an oneliner. | VERIFIED | Modal cancel routes to `:dismiss_modal`; app test asserts modal clears, screen remains main menu, and no create call is received. |

**Score:** 12/12 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/foglet_bbs/oneliners.ex` | Context with create/list APIs | VERIFIED | Exports `create_entry/2` and `list_recent_visible/1`; wired to Repo and Entry. |
| `lib/foglet_bbs/oneliners/entry.ex` | Schema and `create_changeset/2` | VERIFIED | Locked fields, hidden default, no `updated_at`, body-only cast. |
| `priv/repo/migrations/20260424024644_create_oneliners.exs` | Oneliners table and visible-recents index | VERIFIED | Manual glob check found the migration; `gsd-sdk verify.artifacts` had a glob false negative. |
| `test/foglet_bbs/oneliners/oneliners_test.exs` | Domain persistence tests | VERIFIED | Covers schema, validation, actor ownership, listing, and same-user rejection. |
| `lib/foglet_bbs/tui/screens/main_menu.ex` | Stateless split-pane renderer and O command | VERIFIED | Uses `split_pane`, `recent_oneliners`, bounded rows, no Repo/domain calls. |
| `test/foglet_bbs/tui/screens/main_menu_test.exs` | Main menu render/key tests | VERIFIED | Covers nil/empty, row format, clipping, no timestamps, statelessness, and O key. |
| `test/foglet_bbs/tui/layout_smoke_test.exs` | 80x24 layout smoke coverage | VERIFIED | Asserts menu and sample oneliner row render at positioned text coordinates. |
| `lib/foglet_bbs/tui/app.ex` | App-owned load/composer/submit/refresh routing | VERIFIED | Owns `recent_oneliners`, load tasks, modal form, submit result handling, and errors. |
| `test/foglet_bbs/tui/app_test.exs` | App lifecycle integration coverage | VERIFIED | Covers init load, load result, composer open/cancel/submit, success refresh, and same-user error. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `lib/foglet_bbs/oneliners.ex` | `FogletBbs.Repo` | `Repo.transact`, `repo.insert`, `Repo.all` | WIRED | Manual grep verified `Repo.transact`, `repo.insert`, and `Repo.all`; SDK regex missed lowercase transaction binding. |
| `lib/foglet_bbs/oneliners.ex` | `Foglet.Oneliners.Entry` | changeset and Ecto query | WIRED | `Entry.create_changeset(attrs)` and `from e in Entry` are present. |
| `lib/foglet_bbs/tui/screens/main_menu.ex` | `state.recent_oneliners` | render reads loaded app state | WIRED | `oneliner_rows/2` reads `Map.get(:recent_oneliners, [])`. |
| `lib/foglet_bbs/tui/screens/main_menu.ex` | `Foglet.TUI.App` | O key command handled by App | WIRED | MainMenu emits `{:open_oneliner_composer}`; App handles that tuple. |
| `lib/foglet_bbs/tui/app.ex` | `Foglet.Oneliners` | `domain_module(state, :oneliners)` | WIRED | Default domain module is `Foglet.Oneliners`; tests inject `Foglet.TUI.FakeOneliners`. |
| `lib/foglet_bbs/tui/app.ex` | `Foglet.TUI.Widgets.Modal.Form` | open composer modal | WIRED | Aliased as `ModalForm`; composer uses `ModalForm.init/1` and `ModalForm.set_errors/2`. |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `MainMenu.render/1` | `state.recent_oneliners` | `App` state populated by `Foglet.Oneliners.list_recent_visible(5)` | Yes | FLOWING |
| `App` oneliner load | `recent_oneliners` | `domain_module(state, :oneliners).list_recent_visible(@oneliner_limit)` | Yes | FLOWING |
| `App` submit | `body` modal payload | `domain_module(state, :oneliners).create_entry(state.current_user, %{body: body})` | Yes | FLOWING |
| `Foglet.Oneliners` recents | `Entry` rows | `Repo.all(from e in Entry, where: e.hidden == false, preload: [:user])` | Yes | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Phase 7 domain/TUI targeted suite | `mix test test/foglet_bbs/oneliners/oneliners_test.exs test/foglet_bbs/tui/screens/main_menu_test.exs test/foglet_bbs/tui/app_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` | 154 tests, 0 failures | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| ONEL-01 | 07-01, 07-02, 07-03 | User can view recent oneliners on the main menu. | SATISFIED | Domain recents list, App load state, MainMenu render, and layout/render tests verified. |
| ONEL-02 | 07-03 | User can post a short oneliner from the main menu. | SATISFIED | O key opens composer; submit calls `create_entry/2`; success refreshes and closes modal. |
| ONEL-03 | 07-01, 07-03 | Oneliner posts persist across restart and respect a bounded maximum length. | SATISFIED | Postgres migration/schema/context exist; body validation is 1-120; tests cover persistence and boundaries. |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `lib/foglet_bbs/tui/screens/main_menu.ex` | 13 | Historical "placeholders" wording in module docs | Info | Refers to Phase 0 shells, not Phase 7 oneliner implementation. |
| `test/foglet_bbs/tui/app_test.exs` | 325 | Negative assertion for `Hide oneliner` / `hidden_reason` | Info | Test-only proof that Phase 7 does not expose moderation UI. |

### Human Verification Required

### 1. First Render Visual Check

**Test:** SSH into the TUI as an authenticated user with existing visible oneliners.
**Expected:** The first main-menu render shows the Oneliners strip with recent rows, keeps the normal menu/key bar visible, and does not show timestamps or hide controls.
**Why human:** Terminal visual layout and first-render feel need human inspection beyond structural render tests.

### 2. Composer Interaction Check

**Test:** Press O from the main menu, type a valid oneliner, submit it, then try an invalid/same-user post.
**Expected:** The composer is focused, valid submit returns to the main menu with a refreshed strip, and invalid submit keeps the modal open with visible error copy.
**Why human:** End-to-end keyboard focus and modal interaction in the real terminal runtime need human confirmation.

### Gaps Summary

No automated gaps found. All plan truths, artifacts, key links, data flow, requirements, and the code-review warning about authenticated startup are verified. Status is `human_needed` only because this phase changes terminal visual layout and interactive keyboard flow.

---

_Verified: 2026-04-24T03:47:52Z_
_Verifier: Claude (gsd-verifier)_
