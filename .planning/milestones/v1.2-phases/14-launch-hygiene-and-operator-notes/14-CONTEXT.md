# Phase 14: Launch Hygiene and Operator Notes - Context

**Gathered:** 2026-04-24 (assumptions mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 14 audits and polishes the pre-alpha-visible behavior produced by Phases 9-13 so Sysop settings, terminal copy, tests, and root operator notes match what Foglet actually supports. It may make narrow launch-hygiene fixes for dishonest copy, dead controls, disabled/unavailable states, README operator guidance, and missing or low-value tests. Major missing Phase 9-13 capabilities are upstream blockers for their owning phases, not implementation scope for Phase 14.
</domain>

<decisions>
## Implementation Decisions

### Phase Boundary Enforcement
- **D-01:** Treat Phase 14 as an audit-and-polish pass over completed Phase 9-13 behavior, not as a catch-all implementation phase for unfinished upstream features.
- **D-02:** If a core Phase 9-13 capability is still missing or too incomplete to audit, report it as a blocker for the owning phase instead of absorbing it into Phase 14.
- **D-03:** Allow narrow fixes only when they align an already-scoped visible surface with implemented behavior, such as honest copy, disabled/unavailable states, README notes, focused tests, or small wiring corrections.

### Sysop Config Accountability
- **D-04:** Drive config accountability from `Foglet.Config.Schema.entries/0`, comparing every schematized key with Sysop-visible form key lists.
- **D-05:** Classify every schematized key as visible, conditionally visible, intentionally hidden, or non-pre-alpha, with a launch-facing reason for any key that is not always visible.
- **D-06:** Preserve existing Sysop SITE/LIMITS form patterns for rendered keys, but strengthen tests or audit evidence beyond simple partition coverage so each visible control is tied to real behavior or honest unavailability.

### Launch-Facing Copy And README
- **D-07:** Perform a cross-surface copy audit over terminal-visible TUI screens, Mix tasks, and root `README.md`, prioritizing removal of false email, browser, webhook, digest, sysop-action, and full case-management claims.
- **D-08:** Rewrite root `README.md` as the canonical pre-alpha operator guide rather than leaving it as target-state product copy.
- **D-09:** README operator notes must cover SSH-first operation, SMTP mode, no-email mode, relevant break-glass Mix tasks, launch caveats, and the fact that nested `docs/` may contain future-oriented or internal design material.
- **D-10:** Do not create or move the required operator guide into nested `docs/`; root `README.md` is the required destination for this phase.

### Test Audit Shape
- **D-11:** Preserve behavior-rich context, TUI, SSH, config, and Mix task tests that would fail on realistic regressions.
- **D-12:** Add focused tests or documented verification for visible v1.2 launch-blocker claims where happy path, forbidden path, and user-facing error/copy behavior are meaningful risks.
- **D-13:** Remove or rewrite only tests that are static, redundant, or too shallow to catch realistic regressions, and justify each removal or rewrite by overlap or low defect-detection value.
- **D-14:** Prefer traceable launch-hygiene coverage over broad snapshot-style copy assertions; tests should prove behavior or visible claims tied to implemented behavior.

### the agent's Discretion
- Exact format for the config accountability artifact or test structure, provided every schematized key has an explicit visibility classification and reason.
- Exact README organization and wording, provided it is practical for pre-alpha operators and does not imply unsupported workflows.
- Exact copy-audit search terms and test grouping, provided terminal-visible false claims are covered and fixed.
- Exact pruning candidates, provided each removal or rewrite is justified and behavior-rich coverage remains.

### Folded Todos
None.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Locked Phase Requirements
- `.planning/phases/14-launch-hygiene-and-operator-notes/14-SPEC.md` - Locked requirements, boundaries, constraints, acceptance criteria, and audit/pruning rules for Phase 14.
- `.planning/ROADMAP.md` - Phase 14 roadmap goal, dependency on Phase 13, success criteria, and v1.2 milestone boundary.
- `.planning/REQUIREMENTS.md` - HYGN-01 through HYGN-03 traceability and v1.2 out-of-scope feature list.
- `.planning/PROJECT.md` - SSH-first product direction, current milestone goal, validated decisions, and out-of-scope browser/reach features.
- `.planning/STATE.md` - Current milestone position, deferred UAT/verification items, and recent decisions affecting Phase 14.

### Upstream Phase Contracts
- `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-CONTEXT.md` - Delivery-mode, SMTP/no-email, reset, verification, and honest-copy decisions consumed by Phase 14.
- `.planning/phases/10-user-status-administration/10-CONTEXT.md` - User status, Sysop USERS, notification, login-copy, and break-glass task decisions consumed by Phase 14.
- `.planning/phases/11-posting-policy-enforcement/11-CONTEXT.md` - Posting-policy enforcement and structured terminal error decisions consumed by Phase 14.
- `.planning/phases/12-account-ssh-key-management/12-CONTEXT.md` - SSH key management, public-key auth metadata, Account TUI, and test-shape decisions consumed by Phase 14.
- `.planning/phases/13-board-subscription-management/13-SPEC.md` - Locked board subscription requirements and empty-state/operator-task expectations. Phase 13 has no committed context yet, so treat the SPEC as the canonical upstream contract.

### Codebase Maps And Domain Docs
- `.planning/codebase/ARCHITECTURE.md` - SSH/TUI/domain layering, Config cache, command routing, and Phoenix operational boundary.
- `.planning/codebase/CONVENTIONS.md` - Context boundaries, typed accessors, specs, tests, docs, and precommit expectations.
- `.planning/codebase/STRUCTURE.md` - Source/test layout and relevant TUI, Mix task, config, and README locations.
- `.planning/codebase/TESTING.md` - ExUnit organization, async/sync guidance, config test constraints, fixtures, and process-test rules.
- `docs/DATA_MODEL.md` - Runtime configuration persistence, user/account, board subscription, and data-model conventions.
- `docs/raxol/getting-started/WIDGET_GALLERY.md` - Relevant terminal widget primitives if Phase 14 touches disabled/unavailable control rendering.
- `lib/foglet_bbs/tui/widgets/README.md` - Foglet widget theming and stateful/stateless widget contracts if Phase 14 touches widgets.
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Foglet.Config.Schema.entries/0`, `fetch_spec/1`, and typed `Foglet.Config` accessors provide the authoritative list of schematized runtime keys to audit.
- `Foglet.TUI.Screens.Sysop.SiteForm.visible_keys/1` and `Foglet.TUI.Screens.Sysop.LimitsForm.visible_keys/1` expose the existing Sysop config visibility model.
- `test/foglet_bbs/tui/screens/sysop_test.exs`, `test/foglet_bbs/config_test.exs`, and `test/foglet_bbs/config/schema_test.exs` already cover much of the config schema and Sysop form behavior that Phase 14 should strengthen into launch accountability.
- Existing TUI screen tests under `test/foglet_bbs/tui/screens/` and Mix task tests under `test/mix/tasks/` provide the preferred places for copy and break-glass behavior checks.
- Root `README.md` is available and currently reads as target-state product copy, making it the direct target for operator-note replacement.

### Established Patterns
- Domain behavior lives in `Foglet.*` contexts; Phase 14 should not make TUI copy or disabled controls the enforcement boundary.
- Runtime-editable config keys are declared in `Foglet.Config.Schema`, seeded, cached, and exposed with typed accessors.
- Sysop config UI is split into tab-specific modules instead of placing all logic in `Sysop.render/1`.
- Tests mirror the source tree and should cite requirement IDs where practical.
- Tests that mutate global config/cache state should be `async: false` and isolate ETS/config state explicitly.
- Project finish line remains `mix precommit`, run through `rtk mix precommit` in this repo.

### Integration Points
- Audit `lib/foglet_bbs/config/schema.ex`, `lib/foglet_bbs/tui/screens/sysop/site_form.ex`, `lib/foglet_bbs/tui/screens/sysop/limits_form.ex`, and Sysop tests for schematized-key accountability.
- Audit TUI copy across `lib/foglet_bbs/tui/screens/` and relevant tests for unsupported browser admin, webhook, email digest, full case-management moderation, false email, reset, approval, and subscription claims.
- Audit Mix task copy and tests under `lib/mix/tasks/` and `test/mix/tasks/`, especially break-glass reset/status/subscription tasks after upstream phases land.
- Replace or substantially revise root `README.md` so operators can identify SMTP mode, no-email mode, break-glass tasks, launch caveats, SSH-first operation, and nested-doc status without reading other docs.
- Review v1.2 blocker-flow tests after Phases 9-13 are implemented, adding focused gaps and pruning static/redundant tests only where better behavioral coverage exists.
</code_context>

<specifics>
## Specific Ideas

The confirmed direction is conservative and codebase-native: Phase 14 should make the launch surface honest, traceable, and operator-usable without expanding the product. README should become a practical pre-alpha operator guide, while nested docs may remain design or future-facing as long as README labels that status clearly.
</specifics>

<deferred>
## Deferred Ideas

- Major incomplete Phase 9-13 capabilities discovered during the audit are blockers for their owning phase, not Phase 14 scope.
- End-user browser workflows, webhook notifications, email digests, outbound delivery logs/retry queues, and full case-management moderation remain out of scope for v1.2.
- A nested `docs/SYSOP.md` or broader docs overhaul can happen later; this phase requires root `README.md`.

### Reviewed Todos (not folded)
None.
</deferred>

---

*Phase: 14-launch-hygiene-and-operator-notes*
*Context gathered: 2026-04-24*
