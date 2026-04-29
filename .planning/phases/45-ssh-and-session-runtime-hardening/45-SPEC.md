# Phase 45: SSH And Session Runtime Hardening - Specification

**Created:** 2026-04-29
**Ambiguity score:** 0.14 (gate: <= 0.20)
**Requirements:** 5 locked

## Goal

Operators can trust SSH authentication handoff, guest promotion audit logs, channel termination cleanup, and connection accounting across normal and fragile lifecycle paths.

## Background

Phase 45 covers the remaining SSH/session runtime concerns from the v2.1 concerns audit. `Foglet.SSH.PubkeyStash` currently stores public keys offered during SSH authentication in public ETS and deletes entries only when `Foglet.SSH.CLIHandler` successfully pops them after `ssh_channel_up`; orphaned entries can remain if a connection dies before the channel handler starts. `Foglet.Sessions.Session` currently logs guest promotion with user identity, but it does not include peer context or replacement context from the SSH channel/session path. `Foglet.SSH.CLIHandler` currently owns SSH channel lifecycle, alt-screen restoration, Raxol lifecycle shutdown, session shutdown, channel close, and the global ETS connection counter, but termination behavior is open-coded across `{:EXIT, lifecycle, _}`, `{:eof, _}`, `{:closed, _}`, and `terminate/2`. Existing tests cover several direct and real SSH paths, but the roadmap requires explicit confidence for all listed connection-counter lifecycle paths. `Foglet.Sessions.Supervisor` already has direct coverage for the `replace_then_promote/3` timeout fallback branch that kills a non-supervised registry holder and promotes the guest; this phase must preserve that coverage as the acceptance proof for SESS-01.

## Requirements

1. **Bound public-key stash**: `Foglet.SSH.PubkeyStash` must automatically remove orphaned key-offer entries using TTL-based sweep behavior.
   - Current: Stash entries are deleted only by `pop/1`; the module docs explicitly say periodic sweep is not implemented.
   - Target: Offered public keys have bounded lifetime, and stale entries older than the chosen TTL can be swept without waiting for a matching SSH channel.
   - Acceptance: A focused test can insert an entry, make it stale through the public or test-supported API, run the sweep path, and prove the stale entry is gone while a fresh entry remains available.

2. **Structured promotion audit logs**: Guest-to-user SSH session promotion must emit structured Logger metadata for audit-grade visibility.
   - Current: `Foglet.Sessions.Session` logs `user_id` and `handle` on promotion, while peer context lives in `Foglet.SSH.CLIHandler` state and is not attached to the promotion audit trail.
   - Target: Promotion logging includes the promoted guest/session identity, target user identity, whether a prior session was replaced when known, and peer context when available.
   - Acceptance: Direct tests or log-capture assertions prove a guest promotion emits structured metadata with user id/handle and includes peer metadata when the promotion path has peer context.

3. **Unified SSH termination cleanup**: SSH channel termination behavior must be routed through one helper that owns full cleanup.
   - Current: Alt-screen leave, lifecycle stop, session stop, channel close, and counter decrement are open-coded across multiple callbacks.
   - Target: One helper owns alt-screen leave, lifecycle stop, session stop, connection-counter decrement, and channel close where applicable; callback branches delegate termination cleanup to that helper.
   - Acceptance: Code inspection and focused tests prove `{:EXIT, lifecycle, _}`, `{:closed, _}`, and handler termination paths use the shared helper for cleanup-sensitive behavior.

4. **Balanced SSH connection counter**: The global SSH connection counter must remain balanced across all roadmap-listed lifecycle paths.
   - Current: The counter is initialized by `Foglet.SSH.Supervisor`, incremented inside `check_connection_limit/0`, and decremented in selected termination paths; existing coverage does not explicitly prove every listed path.
   - Target: Counter behavior is proven for normal close, EOF-to-close, lifecycle exit, over-limit reject, rate-limit reject, and crash-during-init paths.
   - Acceptance: Focused tests reset the counter, exercise each listed path, and assert the counter returns to the expected value without going negative or drifting upward.

5. **Preserved forced-promotion fallback coverage**: The `replace_then_promote/3` forced-termination fallback must remain directly covered.
   - Current: `test/foglet_bbs/sessions/supervisor_test.exs` includes a direct test for a registry holder that does not stop gracefully; the test proves the holder is killed and the guest is promoted.
   - Target: That direct coverage remains in place as the acceptance proof for SESS-01, updated only if implementation changes require equivalent assertions.
   - Acceptance: The session supervisor test suite includes a deterministic test proving the timeout fallback kills a non-supervised registry holder and promotes the guest into the registry slot.

## Boundaries

**In scope:**
- TTL-based sweep behavior for `Foglet.SSH.PubkeyStash`.
- Structured Logger metadata for guest-to-user promotion auditing.
- A shared SSH termination cleanup helper for cleanup-sensitive CLIHandler paths.
- Direct connection-counter balance proof for normal close, EOF-to-close, lifecycle exit, over-limit reject, rate-limit reject, and crash-during-init paths.
- Preservation or equivalent replacement of the existing `replace_then_promote/3` forced-termination fallback test.

**Out of scope:**
- New end-user browser workflows - Foglet remains SSH-first and terminal-native.
- Durable database audit records for SSH session promotion - structured logs are the locked requirement for this phase.
- Broader rate limiter, daemon owner, or TUI lifecycle redesign - this phase hardens the mapped SSH/session requirements only.
- Changing one-session-per-user semantics - SESS-01 requires proof of the existing safety behavior, not a new replacement model.
- Replacing Raxol or changing screen behavior - this phase is runtime hardening, not a UI product change.

## Constraints

- Keep domain workflows inside `Foglet.*` contexts and runtime modules; Phoenix remains infrastructure only.
- Use focused behavior tests rather than pure text-presence assertions.
- SSH tests must synchronize with monitors, callbacks, or direct state checks; avoid `Process.sleep/1`.
- ETS remains ephemeral and reconstructable after restart; new stash state must not become durable application state.
- Avoid adding new public product surfaces while hardening the SSH-first runtime.

## Acceptance Criteria

- [ ] `Foglet.SSH.PubkeyStash` has TTL-based sweep behavior that removes stale entries and preserves fresh entries.
- [ ] Guest-to-user promotion emits structured Logger metadata with user identity and peer context when available.
- [ ] SSH termination cleanup-sensitive callbacks delegate alt-screen leave, lifecycle stop, session stop, counter decrement, and applicable channel close behavior to one helper.
- [ ] Counter tests prove expected balance for normal close, EOF-to-close, lifecycle exit, over-limit reject, rate-limit reject, and crash-during-init paths.
- [ ] Direct `replace_then_promote/3` fallback coverage remains present or is replaced by equivalent deterministic coverage.
- [ ] `rtk mix precommit` passes after implementation.

## Ambiguity Report

| Dimension           | Score | Min   | Status | Notes |
|---------------------|-------|-------|--------|-------|
| Goal Clarity        | 0.93  | 0.75  | met    | Roadmap goal mapped to five concrete runtime outcomes. |
| Boundary Clarity    | 0.86  | 0.70  | met    | Scope locked to SSH-01 through SSH-04 and SESS-01 only. |
| Constraint Clarity  | 0.79  | 0.65  | met    | SSH-first, ETS-ephemeral, structured-log, and test constraints are explicit. |
| Acceptance Criteria | 0.82  | 0.70  | met    | Each requirement has pass/fail acceptance checks. |
| **Ambiguity**       | 0.14  | <=0.20 | met    | Gate passed after round 2. |

Status: met = dimension meets minimum; below = planner treats as assumption.

## Interview Log

| Round | Perspective | Question summary | Decision locked |
|-------|-------------|------------------|-----------------|
| 1 | Researcher | What counts as bounded public-key stash behavior? | TTL sweep cleanup is required for orphaned key offers. |
| 1 | Researcher | What level of promotion audit visibility is required? | Structured Logger metadata is required; durable DB audit is out of scope. |
| 1 | Researcher | Which counter paths require proof? | Normal close, EOF-to-close, lifecycle exit, over-limit reject, rate-limit reject, and crash-during-init all require proof. |
| 2 | Researcher/Simplifier | What must the termination helper own? | Full cleanup: alt-screen leave, lifecycle stop, session stop, counter decrement, and channel close where applicable. |
| 2 | Researcher/Simplifier | What is the simplest successful phase? | Harden exactly SSH-01 through SSH-04 and SESS-01; no adjacent runtime expansion. |
| 2 | Researcher/Simplifier | What proof is required for `replace_then_promote/3` fallback? | Existing direct coverage is acceptable as the SESS-01 proof, provided it remains deterministic and equivalent. |

---

*Phase: 45-ssh-and-session-runtime-hardening*
*Spec created: 2026-04-29*
*Next step: $gsd-discuss-phase 45 - implementation decisions (how to build what's specified above)*
