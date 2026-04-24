# Phase 12: Account SSH Key Management - Discussion Log (Assumptions Mode)

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md — this log preserves the analysis.

**Date:** 2026-04-24T16:40:55Z
**Phase:** 12-account-ssh-key-management
**Mode:** assumptions
**Areas analyzed:** Domain Key Lifecycle, Authentication And Last-Used Recording, Account TUI Integration, Test Shape

## Assumptions Presented

### Domain Key Lifecycle
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| SSH key add/list/revoke behavior should be implemented as `Foglet.Accounts` APIs, with ownership enforced by taking the current `%User{}` actor and the key id/label being operated on; revocation should hard-delete the owned row unless planning later explicitly chooses soft revocation. | Likely | `.planning/phases/12-account-ssh-key-management/12-SPEC.md`, `lib/foglet_bbs/accounts.ex`, `lib/foglet_bbs/accounts/ssh_key.ex`, `priv/repo/migrations/20260418000003_create_ssh_keys.exs`, `docs/DATA_MODEL.md` |

### Authentication And Last-Used Recording
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Successful public-key auth should update `last_used_at` inside the Accounts lookup path, likely by adding a new Accounts function for authentication use that finds the matching key and user together, updates only that key, and returns the user; `CLIHandler` should continue only orchestrating stash pop, key encoding, and session start. | Likely | `lib/foglet_bbs/ssh/key_cb.ex`, `lib/foglet_bbs/ssh/pubkey_stash.ex`, `lib/foglet_bbs/ssh/cli_handler.ex`, `lib/foglet_bbs/accounts.ex`, `test/foglet_bbs/ssh/cli_handler_test.exs` |

### Account TUI Integration
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| The Account SSH KEYS surface should be added as another Account tab with screen-local state and a sibling form/actions module, following the existing PROFILE/PREFS/INVITES pattern; the screen should render already-loaded key state and route persistence through Accounts-facing actions rather than calling Repo. | Confident | `lib/foglet_bbs/tui/screens/account/state.ex`, `lib/foglet_bbs/tui/screens/account.ex`, `lib/foglet_bbs/tui/screens/account/profile_form.ex`, `lib/foglet_bbs/tui/screens/account/prefs_form.ex`, `lib/foglet_bbs/tui/screens/shared/invites_actions.ex`, `lib/foglet_bbs/tui/screens/shared/invites_surface.ex`, `lib/foglet_bbs/tui/widgets/README.md` |

### Test Shape
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Phase tests should extend the existing focused test files: Accounts SSH key tests for validation/ownership/revoke/lookup/last-used, SSH CLI handler tests for registered/deleted/revoked auth behavior, and Account screen tests for tab navigation, empty/list/add/revoke rendering and commands. | Confident | `test/foglet_bbs/accounts/ssh_key_test.exs`, `test/foglet_bbs/ssh/cli_handler_test.exs`, `test/foglet_bbs/ssh/key_cb_test.exs`, `test/foglet_bbs/tui/screens/account_test.exs`, `test/support/accounts_fixtures.ex` |

## Corrections Made

No corrections — all assumptions confirmed.

## External Research

No external research was needed; the codebase and locked Phase 12 SPEC provided enough evidence.
