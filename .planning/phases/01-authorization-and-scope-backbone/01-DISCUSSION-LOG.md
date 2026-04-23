# Phase 1: Authorization and Scope Backbone - Discussion Log (Assumptions Mode)

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in `01-CONTEXT.md` — this log preserves the analysis and the
> alternatives that were surfaced but not chosen.

**Date:** 2026-04-23
**Phase:** 01-authorization-and-scope-backbone
**Mode:** assumptions
**Areas analyzed:** Policy module shape, actor, action, scope, return contract,
enforcement surface, v1.1 guard scope, data-visibility seam, guest/suspended handling,
test strategy (10 areas).

---

## Assumptions Presented

### 1. Policy Module Shape
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| `Foglet.Authorization` at `lib/foglet_bbs/authorization.ex`; public API = `authorize/3` + `can?/3`; no per-action predicates | Likely | Matches `Foglet.Accounts`/`Foglet.Boards`/`Foglet.Config` context shape; no authz lib in `mix.exs`; ShellVisibility already splits visibility from authz |

**Alternative considered:** Per-action predicates (`can_lock_thread?/2`). Rejected — forces
every callsite to know the name mapping; central `authorize/3` keeps dispatch in one
table.

### 2. Actor Representation
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Actor is `Foglet.Accounts.User.t() \| nil`; no separate `Actor` struct | Confident | `TUI.App.current_user` already carries `User.t() \| nil`; `Sessions.Session.role` can drift from live `User.role` after role change |

**Alternative considered:** `%{user_id:, role:}` map matching `Session` state. Rejected —
loses type safety and reintroduces drift risk.

### 3. Action Representation
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Flat atoms in a central allowlist; unknown action → `{:error, :forbidden}` + `Logger.warning` (safe default, not raise) | Likely | Codebase idiom for enumerated values is flat atoms (`@valid_roles`, `@valid_statuses`, `Domain.@supported_keys`); `InvitesSurface.visible?/2` already has a safe-default catch-all |

**Alternatives considered:** Namespaced atoms (`:"threads.lock"`) and grouped tuples
(`{:threads, :lock}`). Rejected — same action count with unfamiliar ergonomics.

### 4. Scope Representation
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Tagged tuple `:site \| {:board, Ecto.UUID.t()}`; caller synthesizes scope via `scope_for/1` helpers per domain; policy does not DB-resolve | Confident | ROADMAP locks these two shapes exactly; tagged tuples match existing codebase patterns (`{:via, Registry, ...}`, PubSub tuples); pure-policy mirrors `ShellVisibility.invites_visible?/2` |

**Alternatives considered:** Pass a resource (`authorize(user, :lock_thread, thread)`) with
DB resolution inside the policy — rejected (impure, harder to test). `%Scope{}` struct —
rejected (ceremony for only two cases today).

### 5. Return Contract
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| `:ok \| {:error, :forbidden}`; `can?/3` wraps to boolean; no raises | Confident | `.planning/codebase/CONVENTIONS.md` documents `{:error, :not_found}`, `{:error, :invalid_credentials}` — `:forbidden` extends this; `?`-suffix Credo-enforced; unauthorized is runtime, not programming-error |

**Alternative considered:** `{:error, {:forbidden, action, scope}}` richer payload. Noted
as a future-additive change (useful for Phase 8 audit logging).

### 6. Enforcement Surface
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Domain function is real trust boundary; TUI `can?/3` is advisory; defense-in-depth | Likely | `CONCERNS.md:212-218` flags this exact problem; TUI-only enforcement leaves Mix tasks and future callers bypassed |

**Alternative considered:** TUI-only enforcement. Rejected — `mix foglet.user.promote`,
tests, and future CLIs would silently bypass. Context-only — rejected (UI can't grey out
actions without duplicating predicates).

### 7. v1.1 Guard Scope ⚠️ (the only Unclear item)
| Option | Description | User Chose |
|--------|-------------|------------|
| (a) Guard only v1.1-live actions; pre-define action atoms for Phase 8 | Smaller Phase 1 diff; no speculative signature churn; Phase 8 diff is mechanical | ✓ |
| (b) Defensive backfill — guard every operator action now | Closes the latent risk from CONCERNS.md immediately; ~6 signature changes + test updates added to Phase 1 | |

**User's choice:** Option (a).
**Notes:** User approved all other assumptions and explicitly chose (a) for this area.
The action atoms for deferred functions are still defined in the allowlist now (see
CONTEXT D-12) so Phase 8's diff is "add the guard call" rather than "invent the atoms +
add the guard."

### 8. Data-Visibility vs Action Authorization (MODR-02)
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Add `scopes_for(actor, action) :: [scope]` in Phase 1; returns `[:site]` for mods/sysops in v1.1; no scope-filtered list helpers built yet | Likely | MODR-02 has no visible v1.1 effect (site-scope mods only) but seam must not paint Phase 8 into a corner; mirrors Phase 0 D-07 scaffold-now-activate-later pattern |

**Alternative considered:** Build `Threads.list_for_moderation/2` preemptively. Rejected —
no v1.1 caller, drifts into dead code.

### 9. Guest / Suspended / Deleted Handling
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Policy rejects nil/deleted/suspended/pending at the top, before role dispatch | Likely | `Accounts.authenticate_by_password/2` uses identical `is_nil(user.deleted_at)` pattern; stale session after sysop suspend must not retain operator powers |

**Alternative considered:** Pure role-based matching (no status guard). Rejected — the
stale-session window is small but avoidable; belt-and-suspenders at policy is cheap.

### 10. Test Strategy
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Matrix test at `test/foglet_bbs/authorization_test.exs` + per-context forbidden-path tests; `async: true`, `DataCase` | Confident | `test/foglet_bbs/` mirrors `lib/foglet_bbs/` 1:1 per CONVENTIONS.md; `InvitesSurface.visible?/2`'s four-clause matrix is begging for a table test |

**Alternative considered:** Only matrix test (skip per-context tests). Rejected — misses
regressions where a new context function forgets to call `authorize/3` at all.

---

## Corrections Made

No corrections. The user reviewed the assumptions in file form (see
`01-ASSUMPTIONS-REVIEW.md`) and accepted all 10 areas with option (a) chosen for area 7.

## Follow-up Question Raised by User

**Q:** "A moderator will be able to be assigned moderator to more than one board, yes?"

**A:** Yes. The seam supports this natively today — see CONTEXT D-09 and D-10 for the
invariant. `scopes_for/2` returns a list of scopes (not a single scope), so a moderator on
N boards yields `[{:board, b1}, ..., {:board, bN}]`. The future `board_moderators` table
(v2, MODR-06) will be a many-to-many join (one row per user/board pair), NOT a
single-board column on `users`. The `scopes_for/2` call signature and return shape are
frozen now (D-23) so the v2 implementation swap is invisible to callers.

## External Research

None performed. Project convention (`CLAUDE.md`) prefers stdlib / explicit opt-in to new
deps; no authorization library (Bodyguard, Canada, Canary) is installed, and none of the
design constraints required one.
