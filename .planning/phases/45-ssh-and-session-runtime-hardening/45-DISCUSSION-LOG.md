# Phase 45: SSH And Session Runtime Hardening - Discussion Log (Assumptions Mode)

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md - this log preserves the analysis.

**Date:** 2026-04-30
**Phase:** 45-ssh-and-session-runtime-hardening
**Mode:** assumptions
**Areas analyzed:** Public-Key Stash Cleanup, Promotion Audit Metadata, Unified CLIHandler Cleanup, Connection Counter Proof, Forced-Promotion Fallback

## Assumptions Presented

### Public-Key Stash Cleanup

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| PubkeyStash should get explicit timestamped TTL sweep APIs, not durable storage or a new auth model. | Confident | `45-SPEC.md`; `lib/foglet_bbs/ssh/pubkey_stash.ex`; `lib/foglet_bbs/ssh/key_cb.ex`; `.planning/codebase/CONCERNS.md` |
| `put/2` and `pop/1` should stay compatible while adding a deterministic stale-entry sweep path. | Likely | `test/foglet_bbs/ssh/cli_handler_test.exs`; `test/foglet_bbs/ssh/key_cb_test.exs` |

### Promotion Audit Metadata

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Peer metadata should be carried from CLIHandler through SessionContext/App/Sessions, because promotion happens after channel-up. | Likely | `lib/foglet_bbs/ssh/cli_handler.ex`; `lib/foglet_bbs/tui/session_context.ex`; `lib/foglet_bbs/tui/app.ex`; `lib/foglet_bbs/sessions/session.ex` |
| Promotion logging should use structured Logger metadata with user, session, peer, and replacement context when known; durable DB audit is out of scope. | Confident | `45-SPEC.md`; `lib/foglet_bbs/sessions/session.ex`; `.planning/codebase/CONCERNS.md` |

### Unified CLIHandler Cleanup

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| CLIHandler termination paths should delegate to one cleanup helper that owns alt-screen leave, lifecycle stop, session stop, counter decrement, and channel close where applicable. | Confident | `45-SPEC.md`; `lib/foglet_bbs/ssh/cli_handler.ex`; `.planning/codebase/CONCERNS.md` |
| The cleanup helper must be idempotent enough to tolerate EOF, closed, lifecycle EXIT, and terminate ordering without double decrement. | Likely | `lib/foglet_bbs/ssh/cli_handler.ex`; `test/foglet_bbs/ssh/cli_handler_test.exs` |

### Connection Counter Proof

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Counter proof should combine deterministic direct callback/unit tests with existing real SSH tests where useful, instead of full network simulations for every branch. | Likely | `test/foglet_bbs/ssh/cli_handler_test.exs`; `.planning/codebase/TESTING.md`; `45-SPEC.md` |
| Over-limit and rate-limit rejection should be proven as reject states that do not require later decrement. | Likely | `lib/foglet_bbs/ssh/cli_handler.ex`; `lib/foglet_bbs/ssh/rate_limiter.ex`; `test/foglet_bbs/ssh/rate_limiter_test.exs` |

### Forced-Promotion Fallback

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| The existing forced fallback test should remain the SESS-01 proof unless implementation changes require equivalent coverage. | Confident | `45-SPEC.md`; `test/foglet_bbs/sessions/supervisor_test.exs`; `lib/foglet_bbs/sessions/supervisor.ex` |

## Corrections Made

No corrections - all assumptions confirmed.
