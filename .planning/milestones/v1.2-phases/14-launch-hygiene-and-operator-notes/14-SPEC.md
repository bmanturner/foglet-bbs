# Phase 14: Launch Hygiene and Operator Notes - Specification

**Created:** 2026-04-24
**Ambiguity score:** 0.13 (gate: <= 0.20)
**Requirements:** 6 locked

## Goal

Foglet's pre-alpha terminal-visible operator surfaces, root README operator notes, and test suite accurately match the behavior implemented by phases 9-13 without adding new product scope.

## Background

Foglet is SSH-first and TUI-first. The current v1.2 roadmap closes pre-alpha gaps in delivery modes, user status administration, posting policy enforcement, SSH key management, and board subscription management before Phase 14 runs. Existing Sysop surfaces already include SITE, BOARDS, LIMITS, SYSTEM, USERS, and INVITES tabs, and config forms render schematized runtime keys through `Foglet.Config.Schema`. Some current copy is intentionally placeholder-like, such as the Sysop USERS tab saying user administration will arrive later, while earlier phase specs identify delivery-mode, approval, reset, and subscription copy that must become honest as those phases land.

The project also has many focused tests across domain contexts, TUI screens, widgets, SSH, Mix tasks, and configuration. Phase 14 is the final launch-hygiene pass: it audits what is visible after phases 9-13, fixes dishonest or dead launch-facing surfaces, rationalizes tests that are missing or low value, and makes the root `README.md` the practical pre-alpha operator guide. Nested `docs/` content may remain future-oriented or design-oriented, but root README must explain that status clearly.

## Requirements

1. **Visible Sysop configuration audit**: Every control rendered in the Sysop TUI either changes real runtime behavior or is disabled/unavailable with honest copy.
   - Current: Sysop SITE and LIMITS forms render selected schematized config keys; future phases may add delivery, user, subscription, or status controls before Phase 14 runs.
   - Target: Phase 14 audits the final pre-alpha Sysop TUI and fixes any visible config option that is dead, misleading, or not backed by real behavior.
   - Acceptance: A verifier can enumerate Sysop-visible config controls and confirm each one either persists through the owning context/config API and affects behavior, or renders as unavailable/disabled with explicit copy explaining that it is not currently supported.

2. **Schematized config accountability**: Every key in `Foglet.Config.Schema` is accounted for as operator-editable, intentionally hidden, or non-pre-alpha.
   - Current: Schematized keys exist independently from the subset rendered in Sysop forms, and later phases may add more keys.
   - Target: Phase 14 documents or tests the intended visibility status for every schematized key without requiring all keys to appear in the Sysop TUI.
   - Acceptance: A verifier can compare `Foglet.Config.Schema.entries/0` with Sysop form key lists and see no unexplained key: visible keys are tested through the UI or form layer, hidden keys have an intentional reason, and non-pre-alpha keys are not presented as available.

3. **Pre-alpha surface honesty audit**: Terminal-visible launch surfaces do not offer out-of-scope workflows or false delivery/admin claims.
   - Current: The roadmap explicitly excludes end-user browser workflows, webhook notifications, email digests, and full case-management moderation; earlier specs identify copy that must avoid false email, reset, approval, and sysop-action promises.
   - Target: Phase 14 audits TUI and Mix-task copy visible to users and operators after phases 9-13, then fixes copy that promises unimplemented browser admin, webhook delivery, email digests, full moderation case management, or unavailable email/operator workflows.
   - Acceptance: Focused tests or documented audit evidence prove no pre-alpha terminal surface offers browser admin, webhook notification, email digest, full case-management moderation, or email/reset/approval/subscription behavior that is not actually implemented.

4. **Root README operator notes**: `README.md` becomes the canonical pre-alpha operator guide for running Foglet.
   - Current: The roadmap requires operator notes for SMTP and no-email operation; nested `docs/` content exists and may describe design or future-oriented architecture.
   - Target: Root `README.md` explains SSH-first operation, SMTP mode, no-email mode, relevant break-glass Mix tasks, launch caveats, and that nested `docs/` may contain future-oriented/internal design material.
   - Acceptance: A verifier can use only `README.md` to identify how to operate Foglet in SMTP mode and no-email mode, what delivery/admin assumptions each mode implies, which key Mix tasks are available, and how to interpret nested `docs/`.

5. **Test audit and coverage fill**: Pre-alpha blocker flows have focused tests for happy path, forbidden path, and user-facing error/copy behavior where those risks exist.
   - Current: The test suite is broad, but phases 9-13 will add or change launch-blocker flows whose final coverage must be audited together.
   - Target: Phase 14 reviews tests for delivery modes, user status administration, posting policy enforcement, SSH key management, board subscriptions, Sysop config, and launch-visible copy, adding focused tests where meaningful coverage is missing.
   - Acceptance: A verifier can trace each v1.2 pre-alpha blocker requirement to tests or documented manual verification covering successful behavior, forbidden/unauthorized behavior, and user-facing error/copy behavior when applicable.

6. **Low-value test pruning**: Tests that cannot catch real regressions are removed or rewritten when deeper tests already cover the behavior.
   - Current: Some tests may assert static module existence, static copy without behavior, or framework plumbing that is already covered more deeply elsewhere.
   - Target: Phase 14 removes or rewrites tests that are too shallow to fail on meaningful regressions, while retaining tests that protect auth, persistence, TUI routing/copy, config behavior, and operator-visible workflows.
   - Acceptance: Any removed or rewritten test is justified by overlap or low defect-detection value, and the remaining or replacement coverage would fail on a realistic regression in the associated behavior.

## Boundaries

**In scope:**
- Audit-and-polish fixes for terminal-visible launch surfaces after phases 9-13.
- Narrow fixes for dishonest copy, dead controls, disabled/unavailable states, and missing visible-surface behavior wiring.
- Accountability for every schematized runtime config key.
- Root `README.md` operator notes for SMTP mode, no-email mode, SSH-first operation, break-glass Mix tasks, launch caveats, and nested-doc status.
- Test audit across v1.2 launch-blocker flows, with focused coverage added where useful.
- Removal or rewrite of tests that are static, redundant, or too shallow to catch realistic regressions.

**Out of scope:**
- Major implementation of incomplete Phase 9-13 core capabilities - those are blockers for their owning phases, not Phase 14 scope.
- New end-user browser workflows - Foglet remains SSH-first/TUI-first for this milestone.
- Moving operator notes into nested `docs/` files - root `README.md` is the required pre-alpha operator guide.
- Treating nested `docs/` as fully current operator documentation - README may explain that those docs are future-oriented/internal design material.
- Webhook notifications, email digests, delivery retry queues, outbound delivery logs, and full case-management moderation - these remain outside v1.2.
- A full v1.1 historical test audit unrelated to current pre-alpha-visible launch surfaces - older tests are touched only when Phase 14 audits or changes the related visible behavior.

## Constraints

- Phase 14 runs after phases 9-13 and must audit their final behavior rather than redefine their requirements.
- Foglet remains SSH-first; Phoenix/browser surfaces must not become end-user product workflows in this phase.
- Domain mutations must remain in `Foglet.*` contexts with authorization enforced there; TUI copy and disabled states are not authorization.
- `README.md` is the only required operator-note destination for this phase.
- Hidden or disabled UI must use honest copy and must not imply that a future feature is available now.
- Test pruning must be behavior-driven: remove or rewrite tests only when they are redundant, static, or too shallow to catch realistic regressions.

## Acceptance Criteria

- [ ] Every Sysop-visible configuration control is verified to affect real runtime behavior or render as disabled/unavailable with honest copy.
- [ ] Every `Foglet.Config.Schema` key is accounted for as visible, intentionally hidden, or non-pre-alpha.
- [ ] Pre-alpha terminal surfaces do not offer browser admin, webhook notifications, email digests, full case-management moderation, or unsupported delivery/admin workflows.
- [ ] Root `README.md` documents SMTP mode and no-email mode operation.
- [ ] Root `README.md` explains that nested `docs/` content may be future-oriented/internal design material at this stage.
- [ ] v1.2 launch-blocker flows have focused tests or documented verification for happy path, forbidden path, and user-facing error/copy behavior where applicable.
- [ ] Low-value tests removed or rewritten during the audit are justified by redundancy or inability to catch meaningful regressions.
- [ ] Phase 14 does not absorb major unfinished implementation from phases 9-13; such gaps are reported as blockers for the owning phase.

## Ambiguity Report

| Dimension           | Score | Min   | Status | Notes |
|---------------------|-------|-------|--------|-------|
| Goal Clarity        | 0.90  | 0.75  | met    | Audit/polish outcome is tied to visible launch surfaces, README notes, and test-suite quality. |
| Boundary Clarity    | 0.88  | 0.70  | met    | Major prior-phase implementation, nested docs operator notes, browser workflows, and v2 notification features are excluded. |
| Constraint Clarity  | 0.82  | 0.65  | met    | README-only operator-note destination, SSH-first boundary, config accountability, and behavior-driven test pruning are locked. |
| Acceptance Criteria | 0.86  | 0.70  | met    | Acceptance criteria are pass/fail checks against visible controls, config keys, README content, and test audit evidence. |
| **Ambiguity**       | 0.13  | <=0.20 | met    | Gate passed after round 2. |

Status: met = dimension meets minimum, below = planner treats as assumption

## Interview Log

| Round | Perspective | Question summary | Decision locked |
|-------|-------------|------------------|-----------------|
| 1 | Researcher | Should Phase 14 absorb incomplete work from phases 9-13? | Phase 14 is audit/polish with narrowly scoped fixes; major missing prior-phase capability is a blocker for its owning phase. |
| 1 | Researcher | Where should operator notes live? | Root `README.md`, not nested `docs/`, is the required pre-alpha operator-note destination. |
| 1 | Researcher | How broad is HYGN-02 testing? | Run a real test audit; add missing useful tests and remove or rewrite tests that are redundant or too shallow. |
| 2 | Researcher + Simplifier | What counts as a visible Sysop configuration option? | Sysop-rendered controls must work or be honest; every schematized config key must also be accounted for. |
| 2 | Simplifier | Should README be canonical and label nested docs status? | Yes; README is the practical pre-alpha guide and should explain that nested docs may be future-oriented/internal. |
| 2 | Simplifier | What is the test-pruning rule? | Remove or rewrite static, redundant, or plumbing-only tests; keep tests that would fail on meaningful regressions. |

---

*Phase: 14-launch-hygiene-and-operator-notes*
*Spec created: 2026-04-24*
*Next step: $gsd-discuss-phase 14 - implementation decisions (how to build what's specified above)*
