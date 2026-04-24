# Phase 9: Delivery Modes and Onboarding Honesty - Context

**Gathered:** 2026-04-24 (assumptions mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Verification and password-reset flows only operate when email delivery is configured through Swoosh, and no-email operation prevents verification and password reset from being offered as valid user workflows. This phase adds honest delivery-mode behavior, terminal-native reset request behavior in Swoosh mode, operator visibility for delivery implications, and copy/tests for MAIL-01 through MAIL-06. It does not add browser reset pages, no-email relay workflows, approval/rejection notification delivery, webhook/email digest features, durable delivery logs, or full user-status administration.
</domain>

<decisions>
## Implementation Decisions

### Delivery Mode Configuration
- **D-01:** Represent delivery mode as one schematized, runtime-editable, non-secret config key with exactly two enum values: Swoosh email delivery enabled and explicit no-email mode.
- **D-02:** Expose delivery mode through a typed `Foglet.Config` accessor so `Foglet.Accounts`, TUI screens, Sysop forms, tests, and Mix tasks branch from one canonical runtime API.
- **D-03:** Keep Swoosh adapter settings, API keys, SMTP credentials, and other secrets in runtime/environment configuration, not in DB-backed `configuration` rows.

### Verification Delivery Boundary
- **D-04:** Registration, login re-entry, and Verify-screen resend should stop treating `Accounts.build_verify_code/1` as the delivery workflow.
- **D-05:** Add an Accounts-level delivery function that creates the verification code, attempts Swoosh delivery when email mode is enabled, and returns only generic success/failure information to TUI callers.
- **D-06:** TUI screens should render delivery state and copy from Accounts/Config results; they should not own Swoosh calls, direct token persistence, or ad hoc delivery-mode branching.
- **D-07:** Preserve existing Verify-screen code entry, invalid-attempt cooldown, resend cooldown, and their independence while changing resend success/failure copy to match attempted delivery.

### Password Reset Flow
- **D-08:** Add a terminal-native password-reset request subflow to the Login screen, available only when Swoosh email mode is configured.
- **D-09:** Back user-requested reset with an enumeration-safe Accounts function that targets active, non-deleted users and gives the same outward response for unknown, deleted, inactive, and delivery-failure cases.
- **D-10:** Do not expose the existing browser-style reset URL to end users. User-facing reset delivery must not point to unimplemented browser reset pages.
- **D-11:** Preserve operator break-glass reset intent, but align the Mix task with delivery mode so no-email mode does not present normal user reset delivery as available.

### Operator Surfaces And Honest Copy
- **D-12:** Integrate delivery-mode visibility and editability into existing Sysop config surfaces rather than creating a separate administration surface.
- **D-13:** Existing Sysop config placement rules still apply: new schematized keys must be intentionally placed in the correct tab/form list and not appear accidentally.
- **D-14:** Normal operator configuration must block or clearly flag `delivery_mode=no_email` combined with `require_email_verification=true`.
- **D-15:** Update Register, Login, Verify, Sysop, and reset-task copy so it distinguishes emailed instructions, delivery attempted, no-email unavailable paths, pending sysop approval, and break-glass generated outcomes.
- **D-16:** Pending approval copy must remain honest for Phase 9 and must not promise MAIL-07 approval/rejection notification delivery before Phase 10 implements it.

### the agent's Discretion
- Exact enum key name and enum string values, as long as the two user-visible states are unambiguous and typed.
- Exact terminal layout for the Login reset-request subflow, provided it follows existing Login screen patterns and remains SSH/TUI-first.
- Exact generic success/failure wording, provided tests prove it avoids false delivery claims and user enumeration.
- Exact Swoosh mailer module placement and adapter configuration pattern, subject to official Swoosh/Phoenix guidance during research.

### Folded Todos
None.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Locked Phase Requirements
- `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-SPEC.md` — Locked requirements, boundaries, constraints, and acceptance criteria for MAIL-01 through MAIL-06.
- `.planning/ROADMAP.md` — Phase 9 roadmap goal, dependencies, success criteria, and milestone boundary.
- `.planning/PROJECT.md` — SSH-first product direction, current milestone goal, constraints, and out-of-scope browser/reach features.
- `.planning/STATE.md` — Current v1.2 position and recent decisions affecting Phase 9.

### Prior Config And Sysop Decisions
- `.planning/milestones/v1.1-phases/02-sysop-config-and-board-management/02-CONTEXT.md` — Sysop config surface decisions, including explicit tab placement for schematized config keys.
- `docs/DATA_MODEL.md` — Data model conventions and runtime configuration persistence constraints.

### Codebase Maps
- `.planning/codebase/ARCHITECTURE.md` — SSH/TUI/domain layering, Config cache, and command routing patterns.
- `.planning/codebase/CONVENTIONS.md` — Context boundaries, typed accessors, specs, tests, and precommit expectations.
- `.planning/codebase/INTEGRATIONS.md` — Current absence of outgoing external integrations and Swoosh/mailers.
- `.planning/codebase/TESTING.md` — ExUnit organization, async/sync guidance, config test constraints, and fixture patterns.
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Foglet.Config.Schema` and `Foglet.Config` already provide the pattern for schematized runtime keys, validation, ETS-backed reads, actor-aware writes, and typed accessors.
- `Foglet.Accounts.UserToken.build_verify_code/1`, `Accounts.build_verify_code/1`, and `Accounts.verify_email_code/2` provide the existing verification-code persistence and verification semantics that delivery functions should wrap rather than duplicate.
- `Accounts.deliver_user_reset_password_instructions/2` and `UserToken.build_email_token/2` provide reset token persistence, but current URL-return behavior needs to be separated from user-facing delivery.
- `Foglet.TUI.Screens.Login`, `Register`, and `Verify` already contain the user flows that need delivery-mode-aware branching and honest copy.
- Existing Sysop `site_form.ex` and `limits_form.ex` show how config keys are placed, rendered, validated, and saved through `Config.put/3`.
- Mix task patterns in `lib/mix/tasks/foglet.user.reset_password.ex` and related tests provide the break-glass tooling shape.

### Established Patterns
- Domain decisions and side effects belong in `Foglet.*` contexts; TUI screens consume context results and return commands/state changes.
- Runtime-editable config keys are declared in `Foglet.Config.Schema`, seeded, cached, and exposed with typed accessors.
- Actor-triggered config writes use `Config.put/3`; trusted setup/test paths use `Config.put!/3`.
- TUI copy and screen logic are tested directly under `test/foglet_bbs/tui/screens/*_test.exs`.
- Tests that mutate global config cache/state should use `async: false` and restore or invalidate config explicitly.

### Integration Points
- Add Swoosh dependency, mailer module, runtime adapter config, and test adapter setup based on official Swoosh/Phoenix guidance.
- Update config schema/seeds/tests for the delivery-mode key and invalid no-email-plus-verification validation.
- Update Accounts verification/reset APIs so TUI and Mix callers do not branch independently.
- Update Login/Register/Verify screens and tests for delivery-mode-aware reset/verification flows and honest copy.
- Update Sysop config forms/tests so delivery mode is visible and invalid combinations are blocked or flagged.
- Update `foglet.user.reset_password` task/tests so no-email mode is unavailable and Swoosh mode preserves intended reset behavior.
</code_context>

<specifics>
## Specific Ideas

No specific external product reference was provided. The accepted direction is conservative and codebase-native: keep the experience terminal-first, avoid browser reset links, centralize delivery behavior in Accounts/Config, and make every visible message honest about what Foglet actually attempted.
</specifics>

<deferred>
## Deferred Ideas

- MAIL-07 approval/rejection notification delivery — Phase 10.
- Browser password-reset pages or other end-user browser workflows — out of scope for v1.2 unless architecture docs change.
- No-email verification relay and no-email password-reset relay — explicitly invalid for Phase 9.
- Webhook notifications, email digests, delivery retry queues, outbound delivery logs, and durable background delivery processing — future notification/reach work.

### Reviewed Todos (not folded)
None.
</deferred>

---

*Phase: 09-delivery-modes-and-onboarding-honesty*
*Context gathered: 2026-04-24*
