# Phase 14: Launch Hygiene and Operator Notes - Research

**Researched:** 2026-04-24
**Domain:** SSH-first launch-surface audit, runtime config accountability, TUI copy, operator documentation, ExUnit coverage
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

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

### Claude's Discretion
- Exact format for the config accountability artifact or test structure, provided every schematized key has an explicit visibility classification and reason.
- Exact README organization and wording, provided it is practical for pre-alpha operators and does not imply unsupported workflows.
- Exact copy-audit search terms and test grouping, provided terminal-visible false claims are covered and fixed.
- Exact pruning candidates, provided each removal or rewrite is justified and behavior-rich coverage remains.

### Deferred Ideas (OUT OF SCOPE)
- Major incomplete Phase 9-13 capabilities discovered during the audit are blockers for their owning phase, not Phase 14 scope.
- End-user browser workflows, webhook notifications, email digests, outbound delivery logs/retry queues, and full case-management moderation remain out of scope for v1.2.
- A nested `docs/SYSOP.md` or broader docs overhaul can happen later; this phase requires root `README.md`.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| HYGN-01 | Every currently visible Sysop configuration option either changes real runtime behavior or renders as disabled/unavailable with honest copy. | Use `Foglet.Config.Schema.entries/0`, `SiteForm.site_keys/0`, `LimitsForm.limits_keys/0`, form render tests, and behavior-link tests. [VERIFIED: .planning/REQUIREMENTS.md, lib/foglet_bbs/config/schema.ex, lib/foglet_bbs/tui/screens/sysop/site_form.ex, lib/foglet_bbs/tui/screens/sysop/limits_form.ex] |
| HYGN-02 | Pre-alpha blocker flows have focused tests for happy path, forbidden path, and user-facing error/copy behavior. | Use existing ExUnit structure under mirrored source paths and add requirement-traceable tests for delivery, user status, posting policy, keys, subscriptions, Sysop config, and copy. [VERIFIED: .planning/REQUIREMENTS.md, .planning/codebase/TESTING.md, test/] |
| HYGN-03 | Pre-alpha docs or operator notes describe how to run Foglet in SMTP mode and no-email mode. | Rewrite root `README.md` as the required operator guide and include SMTP/no-email mode, SSH-first operation, break-glass tasks, caveats, and nested-doc status. [VERIFIED: .planning/phases/14-launch-hygiene-and-operator-notes/14-SPEC.md, .planning/phases/14-launch-hygiene-and-operator-notes/14-CONTEXT.md, README.md] |
</phase_requirements>

## Summary

Phase 14 should be planned as an evidence-producing audit pass with narrowly scoped repairs. [VERIFIED: .planning/phases/14-launch-hygiene-and-operator-notes/14-CONTEXT.md] The planner should not create tasks that implement missing Phase 9-13 core features; it should create tasks that enumerate the final visible surfaces, prove whether each surface is honest, and either fix small launch-facing mismatches or record upstream blockers. [VERIFIED: .planning/phases/14-launch-hygiene-and-operator-notes/14-CONTEXT.md]

The established architecture is already local and should not change: runtime config is owned by `Foglet.Config` and `Foglet.Config.Schema`, terminal behavior is owned by TUI screens/widgets, durable behavior belongs in `Foglet.*` contexts, and Phoenix remains infrastructure. [VERIFIED: CLAUDE.md, .planning/codebase/ARCHITECTURE.md, lib/foglet_bbs/config.ex] The highest-value Phase 14 artifact is a config/copy/test audit that can be verified by source enumeration plus focused ExUnit tests. [VERIFIED: .planning/phases/14-launch-hygiene-and-operator-notes/14-SPEC.md, test/foglet_bbs/tui/screens/sysop_test.exs]

**Primary recommendation:** Use a three-lane plan: config accountability, launch-copy/README honesty, and test coverage/pruning, with a blocker log for any major missing upstream capability. [VERIFIED: .planning/phases/14-launch-hygiene-and-operator-notes/14-CONTEXT.md]

## Project Constraints (from CLAUDE.md)

- Foglet is SSH-first and the primary product experience is the SSH terminal UI; do not add end-user browser workflows unless architecture docs are updated. [VERIFIED: CLAUDE.md]
- Use `rtk` as the shell command prefix in this repo. [VERIFIED: CLAUDE.md]
- Read `docs/DATA_MODEL.md` before touching schemas, migrations, associations, or persistence invariants. [VERIFIED: CLAUDE.md]
- Before TUI/Raxol work, read `docs/raxol/getting-started/WIDGET_GALLERY.md`; before widget work, also read `lib/foglet_bbs/tui/widgets/README.md`. [VERIFIED: CLAUDE.md]
- Keep domain workflows in `Foglet.*` contexts, not Phoenix controllers, SSH callbacks, or TUI render functions. [VERIFIED: CLAUDE.md]
- Postgres is authoritative for durable state; ETS and processes are ephemeral and reconstructable. [VERIFIED: CLAUDE.md]
- Runtime config uses `Foglet.Config` over an ETS cache and the `configuration` table; add typed accessors for schematized keys and do not scatter string-key reads. [VERIFIED: CLAUDE.md]
- Context mutations must use authorization checks; hidden or disabled UI is not authorization. [VERIFIED: CLAUDE.md]
- TUI render functions should be pure over already-loaded state, route colors through `Foglet.TUI.Theme`, and pass theme explicitly. [VERIFIED: CLAUDE.md]
- Use `start_supervised!/1` for test processes and avoid `Process.sleep/1` / `Process.alive?/1`; synchronize with monitors, explicit messages, or `:sys.get_state/1`. [VERIFIED: CLAUDE.md]
- Run `rtk mix precommit` when changes are complete. [VERIFIED: CLAUDE.md]

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Sysop config accountability | API / Backend | Browser / Client equivalent: TUI | `Foglet.Config.Schema` and `Foglet.Config.put/3` own schema validation, persistence, cache invalidation, and authorization; TUI forms only render/edit visible keys. [VERIFIED: lib/foglet_bbs/config.ex, lib/foglet_bbs/tui/screens/sysop/site_form.ex] |
| Honest terminal copy | Browser / Client equivalent: TUI | API / Backend | Copy is visible in TUI screens and Mix tasks, but claims must match context behavior. [VERIFIED: lib/foglet_bbs/tui/screens/, lib/mix/tasks/] |
| Operator notes | Documentation | API / Backend | Root `README.md` is the required operator guide; it should describe existing runtime modes and tasks, not create behavior. [VERIFIED: .planning/phases/14-launch-hygiene-and-operator-notes/14-SPEC.md] |
| Test audit | Test suite | API / Backend / TUI | Tests live under mirrored ExUnit paths and should cover context behavior, TUI errors/copy, and Mix task output. [VERIFIED: .planning/codebase/TESTING.md, test/] |
| Unsupported workflow removal | TUI / Documentation | Phoenix Web Layer | Browser admin, webhook notifications, email digests, and full moderation case management are excluded for v1.2; Phoenix should remain infrastructure. [VERIFIED: .planning/REQUIREMENTS.md, CLAUDE.md] |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Elixir / Mix | 1.19.5 observed | Language, build, test runner, Mix tasks | Project is an Elixir OTP app and all phase validation uses `rtk mix ...`. [VERIFIED: .planning/codebase/STACK.md, mix.exs] |
| ExUnit | stdlib with Elixir 1.19.5 | Focused context, TUI, Mix task, and regression tests | Existing test suite is ExUnit and mirrors source paths. [VERIFIED: .planning/codebase/TESTING.md, test/test_helper.exs] |
| Phoenix | 1.8.5 | Endpoint, PubSub, telemetry, LiveDashboard infrastructure | Installed Phoenix layer is infrastructure, not an end-user product surface. [VERIFIED: mix.exs, .planning/codebase/ARCHITECTURE.md] |
| Ecto SQL / Postgrex | Ecto SQL 3.13.5 / Postgrex 0.22.0 | Durable DB access for config and domain behavior | Runtime config is persisted in Postgres and cached via ETS. [VERIFIED: rtk mix deps, lib/foglet_bbs/config.ex] |
| Raxol | 2.4.0 vendored | Terminal UI rendering and widgets | The SSH terminal UI is implemented with Raxol screens/widgets. [VERIFIED: rtk mix deps, docs/raxol/getting-started/WIDGET_GALLERY.md] |
| Bodyguard | 2.4.3 | Authorization policy checks | `Foglet.Config.put/3` uses `Bodyguard.permit/4` for actor-aware config writes. [VERIFIED: rtk mix deps, lib/foglet_bbs/config.ex] |
| Swoosh / gen_smtp | Swoosh 1.25.0 / gen_smtp 1.3.0 | SMTP delivery support | Operator notes must describe SMTP/no-email behavior added by upstream delivery phases. [VERIFIED: rtk mix deps, .planning/REQUIREMENTS.md] |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| StreamData | 1.3.0 | Property tests | Keep only if an audited blocker flow has stateful or combinatorial behavior; do not use for copy snapshots. [VERIFIED: rtk mix deps, .planning/codebase/TESTING.md] |
| Credo | 1.7.18 | Static analysis | Run via `rtk mix precommit`; do not add phase-specific lint tooling. [VERIFIED: rtk mix deps, mix.exs] |
| Sobelow | 0.14.1 | Security static analysis | Run via `rtk mix precommit`; do not add browser workflows to silence launch-copy findings. [VERIFIED: rtk mix deps, mix.exs] |
| Dialyxir | 1.4.7 | Dialyzer integration | Run via `rtk mix precommit` after edits. [VERIFIED: rtk mix deps, mix.exs] |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| ExUnit focused tests | Snapshot/golden terminal dumps | Avoid broad snapshots; they are brittle and weaker at proving behavior. [VERIFIED: .planning/phases/14-launch-hygiene-and-operator-notes/14-CONTEXT.md] |
| Root README operator guide | Nested `docs/SYSOP.md` | Root README is locked as the required destination for this phase. [VERIFIED: .planning/phases/14-launch-hygiene-and-operator-notes/14-CONTEXT.md] |
| Existing config schema/forms | New admin configuration framework | Existing schema/form/context pattern is already the authoritative boundary. [VERIFIED: CLAUDE.md, lib/foglet_bbs/config/schema.ex] |

**Installation:**
```bash
rtk mix deps.get
```

**Version verification:** Package versions above were verified with `rtk mix deps`; the command succeeded and showed locked versions. [VERIFIED: rtk mix deps]

## Architecture Patterns

### System Architecture Diagram

```text
Phase 9-13 final behavior
        |
        v
Enumerate launch-visible surfaces
        |
        +--> Config keys: Config.Schema.entries/0
        |        |
        |        v
        |   Compare with SiteForm/LimitsForm visible keys
        |        |
        |        +--> visible -> prove Config.put/3 persists and affects behavior
        |        +--> conditional -> prove render condition and reason
        |        +--> hidden/non-pre-alpha -> document reason and ensure not rendered
        |
        +--> TUI/Mix copy
        |        |
        |        v
        |   Search forbidden launch claims
        |        |
        |        +--> false claim -> narrow copy fix + focused test
        |        +--> true claim -> behavior-linked test or audit evidence
        |
        +--> README.md
        |        |
        |        v
        |   Replace target-state copy with operator guide
        |
        v
Requirement traceability matrix
        |
        v
rtk mix test targeted files -> rtk mix precommit
```

### Recommended Project Structure

```text
lib/
├── foglet_bbs/config/               # config schema specs and typed runtime accessors
├── foglet_bbs/tui/screens/sysop/    # SITE/LIMITS/SYSTEM/USERS launch-visible controls
├── foglet_bbs/tui/screens/          # terminal-visible copy audit targets
└── mix/tasks/                       # break-glass operator task copy and behavior
test/
├── foglet_bbs/config/               # schema/default/accountability tests
├── foglet_bbs/tui/screens/          # screen copy and interaction tests
└── mix/tasks/                       # operator task behavior and output tests
README.md                            # canonical pre-alpha operator guide
```

### Pattern 1: Config Visibility Ledger

**What:** Build an explicit ledger from `Foglet.Config.Schema.entries/0` to visibility status: visible, conditionally visible, intentionally hidden, or non-pre-alpha. [VERIFIED: .planning/phases/14-launch-hygiene-and-operator-notes/14-CONTEXT.md]

**When to use:** Use for HYGN-01 and HYGN-02 planning before touching form code. [VERIFIED: .planning/REQUIREMENTS.md]

**Example:**
```elixir
# Source: local codebase pattern in test/foglet_bbs/tui/screens/sysop_test.exs
all_keys = MapSet.new(Enum.map(Foglet.Config.Schema.entries(), & &1.key))
site = MapSet.new(Foglet.TUI.Screens.Sysop.SiteForm.site_keys())
limits = MapSet.new(Foglet.TUI.Screens.Sysop.LimitsForm.limits_keys())

assert MapSet.disjoint?(site, limits)
assert MapSet.subset?(MapSet.union(site, limits), all_keys)
```

### Pattern 2: Behavior-Linked Copy Tests

**What:** Assert copy against a real screen or task state that corresponds to behavior, not a static string inventory. [VERIFIED: .planning/phases/14-launch-hygiene-and-operator-notes/14-CONTEXT.md, test/foglet_bbs/tui/screens/sysop_test.exs]

**When to use:** Use for delivery/no-email, pending/suspended login outcomes, board subscription empty states, posting forbidden errors, and Sysop unavailable states. [VERIFIED: .planning/REQUIREMENTS.md]

**Example:**
```elixir
# Source: local render-helper pattern in test/foglet_bbs/tui/screens/sysop_test.exs
flat =
  state
  |> put_in([:screen_state, :sysop], Sysop.init_screen_state())
  |> Sysop.render()
  |> collect_text_values()
  |> Enum.join("\n")

refute String.contains?(flat, "webhook")
refute String.contains?(flat, "email digest")
```

### Pattern 3: Blocker Log for Missing Upstream Features

**What:** If a Phase 9-13 core behavior is absent, record it as a blocker for that phase instead of implementing it in Phase 14. [VERIFIED: .planning/phases/14-launch-hygiene-and-operator-notes/14-CONTEXT.md]

**When to use:** Use when the audit finds missing SMTP delivery, approval status mutation, posting enforcement, SSH key management, or board subscription core behavior. [VERIFIED: .planning/REQUIREMENTS.md]

**Example:**
```markdown
| Upstream Phase | Requirement | Missing Evidence | Phase 14 Action |
|----------------|-------------|------------------|-----------------|
| Phase 13 | SUBS-02 | No terminal subscription action found | Blocker; do not implement in Phase 14 |
```

### Anti-Patterns to Avoid

- **Browser admin drift:** Do not add controllers, LiveViews, or browser reset/admin flows to make README/copy claims true. [VERIFIED: CLAUDE.md, .planning/REQUIREMENTS.md]
- **UI as enforcement:** Do not rely on hidden/disabled controls for authorization; context mutations still need policy checks. [VERIFIED: CLAUDE.md, lib/foglet_bbs/config.ex]
- **Config string scatter:** Do not read `"delivery_mode"` or other keys ad hoc across screens; use typed accessors or existing context APIs. [VERIFIED: CLAUDE.md, lib/foglet_bbs/config.ex]
- **Broad snapshot copy tests:** Do not freeze whole terminal screens; assert forbidden/required phrases in behavior-specific states. [VERIFIED: .planning/phases/14-launch-hygiene-and-operator-notes/14-CONTEXT.md]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Runtime config schema | New parser/registry/audit DSL | `Foglet.Config.Schema.entries/0`, `fetch_spec/1`, typed `Foglet.Config` accessors | Existing schema is the local source of truth for keys, defaults, types, enum/range constraints. [VERIFIED: lib/foglet_bbs/config/schema.ex] |
| Config authorization | Per-screen role checks as enforcement | `Foglet.Config.put/3` with `Bodyguard.permit/4` | Context/API layer owns actor-aware writes; UI visibility is advisory. [VERIFIED: lib/foglet_bbs/config.ex, CLAUDE.md] |
| TUI widgets for disabled copy | New rendering primitives | Existing Raxol `text`, `column`, widget theme patterns, and `Foglet.TUI.Theme` | Existing widgets already define disabled/toggle patterns and theme routing. [VERIFIED: docs/raxol/getting-started/WIDGET_GALLERY.md, lib/foglet_bbs/tui/widgets/README.md] |
| SMTP/no-email operator behavior | Custom mail transport or queue | Existing Swoosh/gen_smtp delivery stack and upstream `Accounts` delivery APIs | Phase 14 documents/audits delivery modes; it does not invent delivery infrastructure. [VERIFIED: mix.exs, .planning/REQUIREMENTS.md] |
| Test runner | Shell wrappers or custom audit runner | ExUnit targeted files and `rtk mix precommit` | Project already standardizes ExUnit and Mix aliases. [VERIFIED: mix.exs, .planning/codebase/TESTING.md] |

**Key insight:** The hard part is traceability, not new machinery; the planner should create auditable ledgers and behavior-linked tests, then make only small repairs. [VERIFIED: .planning/phases/14-launch-hygiene-and-operator-notes/14-SPEC.md]

## Common Pitfalls

### Pitfall 1: Treating Schema Partition Coverage as Behavior Proof
**What goes wrong:** Tests prove every schema key appears in SITE or LIMITS, but not that visible controls affect runtime behavior. [VERIFIED: test/foglet_bbs/tui/screens/sysop_test.exs, .planning/phases/14-launch-hygiene-and-operator-notes/14-CONTEXT.md]
**Why it happens:** Static list comparisons are easy and already exist. [VERIFIED: test/foglet_bbs/tui/screens/sysop_test.exs]
**How to avoid:** For each visible key, document the behavior it affects and add at least one behavior or form submission test. [VERIFIED: .planning/phases/14-launch-hygiene-and-operator-notes/14-SPEC.md]
**Warning signs:** A test only mentions `MapSet.union(site, limits)` and never exercises the consumer of the config value. [VERIFIED: test/foglet_bbs/tui/screens/sysop_test.exs]

### Pitfall 2: Fixing False Claims by Adding Out-of-Scope Features
**What goes wrong:** Browser admin, webhook notification, digest, or case-management copy is made true by adding product scope. [VERIFIED: .planning/REQUIREMENTS.md]
**Why it happens:** Target-state README and web page copy already contain future-facing claims. [VERIFIED: README.md, lib/foglet_bbs_web/controllers/page_html/home.html.heex]
**How to avoid:** Remove or qualify the claim in terminal surfaces and README; do not expand the product surface. [VERIFIED: .planning/phases/14-launch-hygiene-and-operator-notes/14-CONTEXT.md]
**Warning signs:** New files under `lib/foglet_bbs_web` or references to `/users/reset_password`, browser admin, webhook, digest, retry queues, or moderation cases. [VERIFIED: .planning/REQUIREMENTS.md]

### Pitfall 3: Auditing README but Ignoring Terminal/Mix Copy
**What goes wrong:** README becomes honest, but users still see false promises in SSH screens or operators see false task output. [VERIFIED: .planning/phases/14-launch-hygiene-and-operator-notes/14-SPEC.md]
**Why it happens:** Copy is distributed across screens, tasks, and tests. [VERIFIED: rg scan over lib/foglet_bbs/tui/screens and lib/mix/tasks]
**How to avoid:** Search TUI screens, Mix tasks, README, and relevant tests with the same forbidden-claim vocabulary. [VERIFIED: .planning/phases/14-launch-hygiene-and-operator-notes/14-CONTEXT.md]
**Warning signs:** `README.md` changes with no accompanying copy audit evidence or tests. [VERIFIED: .planning/phases/14-launch-hygiene-and-operator-notes/14-SPEC.md]

### Pitfall 4: Pruning Tests by Count Instead of Defect Detection
**What goes wrong:** Static tests are removed without replacement or behavior-rich tests are removed because they look verbose. [VERIFIED: .planning/phases/14-launch-hygiene-and-operator-notes/14-SPEC.md]
**Why it happens:** Phase 14 explicitly permits pruning, but only with justification. [VERIFIED: .planning/phases/14-launch-hygiene-and-operator-notes/14-CONTEXT.md]
**How to avoid:** For every removal/rewrite, state what deeper test covers and what realistic regression it catches. [VERIFIED: .planning/phases/14-launch-hygiene-and-operator-notes/14-SPEC.md]
**Warning signs:** Deleted tests without a replacement assertion, requirement reference, or overlap note. [VERIFIED: .planning/phases/14-launch-hygiene-and-operator-notes/14-SPEC.md]

## Code Examples

### Config Write Path

```elixir
# Source: lib/foglet_bbs/config.ex
with :ok <- Bodyguard.permit(Foglet.Authorization, :edit_config, actor, :site) do
  case Schema.validate(key, value) do
    :ok -> {:ok, do_put!(key, value, actor && actor.id)}
    {:error, {:unknown_key, ^key}} -> {:error, :unknown_key}
    {:error, %{reason: _reason}} -> {:error, :invalid_value}
  end
end
```

### Conditional Config Visibility

```elixir
# Source: lib/foglet_bbs/tui/screens/sysop/site_form.ex
def visible_keys(%__MODULE__{drafts: drafts}) do
  generators = Map.get(drafts, "invite_code_generators")

  Enum.reject(@site_keys, fn
    "invite_generation_per_user_limit" -> generators != "any_user"
    _ -> false
  end)
end
```

### TUI Render Audit Pattern

```elixir
# Source: test/foglet_bbs/tui/screens/sysop_test.exs
flat = Sysop.render(state) |> collect_text_values() |> Enum.join("\n")

assert String.contains?(flat, "delivery_mode")
refute String.contains?(flat, "webhook notification")
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Target-state README with future features | Root README as practical pre-alpha operator guide | Phase 14 locked decision, 2026-04-24 | Plans should replace unsupported claims with current operating notes. [VERIFIED: .planning/phases/14-launch-hygiene-and-operator-notes/14-CONTEXT.md] |
| Static config partition tests only | Config ledger plus behavior/copy proof | Phase 14 locked decision, 2026-04-24 | Plans should map every visible key to real behavior or unavailable copy. [VERIFIED: .planning/phases/14-launch-hygiene-and-operator-notes/14-SPEC.md] |
| Browser/Phoenix product-surface assumption | SSH-first terminal product, Phoenix infrastructure | Project constraint | Plans must not add web admin/end-user workflows. [VERIFIED: CLAUDE.md] |

**Deprecated/outdated:**
- Root README claims for opt-in email digests are not valid launch-surface claims for v1.2 and must be removed or marked future/out-of-scope. [VERIFIED: README.md, .planning/REQUIREMENTS.md]
- Terminal copy telling users to ask a sysop for subscriptions is incompatible with Phase 13's target board-directory action after that phase lands. [VERIFIED: .planning/phases/13-board-subscription-management/13-SPEC.md, lib/foglet_bbs/tui/screens/board_list.ex, lib/foglet_bbs/tui/screens/new_thread.ex]

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | None; all recommendations are based on local phase artifacts, local source, local tests, or observed dependency output. | All | Low. |

## Open Questions

1. **Have Phases 9-13 all landed before Phase 14 execution?**
   - What we know: State currently reports v1.2 still executing and Phase 09 as current focus. [VERIFIED: .planning/STATE.md]
   - What's unclear: The code scanned during research may not yet contain final Phase 9-13 behavior. [VERIFIED: .planning/STATE.md]
   - Recommendation: Plan Phase 14 tasks to start with a blocker audit and stop/report if an owning upstream phase is incomplete. [VERIFIED: .planning/phases/14-launch-hygiene-and-operator-notes/14-CONTEXT.md]

2. **Where should the config accountability ledger live?**
   - What we know: Exact format is discretionary. [VERIFIED: .planning/phases/14-launch-hygiene-and-operator-notes/14-CONTEXT.md]
   - What's unclear: The user has not required a specific artifact path. [VERIFIED: .planning/phases/14-launch-hygiene-and-operator-notes/14-CONTEXT.md]
   - Recommendation: Put the durable ledger in `README.md` only if operator-facing; otherwise encode the ledger in tests plus a short section in the phase implementation notes. [ASSUMED]

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Elixir / Mix | Tests, tasks, precommit | yes | Elixir 1.19.5 observed in Mix error output and codebase stack | None needed. [VERIFIED: .planning/codebase/STACK.md, rtk mix test --list-tags output] |
| PostgreSQL test DB | `rtk mix test` aliases | assumed available | not probed | Planner should rely on existing `rtk mix test` alias; if DB fails, use the project setup path. [VERIFIED: mix.exs] |
| `rtk` wrapper | All repo commands | yes | not versioned | Use raw `mix` only if `rtk` itself is unavailable. [VERIFIED: successful rtk mix deps] |
| ExUnit | Validation | yes | stdlib | None needed. [VERIFIED: test/test_helper.exs] |

**Missing dependencies with no fallback:**
- None found during research. [VERIFIED: successful rtk mix deps]

**Missing dependencies with fallback:**
- `rtk mix test --list-tags` is not supported by this Mix version; use explicit targeted test commands instead. [VERIFIED: rtk mix test --list-tags output]

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | ExUnit with project Mix aliases. [VERIFIED: .planning/codebase/TESTING.md, mix.exs] |
| Config file | `test/test_helper.exs`; `ExUnit.start(exclude: [:pending])`. [VERIFIED: test/test_helper.exs] |
| Quick run command | `rtk mix test test/foglet_bbs/tui/screens/sysop_test.exs test/foglet_bbs/config test/mix/tasks` [VERIFIED: local test layout] |
| Full suite command | `rtk mix test` [VERIFIED: mix.exs] |

### Phase Requirements -> Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| HYGN-01 | Sysop-visible config controls work or honestly render unavailable | screen/unit | `rtk mix test test/foglet_bbs/tui/screens/sysop_test.exs test/foglet_bbs/tui/screens/sysop/site_form_test.exs test/foglet_bbs/config` | yes [VERIFIED: test files] |
| HYGN-02 | Launch-blocker flows have happy, forbidden, and user-facing copy/error coverage | context/screen/task | `rtk mix test test/foglet_bbs/accounts test/foglet_bbs/boards test/foglet_bbs/posts test/foglet_bbs/threads test/foglet_bbs/tui/screens test/mix/tasks` | partial; final gaps depend on Phases 9-13 landing. [VERIFIED: test files, .planning/STATE.md] |
| HYGN-03 | README documents SMTP mode and no-email mode | doc/audit | `rg -n "SMTP|no-email|no_email|delivery_mode|foglet.user" README.md` | README exists; content currently target-state. [VERIFIED: README.md] |

### Sampling Rate

- **Per task commit:** Run the narrow command for the touched area plus `rtk mix format --check-formatted` when formatting-only confidence is needed. [VERIFIED: mix.exs]
- **Per wave merge:** Run `rtk mix test` for behavior changes that span contexts/screens/tasks. [VERIFIED: mix.exs]
- **Phase gate:** Run `rtk mix precommit` before handoff. [VERIFIED: CLAUDE.md, mix.exs]

### Wave 0 Gaps

- [ ] Add or update a config accountability test/ledger that classifies every `Config.Schema.entries/0` key with a reason, not only partition membership. [VERIFIED: .planning/phases/14-launch-hygiene-and-operator-notes/14-CONTEXT.md]
- [ ] Add a launch-copy audit test or documented evidence for forbidden claims across TUI screens, Mix tasks, and README. [VERIFIED: .planning/phases/14-launch-hygiene-and-operator-notes/14-SPEC.md]
- [ ] Add README assertions or review checklist entries for SMTP mode, no-email mode, break-glass tasks, SSH-first operation, launch caveats, and nested-doc status. [VERIFIED: .planning/phases/14-launch-hygiene-and-operator-notes/14-SPEC.md]

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | yes | Do not alter auth in Phase 14 except copy/tests; existing Accounts/SSH key flows own auth behavior. [VERIFIED: .planning/REQUIREMENTS.md, .planning/codebase/ARCHITECTURE.md] |
| V3 Session Management | yes | Do not bypass session layer; Phase 14 is copy/config/tests only. [VERIFIED: .planning/codebase/ARCHITECTURE.md] |
| V4 Access Control | yes | Context/API layer authorization via Bodyguard; disabled UI is not enforcement. [VERIFIED: CLAUDE.md, lib/foglet_bbs/config.ex] |
| V5 Input Validation | yes | `Foglet.Config.Schema.validate/2` for config values and Ecto changesets for domain data. [VERIFIED: lib/foglet_bbs/config/schema.ex, docs/DATA_MODEL.md] |
| V6 Cryptography | no new crypto | Do not hand-roll tokens, passwords, or SMTP secrets in this phase. [VERIFIED: .planning/REQUIREMENTS.md] |

### Known Threat Patterns for Foglet

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Non-sysop config mutation through TUI state manipulation | Elevation of privilege | `Foglet.Config.put/3` with `Bodyguard.permit/4`; tests should assert forbidden path. [VERIFIED: lib/foglet_bbs/config.ex, test/foglet_bbs/tui/screens/sysop_test.exs] |
| False security/operational claims in README or terminal copy | Spoofing / Repudiation | Behavior-linked copy tests and operator notes that distinguish SMTP vs no-email mode. [VERIFIED: .planning/phases/14-launch-hygiene-and-operator-notes/14-SPEC.md] |
| Secret leakage through DB-backed runtime config | Information disclosure | Keep secrets in environment/runtime config, not DB-backed config. [VERIFIED: CLAUDE.md] |

## Sources

### Primary (HIGH confidence)
- `CLAUDE.md` - project constraints, SSH-first boundary, config/TUI/testing rules.
- `.planning/phases/14-launch-hygiene-and-operator-notes/14-CONTEXT.md` - locked implementation decisions.
- `.planning/phases/14-launch-hygiene-and-operator-notes/14-SPEC.md` - requirements, acceptance criteria, scope boundaries.
- `.planning/REQUIREMENTS.md` - HYGN-01 through HYGN-03 and v1.2 out-of-scope list.
- `lib/foglet_bbs/config/schema.ex`, `lib/foglet_bbs/config.ex` - runtime config source of truth and write path.
- `lib/foglet_bbs/tui/screens/sysop/site_form.ex`, `lib/foglet_bbs/tui/screens/sysop/limits_form.ex` - Sysop config rendering/edit patterns.
- `test/foglet_bbs/tui/screens/sysop_test.exs`, `.planning/codebase/TESTING.md` - existing ExUnit patterns.
- `docs/DATA_MODEL.md`, `docs/raxol/getting-started/WIDGET_GALLERY.md`, `lib/foglet_bbs/tui/widgets/README.md` - data/TUI/widget constraints.

### Secondary (MEDIUM confidence)
- `rtk mix deps` output - locked dependency versions observed locally.
- `rg` scan over `lib`, `test`, `README.md`, and relevant phase artifacts - launch-copy hotspots and forbidden-claim search space.
- `.planning/codebase/ARCHITECTURE.md`, `.planning/codebase/STACK.md` - generated codebase maps from 2026-04-22.

### Tertiary (LOW confidence)
- None. External web/library research was not needed because this phase is codebase-native and decisions are locked to existing stack. [VERIFIED: .planning/phases/14-launch-hygiene-and-operator-notes/14-CONTEXT.md]

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - verified from `mix.exs`, `rtk mix deps`, and codebase stack map.
- Architecture: HIGH - verified from CLAUDE.md, codebase architecture, and local source.
- Pitfalls: HIGH - derived from locked phase decisions plus current README/TUI copy scan.
- Validation: MEDIUM - test infrastructure is verified, but final gap list depends on completion of Phases 9-13.

**Research date:** 2026-04-24
**Valid until:** 2026-05-01, or sooner if Phases 9-13 substantially change config keys, TUI surfaces, or Mix tasks.
