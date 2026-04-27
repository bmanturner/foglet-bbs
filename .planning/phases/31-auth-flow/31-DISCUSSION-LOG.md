# Phase 31: Auth Flow - Discussion Log (Assumptions Mode)

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md — this log preserves the analysis.

**Date:** 2026-04-27
**Phase:** 31-auth-flow
**Mode:** assumptions
**Areas analyzed:** Reset Request Surface, Token Consume Surface, Accounts Boundary, No-Email Copy And Sysop Contacts, Testing Shape

## Assumptions Presented

### Reset Request Surface
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| The Login menu should always expose `[F] Forgot password`, and the reset request screen should become email-only with inline field errors. | Likely | `.planning/phases/31-auth-flow/31-SPEC.md`; `lib/foglet_bbs/tui/screens/login.ex`; `lib/foglet_bbs/tui/screens/login/state.ex` |

### Token Consume Surface
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| `:reset_consume` should be implemented inside `Foglet.TUI.Screens.Login` with three `TextInput`s in screen-local state rather than using `Modal.Form`. | Likely | `lib/foglet_bbs/tui/screens/login.ex`; `lib/foglet_bbs/tui/screens/login/state.ex`; `.planning/phases/28-modal-form-substrate/28-CONTEXT.md` |

### Accounts Boundary
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Add the atomic raw-token consume operation to `Foglet.Accounts.Verification`, reusing `UserToken.verify_email_token_query/2`, `User.password_changeset/2`, and `Repo.transact/1`. | Confident | `.planning/phases/31-auth-flow/31-SPEC.md`; `lib/foglet_bbs/accounts/verification.ex`; `lib/foglet_bbs/accounts/user_token.ex`; `lib/foglet_bbs/accounts/user.ex` |

### No-Email Copy And Sysop Contacts
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Add a narrow Accounts/Verification helper for active, non-deleted sysop contact emails and render wrapped no-email copy in Login with `TextWidth.wrap/2`. | Likely | `.planning/phases/31-auth-flow/31-SPEC.md`; `lib/foglet_bbs/accounts.ex`; `lib/foglet_bbs/tui/text_width.ex`; AGENTS.md context-boundary guidance |

### Testing Shape
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Split tests across Accounts verification domain tests, Login key/state tests, and layout smoke tests for compact rendering and token non-leak checks. | Confident | `test/foglet_bbs/accounts/verification_test.exs`; `test/foglet_bbs/tui/screens/login_test.exs`; `test/foglet_bbs/tui/layout_smoke_test.exs` |

## Corrections Made

No corrections — all assumptions confirmed.
