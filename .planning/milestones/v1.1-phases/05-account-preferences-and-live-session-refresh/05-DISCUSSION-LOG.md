# Phase 05: account-preferences-and-live-session-refresh - Discussion Log (Assumptions Mode)

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md — this log preserves the analysis.

**Date:** 2026-04-24
**Phase:** 05-account-preferences-and-live-session-refresh
**Mode:** assumptions
**Areas analyzed:** Persistence Contract, Validation Ownership, Account UI Shape, Live Session Refresh, Timex Use

## Assumptions Presented

### Persistence Contract
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Phase 5 should extend the existing `users` row and `Accounts.update_profile/2` path rather than introduce a separate preferences table or Account-specific persistence API. | Confident | `.planning/phases/05-account-preferences-and-live-session-refresh/05-SPEC.md`; `lib/foglet_bbs/accounts/user.ex`; `lib/foglet_bbs/accounts.ex`; existing users migration |

### Validation Ownership
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Validation for timezone, time format, and theme belongs in `Foglet.Accounts.User.profile_changeset/2`, with `Accounts.update_profile/2` remaining the mutation boundary. | Confident | `lib/foglet_bbs/accounts/user.ex`; `lib/foglet_bbs/accounts.ex`; `lib/foglet_bbs/tui/theme.ex`; `05-SPEC.md` invalid-save requirements |

### Account UI Shape
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Account profile and preferences should be edited inside the existing Account screen state using `Foglet.TUI.Widgets.Modal.Form` for save flows, while preserving the existing `INVITES` tab delegation untouched. | Likely | `.planning/phases/00-screen-shells-and-shared-surface-primitives/00-CONTEXT.md`; `.planning/phases/01.1-shared-modal-form-primitive/01.1-CONTEXT.md`; `.planning/phases/04-shared-invite-surface-activation/04-CONTEXT.md`; `lib/foglet_bbs/tui/screens/account.ex`; `lib/foglet_bbs/tui/screens/account/state.ex`; `lib/foglet_bbs/tui/widgets/modal/form.ex` |

### Live Session Refresh
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| A successful Account save should update three in-memory snapshots together: `state.current_user`, `state.session_context` preference fields including `theme`, and `Foglet.Sessions.Session` state through a new session update API. | Confident | `05-SPEC.md`; `lib/foglet_bbs/tui/app.ex`; `lib/foglet_bbs/tui/theme.ex`; `lib/foglet_bbs/ssh/cli_handler.ex`; `lib/foglet_bbs/sessions/session.ex` |

### Timex Use
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Use `Timex.Timezone.exists?/1` for IANA validation, `Timex.Timezone.local/0` plus `Timex.Timezone.name_of/1` to derive the system timezone, and fall back to `"Etc/UTC"` if resolution fails. | Likely | `05-SPEC.md`; HexDocs `Timex.Timezone` v3.7.13 |

## Corrections Made

### Account UI Shape
- **Original assumption:** Account profile and preferences should use `Foglet.TUI.Widgets.Modal.Form` for save flows.
- **User correction:** Prefer exploring inline form fields in the Account tabs, with researcher/planner deciding the final structure. Inline forms may make theme preview easier and can establish a reusable UX reference for future page-level TUI forms.
- **Reason:** The phase is partly exploratory from the user's perspective; Foglet is still discovering what account/preferences UX feels best in a terminal-native screen.

## External Research

- Timex timezone validation/defaulting: HexDocs for `Timex.Timezone` v3.7.13 documents `exists?/1`, `local/0`, and `name_of/1`, supporting the validation and best-effort local-default decision. Source: https://hexdocs.pm/timex/Timex.Timezone.html
