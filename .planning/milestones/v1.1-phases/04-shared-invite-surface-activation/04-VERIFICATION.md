---
phase: 04-shared-invite-surface-activation
verified: 2026-04-24T02:13:42Z
status: human_needed
score: 10/10 must-haves verified
overrides_applied: 0
human_verification:
  - test: "Terminal rendering fit for live invite rows"
    expected: "Account, Moderation, and Sysop INVITES rows, statuses, errors, generated-code banner, and key hints fit without overlap at the project minimum terminal size."
    why_human: "Automated tests verify text/content and delegation, but terminal layout fit is visual."
---

# Phase 04: Shared Invite Surface Activation Verification Report

**Phase Goal:** shared invite surface activation across Account, Moderation, and Sysop with one shared live INVITES implementation.
**Verified:** 2026-04-24T02:13:42Z
**Status:** human_needed
**Re-verification:** No - initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Authorized actor can open shared INVITES from Account, Moderation, or Sysop according to `invite_code_generators`. | VERIFIED | Account uses `ShellVisibility.invites_visible?/2`; Moderation exposes INVITES only for `:mod` + `"mods"`; Sysop refreshes tabs from `ShellVisibility.invites_visible?/2`. Tests cover `any_user`, `mods`, and `sysop_only` matrices. |
| 2 | Sysop/mod restricted policies provide unlimited invite generation for the permitted role. | VERIFIED | Moderation and Sysop tests assert `persists exactly one invite`, `last_generated_code`, and policy-specific generation under `"mods"` and `"sysop_only"`. |
| 3 | Invite behavior is shared across surfaces rather than duplicated per screen. | VERIFIED | `account.ex`, `moderation.ex`, and `sysop.ex` delegate to `InvitesActions.handle_key/3` and `InvitesActions.load/2`; static scan found no direct `Accounts.create_invite/list_invites/revoke_invite` or `FogletBbs.Repo` calls in shell modules. |
| 4 | Shared INVITES state loads persisted invite statuses through `Foglet.Accounts.list_invites/1`. | VERIFIED | `InvitesActions.load/2` and post-mutation refreshes call `Accounts.list_invites/1`; action tests compare state against persisted `Accounts.list_invites/1` results. |
| 5 | Shared INVITES rendering shows available, consumed, and revoked rows with lifecycle fields. | VERIFIED | `InvitesSurface.row_label/1` renders code, status, issuer_id, inserted_at, consumed_at, consumed_by_user_id, and revoked_at; surface tests assert all fields. |
| 6 | Shared actions generate, refresh, select, revoke, and map errors without per-screen logic. | VERIFIED | `InvitesActions` exposes `load/2`, `refresh/2`, `generate/2`, `select_next/1`, `select_prev/1`, `revoke_selected/2`, and `handle_key/3`; screens only delegate active INVITES keys. |
| 7 | Account INVITES is visible and live only for regular users under `any_user`. | VERIFIED | Account render and handle-key paths sync visibility from runtime policy, load on tab entry, and delegate INVITES keys; tests cover hidden policies and live generation. |
| 8 | Moderation INVITES is visible and live only for moderators under `mods`. | VERIFIED | Moderation-specific visibility rejects sysops, regular users, nil users, and non-`mods` policies; tests cover live moderator generation. |
| 9 | Sysop INVITES is visible and live for sysop policies. | VERIFIED | Sysop state appends INVITES for sysop-visible policies and delegates active INVITES keys; tests cover `sysop_only`, `mods`, `any_user`, and non-sysop denial. |
| 10 | Full Phase 04 focused tests and quality gate pass. | VERIFIED | Local run: focused Phase 04 command including `test/foglet_bbs/accounts/invite_test.exs` passed, 111 tests, 0 failures. `mix precommit` passed successfully. |

**Score:** 10/10 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `lib/foglet_bbs/tui/screens/shared/invites_actions.ex` | Single shared load/refresh/generate/select/revoke/error path | VERIFIED | Exists, substantive, wired to `Foglet.Accounts` only. |
| `lib/foglet_bbs/tui/screens/shared/invites_state.ex` | Live invite rows, selection, loading/error, generated code, frame | VERIFIED | Exists with required fields and state transition helpers. |
| `lib/foglet_bbs/tui/screens/shared/invites_surface.ex` | Live INVITES renderer | VERIFIED | Renders list states, lifecycle rows, generated-code banner, errors, and key hints. |
| `lib/foglet_bbs/tui/screens/account.ex` / `state.ex` | Account visibility and shared action delegation | VERIFIED | Runtime policy sync, load-on-enter, active-tab delegation. |
| `lib/foglet_bbs/tui/screens/moderation.ex` / `state.ex` | Moderation visibility and shared action delegation | VERIFIED | Moderator-only `mods` INVITES path, active-tab delegation. |
| `lib/foglet_bbs/tui/screens/sysop.ex` / `state.ex` | Sysop visibility and shared action delegation | VERIFIED | Runtime tab refresh, load-on-entry, active-tab delegation. |
| Phase 04 focused tests | Visibility, rendering, generate, revoke, non-duplication coverage | VERIFIED | Required test files exist and passed in focused run. |

### Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| `InvitesActions` | `Foglet.Accounts` | `create_invite/1`, `list_invites/1`, `revoke_invite/2` | WIRED | Static scan found only these invite domain calls in shared actions. |
| `InvitesSurface` | `InvitesState` shape | Direct render of state fields | WIRED | Renders `items`, `selected_index`, `last_generated_code`, `error`, and `frame` from shared state/map shape. |
| Account | `InvitesActions` | active INVITES tab key delegation | WIRED | `maybe_load_invites/2` and `delegate_invites_key/3`. |
| Moderation | `InvitesActions` | active INVITES tab key delegation | WIRED | `maybe_load_invites/2` and `delegate_to_active_tab/3`. |
| Sysop | `InvitesActions` | active INVITES tab delegation before submodule fallback | WIRED | `maybe_load_invites_on_entry/2` and `delegate_to_invites/3`. |
| Tests | shared implementation | behavior assertions and static non-duplication checks | WIRED | Tests assert generation/revoke behavior and absence of shell-local invite domain calls. |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|---|---|---|---|---|
| `InvitesActions` | `items` | `Accounts.list_invites(actor)` | Yes, persisted invite status maps | FLOWING |
| `InvitesActions` | `last_generated_code` | `Accounts.create_invite(actor)` return value, then `list_invites/1` refresh | Yes, persisted invite code | FLOWING |
| `InvitesActions` | revoke result state | `Accounts.revoke_invite(actor, code)`, then `list_invites/1` refresh | Yes, persisted revoked status | FLOWING |
| `InvitesSurface` | rendered rows | `state.items` populated by shared actions | Yes, displays Accounts status maps | FLOWING |
| Account/Moderation/Sysop | screen invite state | shared `InvitesActions.load/2` and `handle_key/3` | Yes, active tab loads and mutates via shared state | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| Focused Phase 04 tests | `mix test test/foglet_bbs/tui/screens/shared/invites_surface_test.exs test/foglet_bbs/tui/screens/account_test.exs test/foglet_bbs/tui/screens/moderation_test.exs test/foglet_bbs/tui/screens/sysop_test.exs test/foglet_bbs/tui/screens/shared/invites_actions_test.exs test/foglet_bbs/accounts/invite_test.exs` | 111 tests, 0 failures | PASS |
| Screen-only focused tests from requested files | `mix test test/foglet_bbs/tui/screens/shared/invites_actions_test.exs test/foglet_bbs/tui/screens/shared/invites_surface_test.exs test/foglet_bbs/tui/screens/account_test.exs test/foglet_bbs/tui/screens/moderation_test.exs test/foglet_bbs/tui/screens/sysop_test.exs` | 98 tests, 0 failures | PASS |
| Final quality gate | `mix precommit` | compile, format, Credo, Sobelow, Dialyzer completed; passed successfully | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|---|---|---|---|---|
| INVT-01 | 04-01, 04-02, 04-03, 04-04, 04-05 | Authorized actor can open shared `INVITES` tab from Account, Moderation, or Sysop according to `invite_code_generators`. | SATISFIED | Account, Moderation, and Sysop all expose conditional INVITES and delegate to shared actions; tests cover policy matrices. |
| MODR-04 | 04-01, 04-03, 04-05 | If `invite_code_generators` is `mods`, moderator workspace includes shared `INVITES` tab with unlimited invite generation. | SATISFIED | Moderation visibility restricts to mod actors under `"mods"` and tests assert persisted generation plus `last_generated_code`. |
| SYSO-05 | 04-01, 04-04, 04-05 | If `invite_code_generators` is `sysop_only`, Sysop workspace includes shared `INVITES` tab with unlimited invite generation. | SATISFIED | Sysop appends INVITES for sysop visibility policies and tests assert persisted `sysop_only` generation. |

All Phase 04 requirement IDs declared in PLAN frontmatter are accounted for in `.planning/REQUIREMENTS.md`. No orphaned Phase 04 requirement IDs were found.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|---|---:|---|---|---|
| `lib/foglet_bbs/tui/screens/account.ex` | 176 | Existing PROFILE/PREFS later-phase placeholder copy | Info | Outside Phase 04 INVITES goal; Phase 5 covers Account profile/preferences. |
| `lib/foglet_bbs/tui/screens/moderation.ex` | 124 | Existing moderation placeholder copy | Info | Outside Phase 04 INVITES goal; Phase 8 covers populated moderation workspace. |
| `lib/foglet_bbs/tui/screens/sysop.ex` | 121 | Existing USERS later-phase placeholder copy | Info | Outside Phase 04 INVITES goal and not on invite path. |

No blocking invite-path stubs, direct Repo access, per-screen invite lifecycle duplication, or scaffold/future-placeholder copy in `InvitesSurface` were found.

### Human Verification Required

### 1. Terminal Rendering Fit For Live Invite Rows

**Test:** Start the TUI, open each allowed `INVITES` tab, and inspect rows, status labels, error text, generated-code banner, and key hints at the project minimum terminal size.
**Expected:** Content is readable and does not overlap or obscure adjacent UI.
**Why human:** Automated tests verify text and state behavior, but terminal layout fit is visual.

### Gaps Summary

No code or wiring gaps found. The phase goal is achieved in the codebase. Remaining status is `human_needed` only because the validation plan includes a manual terminal rendering fit check.

---

_Verified: 2026-04-24T02:13:42Z_
_Verifier: Claude (gsd-verifier)_
