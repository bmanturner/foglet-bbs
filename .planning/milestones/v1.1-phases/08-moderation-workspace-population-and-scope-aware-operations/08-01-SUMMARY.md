---
phase: 08-moderation-workspace-population-and-scope-aware-operations
plan: 01
subsystem: database
tags: [moderation, oneliners, authorization, ecto, audit-log]
requires:
  - phase: 01-authorization-and-scope-backbone
    provides: "Foglet.Authorization Bodyguard policy and scopes_for/2 contract"
  - phase: 07-oneliners-and-main-menu-social-strip
    provides: "Persisted oneliners with hidden fields and recent-visible listing"
provides:
  - "mod_actions persistence for hide-oneliner audit records"
  - "Foglet.Moderation.Action schema and narrow audit context"
  - "Foglet.Oneliners.hide_entry/3 actor-first trust boundary"
  - "Database-backed tests for authorization, reason validation, audit side effects, and visible-list exclusion"
affects: [moderation-workspace, main-menu-oneliners, audit-log]
tech-stack:
  added: []
  patterns: ["Actor-first domain mutation with Bodyguard.permit/4 before side effects", "Programmatic moderator/target id assignment outside caller attrs"]
key-files:
  created:
    - priv/repo/migrations/20260424030000_create_mod_actions.exs
    - lib/foglet_bbs/moderation/action.ex
    - lib/foglet_bbs/moderation.ex
    - test/foglet_bbs/moderation/moderation_test.exs
  modified:
    - lib/foglet_bbs/oneliners.ex
    - lib/foglet_bbs/oneliners/entry.ex
    - test/foglet_bbs/oneliners/oneliners_test.exs
key-decisions:
  - "Oneliners are site-scoped in v1.1; board-scope tuples are accepted by list APIs but do not see site hide actions."
  - "Hide audit writes stay narrow to :hide_oneliner and do not introduce reports, sanctions, or broad moderation workflows."
patterns-established:
  - "Use Foglet.Authorization.scopes_for/2 as a list and then Bodyguard.permit/4 for the selected operation scope."
  - "Set hidden_by_id, mod_id, and target_id from trusted structs rather than caller attrs."
requirements-completed: [MODR-05]
duration: 9min
completed: 2026-04-24
---

# Phase 08 Plan 01: Domain Hide and Audit Persistence Summary

**Authorized oneliner hides with durable `mod_actions` audit records and failure paths that leave both oneliners and audit logs untouched.**

## Performance

- **Duration:** 9 min
- **Started:** 2026-04-24T12:55:00Z
- **Completed:** 2026-04-24T13:03:56Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments

- Added `mod_actions` persistence with constrained hide-oneliner audit rows.
- Added `Foglet.Moderation.record_hide_oneliner!/4` and `list_actions_for_scopes/2`.
- Added `Foglet.Oneliners.hide_entry/3` with actor-first authorization, required trimmed reasons, transactional mutation plus audit insert, and metadata capture.
- Covered success and failure behavior with database-backed tests.

## Task Commits

1. **Task 1 RED: Add moderation audit tests** - `0263538` (test)
2. **Task 1 GREEN: Add moderation audit persistence** - `c83cd78` (feat)
3. **Task 2 RED: Add oneliner hide tests** - `c7a672e` (test)
4. **Task 2 GREEN: Implement actor-first oneliner hide** - `30091b8` (feat)

## Files Created/Modified

- `priv/repo/migrations/20260424030000_create_mod_actions.exs` - Creates constrained audit table and indexes.
- `lib/foglet_bbs/moderation/action.ex` - Ecto schema for hide-oneliner audit actions.
- `lib/foglet_bbs/moderation.ex` - Narrow moderation audit context.
- `lib/foglet_bbs/oneliners.ex` - Adds authorized `hide_entry/3` trust-boundary operation.
- `lib/foglet_bbs/oneliners/entry.ex` - Adds trusted hide changeset without casting `hidden_by_id`.
- `test/foglet_bbs/moderation/moderation_test.exs` - Covers audit insertion and scope-shaped listing.
- `test/foglet_bbs/oneliners/oneliners_test.exs` - Covers hide authorization, validation, audit counts, and visible listing exclusion.

## Decisions Made

- Site scope is required to hide oneliners in v1.1; board-only scopes remain out of scope for this site-scoped resource.
- Audit metadata stores oneliner body and author handle so later TUI log rendering can work without inventing reports or sanctions.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Test Bug] Fixed invalid pin assertion in moderation audit RED test**
- **Found during:** Task 1 RED verification
- **Issue:** The initial test used an invalid pinned field expression and could not compile.
- **Fix:** Bound the listed moderator id before comparing it to the expected id.
- **Files modified:** `test/foglet_bbs/moderation/moderation_test.exs`
- **Verification:** `mix test test/foglet_bbs/moderation/moderation_test.exs`
- **Committed in:** `0263538`

**2. [Rule 1 - Test Bug] Fixed oneliner hide fixtures to respect existing latest-visible author rule**
- **Found during:** Task 2 GREEN verification
- **Issue:** New tests reused the same author and tripped the existing `:same_user_latest_visible` guard before hide behavior ran.
- **Fix:** Created a fresh author for each row in those test loops.
- **Files modified:** `test/foglet_bbs/oneliners/oneliners_test.exs`
- **Verification:** `mix test test/foglet_bbs/oneliners/oneliners_test.exs test/foglet_bbs/moderation/moderation_test.exs`
- **Committed in:** `30091b8`

---

**Total deviations:** 2 auto-fixed test issues.
**Impact on plan:** No scope change. Fixes were required for valid TDD coverage.

## Issues Encountered

- `mix precommit` initially reported alias ordering in Task 2 files; fixed and amended into `30091b8`.

## Known Stubs

None.

## Threat Flags

None - new persistence and authorization surfaces were covered by the plan threat model.

## User Setup Required

None - no external service configuration required.

## Verification

- `mix test test/foglet_bbs/moderation/moderation_test.exs` - passed
- `mix test test/foglet_bbs/oneliners/oneliners_test.exs test/foglet_bbs/moderation/moderation_test.exs` - passed
- `mix precommit` - passed

## Next Phase Readiness

Plan 08-02 can consume `Foglet.Moderation.list_actions_for_scopes/2` for the Moderation LOG tab. Plan 08-03 can call `Foglet.Oneliners.hide_entry/3` from the main-menu hide modal.

## Self-Check: PASSED

- Created files exist.
- Task commits are present in git history.
- SUMMARY.md is committed separately after task commits.

---
*Phase: 08-moderation-workspace-population-and-scope-aware-operations*
*Completed: 2026-04-24*
